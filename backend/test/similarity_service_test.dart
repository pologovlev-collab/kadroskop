import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  test('plot and genre modes apply different deterministic weights', () async {
    final service = _service();

    final plot = await service.search(
      source: 'tmdb_movie',
      sourceId: '10',
      mode: SimilarityMode.plot,
    );
    final genres = await service.search(
      source: 'tmdb_movie',
      sourceId: '10',
      mode: SimilarityMode.genres,
    );

    expect(((plot['results'] as List).first as Map)['title'], 'Island Mystery');
    expect(
      ((genres['results'] as List).first as Map)['title'],
      'City Survival',
    );
    expect(
      ((plot['results'] as List).first as Map)['similarityReasons'],
      contains('Похожий сюжет и темы'),
    );
  });

  test(
    'deduplicates official evidence and removes self and adult media',
    () async {
      final service = _service();
      final result = await service.search(source: 'tmdb_movie', sourceId: '10');
      final rows = result['results'] as List<dynamic>;

      expect(
        rows.where((row) => (row as Map)['title'] == 'Island Mystery'),
        hasLength(1),
      );
    expect(rows.toString(), isNot(contains('Adult Duplicate')));
    expect(rows.toString(), isNot(contains('Reference Work')));
      final island =
          rows.firstWhere((row) => (row as Map)['title'] == 'Island Mystery')
              as Map;
      expect(
        (island['similarityBreakdown'] as Map),
        contains('officialRecommendation'),
      );
      expect(
        (island['similarityBreakdown'] as Map),
        contains('officialSimilar'),
      );
    },
  );
}

SimilarityService _service() => SimilarityService(
  details: (source, id) async => _reference,
  related: (source, id, page, recommendations, similar) async =>
      CatalogSearchPage(
        results: recommendations
            ? [_plotCandidate, _genreCandidate, _adultCandidate]
            : [
                {..._plotCandidate, 'source': 'tvmaze', 'externalId': '501'},
                _reference,
              ],
        page: 1,
        hasMore: false,
        warnings: const [],
        providers: const {},
      ),
  discover: (types, genres, page) async => const CatalogSearchPage(
    results: [],
    page: 1,
    hasMore: false,
    warnings: [],
    providers: {},
  ),
);

const _reference = <String, Object?>{
  'id': 1000000010,
  'source': 'tmdb_movie',
  'externalId': '10',
  'externalIds': {'imdb': 'tt0010'},
  'title': 'Reference Work',
  'kind': 'movie',
  'year': 2020,
  'genres': ['Thriller', 'Drama'],
  'keywords': ['island', 'mystery', 'survival'],
  'tags': ['dark'],
  'description': 'People survive on an island and uncover a mystery.',
};

const _plotCandidate = <String, Object?>{
  'id': 1000000011,
  'source': 'tmdb_movie',
  'externalId': '11',
  'externalIds': {'imdb': 'tt0011'},
  'title': 'Island Mystery',
  'kind': 'movie',
  'year': 2021,
  'genres': ['Adventure'],
  'keywords': ['island', 'mystery', 'survival'],
  'description': 'A group must survive on an island and solve a mystery.',
};

const _genreCandidate = <String, Object?>{
  'id': 1000000012,
  'source': 'tmdb_movie',
  'externalId': '12',
  'externalIds': {'imdb': 'tt0012'},
  'title': 'City Survival',
  'kind': 'movie',
  'year': 2019,
  'genres': ['Thriller', 'Drama'],
  'keywords': ['city'],
  'description': 'A quiet urban character drama.',
};

const _adultCandidate = <String, Object?>{
  'id': 1000000013,
  'source': 'tmdb_movie',
  'externalId': '13',
  'title': 'Adult Duplicate',
  'kind': 'movie',
  'genres': ['Thriller'],
  'isAdult': true,
};
