import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class CatalogGateway {
  CatalogGateway(
    this._client, {
    String? tmdbToken,
    Duration requestTimeout = const Duration(seconds: 12),
  }) : _tmdbToken = _cleanSecret(tmdbToken),
       _requestTimeout = requestTimeout;

  final http.Client _client;
  final String? _tmdbToken;
  final Duration _requestTimeout;
  final _cache = _MemoryCache();
  final Map<String, ProviderHealth> _health = {
    'tmdb': const ProviderHealth(
      provider: 'tmdb',
      state: ProviderState.unknown,
    ),
    'anilist': const ProviderHealth(
      provider: 'anilist',
      state: ProviderState.unknown,
    ),
  };

  bool get tmdbConfigured => _tmdbToken != null;

  Map<String, Object?> get diagnostics => {
    'tmdb':
        (_health['tmdb'] ??
                const ProviderHealth(
                  provider: 'tmdb',
                  state: ProviderState.unknown,
                ))
            .copyWith(
              state: tmdbConfigured
                  ? _health['tmdb']!.state
                  : ProviderState.notConfigured,
              message: tmdbConfigured
                  ? _health['tmdb']!.message
                  : 'Ключ не настроен',
            )
            .toJson(),
    'anilist': _health['anilist']!.toJson(),
  };

  Future<CatalogSearchPage> search(
    String query, {
    String? kind,
    int page = 1,
  }) async {
    final normalized = _normalizeQuery(query);
    final safePage = _safePage(page);
    final cacheKey = 'search:$normalized:$kind:$safePage';
    final cached = _cache.read<CatalogSearchPage>(cacheKey);
    if (cached != null) return cached;

    final includeMovies =
        kind == null ||
        const ['movie', 'cartoon', 'documentary'].contains(kind);
    final includeTv =
        kind == null || const ['series', 'animatedSeries'].contains(kind);
    final includeAnime = kind == null || kind == 'anime';
    final operations = <_ProviderOperation>[
      if (tmdbConfigured && includeMovies)
        _ProviderOperation(
          'tmdb',
          () => _searchTmdb(normalized, 'movie', page: safePage),
        ),
      if (tmdbConfigured && includeTv)
        _ProviderOperation(
          'tmdb',
          () => _searchTmdb(normalized, 'tv', page: safePage),
        ),
      if (includeAnime)
        _ProviderOperation(
          'anilist',
          () => _searchAniList(normalized, page: safePage),
        ),
    ];

    if (operations.isEmpty) {
      throw CatalogException(
        'Для этого типа нужен TMDB_ACCESS_TOKEN в backend/.env.',
        503,
      );
    }
    final value = await _runOperations(operations, kind: kind, page: safePage);
    _cache.write(cacheKey, value);
    return value;
  }

  Future<CatalogSearchPage> popular({String? kind, int page = 1}) async {
    final safePage = _safePage(page);
    final cacheKey = 'popular:$kind:$safePage';
    final cached = _cache.read<CatalogSearchPage>(cacheKey);
    if (cached != null) return cached;

    final includeMovies =
        kind == null ||
        const ['movie', 'cartoon', 'documentary'].contains(kind);
    final includeTv =
        kind == null || const ['series', 'animatedSeries'].contains(kind);
    final includeAnime = kind == null || kind == 'anime';
    final operations = <_ProviderOperation>[
      if (tmdbConfigured && includeMovies)
        _ProviderOperation('tmdb', () => _popularTmdb('movie', page: safePage)),
      if (tmdbConfigured && includeTv)
        _ProviderOperation('tmdb', () => _popularTmdb('tv', page: safePage)),
      if (includeAnime)
        _ProviderOperation('anilist', () => _popularAniList(page: safePage)),
    ];
    if (operations.isEmpty) {
      throw CatalogException(
        'Для этого типа нужен TMDB_ACCESS_TOKEN в backend/.env.',
        503,
      );
    }
    final value = await _runOperations(operations, kind: kind, page: safePage);
    _cache.write(cacheKey, value, ttl: const Duration(minutes: 30));
    return value;
  }

  Future<CatalogSearchPage> discover({
    required List<String> workTypes,
    int? yearFrom,
    int? yearTo,
    List<String> genres = const [],
    List<String> plotKeywords = const [],
    List<String> countries = const [],
    int page = 1,
  }) async {
    final safePage = _safePage(page);
    final types = workTypes.toSet();
    final includeEverything = types.isEmpty;
    final includeMovies =
        includeEverything ||
        types.any(const {'movie', 'cartoon', 'documentary'}.contains);
    final includeTv =
        includeEverything ||
        types.any(const {'series', 'animated_series'}.contains);
    final includeAnime = includeEverything || types.contains('anime');
    final operations = <_ProviderOperation>[
      if (tmdbConfigured && includeMovies)
        _ProviderOperation(
          'tmdb',
          () => _discoverTmdb(
            'movie',
            workTypes: workTypes,
            yearFrom: yearFrom,
            yearTo: yearTo,
            genres: genres,
            plotKeywords: plotKeywords,
            countries: countries,
            page: safePage,
          ),
        ),
      if (tmdbConfigured && includeTv)
        _ProviderOperation(
          'tmdb',
          () => _discoverTmdb(
            'tv',
            workTypes: workTypes,
            yearFrom: yearFrom,
            yearTo: yearTo,
            genres: genres,
            plotKeywords: plotKeywords,
            countries: countries,
            page: safePage,
          ),
        ),
      if (includeAnime)
        _ProviderOperation(
          'anilist',
          () => _discoverAniList(
            yearFrom: yearFrom,
            yearTo: yearTo,
            genres: genres,
            countries: countries,
            page: safePage,
          ),
        ),
    ];
    if (operations.isEmpty) {
      throw CatalogException(
        'Для выбранных типов нужен TMDB_ACCESS_TOKEN в backend/.env.',
        503,
      );
    }
    return _runOperations(operations, kind: null, page: safePage);
  }

  Future<CatalogSearchPage> _runOperations(
    List<_ProviderOperation> operations, {
    required String? kind,
    required int page,
  }) async {
    final settled = await Future.wait(operations.map(_settle));
    final successes = settled.where((result) => result.error == null).toList();
    final failures = settled.where((result) => result.error != null).toList();
    if (successes.isEmpty) {
      final details = failures.map((failure) => failure.error!).join(' ');
      throw CatalogException(
        details.isEmpty ? 'Каталоги временно недоступны.' : details,
        503,
      );
    }

    final combined =
        successes
            .expand((result) => result.items)
            .where((item) => kind == null || item['kind'] == kind)
            .toList()
          ..sort(
            (a, b) => ((b['popularity'] as num?) ?? 0).compareTo(
              (a['popularity'] as num?) ?? 0,
            ),
          );
    final deduplicated = <String, Map<String, Object?>>{};
    for (final item in combined) {
      final key = _deduplicationKey(item);
      deduplicated.putIfAbsent(key, () => item);
    }
    return CatalogSearchPage(
      results: deduplicated.values.take(40).toList(),
      page: page,
      hasMore: successes.any((result) => result.items.length >= 20),
      warnings: failures.map((failure) => failure.error!).toSet().toList(),
      providers: diagnostics,
    );
  }

  Future<_SettledOperation> _settle(_ProviderOperation operation) async {
    try {
      final items = await operation.run();
      _health[operation.provider] = ProviderHealth(
        provider: operation.provider,
        state: ProviderState.connected,
        checkedAt: DateTime.now(),
      );
      return _SettledOperation(items: items);
    } on CatalogException catch (error) {
      _recordFailure(operation.provider, error.message);
      return _SettledOperation(error: error.message);
    } on TimeoutException {
      final message =
          '${_providerLabel(operation.provider)} не ответил вовремя.';
      _recordFailure(operation.provider, message);
      return _SettledOperation(error: message);
    } on http.ClientException catch (error) {
      final message =
          '${_providerLabel(operation.provider)} недоступен: ${_shortNetworkError(error.message)}';
      _recordFailure(operation.provider, message);
      return _SettledOperation(error: message);
    } catch (error) {
      final message =
          '${_providerLabel(operation.provider)} временно недоступен (${error.runtimeType}).';
      _recordFailure(operation.provider, message);
      return _SettledOperation(error: message);
    }
  }

  void _recordFailure(String provider, String message) {
    _health[provider] = ProviderHealth(
      provider: provider,
      state: ProviderState.error,
      message: message,
      checkedAt: DateTime.now(),
    );
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
    String type, {
    required int page,
  }) async {
    final uri = Uri.https('api.themoviedb.org', '/3/search/$type', {
      'query': query,
      'language': 'ru-RU',
      'include_adult': 'false',
      'page': '$page',
    });
    return _mapTmdbResults(await _getTmdb(uri), type);
  }

  Future<List<Map<String, Object?>>> _popularTmdb(
    String type, {
    required int page,
  }) async {
    final uri = Uri.https('api.themoviedb.org', '/3/trending/$type/week', {
      'language': 'ru-RU',
      'page': '$page',
    });
    return _mapTmdbResults(await _getTmdb(uri), type);
  }

  Future<List<Map<String, Object?>>> _discoverTmdb(
    String type, {
    required List<String> workTypes,
    required int? yearFrom,
    required int? yearTo,
    required List<String> genres,
    required List<String> plotKeywords,
    required List<String> countries,
    required int page,
  }) async {
    final genreIds = genres
        .map((genre) => _tmdbGenreNames[genre.toLowerCase()])
        .whereType<int>()
        .toSet();
    if (workTypes.contains('cartoon') ||
        workTypes.contains('animated_series')) {
      genreIds.add(16);
    }
    if (workTypes.contains('documentary')) genreIds.add(99);
    final keywordIds = await _tmdbKeywordIds(plotKeywords.take(4));
    final countryCodes = countries
        .map((country) => _countryCodes[country.toLowerCase()])
        .whereType<String>()
        .toSet();
    final dateField = type == 'tv' ? 'first_air_date' : 'primary_release_date';
    final parameters = <String, String>{
      'language': 'ru-RU',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
      'page': '$page',
      if (yearFrom != null) '$dateField.gte': '$yearFrom-01-01',
      if (yearTo != null) '$dateField.lte': '$yearTo-12-31',
      if (genreIds.isNotEmpty) 'with_genres': genreIds.join(','),
      if (keywordIds.isNotEmpty) 'with_keywords': keywordIds.join('|'),
      if (countryCodes.isNotEmpty)
        'with_origin_country': countryCodes.join('|'),
    };
    final uri = Uri.https(
      'api.themoviedb.org',
      '/3/discover/$type',
      parameters,
    );
    return _mapTmdbResults(await _getTmdb(uri), type);
  }

  Future<List<int>> _tmdbKeywordIds(Iterable<String> keywords) async {
    final normalized = keywords
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.length >= 3)
        .toSet()
        .toList();
    final ids = <int>[];
    for (final keyword in normalized) {
      final cacheKey = 'tmdb-keyword:$keyword';
      final cached = _cache.read<int>(cacheKey);
      if (cached != null) {
        ids.add(cached);
        continue;
      }
      final uri = Uri.https('api.themoviedb.org', '/3/search/keyword', {
        'query': keyword,
        'page': '1',
      });
      final data = await _getTmdb(uri);
      final results = (data['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      if (results.isEmpty) continue;
      final id = (results.first['id'] as num?)?.toInt();
      if (id != null) {
        ids.add(id);
        _cache.write(cacheKey, id, ttl: const Duration(hours: 12));
      }
    }
    return ids;
  }

  List<Map<String, Object?>> _mapTmdbResults(
    Map<String, dynamic> data,
    String type,
  ) => (data['results'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .where((row) => row['id'] != null)
      .map((row) => _mapTmdb(row, type))
      .toList();

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
              .whereType<Map<String, dynamic>>()
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
        .whereType<Map<String, dynamic>>()
        .map((genre) => genre['name'])
        .whereType<String>()
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
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw CatalogException(
        response.statusCode == 401
            ? 'TMDB отклонил ключ (401). Проверьте TMDB_ACCESS_TOKEN.'
            : 'TMDB временно недоступен (${response.statusCode}).',
        response.statusCode,
      );
    }
    return _decodeObject(response.body, provider: 'TMDB');
  }

  Map<String, Object?> _mapTmdb(Map<String, dynamic> row, String type) {
    final isTv = type == 'tv';
    final genreIds = (row['genre_ids'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
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
      'originCountries': (row['origin_country'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      'originalLanguage': row['original_language'] as String?,
    };
  }

  Future<List<Map<String, Object?>>> _searchAniList(
    String query, {
    required int page,
  }) async {
    final response = await _postAniList(_aniListSearchQuery, {
      'search': query,
      'page': page,
    });
    return _aniListMedia(response).map(_mapAniList).toList();
  }

  Future<List<Map<String, Object?>>> _popularAniList({
    required int page,
  }) async {
    final response = await _postAniList(_aniListPopularQuery, {'page': page});
    return _aniListMedia(response).map(_mapAniList).toList();
  }

  Future<List<Map<String, Object?>>> _discoverAniList({
    required int? yearFrom,
    required int? yearTo,
    required List<String> genres,
    required List<String> countries,
    required int page,
  }) async {
    final supportedGenres = genres
        .map((genre) => _aniListGenres[genre.toLowerCase()])
        .whereType<String>()
        .toSet()
        .toList();
    final countryCodes = countries
        .map((value) => _countryCodes[value.toLowerCase()])
        .whereType<String>()
        .toList();
    final response = await _postAniList(_aniListDiscoverQuery, {
      'page': page,
      if (yearFrom != null) 'startFrom': yearFrom * 10000 + 101,
      if (yearTo != null) 'startTo': yearTo * 10000 + 1231,
      if (supportedGenres.isNotEmpty) 'genres': supportedGenres,
      if (countryCodes.isNotEmpty) 'country': countryCodes.first,
    });
    return _aniListMedia(response).map(_mapAniList).toList();
  }

  Iterable<Map<String, dynamic>> _aniListMedia(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final page = data['Page'] as Map<String, dynamic>? ?? const {};
    return (page['media'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
  }

  Future<Map<String, Object?>> _aniListDetails(String id) async {
    final response = await _postAniList(_aniListDetailsQuery, {
      'id': int.parse(id),
    });
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final row = data['Media'] as Map<String, dynamic>?;
    if (row == null) {
      throw CatalogException('AniList не нашёл произведение.', 404);
    }
    return _mapAniList(row);
  }

  Future<Map<String, dynamic>> _postAniList(
    String query,
    Map<String, Object?> variables,
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
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw CatalogException(
        'AniList временно недоступен (${response.statusCode}).',
        response.statusCode,
      );
    }
    return _decodeObject(response.body, provider: 'AniList');
  }

  Map<String, Object?> _mapAniList(Map<String, dynamic> row) {
    final title = row['title'] as Map<String, dynamic>? ?? const {};
    final cover = row['coverImage'] as Map<String, dynamic>? ?? const {};
    final startDate = row['startDate'] as Map<String, dynamic>? ?? const {};
    final externalId = (row['id'] as num).toInt();
    final episodes = ((row['episodes'] as num?) ?? 0).toInt();
    final duration = ((row['duration'] as num?) ?? 0).toInt();
    final format = row['format'] as String?;
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
      'genres': (row['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      'posterUrl': (cover['extraLarge'] ?? cover['large']) as String?,
      'runtimeMinutes': format == 'MOVIE' ? duration : 0,
      'seasonCount': episodes > 0 ? 1 : 0,
      'episodeCount': episodes,
      'episodeRuntimeMinutes': duration,
      'seasons': episodes > 0
          ? [
              {'number': 1, 'episodeCount': episodes, 'name': 'Сезон 1'},
            ]
          : const [],
      'popularity': ((row['popularity'] as num?) ?? 0).toDouble(),
      'originCountries': [
        if (row['countryOfOrigin'] case final String country) country,
      ],
      'originalLanguage': row['countryOfOrigin'] as String?,
      'format': format,
      'tags': (row['tags'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((tag) => tag['name'])
          .whereType<String>()
          .take(12)
          .toList(),
    };
  }
}

class CatalogSearchPage {
  const CatalogSearchPage({
    required this.results,
    required this.page,
    required this.hasMore,
    required this.warnings,
    required this.providers,
  });

  final List<Map<String, Object?>> results;
  final int page;
  final bool hasMore;
  final List<String> warnings;
  final Map<String, Object?> providers;

  Map<String, Object?> toJson() => {
    'results': results,
    'count': results.length,
    'page': page,
    'hasMore': hasMore,
    'warnings': warnings,
    'providers': providers,
  };
}

enum ProviderState { unknown, connected, notConfigured, error }

class ProviderHealth {
  const ProviderHealth({
    required this.provider,
    required this.state,
    this.message,
    this.checkedAt,
  });

  final String provider;
  final ProviderState state;
  final String? message;
  final DateTime? checkedAt;

  ProviderHealth copyWith({ProviderState? state, String? message}) =>
      ProviderHealth(
        provider: provider,
        state: state ?? this.state,
        message: message ?? this.message,
        checkedAt: checkedAt,
      );

  Map<String, Object?> toJson() => {
    'provider': provider,
    'status': state.name,
    if (message != null) 'message': message,
    if (checkedAt != null) 'checkedAt': checkedAt!.toIso8601String(),
  };
}

class CatalogException implements Exception {
  CatalogException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class _ProviderOperation {
  const _ProviderOperation(this.provider, this.run);
  final String provider;
  final Future<List<Map<String, Object?>>> Function() run;
}

class _SettledOperation {
  const _SettledOperation({this.items = const [], this.error});
  final List<Map<String, Object?>> items;
  final String? error;
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

  void write(
    String key,
    Object value, {
    Duration ttl = const Duration(minutes: 10),
  }) {
    if (_values.length >= 300) _values.remove(_values.keys.first);
    _values[key] = (expiresAt: DateTime.now().add(ttl), value: value);
  }
}

Map<String, dynamic> _decodeObject(String body, {required String provider}) {
  try {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    // Converted to a provider-specific error below.
  }
  throw CatalogException('$provider вернул некорректный JSON.', 502);
}

String _normalizeQuery(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

int _safePage(int value) => value < 1 ? 1 : (value > 50 ? 50 : value);

String _deduplicationKey(Map<String, Object?> item) {
  final title = (item['title'] as String? ?? '').toLowerCase().replaceAll(
    RegExp(r'[^a-zа-яё0-9]+', caseSensitive: false),
    '',
  );
  return '$title:${item['year']}';
}

String? _cleanSecret(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

String _providerLabel(String provider) => switch (provider) {
  'tmdb' => 'TMDB',
  'anilist' => 'AniList',
  _ => provider,
};

String _shortNetworkError(String value) {
  final firstLine = value.split('\n').first.trim();
  return firstLine.length <= 180
      ? firstLine
      : '${firstLine.substring(0, 177)}…';
}

String _stripHtml(String value) => value
    .replaceAll(RegExp('<br\\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&');

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

const _tmdbGenreNames = <String, int>{
  'action': 28,
  'adventure': 12,
  'animation': 16,
  'comedy': 35,
  'crime': 80,
  'documentary': 99,
  'drama': 18,
  'family': 10751,
  'fantasy': 14,
  'history': 36,
  'horror': 27,
  'mystery': 9648,
  'romance': 10749,
  'science fiction': 878,
  'thriller': 53,
  'western': 37,
};

const _aniListGenres = <String, String>{
  'action': 'Action',
  'adventure': 'Adventure',
  'comedy': 'Comedy',
  'drama': 'Drama',
  'fantasy': 'Fantasy',
  'horror': 'Horror',
  'mystery': 'Mystery',
  'romance': 'Romance',
  'science fiction': 'Sci-Fi',
  'sports': 'Sports',
  'supernatural': 'Supernatural',
};

const _countryCodes = <String, String>{
  'japan': 'JP',
  'япония': 'JP',
  'united states': 'US',
  'сша': 'US',
  'russia': 'RU',
  'россия': 'RU',
  'france': 'FR',
  'франция': 'FR',
  'united kingdom': 'GB',
  'south korea': 'KR',
  'china': 'CN',
};

const _aniListFields = r'''
  id
  title { romaji english native }
  description(asHtml: false)
  startDate { year }
  countryOfOrigin
  format
  episodes
  duration
  averageScore
  popularity
  genres
  tags { name rank }
  coverImage { large extraLarge }
''';

const _aniListSearchQuery =
    '''
query SearchAnime(\$search: String!, \$page: Int!) {
  Page(page: \$page, perPage: 20) {
    media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
      $_aniListFields
    }
  }
}
''';

const _aniListPopularQuery =
    '''
query PopularAnime(\$page: Int!) {
  Page(page: \$page, perPage: 20) {
    media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) {
      $_aniListFields
    }
  }
}
''';

const _aniListDiscoverQuery =
    '''
query DiscoverAnime(
  \$page: Int!,
  \$startFrom: FuzzyDateInt,
  \$startTo: FuzzyDateInt,
  \$genres: [String],
  \$country: CountryCode
) {
  Page(page: \$page, perPage: 20) {
    media(
      type: ANIME,
      sort: POPULARITY_DESC,
      isAdult: false,
      startDate_greater: \$startFrom,
      startDate_lesser: \$startTo,
      genre_in: \$genres,
      countryOfOrigin: \$country
    ) {
      $_aniListFields
    }
  }
}
''';

const _aniListDetailsQuery =
    '''
query AnimeDetails(\$id: Int!) {
  Media(id: \$id, type: ANIME) {
    $_aniListFields
  }
}
''';
