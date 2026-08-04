import 'package:http/testing.dart';
import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'character search puts Naruto in the top five with real reasons',
    () async {
      final service = _service();

      final response = await service.search(
        const RememberSearchRequest(
          query: 'Аниме, где главным персонажем был Наруто',
        ),
      );
      final results = response['results']! as List<dynamic>;

      expect(results, isNotEmpty);
      expect(
        results.take(5).map((item) => (item as Map)['title']),
        contains('Naruto'),
      );
      final naruto = results.first as Map<String, Object?>;
      expect(naruto['source'], 'anilist');
      expect(naruto['matchScore'], inInclusiveRange(18, 100));
      expect(
        (naruto['matchReasons'] as List<dynamic>).join(' '),
        contains('персонаж'),
      );
      final breakdown = naruto['scoreBreakdown'] as Map<String, dynamic>;
      expect(breakdown['characters'], 30);
      expect(breakdown['total'], naruto['matchScore']);
    },
  );

  test(
    'a named villain changes candidates and removes generic popular data',
    () async {
      final service = _service();

      final response = await service.search(
        const RememberSearchRequest(
          query: 'Мультсериал, где злодея звали Фобос',
        ),
      );
      final results = response['results']! as List<dynamic>;

      expect(results, hasLength(1));
      expect((results.single as Map)['title'], 'W.I.T.C.H.');
      expect(response['algorithmVersion'], rememberSearchAlgorithmVersion);
      expect(response.toString(), isNot(contains('Generic Popular Show')));
    },
  );

  test('weak type-only candidates produce honest empty guidance', () async {
    final service = _service();

    final response = await service.search(
      const RememberSearchRequest(
        query: 'Сериал, почти ничего больше не помню',
      ),
    );

    expect(response['results'], isEmpty);
    expect(response['guidance'], contains('Добавьте'));
  });

  test('cache key includes feedback, provider, model and algorithm', () {
    const base = RememberSearchRequest(query: 'Достаточно длинное описание');
    const excluded = RememberSearchRequest(
      query: 'Достаточно длинное описание',
      excluded: ['anilist:20'],
    );

    final first = rememberFiltersHash(
      base,
      provider: 'gemini',
      model: 'gemini-3.5-flash-lite',
    );
    final withFeedback = rememberFiltersHash(
      excluded,
      provider: 'gemini',
      model: 'gemini-3.5-flash-lite',
    );
    final otherModel = rememberFiltersHash(
      base,
      provider: 'gemini',
      model: 'another-model',
    );
    final otherAlgorithm = rememberFiltersHash(
      base,
      provider: 'gemini',
      model: 'gemini-3.5-flash-lite',
      algorithmVersion: 'future-version',
    );

    expect({first, withFeedback, otherModel, otherAlgorithm}, hasLength(4));
  });
}

RememberSearchService _service() {
  final parser = createAiQueryParser(
    AiSettings.fromEnvironment(const {'AI_PROVIDER': 'none'}),
  );
  return RememberSearchService(
    catalog: _RememberCatalog(),
    parser: parser,
    cache: MemoryAiIntentCache(),
  );
}

class _RememberCatalog extends CatalogGateway {
  _RememberCatalog()
    : super(
        MockClient((request) async => throw StateError('Unexpected HTTP')),
        settings: const CatalogSettings(
          tmdbEnabled: false,
          aniListEnabled: false,
          jikanEnabled: false,
          tvMazeEnabled: false,
        ),
      );

  @override
  Map<String, Object?> get diagnostics => const {
    'anilist': {'provider': 'anilist', 'status': 'connected'},
  };

  @override
  Future<CatalogSearchPage> search(
    String query, {
    String? kind,
    int page = 1,
  }) async => _page(const []);

  @override
  Future<CatalogSearchPage> searchByCharacters(
    List<String> characterNames, {
    int page = 1,
  }) async {
    final normalized = characterNames.join(' ').toLowerCase();
    if (normalized.contains('naruto')) return _page([_naruto]);
    if (normalized.contains('phobos') || normalized.contains('фобос')) {
      return _page([_witch]);
    }
    return _page(const []);
  }

  @override
  Future<CatalogSearchPage> discover({
    required List<String> workTypes,
    int? yearFrom,
    int? yearTo,
    List<String> genres = const [],
    List<String> plotKeywords = const [],
    List<String> countries = const [],
    int page = 1,
  }) async => _page([_generic]);

  @override
  Future<Map<String, Object?>> details(String source, String id) async =>
      throw CatalogException('No similar details', 404);
}

CatalogSearchPage _page(List<Map<String, Object?>> results) =>
    CatalogSearchPage(
      results: results,
      page: 1,
      hasMore: false,
      warnings: const [],
      providers: const {},
    );

final _naruto = <String, Object?>{
  'id': 3000000020,
  'source': 'anilist',
  'externalId': '20',
  'title': 'Naruto',
  'originalTitle': 'Naruto',
  'description': 'A young ninja seeks recognition in his village.',
  'year': 2002,
  'kind': 'anime',
  'rating': 8.0,
  'popularity': 500000.0,
  'genres': ['Action', 'Adventure'],
  'characters': [
    {'name': 'Naruto Uzumaki'},
  ],
};

final _witch = <String, Object?>{
  'id': 2000000100,
  'source': 'tmdb_tv',
  'externalId': '100',
  'title': 'W.I.T.C.H.',
  'originalTitle': 'W.I.T.C.H.',
  'description': 'Animated fantasy series with Prince Phobos as the villain.',
  'year': 2004,
  'kind': 'animatedSeries',
  'rating': 7.5,
  'popularity': 1000.0,
  'genres': ['Animation', 'Fantasy'],
  'characters': [
    {'name': 'Prince Phobos'},
  ],
};

final _generic = <String, Object?>{
  'id': 3000000999,
  'source': 'anilist',
  'externalId': '999',
  'title': 'Generic Popular Show',
  'originalTitle': 'Generic Popular Show',
  'description': 'A popular catalog result without matching details.',
  'year': 2020,
  'kind': 'series',
  'rating': 10.0,
  'popularity': 9999999.0,
  'genres': ['Drama'],
};
