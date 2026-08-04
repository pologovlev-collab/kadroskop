import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_profile.dart';
import '../models/media_item.dart';
import '../models/recommendation.dart';
import '../models/remember_search.dart';
import '../models/similar_media.dart';
import 'local_database.dart';

abstract interface class CatalogSource {
  Future<List<MediaItem>> search(String query, {MediaKind? kind});
  Future<CatalogPage> searchPage(String query, {MediaKind? kind, int page = 1});
  Future<CatalogPage> popular({MediaKind? kind, int page = 1});
  Future<MediaItem> details(MediaItem item);
  Future<RememberSearchResult> rememberSearch(RememberSearchFilters filters);
  Future<RecommendationPage> recommendations({
    required List<RecommendationSeed> seeds,
    Set<String> excluded = const {},
    MediaKind? kind,
    int page = 1,
    bool refresh = false,
  });
  Future<SimilarMediaPage> similar(
    MediaItem item, {
    SimilarMode mode = SimilarMode.overall,
    int page = 1,
    bool refresh = false,
  });
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
  Future<RecommendationPage> loadRecommendations({
    MediaKind? kind,
    int page = 1,
    bool refresh = false,
  });
  Future<SimilarMediaPage> loadSimilar(
    MediaItem item, {
    SimilarMode mode = SimilarMode.overall,
    int page = 1,
    bool refresh = false,
  });
  Future<Map<String, dynamic>> loadDiagnostics();
  Future<void> setStatus(
    MediaItem item,
    WatchStatus status, {
    bool resetProgress = false,
  });
  Future<void> setFavorite(MediaItem item, bool favorite);
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
  Future<int> setEpisodeRange(
    MediaItem item,
    Iterable<int> episodeNumbers,
    bool watched,
  );
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
      SELECT m.*, COALESCE(u.status, 'none') AS status, u.user_rating,
             COALESCE(u.favorite, 0) AS favorite, u.favorite_updated_at,
             COALESCE(u.watched_episode_count, 0) AS watched_episode_count,
             COALESCE(u.watched_minutes, 0) AS watched_minutes
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
      return saved == null
          ? item
          : item.copyWith(
              status: saved.status,
              userRating: saved.userRating,
              isFavorite: saved.isFavorite,
              favoriteUpdatedAt: saved.favoriteUpdatedAt,
              watchedEpisodeCount: saved.watchedEpisodeCount,
              watchedMinutes: saved.watchedMinutes,
            );
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
      return saved == null
          ? item
          : item.copyWith(
              status: saved.status,
              userRating: saved.userRating,
              isFavorite: saved.isFavorite,
              favoriteUpdatedAt: saved.favoriteUpdatedAt,
              watchedEpisodeCount: saved.watchedEpisodeCount,
              watchedMinutes: saved.watchedMinutes,
            );
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
  Future<RecommendationPage> loadRecommendations({
    MediaKind? kind,
    int page = 1,
    bool refresh = false,
  }) async {
    if (_catalog == null) {
      return const RecommendationPage(
        items: [],
        page: 1,
        hasMore: false,
        warnings: [],
        guidance: 'Backend рекомендаций не настроен.',
      );
    }
    final media = await loadMedia();
    final seeds = <RecommendationSeed>[];
    final excluded = <String>{};
    for (final item in media) {
      final externalId = item.externalId;
      if (externalId == null || item.source == 'local') continue;
      final identity = '${item.source}:$externalId';
      if (item.status == WatchStatus.watched ||
          item.status == WatchStatus.dropped ||
          (item.userRating != null && item.userRating! <= 4)) {
        excluded.add(identity);
      }
      final weight = _recommendationWeight(item);
      if (weight > 0) {
        seeds.add(
          RecommendationSeed(
            source: item.source,
            sourceId: externalId,
            weight: weight,
          ),
        );
      }
    }
    final pageResult = await _catalog.recommendations(
      seeds: seeds,
      excluded: excluded,
      kind: kind,
      page: page,
      refresh: refresh,
    );
    final saved = await loadMedia();
    final savedByIdentity = {
      for (final item in saved)
        if (item.externalId != null) '${item.source}:${item.externalId}': item,
    };
    return RecommendationPage(
      items: pageResult.items.map((entry) {
        final item = entry.media;
        final local = savedByIdentity['${item.source}:${item.externalId}'];
        return local == null
            ? entry
            : RecommendationItem(
                media: item.copyWith(
                  status: local.status,
                  userRating: local.userRating,
                  isFavorite: local.isFavorite,
                  favoriteUpdatedAt: local.favoriteUpdatedAt,
                  watchedEpisodeCount: local.watchedEpisodeCount,
                  watchedMinutes: local.watchedMinutes,
                ),
                score: entry.score,
                reasons: entry.reasons,
              );
      }).toList(),
      page: pageResult.page,
      hasMore: pageResult.hasMore,
      warnings: pageResult.warnings,
      guidance: pageResult.guidance,
    );
  }

  @override
  Future<SimilarMediaPage> loadSimilar(
    MediaItem item, {
    SimilarMode mode = SimilarMode.overall,
    int page = 1,
    bool refresh = false,
  }) async {
    if (_catalog == null || item.externalId == null) {
      return const SimilarMediaPage(
        items: [],
        page: 1,
        hasMore: false,
        warnings: [],
        guidance: 'Для локального произведения похожие пока недоступны.',
      );
    }
    final result = await _catalog.similar(
      item,
      mode: mode,
      page: page,
      refresh: refresh,
    );
    final local = await loadMedia();
    final byIdentity = {
      for (final saved in local)
        if (saved.externalId != null)
          '${saved.source}:${saved.externalId}': saved,
    };
    return SimilarMediaPage(
      items: result.items.map((entry) {
        final saved =
            byIdentity['${entry.media.source}:${entry.media.externalId}'];
        if (saved == null) return entry;
        return SimilarMediaItem(
          media: entry.media.copyWith(
            status: saved.status,
            userRating: saved.userRating,
            isFavorite: saved.isFavorite,
            favoriteUpdatedAt: saved.favoriteUpdatedAt,
            watchedEpisodeCount: saved.watchedEpisodeCount,
            watchedMinutes: saved.watchedMinutes,
          ),
          score: entry.score,
          reasons: entry.reasons,
          breakdown: entry.breakdown,
        );
      }).toList(),
      page: result.page,
      hasMore: result.hasMore,
      warnings: result.warnings,
      guidance: result.guidance,
    );
  }

  @override
  Future<Map<String, dynamic>> loadDiagnostics() async =>
      _catalog?.diagnostics() ??
      {
        'ok': false,
        'backend': {'status': 'unavailable'},
      };

  Future<void> _saveMedia(MediaItem item) async {
    await _saveMediaWith(_local.database, item);
  }

  Future<void> _saveMediaWith(DatabaseExecutor executor, MediaItem item) async {
    final data = item.toDatabaseMap();
    await executor.insert(
      'media',
      data,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await executor.update(
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
    return detailed.copyWith(
      status: item.status,
      userRating: item.userRating,
      isFavorite: item.isFavorite,
      favoriteUpdatedAt: item.favoriteUpdatedAt,
      watchedEpisodeCount: item.watchedEpisodeCount,
      watchedMinutes: item.watchedMinutes,
    );
  }

  @override
  Future<void> setStatus(
    MediaItem item,
    WatchStatus status, {
    bool resetProgress = false,
  }) async {
    final shouldReset = resetProgress || status == WatchStatus.none;
    final totalEpisodes = _totalEpisodeCapacity(item);
    if (item.isEpisodic && status == WatchStatus.watched && totalEpisodes < 1) {
      throw StateError('Каталог не сообщил количество эпизодов.');
    }
    await _local.database.transaction((transaction) async {
      await _saveMediaWith(transaction, item);
      final now = DateTime.now().toIso8601String();
      if (item.isEpisodic && status == WatchStatus.watched) {
        await transaction.delete(
          'episode_progress',
          where: 'media_id = ?',
          whereArgs: [item.id],
        );
        final batch = transaction.batch();
        for (final coordinate in _episodeCoordinates(item)) {
          batch.insert('episode_progress', {
            'media_id': item.id,
            'season_number': coordinate.$1,
            'episode_number': coordinate.$2,
            'watched': 1,
            'watched_at': now,
          });
        }
        await batch.commit(noResult: true);
        await _reconcileItemProgress(
          transaction,
          item,
          now: now,
          forceStatus: WatchStatus.watched,
        );
      } else if (shouldReset) {
        await transaction.delete(
          'episode_progress',
          where: 'media_id = ?',
          whereArgs: [item.id],
        );
        await _reconcileItemProgress(
          transaction,
          item,
          now: now,
          forceStatus: status,
        );
      } else {
        await transaction.rawInsert(
          '''
          INSERT INTO user_media (media_id, status, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(media_id) DO UPDATE SET
            status = excluded.status,
            updated_at = excluded.updated_at
          ''',
          [item.id, status.name, now],
        );
      }
      await transaction.insert('interactions', {
        'media_id': item.id,
        'event_type': shouldReset
            ? 'status_${status.name}_progress_reset'
            : 'status_${status.name}',
        'created_at': now,
      });
    });
  }

  @override
  Future<void> setFavorite(MediaItem item, bool favorite) async {
    await _saveMedia(item);
    final now = DateTime.now().toIso8601String();
    await _local.database.rawInsert(
      '''
      INSERT INTO user_media (
        media_id, status, favorite, favorite_updated_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(media_id) DO UPDATE SET
        favorite = excluded.favorite,
        favorite_updated_at = excluded.favorite_updated_at,
        updated_at = excluded.updated_at
      ''',
      [item.id, item.status.name, favorite ? 1 : 0, now, now],
    );
    await _local.database.insert('interactions', {
      'media_id': item.id,
      'event_type': favorite ? 'favorite_added' : 'favorite_removed',
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
      WHERE event_type LIKE 'status_%'
         OR event_type LIKE 'episode_%'
         OR event_type LIKE 'episodes_%'
         OR event_type = 'rated'
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
    if (rows.isEmpty || rows.first['signed_in'] == 0) return null;
    if (rows.first['signed_in'] == 2) {
      return const AppProfile(
        name: 'Гость',
        email: '',
        isGuest: true,
        favoriteGenres: [],
        darkTheme: false,
      );
    }
    return AppProfile.fromMap(rows.first);
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
      'signed_in': 1,
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
    await _local.database.update('app_profile', {
      'signed_in': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
    return (await loadProfile())!;
  }

  @override
  Future<AppProfile> continueAsGuest() async {
    final rows = await _local.database.query('app_profile', where: 'id = 1');
    if (rows.isEmpty) {
      await _local.database.insert('app_profile', {
        'id': 1,
        'name': 'Гость',
        'email': '',
        'is_guest': 1,
        'favorite_genres': '',
        'dark_theme': 0,
        'signed_in': 2,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      await _local.database.update('app_profile', {
        'signed_in': 2,
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    }
    return (await loadProfile())!;
  }

  @override
  Future<AppProfile> saveProfile(AppProfile profile) async {
    final current = await _local.database.query(
      'app_profile',
      where: 'id = 1',
      limit: 1,
    );
    if (current.isNotEmpty &&
        current.first['signed_in'] == 2 &&
        current.first['is_guest'] == 0) {
      return profile;
    }
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
  Future<void> logout() => _local.database.update('app_profile', {
    'signed_in': 0,
    'updated_at': DateTime.now().toIso8601String(),
  }, where: 'id = 1');

  @override
  Future<String> exportCollection() async {
    final media = await _local.database.rawQuery('''
      SELECT m.*, u.status, u.progress, u.favorite, u.user_rating, u.updated_at
      FROM media m
      INNER JOIN user_media u ON u.media_id = m.id
      WHERE u.status != 'none' OR u.favorite = 1
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
          'favorite_updated_at': row['favorite_updated_at'],
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
    await _local.reconcileEpisodeProgress();
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
    _validateEpisode(item, seasonNumber, episodeNumber);
    await _local.database.transaction((transaction) async {
      await _saveMediaWith(transaction, item);
      final now = DateTime.now().toIso8601String();
      if (watched) {
        await transaction.insert('episode_progress', {
          'media_id': item.id,
          'season_number': seasonNumber,
          'episode_number': episodeNumber,
          'watched': 1,
          'watched_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await transaction.delete(
          'episode_progress',
          where: 'media_id = ? AND season_number = ? AND episode_number = ?',
          whereArgs: [item.id, seasonNumber, episodeNumber],
        );
      }
      await _reconcileItemProgress(transaction, item, now: now);
      await transaction.insert('interactions', {
        'media_id': item.id,
        'event_type': watched ? 'episode_watched' : 'episode_unwatched',
        'created_at': now,
      });
    });
  }

  @override
  Future<void> setAllEpisodesWatched(MediaItem item, bool watched) async {
    if (watched && _totalEpisodeCapacity(item) < 1) {
      throw StateError('Каталог не сообщил количество эпизодов.');
    }
    await _local.database.transaction((transaction) async {
      await _saveMediaWith(transaction, item);
      final now = DateTime.now().toIso8601String();
      await transaction.delete(
        'episode_progress',
        where: 'media_id = ?',
        whereArgs: [item.id],
      );
      if (watched) {
        final batch = transaction.batch();
        for (final coordinate in _episodeCoordinates(item)) {
          batch.insert('episode_progress', {
            'media_id': item.id,
            'season_number': coordinate.$1,
            'episode_number': coordinate.$2,
            'watched': 1,
            'watched_at': now,
          });
        }
        await batch.commit(noResult: true);
      }
      await _reconcileItemProgress(
        transaction,
        item,
        now: now,
        forceStatus: watched ? WatchStatus.watched : WatchStatus.planned,
      );
      await transaction.insert('interactions', {
        'media_id': item.id,
        'event_type': watched ? 'episodes_all_watched' : 'episodes_cleared',
        'created_at': now,
      });
    });
  }

  @override
  Future<int> setEpisodeRange(
    MediaItem item,
    Iterable<int> episodeNumbers,
    bool watched,
  ) async {
    final total = _totalEpisodeCapacity(item);
    final numbers = episodeNumbers.toSet().toList()..sort();
    if (numbers.isEmpty) return 0;
    if (numbers.first < 1 || numbers.last > total) {
      throw RangeError('Диапазон выходит за пределы 1–$total.');
    }
    await _local.database.transaction((transaction) async {
      await _saveMediaWith(transaction, item);
      final now = DateTime.now().toIso8601String();
      final batch = transaction.batch();
      for (final number in numbers) {
        final coordinate = _episodeCoordinate(item, number);
        if (watched) {
          batch.insert('episode_progress', {
            'media_id': item.id,
            'season_number': coordinate.$1,
            'episode_number': coordinate.$2,
            'watched': 1,
            'watched_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          batch.delete(
            'episode_progress',
            where: 'media_id = ? AND season_number = ? AND episode_number = ?',
            whereArgs: [item.id, coordinate.$1, coordinate.$2],
          );
        }
      }
      await batch.commit(noResult: true);
      await _reconcileItemProgress(transaction, item, now: now);
      await transaction.insert('interactions', {
        'media_id': item.id,
        'event_type': watched
            ? 'episodes_range_watched'
            : 'episodes_range_unwatched',
        'created_at': now,
      });
    });
    return numbers.length;
  }

  void _validateEpisode(MediaItem item, int seasonNumber, int episodeNumber) {
    if (episodeNumber < 1) {
      throw RangeError.range(episodeNumber, 1, null, 'episodeNumber');
    }
    if (item.seasons.isEmpty) {
      if (seasonNumber != 0 ||
          item.episodeCount <= 0 ||
          episodeNumber > item.episodeCount) {
        throw RangeError('Эпизод отсутствует в данных каталога.');
      }
      return;
    }
    final season = item.seasons
        .where((value) => value.number == seasonNumber)
        .firstOrNull;
    if (season == null || episodeNumber > season.episodeCount) {
      throw RangeError('Эпизод отсутствует в данных каталога.');
    }
  }

  Future<void> _reconcileItemProgress(
    DatabaseExecutor executor,
    MediaItem item, {
    required String now,
    WatchStatus? forceStatus,
  }) async {
    final watchedCount =
        Sqflite.firstIntValue(
          await executor.rawQuery(
            'SELECT COUNT(*) FROM episode_progress WHERE media_id = ? AND watched = 1',
            [item.id],
          ),
        ) ??
        0;
    final currentRows = await executor.query(
      'user_media',
      columns: ['status'],
      where: 'media_id = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    final current = currentRows.isEmpty
        ? item.status
        : WatchStatus.values.firstWhere(
            (value) => value.name == currentRows.first['status'],
            orElse: () => item.status,
          );
    final totalEpisodes = _totalEpisodeCapacity(item);
    final status =
        forceStatus ??
        (watchedCount >= totalEpisodes && totalEpisodes > 0
            ? WatchStatus.watched
            : watchedCount > 0
            ? current == WatchStatus.dropped
                  ? WatchStatus.dropped
                  : WatchStatus.watching
            : current == WatchStatus.dropped
            ? WatchStatus.dropped
            : current == WatchStatus.none
            ? WatchStatus.none
            : WatchStatus.planned);
    await executor.rawInsert(
      '''
      INSERT INTO user_media (
        media_id, status, watched_episode_count, watched_minutes, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(media_id) DO UPDATE SET
        status = excluded.status,
        watched_episode_count = excluded.watched_episode_count,
        watched_minutes = excluded.watched_minutes,
        updated_at = excluded.updated_at
      ''',
      [
        item.id,
        status.name,
        watchedCount,
        watchedCount * item.episodeRuntimeMinutes,
        now,
      ],
    );
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
  Future<RecommendationPage> loadRecommendations({
    MediaKind? kind,
    int page = 1,
    bool refresh = false,
  }) async {
    final values = items
        .where((item) => kind == null || item.kind == kind)
        .where((item) => item.status != WatchStatus.dropped)
        .map(
          (item) => RecommendationItem(
            media: item,
            score: _recommendationWeight(item),
            reasons: const ['На основе локальной тестовой коллекции'],
          ),
        )
        .toList();
    return RecommendationPage(
      items: values,
      page: page,
      hasMore: false,
      warnings: const [],
      guidance: values.isEmpty ? 'Добавьте произведения в избранное.' : null,
    );
  }

  @override
  Future<SimilarMediaPage> loadSimilar(
    MediaItem item, {
    SimilarMode mode = SimilarMode.overall,
    int page = 1,
    bool refresh = false,
  }) async {
    final normalizedGenres = item.genres.map((genre) => genre.toLowerCase());
    final values = items
        .where((candidate) => candidate.id != item.id)
        .where(
          (candidate) => candidate.genres.any(
            (genre) => normalizedGenres.contains(genre.toLowerCase()),
          ),
        )
        .map(
          (candidate) => SimilarMediaItem(
            media: candidate,
            score: 50,
            reasons: const ['Совпадают жанры'],
            breakdown: const {'genres': 50},
          ),
        )
        .toList();
    return SimilarMediaPage(
      items: values,
      page: page,
      hasMore: false,
      warnings: const [],
      guidance: values.isEmpty ? 'Похожие произведения не найдены.' : null,
    );
  }

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
  Future<void> setStatus(
    MediaItem item,
    WatchStatus status, {
    bool resetProgress = false,
  }) async {
    final total = _totalEpisodeCapacity(item);
    if (item.isEpisodic && status == WatchStatus.watched && total < 1) {
      throw StateError('Каталог не сообщил количество эпизодов.');
    }
    final shouldReset = resetProgress || status == WatchStatus.none;
    if (item.isEpisodic && status == WatchStatus.watched) {
      _episodeProgress[item.id] = [
        for (final coordinate in _episodeCoordinates(item))
          EpisodeProgress(
            seasonNumber: coordinate.$1,
            episodeNumber: coordinate.$2,
            watched: true,
          ),
      ];
    } else if (shouldReset) {
      _episodeProgress[item.id] = [];
    }
    final watchedCount = _episodeProgress[item.id]?.length ?? 0;
    items = items
        .map(
          (existing) => existing.id == item.id
              ? existing.copyWith(
                  status: status,
                  watchedEpisodeCount: watchedCount,
                  watchedMinutes: watchedCount * item.episodeRuntimeMinutes,
                )
              : existing,
        )
        .toList();
  }

  @override
  Future<void> setFavorite(MediaItem item, bool favorite) async {
    items = items
        .map(
          (existing) => existing.id == item.id
              ? item.copyWith(
                  isFavorite: favorite,
                  favoriteUpdatedAt: DateTime.now(),
                )
              : existing,
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
    final current = items.firstWhere(
      (candidate) => candidate.id == item.id,
      orElse: () => item,
    );
    final count = values.length;
    final status = count >= item.episodeCount && item.episodeCount > 0
        ? WatchStatus.watched
        : count > 0
        ? current.status == WatchStatus.dropped
              ? WatchStatus.dropped
              : WatchStatus.watching
        : current.status == WatchStatus.dropped
        ? WatchStatus.dropped
        : current.status == WatchStatus.none
        ? WatchStatus.none
        : WatchStatus.planned;
    items = items
        .map(
          (candidate) => candidate.id == item.id
              ? current.copyWith(
                  status: status,
                  watchedEpisodeCount: count,
                  watchedMinutes: count * item.episodeRuntimeMinutes,
                )
              : candidate,
        )
        .toList();
  }

  @override
  Future<void> setAllEpisodesWatched(MediaItem item, bool watched) async {
    if (watched && _totalEpisodeCapacity(item) < 1) {
      throw StateError('Каталог не сообщил количество эпизодов.');
    }
    _episodeProgress[item.id] = watched
        ? [
            for (final coordinate in _episodeCoordinates(item))
              EpisodeProgress(
                seasonNumber: coordinate.$1,
                episodeNumber: coordinate.$2,
                watched: true,
              ),
          ]
        : [];
    final count = _episodeProgress[item.id]!.length;
    final current = items.firstWhere(
      (candidate) => candidate.id == item.id,
      orElse: () => item,
    );
    items = items
        .map(
          (candidate) => candidate.id == item.id
              ? current.copyWith(
                  status: watched ? WatchStatus.watched : WatchStatus.planned,
                  watchedEpisodeCount: count,
                  watchedMinutes: count * item.episodeRuntimeMinutes,
                )
              : candidate,
        )
        .toList();
  }

  @override
  Future<int> setEpisodeRange(
    MediaItem item,
    Iterable<int> episodeNumbers,
    bool watched,
  ) async {
    final numbers = episodeNumbers.toSet().toList()..sort();
    final total = _totalEpisodeCapacity(item);
    if (numbers.isEmpty) return 0;
    if (numbers.first < 1 || numbers.last > total) {
      throw RangeError('Диапазон выходит за пределы 1–$total.');
    }
    final values = <EpisodeProgress>[
      ...(_episodeProgress[item.id] ?? const <EpisodeProgress>[]),
    ];
    final coordinates = numbers.map(
      (number) => _episodeCoordinate(item, number),
    );
    for (final coordinate in coordinates) {
      values.removeWhere(
        (value) =>
            value.seasonNumber == coordinate.$1 &&
            value.episodeNumber == coordinate.$2,
      );
      if (watched) {
        values.add(
          EpisodeProgress(
            seasonNumber: coordinate.$1,
            episodeNumber: coordinate.$2,
            watched: true,
          ),
        );
      }
    }
    _episodeProgress[item.id] = values;
    final current = items.firstWhere(
      (candidate) => candidate.id == item.id,
      orElse: () => item,
    );
    final count = values.length;
    final status = count >= total
        ? WatchStatus.watched
        : count > 0
        ? current.status == WatchStatus.dropped
              ? WatchStatus.dropped
              : WatchStatus.watching
        : current.status == WatchStatus.dropped
        ? WatchStatus.dropped
        : WatchStatus.planned;
    items = items
        .map(
          (candidate) => candidate.id == item.id
              ? current.copyWith(
                  status: status,
                  watchedEpisodeCount: count,
                  watchedMinutes: count * item.episodeRuntimeMinutes,
                )
              : candidate,
        )
        .toList();
    return numbers.length;
  }
}

Iterable<(int, int)> _episodeCoordinates(MediaItem item) sync* {
  if (item.seasons.isNotEmpty) {
    for (final season in item.seasons) {
      for (var episode = 1; episode <= season.episodeCount; episode++) {
        yield (season.number, episode);
      }
    }
    return;
  }
  for (var episode = 1; episode <= item.episodeCount; episode++) {
    yield (0, episode);
  }
}

int _totalEpisodeCapacity(MediaItem item) => item.seasons.isNotEmpty
    ? item.seasons.fold(0, (sum, season) => sum + season.episodeCount)
    : item.episodeCount;

(int, int) _episodeCoordinate(MediaItem item, int ordinal) {
  if (item.seasons.isEmpty) return (0, ordinal);
  var remaining = ordinal;
  for (final season in item.seasons) {
    if (remaining <= season.episodeCount) return (season.number, remaining);
    remaining -= season.episodeCount;
  }
  throw RangeError('Эпизод $ordinal отсутствует.');
}

int _recommendationWeight(MediaItem item) {
  var weight = 0;
  if (item.isFavorite) weight = 100;
  final rating = item.userRating;
  if (rating != null) {
    if (rating >= 9) {
      weight = max(weight, 90);
    } else if (rating >= 7) {
      weight = max(weight, 65);
    } else if (rating <= 4) {
      return -80;
    }
  }
  final statusWeight = switch (item.status) {
    WatchStatus.watched => 45,
    WatchStatus.watching => 40,
    WatchStatus.planned => 15,
    WatchStatus.dropped => -70,
    WatchStatus.none => 0,
  };
  return max(weight, statusWeight);
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
  'backdrop_url',
  'runtime_minutes',
  'season_count',
  'episode_count',
  'episode_runtime_minutes',
  'seasons_json',
};
