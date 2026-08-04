import 'dart:io';

import 'package:kadroskop_backend/kadroskop_server.dart';

Future<void> main() async {
  final localEnvironment = await _readLocalEnvironment();
  final environment = {...localEnvironment, ...Platform.environment};
  final port = int.tryParse(environment['PORT'] ?? '') ?? 8080;
  final server = await startKadroskopServer(
    address: InternetAddress.anyIPv4,
    port: port,
    catalogSettings: CatalogSettings.fromEnvironment(environment),
    aiSettings: AiSettings.fromEnvironment(environment),
    recommendationCacheTtl: Duration(
      hours: _boundedInt(
        environment['RECOMMENDATIONS_CACHE_HOURS'],
        fallback: 6,
        min: 1,
        max: 168,
      ),
    ),
  );
  stdout.writeln(
    'Kadroskop backend: http://${server.address.host}:${server.port}',
  );
}

int _boundedInt(
  String? value, {
  required int fallback,
  required int min,
  required int max,
}) => (int.tryParse(value ?? '') ?? fallback).clamp(min, max);

Future<Map<String, String>> _readLocalEnvironment() async {
  final file = File('.env');
  if (!await file.exists()) return const {};
  final values = <String, String>{};
  for (final rawLine in await file.readAsLines()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final separator = line.indexOf('=');
    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (key.isNotEmpty) values[key] = value;
  }
  return values;
}
