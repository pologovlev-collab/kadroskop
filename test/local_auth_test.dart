import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/local_database.dart';
import 'package:kadroskop/data/media_repository.dart';

void main() {
  test('local account survives logout and guest mode', () async {
    final database = await LocalDatabase.openInMemoryForTesting();
    addTearDown(database.database.close);
    final repository = LocalMediaRepository(database);

    final registered = await repository.registerLocalAccount(
      name: 'Лев',
      email: 'lev@example.test',
      password: 'correct-password',
    );
    expect(registered.isGuest, isFalse);

    await repository.logout();
    expect(await repository.loadProfile(), isNull);

    final guest = await repository.continueAsGuest();
    expect(guest.isGuest, isTrue);
    expect(guest.name, 'Гость');

    await repository.logout();
    final restored = await repository.loginLocalAccount(
      email: 'lev@example.test',
      password: 'correct-password',
    );
    expect(restored.name, 'Лев');
    expect(restored.isGuest, isFalse);
  });
}
