import 'package:sqflite/sqflite.dart';

import '../models/media_item.dart';
import 'local_database.dart';

abstract interface class CatalogSource {
  Future<List<MediaItem>> search(String query, {MediaKind? kind});
  Future<MediaItem> details(MediaItem item);
}

abstract interface class MediaRepository {
  Future<List<MediaItem>> loadMedia();
  Future<List<MediaItem>> searchCatalog(String query, {MediaKind? kind});
  Future<MediaItem> loadDetails(MediaItem item);
  Future<void> setStatus(MediaItem item, WatchStatus status);
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
      SELECT m.*, COALESCE(u.status, 'none') AS status
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
    await _local.database.insert('user_media', {
      'media_id': item.id,
      'status': status.name,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
