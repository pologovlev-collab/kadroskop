import 'package:flutter/material.dart';

import 'data/local_database.dart';
import 'data/media_repository.dart';
import 'ui/kadroskop_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await LocalDatabase.open();
  runApp(KadroskopApp(repository: LocalMediaRepository(database)));
}
