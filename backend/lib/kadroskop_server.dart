import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'catalog_gateway.dart';

export 'catalog_gateway.dart';

Future<HttpServer> startKadroskopServer({
  required InternetAddress address,
  required int port,
  String? tmdbToken,
  CatalogGateway? catalogGateway,
}) {
  final catalog =
      catalogGateway ?? CatalogGateway(http.Client(), tmdbToken: tmdbToken);
  final router = Router()
    ..get('/v1/health', (Request request) {
      return _json({
        'ok': true,
        'backend': {'status': 'connected'},
        'providers': catalog.diagnostics,
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
