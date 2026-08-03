import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remember_models.dart';

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
  final String? deepSeekApiKey;
  final String deepSeekBaseUrl;
  final String deepSeekModel;
  final String? yandexApiKey;
  final String? yandexFolderId;
  final String yandexModel;

  factory AiSettings.fromEnvironment(Map<String, String> values) => AiSettings(
    enabled: _bool(values['AI_ENABLED'], fallback: true),
    provider: (values['AI_PROVIDER'] ?? 'deepseek').trim().toLowerCase(),
    timeout: Duration(
      seconds: _boundedInt(
        values['AI_TIMEOUT_SECONDS'],
        fallback: 12,
        min: 2,
        max: 60,
      ),
    ),
    maxInputLength: _boundedInt(
      values['AI_MAX_INPUT_LENGTH'],
      fallback: 1000,
      min: 100,
      max: 5000,
    ),
    maxOutputTokens: _boundedInt(
      values['AI_MAX_OUTPUT_TOKENS'],
      fallback: 400,
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
    deepSeekApiKey: _secret(values['DEEPSEEK_API_KEY']),
    deepSeekBaseUrl:
        _secret(values['DEEPSEEK_BASE_URL']) ?? 'https://api.deepseek.com',
    deepSeekModel: _secret(values['DEEPSEEK_MODEL']) ?? 'deepseek-v4-flash',
    yandexApiKey: _secret(values['YANDEXGPT_API_KEY']),
    yandexFolderId: _secret(values['YANDEXGPT_FOLDER_ID']),
    yandexModel: _secret(values['YANDEXGPT_MODEL']) ?? 'yandexgpt-lite',
  );
}

enum AiProviderStatus { connected, noKey, noFunds, error, disabled, fallback }

class AiParserController implements AiQueryParser {
  AiParserController({
    required this.provider,
    required this.model,
    required AiQueryParser primary,
    required AiQueryParser fallback,
    required AiProviderStatus initialStatus,
  }) : _primary = primary,
       _fallback = fallback,
       status = initialStatus;

  final String provider;
  final String model;
  final AiQueryParser _primary;
  final AiQueryParser _fallback;
  AiProviderStatus status;
  String? message;
  int providerCalls = 0;

  bool get usesNetworkProvider =>
      provider == 'deepseek' || provider == 'yandex';

  @override
  Future<RememberSearchIntent> parse(RememberSearchRequest request) async {
    if (!usesNetworkProvider || status == AiProviderStatus.noKey) {
      status = status == AiProviderStatus.noKey
          ? AiProviderStatus.noKey
          : AiProviderStatus.disabled;
      return _fallback.parse(request);
    }
    providerCalls += 1;
    try {
      final result = await _primary.parse(request);
      status = AiProviderStatus.connected;
      message = null;
      return result;
    } on AiProviderException catch (error) {
      status = switch (error.kind) {
        AiProviderErrorKind.missingKey => AiProviderStatus.noKey,
        AiProviderErrorKind.noFunds => AiProviderStatus.noFunds,
        _ => AiProviderStatus.error,
      };
      message = error.message;
      return _fallback.parse(request);
    } on TimeoutException {
      status = AiProviderStatus.error;
      message = 'AI-провайдер не ответил вовремя.';
      return _fallback.parse(request);
    } on FormatException {
      status = AiProviderStatus.error;
      message = 'AI-провайдер вернул некорректный JSON.';
      return _fallback.parse(request);
    } on RememberValidationException catch (error) {
      status = AiProviderStatus.error;
      message = error.message;
      return _fallback.parse(request);
    } catch (_) {
      status = AiProviderStatus.error;
      message = 'Ошибка AI-провайдера.';
      return _fallback.parse(request);
    }
  }

  Map<String, Object?> toJson() => {
    'provider': switch (provider) {
      'deepseek' => 'DeepSeek',
      'yandex' => 'YandexGPT',
      _ => 'none',
    },
    'model': model,
    'status': status.name,
    if (message != null) 'message': message,
  };
}

AiParserController createAiQueryParser(
  AiSettings settings, {
  http.Client? client,
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
    final text = request.normalizedQuery;
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
    _addByPattern(text, genres, _genrePatterns);
    final countries = <String>{};
    _addByPattern(text, countries, _countryPatterns);
    final plotKeywords = <String>{};
    _addByPattern(text, plotKeywords, _plotPatterns);
    final visualStyle = text.contains('куколь') || text.contains('stop motion')
        ? 'puppet'
        : text.contains('3d') || text.contains('3д')
        ? '3d'
        : text.contains('2d') || text.contains('2д') || text.contains('рисован')
        ? '2d'
        : null;
    final years = _extractYears(text);
    return request.applyTo(
      RememberSearchIntent(
        workTypes: types.toList(),
        yearFrom: years.$1,
        yearTo: years.$2,
        genres: genres.toList(),
        plotKeywords: plotKeywords.toList(),
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
  final kind = switch (response.statusCode) {
    401 || 403 => AiProviderErrorKind.unauthorized,
    402 => AiProviderErrorKind.noFunds,
    429 => AiProviderErrorKind.rateLimited,
    _ => AiProviderErrorKind.unavailable,
  };
  throw AiProviderException(kind, switch (kind) {
    AiProviderErrorKind.unauthorized => '$provider отклонил API-ключ.',
    AiProviderErrorKind.noFunds => 'На балансе $provider нет средств.',
    AiProviderErrorKind.rateLimited => '$provider ограничил частоту запросов.',
    _ => '$provider временно недоступен (${response.statusCode}).',
  });
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

const _systemPrompt = '''
Верни только один JSON-объект с признаками забытого произведения. Не предлагай и не угадывай названия. Не создавай фильмы, аниме или сериалы. Не возвращай TMDB/AniList ID, обложки, рейтинги или пояснения. Извлекай только признаки из пользовательского текста.
Допустимые поля: workTypes (movie|series|anime|cartoon|animated_series|documentary), yearFrom, yearTo, genres, plotKeywords, originalLanguageHints, countries, visualStyle (2d|3d|puppet|unknown|null), targetAudience, negativeKeywords, confidence (0..1). Массивы должны быть короткими, значения жанров и сюжетных признаков — на английском.
Пример JSON: {"workTypes":["animated_series","anime"],"yearFrom":1995,"yearTo":2012,"genres":["science fiction","adventure"],"plotKeywords":["teenagers","portals","parallel world","mechanical creatures"],"originalLanguageHints":[],"countries":[],"visualStyle":null,"targetAudience":null,"negativeKeywords":[],"confidence":0.82}
Отвечай только JSON.
''';
