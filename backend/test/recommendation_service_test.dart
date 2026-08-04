import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'favorite seeds produce explained, diverse real recommendations',
    () async {
      var relatedCalls = 0;
      final service = RecommendationService(
        details: (source, id) async => _media(
          source: source,
          id: id,
          title: id == '20' ? 'Naruto' : 'Attack on Titan',
          genres: const ['Action', 'Adventure'],
          studios: const ['Studio A'],
        ),
        related: (source, id, page) async {
          relatedCalls += 1;
          return CatalogSearchPage(
            results: [
              _media(
                source: relatedCalls == 1 ? 'anilist' : 'jikan',
                id: relatedCalls == 1 ? '101' : '501',
                title: 'Black Clover',
                genres: const ['Action', 'Adventure'],
                studios: const ['Studio A'],
                externalIds: const {'mal': '34572'},
              ),
              _media(
                source: 'anilist',
                id: '102',
                title: 'Adult result',
                genres: const ['Action'],
                isAdult: true,
              ),
            ],
            page: 1,
            hasMore: false,
            warnings: const [],
            providers: const {},
          );
        },
        discover: (types, genres, page) async => const CatalogSearchPage(
          results: [],
          page: 1,
          hasMore: false,
          warnings: [],
          providers: {},
        ),
      );

      final result = await service.forYou(
        seeds: const [
          RecommendationSeed(source: 'anilist', sourceId: '20', weight: 100),
          RecommendationSeed(source: 'anilist', sourceId: '21', weight: 90),
        ],
      );
      final rows = result['results']! as List<dynamic>;

      expect(relatedCalls, 2);
      expect(rows, hasLength(1));
      final first = (rows.single as Map).cast<String, Object?>();
      expect(first['title'], 'Black Clover');
      expect(first['recommendationScore'], 100);
      expect(
        first['recommendationReasons'],
        contains('Совпадают жанры: action и adventure'),
      );
      expect(result.toString(), isNot(contains('Adult result')));
    },
  );

  test('exclusions, kind filters and cache are part of the pipeline', () async {
    var relatedCalls = 0;
    final service = RecommendationService(
      details: (source, id) async => _media(
        source: source,
        id: id,
        title: 'Seed',
        genres: const ['Drama'],
      ),
      related: (source, id, page) async {
        relatedCalls += 1;
        return CatalogSearchPage(
          results: [
            _media(
              source: 'tmdb_movie',
              id: '1',
              title: 'Movie',
              kind: 'movie',
            ),
            _media(source: 'anilist', id: '2', title: 'Anime', kind: 'anime'),
          ],
          page: 1,
          hasMore: false,
          warnings: const [],
          providers: const {},
        );
      },
      discover: (types, genres, page) async => const CatalogSearchPage(
        results: [],
        page: 1,
        hasMore: false,
        warnings: [],
        providers: {},
      ),
    );
    const seeds = [
      RecommendationSeed(source: 'anilist', sourceId: '20', weight: 100),
    ];

    final first = await service.forYou(
      seeds: seeds,
      excluded: const {'anilist:2'},
      kind: 'movie',
    );
    final second = await service.forYou(
      seeds: seeds,
      excluded: const {'anilist:2'},
      kind: 'movie',
    );

    expect((first['results'] as List), hasLength(1));
    expect(second, same(first));
    expect(relatedCalls, 1);
  });

  test('empty signals return guidance without catalog calls', () async {
    final service = RecommendationService(
      details: (source, id) => throw StateError('must not run'),
      related: (source, id, page) => throw StateError('must not run'),
      discover: (types, genres, page) => throw StateError('must not run'),
    );

    final result = await service.forYou(seeds: const []);

    expect(result['results'], isEmpty);
    expect(result['guidance'], contains('избранное'));
  });

  test('compact seed parser accepts only bounded identifiers and weights', () {
    final seed = RecommendationSeed.tryParse('anilist:20:500');
    expect(seed, isNotNull);
    expect(seed!.weight, 100);
    expect(RecommendationSeed.tryParse('bad seed:20:10'), isNull);
    expect(RecommendationSeed.tryParse('anilist:20'), isNull);
  });
}

Map<String, Object?> _media({
  required String source,
  required String id,
  required String title,
  String kind = 'anime',
  List<String> genres = const [],
  List<String> studios = const [],
  bool isAdult = false,
  Map<String, String> externalIds = const {},
}) => {
  'id': int.tryParse(id) ?? id.hashCode,
  'source': source,
  'externalId': id,
  'title': title,
  'kind': kind,
  'genres': genres,
  'studios': studios,
  'year': 2020,
  'rating': 8.0,
  'isAdult': isAdult,
  'externalIds': externalIds,
};
