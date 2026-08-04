import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  test('Jikan maps a real anime DTO and retries 429 only once', () async {
    var calls = 0;
    final provider = JikanCatalogProvider(
      client: MockClient((request) async {
        calls += 1;
        expect(request.url.path, '/v4/anime');
        expect(request.url.queryParameters['q'], 'Naruto');
        if (calls == 1) {
          return http.Response(
            '{"status":429}',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return _jsonResponse(_jikanSearch);
      }),
      delay: (_) async {},
    );

    final results = await provider.search(
      const CatalogProviderRequest(query: 'Naruto'),
    );

    expect(calls, 2);
    expect(results, hasLength(1));
    final anime = results.single;
    expect(anime.source, 'jikan');
    expect(anime.externalIds['mal'], '20');
    expect(anime.title, 'Naruto');
    expect(anime.nativeTitle, 'ナルト');
    expect(anime.posterUrl, 'https://img.test/naruto-large.jpg');
    expect(anime.episodeCount, 220);
    expect(anime.seasons, isEmpty);
    expect(anime.studios, contains('Studio Pierrot'));
  });

  test('TVmaze maps show, episodes, seasons and cast', () async {
    final provider = TvMazeCatalogProvider(
      client: MockClient((request) async {
        expect(request.url.path, '/shows/216');
        return http.Response(jsonEncode(_tvMazeDetails), 200);
      }),
    );

    final show = await provider.details('tvmaze', '216');

    expect(show.title, 'Rick and Morty');
    expect(show.source, 'tvmaze');
    expect(show.externalIds['imdb'], 'tt2861424');
    expect(show.posterUrl, 'https://img.test/rick-original.jpg');
    expect(show.episodeCount, 2);
    expect(show.seasonCount, 1);
    expect(show.seasons.single['episodeCount'], 2);
    expect(show.cast.single['character'], 'Rick Sanchez');
    expect(show.description, isNot(contains('<b>')));
  });

  test('gateway deduplicates AniList and Jikan with provenance', () async {
    final gateway = CatalogGateway(
      MockClient((request) async {
        if (request.url.host == 'graphql.anilist.co') {
          return _jsonResponse(_aniListSearch);
        }
        if (request.url.host == 'api.jikan.moe') {
          return _jsonResponse(_jikanSearch);
        }
        return http.Response('{}', 404);
      }),
      settings: const CatalogSettings(tmdbEnabled: false, tvMazeEnabled: false),
    );

    final page = await gateway.search('Naruto', kind: 'anime');

    expect(page.results, hasLength(1));
    final result = page.results.single;
    expect(result['source'], 'anilist');
    expect((result['externalIds'] as Map)['mal'], '20');
    expect((result['provenance'] as List), hasLength(2));
    expect(result['dedupeConfidence'], greaterThanOrEqualTo(.9));
  });

  test('AniList character pool returns verified media', () async {
    final gateway = CatalogGateway(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['query'], contains('SearchCharacters'));
        expect((body['variables'] as Map)['search'], 'Naruto Uzumaki');
        return _jsonResponse({
          'data': {
            'Page': {
              'characters': [
                {
                  'name': {'full': 'Naruto Uzumaki', 'native': 'うずまきナルト'},
                  'media': {
                    'nodes': (_aniListSearch['data']! as Map)['Page']['media'],
                  },
                },
              ],
            },
          },
        });
      }),
      settings: const CatalogSettings(
        tmdbEnabled: false,
        jikanEnabled: false,
        tvMazeEnabled: false,
      ),
    );

    final page = await gateway.searchByCharacters(['Naruto Uzumaki']);

    expect(page.results, hasLength(1));
    expect(page.results.single['title'], 'Naruto');
    expect(
      ((page.results.single['characters'] as List).single as Map)['name'],
      'Naruto Uzumaki',
    );
  });
}

http.Response _jsonResponse(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final _jikanSearch = {
  'data': [
    {
      'mal_id': 20,
      'url': 'https://myanimelist.net/anime/20/Naruto',
      'title': 'Naruto',
      'title_english': 'Naruto',
      'title_japanese': 'ナルト',
      'titles': [
        {'type': 'Default', 'title': 'Naruto'},
      ],
      'title_synonyms': ['NARUTO'],
      'type': 'TV',
      'episodes': 220,
      'duration': '23 min per ep',
      'year': 2002,
      'aired': {'from': '2002-10-03T00:00:00+00:00', 'to': '2007-02-08'},
      'score': 8.0,
      'scored_by': 2000000,
      'popularity': 8,
      'synopsis': '<b>Ninja</b> adventure',
      'images': {
        'jpg': {
          'image_url': 'https://img.test/naruto.jpg',
          'large_image_url': 'https://img.test/naruto-large.jpg',
        },
      },
      'genres': [
        {'name': 'Action'},
      ],
      'themes': [
        {'name': 'Martial Arts'},
      ],
      'studios': [
        {'name': 'Studio Pierrot'},
      ],
      'relations': const [],
    },
  ],
};

final _aniListSearch = {
  'data': {
    'Page': {
      'media': [
        {
          'id': 20,
          'idMal': 20,
          'title': {'romaji': 'Naruto', 'english': 'Naruto', 'native': 'ナルト'},
          'synonyms': ['NARUTO'],
          'description': 'Ninja adventure',
          'startDate': {'year': 2002},
          'endDate': {'year': 2007},
          'countryOfOrigin': 'JP',
          'format': 'TV',
          'episodes': 220,
          'duration': 23,
          'averageScore': 80,
          'popularity': 500000,
          'genres': ['Action'],
          'tags': const [],
          'coverImage': {'large': 'https://img.test/anilist-naruto.jpg'},
          'studios': {
            'nodes': [
              {'name': 'Studio Pierrot'},
            ],
          },
          'relations': {'edges': const []},
          'externalLinks': const [],
          'siteUrl': 'https://anilist.co/anime/20',
        },
      ],
    },
  },
};

final _tvMazeDetails = {
  'id': 216,
  'name': 'Rick and Morty',
  'url': 'https://www.tvmaze.com/shows/216/rick-and-morty',
  'type': 'Animation',
  'language': 'English',
  'genres': ['Comedy', 'Science-Fiction', 'Animation'],
  'premiered': '2013-12-02',
  'summary': '<b>Rick</b> takes Morty on adventures.',
  'averageRuntime': 23,
  'rating': {'average': 8.9},
  'weight': 99,
  'image': {
    'medium': 'https://img.test/rick-medium.jpg',
    'original': 'https://img.test/rick-original.jpg',
  },
  'network': {
    'name': 'Adult Swim',
    'country': {'code': 'US'},
  },
  'externals': {'imdb': 'tt2861424', 'thetvdb': 275274},
  '_embedded': {
    'episodes': [
      {'id': 1, 'season': 1, 'number': 1},
      {'id': 2, 'season': 1, 'number': 2},
    ],
    'seasons': [
      {'id': 1, 'number': 1},
    ],
    'cast': [
      {
        'person': {'name': 'Justin Roiland'},
        'character': {'name': 'Rick Sanchez'},
      },
    ],
  },
};
