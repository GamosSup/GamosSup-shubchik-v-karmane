import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_store.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  setUpAll(() {
    ffi.sqfliteFfiInit();
    sqlite.databaseFactory = ffi.databaseFactoryFfi;
  });

  test('Finance plans, tags and receipts survive a transactional restore', () async {
    final store = GuestStore(fileName: sqlite.inMemoryDatabasePath);
    addTearDown(() async => (await store.database).close());
    await store.saveFinanceItem(kind: 'account', title: 'Наличные', target: 100000, current: 0);
    await store.saveFinanceItem(kind: 'budget', title: 'Продукты', target: 50000, current: 0);
    await store.addMoney('Продукты', -1500, account: 'Наличные',
      category: suggestCategory('Продукты', -1500), recordedOn: '2026-11-11');
    final id = (await store.entries('ledger')).single['id'] as int;
    final pdf = Uint8List.fromList('%PDF-test'.codeUnits);
    await store.setReceipt(id, 'чек.pdf', pdf);
    await expectLater(store.setReceipt(id, 'bad.jpg', pdf), throwsFormatException);
    final snapshot = await store.exportBackup();
    await store.clear();
    await store.restoreBackup(snapshot);
    final plans = await store.entries('finance_items');
    expect(plans, hasLength(2));
    expect((await store.entries('ledger')).single['category'], 'Продукты');
    expect((await store.receiptFor(id))?.bytes, pdf);
    expect(await store.exportBackup(), snapshot);
  });
}
