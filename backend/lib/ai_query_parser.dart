import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_usage_quota.dart';
import 'remember_models.dart';
import 'query_normalizer.dart';

abstract interface class AiQueryParser {
  Future<RememberSearchIntent> parse(RememberSearchRequest request);
}

class AiSettings {
  const AiSettings({
    required this.enabled,
    required this.provider,
    required this.timeout,
    required this.maxInputLength,
    required this.maxOutputTokens,
    required this.cacheHours,
    required this.rerankEnabled,
    required this.secondaryProvider,
    required this.fallbackProvider,
    required this.logFullPrompts,
    required this.openRouterApiKey,
    required this.openRouterBaseUrl,
    required this.openRouterModel,
    required this.openRouterSpecificModel,
    required this.openRouterAppTitle,
    required this.openRouterHttpReferer,
    required this.openRouterTimeout,
    required this.openRouterMaxOutputTokens,
    required this.openRouterCacheDays,
    required this.openRouterLocalDailyLimit,
    required this.openRouterRequireStructuredOutput,
    required this.geminiApiKey,
    required this.geminiModel,
    required this.geminiThinkingLevel,
    required this.deepSeekApiKey,
    required this.deepSeekBaseUrl,
    required this.deepSeekModel,
    required this.yandexApiKey,
    required this.yandexFolderId,
    required this.yandexModel,
  });

  final bool enabled;
  final String provider;
  final Duration timeout;
  final int maxInputLength;
  final int maxOutputTokens;
  final int cacheHours;
  final bool rerankEnabled;
  final String secondaryProvider;
  final String fallbackProvider;
  final bool logFullPrompts;
  final String? openRouterApiKey;
  final String openRouterBaseUrl;
  final String openRouterModel;
  final String? openRouterSpecificModel;
  final String? openRouterAppTitle;
  final String? openRouterHttpReferer;
  final Duration openRouterTimeout;
  final int openRouterMaxOutputTokens;
  final int openRouterCacheDays;
  final int openRouterLocalDailyLimit;
  final bool openRouterRequireStructuredOutput;
  final String? geminiApiKey;
  final String geminiModel;
  final String geminiThinkingLevel;
  final String? deepSeekApiKey;
  final String deepSeekBaseUrl;
  final String deepSeekModel;
  final String? yandexApiKey;
  final String? yandexFolderId;
  final String yandexModel;

  factory AiSettings.fromEnvironment(Map<String, String> values) => AiSettings(
    enabled: _bool(values['AI_ENABLED'], fallback: true),
    provider: (values['AI_PROVIDER'] ?? 'openrouter').trim().toLowerCase(),
    timeout: Duration(
      seconds: _boundedInt(
        values['AI_TIMEOUT_SECONDS'],
        fallback: 15,
        min: 2,
        max: 60,
      ),
    ),
    maxInputLength: _boundedInt(
      values['AI_MAX_INPUT_LENGTH'],
      fallback: 1500,
      min: 100,
      max: 5000,
    ),
    maxOutputTokens: _boundedInt(
      values['AI_MAX_OUTPUT_TOKENS'],
      fallback: 500,
      min: 100,
      max: 800,
    ),
    cacheHours: _boundedInt(
      values['AI_CACHE_HOURS'],
      fallback: 24,
      min: 1,
      max: 720,
    ),
    rerankEnabled: _bool(values['AI_RERANK_ENABLED'], fallback: false),
    secondaryProvider: (values['AI_SECONDARY_PROVIDER'] ?? 'none')
        .trim()
        .toLowerCase(),
    fallbackProvider: (values['AI_FALLBACK_PROVIDER'] ?? 'none')
        .trim()
        .toLowerCase(),
    logFullPrompts: _bool(values['AI_LOG_FULL_PROMPTS'], fallback: false),
    openRouterApiKey: _secret(values['OPENROUTER_API_KEY']),
    openRouterBaseUrl:
        _secret(values['OPENROUTER_BASE_URL']) ??
        'https://openrouter.ai/api/v1',
    openRouterModel: _secret(values['OPENROUTER_MODEL']) ?? 'openrouter/free',
    openRouterSpecificModel: _secret(values['OPENROUTER_SPECIFIC_MODEL']),
    openRouterAppTitle: _secret(values['OPENROUTER_APP_TITLE']),
    openRouterHttpReferer: _secret(values['OPENROUTER_HTTP_REFERER']),
    openRouterTimeout: Duration(
      seconds: _boundedInt(
        values['OPENROUTER_TIMEOUT_SECONDS'],
        fallback: 30,
        min: 2,
        max: 60,
      ),
    ),
    openRouterMaxOutputTokens: _boundedInt(
      values['OPENROUTER_MAX_OUTPUT_TOKENS'],
      fallback: 400,
      min: 100,
      max: 400,
    ),
    openRouterCacheDays: _boundedInt(
      values['OPENROUTER_CACHE_DAYS'],
      fallback: 30,
      min: 1,
      max: 90,
    ),
    openRouterLocalDailyLimit: _boundedInt(
      values['OPENROUTER_LOCAL_DAILY_LIMIT'],
      fallback: 45,
      min: 0,
      max: 1000,
    ),
    openRouterRequireStructuredOutput: _bool(
      values['OPENROUTER_REQUIRE_STRUCTURED_OUTPUT'],
      fallback: true,
    ),
    geminiApiKey: _secret(values['GEMINI_API_KEY']),
    geminiModel: _secret(values['GEMINI_MODEL']) ?? 'gemini-3.5-flash-lite',
    geminiThinkingLevel: _secret(values['GEMINI_THINKING_LEVEL']) ?? 'minimal',
    deepSeekApiKey: _secret(values['DEEPSEEK_API_KEY']),
    deepSeekBaseUrl:
        _secret(values['DEEPSEEK_BASE_URL']) ?? 'https://api.deepseek.com',
    deepSeekModel: _secret(values['DEEPSEEK_MODEL']) ?? 'deepseek-v4-flash',
    yandexApiKey: _secret(values['YANDEXGPT_API_KEY']),
    yandexFolderId: _secret(values['YANDEXGPT_FOLDER_ID']),
    yandexModel: _secret(values['YANDEXGPT_MODEL']) ?? 'yandexgpt-lite',
  );

  Duration get intentCacheTtl => provider == 'openrouter'
      ? Duration(days: openRouterCacheDays)
      : Duration(hours: cacheHours);

  String get configuredOpenRouterModel =>
      openRouterSpecificModel ?? openRouterModel;
}

enum AiProviderStatus {
  connected,
  noKey,
  noFunds,
  limit,
  unavailable,
  error,
  disabled,
  fallback,
}

class AiParserController implements AiQueryParser {
  AiParserController({
    required this.provider,
    required this.model,
    required AiQueryParser primary,
    required AiQueryParser fallback,
    required AiProviderStatus initialStatus,
    AiUsageQuota? usageQuota,
    String? Function()? actualModel,
    DateTime Function()? clock,
    this.rateLimitCooldown = const Duration(minutes: 5),
    this.regionUnavailableCooldown = const Duration(hours: 24),
  }) : _primary = primary,
       _fallback = fallback,
       _usageQuota = usageQuota,
       _actualModel = actualModel,
       _clock = clock ?? DateTime.now,
       status = initialStatus;

  final String provider;
  final String model;
  final AiQueryParser _primary;
  final AiQueryParser _fallback;
  final AiUsageQuota? _usageQuota;
  final String? Function()? _actualModel;
  final DateTime Function() _clock;
  final Duration rateLimitCooldown;
  final Duration regionUnavailableCooldown;
  AiProviderStatus status;
  String? message;
  int providerCalls = 0;
  DateTime? _cooldownUntil;
  String? _cooldownMessage;
  String? _usedModel;

  bool get usesNetworkProvider =>
      provider == 'openrouter' ||
      provider == 'gemini' ||
      provider == 'deepseek' ||
      provider == 'yandex';

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    if (!usesNetworkProvider || status == AiProviderStatus.noKey) {
      status = status == AiProviderStatus.noKey
          ? AiProviderStatus.noKey
          : AiProviderStatus.disabled;
      return _fallback.parse(request);
    }
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && _clock().isBefore(cooldownUntil)) {
      status = AiProviderStatus.unavailable;
      message =
          _cooldownMessage ??
          'AI-провайдер временно недоступен. Использован обычный поиск.';
      return _fallback.parse(request);
    }
    final usageQuota = _usageQuota;
    var acquiredQuota = false;
    if (usageQuota != null) {
      acquiredQuota = await usageQuota.tryAcquire();
      if (!acquiredQuota) {
        status = AiProviderStatus.limit;
        message =
            'Дневной лимит расширенного анализа достигнут. Использован обычный поиск.';
        return _fallback.parse(request);
      }
    }
    providerCalls += 1;
    try {
      final result = await _primary.parse(request);
      if (acquiredQuota) await usageQuota!.recordSuccess();
      _usedModel = _actualModel?.call() ?? _usedModel;
      status = AiProviderStatus.connected;
      message = null;
      return result;
    } on AiProviderException catch (error) {
      if (acquiredQuota) await usageQuota!.recordFailure();
      if (error.kind == AiProviderErrorKind.rateLimited) {
        _cooldownUntil = _clock().add(rateLimitCooldown);
        _cooldownMessage =
            'AI-провайдер временно недоступен. Использован обычный поиск.';
      } else if (error.kind == AiProviderErrorKind.regionUnavailable) {
        _cooldownUntil = _clock().add(regionUnavailableCooldown);
        _cooldownMessage = error.message;
      }
      status = switch (error.kind) {
        AiProviderErrorKind.missingKey => AiProviderStatus.noKey,
        AiProviderErrorKind.noFunds ||
        AiProviderErrorKind.quotaExceeded => AiProviderStatus.noFunds,
        AiProviderErrorKind.rateLimited => AiProviderStatus.unavailable,
        AiProviderErrorKind.regionUnavailable => AiProviderStatus.unavailable,
        _ => AiProviderStatus.error,
      };
      message = error.message;
      return _fallback.parse(request);
    } on TimeoutException {
      if (acquiredQuota) await usageQuota!.recordFailure();
      status = AiProviderStatus.error;
      message = 'AI-провайдер не ответил вовремя.';
      return _fallback.parse(request);
    } on FormatException {
      if (acquiredQuota) await usageQuota!.recordFailure();
      status = AiProviderStatus.error;
      message = 'AI-провайдер вернул некорректный JSON.';
      return _fallback.parse(request);
    } on RememberValidationException catch (error) {
      if (acquiredQuota) await usageQuota!.recordFailure();
      status = AiProviderStatus.error;
      message = error.message;
      return _fallback.parse(request);
    } catch (_) {
      if (acquiredQuota) await usageQuota!.recordFailure();
      status = AiProviderStatus.error;
      message = 'Ошибка AI-провайдера.';
      return _fallback.parse(request);
    }
  }

  Map<String, Object?> toJson() => {
    'provider': switch (provider) {
      'openrouter' => 'OpenRouter',
      'gemini' => 'Gemini',
      'deepseek' => 'DeepSeek',
      'yandex' => 'YandexGPT',
      _ => 'none',
    },
    'model': _usedModel ?? model,
    'status': status.name,
    if (message != null) 'message': message,
    if (_usageQuota != null) 'quota': _usageQuota.diagnostics,
  };
}

AiParserController createAiQueryParser(
  AiSettings settings, {
  http.Client? client,
  AiUsageQuota? usageQuota,
}) {
  final fallback = FallbackQueryParser();
  if (!settings.enabled || settings.provider == 'none') {
    return AiParserController(
      provider: 'none',
      model: 'fallback',
      primary: fallback,
      fallback: fallback,
      initialStatus: AiProviderStatus.disabled,
    );
  }
  final httpClient = client ?? http.Client();
  if (settings.provider == 'openrouter') {
    final key = settings.openRouterApiKey;
    final quota =
        usageQuota ??
        MemoryAiUsageQuota(limit: settings.openRouterLocalDailyLimit);
    late final OpenRouterQueryParser? primary;
    if (key != null) {
      primary = OpenRouterQueryParser(
        client: httpClient,
        apiKey: key,
        baseUrl: settings.openRouterBaseUrl,
        model: settings.configuredOpenRouterModel,
        appTitle: settings.openRouterAppTitle,
        httpReferer: settings.openRouterHttpReferer,
        timeout: settings.openRouterTimeout,
        maxTokens: settings.openRouterMaxOutputTokens,
        requireStructuredOutput: settings.openRouterRequireStructuredOutput,
      );
    } else {
      primary = null;
    }
    return AiParserController(
      provider: 'openrouter',
      model: settings.configuredOpenRouterModel,
      primary: primary ?? const MissingKeyQueryParser('OpenRouter'),
      fallback: fallback,
      initialStatus: key == null
          ? AiProviderStatus.noKey
          : AiProviderStatus.fallback,
      usageQuota: quota,
      actualModel: primary == null ? null : () => primary?.actualModel,
    );
  }
  if (settings.provider == 'gemini') {
    final key = settings.geminiApiKey;
    return AiParserController(
      provider: 'gemini',
      model: settings.geminiModel,
      primary: key == null
          ? const MissingKeyQueryParser('Gemini')
          : GeminiQueryParser(
              client: httpClient,
              apiKey: key,
              model: settings.geminiModel,
              thinkingLevel: settings.geminiThinkingLevel,
              timeout: settings.timeout,
              maxTokens: settings.maxOutputTokens,
            ),
      fallback: fallback,
      initialStatus: key == null
          ? AiProviderStatus.noKey
          : AiProviderStatus.fallback,
    );
  }
  if (settings.provider == 'deepseek') {
    final key = settings.deepSeekApiKey;
    return AiParserController(
      provider: 'deepseek',
      model: settings.deepSeekModel,
      primary: key == null
          ? const MissingKeyQueryParser('DeepSeek')
          : DeepSeekQueryParser(
              client: httpClient,
              apiKey: key,
              baseUrl: settings.deepSeekBaseUrl,
              model: settings.deepSeekModel,
              timeout: settings.timeout,
              maxTokens: settings.maxOutputTokens,
            ),
      fallback: fallback,
      initialStatus: key == null
          ? AiProviderStatus.noKey
          : AiProviderStatus.fallback,
    );
  }
  if (settings.provider == 'yandex') {
    final key = settings.yandexApiKey;
    final folder = settings.yandexFolderId;
    return AiParserController(
      provider: 'yandex',
      model: settings.yandexModel,
      primary: key == null || folder == null
          ? const MissingKeyQueryParser('YandexGPT')
          : YandexGptQueryParser(
              client: httpClient,
              apiKey: key,
              folderId: folder,
              model: settings.yandexModel,
              timeout: settings.timeout,
              maxTokens: settings.maxOutputTokens,
            ),
      fallback: fallback,
      initialStatus: key == null || folder == null
          ? AiProviderStatus.noKey
          : AiProviderStatus.fallback,
    );
  }
  return AiParserController(
    provider: 'none',
    model: 'fallback',
    primary: fallback,
    fallback: fallback,
    initialStatus: AiProviderStatus.disabled,
  );
}

class OpenRouterQueryParser implements AiQueryParser {
  OpenRouterQueryParser({
    required this.client,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.appTitle,
    required this.httpReferer,
    required this.timeout,
    required this.maxTokens,
    required this.requireStructuredOutput,
  });

  final http.Client client;
  final String apiKey;
  final String baseUrl;
  final String model;
  final String? appTitle;
  final String? httpReferer;
  final Duration timeout;
  final int maxTokens;
  final bool requireStructuredOutput;
  String? actualModel;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (httpReferer != null && httpReferer!.isNotEmpty) {
      headers['HTTP-Referer'] = httpReferer!;
    }
    if (appTitle != null && appTitle!.isNotEmpty) {
      headers['X-Title'] = appTitle!;
    }
    final response = await client
        .post(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
          ),
          headers: headers,
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': _openRouterRequestPayload(request)},
            ],
            if (requireStructuredOutput)
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'remember_search_intent',
                  'strict': true,
                  'schema': _openRouterIntentJsonSchema,
                },
              }
            else
              'response_format': {'type': 'json_object'},
            'temperature': 0,
            'max_tokens': maxTokens.clamp(100, 400),
            'stream': false,
          }),
        )
        .timeout(timeout);
    _validateStatus(response, 'OpenRouter');
    final body = _decodeResponse(response.body, 'OpenRouter');
    actualModel = body['model'] as String? ?? model;
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiProviderException(
        AiProviderErrorKind.invalidResponse,
        'OpenRouter вернул пустой ответ.',
      );
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    return _intentFromContent(content, 'OpenRouter');
  }
}

class GeminiQueryParser implements AiQueryParser {
  GeminiQueryParser({
    required this.client,
    required this.apiKey,
    required this.model,
    required this.thinkingLevel,
    required this.timeout,
    required this.maxTokens,
    this.delay,
  });

  final http.Client client;
  final String apiKey;
  final String model;
  final String thinkingLevel;
  final Duration timeout;
  final int maxTokens;
  final Future<void> Function(Duration duration)? delay;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': request.query},
          ],
        },
      ],
      'generationConfig': {
        'thinkingLevel': thinkingLevel,
        'maxOutputTokens': maxTokens.clamp(100, 500),
        'responseFormat': {
          'text': {
            'mimeType': 'application/json',
            'schema': _openRouterIntentJsonSchema,
          },
        },
      },
    });

    var response = await _post(uri, body);
    if (response.statusCode == 429) {
      await (delay ?? Future<void>.delayed)(_retryAfter(response));
      response = await _post(uri, body);
    }
    _validateStatus(response, 'Gemini');
    final decoded = _decodeResponse(response.body, 'Gemini');
    final candidates = decoded['candidates'];
    final first = candidates is List && candidates.isNotEmpty
        ? candidates.first
        : null;
    final content = first is Map ? first['content'] : null;
    final parts = content is Map ? content['parts'] : null;
    final text = parts is List
        ? parts
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join()
        : null;
    return _intentFromContent(text, 'Gemini');
  }

  Future<http.Response> _post(Uri uri, String body) => client
      .post(
        uri,
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      )
      .timeout(timeout);
}

class DeepSeekQueryParser implements AiQueryParser {
  const DeepSeekQueryParser({
    required this.client,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.timeout,
    required this.maxTokens,
  });

  final http.Client client;
  final String apiKey;
  final String baseUrl;
  final String model;
  final Duration timeout;
  final int maxTokens;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    final response = await client
        .post(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
          ),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': request.query},
            ],
            'thinking': {'type': 'disabled'},
            'response_format': {'type': 'json_object'},
            'temperature': 0,
            'max_tokens': maxTokens.clamp(100, 400),
            'stream': false,
          }),
        )
        .timeout(timeout);
    _validateStatus(response, 'DeepSeek');
    final body = _decodeResponse(response.body, 'DeepSeek');
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiProviderException(
        AiProviderErrorKind.invalidResponse,
        'DeepSeek вернул пустой ответ.',
      );
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw const AiProviderException(
        AiProviderErrorKind.invalidResponse,
        'DeepSeek вернул некорректный ответ.',
      );
    }
    final message = choice['message'];
    final content = message is Map ? message['content'] : null;
    return _intentFromContent(content, 'DeepSeek');
  }
}

class YandexGptQueryParser implements AiQueryParser {
  const YandexGptQueryParser({
    required this.client,
    required this.apiKey,
    required this.folderId,
    required this.model,
    required this.timeout,
    required this.maxTokens,
  });

  final http.Client client;
  final String apiKey;
  final String folderId;
  final String model;
  final Duration timeout;
  final int maxTokens;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    final response = await client
        .post(
          Uri.parse(
            'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
          ),
          headers: {
            'Authorization': 'Api-Key $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'modelUri': 'gpt://$folderId/$model/latest',
            'completionOptions': {
              'stream': false,
              'temperature': 0,
              'maxTokens': '${maxTokens.clamp(100, 400)}',
            },
            'messages': [
              {'role': 'system', 'text': _systemPrompt},
              {'role': 'user', 'text': request.query},
            ],
            'jsonObject': true,
          }),
        )
        .timeout(timeout);
    _validateStatus(response, 'YandexGPT');
    final body = _decodeResponse(response.body, 'YandexGPT');
    final result = body['result'];
    final alternatives = result is Map ? result['alternatives'] : null;
    final first = alternatives is List && alternatives.isNotEmpty
        ? alternatives.first
        : null;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['text'] : null;
    return _intentFromContent(content, 'YandexGPT');
  }
}

class MissingKeyQueryParser implements AiQueryParser {
  const MissingKeyQueryParser(this.provider);
  final String provider;

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) {
    throw AiProviderException(
      AiProviderErrorKind.missingKey,
      'Для $provider не настроен API-ключ.',
    );
  }
}

class FallbackQueryParser implements AiQueryParser {
  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    final normalizer = const QueryNormalizer();
    final text = request.normalizedQuery;
    final keyboardText = normalizer.swapKeyboardLayout(request.query);
    final transliteratedText = normalizer.transliterate(request.query);
    final searchableText = '$text $keyboardText $transliteratedText';
    final types = <String>{};
    if (text.contains('мультсериал') || text.contains('мульт сериал')) {
      types.addAll(const ['animated_series', 'anime']);
    } else if (text.contains('сериал')) {
      types.add('series');
    }
    if (text.contains('мультфильм')) types.add('cartoon');
    if (text.contains('аниме')) types.add('anime');
    if (text.contains('документаль')) types.add('documentary');
    if (text.contains('фильм') && !text.contains('мультфильм')) {
      types.add('movie');
    }
    final genres = <String>{};
    _addByPattern(searchableText, genres, _genrePatterns);
    final countries = <String>{};
    _addByPattern(searchableText, countries, _countryPatterns);
    final plotKeywords = <String>{};
    _addByPattern(searchableText, plotKeywords, _plotPatterns);
    final titleFragments = _extractQuotedFragments(request.query);
    final characterNames = _extractCharacterNames(request.query);
    final locations = <String>{};
    _addByPattern(searchableText, locations, _locationPatterns);
    final objects = <String>{};
    _addByPattern(searchableText, objects, _objectPatterns);
    final searchVariants = <String>{};
    for (final fragment in [...titleFragments, ...characterNames]) {
      searchVariants.addAll(confirmedTitleAliases(fragment.toLowerCase()));
    }
    final visualStyle = text.contains('куколь') || text.contains('stop motion')
        ? 'puppet'
        : text.contains('3d') || text.contains('3д')
        ? '3d'
        : text.contains('2d') || text.contains('2д') || text.contains('рисован')
        ? '2d'
        : null;
    final years = _extractYears(searchableText);
    return request.applyTo(
      RememberSearchIntent(
        workTypes: types.toList(),
        yearFrom: years.$1,
        yearTo: years.$2,
        genres: genres.toList(),
        plotKeywords: plotKeywords.toList(),
        titleFragments: titleFragments,
        characterNames: characterNames,
        locations: locations.toList(),
        objects: objects.toList(),
        searchVariants: searchVariants.toList(),
        countries: countries.toList(),
        visualStyle: visualStyle,
        targetAudience: text.contains('подрост') ? 'teenagers' : null,
        confidence: 0.55,
      ),
    );
  }
}

enum AiProviderErrorKind {
  missingKey,
  unauthorized,
  rateLimited,
  noFunds,
  quotaExceeded,
  regionUnavailable,
  modelUnavailable,
  invalidRequest,
  structuredOutputUnavailable,
  timeout,
  invalidResponse,
  unavailable,
}

class AiProviderException implements Exception {
  const AiProviderException(this.kind, this.message);
  final AiProviderErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

RememberSearchIntent _intentFromContent(Object? content, String provider) {
  if (content is! String || content.trim().isEmpty) {
    throw AiProviderException(
      AiProviderErrorKind.invalidResponse,
      '$provider вернул пустой content.',
    );
  }
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) throw const FormatException();
    return RememberSearchIntent.fromJson(decoded.cast<String, dynamic>());
  } on FormatException {
    throw AiProviderException(
      AiProviderErrorKind.invalidResponse,
      '$provider вернул текст вне JSON.',
    );
  }
}

Map<String, dynamic> _decodeResponse(String value, String provider) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Converted to a typed provider error below.
  }
  throw AiProviderException(
    AiProviderErrorKind.invalidResponse,
    '$provider вернул некорректный JSON.',
  );
}

void _validateStatus(http.Response response, String provider) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  final errorBody = response.body.toLowerCase();
  final kind = _isRegionUnavailable(errorBody)
      ? AiProviderErrorKind.regionUnavailable
      : switch (response.statusCode) {
          401 || 403 => AiProviderErrorKind.unauthorized,
          402 => AiProviderErrorKind.noFunds,
          404 => AiProviderErrorKind.modelUnavailable,
          429
              when errorBody.contains('quota') ||
                  errorBody.contains('resource_exhausted') =>
            AiProviderErrorKind.quotaExceeded,
          429 => AiProviderErrorKind.rateLimited,
          400 || 422
              when errorBody.contains('json_schema') ||
                  errorBody.contains('response_format') ||
                  errorBody.contains('structured') =>
            AiProviderErrorKind.structuredOutputUnavailable,
          400 || 422 => AiProviderErrorKind.invalidRequest,
          _ => AiProviderErrorKind.unavailable,
        };
  throw AiProviderException(kind, switch (kind) {
    AiProviderErrorKind.unauthorized => '$provider отклонил API-ключ.',
    AiProviderErrorKind.noFunds => 'На балансе $provider нет средств.',
    AiProviderErrorKind.rateLimited => '$provider ограничил частоту запросов.',
    AiProviderErrorKind.regionUnavailable when provider == 'Gemini' =>
      'Gemini недоступен в текущем регионе. Используется другой способ анализа.',
    AiProviderErrorKind.regionUnavailable =>
      '$provider недоступен в текущем регионе.',
    AiProviderErrorKind.modelUnavailable =>
      'Модель $provider временно недоступна.',
    AiProviderErrorKind.structuredOutputUnavailable =>
      '$provider не поддержал строгий JSON-ответ.',
    AiProviderErrorKind.invalidRequest =>
      '$provider отклонил параметры запроса.',
    _ => '$provider временно недоступен (${response.statusCode}).',
  });
}

bool _isRegionUnavailable(String body) =>
    body.contains('this api is not available in your current location') ||
    body.contains('user location is not supported for the api use') ||
    (body.contains('failed_precondition') &&
        (body.contains('location') || body.contains('region')));

Duration _retryAfter(http.Response response) {
  final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
  return Duration(seconds: seconds.clamp(0, 30));
}

void _addByPattern(
  String text,
  Set<String> target,
  Map<String, String> patterns,
) {
  for (final entry in patterns.entries) {
    if (text.contains(entry.key)) target.add(entry.value);
  }
}

(int?, int?) _extractYears(String text) {
  final decade = RegExp(r'(19\d0|20\d0)(?:-х|х|s)').firstMatch(text);
  if (decade != null) {
    final start = int.parse(decade.group(1)!);
    final approximate = text.contains('пример') || text.contains('где-то');
    return approximate ? (start - 5, start + 12) : (start, start + 9);
  }
  final exact = RegExp(
    r'\b(18\d{2}|19\d{2}|20\d{2})\b',
  ).allMatches(text).map((match) => int.parse(match.group(0)!)).toList();
  if (exact.length >= 2) return (exact.first, exact[1]);
  if (exact.length == 1) {
    final value = exact.first;
    return text.contains('пример') ? (value - 3, value + 3) : (value, value);
  }
  return (null, null);
}

bool _bool(String? value, {required bool fallback}) =>
    switch (value?.trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => fallback,
    };

int _boundedInt(
  String? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = int.tryParse(value ?? '') ?? fallback;
  return parsed.clamp(min, max);
}

String? _secret(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

const _genrePatterns = {
  'фантаст': 'science fiction',
  'научн': 'science fiction',
  'приключ': 'adventure',
  'детектив': 'mystery',
  'ужас': 'horror',
  'комеди': 'comedy',
  'роман': 'romance',
  'мелодрам': 'romance',
  'драм': 'drama',
  'фэнтези': 'fantasy',
  'боевик': 'action',
  'историч': 'history',
};

const _countryPatterns = {
  'япон': 'Japan',
  'сша': 'United States',
  'американ': 'United States',
  'росси': 'Russia',
  'советск': 'Soviet Union',
  'француз': 'France',
  'британ': 'United Kingdom',
  'корей': 'South Korea',
  'китай': 'China',
};

const _plotPatterns = {
  'подрост': 'teenagers',
  'портал': 'portals',
  'другой мир': 'parallel world',
  'параллельн': 'parallel world',
  'механическ': 'mechanical creatures',
  'робот': 'robots',
  'космос': 'space',
  'школ': 'school',
  'маг': 'magic',
  'путешеств': 'journey',
  'машин времени': 'time travel',
  'будущ': 'future',
  'прошл': 'past',
  'детектив': 'investigation',
  'монстр': 'monsters',
  'животн': 'animals',
  'остров': 'island',
  'пустын': 'desert',
};

const _locationPatterns = {
  'другой мир': 'parallel world',
  'параллельн': 'parallel world',
  'космос': 'space',
  'школ': 'school',
  'остров': 'island',
  'пустын': 'desert',
  'подзем': 'underground',
  'город': 'city',
};

const _objectPatterns = {
  'портал': 'portals',
  'механическ': 'mechanical creatures',
  'робот': 'robots',
  'маск': 'mask',
  'меч': 'sword',
  'кольц': 'ring',
  'амулет': 'amulet',
  'машин времени': 'time machine',
};

List<String> _extractQuotedFragments(String value) => RegExp(
  r'[«"“]([^»"”]{2,100})[»"”]',
).allMatches(value).map((match) => match.group(1)!.trim()).toSet().toList();

List<String> _extractCharacterNames(String value) {
  final names = <String>{};
  final expressions = [
    RegExp(
      r'(?:злодея|злодейку|героя|героиню|персонажа|мальчика|девочку)\s+(?:звали|по имени)\s+([a-zа-яё-]{2,40})',
      caseSensitive: false,
    ),
    RegExp(r'(?:звали|по имени)\s+([a-zа-яё-]{2,40})', caseSensitive: false),
  ];
  for (final expression in expressions) {
    for (final match in expression.allMatches(value)) {
      names.add(match.group(1)!.trim());
    }
  }
  final normalized = value.toLowerCase().replaceAll('ё', 'е');
  for (final entry in _knownCharacterAliases.entries) {
    if (normalized.contains(entry.key)) names.add(entry.value);
  }
  for (final entry in _knownLatinCharacterAliases.entries) {
    if (RegExp('\\b${entry.key}\\b', caseSensitive: false).hasMatch(value)) {
      names.add(entry.value);
    }
  }
  for (final match in RegExp(r'\b[A-Z][a-z]{2,40}\b').allMatches(value)) {
    final candidate = match.group(0)!;
    if (!_latinStopWords.contains(candidate.toLowerCase())) {
      names.add(candidate);
    }
  }
  return names.take(15).toList();
}

const _knownCharacterAliases = {
  'фобос': 'Phobos',
  'наруто': 'Naruto Uzumaki',
  'ичиго': 'Ichigo Kurosaki',
  'сейлор мун': 'Usagi Tsukino',
  'рик санчез': 'Rick Sanchez',
};

const _knownLatinCharacterAliases = {
  'sasuke': 'Sasuke Uchiha',
  'sakura': 'Sakura Haruno',
  'madara': 'Madara Uchiha',
  'naruto': 'Naruto Uzumaki',
  'ichigo': 'Ichigo Kurosaki',
};

const _latinStopWords = {
  'about',
  'anime',
  'cartoon',
  'film',
  'movie',
  'series',
  'the',
};

String _openRouterRequestPayload(RememberSearchRequest request) => jsonEncode({
  'description': request.query,
  'type': request.type,
  'yearFrom': request.yearFrom,
  'yearTo': request.yearTo,
  'country': request.country,
  'visualStyle': request.visualStyle,
});

const Map<String, Object?> _openRouterIntentJsonSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'workTypes': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [
          'movie',
          'series',
          'anime',
          'cartoon',
          'animated_series',
          'documentary',
        ],
      },
      'maxItems': 6,
    },
    'yearFrom': {
      'anyOf': [
        {'type': 'integer'},
        {'type': 'null'},
      ],
    },
    'yearTo': {
      'anyOf': [
        {'type': 'integer'},
        {'type': 'null'},
      ],
    },
    'genres': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'plotKeywords': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 20,
    },
    'titleFragments': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'characterNames': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 15,
    },
    'franchiseTerms': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'locations': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'objects': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'originalLanguageHints': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 8,
    },
    'countries': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 8,
    },
    'visualStyle': {
      'anyOf': [
        {
          'type': 'string',
          'enum': ['2d', '3d', 'puppet', 'unknown'],
        },
        {'type': 'null'},
      ],
    },
    'targetAudience': {
      'anyOf': [
        {'type': 'string'},
        {'type': 'null'},
      ],
    },
    'negativeKeywords': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 10,
    },
    'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
  },
  'required': [
    'workTypes',
    'yearFrom',
    'yearTo',
    'genres',
    'plotKeywords',
    'titleFragments',
    'characterNames',
    'franchiseTerms',
    'locations',
    'objects',
    'originalLanguageHints',
    'countries',
    'visualStyle',
    'targetAudience',
    'negativeKeywords',
    'confidence',
  ],
};

const _systemPrompt = '''
Верни только один JSON-объект с признаками забытого произведения. Не предлагай и не угадывай названия. Не создавай фильмы, аниме или сериалы. Не возвращай TMDB/AniList ID, обложки, рейтинги или пояснения. Извлекай только признаки из пользовательского текста.
Допустимые поля: workTypes (movie|series|anime|cartoon|animated_series|documentary), yearFrom, yearTo, genres, plotKeywords, titleFragments, characterNames, franchiseTerms, locations, objects, originalLanguageHints, countries, visualStyle (2d|3d|puppet|unknown|null), targetAudience, negativeKeywords, confidence (0..1). titleFragments содержит только буквально названные пользователем фрагменты, characterNames — только упомянутые имена; не угадывай итоговое произведение. Массивы должны быть короткими, значения жанров и сюжетных признаков — на английском.
Пример JSON: {"workTypes":["animated_series","anime"],"yearFrom":1995,"yearTo":2012,"genres":["science fiction","adventure"],"plotKeywords":["teenagers","portals","parallel world","mechanical creatures"],"titleFragments":[],"characterNames":[],"franchiseTerms":[],"locations":["parallel world"],"objects":["portals","mechanical creatures"],"originalLanguageHints":[],"countries":[],"visualStyle":null,"targetAudience":null,"negativeKeywords":[],"confidence":0.82}
Отвечай только JSON.
''';
