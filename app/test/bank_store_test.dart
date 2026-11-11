import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_store.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

const first = (key: 'sber:1', date: '2026-11-11', title: 'Чай', cents: -500);
const second = (key: 'sber:2', date: '2026-11-11', title: 'Чай', cents: -500);

void main() {
  setUpAll(() {
    ffi.sqfliteFfiInit();
    sqlite.databaseFactory = ffi.databaseFactoryFfi;
  });

  test('Repeated and overlapping imports stay idempotent after restore', () async {
    final store = GuestStore(fileName: sqlite.inMemoryDatabasePath);
    addTearDown(() async => (await store.database).close());
    expect(await store.importBankRows([first]), 1);
    expect(await store.importBankRows([first, second]), 1);
    expect(await store.importBankRows([first, second]), 0);
    final copy = await store.exportBackup();
    await store.clear();
    expect(await store.entries('ledger'), isEmpty);
    await store.restoreBackup(copy);
    expect(await store.importBankRows([first]), 0);
    expect(await store.entries('ledger'), hasLength(2));
  });

  test('A conflicting ID rolls back the entire file', () async {
    final store = GuestStore(fileName: sqlite.inMemoryDatabasePath);
    addTearDown(() async => (await store.database).close());
    await store.importBankRows([first]);
    final changed = (key: first.key, date: first.date, title: 'Кофе', cents: -800);
    await expectLater(store.importBankRows([second, changed]), throwsFormatException);
    expect(await store.entries('ledger'), hasLength(1));
  });
}
