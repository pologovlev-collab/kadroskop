import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

abstract interface class AiUsageQuota {
  Future<bool> tryAcquire();
  Future<void> recordSuccess();
  Future<void> recordFailure();
  Map<String, Object?> get diagnostics;
}

class NoopAiUsageQuota implements AiUsageQuota {
  const NoopAiUsageQuota();

  @override
  Map<String, Object?> get diagnostics => const {'enabled': false};

  @override
  Future<void> recordFailure() async {}

  @override
  Future<void> recordSuccess() async {}

  @override
  Future<bool> tryAcquire() async => true;
}

class MemoryAiUsageQuota implements AiUsageQuota {
  MemoryAiUsageQuota({required this.limit, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int limit;
  final DateTime Function() _clock;
  String? _date;
  int externalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;

  @override
  Map<String, Object?> get diagnostics => {
    'enabled': limit > 0,
    'limit': limit,
    'date': _date,
    'externalRequests': externalRequests,
    'successfulRequests': successfulRequests,
    'failedRequests': failedRequests,
  };

  @override
  Future<void> recordFailure() async {
    _ensureDate();
    failedRequests += 1;
  }

  @override
  Future<void> recordSuccess() async {
    _ensureDate();
    successfulRequests += 1;
  }

  @override
  Future<bool> tryAcquire() async {
    _ensureDate();
    if (limit == 0) return true;
    if (externalRequests >= limit) return false;
    externalRequests += 1;
    return true;
  }

  void _ensureDate() {
    final date = _utcDate(_clock());
    if (_date == date) return;
    _date = date;
    externalRequests = 0;
    successfulRequests = 0;
    failedRequests = 0;
  }
}

class SqliteAiUsageQuota implements AiUsageQuota {
  SqliteAiUsageQuota({
    required String path,
    required this.limit,
    Database? database,
    DateTime Function()? clock,
  }) : _database = database ?? _open(path),
       _clock = clock ?? DateTime.now {
    _database.execute('PRAGMA busy_timeout = 3000');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage_quota (
        utc_date TEXT PRIMARY KEY,
        external_requests INTEGER NOT NULL DEFAULT 0,
        successful_requests INTEGER NOT NULL DEFAULT 0,
        failed_requests INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  final Database _database;
  final int limit;
  final DateTime Function() _clock;

  static Database _open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return sqlite3.open(path);
  }

  @override
  Map<String, Object?> get diagnostics {
    final date = _utcDate(_clock());
    final rows = _database.select(
      '''
      SELECT external_requests, successful_requests, failed_requests
      FROM ai_usage_quota WHERE utc_date = ? LIMIT 1
      ''',
      [date],
    );
    final row = rows.isEmpty ? null : rows.first;
    return {
      'enabled': limit > 0,
      'limit': limit,
      'date': date,
      'externalRequests': (row?['external_requests'] as num?)?.toInt() ?? 0,
      'successfulRequests': (row?['successful_requests'] as num?)?.toInt() ?? 0,
      'failedRequests': (row?['failed_requests'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  Future<void> recordFailure() async => _increment('failed_requests');

  @override
  Future<void> recordSuccess() async => _increment('successful_requests');

  @override
  Future<bool> tryAcquire() async {
    if (limit == 0) return true;
    final date = _utcDate(_clock());
    _database.execute('BEGIN IMMEDIATE');
    try {
      _ensureRow(date);
      final row = _database.select(
        'SELECT external_requests FROM ai_usage_quota WHERE utc_date = ?',
        [date],
      ).first;
      final requests = (row['external_requests'] as num).toInt();
      if (requests >= limit) {
        _database.execute('COMMIT');
        return false;
      }
      _database.execute(
        '''
        UPDATE ai_usage_quota
        SET external_requests = external_requests + 1
        WHERE utc_date = ?
        ''',
        [date],
      );
      _database.execute('COMMIT');
      return true;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureRow(String date) {
    _database.execute(
      '''
      INSERT INTO ai_usage_quota (utc_date)
      VALUES (?)
      ON CONFLICT(utc_date) DO NOTHING
      ''',
      [date],
    );
  }

  void _increment(String column) {
    final date = _utcDate(_clock());
    _ensureRow(date);
    _database.execute(
      'UPDATE ai_usage_quota SET $column = $column + 1 WHERE utc_date = ?',
      [date],
    );
  }
}

String _utcDate(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
}
