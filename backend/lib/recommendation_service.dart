import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'catalog_gateway.dart';
import 'query_normalizer.dart';

const recommendationAlgorithmVersion = 'for-you-v1-2026-08';

typedef CatalogDetailsLookup =
    Future<Map<String, Object?>> Function(String source, String id);
typedef CatalogRelatedLookup =
    Future<CatalogSearchPage> Function(String source, String id, int page);
typedef CatalogDiscoverLookup =
    Future<CatalogSearchPage> Function(
      List<String> workTypes,
      List<String> genres,
      int page,
    );

class RecommendationSeed {
  const RecommendationSeed({
    required this.source,
    required this.sourceId,
    required this.weight,
  });

  final String source;
  final String sourceId;
  final int weight;

  String get identity => '$source:$sourceId';

  static RecommendationSeed? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final weight = int.tryParse(parts[2]);
    if (!_safeId.hasMatch(parts[0]) ||
        !_safeId.hasMatch(parts[1]) ||
        weight == null) {
      return null;
    }
    return RecommendationSeed(
      source: parts[0],
      sourceId: parts[1],
      weight: weight.clamp(-100, 100),
    );
  }
}

class RecommendationService {
  RecommendationService({
    required CatalogDetailsLookup details,
    required CatalogRelatedLookup related,
    required CatalogDiscoverLookup discover,
    Duration cacheTtl = const Duration(hours: 6),
  }) : _details = details,
       _related = related,
       _discover = discover,
       _cacheTtl = cacheTtl;

  factory RecommendationService.forCatalog(
    CatalogGateway catalog, {
    Duration cacheTtl = const Duration(hours: 6),
  }) => RecommendationService(
    details: catalog.details,
    related: (source, id, page) => catalog.related(
      source,
      id,
      page: page,
      includeRecommendations: true,
      includeSimilar: true,
    ),
    discover: (workTypes, genres, page) =>
        catalog.discover(workTypes: workTypes, genres: genres, page: page),
    cacheTtl: cacheTtl,
  );

  final CatalogDetailsLookup _details;
  final CatalogRelatedLookup _related;
  final CatalogDiscoverLookup _discover;
  final Duration _cacheTtl;
  final QueryNormalizer _normalizer = const QueryNormalizer();
  final Map<String, _RecommendationCacheEntry> _cache = {};

  Future<Map<String, Object?>> forYou({
    required List<RecommendationSeed> seeds,
    Set<String> excluded = const {},
    String? kind,
    int page = 1,
    bool refresh = false,
  }) async {
    final safePage = page.clamp(1, 50);
    final positiveSeeds = seeds.where((seed) => seed.weight > 0).toList()
      ..sort((left, right) => right.weight.compareTo(left.weight));
    if (positiveSeeds.isEmpty) {
      return {
        'results': const <Object?>[],
        'page': safePage,
        'hasMore': false,
        'warnings': const <String>[],
        'guidance':
            'Добавьте несколько произведений в избранное или поставьте им оценки.',
        'algorithmVersion': recommendationAlgorithmVersion,
      };
    }

    final cacheKey = _cacheKey(
      positiveSeeds,
      excluded: excluded,
      kind: kind,
      page: safePage,
    );
    final cached = _cache[cacheKey];
    if (!refresh && cached != null && !cached.expired) return cached.value;

    final candidates = <String, _ScoredRecommendation>{};
    final warnings = <String>{};
    for (final seed in positiveSeeds.take(6)) {
      Map<String, Object?> seedMedia;
      try {
        seedMedia = await _details(seed.source, seed.sourceId);
      } catch (error) {
        warnings.add('Не удалось открыть источник ${seed.identity}.');
        continue;
      }

      var relatedItems = const <Map<String, Object?>>[];
      try {
        final relatedPage = await _related(seed.source, seed.sourceId, 1);
        relatedItems = relatedPage.results;
        warnings.addAll(relatedPage.warnings);
      } catch (error) {
        warnings.add(
          'Рекомендации для ${_title(seedMedia)} временно недоступны.',
        );
      }

      if (relatedItems.isEmpty) {
        try {
          final discovered = await _discover(
            [_workType(seedMedia)],
            _strings(seedMedia['genres']).take(3).toList(),
            1,
          );
          relatedItems = discovered.results;
          warnings.addAll(discovered.warnings);
        } catch (_) {
          // A failed fallback should not discard results from other seeds.
        }
      }

      for (final candidate in relatedItems) {
        if (candidate['isAdult'] == true) continue;
        if (kind != null && kind != 'all' && candidate['kind'] != kind) {
          continue;
        }
        final identity = _identity(candidate);
        if (identity.isEmpty || identity == seed.identity) continue;
        if (excluded.contains(identity)) continue;
        final candidateKey = _dedupeKey(candidate, _normalizer);
        final scored = _score(seed, seedMedia, candidate);
        final existing = candidates[candidateKey];
        candidates[candidateKey] = existing == null
            ? scored
            : existing.merge(scored);
      }
    }

    final ranked = candidates.values.toList()
      ..sort((left, right) => right.score.compareTo(left.score));
    final diverse = _applyDiversity(ranked);
    const pageSize = 20;
    final start = (safePage - 1) * pageSize;
    final pageItems = start >= diverse.length
        ? const <_ScoredRecommendation>[]
        : diverse.skip(start).take(pageSize).toList();
    final value = <String, Object?>{
      'results': pageItems.map((item) => item.toJson()).toList(),
      'page': safePage,
      'hasMore': start + pageItems.length < diverse.length,
      'warnings': warnings.toList(),
      if (pageItems.isEmpty)
        'guidance': kind == null || kind == 'all'
            ? 'Добавьте ещё несколько произведений в избранное или поставьте им оценки.'
            : 'Добавьте несколько произведений этой категории в избранное или поставьте им оценки.',
      'algorithmVersion': recommendationAlgorithmVersion,
    };
    _cache[cacheKey] = _RecommendationCacheEntry(value, _cacheTtl);
    return value;
  }

  _ScoredRecommendation _score(
    RecommendationSeed seed,
    Map<String, Object?> source,
    Map<String, Object?> candidate,
  ) {
    final reasons = <String>['Потому что вам понравился ${_title(source)}'];
    var score = seed.weight * .55 + 24;
    final sourceGenres = _normalizedSet(source['genres']);
    final candidateGenres = _normalizedSet(candidate['genres']);
    final sharedGenres = sourceGenres.intersection(candidateGenres);
    if (sharedGenres.isNotEmpty) {
      score += math.min(18, sharedGenres.length * 6);
      reasons.add('Совпадают жанры: ${_displayList(sharedGenres)}');
    }
    final sharedTags = _normalizedSet(
      source['tags'],
    ).intersection(_normalizedSet(candidate['tags']));
    if (sharedTags.isNotEmpty) {
      score += math.min(12, sharedTags.length * 3);
      reasons.add('Похожие темы и атмосфера');
    }
    final sharedStudios = _normalizedSet(
      source['studios'],
    ).intersection(_normalizedSet(candidate['studios']));
    if (sharedStudios.isNotEmpty) {
      score += 8;
      reasons.add('От той же студии');
    }
    final sourceYear = _number(source['year']);
    final candidateYear = _number(candidate['year']);
    if (sourceYear > 0 && candidateYear > 0) {
      final distance = (sourceYear - candidateYear).abs();
      if (distance <= 5) score += 5;
    }
    if (source['kind'] == candidate['kind']) score += 4;
    score += math.min(5, _number(candidate['rating']) / 2);
    return _ScoredRecommendation(
      media: candidate,
      score: score.clamp(0, 100).toDouble(),
      reasons: reasons.take(3).toList(),
      seedIdentities: {seed.identity},
    );
  }

  List<_ScoredRecommendation> _applyDiversity(
    List<_ScoredRecommendation> ranked,
  ) {
    final franchiseCounts = <String, int>{};
    final result = <_ScoredRecommendation>[];
    for (final candidate in ranked) {
      final key = _franchiseKey(_title(candidate.media));
      if ((franchiseCounts[key] ?? 0) >= 2) continue;
      franchiseCounts[key] = (franchiseCounts[key] ?? 0) + 1;
      result.add(candidate);
    }
    return result;
  }

  String _cacheKey(
    List<RecommendationSeed> seeds, {
    required Set<String> excluded,
    required String? kind,
    required int page,
  }) {
    final payload = jsonEncode({
      'version': recommendationAlgorithmVersion,
      'seeds': [for (final seed in seeds) '${seed.identity}:${seed.weight}'],
      'excluded': excluded.toList()..sort(),
      'kind': kind,
      'page': page,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Set<String> _normalizedSet(Object? value) => _strings(
    value,
  ).map(_normalizer.normalize).where((item) => item.isNotEmpty).toSet();
}

class _ScoredRecommendation {
  const _ScoredRecommendation({
    required this.media,
    required this.score,
    required this.reasons,
    required this.seedIdentities,
  });

  final Map<String, Object?> media;
  final double score;
  final List<String> reasons;
  final Set<String> seedIdentities;

  _ScoredRecommendation merge(_ScoredRecommendation other) =>
      _ScoredRecommendation(
        media: media,
        score: math.min(100, score + other.score * .3),
        reasons: {...reasons, ...other.reasons}.take(4).toList(),
        seedIdentities: {...seedIdentities, ...other.seedIdentities},
      );

  Map<String, Object?> toJson() => {
    ...media,
    'recommendationScore': score.round(),
    'recommendationReasons': reasons,
    'recommendedFrom': seedIdentities.toList(),
  };
}

class _RecommendationCacheEntry {
  _RecommendationCacheEntry(this.value, Duration ttl)
    : expiresAt = DateTime.now().add(ttl);

  final Map<String, Object?> value;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

Iterable<String> _strings(Object? value) => value is List
    ? value.whereType<String>().map((item) => item.trim())
    : const <String>[];

num _number(Object? value) => value is num ? value : 0;

String _title(Map<String, Object?> media) =>
    '${media['title'] ?? media['originalTitle'] ?? 'произведение'}'.trim();

String _identity(Map<String, Object?> media) {
  final source = '${media['source'] ?? ''}'.trim();
  final id = '${media['externalId'] ?? ''}'.trim();
  return source.isEmpty || id.isEmpty ? '' : '$source:$id';
}

String _dedupeKey(Map<String, Object?> media, QueryNormalizer normalizer) {
  final externalIds = media['externalIds'];
  if (externalIds is Map) {
    for (final provider in const ['imdb', 'tmdb', 'mal', 'thetvdb']) {
      final value = '${externalIds[provider] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return '$provider:$value';
    }
  }
  return '${normalizer.normalize(_title(media))}:${media['year']}:${media['kind']}';
}

String _workType(Map<String, Object?> media) => switch (media['kind']) {
  'animatedSeries' => 'animated_series',
  final String kind when kind.isNotEmpty => kind,
  _ => 'movie',
};

String _displayList(Iterable<String> values) => values.take(2).join(' и ');

String _franchiseKey(String title) {
  final normalized = title
      .toLowerCase()
      .replaceAll(RegExp(r'[:\-–—].*$'), '')
      .replaceAll(RegExp(r'\b(season|сезон|part|часть)\s*\d+\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized.isEmpty ? title.toLowerCase() : normalized;
}

final RegExp _safeId = RegExp(r'^[a-zA-Z0-9_\-]{1,80}$');
