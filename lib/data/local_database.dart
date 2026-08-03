import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/media_item.dart';

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
        version: 2,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await _createSchema(database);
          await _seed(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            for (final statement in _mediaV2Columns) {
              await database.execute(statement);
            }
            await _createEpisodeProgress(database);
            await _hydrateSeedMetadata(database);
          }
        },
      ),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _createSchema(Database database) async {
    await database.execute('''
      CREATE TABLE media (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        release_year INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL,
        rating REAL NOT NULL DEFAULT 0,
        genres TEXT NOT NULL DEFAULT '',
        color_a INTEGER NOT NULL,
        color_b INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'local',
        external_id TEXT,
        poster_url TEXT,
        runtime_minutes INTEGER NOT NULL DEFAULT 0,
        season_count INTEGER NOT NULL DEFAULT 0,
        episode_count INTEGER NOT NULL DEFAULT 0,
        episode_runtime_minutes INTEGER NOT NULL DEFAULT 0,
        seasons_json TEXT NOT NULL DEFAULT '[]',
        UNIQUE(source, external_id)
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
    await _createEpisodeProgress(database);
  }

  static Future<void> _createEpisodeProgress(Database database) =>
      database.execute('''
        CREATE TABLE IF NOT EXISTS episode_progress (
          media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
          season_number INTEGER NOT NULL,
          episode_number INTEGER NOT NULL,
          watched INTEGER NOT NULL DEFAULT 0,
          watched_at TEXT,
          PRIMARY KEY(media_id, season_number, episode_number)
        )
      ''');

  static Future<void> _seed(Database database) async {
    final batch = database.batch();
    for (final row in _seedMedia) {
      batch.insert('media', row.toDatabaseMap());
    }
    final now = DateTime.now().toIso8601String();
    batch.insert('user_media', {
      'media_id': 2,
      'status': 'watched',
      'updated_at': now,
    });
    batch.insert('user_media', {
      'media_id': 5,
      'status': 'watched',
      'updated_at': now,
    });
    batch.insert('user_media', {
      'media_id': 6,
      'status': 'planned',
      'updated_at': now,
    });
    await batch.commit(noResult: true);
  }

  static Future<void> _hydrateSeedMetadata(Database database) async {
    final batch = database.batch();
    for (final item in _seedMedia) {
      batch.update(
        'media',
        {
          'runtime_minutes': item.runtimeMinutes,
          'season_count': item.seasonCount,
          'episode_count': item.episodeCount,
          'episode_runtime_minutes': item.episodeRuntimeMinutes,
          'seasons_json': item.toDatabaseMap()['seasons_json'],
          'source': item.source,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    await batch.commit(noResult: true);
  }
}

const _mediaV2Columns = [
  "ALTER TABLE media ADD COLUMN source TEXT NOT NULL DEFAULT 'local'",
  'ALTER TABLE media ADD COLUMN external_id TEXT',
  'ALTER TABLE media ADD COLUMN poster_url TEXT',
  'ALTER TABLE media ADD COLUMN runtime_minutes INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE media ADD COLUMN season_count INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE media ADD COLUMN episode_count INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE media ADD COLUMN episode_runtime_minutes INTEGER NOT NULL DEFAULT 0',
  "ALTER TABLE media ADD COLUMN seasons_json TEXT NOT NULL DEFAULT '[]'",
];

const _seedMedia = <MediaItem>[
  MediaItem(
    id: 1,
    title: 'Полярная звезда',
    subtitle: 'Тихий космос помнит всё',
    description:
        'Пилот исследовательского корабля получает сигнал из места, которого нет ни на одной карте.',
    year: 2024,
    kind: MediaKind.movie,
    rating: 8.7,
    genres: ['Фантастика', 'Драма'],
    colors: [Color(0xFF071A31), Color(0xFF147FA3)],
    runtimeMinutes: 126,
  ),
  MediaItem(
    id: 2,
    title: 'Тень прошлого',
    subtitle: 'У каждого воспоминания две стороны',
    description:
        'Детектив возвращается в родной город и понимает, что его главное дело началось двадцать лет назад.',
    year: 2021,
    kind: MediaKind.series,
    rating: 8.3,
    genres: ['Триллер', 'Детектив'],
    colors: [Color(0xFF0C1220), Color(0xFF5E2637)],
    seasonCount: 3,
    episodeCount: 24,
    episodeRuntimeMinutes: 48,
    seasons: [
      SeasonInfo(number: 1, episodeCount: 8),
      SeasonInfo(number: 2, episodeCount: 8),
      SeasonInfo(number: 3, episodeCount: 8),
    ],
  ),
  MediaItem(
    id: 3,
    title: 'Дождь на стекле',
    subtitle: 'История одного потерянного лета',
    description:
        'Медленная история о случайной встрече, старой фотоплёнке и городе под бесконечным дождём.',
    year: 2019,
    kind: MediaKind.movie,
    rating: 7.9,
    genres: ['Драма', 'Мелодрама'],
    colors: [Color(0xFF172A36), Color(0xFFC7905B)],
    runtimeMinutes: 104,
  ),
  MediaItem(
    id: 4,
    title: 'По следам света',
    subtitle: 'Дорога начинается после заката',
    description:
        'Путешественница ищет заброшенные маяки и собирает истории людей, которых они когда-то спасли.',
    year: 2023,
    kind: MediaKind.documentary,
    rating: 8.1,
    genres: ['Путешествия', 'История'],
    colors: [Color(0xFF2B3B3B), Color(0xFFE3A63D)],
    runtimeMinutes: 92,
  ),
  MediaItem(
    id: 5,
    title: 'Интерстеллар',
    subtitle: 'Человечеству пора оставить колыбель',
    description:
        'Команда исследователей отправляется сквозь космический тоннель, чтобы найти новый дом для человечества.',
    year: 2014,
    kind: MediaKind.movie,
    rating: 8.7,
    genres: ['Фантастика', 'Приключения', 'Драма'],
    colors: [Color(0xFF243843), Color(0xFFC59D73)],
    runtimeMinutes: 169,
  ),
  MediaItem(
    id: 6,
    title: 'Лунный страж',
    subtitle: 'Ночь выбрала своего героя',
    description:
        'Юный хранитель снов защищает город от существ, которые крадут у людей самые дорогие воспоминания.',
    year: 2008,
    kind: MediaKind.anime,
    rating: 7.8,
    genres: ['Фэнтези', 'Приключения'],
    colors: [Color(0xFF111B38), Color(0xFF82559B)],
    seasonCount: 2,
    episodeCount: 26,
    episodeRuntimeMinutes: 24,
    seasons: [
      SeasonInfo(number: 1, episodeCount: 13),
      SeasonInfo(number: 2, episodeCount: 13),
    ],
  ),
  MediaItem(
    id: 7,
    title: 'Пустынный маршрут',
    subtitle: 'Ты точно видел это по телевизору',
    description:
        'Мальчик и механический зверь пересекают пустыню в поисках летающего города.',
    year: 2006,
    kind: MediaKind.animatedSeries,
    rating: 7.5,
    genres: ['Приключения', 'Фантастика'],
    colors: [Color(0xFF553526), Color(0xFFE2A553)],
    seasonCount: 2,
    episodeCount: 40,
    episodeRuntimeMinutes: 22,
    seasons: [
      SeasonInfo(number: 1, episodeCount: 20),
      SeasonInfo(number: 2, episodeCount: 20),
    ],
  ),
  MediaItem(
    id: 8,
    title: 'Сад на орбите',
    subtitle: 'Даже в пустоте растут цветы',
    description:
        'Смотритель последней космической оранжереи находит в ней незнакомое растение и тайное послание.',
    year: 2022,
    kind: MediaKind.anime,
    rating: 8.0,
    genres: ['Фантастика', 'Повседневность'],
    colors: [Color(0xFF183B3A), Color(0xFF68A46F)],
    seasonCount: 1,
    episodeCount: 12,
    episodeRuntimeMinutes: 24,
    seasons: [SeasonInfo(number: 1, episodeCount: 12)],
  ),
];
