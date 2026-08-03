import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_profile.dart';
import '../models/media_item.dart';
import '../models/remember_search.dart';
import 'local_database.dart';

abstract interface class CatalogSource {
  Future<List<MediaItem>> search(String query, {MediaKind? kind});
  Future<CatalogPage> searchPage(String query, {MediaKind? kind, int page = 1});
  Future<CatalogPage> popular({MediaKind? kind, int page = 1});
  Future<MediaItem> details(MediaItem item);
  Future<RememberSearchResult> rememberSearch(RememberSearchFilters filters);
  Future<Map<String, dynamic>> diagnostics();
}

abstract interface class MediaRepository {
  Future<List<MediaItem>> loadMedia();
  Future<List<MediaItem>> searchCatalog(String query, {MediaKind? kind});
  Future<CatalogPage> searchCatalogPage(
    String query, {
    MediaKind? kind,
    int page = 1,
  });
  Future<CatalogPage> loadPopular({MediaKind? kind, int page = 1});
  Future<MediaItem> loadDetails(MediaItem item);
  Future<RememberSearchResult> rememberSearch(RememberSearchFilters filters);
  Future<Map<String, dynamic>> loadDiagnostics();
  Future<void> setStatus(MediaItem item, WatchStatus status);
  Future<void> setRating(MediaItem item, double? rating);
  Future<Map<String, int>> loadActivityByMonth();
  Future<AppProfile?> loadProfile();
  Future<AppProfile> registerLocalAccount({
    required String name,
    required String email,
    required String password,
  });
  Future<AppProfile> loginLocalAccount({
    required String email,
    required String password,
  });
  Future<AppProfile> continueAsGuest();
  Future<AppProfile> saveProfile(AppProfile profile);
  Future<void> logout();
  Future<String> exportCollection();
  Future<void> importCollection(String encoded);
  Future<void> clearCollection();
  Future<List<EpisodeProgress>> loadEpisodeProgress(int mediaId);
  Future<void> setEpisodeWatched(
    MediaItem item,
    int seasonNumber,
    int episodeNumber,
    bool watched,
  );
  Future<void> setAllEpisodesWatched(MediaItem item, bool watched);
  Future<void> recordInteraction(MediaItem item, String eventType);
}

class LocalMediaRepository implements MediaRepository {
  LocalMediaRepository(this._local, {CatalogSource? catalog})
    : _catalog = catalog;

  final LocalDatabase _local;
  final CatalogSource? _catalog;

  @override
  Future<List<MediaItem>> loadMedia() async {
    final rows = await _local.database.rawQuery('''
      SELECT m.*, COALESCE(u.status, 'none') AS status, u.user_rating
      FROM media m
      LEFT JOIN user_media u ON u.media_id = m.id
      ORDER BY CASE WHEN u.updated_at IS NULL THEN 1 ELSE 0 END,
               u.updated_at DESC,
               m.id
    ''');
    return rows.map(MediaItem.fromMap).toList();
  }

  @override
  Future<List<MediaItem>> searchCatalog(String query, {MediaKind? kind}) async {
    final normalized = query.trim().toLowerCase();
    final localItems = await loadMedia();
    final localMatches = localItems.where((item) {
      final matchesKind = kind == null || item.kind == kind;
      final matchesText =
          normalized.isEmpty ||
          item.title.toLowerCase().contains(normalized) ||
          item.description.toLowerCase().contains(normalized) ||
          item.genres.any((genre) => genre.toLowerCase().contains(normalized));
      return matchesKind && matchesText;
    }).toList();
    if (normalized.length < 2 || _catalog == null) return localMatches;

    final remoteMatches = await _catalog.search(query, kind: kind);
    final localBySource = {
      for (final item in localItems) '${item.source}:${item.externalId}': item,
    };
    return remoteMatches.map((item) {
      final saved = localBySource['${item.source}:${item.externalId}'];
      return saved == null ? item : item.copyWith(status: saved.status);
    }).toList();
  }

  @override
  Future<CatalogPage> searchCatalogPage(
    String query, {
    MediaKind? kind,
    int page = 1,
  }) async {
    if (_catalog == null) {
      return CatalogPage(
        items: await searchCatalog(query, kind: kind),
        page: page,
        hasMore: false,
        warnings: const [],
      );
    }
    final remote = await _catalog.searchPage(query, kind: kind, page: page);
    return CatalogPage(
      items: await _mergeSaved(remote.items),
      page: remote.page,
      hasMore: remote.hasMore,
      warnings: remote.warnings,
    );
  }

  @override
  Future<CatalogPage> loadPopular({MediaKind? kind, int page = 1}) async {
    if (_catalog == null) {
      return CatalogPage(
        items: const [],
        page: page,
        hasMore: false,
        warnings: const [],
      );
    }
    final remote = await _catalog.popular(kind: kind, page: page);
    return CatalogPage(
      items: await _mergeSaved(remote.items),
      page: remote.page,
      hasMore: remote.hasMore,
      warnings: remote.warnings,
    );
  }

  Future<List<MediaItem>> _mergeSaved(List<MediaItem> remote) async {
    final localItems = await loadMedia();
    final localBySource = {
      for (final item in localItems) '${item.source}:${item.externalId}': item,
    };
    return remote.map((item) {
      final saved = localBySource['${item.source}:${item.externalId}'];
      return saved == null ? item : item.copyWith(status: saved.status);
    }).toList();
  }

  @override
  Future<RememberSearchResult> rememberSearch(
    RememberSearchFilters filters,
  ) async {
    if (_catalog == null) {
      throw StateError('Backend поиска не настроен.');
    }
    return _catalog.rememberSearch(filters);
  }

  @override
  Future<Map<String, dynamic>> loadDiagnostics() async =>
      _catalog?.diagnostics() ??
      {
        'ok': false,
        'backend': {'status': 'unavailable'},
      };

  Future<void> _saveMedia(MediaItem item) async {
    final data = item.toDatabaseMap();
    await _local.database.insert(
      'media',
      data,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _local.database.update(
      'media',
      {...data}..remove('id'),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  @override
  Future<MediaItem> loadDetails(MediaItem item) async {
    if (_catalog == null || item.externalId == null) return item;
    final detailed = await _catalog.details(item);
    return detailed.copyWith(status: item.status);
  }

  @override
  Future<void> setStatus(MediaItem item, WatchStatus status) async {
    await _saveMedia(item);
    final now = DateTime.now().toIso8601String();
    await _local.database.rawInsert(
      '''
      INSERT INTO user_media (media_id, status, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(media_id) DO UPDATE SET
        status = excluded.status,
        updated_at = excluded.updated_at
      ''',
      [item.id, status.name, now],
    );
    await _local.database.insert('interactions', {
      'media_id': item.id,
      'event_type': 'status_${status.name}',
      'created_at': now,
    });
  }

  @override
  Future<void> setRating(MediaItem item, double? rating) async {
    if (rating != null && (rating < 0 || rating > 10)) {
      throw ArgumentError.value(
        rating,
        'rating',
        'Оценка должна быть от 0 до 10',
      );
    }
    await _saveMedia(item);
    final now = DateTime.now().toIso8601String();
    await _local.database.rawInsert(
      '''
      INSERT INTO user_media (media_id, status, user_rating, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(media_id) DO UPDATE SET
        user_rating = excluded.user_rating,
        updated_at = excluded.updated_at
      ''',
      [item.id, item.status.name, rating, now],
    );
    await _local.database.insert('interactions', {
      'media_id': item.id,
      'event_type': 'rated',
      'created_at': now,
    });
  }

  @override
  Future<Map<String, int>> loadActivityByMonth() async {
    final rows = await _local.database.rawQuery('''
      SELECT substr(created_at, 1, 7) AS month, COUNT(*) AS total
      FROM interactions
      WHERE event_type LIKE 'status_%' OR event_type = 'rated'
      GROUP BY substr(created_at, 1, 7)
      ORDER BY month
    ''');
    return {
      for (final row in rows)
        row['month'] as String: (row['total'] as num).toInt(),
    };
  }

  @override
  Future<AppProfile?> loadProfile() async {
    final rows = await _local.database.query(
      'app_profile',
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : AppProfile.fromMap(rows.first);
  }

  @override
  Future<AppProfile> registerLocalAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.length < 2) throw ArgumentError('Введите имя.');
    if (!cleanEmail.contains('@')) {
      throw ArgumentError('Введите корректный email.');
    }
    if (password.length < 6) {
      throw ArgumentError('Пароль должен содержать минимум 6 символов.');
    }
    final salt = _randomSalt();
    await _local.database.insert('app_profile', {
      'id': 1,
      'name': cleanName,
      'email': cleanEmail,
      'password_salt': salt,
      'password_hash': _passwordHash(password, salt),
      'is_guest': 0,
      'favorite_genres': '',
      'dark_theme': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return (await loadProfile())!;
  }

  @override
  Future<AppProfile> loginLocalAccount({
    required String email,
    required String password,
  }) async {
    final rows = await _local.database.query(
      'app_profile',
      where: 'id = 1 AND is_guest = 0',
      limit: 1,
    );
    if (rows.isEmpty ||
        (rows.first['email'] as String).toLowerCase() !=
            email.trim().toLowerCase()) {
      throw StateError('Аккаунт с таким email не найден на этом устройстве.');
    }
    final salt = rows.first['password_salt'] as String? ?? '';
    if (_passwordHash(password, salt) != rows.first['password_hash']) {
      throw StateError('Неверный пароль.');
    }
    return AppProfile.fromMap(rows.first);
  }

  @override
  Future<AppProfile> continueAsGuest() async {
    await _local.database.insert('app_profile', {
      'id': 1,
      'name': 'Гость',
      'email': '',
      'is_guest': 1,
      'favorite_genres': '',
      'dark_theme': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return (await loadProfile())!;
  }

  @override
  Future<AppProfile> saveProfile(AppProfile profile) async {
    await _local.database.update('app_profile', {
      'name': profile.name.trim(),
      'email': profile.email.trim().toLowerCase(),
      'is_guest': profile.isGuest ? 1 : 0,
      'favorite_genres': profile.favoriteGenres.join(','),
      'dark_theme': profile.darkTheme ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
    return (await loadProfile())!;
  }

  @override
  Future<void> logout() =>
      _local.database.delete('app_profile', where: 'id = 1');

  @override
  Future<String> exportCollection() async {
    final media = await _local.database.rawQuery('''
      SELECT m.*, u.status, u.progress, u.favorite, u.user_rating, u.updated_at
      FROM media m
      INNER JOIN user_media u ON u.media_id = m.id
      WHERE u.status != 'none'
    ''');
    final episodes = await _local.database.query('episode_progress');
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'kadroskop.collection',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'media': media,
      'episodeProgress': episodes,
    });
  }

  @override
  Future<void> importCollection(String encoded) async {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['format'] != 'kadroskop.collection') {
      throw const FormatException('Это не файл коллекции Кадроскопа.');
    }
    final mediaRows = decoded['media'];
    final episodeRows = decoded['episodeProgress'];
    if (mediaRows is! List || episodeRows is! List) {
      throw const FormatException('Файл коллекции повреждён.');
    }
    await _local.database.transaction((transaction) async {
      for (final raw in mediaRows) {
        final row = (raw as Map).cast<String, Object?>();
        final media = <String, Object?>{
          for (final key in _mediaExportColumns)
            if (row.containsKey(key)) key: row[key],
        };
        await transaction.insert(
          'media',
          media,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await transaction.insert('user_media', {
          'media_id': row['id'],
          'status': row['status'] ?? 'planned',
          'progress': row['progress'] ?? 0,
          'favorite': row['favorite'] ?? 0,
          'user_rating': row['user_rating'],
          'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final raw in episodeRows) {
        await transaction.insert(
          'episode_progress',
          (raw as Map).cast<String, Object?>(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> clearCollection() async {
    await _local.database.transaction((transaction) async {
      await transaction.delete('episode_progress');
      await transaction.delete('interactions');
      await transaction.delete('user_media');
      await transaction.delete('media');
    });
  }

  @override
  Future<List<EpisodeProgress>> loadEpisodeProgress(int mediaId) async {
    final rows = await _local.database.query(
      'episode_progress',
      where: 'media_id = ? AND watched = 1',
      whereArgs: [mediaId],
      orderBy: 'season_number, episode_number',
    );
    return rows
        .map(
          (row) => EpisodeProgress(
            seasonNumber: row['season_number']! as int,
            episodeNumber: row['episode_number']! as int,
            watched: (row['watched']! as int) == 1,
          ),
        )
        .toList();
  }

  @override
  Future<void> setEpisodeWatched(
    MediaItem item,
    int seasonNumber,
    int episodeNumber,
    bool watched,
  ) async {
    await _saveMedia(item);
    await _local.database.insert('episode_progress', {
      'media_id': item.id,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'watched': watched ? 1 : 0,
      'watched_at': watched ? DateTime.now().toIso8601String() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final watchedCount =
        Sqflite.firstIntValue(
          await _local.database.rawQuery(
            'SELECT COUNT(*) FROM episode_progress WHERE media_id = ? AND watched = 1',
            [item.id],
          ),
        ) ??
        0;
    await setStatus(
      item,
      watchedCount >= item.episodeCount && item.episodeCount > 0
          ? WatchStatus.watched
          : watchedCount > 0
          ? WatchStatus.watching
          : WatchStatus.planned,
    );
  }

  @override
  Future<void> setAllEpisodesWatched(MediaItem item, bool watched) async {
    await _saveMedia(item);
    await _local.database.transaction((transaction) async {
      await transaction.delete(
        'episode_progress',
        where: 'media_id = ?',
        whereArgs: [item.id],
      );
      if (watched) {
        final batch = transaction.batch();
        for (final season in _seasonsFor(item)) {
          for (var episode = 1; episode <= season.episodeCount; episode++) {
            batch.insert('episode_progress', {
              'media_id': item.id,
              'season_number': season.number,
              'episode_number': episode,
              'watched': 1,
              'watched_at': DateTime.now().toIso8601String(),
            });
          }
        }
        await batch.commit(noResult: true);
      }
    });
    await setStatus(item, watched ? WatchStatus.watched : WatchStatus.planned);
  }

  @override
  Future<void> recordInteraction(MediaItem item, String eventType) async {
    await _saveMedia(item);
    await _local.database.insert('interactions', {
      'media_id': item.id,
      'event_type': eventType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class MemoryMediaRepository implements MediaRepository {
  MemoryMediaRepository(this.items);

  List<MediaItem> items;
  final Map<int, List<EpisodeProgress>> _episodeProgress = {};
  AppProfile? profile = const AppProfile(
    name: 'Тестовый пользователь',
    email: '',
    isGuest: true,
    favoriteGenres: [],
    darkTheme: false,
  );

  @override
  Future<List<MediaItem>> loadMedia() async => items;

  @override
  Future<List<MediaItem>> searchCatalog(String query, {MediaKind? kind}) async {
    final normalized = query.toLowerCase();
    return items
        .where(
          (item) =>
              (kind == null || item.kind == kind) &&
              item.title.toLowerCase().contains(normalized),
        )
        .toList();
  }

  @override
  Future<CatalogPage> searchCatalogPage(
    String query, {
    MediaKind? kind,
    int page = 1,
  }) async => CatalogPage(
    items: await searchCatalog(query, kind: kind),
    page: page,
    hasMore: false,
    warnings: const [],
  );

  @override
  Future<CatalogPage> loadPopular({MediaKind? kind, int page = 1}) async =>
      CatalogPage(
        items: items
            .where((item) => kind == null || item.kind == kind)
            .toList(),
        page: page,
        hasMore: false,
        warnings: const [],
      );

  @override
  Future<RememberSearchResult> rememberSearch(
    RememberSearchFilters filters,
  ) async => const RememberSearchResult(
    candidates: [],
    warnings: [],
    ai: {'provider': 'none', 'status': 'disabled'},
  );

  @override
  Future<Map<String, dynamic>> loadDiagnostics() async => {
    'ok': true,
    'backend': {'status': 'memory'},
  };

  @override
  Future<MediaItem> loadDetails(MediaItem item) async => item;

  @override
  Future<void> recordInteraction(MediaItem item, String eventType) async {}

  @override
  Future<void> setStatus(MediaItem item, WatchStatus status) async {
    items = items
        .map(
          (existing) =>
              existing.id == item.id ? item.copyWith(status: status) : existing,
        )
        .toList();
  }

  @override
  Future<void> setRating(MediaItem item, double? rating) async {
    items = items
        .map(
          (existing) => existing.id == item.id
              ? item.copyWith(userRating: rating)
              : existing,
        )
        .toList();
  }

  @override
  Future<Map<String, int>> loadActivityByMonth() async => const {};

  @override
  Future<AppProfile?> loadProfile() async => profile;

  @override
  Future<AppProfile> continueAsGuest() async => profile!;

  @override
  Future<AppProfile> registerLocalAccount({
    required String name,
    required String email,
    required String password,
  }) async => profile = AppProfile(
    name: name,
    email: email,
    isGuest: false,
    favoriteGenres: const [],
    darkTheme: false,
  );

  @override
  Future<AppProfile> loginLocalAccount({
    required String email,
    required String password,
  }) async => profile!;

  @override
  Future<AppProfile> saveProfile(AppProfile value) async => profile = value;

  @override
  Future<void> logout() async => profile = null;

  @override
  Future<String> exportCollection() async => jsonEncode({
    'format': 'kadroskop.collection',
    'version': 1,
    'media': const [],
    'episodeProgress': const [],
  });

  @override
  Future<void> importCollection(String encoded) async {
    jsonDecode(encoded);
  }

  @override
  Future<void> clearCollection() async {
    items = const [];
    _episodeProgress.clear();
  }

  @override
  Future<List<EpisodeProgress>> loadEpisodeProgress(int mediaId) async =>
      _episodeProgress[mediaId] ?? const [];

  @override
  Future<void> setEpisodeWatched(
    MediaItem item,
    int seasonNumber,
    int episodeNumber,
    bool watched,
  ) async {
    final values = <EpisodeProgress>[
      ...(_episodeProgress[item.id] ?? const <EpisodeProgress>[]),
    ];
    values.removeWhere(
      (value) =>
          value.seasonNumber == seasonNumber &&
          value.episodeNumber == episodeNumber,
    );
    if (watched) {
      values.add(
        EpisodeProgress(
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          watched: true,
        ),
      );
    }
    _episodeProgress[item.id] = values;
    await setStatus(
      item,
      values.isNotEmpty ? WatchStatus.watching : WatchStatus.planned,
    );
  }

  @override
  Future<void> setAllEpisodesWatched(MediaItem item, bool watched) async {
    _episodeProgress[item.id] = watched
        ? [
            for (final season in _seasonsFor(item))
              for (var episode = 1; episode <= season.episodeCount; episode++)
                EpisodeProgress(
                  seasonNumber: season.number,
                  episodeNumber: episode,
                  watched: true,
                ),
          ]
        : [];
    await setStatus(item, watched ? WatchStatus.watched : WatchStatus.planned);
  }
}

List<SeasonInfo> _seasonsFor(MediaItem item) {
  if (item.seasons.isNotEmpty) return item.seasons;
  final seasonCount = item.seasonCount <= 0 ? 1 : item.seasonCount;
  final perSeason = item.episodeCount <= 0
      ? 12
      : (item.episodeCount / seasonCount).ceil();
  return [
    for (var number = 1; number <= seasonCount; number++)
      SeasonInfo(number: number, episodeCount: perSeason),
  ];
}

String _randomSalt() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
}

String _passwordHash(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();

const _mediaExportColumns = {
  'id',
  'title',
  'subtitle',
  'description',
  'release_year',
  'kind',
  'rating',
  'genres',
  'color_a',
  'color_b',
  'source',
  'external_id',
  'poster_url',
  'runtime_minutes',
  'season_count',
  'episode_count',
  'episode_runtime_minutes',
  'seasons_json',
};
