import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'catalog_provider.dart';
import 'query_normalizer.dart';

abstract interface class MediaAliasStore {
  Future<List<String>> aliasesForQuery(String normalizedQuery);
  Future<void> record(Iterable<CatalogMedia> media);
  Future<void> close();
}

class SqliteMediaAliasStore implements MediaAliasStore {
  SqliteMediaAliasStore({required String path, Database? database})
    : _database = database ?? _open(path) {
    _database.execute('PRAGMA busy_timeout = 3000');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS media_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        normalized_alias TEXT NOT NULL,
        display_alias TEXT NOT NULL,
        language TEXT NOT NULL,
        source TEXT NOT NULL,
        external_id TEXT NOT NULL,
        alias_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(normalized_alias, source, external_id, alias_type)
      )
    ''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_alias_normalized '
      'ON media_aliases(normalized_alias)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_alias_source_id '
      'ON media_aliases(source, external_id)',
    );
  }

  final Database _database;
  final QueryNormalizer _normalizer = const QueryNormalizer();

  static Database _open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return sqlite3.open(path);
  }

  @override
  Future<List<String>> aliasesForQuery(String normalizedQuery) async {
    if (normalizedQuery.length < 2) return const [];
    final rows = _database.select(
      '''
      WITH matching_media AS (
        SELECT DISTINCT source, external_id
        FROM media_aliases
        WHERE normalized_alias = ?
           OR (length(?) >= 3 AND normalized_alias LIKE ?)
        LIMIT 20
      )
      SELECT DISTINCT a.display_alias
      FROM media_aliases a
      INNER JOIN matching_media m
        ON m.source = a.source AND m.external_id = a.external_id
      ORDER BY length(a.display_alias), a.display_alias
      LIMIT 30
      ''',
      [normalizedQuery, normalizedQuery, '$normalizedQuery%'],
    );
    return rows.map((row) => row['display_alias']).whereType<String>().toList();
  }

  @override
  Future<void> record(Iterable<CatalogMedia> media) async {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final item in media) {
        final aliases = <(String, String)>[
          (item.title, 'primary'),
          if (item.originalTitle.isNotEmpty) (item.originalTitle, 'original'),
          if (item.englishTitle.isNotEmpty) (item.englishTitle, 'english'),
          if (item.nativeTitle.isNotEmpty) (item.nativeTitle, 'native'),
          ...item.synonyms.map((alias) => (alias, 'synonym')),
        ];
        final seen = <String>{};
        for (final (displayAlias, aliasType) in aliases) {
          final normalized = _normalizer.normalize(displayAlias);
          if (normalized.length < 2 || !seen.add('$normalized:$aliasType')) {
            continue;
          }
          _database.execute(
            '''
            INSERT INTO media_aliases (
              normalized_alias,
              display_alias,
              language,
              source,
              external_id,
              alias_type,
              created_at,
              updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(normalized_alias, source, external_id, alias_type)
            DO UPDATE SET
              display_alias = excluded.display_alias,
              language = excluded.language,
              updated_at = excluded.updated_at
            ''',
            [
              normalized,
              displayAlias.trim(),
              _language(displayAlias),
              item.source,
              item.externalId,
              aliasType,
              now,
              now,
            ],
          );
        }
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> close() async => _database.close();
}

class MemoryMediaAliasStore implements MediaAliasStore {
  final List<_MemoryAlias> _aliases = [];
  final QueryNormalizer _normalizer = const QueryNormalizer();

  @override
  Future<List<String>> aliasesForQuery(String normalizedQuery) async {
    final matchingIds = _aliases
        .where(
          (alias) =>
              alias.normalized == normalizedQuery ||
              (normalizedQuery.length >= 3 &&
                  alias.normalized.startsWith(normalizedQuery)),
        )
        .map((alias) => '${alias.source}:${alias.externalId}')
        .toSet();
    return _aliases
        .where(
          (alias) =>
              matchingIds.contains('${alias.source}:${alias.externalId}'),
        )
        .map((alias) => alias.display)
        .toSet()
        .toList();
  }

  @override
  Future<void> record(Iterable<CatalogMedia> media) async {
    for (final item in media) {
      for (final alias in item.titleVariants) {
        final normalized = _normalizer.normalize(alias);
        if (normalized.length < 2) continue;
        final record = _MemoryAlias(
          normalized,
          alias,
          item.source,
          item.externalId,
        );
        if (!_aliases.contains(record)) _aliases.add(record);
      }
    }
  }

  @override
  Future<void> close() async {}
}

class _MemoryAlias {
  const _MemoryAlias(
    this.normalized,
    this.display,
    this.source,
    this.externalId,
  );

  final String normalized;
  final String display;
  final String source;
  final String externalId;

  @override
  bool operator ==(Object other) =>
      other is _MemoryAlias &&
      normalized == other.normalized &&
      source == other.source &&
      externalId == other.externalId;

  @override
  int get hashCode => Object.hash(normalized, source, externalId);
}

String _language(String value) {
  if (RegExp(r'[а-яё]', caseSensitive: false).hasMatch(value)) return 'ru';
  if (RegExp(r'[一-龯ぁ-ゔァ-ヴー々〆〤]').hasMatch(value)) return 'ja';
  if (RegExp(r'[a-z]', caseSensitive: false).hasMatch(value)) return 'en';
  return 'und';
}
