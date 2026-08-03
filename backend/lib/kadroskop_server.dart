import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<HttpServer> startKadroskopServer({
  required InternetAddress address,
  required int port,
  String? tmdbToken,
}) {
  final catalog = CatalogGateway(http.Client(), tmdbToken: tmdbToken?.trim());
  final router = Router()
    ..get('/v1/health', (Request request) {
      return _json({
        'ok': true,
        'tmdbConfigured': catalog.tmdbConfigured,
        'anilistConfigured': true,
      });
    })
    ..get('/v1/search', (Request request) async {
      final query = request.url.queryParameters['q']?.trim() ?? '';
      final kind = request.url.queryParameters['kind'];
      if (query.length < 2) {
        return _json({
          'error': 'Параметр q должен содержать минимум 2 символа.',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        final results = await catalog.search(query, kind: kind);
        return _json({'results': results, 'count': results.length});
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    })
    ..get('/v1/media/<source>/<id>', (
      Request request,
      String source,
      String id,
    ) async {
      try {
        return _json(await catalog.details(source, id));
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addMiddleware(_errorBoundary())
      .addHandler(router.call);
  return shelf_io.serve(handler, address, port);
}

class CatalogGateway {
  CatalogGateway(this._client, {String? tmdbToken})
    : _tmdbToken = tmdbToken == null || tmdbToken.isEmpty ? null : tmdbToken;

  final http.Client _client;
  final String? _tmdbToken;
  final _cache = _MemoryCache();

  bool get tmdbConfigured => _tmdbToken != null;

  Future<List<Map<String, Object?>>> search(
    String query, {
    String? kind,
  }) async {
    final cacheKey = 'search:$query:$kind';
    final cached = _cache.read<List<Map<String, Object?>>>(cacheKey);
    if (cached != null) return cached;

    final includeMovies =
        kind == null ||
        const ['movie', 'cartoon', 'documentary'].contains(kind);
    final includeTv =
        kind == null || const ['series', 'animatedSeries'].contains(kind);
    final includeAnime = kind == null || kind == 'anime';
    final tasks = <Future<List<Map<String, Object?>>>>[
      if (tmdbConfigured && includeMovies) _searchTmdb(query, 'movie'),
      if (tmdbConfigured && includeTv) _searchTmdb(query, 'tv'),
      if (includeAnime) _searchAniList(query),
    ];
    final groups = await Future.wait(tasks);
    final results =
        groups.expand((group) => group).where((item) {
          return kind == null || item['kind'] == kind;
        }).toList()..sort(
          (a, b) => ((b['popularity'] as num?) ?? 0).compareTo(
            (a['popularity'] as num?) ?? 0,
          ),
        );

    final deduplicated = <String, Map<String, Object?>>{};
    for (final item in results) {
      final key = '${(item['title'] as String).toLowerCase()}:${item['year']}';
      deduplicated.putIfAbsent(key, () => item);
    }
    final value = deduplicated.values.take(40).toList();
    _cache.write(cacheKey, value);
    return value;
  }

  Future<Map<String, Object?>> details(String source, String id) async {
    final cacheKey = 'details:$source:$id';
    final cached = _cache.read<Map<String, Object?>>(cacheKey);
    if (cached != null) return cached;
    final result = switch (source) {
      'tmdb_movie' => await _tmdbDetails(id, isTv: false),
      'tmdb_tv' => await _tmdbDetails(id, isTv: true),
      'anilist' => await _aniListDetails(id),
      _ => throw CatalogException('Неизвестный источник: $source', 400),
    };
    _cache.write(cacheKey, result);
    return result;
  }

  Future<List<Map<String, Object?>>> _searchTmdb(
    String query,
    String type,
  ) async {
    final uri = Uri.https('api.themoviedb.org', '/3/search/$type', {
      'query': query,
      'language': 'ru-RU',
      'include_adult': 'false',
      'page': '1',
    });
    final data = await _getTmdb(uri);
    final results = (data['results'] as List<dynamic>? ?? const []);
    return results
        .cast<Map<String, dynamic>>()
        .where((row) => row['id'] != null)
        .map((row) => _mapTmdb(row, type))
        .toList();
  }

  Future<Map<String, Object?>> _tmdbDetails(
    String id, {
    required bool isTv,
  }) async {
    if (!tmdbConfigured) {
      throw CatalogException('TMDB_ACCESS_TOKEN не настроен.', 503);
    }
    final type = isTv ? 'tv' : 'movie';
    final uri = Uri.https('api.themoviedb.org', '/3/$type/$id', {
      'language': 'ru-RU',
    });
    final row = await _getTmdb(uri);
    final result = _mapTmdb(row, type);
    final runtimeValues = isTv
        ? (row['episode_run_time'] as List<dynamic>? ?? const [])
        : const [];
    result['runtimeMinutes'] = isTv
        ? (runtimeValues.isEmpty ? 0 : (runtimeValues.first as num).toInt())
        : ((row['runtime'] as num?) ?? 0).toInt();
    result['seasonCount'] = ((row['number_of_seasons'] as num?) ?? 0).toInt();
    result['episodeCount'] = ((row['number_of_episodes'] as num?) ?? 0).toInt();
    result['seasons'] = isTv
        ? (row['seasons'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .where((season) => ((season['season_number'] as num?) ?? 0) > 0)
              .map(
                (season) => {
                  'number': (season['season_number'] as num).toInt(),
                  'episodeCount': ((season['episode_count'] as num?) ?? 0)
                      .toInt(),
                  'name': season['name'] as String?,
                },
              )
              .toList()
        : const [];
    result['genres'] = (row['genres'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((genre) => genre['name'] as String)
        .toList();
    return result;
  }

  Future<Map<String, dynamic>> _getTmdb(Uri uri) async {
    final response = await _client
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $_tmdbToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw CatalogException(
        'TMDB временно недоступен (${response.statusCode}).',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, Object?> _mapTmdb(Map<String, dynamic> row, String type) {
    final isTv = type == 'tv';
    final genreIds = (row['genre_ids'] as List<dynamic>? ?? const [])
        .map((value) => (value as num).toInt())
        .toList();
    final genres = genreIds
        .map((id) => _tmdbGenres[id])
        .whereType<String>()
        .toList();
    final kind = isTv
        ? (genreIds.contains(16) ? 'animatedSeries' : 'series')
        : (genreIds.contains(16)
              ? 'cartoon'
              : genreIds.contains(99)
              ? 'documentary'
              : 'movie');
    final externalId = (row['id'] as num).toInt();
    final date =
        (row[isTv ? 'first_air_date' : 'release_date'] as String?) ?? '';
    final title =
        (row[isTv ? 'name' : 'title'] as String?) ??
        (row[isTv ? 'original_name' : 'original_title'] as String?) ??
        'Без названия';
    final posterPath = row['poster_path'] as String?;
    return {
      'id': (isTv ? 2000000000 : 1000000000) + externalId,
      'source': 'tmdb_$type',
      'externalId': '$externalId',
      'title': title,
      'subtitle':
          (row['original_name'] ?? row['original_title'] ?? '') as String,
      'description': (row['overview'] as String?) ?? '',
      'year': date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0,
      'kind': kind,
      'rating': ((row['vote_average'] as num?) ?? 0).toDouble(),
      'genres': genres,
      'posterUrl': posterPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w500$posterPath',
      'runtimeMinutes': 0,
      'seasonCount': 0,
      'episodeCount': 0,
      'episodeRuntimeMinutes': isTv ? 45 : 0,
      'seasons': const [],
      'popularity': ((row['popularity'] as num?) ?? 0).toDouble(),
    };
  }

  Future<List<Map<String, Object?>>> _searchAniList(String query) async {
    final response = await _postAniList(_aniListSearchQuery, {'search': query});
    final page =
        (response['data'] as Map<String, dynamic>)['Page']
            as Map<String, dynamic>;
    return (page['media'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(_mapAniList)
        .toList();
  }

  Future<Map<String, Object?>> _aniListDetails(String id) async {
    final response = await _postAniList(_aniListDetailsQuery, {
      'id': int.parse(id),
    });
    final row =
        (response['data'] as Map<String, dynamic>)['Media']
            as Map<String, dynamic>;
    return _mapAniList(row);
  }

  Future<Map<String, dynamic>> _postAniList(
    String query,
    Map<String, Object> variables,
  ) async {
    final response = await _client
        .post(
          Uri.parse('https://graphql.anilist.co'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw CatalogException(
        'AniList временно недоступен (${response.statusCode}).',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, Object?> _mapAniList(Map<String, dynamic> row) {
    final title = row['title'] as Map<String, dynamic>? ?? const {};
    final cover = row['coverImage'] as Map<String, dynamic>? ?? const {};
    final startDate = row['startDate'] as Map<String, dynamic>? ?? const {};
    final externalId = (row['id'] as num).toInt();
    final episodes = ((row['episodes'] as num?) ?? 0).toInt();
    final duration = ((row['duration'] as num?) ?? 0).toInt();
    return {
      'id': 3000000000 + externalId,
      'source': 'anilist',
      'externalId': '$externalId',
      'title':
          (title['english'] ?? title['romaji'] ?? title['native']) as String,
      'subtitle': (title['romaji'] ?? title['native'] ?? '') as String,
      'description': _stripHtml((row['description'] as String?) ?? ''),
      'year': ((startDate['year'] as num?) ?? 0).toInt(),
      'kind': 'anime',
      'rating': (((row['averageScore'] as num?) ?? 0) / 10).toDouble(),
      'genres': (row['genres'] as List<dynamic>? ?? const []).cast<String>(),
      'posterUrl': (cover['extraLarge'] ?? cover['large']) as String?,
      'runtimeMinutes': row['format'] == 'MOVIE' ? duration : 0,
      'seasonCount': episodes > 0 ? 1 : 0,
      'episodeCount': episodes,
      'episodeRuntimeMinutes': duration,
      'seasons': episodes > 0
          ? [
              {'number': 1, 'episodeCount': episodes, 'name': 'Сезон 1'},
            ]
          : const [],
      'popularity': ((row['popularity'] as num?) ?? 0).toDouble(),
    };
  }
}

class CatalogException implements Exception {
  CatalogException(this.message, this.statusCode);
  final String message;
  final int statusCode;
}

class _MemoryCache {
  final _values = <String, ({DateTime expiresAt, Object value})>{};

  T? read<T>(String key) {
    final entry = _values[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _values.remove(key);
      return null;
    }
    return entry.value as T;
  }

  void write(String key, Object value) {
    if (_values.length >= 200) _values.remove(_values.keys.first);
    _values[key] = (
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      value: value,
    );
  }
}

Middleware _cors() =>
    (innerHandler) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: {...response.headers, ..._corsHeaders});
    };

Middleware _errorBoundary() =>
    (innerHandler) => (request) async {
      try {
        return await innerHandler(request);
      } on TimeoutException {
        return _json({
          'error': 'Источник каталога не ответил вовремя.',
        }, statusCode: HttpStatus.gatewayTimeout);
      } catch (error, stackTrace) {
        stderr.writeln('$error\n$stackTrace');
        return _json({
          'error': 'Внутренняя ошибка backend.',
        }, statusCode: HttpStatus.internalServerError);
      }
    };

Response _json(Object value, {int statusCode = 200}) => Response(
  statusCode,
  body: jsonEncode(value),
  headers: {
    HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
    ..._corsHeaders,
  },
);

String _stripHtml(String value) => value
    .replaceAll(RegExp('<br\\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&');

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

const _tmdbGenres = <int, String>{
  12: 'Приключения',
  14: 'Фэнтези',
  16: 'Анимация',
  18: 'Драма',
  27: 'Ужасы',
  28: 'Боевик',
  35: 'Комедия',
  36: 'История',
  37: 'Вестерн',
  53: 'Триллер',
  80: 'Криминал',
  99: 'Документальное',
  878: 'Фантастика',
  9648: 'Детектив',
  10749: 'Мелодрама',
  10751: 'Семейный',
  10759: 'Боевик и приключения',
  10762: 'Детский',
  10765: 'Фантастика и фэнтези',
};

const _aniListSearchQuery = r'''
query SearchAnime($search: String!) {
  Page(page: 1, perPage: 20) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      title { romaji english native }
      description(asHtml: false)
      startDate { year }
      format
      episodes
      duration
      averageScore
      popularity
      genres
      coverImage { large extraLarge }
    }
  }
}
''';

const _aniListDetailsQuery = r'''
query AnimeDetails($id: Int!) {
  Media(id: $id, type: ANIME) {
    id
    title { romaji english native }
    description(asHtml: false)
    startDate { year }
    format
    episodes
    duration
    averageScore
    popularity
    genres
    coverImage { large extraLarge }
  }
}
''';
