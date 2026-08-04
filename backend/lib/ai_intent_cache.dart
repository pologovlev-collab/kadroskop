import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'remember_models.dart';

abstract interface class AiIntentCache {
  Future<RememberSearchIntent?> read(
    String normalizedQuery,
    String filtersHash,
  );

  Future<void> write({
    required String normalizedQuery,
    required String filtersHash,
    required RememberSearchIntent intent,
    required String provider,
    required String model,
  });

  Future<void> close();
}

class SqliteAiIntentCache implements AiIntentCache {
  SqliteAiIntentCache({
    required String path,
    required this.ttl,
    Database? database,
  }) : _database = database ?? _open(path) {
    _database.execute('PRAGMA busy_timeout = 3000');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS ai_intent_cache (
        normalized_query TEXT NOT NULL,
        filters_hash TEXT NOT NULL,
        parsed_intent_json TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (normalized_query, filters_hash)
      )
    ''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_cache_created_at '
      'ON ai_intent_cache(created_at)',
    );
  }

  final Database _database;
  final Duration ttl;

  static Database _open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return sqlite3.open(path);
  }

  @override
  Future<RememberSearchIntent?> read(
    String normalizedQuery,
    String filtersHash,
  ) async {
    final cutoff = DateTime.now().subtract(ttl).toIso8601String();
    _database.execute('DELETE FROM ai_intent_cache WHERE created_at < ?', [
      cutoff,
    ]);
    final rows = _database.select(
      '''
      SELECT parsed_intent_json
      FROM ai_intent_cache
      WHERE normalized_query = ? AND filters_hash = ? AND created_at >= ?
      LIMIT 1
      ''',
      [normalizedQuery, filtersHash, cutoff],
    );
    if (rows.isEmpty) return null;
    try {
      return RememberSearchIntent.decode(
        rows.first['parsed_intent_json'] as String,
      );
    } catch (_) {
      _database.execute(
        'DELETE FROM ai_intent_cache WHERE normalized_query = ? AND filters_hash = ?',
        [normalizedQuery, filtersHash],
      );
      return null;
    }
  }

  @override
  Future<void> write({
    required String normalizedQuery,
    required String filtersHash,
    required RememberSearchIntent intent,
    required String provider,
    required String model,
  }) async {
    _database.execute(
      '''
      INSERT INTO ai_intent_cache (
        normalized_query,
        filters_hash,
        parsed_intent_json,
        provider,
        model,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(normalized_query, filters_hash) DO UPDATE SET
        parsed_intent_json = excluded.parsed_intent_json,
        provider = excluded.provider,
        model = excluded.model,
        created_at = excluded.created_at
      ''',
      [
        normalizedQuery,
        filtersHash,
        jsonEncode(intent.toJson()),
        provider,
        model,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> close() async => _database.close();
}

class MemoryAiIntentCache implements AiIntentCache {
  final Map<String, RememberSearchIntent> _values = {};
  int writes = 0;

  @override
  Future<RememberSearchIntent?> read(
    String normalizedQuery,
    String filtersHash,
  ) async => _values['$normalizedQuery:$filtersHash'];

  @override
  Future<void> write({
    required String normalizedQuery,
    required String filtersHash,
    required RememberSearchIntent intent,
    required String provider,
    required String model,
  }) async {
    writes += 1;
    _values['$normalizedQuery:$filtersHash'] = intent;
  }

  @override
  Future<void> close() async {}
}

const rememberSearchAlgorithmVersion = 'remember-search-v2-characters-2026-08';
const rememberIntentSchemaVersion = 'remember-intent-v3-structured-2026-08';

String rememberFiltersHash(
  RememberSearchRequest request, {
  required String provider,
  required String model,
  String algorithmVersion = rememberSearchAlgorithmVersion,
  String schemaVersion = rememberIntentSchemaVersion,
}) {
  final canonical = jsonEncode({
    ...request.cacheFilters,
    'provider': provider,
    'model': model,
    'schemaVersion': schemaVersion,
    'algorithmVersion': algorithmVersion,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}
