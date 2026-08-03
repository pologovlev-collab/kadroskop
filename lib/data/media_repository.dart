import '../models/media_item.dart';
import 'local_database.dart';
import 'package:sqflite/sqflite.dart';

abstract interface class MediaRepository {
  Future<List<MediaItem>> loadMedia();
  Future<void> setStatus(int mediaId, WatchStatus status);
  Future<void> recordInteraction(int mediaId, String eventType);
}

class LocalMediaRepository implements MediaRepository {
  LocalMediaRepository(this._local);

  final LocalDatabase _local;

  @override
  Future<List<MediaItem>> loadMedia() async {
    final rows = await _local.database.rawQuery('''
      SELECT m.*, COALESCE(u.status, 'none') AS status,
             COALESCE(u.progress, 0) AS progress
      FROM media m
      LEFT JOIN user_media u ON u.media_id = m.id
      ORDER BY m.id
    ''');
    return rows.map(MediaItem.fromMap).toList();
  }

  @override
  Future<void> setStatus(int mediaId, WatchStatus status) async {
    await _local.database.insert('user_media', {
      'media_id': mediaId,
      'status': status.name,
      'progress': status == WatchStatus.watched ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> recordInteraction(int mediaId, String eventType) =>
      _local.database.insert('interactions', {
        'media_id': mediaId,
        'event_type': eventType,
        'created_at': DateTime.now().toIso8601String(),
      });
}

class MemoryMediaRepository implements MediaRepository {
  MemoryMediaRepository(this.items);

  List<MediaItem> items;

  @override
  Future<List<MediaItem>> loadMedia() async => items;

  @override
  Future<void> recordInteraction(int mediaId, String eventType) async {}

  @override
  Future<void> setStatus(int mediaId, WatchStatus status) async {
    items = items
        .map(
          (item) => item.id == mediaId ? item.copyWith(status: status) : item,
        )
        .toList();
  }
}
