import 'dart:convert';

abstract interface class CatalogProvider {
  String get name;
  bool get enabled;
  bool get supportsCharacterSearch;
  bool supportsKind(String? kind);
  bool supportsSource(String source);

  Future<List<CatalogMedia>> search(CatalogProviderRequest request);
  Future<List<CatalogMedia>> popular(CatalogProviderRequest request);
  Future<List<CatalogMedia>> discover(CatalogProviderRequest request);
  Future<List<CatalogMedia>> searchByCharacter(
    String characterName, {
    int page = 1,
  });
  Future<List<CatalogMedia>> recommendations(
    String source,
    String id, {
    int page = 1,
  });
  Future<List<CatalogMedia>> similar(String source, String id, {int page = 1});
  Future<CatalogMedia> details(String source, String id);
}

class CatalogProviderException implements Exception {
  const CatalogProviderException(
    this.provider,
    this.code,
    this.userMessage, {
    this.statusCode = 502,
    this.retryable = true,
  });

  final String provider;
  final String code;
  final String userMessage;
  final int statusCode;
  final bool retryable;

  @override
  String toString() => userMessage;
}

class CatalogProviderRequest {
  const CatalogProviderRequest({
    this.query = '',
    this.kind,
    this.page = 1,
    this.yearFrom,
    this.yearTo,
    this.genres = const [],
    this.plotKeywords = const [],
    this.countries = const [],
    this.workTypes = const [],
  });

  final String query;
  final String? kind;
  final int page;
  final int? yearFrom;
  final int? yearTo;
  final List<String> genres;
  final List<String> plotKeywords;
  final List<String> countries;
  final List<String> workTypes;
}

class CatalogMedia {
  CatalogMedia({
    required this.id,
    required this.source,
    required this.externalId,
    required this.title,
    required this.kind,
    this.externalIds = const {},
    this.originalTitle = '',
    this.englishTitle = '',
    this.nativeTitle = '',
    this.synonyms = const [],
    this.year = 0,
    this.endYear,
    this.format,
    this.genres = const [],
    this.tags = const [],
    this.keywords = const [],
    this.countries = const [],
    this.originalLanguage,
    this.posterUrl,
    this.backdropUrl,
    this.description = '',
    this.rating = 0,
    this.voteCount = 0,
    this.popularity = 0,
    this.runtimeMinutes = 0,
    this.seasonCount = 0,
    this.episodeCount = 0,
    this.episodeRuntimeMinutes = 0,
    this.seasons = const [],
    this.characters = const [],
    this.cast = const [],
    this.studios = const [],
    this.relations = const [],
    this.sourceUrls = const [],
    this.isAdult = false,
    List<Map<String, Object?>>? provenance,
    this.dedupeConfidence,
  }) : provenance =
           provenance ??
           [
             {'source': source, 'externalId': externalId},
           ];

  final int id;
  final String source;
  final String externalId;
  final Map<String, String> externalIds;
  final String title;
  final String originalTitle;
  final String englishTitle;
  final String nativeTitle;
  final List<String> synonyms;
  final int year;
  final int? endYear;
  final String kind;
  final String? format;
  final List<String> genres;
  final List<String> tags;
  final List<String> keywords;
  final List<String> countries;
  final String? originalLanguage;
  final String? posterUrl;
  final String? backdropUrl;
  final String description;
  final double rating;
  final int voteCount;
  final double popularity;
  final int runtimeMinutes;
  final int seasonCount;
  final int episodeCount;
  final int episodeRuntimeMinutes;
  final List<Map<String, Object?>> seasons;
  final List<Map<String, Object?>> characters;
  final List<Map<String, Object?>> cast;
  final List<String> studios;
  final List<Map<String, Object?>> relations;
  final List<String> sourceUrls;
  final bool isAdult;
  final List<Map<String, Object?>> provenance;
  final double? dedupeConfidence;

  Iterable<String> get titleVariants sync* {
    yield title;
    if (originalTitle.isNotEmpty) yield originalTitle;
    if (englishTitle.isNotEmpty) yield englishTitle;
    if (nativeTitle.isNotEmpty) yield nativeTitle;
    yield* synonyms;
  }

  factory CatalogMedia.fromJson(Map<String, Object?> json) => CatalogMedia(
    id: _asInt(json['id']),
    source: _asString(json['source']),
    externalId: _asString(json['externalId']),
    externalIds: _stringMap(json['externalIds']),
    title: _asString(json['title'], fallback: 'Без названия'),
    originalTitle: _asString(
      json['originalTitle'],
      fallback: _asString(json['subtitle']),
    ),
    englishTitle: _asString(json['englishTitle']),
    nativeTitle: _asString(json['nativeTitle']),
    synonyms: _stringList(json['synonyms']),
    year: _asInt(json['year']),
    endYear: _nullableInt(json['endYear']),
    kind: _asString(json['kind'], fallback: 'movie'),
    format: _nullableString(json['format']),
    genres: _stringList(json['genres']),
    tags: _stringList(json['tags']),
    keywords: _stringList(json['keywords']),
    countries: _stringList(json['countries'] ?? json['originCountries']),
    originalLanguage: _nullableString(json['originalLanguage']),
    posterUrl: _nullableString(json['posterUrl']),
    backdropUrl: _nullableString(json['backdropUrl']),
    description: cleanCatalogText(_asString(json['description'])),
    rating: _asDouble(json['rating']),
    voteCount: _asInt(json['voteCount']),
    popularity: _asDouble(json['popularity']),
    runtimeMinutes: _asInt(json['runtimeMinutes']),
    seasonCount: _asInt(json['seasonCount']),
    episodeCount: _asInt(json['episodeCount']),
    episodeRuntimeMinutes: _asInt(json['episodeRuntimeMinutes']),
    seasons: _mapList(json['seasons']),
    characters: _mapList(json['characters']),
    cast: _mapList(json['cast']),
    studios: _stringList(json['studios']),
    relations: _mapList(json['relations']),
    sourceUrls: _stringList(json['sourceUrls']),
    isAdult: json['isAdult'] == true || json['adult'] == true,
    provenance: json['provenance'] == null
        ? null
        : _mapList(json['provenance']),
    dedupeConfidence: json['dedupeConfidence'] is num
        ? (json['dedupeConfidence'] as num).toDouble()
        : null,
  );

  CatalogMedia merge(CatalogMedia other, {required double confidence}) {
    final preferred = _sourceWeight(source) >= _sourceWeight(other.source)
        ? this
        : other;
    final secondary = identical(preferred, this) ? other : this;
    return CatalogMedia(
      id: preferred.id,
      source: preferred.source,
      externalId: preferred.externalId,
      externalIds: {...secondary.externalIds, ...preferred.externalIds},
      title: preferred.title,
      originalTitle: _firstText(
        preferred.originalTitle,
        secondary.originalTitle,
      ),
      englishTitle: _firstText(preferred.englishTitle, secondary.englishTitle),
      nativeTitle: _firstText(preferred.nativeTitle, secondary.nativeTitle),
      synonyms: _uniqueStrings([
        ...preferred.synonyms,
        ...secondary.titleVariants,
        ...secondary.synonyms,
      ]).where((value) => value != preferred.title).toList(),
      year: preferred.year != 0 ? preferred.year : secondary.year,
      endYear: preferred.endYear ?? secondary.endYear,
      kind: preferred.kind,
      format: preferred.format ?? secondary.format,
      genres: _uniqueStrings([...preferred.genres, ...secondary.genres]),
      tags: _uniqueStrings([...preferred.tags, ...secondary.tags]),
      keywords: _uniqueStrings([...preferred.keywords, ...secondary.keywords]),
      countries: _uniqueStrings([
        ...preferred.countries,
        ...secondary.countries,
      ]),
      originalLanguage:
          preferred.originalLanguage ?? secondary.originalLanguage,
      posterUrl: preferred.posterUrl ?? secondary.posterUrl,
      backdropUrl: preferred.backdropUrl ?? secondary.backdropUrl,
      description: preferred.description.length >= secondary.description.length
          ? preferred.description
          : secondary.description,
      rating: preferred.rating > 0 ? preferred.rating : secondary.rating,
      voteCount: preferred.voteCount > 0
          ? preferred.voteCount
          : secondary.voteCount,
      popularity: preferred.popularity > secondary.popularity
          ? preferred.popularity
          : secondary.popularity,
      runtimeMinutes: preferred.runtimeMinutes > 0
          ? preferred.runtimeMinutes
          : secondary.runtimeMinutes,
      seasonCount: preferred.seasonCount > 0
          ? preferred.seasonCount
          : secondary.seasonCount,
      episodeCount: preferred.episodeCount > 0
          ? preferred.episodeCount
          : secondary.episodeCount,
      episodeRuntimeMinutes: preferred.episodeRuntimeMinutes > 0
          ? preferred.episodeRuntimeMinutes
          : secondary.episodeRuntimeMinutes,
      seasons: preferred.seasons.isNotEmpty
          ? preferred.seasons
          : secondary.seasons,
      characters: _uniqueMaps([
        ...preferred.characters,
        ...secondary.characters,
      ]),
      cast: _uniqueMaps([...preferred.cast, ...secondary.cast]),
      studios: _uniqueStrings([...preferred.studios, ...secondary.studios]),
      relations: _uniqueMaps([...preferred.relations, ...secondary.relations]),
      sourceUrls: _uniqueStrings([
        ...preferred.sourceUrls,
        ...secondary.sourceUrls,
      ]),
      isAdult: preferred.isAdult || secondary.isAdult,
      provenance: _uniqueMaps([
        ...preferred.provenance,
        ...secondary.provenance,
      ]),
      dedupeConfidence: confidence,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'externalId': externalId,
    'externalIds': externalIds,
    'title': title,
    'subtitle': originalTitle,
    'originalTitle': originalTitle,
    'englishTitle': englishTitle,
    'nativeTitle': nativeTitle,
    'synonyms': synonyms,
    'year': year,
    'endYear': endYear,
    'kind': kind,
    'format': format,
    'genres': genres,
    'tags': tags,
    'keywords': keywords,
    'countries': countries,
    'originCountries': countries,
    'originalLanguage': originalLanguage,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'description': description,
    'rating': rating,
    'voteCount': voteCount,
    'popularity': popularity,
    'runtimeMinutes': runtimeMinutes,
    'seasonCount': seasonCount,
    'episodeCount': episodeCount,
    'episodeRuntimeMinutes': episodeRuntimeMinutes,
    'seasons': seasons,
    'characters': characters,
    'cast': cast,
    'studios': studios,
    'relations': relations,
    'sourceUrls': sourceUrls,
    'isAdult': isAdult,
    'provenance': provenance,
    if (dedupeConfidence != null) 'dedupeConfidence': dedupeConfidence,
  };
}

String cleanCatalogText(String value) => value
    .replaceAll(RegExp('<br\\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
    .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _sourceWeight(String source) => switch (source) {
  'tmdb_movie' || 'tmdb_tv' => 5,
  'anilist' => 4,
  'jikan' => 3,
  'tvmaze' => 3,
  _ => 1,
};

String _firstText(String first, String second) =>
    first.trim().isNotEmpty ? first : second;

List<String> _uniqueStrings(Iterable<String> values) {
  final seen = <String>{};
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .where((value) => seen.add(value.toLowerCase()))
      .toList();
}

List<Map<String, Object?>> _uniqueMaps(Iterable<Map<String, Object?>> values) {
  final seen = <String>{};
  return values.where((value) => seen.add(jsonEncode(value))).toList();
}

String _asString(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String? _nullableString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int _asInt(Object? value) => value is num ? value.toInt() : 0;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().map((item) => item.trim()).toList()
    : const [];

Map<String, String> _stringMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry('$key', '$item'))
    : const {};

List<Map<String, Object?>> _mapList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : const [];
