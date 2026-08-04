import 'dart:convert';
import 'dart:math' as math;

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
    final filtersHash = rememberFiltersHash(
      request,
      provider: parser.provider,
      model: parser.model,
    );
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
        // Feedback enrichment is optional; base search remains available.
      }
    }

    final evidence = <String, _CandidateEvidence>{};
    final warnings = <String>{};
    void collect(CatalogSearchPage page, {required String pool, String? term}) {
      warnings.addAll(page.warnings);
      for (final item in page.results.where(_isVerifiedSource)) {
        final key = '${item['source']}:${item['externalId']}';
        final current = evidence.putIfAbsent(
          key,
          () => _CandidateEvidence(item),
        );
        current.pools.add(pool);
        if (term != null) current.terms.add(term);
      }
    }

    final searchKind = _catalogKind(intent.workTypes);
    final titleTerms = {
      ...intent.titleFragments,
      ...intent.franchiseTerms,
      ...intent.searchVariants,
    }.where((term) => term.trim().length >= 2).take(4).toList();
    for (final term in titleTerms) {
      try {
        collect(
          await catalog.search(term, kind: searchKind),
          pool: 'title',
          term: term,
        );
      } on CatalogException catch (error) {
        warnings.add(error.message);
      }
    }

    if (intent.characterNames.isNotEmpty) {
      try {
        final page = await catalog.searchByCharacters(intent.characterNames);
        collect(page, pool: 'character');
        for (final candidate in evidence.values.where(
          (candidate) => candidate.pools.contains('character'),
        )) {
          candidate.characters.addAll(intent.characterNames);
        }
      } on CatalogException catch (error) {
        warnings.add(error.message);
      }
    }

    try {
      collect(
        await catalog.discover(
          workTypes: intent.workTypes,
          yearFrom: intent.yearFrom,
          yearTo: intent.yearTo,
          genres: intent.genres,
          plotKeywords: [
            ...intent.plotKeywords,
            ...intent.objects,
            ...intent.locations,
          ],
          countries: intent.countries,
        ),
        pool: 'filters',
      );
    } on CatalogException catch (error) {
      warnings.add(error.message);
    }

    final excluded = {
      ...request.excluded,
      if (reference != null) '${reference.source}:${reference.sourceId}',
    };
    final candidates =
        evidence.entries
            .where((entry) => !excluded.contains(entry.key))
            .map(
              (entry) =>
                  _scoreCandidate(entry.value, intent!, similar: similar),
            )
            .where((candidate) => (candidate['matchScore'] as num) >= 18)
            .toList()
          ..sort(
            (left, right) => (right['matchScore'] as num).compareTo(
              left['matchScore'] as num,
            ),
          );
    final results = candidates.take(30).toList();

    return {
      'algorithmVersion': rememberSearchAlgorithmVersion,
      'intent': intent.toJson(),
      'results': results,
      'count': results.length,
      'warnings': warnings.toList(),
      'providers': catalog.diagnostics,
      'ai': {...parser.toJson(), 'cacheHit': cacheHit},
      if (results.isEmpty)
        'guidance':
            'Совпадений с достаточной уверенностью нет. Добавьте имя героя, сцену, страну или более узкий период.',
    };
  }

  Map<String, Object?> diagnostics() => parser.toJson();
}

class _CandidateEvidence {
  _CandidateEvidence(this.item);

  final Map<String, Object?> item;
  final Set<String> pools = {};
  final Set<String> terms = {};
  final Set<String> characters = {};
}

Map<String, Object?> _scoreCandidate(
  _CandidateEvidence evidence,
  RememberSearchIntent intent, {
  Map<String, Object?>? similar,
}) {
  final item = evidence.item;
  final reasons = <String>[];
  final breakdown = <String, double>{};
  final kind = item['kind'] as String? ?? '';
  final normalizedKind = kind == 'animatedSeries' ? 'animated_series' : kind;
  final titleVariants = [
    item['title'],
    item['originalTitle'],
    item['subtitle'],
    item['englishTitle'],
    item['nativeTitle'],
    ...(item['synonyms'] as List<dynamic>? ?? const []),
  ].whereType<String>().map(_normalizeText).where((value) => value.isNotEmpty);

  final titleSignals = {
    ...intent.titleFragments,
    ...intent.franchiseTerms,
    ...intent.searchVariants,
    ...evidence.terms,
  }.map(_normalizeText).where((value) => value.isNotEmpty).toSet();
  var titleScore = 0.0;
  String? matchedTitle;
  for (final signal in titleSignals) {
    for (final candidate in titleVariants) {
      final score = candidate == signal
          ? 28.0
          : candidate.startsWith(signal) || signal.startsWith(candidate)
          ? 24.0
          : candidate.contains(signal) || signal.contains(candidate)
          ? 19.0
          : 0.0;
      if (score > titleScore) {
        titleScore = score;
        matchedTitle = signal;
      }
    }
  }
  if (titleScore == 0 && evidence.pools.contains('title')) titleScore = 9;
  breakdown['title'] = titleScore;
  if (matchedTitle != null) {
    reasons.add('Название совпадает с фрагментом «$matchedTitle»');
  }

  final characterSignals = intent.characterNames.map(_normalizeText).toSet();
  final itemCharacters = [
    ...evidence.characters,
    ...(item['characters'] as List<dynamic>? ?? const []).expand((entry) {
      if (entry is Map && entry['name'] is String) {
        return [entry['name'] as String];
      }
      if (entry is String) return [entry];
      return const <String>[];
    }),
  ].map(_normalizeText).toSet();
  final matchedCharacters = characterSignals.where(
    (signal) => itemCharacters.any(
      (candidate) => candidate.contains(signal) || signal.contains(candidate),
    ),
  );
  final characterScore = evidence.pools.contains('character')
      ? 30.0
      : matchedCharacters.isNotEmpty
      ? 26.0
      : 0.0;
  breakdown['characters'] = characterScore;
  if (characterScore > 0) {
    final label =
        (matchedCharacters.isNotEmpty ? matchedCharacters : characterSignals)
            .take(2)
            .join(', ');
    reasons.add('Найден упомянутый персонаж${label.isEmpty ? '' : ': $label'}');
  }

  final haystack = _searchableText(item);
  final keywordSignals = {
    ...intent.plotKeywords,
    ...intent.locations,
    ...intent.objects,
  };
  final keywordMatches = keywordSignals.where(
    (keyword) => _keywordVariants(keyword).any(haystack.contains),
  );
  final keywordScore = math.min(22.0, keywordMatches.length * 5.5);
  breakdown['keywords'] = keywordScore;
  if (keywordMatches.isNotEmpty) {
    reasons.add('Сюжетные детали: ${keywordMatches.take(4).join(', ')}');
  }

  var typeScore = 0.0;
  if (intent.workTypes.isNotEmpty) {
    if (_typeMatches(intent.workTypes, normalizedKind)) {
      typeScore = 8;
      reasons.add('Совпадает тип произведения');
    } else {
      typeScore = -10;
    }
  }
  breakdown['type'] = typeScore;

  final year = (item['year'] as num?)?.toInt() ?? 0;
  var yearScore = 0.0;
  if (year > 0 && (intent.yearFrom != null || intent.yearTo != null)) {
    final from = intent.yearFrom ?? 1888;
    final to = intent.yearTo ?? DateTime.now().year + 5;
    if (year >= from && year <= to) {
      yearScore = 8;
      reasons.add('Год $year входит в указанный период');
    } else if (year >= from - 3 && year <= to + 3) {
      yearScore = 3;
    } else {
      yearScore = -6;
    }
  }
  breakdown['year'] = yearScore;

  final genres = (item['genres'] as List<dynamic>? ?? const [])
      .whereType<String>()
      .map(_normalizeGenre)
      .toSet();
  final wantedGenres = intent.genres.map(_normalizeGenre).toSet();
  final genreMatches = genres.intersection(wantedGenres);
  final genreScore = math.min(8.0, genreMatches.length * 3.0);
  breakdown['genres'] = genreScore;
  if (genreMatches.isNotEmpty) {
    reasons.add('Совпадают жанры: ${genreMatches.take(3).join(', ')}');
  }

  final itemCountries = [
    ...(item['countries'] as List<dynamic>? ?? const []),
    ...(item['originCountries'] as List<dynamic>? ?? const []),
  ].whereType<String>().map((value) => value.toLowerCase()).toSet();
  final desiredCountries = intent.countries
      .expand(_countryVariants)
      .map((value) => value.toLowerCase())
      .toSet();
  final countryScore = itemCountries.intersection(desiredCountries).isNotEmpty
      ? 4.0
      : 0.0;
  breakdown['country'] = countryScore;
  if (countryScore > 0) reasons.add('Совпадает страна производства');

  var visualScore = 0.0;
  if (intent.visualStyle != null && intent.visualStyle != 'unknown') {
    if (_keywordVariants(intent.visualStyle!).any(haystack.contains)) {
      visualScore = 3;
      reasons.add('Совпадает визуальный формат');
    }
  }
  breakdown['visualStyle'] = visualScore;

  var similarScore = 0.0;
  if (similar != null) {
    if (similar['kind'] == item['kind']) similarScore += 2;
    final similarGenres = (similar['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map(_normalizeGenre)
        .toSet();
    if (similarGenres.intersection(genres).isNotEmpty) similarScore += 5;
    if (similarScore > 0) reasons.add('Похоже на отмеченный вами результат');
  }
  breakdown['similarity'] = similarScore;

  final negativeMatches = intent.negativeKeywords.where(
    (keyword) => _keywordVariants(keyword).any(haystack.contains),
  );
  final penalties = -math.min(20.0, negativeMatches.length * 10.0);
  breakdown['penalties'] = penalties;

  final rating = ((item['rating'] as num?) ?? 0).toDouble();
  final popularity = ((item['popularity'] as num?) ?? 0).toDouble();
  final catalogEvidence = math.min(
    2.0,
    (rating.clamp(0, 10) / 10) * 1.2 +
        (popularity <= 0
            ? 0
            : math.log(1 + popularity) / math.log(1000001) * .8),
  );
  breakdown['catalogEvidence'] = catalogEvidence;

  final total = breakdown.values.fold<double>(0, (sum, value) => sum + value);
  final matchScore = double.parse(total.clamp(0, 100).toStringAsFixed(1));
  breakdown['total'] = matchScore;
  if (reasons.isEmpty) {
    reasons.add('Низкая уверенность: совпало мало конкретных признаков');
  }
  final source = item['source'] as String;
  final sourceId = item['externalId'].toString();
  return {
    'source': source,
    'sourceId': sourceId,
    'title': item['title'] as String,
    'originalTitle':
        item['originalTitle'] as String? ?? item['subtitle'] as String? ?? '',
    'year': year,
    'type': normalizedKind,
    'posterUrl': item['posterUrl'] as String?,
    'overview': item['description'] as String? ?? '',
    'matchScore': matchScore,
    'scoreBreakdown': breakdown.map(
      (key, value) => MapEntry(key, double.parse(value.toStringAsFixed(1))),
    ),
    'matchReasons': reasons.take(6).toList(),
    'lowConfidence': matchScore < 35,
    'rating': rating,
    'genres': (item['genres'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  };
}

bool _isVerifiedSource(Map<String, Object?> item) {
  const sources = {'tmdb_movie', 'tmdb_tv', 'anilist', 'jikan', 'tvmaze'};
  return sources.contains(item['source']) &&
      item['externalId'] != null &&
      (item['title'] as String?)?.trim().isNotEmpty == true;
}

String? _catalogKind(List<String> workTypes) {
  if (workTypes.length != 1) return null;
  return workTypes.single == 'animated_series'
      ? 'animatedSeries'
      : workTypes.single;
}

bool _typeMatches(List<String> expected, String actual) {
  if (expected.contains(actual)) return true;
  if (actual == 'anime') {
    return expected.contains('animated_series') || expected.contains('cartoon');
  }
  if (actual == 'animated_series') {
    return expected.contains('anime') || expected.contains('cartoon');
  }
  return false;
}

String _searchableText(Map<String, Object?> item) => [
  item['title'],
  item['subtitle'],
  item['originalTitle'],
  item['englishTitle'],
  item['nativeTitle'],
  item['description'],
  ...(item['synonyms'] as List<dynamic>? ?? const []),
  ...(item['genres'] as List<dynamic>? ?? const []),
  ...(item['tags'] as List<dynamic>? ?? const []),
  ...(item['keywords'] as List<dynamic>? ?? const []),
  ...(item['characters'] as List<dynamic>? ?? const []).map(
    (entry) => entry is Map ? entry['name'] : entry,
  ),
].whereType<Object>().join(' ').toLowerCase().replaceAll('ё', 'е');

String _normalizeText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _normalizeGenre(String value) {
  final normalized = value.trim().toLowerCase();
  return _genreAliases[normalized] ?? normalized;
}

Iterable<String> _keywordVariants(String keyword) sync* {
  final normalized = keyword.trim().toLowerCase().replaceAll('ё', 'е');
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
  'mask': ['маск'],
  'sword': ['меч'],
  'ring': ['кольц'],
  'amulet': ['амулет'],
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
