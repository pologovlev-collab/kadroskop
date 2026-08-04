import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_provider.dart';

typedef CatalogListCallback =
    Future<List<Map<String, Object?>>> Function(CatalogProviderRequest request);
typedef CatalogDetailsCallback =
    Future<Map<String, Object?>> Function(String source, String id);
typedef CatalogRelatedCallback =
    Future<List<Map<String, Object?>>> Function(
      String source,
      String id, {
      int page,
    });

class TmdbCatalogProvider extends _CallbackCatalogProvider {
  TmdbCatalogProvider({
    required super.enabled,
    required super.searchCallback,
    required super.popularCallback,
    required super.discoverCallback,
    required super.detailsCallback,
    required super.recommendationsCallback,
    required super.similarCallback,
  }) : super(
         name: 'tmdb',
         kinds: const {
           'movie',
           'series',
           'cartoon',
           'animatedSeries',
           'documentary',
         },
         sources: const {'tmdb_movie', 'tmdb_tv'},
         characterSearchCallback: null,
       );
}

class AniListCatalogProvider extends _CallbackCatalogProvider {
  AniListCatalogProvider({
    required super.enabled,
    required super.searchCallback,
    required super.popularCallback,
    required super.discoverCallback,
    required super.detailsCallback,
    required CatalogListCallback characterSearchCallback,
    required super.recommendationsCallback,
    required super.similarCallback,
  }) : super(
         name: 'anilist',
         kinds: const {'anime', 'cartoon', 'animatedSeries'},
         sources: const {'anilist'},
         characterSearchCallback: characterSearchCallback,
       );
}

class _CallbackCatalogProvider implements CatalogProvider {
  const _CallbackCatalogProvider({
    required this.name,
    required this.enabled,
    required this.kinds,
    required this.sources,
    required this.searchCallback,
    required this.popularCallback,
    required this.discoverCallback,
    required this.detailsCallback,
    required this.characterSearchCallback,
    required this.recommendationsCallback,
    required this.similarCallback,
  });

  @override
  final String name;
  @override
  final bool enabled;
  final Set<String> kinds;
  final Set<String> sources;
  final CatalogListCallback searchCallback;
  final CatalogListCallback popularCallback;
  final CatalogListCallback discoverCallback;
  final CatalogDetailsCallback detailsCallback;
  final CatalogListCallback? characterSearchCallback;
  final CatalogRelatedCallback recommendationsCallback;
  final CatalogRelatedCallback similarCallback;

  @override
  bool get supportsCharacterSearch => characterSearchCallback != null;

  @override
  bool supportsKind(String? kind) => kind == null || kinds.contains(kind);

  @override
  bool supportsSource(String source) => sources.contains(source);

  @override
  Future<List<CatalogMedia>> search(CatalogProviderRequest request) async =>
      (await searchCallback(request)).map(CatalogMedia.fromJson).toList();

  @override
  Future<List<CatalogMedia>> popular(CatalogProviderRequest request) async =>
      (await popularCallback(request)).map(CatalogMedia.fromJson).toList();

  @override
  Future<List<CatalogMedia>> discover(CatalogProviderRequest request) async =>
      (await discoverCallback(request)).map(CatalogMedia.fromJson).toList();

  @override
  Future<CatalogMedia> details(String source, String id) async =>
      CatalogMedia.fromJson(await detailsCallback(source, id));

  @override
  Future<List<CatalogMedia>> searchByCharacter(
    String characterName, {
    int page = 1,
  }) async {
    final callback = characterSearchCallback;
    if (callback == null) return const [];
    return (await callback(
      CatalogProviderRequest(query: characterName, page: page),
    )).map(CatalogMedia.fromJson).toList();
  }

  @override
  Future<List<CatalogMedia>> recommendations(
    String source,
    String id, {
    int page = 1,
  }) async => (await recommendationsCallback(
    source,
    id,
    page: page,
  )).map(CatalogMedia.fromJson).toList();

  @override
  Future<List<CatalogMedia>> similar(
    String source,
    String id, {
    int page = 1,
  }) async => (await similarCallback(
    source,
    id,
    page: page,
  )).map(CatalogMedia.fromJson).toList();
}

class JikanCatalogProvider implements CatalogProvider {
  JikanCatalogProvider({
    required http.Client client,
    this.enabled = true,
    String baseUrl = 'https://api.jikan.moe/v4',
    Duration timeout = const Duration(seconds: 20),
    Future<void> Function(Duration duration)? delay,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _http = _ProviderHttp(
         provider: 'jikan',
         client: client,
         timeout: timeout,
         delay: delay,
         minimumInterval: const Duration(milliseconds: 350),
       );

  @override
  String get name => 'jikan';
  @override
  bool get supportsCharacterSearch => true;
  @override
  final bool enabled;
  final String _baseUrl;
  final _ProviderHttp _http;

  @override
  bool supportsKind(String? kind) =>
      kind == null ||
      const {'anime', 'cartoon', 'animatedSeries'}.contains(kind);

  @override
  bool supportsSource(String source) => source == 'jikan';

  @override
  Future<List<CatalogMedia>> search(CatalogProviderRequest request) async {
    final uri = Uri.parse('$_baseUrl/anime').replace(
      queryParameters: {
        'q': request.query,
        'page': '${request.page}',
        'limit': '25',
        'sfw': 'true',
      },
    );
    return _mediaList(await _http.get(uri));
  }

  @override
  Future<List<CatalogMedia>> popular(CatalogProviderRequest request) async {
    final uri = Uri.parse('$_baseUrl/top/anime').replace(
      queryParameters: {
        'page': '${request.page}',
        'limit': '25',
        'filter': 'bypopularity',
      },
    );
    return _mediaList(await _http.get(uri));
  }

  @override
  Future<List<CatalogMedia>> discover(CatalogProviderRequest request) async {
    final genreIds = request.genres
        .map((genre) => _jikanGenreIds[genre.toLowerCase()])
        .whereType<int>()
        .toSet();
    final uri = Uri.parse('$_baseUrl/anime').replace(
      queryParameters: {
        'page': '${request.page}',
        'limit': '25',
        'sfw': 'true',
        'order_by': 'popularity',
        'sort': 'asc',
        if (request.yearFrom != null) 'start_date': '${request.yearFrom}-01-01',
        if (request.yearTo != null) 'end_date': '${request.yearTo}-12-31',
        if (genreIds.isNotEmpty) 'genres': genreIds.join(','),
      },
    );
    return _mediaList(await _http.get(uri));
  }

  @override
  Future<CatalogMedia> details(String source, String id) async {
    final payload = await _http.get(Uri.parse('$_baseUrl/anime/$id/full'));
    if (payload is! Map) {
      throw const CatalogProviderException(
        'jikan',
        'invalid_response',
        'Jikan вернул некорректный ответ.',
      );
    }
    final data = payload['data'];
    if (data is! Map) {
      throw const CatalogProviderException(
        'jikan',
        'not_found',
        'Jikan не нашёл произведение.',
        statusCode: 404,
        retryable: false,
      );
    }
    return _mapMedia(data.cast<String, dynamic>());
  }

  @override
  Future<List<CatalogMedia>> searchByCharacter(
    String characterName, {
    int page = 1,
  }) async {
    final searchPayload = await _http.get(
      Uri.parse('$_baseUrl/characters').replace(
        queryParameters: {'q': characterName, 'page': '$page', 'limit': '3'},
      ),
    );
    final rows = searchPayload is Map
        ? (searchPayload['data'] as List<dynamic>? ?? const [])
        : const <dynamic>[];
    final animeIds = <int>{};
    for (final character in rows.whereType<Map>().take(3)) {
      final characterId = (character['mal_id'] as num?)?.toInt();
      if (characterId == null) continue;
      final full = await _http.get(
        Uri.parse('$_baseUrl/characters/$characterId/full'),
      );
      final data = full is Map ? full['data'] : null;
      if (data is! Map) continue;
      for (final credit in (data['anime'] as List<dynamic>? ?? const [])) {
        if (credit is! Map) continue;
        final anime = credit['anime'];
        if (anime is Map && anime['mal_id'] is num) {
          animeIds.add((anime['mal_id'] as num).toInt());
        }
        if (animeIds.length >= 8) break;
      }
      if (animeIds.length >= 8) break;
    }
    final results = <CatalogMedia>[];
    for (final animeId in animeIds.take(8)) {
      final media = await details('jikan', '$animeId');
      results.add(
        CatalogMedia.fromJson({
          ...media.toJson(),
          'characters': [
            {'name': characterName},
          ],
        }),
      );
    }
    return results;
  }

  @override
  Future<List<CatalogMedia>> recommendations(
    String source,
    String id, {
    int page = 1,
  }) async {
    final payload = await _http.get(
      Uri.parse('$_baseUrl/anime/$id/recommendations'),
    );
    final rows = payload is Map
        ? (payload['data'] as List<dynamic>? ?? const [])
        : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => row['entry'])
        .whereType<Map>()
        .map((row) => _mapMedia(row.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<CatalogMedia>> similar(
    String source,
    String id, {
    int page = 1,
  }) => recommendations(source, id, page: page);

  List<CatalogMedia> _mediaList(Object? payload) {
    final map = payload is Map ? payload : const {};
    return (map['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => _mapMedia(row.cast<String, dynamic>()))
        .toList();
  }

  CatalogMedia _mapMedia(Map<String, dynamic> row) {
    final malId = (row['mal_id'] as num?)?.toInt() ?? 0;
    final aired = row['aired'] as Map? ?? const {};
    final from = aired['from'] as String? ?? '';
    final to = aired['to'] as String? ?? '';
    final year = (row['year'] as num?)?.toInt() ?? _yearFromDate(from);
    final images = row['images'] as Map? ?? const {};
    final jpg = images['jpg'] as Map? ?? const {};
    final titles = (row['titles'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((title) => '${title['title'] ?? ''}'.trim())
        .where((title) => title.isNotEmpty)
        .toList();
    final english = '${row['title_english'] ?? ''}'.trim();
    final japanese = '${row['title_japanese'] ?? ''}'.trim();
    final mainTitle = english.isNotEmpty
        ? english
        : '${row['title'] ?? titles.firstOrNull ?? 'Без названия'}';
    final type = '${row['type'] ?? ''}'.toUpperCase();
    final episodes = (row['episodes'] as num?)?.toInt() ?? 0;
    final duration = _durationMinutes('${row['duration'] ?? ''}');
    final genres = _namedValues(row, const [
      'genres',
      'explicit_genres',
      'themes',
      'demographics',
    ]);
    final studios = _namedValues(row, const ['studios']);
    final relations = (row['relations'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (relation) => <String, Object?>{
            'relationType': '${relation['relation'] ?? ''}',
            'entries': (relation['entry'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map(
                  (entry) => {
                    'sourceId': '${entry['mal_id'] ?? ''}',
                    'title': '${entry['name'] ?? ''}',
                    'type': '${entry['type'] ?? ''}',
                    'url': entry['url'],
                  },
                )
                .toList(),
          },
        )
        .toList();
    final url = row['url'] as String?;
    return CatalogMedia(
      id: 4000000000 + malId,
      source: 'jikan',
      externalId: '$malId',
      externalIds: {'mal': '$malId'},
      title: mainTitle,
      originalTitle: '${row['title'] ?? ''}',
      englishTitle: english,
      nativeTitle: japanese,
      synonyms: {
        ...titles,
        ...(row['title_synonyms'] as List<dynamic>? ?? const [])
            .whereType<String>(),
      }.where((title) => title != mainTitle).toList(),
      year: year,
      endYear: _yearFromDate(to) == 0 ? null : _yearFromDate(to),
      kind: 'anime',
      format: type,
      genres: genres,
      tags: genres,
      countries: const ['JP'],
      originalLanguage: 'ja',
      posterUrl: (jpg['large_image_url'] ?? jpg['image_url']) as String?,
      backdropUrl: jpg['large_image_url'] as String?,
      description: cleanCatalogText('${row['synopsis'] ?? ''}'),
      rating: (row['score'] as num?)?.toDouble() ?? 0,
      voteCount: (row['scored_by'] as num?)?.toInt() ?? 0,
      popularity: _inverseRank(row['popularity']),
      runtimeMinutes: type == 'MOVIE' ? duration : 0,
      episodeCount: episodes,
      episodeRuntimeMinutes: type == 'MOVIE' ? 0 : duration,
      studios: studios,
      relations: relations,
      sourceUrls: [?url],
      isAdult: '${row['rating'] ?? ''}'.toUpperCase().startsWith('RX'),
    );
  }
}

class TvMazeCatalogProvider implements CatalogProvider {
  TvMazeCatalogProvider({
    required http.Client client,
    this.enabled = true,
    String baseUrl = 'https://api.tvmaze.com',
    Duration timeout = const Duration(seconds: 20),
    Future<void> Function(Duration duration)? delay,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _http = _ProviderHttp(
         provider: 'tvmaze',
         client: client,
         timeout: timeout,
         delay: delay,
       );

  @override
  String get name => 'tvmaze';
  @override
  bool get supportsCharacterSearch => false;
  @override
  final bool enabled;
  final String _baseUrl;
  final _ProviderHttp _http;

  @override
  bool supportsKind(String? kind) =>
      kind == null || const {'series', 'animatedSeries'}.contains(kind);

  @override
  bool supportsSource(String source) => source == 'tvmaze';

  @override
  Future<List<CatalogMedia>> search(CatalogProviderRequest request) async {
    final uri = Uri.parse(
      '$_baseUrl/search/shows',
    ).replace(queryParameters: {'q': request.query});
    final payload = await _http.get(uri);
    if (payload is! List) return const [];
    return payload
        .whereType<Map>()
        .map((entry) {
          final show = entry['show'];
          if (show is! Map) return null;
          return _mapShow(
            show.cast<String, dynamic>(),
            searchScore: (entry['score'] as num?)?.toDouble(),
          );
        })
        .whereType<CatalogMedia>()
        .toList();
  }

  @override
  Future<List<CatalogMedia>> popular(CatalogProviderRequest request) async {
    final page = (request.page - 1).clamp(0, 49);
    final payload = await _http.get(
      Uri.parse('$_baseUrl/shows').replace(queryParameters: {'page': '$page'}),
    );
    if (payload is! List) return const [];
    final items =
        payload
            .whereType<Map>()
            .map((show) => _mapShow(show.cast<String, dynamic>()))
            .toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));
    return items.take(25).toList();
  }

  @override
  Future<List<CatalogMedia>> discover(CatalogProviderRequest request) async {
    final candidates = await popular(request);
    return candidates.where((item) {
      if (request.yearFrom != null && item.year < request.yearFrom!) {
        return false;
      }
      if (request.yearTo != null && item.year > request.yearTo!) return false;
      if (request.genres.isNotEmpty &&
          !request.genres.any(
            (genre) => item.genres.any(
              (candidate) => candidate.toLowerCase() == genre.toLowerCase(),
            ),
          )) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<CatalogMedia> details(String source, String id) async {
    final payload = await _http.get(
      Uri.parse(
        '$_baseUrl/shows/$id?embed[]=episodes&embed[]=seasons&embed[]=cast',
      ),
    );
    if (payload is! Map) {
      throw const CatalogProviderException(
        'tvmaze',
        'invalid_response',
        'TVmaze вернул некорректный ответ.',
      );
    }
    return _mapShow(payload.cast<String, dynamic>());
  }

  @override
  Future<List<CatalogMedia>> searchByCharacter(
    String characterName, {
    int page = 1,
  }) async => const [];

  @override
  Future<List<CatalogMedia>> recommendations(
    String source,
    String id, {
    int page = 1,
  }) async => const [];

  @override
  Future<List<CatalogMedia>> similar(
    String source,
    String id, {
    int page = 1,
  }) async => const [];

  CatalogMedia _mapShow(Map<String, dynamic> row, {double? searchScore}) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    final image = row['image'] as Map? ?? const {};
    final ratingMap = row['rating'] as Map? ?? const {};
    final network = (row['network'] ?? row['webChannel']) as Map? ?? const {};
    final networkName = network['name'] is String
        ? network['name'] as String
        : null;
    final country = network['country'] as Map? ?? const {};
    final embedded = row['_embedded'] as Map? ?? const {};
    final episodes = (embedded['episodes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .toList();
    final seasons = (embedded['seasons'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (season) => <String, Object?>{
            'number': (season['number'] as num?)?.toInt() ?? 0,
            'episodeCount': episodes
                .where((episode) => episode['season'] == season['number'])
                .length,
            'name': season['name'] as String?,
          },
        )
        .where((season) => (season['number'] as int) > 0)
        .toList();
    final cast = (embedded['cast'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (credit) => <String, Object?>{
            'name': (credit['person'] as Map?)?['name'],
            'character': (credit['character'] as Map?)?['name'],
          },
        )
        .toList();
    final genres = (row['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final animated = genres.any(
      (genre) => genre.toLowerCase().contains('animation'),
    );
    final premiered = '${row['premiered'] ?? ''}';
    final ended = '${row['ended'] ?? ''}';
    final externals = (row['externals'] as Map? ?? const {}).map(
      (key, value) => MapEntry('$key', '$value'),
    )..removeWhere((key, value) => value == 'null' || value.isEmpty);
    final aliases = (row['akas'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((aka) => '${aka['name'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final url = row['url'] as String?;
    return CatalogMedia(
      id: 5000000000 + id,
      source: 'tvmaze',
      externalId: '$id',
      externalIds: {'tvmaze': '$id', ...externals},
      title: '${row['name'] ?? 'Без названия'}',
      originalTitle: '${row['name'] ?? ''}',
      synonyms: aliases,
      year: _yearFromDate(premiered),
      endYear: _yearFromDate(ended) == 0 ? null : _yearFromDate(ended),
      kind: animated ? 'animatedSeries' : 'series',
      format: '${row['type'] ?? 'series'}',
      genres: genres,
      countries: [if (country['code'] is String) country['code'] as String],
      originalLanguage: row['language'] as String?,
      posterUrl: (image['original'] ?? image['medium']) as String?,
      backdropUrl: image['original'] as String?,
      description: cleanCatalogText('${row['summary'] ?? ''}'),
      rating: (ratingMap['average'] as num?)?.toDouble() ?? 0,
      popularity: searchScore ?? ((row['weight'] as num?)?.toDouble() ?? 0),
      runtimeMinutes:
          ((row['averageRuntime'] ?? row['runtime']) as num?)?.toInt() ?? 0,
      seasonCount: seasons.length,
      episodeCount: episodes.length,
      episodeRuntimeMinutes:
          ((row['averageRuntime'] ?? row['runtime']) as num?)?.toInt() ?? 0,
      seasons: seasons,
      cast: cast,
      studios: [?networkName],
      sourceUrls: [?url],
    );
  }
}

class _ProviderHttp {
  _ProviderHttp({
    required this.provider,
    required this.client,
    required this.timeout,
    this.delay,
    this.minimumInterval = Duration.zero,
  });

  final String provider;
  final http.Client client;
  final Duration timeout;
  final Future<void> Function(Duration duration)? delay;
  final Duration minimumInterval;
  DateTime? _lastRequestAt;

  Future<Object?> get(Uri uri) async {
    await _throttle();
    var response = await client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    _lastRequestAt = DateTime.now();
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
      await (delay ?? Future<void>.delayed)(
        Duration(seconds: seconds.clamp(0, 30)),
      );
      response = await client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      _lastRequestAt = DateTime.now();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CatalogProviderException(
        provider,
        response.statusCode == 429 ? 'rate_limited' : 'http_error',
        '${_label(provider)} временно недоступен (${response.statusCode}).',
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw CatalogProviderException(
        provider,
        'invalid_json',
        '${_label(provider)} вернул некорректный JSON.',
      );
    }
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last == null || minimumInterval == Duration.zero) return;
    final remaining = minimumInterval - DateTime.now().difference(last);
    if (remaining > Duration.zero) {
      await (delay ?? Future<void>.delayed)(remaining);
    }
  }
}

List<String> _namedValues(Map<String, dynamic> row, List<String> fields) {
  final values = <String>[];
  for (final field in fields) {
    values.addAll(
      (row[field] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => '${entry['name'] ?? ''}'.trim())
          .where((name) => name.isNotEmpty),
    );
  }
  return values.toSet().toList();
}

int _yearFromDate(String value) =>
    value.length >= 4 ? int.tryParse(value.substring(0, 4)) ?? 0 : 0;

int _durationMinutes(String value) {
  final hours = RegExp(r'(\d+)\s*hr').firstMatch(value);
  final minutes = RegExp(r'(\d+)\s*min').firstMatch(value);
  return (int.tryParse(hours?.group(1) ?? '') ?? 0) * 60 +
      (int.tryParse(minutes?.group(1) ?? '') ?? 0);
}

double _inverseRank(Object? value) {
  final rank = value is num ? value.toDouble() : 0;
  return rank <= 0 ? 0 : 1000000 / rank;
}

String _label(String provider) => switch (provider) {
  'jikan' => 'Jikan',
  'tvmaze' => 'TVmaze',
  _ => provider,
};

const _jikanGenreIds = <String, int>{
  'action': 1,
  'adventure': 2,
  'comedy': 4,
  'drama': 8,
  'fantasy': 10,
  'horror': 14,
  'mystery': 7,
  'romance': 22,
  'science fiction': 24,
  'sports': 30,
  'supernatural': 37,
};
