import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'catalog_gateway.dart';
import 'media_alias_store.dart';
import 'ai_intent_cache.dart';
import 'ai_query_parser.dart';
import 'remember_models.dart';
import 'remember_search_service.dart';
import 'recommendation_service.dart';
import 'similarity_service.dart';

export 'catalog_gateway.dart';
export 'catalog_provider.dart';
export 'catalog_providers.dart';
export 'media_alias_store.dart';
export 'query_normalizer.dart';
export 'ai_intent_cache.dart';
export 'ai_query_parser.dart';
export 'remember_models.dart';
export 'remember_search_service.dart';
export 'recommendation_service.dart';
export 'similarity_service.dart';

Future<HttpServer> startKadroskopServer({
  required InternetAddress address,
  required int port,
  String? tmdbToken,
  CatalogSettings? catalogSettings,
  MediaAliasStore? mediaAliasStore,
  CatalogGateway? catalogGateway,
  AiSettings? aiSettings,
  AiParserController? aiParser,
  AiIntentCache? aiIntentCache,
  RememberSearchService? rememberSearchService,
  RecommendationService? recommendationService,
  SimilarityService? similarityService,
  Duration recommendationCacheTtl = const Duration(hours: 6),
  String aiCachePath = 'data/kadroskop_backend.db',
}) {
  final aliases =
      mediaAliasStore ??
      (catalogSettings == null
          ? MemoryMediaAliasStore()
          : SqliteMediaAliasStore(path: aiCachePath));
  final catalog =
      catalogGateway ??
      CatalogGateway(
        http.Client(),
        tmdbToken: tmdbToken,
        settings: catalogSettings,
        aliasStore: aliases,
      );
  final settings =
      aiSettings ?? AiSettings.fromEnvironment(const {'AI_ENABLED': 'false'});
  final parser = aiParser ?? createAiQueryParser(settings);
  final intentCache =
      aiIntentCache ??
      (aiSettings == null
          ? MemoryAiIntentCache()
          : SqliteAiIntentCache(
              path: aiCachePath,
              ttl: Duration(hours: settings.cacheHours),
            ));
  final remember =
      rememberSearchService ??
      RememberSearchService(
        catalog: catalog,
        parser: parser,
        cache: intentCache,
      );
  final recommendations =
      recommendationService ??
      RecommendationService.forCatalog(
        catalog,
        cacheTtl: recommendationCacheTtl,
      );
  final similarity =
      similarityService ??
      SimilarityService.forCatalog(catalog, cacheTtl: recommendationCacheTtl);
  final router = Router()
    ..get('/v1/health', (Request request) {
      return _json({
        'ok': true,
        'backend': {'status': 'connected'},
        'providers': catalog.diagnostics,
        'ai': remember.diagnostics(),
      });
    })
    ..get('/v1/search', (Request request) async {
      final query = _normalizedQuery(request.url.queryParameters['q']);
      final kind = request.url.queryParameters['kind'];
      final page = _page(request);
      if (query.length < 2) {
        return _json({
          'error': 'Параметр q должен содержать минимум 2 символа.',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        return _json(
          (await catalog.search(query, kind: kind, page: page)).toJson(),
        );
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    })
    ..get('/v1/popular', (Request request) async {
      try {
        return _json(
          (await catalog.popular(
            kind: request.url.queryParameters['kind'],
            page: _page(request),
          )).toJson(),
        );
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    })
    ..get('/v1/recommendations/for-you', (Request request) async {
      final seedValues = _listQuery(request, 'seeds');
      final seeds = seedValues
          .map(RecommendationSeed.tryParse)
          .whereType<RecommendationSeed>()
          .take(12)
          .toList();
      if (seedValues.isNotEmpty && seeds.isEmpty) {
        return _json({
          'error': 'Параметр seeds имеет некорректный формат.',
        }, statusCode: HttpStatus.badRequest);
      }
      final kind = request.url.queryParameters['kind'];
      if (kind != null &&
          !const {
            'all',
            'movie',
            'series',
            'anime',
            'cartoon',
            'animatedSeries',
            'documentary',
          }.contains(kind)) {
        return _json({
          'error': 'Неизвестный тип произведения.',
        }, statusCode: HttpStatus.badRequest);
      }
      return _json(
        await recommendations.forYou(
          seeds: seeds,
          excluded: _listQuery(request, 'excluded').take(100).toSet(),
          kind: kind,
          page: _page(request),
          refresh: request.url.queryParameters['refresh'] == 'true',
        ),
      );
    })
    ..get('/v1/media/<source>/<id>', (
      Request request,
      String source,
      String id,
    ) async {
      try {
        return _json(await catalog.details(source, id));
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    })
    ..get('/v1/media/<source>/<id>/similar', (
      Request request,
      String source,
      String id,
    ) async {
      final modeName = request.url.queryParameters['mode'] ?? 'overall';
      final mode = SimilarityMode.values
          .where((value) => value.name == modeName)
          .firstOrNull;
      if (mode == null) {
        return _json({
          'error': 'Неизвестный режим похожести.',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        return _json(
          await similarity.search(
            source: source,
            sourceId: id,
            mode: mode,
            page: _page(request),
            refresh: request.url.queryParameters['refresh'] == 'true',
          ),
        );
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    })
    ..post('/remember/search', (Request request) async {
      try {
        final body = await request.readAsString();
        if (body.length > settings.maxInputLength + 4000) {
          throw const RememberValidationException('Запрос слишком большой.');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          throw const RememberValidationException(
            'Тело запроса должно быть JSON-объектом.',
          );
        }
        final searchRequest = RememberSearchRequest.fromJson(
          decoded.cast<String, dynamic>(),
          maxInputLength: settings.maxInputLength,
        );
        return _json(await remember.search(searchRequest));
      } on FormatException {
        return _json({
          'error': 'Тело запроса содержит некорректный JSON.',
        }, statusCode: HttpStatus.badRequest);
      } on RememberValidationException catch (error) {
        return _json({
          'error': error.message,
        }, statusCode: HttpStatus.badRequest);
      } on CatalogException catch (error) {
        return _json({'error': error.message}, statusCode: error.statusCode);
      }
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addMiddleware(_errorBoundary())
      .addHandler(router.call);
  return shelf_io.serve(handler, address, port);
}

int _page(Request request) {
  final value = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
  return value < 1 ? 1 : (value > 50 ? 50 : value);
}

String _normalizedQuery(String? value) =>
    (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

List<String> _listQuery(Request request, String name) => request
    .url
    .queryParametersAll[name]
    .orEmpty
    .expand((value) => value.split(','))
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList();

extension on List<String>? {
  List<String> get orEmpty => this ?? const [];
}

Middleware _cors() =>
    (innerHandler) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: {...response.headers, ..._corsHeaders});
    };

Middleware _errorBoundary() =>
    (innerHandler) => (request) async {
      try {
        return await innerHandler(request);
      } on TimeoutException {
        return _json({
          'error': 'Источник каталога не ответил вовремя.',
        }, statusCode: HttpStatus.gatewayTimeout);
      } catch (error, stackTrace) {
        stderr.writeln('$error\n$stackTrace');
        return _json({
          'error': 'Внутренняя ошибка backend.',
        }, statusCode: HttpStatus.internalServerError);
      }
    };

Response _json(Object value, {int statusCode = 200}) => Response(
  statusCode,
  body: jsonEncode(value),
  headers: {
    HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
    ..._corsHeaders,
  },
);

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};
