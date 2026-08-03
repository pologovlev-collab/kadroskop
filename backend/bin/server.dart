import 'dart:io';

import 'package:kadroskop_backend/kadroskop_server.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await startKadroskopServer(
    address: InternetAddress.anyIPv4,
    port: port,
    tmdbToken: Platform.environment['TMDB_ACCESS_TOKEN'],
  );
  stdout.writeln(
    'Kadroskop backend: http://${server.address.host}:${server.port}',
  );
}
