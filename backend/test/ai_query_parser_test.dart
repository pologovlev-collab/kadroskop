import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:test/test.dart';

void main() {
  const request = RememberSearchRequest(
    query:
        'Мультсериал примерно из 2000-х. Подростки попадали через порталы в другой мир, там были механические существа.',
  );

  group('DeepSeekQueryParser', () {
    test('parses valid JSON and explicitly disables thinking', () async {
      Map<String, dynamic>? sent;
      final parser = DeepSeekQueryParser(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': jsonEncode(_validIntent)},
                },
              ],
            }),
            200,
          );
        }),
        apiKey: 'test-key',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        timeout: const Duration(seconds: 1),
        maxTokens: 400,
      );

      final intent = await parser.parse(request);

      expect(intent.plotKeywords, contains('portals'));
      expect(sent!['model'], 'deepseek-v4-flash');
      expect(sent!['thinking'], {'type': 'disabled'});
      expect(sent!['response_format'], {'type': 'json_object'});
      expect(sent!['max_tokens'], 400);
      expect(jsonEncode(sent!['messages']), contains('Не предлагай'));
    });

    test(
      'empty content falls back without a second provider request',
      () async {
        var requests = 0;
        final controller = _deepSeekController(
          MockClient((request) async {
            requests += 1;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': ''},
                  },
                ],
              }),
              200,
            );
          }),
        );

        final intent = await controller.parse(request);

        expect(requests, 1);
        expect(intent.plotKeywords, contains('portals'));
        expect(controller.status, AiProviderStatus.error);
      },
    );

    test('invalid JSON falls back', () async {
      final controller = _deepSeekController(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'not-json'},
                },
              ],
            }),
            200,
          ),
        ),
      );

      final intent = await controller.parse(request);

      expect(intent.workTypes, contains('animated_series'));
      expect(controller.status, AiProviderStatus.error);
    });

    for (final status in [401, 429]) {
      test('$status falls back', () async {
        final controller = _deepSeekController(
          MockClient((request) async => http.Response('{}', status)),
        );

        final intent = await controller.parse(request);

        expect(intent.yearFrom, 1995);
        expect(controller.status, AiProviderStatus.error);
      });
    }

    test('timeout falls back', () async {
      final controller = AiParserController(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        primary: DeepSeekQueryParser(
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return http.Response('{}', 200);
          }),
          apiKey: 'test-key',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-flash',
          timeout: const Duration(milliseconds: 1),
          maxTokens: 400,
        ),
        fallback: FallbackQueryParser(),
        initialStatus: AiProviderStatus.fallback,
      );

      final intent = await controller.parse(request);

      expect(intent.plotKeywords, contains('mechanical creatures'));
      expect(controller.status, AiProviderStatus.error);
    });
  });

  group('provider selection', () {
    test(
      'selects DeepSeek and reports missing key without a network call',
      () async {
        final parser = createAiQueryParser(
          AiSettings.fromEnvironment(const {
            'AI_ENABLED': 'true',
            'AI_PROVIDER': 'deepseek',
          }),
        );

        final intent = await parser.parse(request);

        expect(parser.provider, 'deepseek');
        expect(parser.status, AiProviderStatus.noKey);
        expect(parser.providerCalls, 0);
        expect(intent.workTypes, contains('animated_series'));
      },
    );

    test('selects YandexGPT when configured', () {
      final parser = createAiQueryParser(
        AiSettings.fromEnvironment(const {
          'AI_ENABLED': 'true',
          'AI_PROVIDER': 'yandex',
          'YANDEXGPT_API_KEY': 'test-key',
          'YANDEXGPT_FOLDER_ID': 'folder',
          'YANDEXGPT_MODEL': 'yandexgpt-lite',
        }),
      );

      expect(parser.provider, 'yandex');
      expect(parser.model, 'yandexgpt-lite');
    });

    test('none always uses the deterministic fallback', () async {
      final parser = createAiQueryParser(
        AiSettings.fromEnvironment(const {'AI_PROVIDER': 'none'}),
      );

      final intent = await parser.parse(request);

      expect(parser.provider, 'none');
      expect(parser.providerCalls, 0);
      expect(intent.plotKeywords, contains('parallel world'));
    });
  });

  test('strict validation rejects unknown fields and impossible years', () {
    expect(
      () => RememberSearchIntent.fromJson({..._validIntent, 'title': 'Fake'}),
      throwsA(isA<RememberValidationException>()),
    );
    expect(
      () => RememberSearchIntent.fromJson({..._validIntent, 'yearFrom': 1500}),
      throwsA(isA<RememberValidationException>()),
    );
  });

  test(
    'cache prevents repeated AI calls and results keep provider titles',
    () async {
      final counting = _CountingParser();
      final controller = AiParserController(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        primary: counting,
        fallback: FallbackQueryParser(),
        initialStatus: AiProviderStatus.fallback,
      );
      final catalog = CatalogGateway(
        MockClient((request) async {
          expect(request.url.host, 'graphql.anilist.co');
          return http.Response(
            jsonEncode(_aniListDiscoverResponse),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final cache = MemoryAiIntentCache();
      final service = RememberSearchService(
        catalog: catalog,
        parser: controller,
        cache: cache,
      );

      final first = await service.search(request);
      final second = await service.search(request);

      expect(counting.calls, 1);
      expect(controller.providerCalls, 1);
      expect(cache.writes, 1);
      final results = first['results']! as List<dynamic>;
      expect(results, hasLength(1));
      expect(
        (results.single as Map<String, dynamic>)['title'],
        'Real API Title',
      );
      expect(
        (results.single as Map<String, dynamic>)['source'],
        anyOf('tmdb_movie', 'tmdb_tv', 'anilist'),
      );
      expect((second['ai']! as Map<String, dynamic>)['cacheHit'], isTrue);
    },
  );
}

AiParserController _deepSeekController(http.Client client) =>
    AiParserController(
      provider: 'deepseek',
      model: 'deepseek-v4-flash',
      primary: DeepSeekQueryParser(
        client: client,
        apiKey: 'test-key',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        timeout: const Duration(seconds: 1),
        maxTokens: 400,
      ),
      fallback: FallbackQueryParser(),
      initialStatus: AiProviderStatus.fallback,
    );

class _CountingParser implements AiQueryParser {
  int calls = 0;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    calls += 1;
    return RememberSearchIntent.fromJson(_validIntent);
  }
}

final _validIntent = <String, dynamic>{
  'workTypes': ['animated_series', 'anime'],
  'yearFrom': 1995,
  'yearTo': 2012,
  'genres': ['science fiction', 'adventure'],
  'plotKeywords': [
    'teenagers',
    'portals',
    'parallel world',
    'mechanical creatures',
  ],
  'originalLanguageHints': <String>[],
  'countries': <String>[],
  'visualStyle': null,
  'targetAudience': null,
  'negativeKeywords': <String>[],
  'confidence': .82,
};

final _aniListDiscoverResponse = {
  'data': {
    'Page': {
      'media': [
        {
          'id': 777,
          'title': {
            'romaji': 'Real API Title',
            'english': 'Real API Title',
            'native': 'リアル',
          },
          'description': 'Teenagers enter a parallel world through portals.',
          'startDate': {'year': 2005},
          'countryOfOrigin': 'JP',
          'format': 'TV',
          'episodes': 26,
          'duration': 24,
          'averageScore': 75,
          'popularity': 1000,
          'genres': ['Sci-Fi', 'Adventure'],
          'tags': [
            {'name': 'Robots', 'rank': 80},
          ],
          'coverImage': {'large': 'https://example.test/real.jpg'},
        },
      ],
    },
  },
};
