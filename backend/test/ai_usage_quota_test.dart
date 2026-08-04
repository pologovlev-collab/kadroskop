import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'memory quota uses an UTC daily limit and retains no query text',
    () async {
      final quota = MemoryAiUsageQuota(
        limit: 2,
        clock: () => DateTime.utc(2026, 8, 4, 23, 59),
      );

      expect(await quota.tryAcquire(), isTrue);
      await quota.recordSuccess();
      expect(await quota.tryAcquire(), isTrue);
      await quota.recordFailure();
      expect(await quota.tryAcquire(), isFalse);

      expect(quota.diagnostics, {
        'enabled': true,
        'limit': 2,
        'date': '2026-08-04',
        'externalRequests': 2,
        'successfulRequests': 1,
        'failedRequests': 1,
      });
    },
  );

  test('SQLite quota persists counters only', () async {
    final database = sqlite3.openInMemory();
    final quota = SqliteAiUsageQuota(
      path: ':memory:',
      database: database,
      limit: 1,
      clock: () => DateTime.utc(2026, 8, 4),
    );

    expect(await quota.tryAcquire(), isTrue);
    await quota.recordFailure();
    expect(await quota.tryAcquire(), isFalse);

    final columns = database.select('PRAGMA table_info(ai_usage_quota)');
    expect(
      columns.map((row) => row['name']).toList(),
      unorderedEquals([
        'utc_date',
        'external_requests',
        'successful_requests',
        'failed_requests',
      ]),
    );
    expect(quota.diagnostics['externalRequests'], 1);
    expect(quota.diagnostics['failedRequests'], 1);
    database.close();
  });
}
