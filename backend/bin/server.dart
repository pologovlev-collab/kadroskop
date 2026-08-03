import 'dart:io';

import 'package:kadroskop_backend/kadroskop_server.dart';

Future<void> main() async {
  final localEnvironment = await _readLocalEnvironment();
  final port =
      int.tryParse(
        Platform.environment['PORT'] ?? localEnvironment['PORT'] ?? '',
      ) ??
      8080;
  final server = await startKadroskopServer(
    address: InternetAddress.anyIPv4,
    port: port,
    tmdbToken:
        Platform.environment['TMDB_ACCESS_TOKEN'] ??
        localEnvironment['TMDB_ACCESS_TOKEN'],
  );
  stdout.writeln(
    'Kadroskop backend: http://${server.address.host}:${server.port}',
  );
}

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
