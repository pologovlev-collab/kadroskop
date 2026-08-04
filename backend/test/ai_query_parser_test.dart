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

  group('GeminiQueryParser', () {
    test('uses structured JSON with minimal thinking', () async {
      Map<String, dynamic>? sent;
      final parser = GeminiQueryParser(
        client: MockClient((httpRequest) async {
          sent = jsonDecode(httpRequest.body) as Map<String, dynamic>;
          expect(httpRequest.headers['x-goog-api-key'], 'test-key');
          return _geminiResponse(_validIntent);
        }),
        apiKey: 'test-key',
        model: 'gemini-3.5-flash-lite',
        thinkingLevel: 'minimal',
        timeout: const Duration(seconds: 1),
        maxTokens: 500,
      );

      final intent = await parser.parse(request);

      expect(intent.plotKeywords, contains('portals'));
      final generation = sent!['generationConfig'] as Map<String, dynamic>;
      expect(generation['thinkingLevel'], 'minimal');
      expect(generation['maxOutputTokens'], 500);
      final format = generation['responseFormat'] as Map<String, dynamic>;
      final text = format['text'] as Map<String, dynamic>;
      expect(text['mimeType'], 'application/json');
      final schema = text['schema'] as Map<String, dynamic>;
      expect(schema['additionalProperties'], isFalse);
      expect(
        (schema['required'] as List<dynamic>),
        containsAll(['workTypes', 'plotKeywords', 'confidence']),
      );
      expect(jsonEncode(sent), contains('TMDB/AniList ID'));
    });

    test('retries a 429 at most once', () async {
      var calls = 0;
      final parser = GeminiQueryParser(
        client: MockClient((request) async {
          calls += 1;
          if (calls == 1) {
            return http.Response(
              '{"error":{"status":"RESOURCE_EXHAUSTED"}}',
              429,
              headers: {'retry-after': '0'},
            );
          }
          return _geminiResponse(_validIntent);
        }),
        apiKey: 'test-key',
        model: 'gemini-3.5-flash-lite',
        thinkingLevel: 'minimal',
        timeout: const Duration(seconds: 1),
        maxTokens: 500,
        delay: (_) async {},
      );

      await parser.parse(request);

      expect(calls, 2);
    });

    test('empty response falls back without inventing a title', () async {
      final controller = _geminiController(
        MockClient((request) async => _geminiResponse(null)),
      );

      final intent = await controller.parse(request);

      expect(intent.plotKeywords, contains('portals'));
      expect(controller.status, AiProviderStatus.error);
      expect(controller.providerCalls, 1);
    });

    for (final status in [400, 401, 403, 404]) {
      test('$status uses deterministic fallback', () async {
        final controller = _geminiController(
          MockClient((request) async => http.Response('{}', status)),
        );

        final intent = await controller.parse(request);

        expect(intent.workTypes, contains('animated_series'));
        expect(controller.status, AiProviderStatus.error);
      });
    }

    test('quota exhaustion is reported without breaking search', () async {
      var calls = 0;
      final controller = _geminiController(
        MockClient((request) async {
          calls += 1;
          return http.Response(
            '{"error":{"status":"RESOURCE_EXHAUSTED","message":"quota"}}',
            429,
            headers: {'retry-after': '0'},
          );
        }),
      );

      final intent = await controller.parse(request);

      expect(calls, 2);
      expect(intent.plotKeywords, contains('parallel world'));
      expect(controller.status, AiProviderStatus.noFunds);
    });

    test('timeout uses deterministic fallback', () async {
      final controller = AiParserController(
        provider: 'gemini',
        model: 'gemini-3.5-flash-lite',
        primary: GeminiQueryParser(
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return _geminiResponse(_validIntent);
          }),
          apiKey: 'test-key',
          model: 'gemini-3.5-flash-lite',
          thinkingLevel: 'minimal',
          timeout: const Duration(milliseconds: 1),
          maxTokens: 500,
        ),
        fallback: FallbackQueryParser(),
        initialStatus: AiProviderStatus.fallback,
      );

      final intent = await controller.parse(request);

      expect(intent.plotKeywords, contains('mechanical creatures'));
      expect(controller.status, AiProviderStatus.error);
    });

    test('regional API error uses fallback and does not retry Gemini', () async {
      var calls = 0;
      final controller = _geminiController(
        MockClient((httpRequest) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'error': {
                'status': 'FAILED_PRECONDITION',
                'message':
                    'This API is not available in your current location.',
              },
            }),
            400,
          );
        }),
      );

      final first = await controller.parse(request);
      final second = await controller.parse(request);

      expect(first.plotKeywords, contains('portals'));
      expect(second.plotKeywords, contains('portals'));
      expect(calls, 1);
      expect(controller.providerCalls, 1);
      expect(controller.status, AiProviderStatus.unavailable);
      expect(
        controller.message,
        'Gemini недоступен в текущем регионе. Используется другой способ анализа.',
      );
    });

    test(
      'regional diagnosis is retained after the initial Gemini failure',
      () async {
        final controller = _geminiController(
          MockClient(
            (httpRequest) async => http.Response(
              jsonEncode({
                'error': {
                  'message': 'User location is not supported for the API use.',
                },
              }),
              400,
            ),
          ),
        );

        await controller.parse(request);

        expect(controller.status, AiProviderStatus.unavailable);
        expect(
          controller.message,
          'Gemini недоступен в текущем регионе. Используется другой способ анализа.',
        );
      },
    );
  });

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
        expect(
          controller.status,
          status == 429 ? AiProviderStatus.unavailable : AiProviderStatus.error,
        );
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

  group('OpenRouterQueryParser', () {
    test(
      'sends a private strict structured request and reads actual model',
      () async {
        Map<String, dynamic>? sent;
        final parser = OpenRouterQueryParser(
          client: MockClient((httpRequest) async {
            expect(
              httpRequest.url.toString(),
              'https://openrouter.ai/api/v1/chat/completions',
            );
            expect(httpRequest.headers['authorization'], 'Bearer test-key');
            expect(httpRequest.headers, isNot(contains('http-referer')));
            expect(httpRequest.headers, isNot(contains('x-title')));
            sent = jsonDecode(httpRequest.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'model': 'provider/real-free-model',
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
          baseUrl: 'https://openrouter.ai/api/v1',
          model: 'openrouter/free',
          appTitle: null,
          httpReferer: null,
          timeout: const Duration(seconds: 1),
          maxTokens: 400,
          requireStructuredOutput: true,
        );

        final intent = await parser.parse(request);

        expect(intent.plotKeywords, contains('portals'));
        expect(parser.actualModel, 'provider/real-free-model');
        expect(sent!['model'], 'openrouter/free');
        expect(sent!['stream'], isFalse);
        expect(sent, isNot(contains('reasoning')));
        final format = sent!['response_format'] as Map<String, dynamic>;
        final schema = format['json_schema'] as Map<String, dynamic>;
        expect(format['type'], 'json_schema');
        expect(schema['strict'], isTrue);
        final fields =
            (schema['schema'] as Map<String, dynamic>)['properties']
                as Map<String, dynamic>;
        expect(fields, isNot(contains('searchVariants')));
        final user =
            (sent!['messages'] as List<dynamic>)[1] as Map<String, dynamic>;
        final payload =
            jsonDecode(user['content'] as String) as Map<String, dynamic>;
        expect(
          payload.keys,
          unorderedEquals([
            'description',
            'type',
            'yearFrom',
            'yearTo',
            'country',
            'visualStyle',
          ]),
        );
        expect(jsonEncode(sent!['messages']), contains('Не предлагай'));
      },
    );

    test(
      'uses a configured specific model instead of the free router alias',
      () async {
        Map<String, dynamic>? sent;
        final controller = createAiQueryParser(
          AiSettings.fromEnvironment(const {
            'AI_ENABLED': 'true',
            'AI_PROVIDER': 'openrouter',
            'OPENROUTER_API_KEY': 'test-key',
            'OPENROUTER_SPECIFIC_MODEL': 'provider/specific-free-model',
          }),
          client: MockClient((httpRequest) async {
            sent = jsonDecode(httpRequest.body) as Map<String, dynamic>;
            return _openRouterResponse(_validIntent);
          }),
        );

        await controller.parse(request);

        expect(sent!['model'], 'provider/specific-free-model');
        expect(controller.provider, 'openrouter');
      },
    );

    test(
      'rate limiting makes one request and then uses fallback during cooldown',
      () async {
        var calls = 0;
        final controller = _openRouterController(
          MockClient((httpRequest) async {
            calls += 1;
            return http.Response('{}', 429, headers: {'retry-after': '30'});
          }),
        );

        final first = await controller.parse(request);
        final second = await controller.parse(request);

        expect(first.plotKeywords, contains('portals'));
        expect(second.plotKeywords, contains('portals'));
        expect(calls, 1);
        expect(controller.providerCalls, 1);
        expect(controller.status, AiProviderStatus.unavailable);
      },
    );

    test('invalid JSON and a missing key always use fallback', () async {
      final invalid = _openRouterController(
        MockClient(
          (httpRequest) async => http.Response(
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
      final missing = createAiQueryParser(
        AiSettings.fromEnvironment(const {
          'AI_ENABLED': 'true',
          'AI_PROVIDER': 'openrouter',
        }),
      );

      final invalidIntent = await invalid.parse(request);
      final missingIntent = await missing.parse(request);

      expect(invalidIntent.workTypes, contains('animated_series'));
      expect(invalid.status, AiProviderStatus.error);
      expect(missingIntent.workTypes, contains('animated_series'));
      expect(missing.status, AiProviderStatus.noKey);
      expect(missing.providerCalls, 0);
    });

    test('daily limit falls back without a second OpenRouter request', () async {
      var calls = 0;
      final controller = _openRouterController(
        MockClient((httpRequest) async {
          calls += 1;
          return _openRouterResponse(_validIntent);
        }),
        quota: MemoryAiUsageQuota(limit: 1),
      );

      await controller.parse(request);
      final limited = await controller.parse(request);

      expect(calls, 1);
      expect(limited.plotKeywords, contains('portals'));
      expect(controller.status, AiProviderStatus.limit);
      expect(
        controller.message,
        'Дневной лимит расширенного анализа достигнут. Использован обычный поиск.',
      );
    });
  });

  group('provider selection', () {
    test('selects OpenRouter by default', () {
      final parser = createAiQueryParser(
        AiSettings.fromEnvironment(const {
          'AI_ENABLED': 'true',
          'OPENROUTER_API_KEY': 'test-key',
        }),
      );

      expect(parser.provider, 'openrouter');
      expect(parser.model, 'openrouter/free');
      expect(parser.status, AiProviderStatus.fallback);
    });

    test('reports a missing Gemini key without a network call', () async {
      final parser = createAiQueryParser(
        AiSettings.fromEnvironment(const {
          'AI_ENABLED': 'true',
          'AI_PROVIDER': 'gemini',
        }),
      );

      final intent = await parser.parse(request);

      expect(parser.provider, 'gemini');
      expect(parser.status, AiProviderStatus.noKey);
      expect(parser.providerCalls, 0);
      expect(intent.workTypes, contains('animated_series'));
    });

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

  test('cache hash changes when the structured schema changes', () {
    final first = rememberFiltersHash(
      request,
      provider: 'openrouter',
      model: 'openrouter/free',
      schemaVersion: 'schema-a',
    );
    final second = rememberFiltersHash(
      request,
      provider: 'openrouter',
      model: 'openrouter/free',
      schemaVersion: 'schema-b',
    );

    expect(first, isNot(second));
  });

  test(
    'fallback extracts known Latin character names and query variants',
    () async {
      final parser = FallbackQueryParser();

      final intent = await parser.parse(
        const RememberSearchRequest(query: 'sasuke sakura madara аниме 2000-х'),
      );

      expect(intent.workTypes, contains('anime'));
      expect(intent.yearFrom, 2000);
      expect(
        intent.characterNames,
        containsAll(['Sasuke Uchiha', 'Sakura Haruno', 'Madara Uchiha']),
      );
    },
  );

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

AiParserController _geminiController(http.Client client) => AiParserController(
  provider: 'gemini',
  model: 'gemini-3.5-flash-lite',
  primary: GeminiQueryParser(
    client: client,
    apiKey: 'test-key',
    model: 'gemini-3.5-flash-lite',
    thinkingLevel: 'minimal',
    timeout: const Duration(seconds: 1),
    maxTokens: 500,
    delay: (_) async {},
  ),
  fallback: FallbackQueryParser(),
  initialStatus: AiProviderStatus.fallback,
);

http.Response _geminiResponse(Map<String, dynamic>? intent) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': intent == null ? '' : jsonEncode(intent)},
          ],
        },
      },
    ],
  }),
  200,
);

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

AiParserController _openRouterController(
  http.Client client, {
  AiUsageQuota? quota,
}) => AiParserController(
  provider: 'openrouter',
  model: 'openrouter/free',
  primary: OpenRouterQueryParser(
    client: client,
    apiKey: 'test-key',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openrouter/free',
    appTitle: null,
    httpReferer: null,
    timeout: const Duration(seconds: 1),
    maxTokens: 400,
    requireStructuredOutput: true,
  ),
  fallback: FallbackQueryParser(),
  initialStatus: AiProviderStatus.fallback,
  usageQuota: quota,
);

http.Response _openRouterResponse(Map<String, dynamic> intent) => http.Response(
  jsonEncode({
    'model': 'provider/real-free-model',
    'choices': [
      {
        'message': {'content': jsonEncode(intent)},
      },
    ],
  }),
  200,
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
  'titleFragments': <String>[],
  'characterNames': <String>[],
  'franchiseTerms': <String>[],
  'locations': ['parallel world'],
  'objects': ['portals', 'mechanical creatures'],
  'searchVariants': <String>[],
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
