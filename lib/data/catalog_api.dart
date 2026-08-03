import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import '../models/remember_search.dart';
import 'media_repository.dart';

class CatalogApi implements CatalogSource {
  CatalogApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = Uri.parse(baseUrl ?? _defaultBaseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  String get baseUrl => _baseUrl.toString();

  static const _configuredBaseUrl = String.fromEnvironment('KADROSKOP_API_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:8080/'
        : 'http://127.0.0.1:8080/';
  }

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async {
    return (await searchPage(query, kind: kind)).items;
  }

  @override
  Future<CatalogPage> searchPage(
    String query, {
    MediaKind? kind,
    int page = 1,
  }) async {
    final uri = _baseUrl
        .resolve('/v1/search')
        .replace(
          queryParameters: {
            'q': query.trim(),
            'page': '$page',
            if (kind != null) 'kind': kind.name,
          },
        );
    final data = await _getJson(uri);
    return _catalogPage(data);
  }

  @override
  Future<CatalogPage> popular({MediaKind? kind, int page = 1}) async {
    final uri = _baseUrl
        .resolve('/v1/popular')
        .replace(
          queryParameters: {
            'page': '$page',
            if (kind != null) 'kind': kind.name,
          },
        );
    return _catalogPage(await _getJson(uri));
  }

  CatalogPage _catalogPage(Map<String, dynamic> data) => CatalogPage(
    items: (data['results'] as List<dynamic>? ?? const [])
        .map((row) => MediaItem.fromApi(row as Map<String, dynamic>))
        .toList(),
    page: ((data['page'] as num?) ?? 1).toInt(),
    hasMore: (data['hasMore'] as bool?) ?? false,
    warnings: (data['warnings'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  );

  @override
  Future<RememberSearchResult> rememberSearch(
    RememberSearchFilters filters,
  ) async {
    final data = await _postJson(
      _baseUrl.resolve('/remember/search'),
      filters.toJson(),
    );
    return RememberSearchResult(
      candidates: (data['results'] as List<dynamic>? ?? const [])
          .map(
            (row) => RememberCandidate.fromJson(
              (row as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      warnings: (data['warnings'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      ai: (data['ai'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  Future<Map<String, dynamic>> diagnostics() =>
      _getJson(_baseUrl.resolve('/v1/health'));

  @override
  Future<MediaItem> details(MediaItem item) async {
    final id = item.externalId;
    if (id == null) return item;
    final uri = _baseUrl.resolve('/v1/media/${item.source}/$id');
    return MediaItem.fromApi(await _getJson(uri));
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    return _requestJson(() => _client.get(uri, headers: _jsonHeaders));
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, Object?> body,
  ) async {
    return _requestJson(
      () => _client.post(uri, headers: _jsonHeaders, body: jsonEncode(body)),
    );
  }

  Future<Map<String, dynamic>> _requestJson(
    Future<http.Response> Function() send,
  ) async {
    try {
      final response = await send().timeout(const Duration(seconds: 20));
      final value = jsonDecode(response.body);
      if (value is! Map) {
        throw const FormatException('Expected a JSON object');
      }
      final decoded = value.cast<String, dynamic>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogApiException(
          (decoded['error'] as String?) ?? 'Ошибка каталога',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const CatalogApiException(
        'Backend или внешний каталог не ответил вовремя.',
      );
    } on SocketException {
      throw const CatalogApiException(
        'Backend недоступен. Запустите сервер из папки backend.',
      );
    } on http.ClientException {
      throw const CatalogApiException(
        'Не удалось подключиться к backend. Проверьте адрес сервера.',
      );
    } on FormatException {
      throw const CatalogApiException('Backend вернул некорректный ответ.');
    }
  }
}

const _jsonHeaders = {
  'Accept': 'application/json',
  'Content-Type': 'application/json; charset=utf-8',
};

class CatalogApiException implements Exception {
  const CatalogApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
