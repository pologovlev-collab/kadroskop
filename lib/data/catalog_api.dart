import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import 'media_repository.dart';

class CatalogApi implements CatalogSource {
  CatalogApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = Uri.parse(baseUrl ?? _defaultBaseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  static const _configuredBaseUrl = String.fromEnvironment('KADROSKOP_API_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:8080/'
        : 'http://127.0.0.1:8080/';
  }

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async {
    final uri = _baseUrl
        .resolve('/v1/search')
        .replace(
          queryParameters: {'q': query, if (kind != null) 'kind': kind.name},
        );
    final data = await _getJson(uri);
    return (data['results'] as List<dynamic>? ?? const [])
        .map((row) => MediaItem.fromApi(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<MediaItem> details(MediaItem item) async {
    final id = item.externalId;
    if (id == null) return item;
    final uri = _baseUrl.resolve('/v1/media/${item.source}/$id');
    return MediaItem.fromApi(await _getJson(uri));
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogApiException(
          (decoded['error'] as String?) ?? 'Ошибка каталога',
        );
      }
      return decoded;
    } on SocketException {
      throw const CatalogApiException(
        'Backend недоступен. Запустите сервер из папки backend.',
      );
    } on FormatException {
      throw const CatalogApiException('Backend вернул некорректный ответ.');
    }
  }
}

class CatalogApiException implements Exception {
  const CatalogApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
