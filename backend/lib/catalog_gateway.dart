import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_provider.dart';
import 'catalog_providers.dart';

class CatalogSettings {
  const CatalogSettings({
    this.tmdbEnabled = true,
    this.aniListEnabled = true,
    this.jikanEnabled = true,
    this.tvMazeEnabled = true,
    this.tmdbToken,
    this.tmdbLanguage = 'ru-RU',
    this.tmdbRegion = 'RU',
    this.jikanBaseUrl = 'https://api.jikan.moe/v4',
    this.tvMazeBaseUrl = 'https://api.tvmaze.com',
    this.aniListBaseUrl = 'https://graphql.anilist.co',
    this.connectionTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 20),
    this.cacheTtl = const Duration(hours: 24),
  });

  final bool tmdbEnabled;
  final bool aniListEnabled;
  final bool jikanEnabled;
  final bool tvMazeEnabled;
  final String? tmdbToken;
  final String tmdbLanguage;
  final String tmdbRegion;
  final String jikanBaseUrl;
  final String tvMazeBaseUrl;
  final String aniListBaseUrl;
  final Duration connectionTimeout;
  final Duration requestTimeout;
  final Duration cacheTtl;

  factory CatalogSettings.fromEnvironment(Map<String, String> values) =>
      CatalogSettings(
        tmdbEnabled: _settingBool(values['TMDB_ENABLED'], fallback: true),
        aniListEnabled: _settingBool(values['ANILIST_ENABLED'], fallback: true),
        jikanEnabled: _settingBool(values['JIKAN_ENABLED'], fallback: true),
        tvMazeEnabled: _settingBool(values['TVMAZE_ENABLED'], fallback: true),
        tmdbToken: _cleanSecret(values['TMDB_ACCESS_TOKEN']),
        tmdbLanguage: _cleanSecret(values['TMDB_LANGUAGE']) ?? 'ru-RU',
        tmdbRegion: _cleanSecret(values['TMDB_REGION']) ?? 'RU',
        jikanBaseUrl:
            _cleanSecret(values['JIKAN_BASE_URL']) ??
            'https://api.jikan.moe/v4',
        tvMazeBaseUrl:
            _cleanSecret(values['TVMAZE_BASE_URL']) ?? 'https://api.tvmaze.com',
        aniListBaseUrl:
            _cleanSecret(values['ANILIST_BASE_URL']) ??
            'https://graphql.anilist.co',
        connectionTimeout: Duration(
          seconds: _settingInt(
            values['CATALOG_CONNECTION_TIMEOUT_SECONDS'],
            fallback: 10,
            min: 2,
            max: 60,
          ),
        ),
        requestTimeout: Duration(
          seconds: _settingInt(
            values['CATALOG_REQUEST_TIMEOUT_SECONDS'],
            fallback: 20,
            min: 2,
            max: 120,
          ),
        ),
        cacheTtl: Duration(
          hours: _settingInt(
            values['CATALOG_CACHE_HOURS'],
            fallback: 24,
            min: 1,
            max: 720,
          ),
        ),
      );
}

class CatalogGateway {
  CatalogGateway(
    this._client, {
    String? tmdbToken,
    Duration requestTimeout = const Duration(seconds: 12),
    CatalogSettings? settings,
  }) : _settings =
           settings ??
           CatalogSettings(
             tmdbToken: tmdbToken,
             requestTimeout: requestTimeout,
           ),
       _tmdbToken = _cleanSecret(settings?.tmdbToken ?? tmdbToken),
       _requestTimeout = settings?.requestTimeout ?? requestTimeout {
    _providers = [
      TmdbCatalogProvider(
        enabled: _settings.tmdbEnabled && tmdbConfigured,
        searchCallback: _legacyTmdbSearch,
        popularCallback: _legacyTmdbPopular,
        discoverCallback: _legacyTmdbDiscover,
        detailsCallback: _legacyTmdbDetails,
      ),
      AniListCatalogProvider(
        enabled: _settings.aniListEnabled,
        searchCallback: _legacyAniListSearch,
        popularCallback: _legacyAniListPopular,
        discoverCallback: _legacyAniListDiscover,
        detailsCallback: _legacyAniListDetails,
      ),
      JikanCatalogProvider(
        client: _client,
        enabled: _settings.jikanEnabled,
        baseUrl: _settings.jikanBaseUrl,
        timeout: _requestTimeout,
      ),
      TvMazeCatalogProvider(
        client: _client,
        enabled: _settings.tvMazeEnabled,
        baseUrl: _settings.tvMazeBaseUrl,
        timeout: _requestTimeout,
      ),
    ];
    for (final provider in _providers) {
      _health[provider.name] = ProviderHealth(
        provider: provider.name,
        state: provider.enabled
            ? ProviderState.unknown
            : ProviderState.disabled,
      );
    }
  }

  final http.Client _client;
  final CatalogSettings _settings;
  final String? _tmdbToken;
  final Duration _requestTimeout;
  late final List<CatalogProvider> _providers;
  final _cache = _MemoryCache();
  final Map<String, ProviderHealth> _health = {};

  bool get tmdbConfigured => _tmdbToken != null;

  Map<String, Object?> get diagnostics => {
    for (final provider in _providers)
      provider.name: provider.name == 'tmdb' && !tmdbConfigured
          ? const ProviderHealth(
              provider: 'tmdb',
              state: ProviderState.notConfigured,
              message: 'Ключ не настроен',
            ).toJson()
          : _health[provider.name]!.toJson(),
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

    final request = CatalogProviderRequest(
      query: normalized,
      kind: kind,
      page: safePage,
    );
    final operations = _providers
        .where((provider) => provider.enabled && provider.supportsKind(kind))
        .map(
          (provider) =>
              _ProviderOperation(provider.name, () => provider.search(request)),
        )
        .toList();

    if (operations.isEmpty) {
      throw CatalogException(
        'Для этого типа нужен TMDB_ACCESS_TOKEN в backend/.env.',
        503,
      );
    }
    final value = await _runOperations(operations, kind: kind, page: safePage);
    _cache.write(cacheKey, value, ttl: _settings.cacheTtl);
    return value;
  }

  Future<CatalogSearchPage> popular({String? kind, int page = 1}) async {
    final safePage = _safePage(page);
    final cacheKey = 'popular:$kind:$safePage';
    final cached = _cache.read<CatalogSearchPage>(cacheKey);
    if (cached != null) return cached;

    final request = CatalogProviderRequest(kind: kind, page: safePage);
    final operations = _providers
        .where((provider) => provider.enabled && provider.supportsKind(kind))
        .map(
          (provider) => _ProviderOperation(
            provider.name,
            () => provider.popular(request),
          ),
        )
        .toList();
    if (operations.isEmpty) {
      throw CatalogException(
        'Для этого типа нужен TMDB_ACCESS_TOKEN в backend/.env.',
        503,
      );
    }
    final value = await _runOperations(operations, kind: kind, page: safePage);
    _cache.write(cacheKey, value, ttl: _settings.cacheTtl);
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
    final request = CatalogProviderRequest(
      page: safePage,
      yearFrom: yearFrom,
      yearTo: yearTo,
      genres: genres,
      plotKeywords: plotKeywords,
      countries: countries,
      workTypes: workTypes,
    );
    final operations = _providers
        .where(
          (provider) =>
              provider.enabled &&
              _providerMatchesWorkTypes(provider.name, workTypes),
        )
        .map(
          (provider) => _ProviderOperation(
            provider.name,
            () => provider.discover(request),
          ),
        )
        .toList();
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
            .where((item) => kind == null || item.kind == kind)
            .toList()
          ..sort((a, b) => b.popularity.compareTo(a.popularity));
    final deduplicated = <CatalogMedia>[];
    for (final candidate in combined) {
      final matchIndex = deduplicated.indexWhere(
        (existing) => _dedupeConfidence(existing, candidate) != null,
      );
      if (matchIndex < 0) {
        deduplicated.add(candidate);
        continue;
      }
      final confidence = _dedupeConfidence(
        deduplicated[matchIndex],
        candidate,
      )!;
      deduplicated[matchIndex] = deduplicated[matchIndex].merge(
        candidate,
        confidence: confidence,
      );
    }
    return CatalogSearchPage(
      results: deduplicated.take(40).map((item) => item.toJson()).toList(),
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
    } on CatalogProviderException catch (error) {
      _recordFailure(operation.provider, error.userMessage);
      return _SettledOperation(error: error.userMessage);
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
    final provider = _providers
        .where((candidate) => candidate.supportsSource(source))
        .firstOrNull;
    if (provider == null) {
      throw CatalogException('Неизвестный источник: $source', 400);
    }
    if (!provider.enabled) {
      throw CatalogException(
        '${_providerLabel(provider.name)} не настроен или отключён.',
        503,
      );
    }
    late final Map<String, Object?> result;
    try {
      result = (await provider.details(source, id)).toJson();
      _health[provider.name] = ProviderHealth(
        provider: provider.name,
        state: ProviderState.connected,
        checkedAt: DateTime.now(),
      );
    } on CatalogProviderException catch (error) {
      _recordFailure(provider.name, error.userMessage);
      throw CatalogException(error.userMessage, error.statusCode);
    }
    _cache.write(cacheKey, result, ttl: _settings.cacheTtl);
    return result;
  }

  Future<List<Map<String, Object?>>> _legacyTmdbSearch(
    CatalogProviderRequest request,
  ) async {
    final types = <String>[
      if (request.kind == null ||
          const {'movie', 'cartoon', 'documentary'}.contains(request.kind))
        'movie',
      if (request.kind == null ||
          const {'series', 'animatedSeries'}.contains(request.kind))
        'tv',
    ];
    final pages = await Future.wait(
      types.map((type) => _searchTmdb(request.query, type, page: request.page)),
    );
    return pages.expand((items) => items).toList();
  }

  Future<List<Map<String, Object?>>> _legacyTmdbPopular(
    CatalogProviderRequest request,
  ) async {
    final types = <String>[
      if (request.kind == null ||
          const {'movie', 'cartoon', 'documentary'}.contains(request.kind))
        'movie',
      if (request.kind == null ||
          const {'series', 'animatedSeries'}.contains(request.kind))
        'tv',
    ];
    final pages = await Future.wait(
      types.map((type) => _popularTmdb(type, page: request.page)),
    );
    return pages.expand((items) => items).toList();
  }

  Future<List<Map<String, Object?>>> _legacyTmdbDiscover(
    CatalogProviderRequest request,
  ) async {
    final types = request.workTypes.toSet();
    final includeEverything = types.isEmpty;
    final mediaTypes = <String>[
      if (includeEverything ||
          types.any(const {'movie', 'cartoon', 'documentary'}.contains))
        'movie',
      if (includeEverything ||
          types.any(const {'series', 'animated_series'}.contains))
        'tv',
    ];
    final pages = await Future.wait(
      mediaTypes.map(
        (type) => _discoverTmdb(
          type,
          workTypes: request.workTypes,
          yearFrom: request.yearFrom,
          yearTo: request.yearTo,
          genres: request.genres,
          plotKeywords: request.plotKeywords,
          countries: request.countries,
          page: request.page,
        ),
      ),
    );
    return pages.expand((items) => items).toList();
  }

  Future<Map<String, Object?>> _legacyTmdbDetails(String source, String id) =>
      _tmdbDetails(id, isTv: source == 'tmdb_tv');

  Future<List<Map<String, Object?>>> _legacyAniListSearch(
    CatalogProviderRequest request,
  ) => _searchAniList(request.query, page: request.page);

  Future<List<Map<String, Object?>>> _legacyAniListPopular(
    CatalogProviderRequest request,
  ) => _popularAniList(page: request.page);

  Future<List<Map<String, Object?>>> _legacyAniListDiscover(
    CatalogProviderRequest request,
  ) => _discoverAniList(
    yearFrom: request.yearFrom,
    yearTo: request.yearTo,
    genres: request.genres,
    countries: request.countries,
    page: request.page,
  );

  Future<Map<String, Object?>> _legacyAniListDetails(
    String source,
    String id,
  ) => _aniListDetails(id);

  Future<List<Map<String, Object?>>> _searchTmdb(
    String query,
    String type, {
    required int page,
  }) async {
    final uri = Uri.https('api.themoviedb.org', '/3/search/$type', {
      'query': query,
      'language': _settings.tmdbLanguage,
      'region': _settings.tmdbRegion,
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
      'language': _settings.tmdbLanguage,
      'region': _settings.tmdbRegion,
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
      'language': _settings.tmdbLanguage,
      'region': _settings.tmdbRegion,
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
      'language': _settings.tmdbLanguage,
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
      'externalIds': {'tmdb': '$externalId'},
      'title': title,
      'subtitle':
          (row['original_name'] ?? row['original_title'] ?? '') as String,
      'originalTitle':
          (row['original_name'] ?? row['original_title'] ?? '') as String,
      'synonyms': const <String>[],
      'description': (row['overview'] as String?) ?? '',
      'year': date.length >= 4 ? int.tryParse(date.substring(0, 4)) ?? 0 : 0,
      'kind': kind,
      'rating': ((row['vote_average'] as num?) ?? 0).toDouble(),
      'genres': genres,
      'posterUrl': posterPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w500$posterPath',
      'backdropUrl': row['backdrop_path'] == null
          ? null
          : 'https://image.tmdb.org/t/p/w1280${row['backdrop_path']}',
      'runtimeMinutes': 0,
      'seasonCount': 0,
      'episodeCount': 0,
      'episodeRuntimeMinutes': isTv ? 45 : 0,
      'seasons': const [],
      'popularity': ((row['popularity'] as num?) ?? 0).toDouble(),
      'voteCount': ((row['vote_count'] as num?) ?? 0).toInt(),
      'originCountries': (row['origin_country'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      'originalLanguage': row['original_language'] as String?,
      'format': isTv ? 'TV' : 'MOVIE',
      'keywords': const <String>[],
      'characters': const <Map<String, Object?>>[],
      'cast': const <Map<String, Object?>>[],
      'studios': const <String>[],
      'relations': const <Map<String, Object?>>[],
      'sourceUrls': ['https://www.themoviedb.org/$type/$externalId'],
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
          Uri.parse(_settings.aniListBaseUrl),
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
    final endDate = row['endDate'] as Map<String, dynamic>? ?? const {};
    final externalId = (row['id'] as num).toInt();
    final malId = (row['idMal'] as num?)?.toInt();
    final episodes = ((row['episodes'] as num?) ?? 0).toInt();
    final duration = ((row['duration'] as num?) ?? 0).toInt();
    final format = row['format'] as String?;
    return {
      'id': 3000000000 + externalId,
      'source': 'anilist',
      'externalId': '$externalId',
      'externalIds': {
        'anilist': '$externalId',
        if (malId != null) 'mal': '$malId',
      },
      'title':
          (title['english'] ?? title['romaji'] ?? title['native']) as String,
      'subtitle': (title['romaji'] ?? title['native'] ?? '') as String,
      'originalTitle': (title['romaji'] ?? title['native'] ?? '') as String,
      'englishTitle': (title['english'] ?? '') as String,
      'nativeTitle': (title['native'] ?? '') as String,
      'synonyms': (row['synonyms'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      'description': _stripHtml((row['description'] as String?) ?? ''),
      'year': ((startDate['year'] as num?) ?? 0).toInt(),
      'endYear': (endDate['year'] as num?)?.toInt(),
      'kind': 'anime',
      'rating': (((row['averageScore'] as num?) ?? 0) / 10).toDouble(),
      'genres': (row['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      'posterUrl': (cover['extraLarge'] ?? cover['large']) as String?,
      'backdropUrl': row['bannerImage'] as String?,
      'runtimeMinutes': format == 'MOVIE' ? duration : 0,
      'seasonCount': 0,
      'episodeCount': episodes,
      'episodeRuntimeMinutes': duration,
      'seasons': const <Map<String, Object?>>[],
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
      'keywords': const <String>[],
      'voteCount': 0,
      'characters': const <Map<String, Object?>>[],
      'cast': const <Map<String, Object?>>[],
      'studios':
          ((row['studios'] as Map?)?['nodes'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((studio) => studio['name'])
              .whereType<String>()
              .toList(),
      'relations':
          ((row['relations'] as Map?)?['edges'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((edge) {
                final node = edge['node'] as Map? ?? const {};
                final relationTitle = node['title'] as Map? ?? const {};
                return <String, Object?>{
                  'relationType': edge['relationType'],
                  'source': 'anilist',
                  'sourceId': '${node['id'] ?? ''}',
                  'title': relationTitle['english'] ?? relationTitle['romaji'],
                  'format': node['format'],
                };
              })
              .toList(),
      'sourceUrls': {
        if (row['siteUrl'] is String) row['siteUrl'] as String,
        ...((row['externalLinks'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((link) => link['url'])
            .whereType<String>()),
      }.toList(),
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

enum ProviderState { unknown, connected, notConfigured, disabled, error }

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
  final Future<List<CatalogMedia>> Function() run;
}

class _SettledOperation {
  const _SettledOperation({this.items = const [], this.error});
  final List<CatalogMedia> items;
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

bool _providerMatchesWorkTypes(String provider, List<String> workTypes) {
  if (workTypes.isEmpty) return true;
  final types = workTypes.toSet();
  return switch (provider) {
    'tmdb' => types.any(
      const {
        'movie',
        'series',
        'cartoon',
        'animated_series',
        'documentary',
      }.contains,
    ),
    'anilist' || 'jikan' => types.any(
      const {'anime', 'cartoon', 'animated_series'}.contains,
    ),
    'tvmaze' => types.any(const {'series', 'animated_series'}.contains),
    _ => false,
  };
}

double? _dedupeConfidence(CatalogMedia first, CatalogMedia second) {
  if (first.source == second.source && first.externalId == second.externalId) {
    return 1;
  }
  for (final key in first.externalIds.keys) {
    final left = first.externalIds[key];
    final right = second.externalIds[key];
    if (left != null && left.isNotEmpty && left == right) return .99;
  }
  if (!_compatibleFormats(first.format, second.format)) return null;
  if (first.year > 0 &&
      second.year > 0 &&
      (first.year - second.year).abs() > 1) {
    return null;
  }
  final firstTitles = first.titleVariants.map(_normalizedTitle).toSet()
    ..remove('');
  final secondTitles = second.titleVariants.map(_normalizedTitle).toSet()
    ..remove('');
  if (firstTitles.intersection(secondTitles).isEmpty) return null;
  return first.year == second.year ? .9 : .84;
}

bool _compatibleFormats(String? first, String? second) {
  if (first == null || second == null || first.isEmpty || second.isEmpty) {
    return true;
  }
  final left = first.toUpperCase();
  final right = second.toUpperCase();
  final leftMovie = left.contains('MOVIE') || left.contains('FILM');
  final rightMovie = right.contains('MOVIE') || right.contains('FILM');
  return leftMovie == rightMovie;
}

String _normalizedTitle(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), '');

String? _cleanSecret(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

bool _settingBool(String? value, {required bool fallback}) =>
    switch (value?.trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => fallback,
    };

int _settingInt(
  String? value, {
  required int fallback,
  required int min,
  required int max,
}) => (int.tryParse(value ?? '') ?? fallback).clamp(min, max);

String _providerLabel(String provider) => switch (provider) {
  'tmdb' => 'TMDB',
  'anilist' => 'AniList',
  'jikan' => 'Jikan',
  'tvmaze' => 'TVmaze',
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
  idMal
  title { romaji english native }
  synonyms
  description(asHtml: false)
  startDate { year }
  endDate { year }
  countryOfOrigin
  format
  episodes
  duration
  averageScore
  popularity
  genres
  tags { name rank }
  coverImage { large extraLarge }
  bannerImage
  siteUrl
  studios(isMain: true) { nodes { name } }
  relations {
    edges {
      relationType(version: 2)
      node { id type format title { romaji english native } }
    }
  }
  externalLinks { site url }
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
