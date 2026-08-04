import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'catalog_gateway.dart';
import 'query_normalizer.dart';

const similarityAlgorithmVersion = 'similarity-v1-2026-08';

enum SimilarityMode { overall, plot, genres, atmosphere, characters }

typedef SimilarDetailsLookup =
    Future<Map<String, Object?>> Function(String source, String id);
typedef SimilarRelatedLookup =
    Future<CatalogSearchPage> Function(
      String source,
      String id,
      int page,
      bool recommendations,
      bool similar,
    );
typedef SimilarDiscoverLookup =
    Future<CatalogSearchPage> Function(
      List<String> workTypes,
      List<String> genres,
      int page,
    );

class SimilarityService {
  SimilarityService({
    required SimilarDetailsLookup details,
    required SimilarRelatedLookup related,
    required SimilarDiscoverLookup discover,
    Duration cacheTtl = const Duration(hours: 6),
  }) : _details = details,
       _related = related,
       _discover = discover,
       _cacheTtl = cacheTtl;

  factory SimilarityService.forCatalog(
    CatalogGateway catalog, {
    Duration cacheTtl = const Duration(hours: 6),
  }) => SimilarityService(
    details: catalog.details,
    related: (source, id, page, recommendations, similar) => catalog.related(
      source,
      id,
      page: page,
      includeRecommendations: recommendations,
      includeSimilar: similar,
    ),
    discover: (types, genres, page) =>
        catalog.discover(workTypes: types, genres: genres, page: page),
    cacheTtl: cacheTtl,
  );

  final SimilarDetailsLookup _details;
  final SimilarRelatedLookup _related;
  final SimilarDiscoverLookup _discover;
  final Duration _cacheTtl;
  final QueryNormalizer _normalizer = const QueryNormalizer();
  final Map<String, _SimilarityCacheEntry> _cache = {};

  Future<Map<String, Object?>> search({
    required String source,
    required String sourceId,
    SimilarityMode mode = SimilarityMode.overall,
    int page = 1,
    bool refresh = false,
  }) async {
    final safePage = page.clamp(1, 50);
    final cacheKey = sha256
        .convert(
          utf8.encode(
            '$similarityAlgorithmVersion:$source:$sourceId:${mode.name}:$safePage',
          ),
        )
        .toString();
    final cached = _cache[cacheKey];
    if (!refresh && cached != null && !cached.expired) return cached.value;

    final reference = await _details(source, sourceId);
    final warnings = <String>{};
    final evidence = <String, _SimilarEvidence>{};
    await _collectOfficial(
      source,
      sourceId,
      recommendations: true,
      similar: false,
      evidence: evidence,
      warnings: warnings,
    );
    await _collectOfficial(
      source,
      sourceId,
      recommendations: false,
      similar: true,
      evidence: evidence,
      warnings: warnings,
    );
    if (evidence.length < 8) {
      try {
        final fallback = await _discover(
          [_workType(reference)],
          _strings(reference['genres']).take(4).toList(),
          1,
        );
        warnings.addAll(fallback.warnings);
        for (final item in fallback.results) {
          _addEvidence(evidence, item, discovered: true);
        }
      } catch (_) {
        // Official related results remain valid if discovery is unavailable.
      }
    }

    final referenceIdentity = _identity(reference);
    final ranked = <_ScoredSimilar>[];
    for (final candidateEvidence in evidence.values) {
      final candidate = candidateEvidence.media;
      if (candidate['isAdult'] == true ||
          _identity(candidate) == referenceIdentity) {
        continue;
      }
      ranked.add(_score(reference, candidateEvidence, mode: mode));
    }
    ranked.sort((left, right) => right.score.compareTo(left.score));
    const pageSize = 20;
    final start = (safePage - 1) * pageSize;
    final pageItems = start >= ranked.length
        ? const <_ScoredSimilar>[]
        : ranked.skip(start).take(pageSize).toList();
    final value = <String, Object?>{
      'reference': reference,
      'mode': mode.name,
      'results': pageItems.map((item) => item.toJson(mode)).toList(),
      'page': safePage,
      'hasMore': start + pageItems.length < ranked.length,
      'warnings': warnings.toList(),
      if (pageItems.isEmpty)
        'guidance': 'Для выбранного режима похожие произведения не найдены.',
      'algorithmVersion': similarityAlgorithmVersion,
    };
    _cache[cacheKey] = _SimilarityCacheEntry(value, _cacheTtl);
    return value;
  }

  Future<void> _collectOfficial(
    String source,
    String id, {
    required bool recommendations,
    required bool similar,
    required Map<String, _SimilarEvidence> evidence,
    required Set<String> warnings,
  }) async {
    try {
      final page = await _related(source, id, 1, recommendations, similar);
      warnings.addAll(page.warnings);
      for (final item in page.results) {
        _addEvidence(
          evidence,
          item,
          recommended: recommendations,
          officiallySimilar: similar,
        );
      }
    } catch (error) {
      warnings.add(
        recommendations
            ? 'Официальные рекомендации временно недоступны.'
            : 'Официальный поиск похожих временно недоступен.',
      );
    }
  }

  void _addEvidence(
    Map<String, _SimilarEvidence> values,
    Map<String, Object?> item, {
    bool recommended = false,
    bool officiallySimilar = false,
    bool discovered = false,
  }) {
    final identity = _dedupeKey(item, _normalizer);
    final next = _SimilarEvidence(
      media: item,
      recommended: recommended,
      officiallySimilar: officiallySimilar,
      discovered: discovered,
    );
    final existing = values[identity];
    values[identity] = existing == null ? next : existing.merge(next);
  }

  _ScoredSimilar _score(
    Map<String, Object?> reference,
    _SimilarEvidence evidence, {
    required SimilarityMode mode,
  }) {
    final candidate = evidence.media;
    final breakdown = <String, double>{};
    final reasons = <String>[];
    var score = 0.0;

    final genreMatch = _overlap(reference['genres'], candidate['genres']);
    final tagMatch = _overlap(reference['tags'], candidate['tags']);
    final keywordMatch = _overlap(reference['keywords'], candidate['keywords']);
    final descriptionMatch = _descriptionSimilarity(
      '${reference['description'] ?? ''}',
      '${candidate['description'] ?? ''}',
    );
    final characterMatch = _mapNameOverlap(
      reference['characters'],
      candidate['characters'],
    );
    final castMatch = _mapNameOverlap(reference['cast'], candidate['cast']);
    final studioMatch = _overlap(reference['studios'], candidate['studios']);
    final countryMatch = _overlap(
      reference['countries'] ?? reference['originCountries'],
      candidate['countries'] ?? candidate['originCountries'],
    );

    final weights = switch (mode) {
      SimilarityMode.plot => const (16.0, 10.0, 26.0, 25.0, 5.0),
      SimilarityMode.genres => const (34.0, 24.0, 10.0, 8.0, 4.0),
      SimilarityMode.atmosphere => const (18.0, 30.0, 12.0, 20.0, 5.0),
      SimilarityMode.characters => const (12.0, 12.0, 12.0, 10.0, 32.0),
      SimilarityMode.overall => const (24.0, 18.0, 16.0, 14.0, 10.0),
    };
    breakdown['genres'] = genreMatch * weights.$1;
    breakdown['tags'] = tagMatch * weights.$2;
    breakdown['keywords'] = keywordMatch * weights.$3;
    breakdown['description'] = descriptionMatch * weights.$4;
    breakdown['characters'] = math.max(characterMatch, castMatch) * weights.$5;
    score += breakdown.values.fold(0, (sum, value) => sum + value);

    if (genreMatch > 0) {
      final shared = _normalizedSet(
        reference['genres'],
      ).intersection(_normalizedSet(candidate['genres']));
      reasons.add('Совпадают жанры: ${shared.take(2).join(' и ')}');
    }
    if (keywordMatch > 0 || descriptionMatch >= .12) {
      reasons.add('Похожий сюжет и темы');
    }
    if (tagMatch > 0) reasons.add('Похожая атмосфера');
    if (characterMatch > 0 || castMatch > 0) {
      reasons.add('Связанные персонажи или актёры');
    }
    if (studioMatch > 0) {
      breakdown['studio'] = 6;
      score += 6;
      reasons.add('От той же студии');
    }
    if (countryMatch > 0) {
      breakdown['country'] = 3;
      score += 3;
    }
    if (reference['originalLanguage'] != null &&
        reference['originalLanguage'] == candidate['originalLanguage']) {
      breakdown['language'] = 3;
      score += 3;
    }
    if (reference['format'] != null &&
        reference['format'] == candidate['format']) {
      breakdown['format'] = 4;
      score += 4;
    }
    if (reference['kind'] == candidate['kind']) {
      breakdown['kind'] = 4;
      score += 4;
    }
    final referenceYear = _number(reference['year']);
    final candidateYear = _number(candidate['year']);
    if (referenceYear > 0 && candidateYear > 0) {
      final yearScore = math.max(
        0,
        5 - (referenceYear - candidateYear).abs() / 4,
      );
      breakdown['year'] = yearScore.toDouble();
      score += yearScore;
    }
    if (evidence.recommended) {
      breakdown['officialRecommendation'] = 12;
      score += 12;
      reasons.add(
        reference['source'] == 'anilist'
            ? 'Рекомендовано пользователями AniList'
            : 'Рекомендовано каталогом',
      );
    }
    if (evidence.officiallySimilar) {
      breakdown['officialSimilar'] = 10;
      score += 10;
    }
    if (evidence.discovered) {
      breakdown['discoveryEvidence'] = 2;
      score += 2;
    }
    if (reasons.isEmpty) reasons.add('Совпадают данные каталога');
    return _ScoredSimilar(
      media: candidate,
      score: score.clamp(0, 100).toDouble(),
      reasons: reasons.toSet().take(4).toList(),
      breakdown: breakdown,
    );
  }

  double _overlap(Object? left, Object? right) {
    final first = _normalizedSet(left);
    final second = _normalizedSet(right);
    if (first.isEmpty || second.isEmpty) return 0;
    return first.intersection(second).length /
        math.max(first.length, second.length);
  }

  double _mapNameOverlap(Object? left, Object? right) {
    final first = _mapNames(left);
    final second = _mapNames(right);
    if (first.isEmpty || second.isEmpty) return 0;
    return first.intersection(second).length /
        math.max(first.length, second.length);
  }

  double _descriptionSimilarity(String left, String right) {
    final first = _words(left);
    final second = _words(right);
    if (first.isEmpty || second.isEmpty) return 0;
    return first.intersection(second).length /
        first.union(second).length.clamp(1, 100000);
  }

  Set<String> _words(String text) => _normalizer
      .normalize(text)
      .split(' ')
      .where((word) => word.length >= 4 && !_stopWords.contains(word))
      .toSet();

  Set<String> _normalizedSet(Object? value) => _strings(
    value,
  ).map(_normalizer.normalize).where((item) => item.isNotEmpty).toSet();

  Set<String> _mapNames(Object? value) => value is List
      ? value
            .whereType<Map>()
            .expand((entry) => [entry['name'], entry['character']])
            .whereType<String>()
            .map(_normalizer.normalize)
            .where((item) => item.isNotEmpty)
            .toSet()
      : const {};
}

class _SimilarEvidence {
  const _SimilarEvidence({
    required this.media,
    required this.recommended,
    required this.officiallySimilar,
    required this.discovered,
  });

  final Map<String, Object?> media;
  final bool recommended;
  final bool officiallySimilar;
  final bool discovered;

  _SimilarEvidence merge(_SimilarEvidence other) => _SimilarEvidence(
    media: media.length >= other.media.length ? media : other.media,
    recommended: recommended || other.recommended,
    officiallySimilar: officiallySimilar || other.officiallySimilar,
    discovered: discovered || other.discovered,
  );
}

class _ScoredSimilar {
  const _ScoredSimilar({
    required this.media,
    required this.score,
    required this.reasons,
    required this.breakdown,
  });

  final Map<String, Object?> media;
  final double score;
  final List<String> reasons;
  final Map<String, double> breakdown;

  Map<String, Object?> toJson(SimilarityMode mode) => {
    ...media,
    'similarityScore': score.round(),
    'similarityReasons': reasons,
    'similarityBreakdown': breakdown,
    'similarityMode': mode.name,
  };
}

class _SimilarityCacheEntry {
  _SimilarityCacheEntry(this.value, Duration ttl)
    : expiresAt = DateTime.now().add(ttl);

  final Map<String, Object?> value;
  final DateTime expiresAt;
  bool get expired => DateTime.now().isAfter(expiresAt);
}

Iterable<String> _strings(Object? value) => value is List
    ? value.whereType<String>().map((item) => item.trim())
    : const <String>[];

num _number(Object? value) => value is num ? value : 0;

String _identity(Map<String, Object?> media) {
  final source = '${media['source'] ?? ''}'.trim();
  final id = '${media['externalId'] ?? ''}'.trim();
  return '$source:$id';
}

String _dedupeKey(Map<String, Object?> media, QueryNormalizer normalizer) {
  final ids = media['externalIds'];
  if (ids is Map) {
    for (final provider in const ['imdb', 'tmdb', 'mal', 'thetvdb']) {
      final value = '${ids[provider] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return '$provider:$value';
    }
  }
  return '${normalizer.normalize('${media['title'] ?? ''}')}:${media['year']}:${media['kind']}';
}

String _workType(Map<String, Object?> media) => switch (media['kind']) {
  'animatedSeries' => 'animated_series',
  final String kind when kind.isNotEmpty => kind,
  _ => 'movie',
};

const _stopWords = {
  'который',
  'которая',
  'этого',
  'после',
  'через',
  'their',
  'about',
  'after',
  'with',
  'from',
  'that',
};
