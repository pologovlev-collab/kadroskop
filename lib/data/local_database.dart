import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._(this.database);

  final Database database;

  static Future<LocalDatabase> open() async {
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }

    final directory = await factory.getDatabasesPath();
    final db = await factory.openDatabase(
      p.join(directory, 'kadroskop.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE media (
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              subtitle TEXT NOT NULL,
              description TEXT NOT NULL,
              release_year INTEGER NOT NULL,
              kind TEXT NOT NULL,
              rating REAL NOT NULL,
              genres TEXT NOT NULL,
              color_a INTEGER NOT NULL,
              color_b INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE user_media (
              media_id INTEGER PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,
              status TEXT NOT NULL DEFAULT 'none',
              progress REAL NOT NULL DEFAULT 0,
              favorite INTEGER NOT NULL DEFAULT 0,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE interactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
              event_type TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await _seed(database);
        },
      ),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _seed(Database database) async {
    final batch = database.batch();
    for (final row in _seedMedia) {
      batch.insert('media', row);
    }
    batch.insert('user_media', {
      'media_id': 5,
      'status': 'watching',
      'progress': .64,
      'updated_at': DateTime.now().toIso8601String(),
    });
    batch.insert('user_media', {
      'media_id': 6,
      'status': 'planned',
      'progress': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await batch.commit(noResult: true);
  }
}

const _seedMedia = <Map<String, Object>>[
  {
    'id': 1,
    'title': 'Полярная звезда',
    'subtitle': 'Тихий космос помнит всё',
    'description':
        'Пилот исследовательского корабля получает сигнал из места, которого нет ни на одной карте.',
    'release_year': 2024,
    'kind': 'movie',
    'rating': 8.7,
    'genres': 'Фантастика,Драма',
    'color_a': 0xFF071A31,
    'color_b': 0xFF147FA3,
  },
  {
    'id': 2,
    'title': 'Тень прошлого',
    'subtitle': 'У каждого воспоминания две стороны',
    'description':
        'Детектив возвращается в родной город и понимает, что его главное дело началось двадцать лет назад.',
    'release_year': 2021,
    'kind': 'series',
    'rating': 8.3,
    'genres': 'Триллер,Детектив',
    'color_a': 0xFF0C1220,
    'color_b': 0xFF5E2637,
  },
  {
    'id': 3,
    'title': 'Дождь на стекле',
    'subtitle': 'История одного потерянного лета',
    'description':
        'Медленная история о случайной встрече, старой фотоплёнке и городе под бесконечным дождём.',
    'release_year': 2019,
    'kind': 'movie',
    'rating': 7.9,
    'genres': 'Драма,Мелодрама',
    'color_a': 0xFF172A36,
    'color_b': 0xFFC7905B,
  },
  {
    'id': 4,
    'title': 'По следам света',
    'subtitle': 'Дорога начинается после заката',
    'description':
        'Путешественница ищет заброшенные маяки и собирает истории людей, которых они когда-то спасли.',
    'release_year': 2023,
    'kind': 'documentary',
    'rating': 8.1,
    'genres': 'Путешествия,История',
    'color_a': 0xFF2B3B3B,
    'color_b': 0xFFE3A63D,
  },
  {
    'id': 5,
    'title': 'Интерстеллар',
    'subtitle': 'Человечеству пора оставить колыбель',
    'description':
        'Команда исследователей отправляется сквозь космический тоннель, чтобы найти новый дом для человечества.',
    'release_year': 2014,
    'kind': 'movie',
    'rating': 8.7,
    'genres': 'Фантастика,Приключения,Драма',
    'color_a': 0xFF243843,
    'color_b': 0xFFC59D73,
  },
  {
    'id': 6,
    'title': 'Лунный страж',
    'subtitle': 'Ночь выбрала своего героя',
    'description':
        'Юный хранитель снов защищает город от существ, которые крадут у людей самые дорогие воспоминания.',
    'release_year': 2008,
    'kind': 'anime',
    'rating': 7.8,
    'genres': 'Фэнтези,Приключения',
    'color_a': 0xFF111B38,
    'color_b': 0xFF82559B,
  },
  {
    'id': 7,
    'title': 'Пустынный маршрут',
    'subtitle': 'Ты точно видел это по телевизору',
    'description':
        'Мальчик и механический зверь пересекают пустыню в поисках летающего города.',
    'release_year': 2006,
    'kind': 'cartoon',
    'rating': 7.5,
    'genres': 'Приключения,Фантастика',
    'color_a': 0xFF553526,
    'color_b': 0xFFE2A553,
  },
  {
    'id': 8,
    'title': 'Сад на орбите',
    'subtitle': 'Даже в пустоте растут цветы',
    'description':
        'Смотритель последней космической оранжереи находит в ней незнакомое растение и тайное послание.',
    'release_year': 2022,
    'kind': 'anime',
    'rating': 8.0,
    'genres': 'Фантастика,Повседневность',
    'color_a': 0xFF183B3A,
    'color_b': 0xFF68A46F,
  },
];
