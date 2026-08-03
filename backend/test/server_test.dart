import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  test('health endpoint reports provider configuration', () async {
    final server = await startKadroskopServer(
      address: InternetAddress.loopbackIPv4,
      port: 0,
    );
    addTearDown(() => server.close(force: true));

    final response = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}/v1/health'),
    );

    expect(response.statusCode, 200);
    expect(response.body, contains('"ok":true'));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final providers = body['providers'] as Map<String, dynamic>;
    expect(body['ok'], isTrue);
    expect(
      (providers['tmdb'] as Map<String, dynamic>)['status'],
      'notConfigured',
    );
    expect((providers['anilist'] as Map<String, dynamic>)['status'], 'unknown');
  });

  test('AniList results survive a TMDB connection failure', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.themoviedb.org') {
        throw http.ClientException('connection refused', request.url);
      }
      return http.Response(
        jsonEncode({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 1,
                  'title': {
                    'romaji': 'Black Clover',
                    'english': 'Black Clover',
                    'native': 'ブラッククローバー',
                  },
                  'description': 'Magic adventure',
                  'startDate': {'year': 2017},
                  'countryOfOrigin': 'JP',
                  'format': 'TV',
                  'episodes': 170,
                  'duration': 24,
                  'averageScore': 79,
                  'popularity': 500000,
                  'genres': ['Action', 'Fantasy'],
                  'coverImage': {'large': 'https://example.test/poster.jpg'},
                },
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final gateway = CatalogGateway(
      client,
      tmdbToken: 'configured-token',
      requestTimeout: const Duration(milliseconds: 100),
    );

    final result = await gateway.search('black clover');

    expect(result.results, hasLength(1));
    expect(result.results.single['source'], 'anilist');
    expect(result.warnings.single, contains('TMDB'));
    expect(
      ((gateway.diagnostics['anilist'] as Map<String, Object?>)['status']),
      'connected',
    );
  });

  test(
    'search returns a service error only when every provider fails',
    () async {
      final gateway = CatalogGateway(
        MockClient((request) async {
          throw http.ClientException('connection refused', request.url);
        }),
        tmdbToken: 'configured-token',
        requestTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        gateway.search('anything'),
        throwsA(
          isA<CatalogException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.message, 'message', contains('TMDB')),
        ),
      );
    },
  );

  test('POST /remember/search returns only verified candidates', () async {
    final catalog = CatalogGateway(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'Page': {
                'media': [
                  {
                    'id': 42,
                    'title': {
                      'romaji': 'Verified Work',
                      'english': 'Verified Work',
                      'native': 'Verified Work',
                    },
                    'description': 'Teenagers travel through portals.',
                    'startDate': {'year': 2004},
                    'countryOfOrigin': 'JP',
                    'format': 'TV',
                    'episodes': 12,
                    'duration': 24,
                    'averageScore': 80,
                    'popularity': 100,
                    'genres': ['Sci-Fi'],
                    'tags': const [],
                    'coverImage': {
                      'large': 'https://example.test/verified.jpg',
                    },
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final parser = createAiQueryParser(
      AiSettings.fromEnvironment(const {'AI_PROVIDER': 'none'}),
    );
    final server = await startKadroskopServer(
      address: InternetAddress.loopbackIPv4,
      port: 0,
      catalogGateway: catalog,
      aiParser: parser,
      aiIntentCache: MemoryAiIntentCache(),
    );
    addTearDown(() => server.close(force: true));

    final response = await http.post(
      Uri.parse('http://127.0.0.1:${server.port}/remember/search'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'query':
            'Мультсериал из 2000-х про подростков, порталы и механических существ',
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>;

    expect(response.statusCode, 200);
    expect(results, hasLength(1));
    expect((results.single as Map<String, dynamic>)['source'], 'anilist');
    expect((results.single as Map<String, dynamic>)['title'], 'Verified Work');
    expect(body.toString(), isNot(contains('Дождь на стекле')));
  });
}
