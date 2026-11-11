import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_store.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  setUpAll(() {
    ffi.sqfliteFfiInit();
    sqlite.databaseFactory = ffi.databaseFactoryFfi;
  });

  test('Cloud replacement keeps local data until explicit deletion', () async {
    final store = GuestStore(fileName: sqlite.inMemoryDatabasePath);
    addTearDown(() async => (await store.database).close());
    await store.addTask('Local task');
    final local = await store.exportBackup();
    final remote = encodeBackup([], []);
    expect(await store.acceptSync(
      revision: 1, payload: remote, expectedLocal: local, replaceLocal: true,
    ), isTrue);
    expect(await store.latestRecoveryPoint(), local);
    await store.restoreBackup(local);
    expect(await store.exportBackup(), local);
    await store.clear();
    expect(await store.latestRecoveryPoint(), isNull);
  });
}
