import 'dart:convert';

import 'ai_intent_cache.dart';
import 'ai_query_parser.dart';
import 'catalog_gateway.dart';
import 'remember_models.dart';

class RememberSearchService {
  const RememberSearchService({
    required this.catalog,
    required this.parser,
    required this.cache,
  });

  final CatalogGateway catalog;
  final AiParserController parser;
  final AiIntentCache cache;

  Future<Map<String, Object?>> search(RememberSearchRequest request) async {
    final filtersHash = rememberFiltersHash(request);
    var intent = await cache.read(request.normalizedQuery, filtersHash);
    final cacheHit = intent != null;
    if (intent == null) {
      intent = request.applyTo(await parser.parse(request));
      await cache.write(
        normalizedQuery: request.normalizedQuery,
        filtersHash: filtersHash,
        intent: intent,
        provider: parser.provider,
        model: parser.model,
      );
    }

    Map<String, Object?>? similar;
    final reference = request.similarTo;
    if (reference != null) {
      try {
        similar = await catalog.details(reference.source, reference.sourceId);
      } catch (_) {
        // Similarity feedback is optional and must not break the base search.
      }
    }
    final page = await catalog.discover(
      workTypes: intent.workTypes,
      yearFrom: intent.yearFrom,
      yearTo: intent.yearTo,
      genres: intent.genres,
      plotKeywords: intent.plotKeywords,
      countries: intent.countries,
    );
    final excluded = request.excluded.toSet();
    final candidates =
        page.results
            .where(_isVerifiedSource)
            .where(
              (item) =>
                  !excluded.contains('${item['source']}:${item['externalId']}'),
            )
            .map((item) => _scoreCandidate(item, intent!, similar: similar))
            .toList()
          ..sort(
            (a, b) =>
                (b['matchScore'] as num).compareTo(a['matchScore'] as num),
          );

    return {
      'intent': intent.toJson(),
      'results': candidates.take(30).toList(),
      'count': candidates.length.clamp(0, 30),
      'warnings': page.warnings,
      'providers': page.providers,
      'ai': {...parser.toJson(), 'cacheHit': cacheHit},
    };
  }

  Map<String, Object?> diagnostics() => parser.toJson();
}

Map<String, Object?> _scoreCandidate(
  Map<String, Object?> item,
  RememberSearchIntent intent, {
  Map<String, Object?>? similar,
}) {
  var score = .18;
  final reasons = <String>[];
  final kind = item['kind'] as String? ?? '';
  final normalizedKind = kind == 'animatedSeries' ? 'animated_series' : kind;
  if (intent.workTypes.isEmpty || intent.workTypes.contains(normalizedKind)) {
    score += .2;
    if (intent.workTypes.isNotEmpty) reasons.add('Подходящий тип произведения');
  }

  final year = (item['year'] as num?)?.toInt() ?? 0;
  if (year > 0) {
    final afterStart = intent.yearFrom == null || year >= intent.yearFrom!;
    final beforeEnd = intent.yearTo == null || year <= intent.yearTo!;
    if (afterStart && beforeEnd) {
      score += .18;
      if (intent.yearFrom != null || intent.yearTo != null) {
        reasons.add('Год попадает в указанный период');
      }
    } else if (intent.yearFrom != null || intent.yearTo != null) {
      score -= .12;
    }
  }

  final genres = (item['genres'] as List<dynamic>? ?? const [])
      .whereType<String>()
      .map(_normalizeGenre)
      .toSet();
  final wantedGenres = intent.genres.map(_normalizeGenre).toSet();
  final genreMatches = genres.intersection(wantedGenres);
  if (genreMatches.isNotEmpty) {
    score += (.07 * genreMatches.length).clamp(0, .2);
    reasons.add('Совпадают жанры: ${genreMatches.take(3).join(', ')}');
  }

  final haystack = [
    item['title'],
    item['subtitle'],
    item['description'],
    ...(item['tags'] as List<dynamic>? ?? const []),
  ].whereType<Object>().join(' ').toLowerCase();
  final keywordMatches = intent.plotKeywords.where((keyword) {
    return _keywordVariants(keyword).any(haystack.contains);
  }).toList();
  if (keywordMatches.isNotEmpty) {
    score += (.055 * keywordMatches.length).clamp(0, .27);
    reasons.add('Сюжет: ${keywordMatches.take(4).join(', ')}');
  } else if (intent.plotKeywords.isNotEmpty) {
    score += .03;
  }

  final itemCountries = (item['originCountries'] as List<dynamic>? ?? const [])
      .whereType<String>()
      .map((value) => value.toLowerCase())
      .toSet();
  final desiredCountries = intent.countries
      .expand(_countryVariants)
      .map((value) => value.toLowerCase())
      .toSet();
  if (itemCountries.intersection(desiredCountries).isNotEmpty) {
    score += .08;
    reasons.add('Совпадает страна производства');
  }

  if (intent.visualStyle != null && intent.visualStyle != 'unknown') {
    final variants = _keywordVariants(intent.visualStyle!);
    if (variants.any(haystack.contains)) {
      score += .05;
      reasons.add('Похожий визуальный формат');
    }
  }
  if (intent.negativeKeywords.any(
    (keyword) => _keywordVariants(keyword).any(haystack.contains),
  )) {
    score -= .18;
  }

  if (similar != null) {
    final similarKind = similar['kind'];
    if (similarKind == item['kind']) score += .05;
    final similarGenres = (similar['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map(_normalizeGenre)
        .toSet();
    if (similarGenres.intersection(genres).isNotEmpty) {
      score += .08;
      reasons.add('Похоже на выбранный вами результат');
    }
  }

  if (reasons.isEmpty) reasons.add('Подобрано по общим признакам описания');
  final source = item['source'] as String;
  final sourceId = item['externalId'].toString();
  return {
    'source': source,
    'sourceId': sourceId,
    'title': item['title'] as String,
    'originalTitle': item['subtitle'] as String? ?? '',
    'year': year,
    'type': normalizedKind,
    'posterUrl': item['posterUrl'] as String?,
    'overview': item['description'] as String? ?? '',
    'matchScore': score.clamp(0, 1),
    'matchReasons': reasons.take(5).toList(),
    'rating': ((item['rating'] as num?) ?? 0).toDouble(),
    'genres': (item['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  };
}

bool _isVerifiedSource(Map<String, Object?> item) {
  const sources = {'tmdb_movie', 'tmdb_tv', 'anilist'};
  return sources.contains(item['source']) &&
      item['externalId'] != null &&
      (item['title'] as String?)?.trim().isNotEmpty == true;
}

String _normalizeGenre(String value) {
  final normalized = value.trim().toLowerCase();
  return _genreAliases[normalized] ?? normalized;
}

Iterable<String> _keywordVariants(String keyword) sync* {
  final normalized = keyword.trim().toLowerCase();
  yield normalized;
  for (final variant in _keywordTranslations[normalized] ?? const <String>[]) {
    yield variant;
  }
}

Iterable<String> _countryVariants(String country) sync* {
  final normalized = country.trim().toLowerCase();
  yield normalized;
  for (final variant in _countryAliases[normalized] ?? const <String>[]) {
    yield variant;
  }
}

const _genreAliases = {
  'фантастика': 'science fiction',
  'sci-fi': 'science fiction',
  'приключения': 'adventure',
  'драма': 'drama',
  'фэнтези': 'fantasy',
  'боевик': 'action',
  'комедия': 'comedy',
  'детектив': 'mystery',
  'мелодрама': 'romance',
  'ужасы': 'horror',
};

const _keywordTranslations = <String, List<String>>{
  'teenagers': ['подрост'],
  'portals': ['портал'],
  'parallel world': ['другой мир', 'параллельн'],
  'mechanical creatures': ['механическ', 'робот'],
  'robots': ['робот'],
  'space': ['космос'],
  'school': ['школ'],
  'magic': ['магия', 'магическ'],
  'journey': ['путешеств'],
  'time travel': ['машин времени', 'путешеств во времени'],
  'monsters': ['монстр'],
  'animals': ['животн'],
  '2d': ['2д', 'рисован'],
  '3d': ['3д', 'компьютерная анимация'],
  'puppet': ['куколь', 'stop motion'],
};

const _countryAliases = <String, List<String>>{
  'japan': ['jp', 'япония'],
  'united states': ['us', 'сша'],
  'russia': ['ru', 'россия'],
  'france': ['fr', 'франция'],
  'united kingdom': ['gb', 'великобритания'],
  'south korea': ['kr', 'южная корея'],
  'china': ['cn', 'китай'],
};

String prettyIntent(RememberSearchIntent intent) =>
    const JsonEncoder.withIndent('  ').convert(intent.toJson());
