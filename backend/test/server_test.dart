import 'dart:io';

import 'package:http/http.dart' as http;
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
    expect(response.body, contains('"tmdbConfigured":false'));
    expect(response.body, contains('"anilistConfigured":true'));
  });
}
