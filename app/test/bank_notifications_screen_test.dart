import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/bank_notifications_screen.dart';
import 'package:shubchik/guest_store.dart';

class _TestStore extends GuestStore {
  final saved = <BankRow>[];

  @override
  Future<int> importBankRows(List<BankRow> rows, {String? account}) async {
    saved.addAll(rows);
    return rows.length;
  }
}

void main() {
  testWidgets('synthetic notification enters the ledger only after review',
      (tester) async {
    const channel = MethodChannel('shubchik/bank_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var visible = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'dismiss') {
        expect(call.arguments, {'id': 'test-event'});
        visible = false;
        return null;
      }
      expect(call.method, 'read');
      return {
        'enabled': true,
        'items': jsonEncode([
          if (visible)
            {'id': 'test-event', 'bank': 'sber', 'cents': -12500, 'time': 1794412800000},
        ]),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = _TestStore();
    await tester.pumpWidget(MaterialApp(home: BankNotificationsScreen(store: store)));
    await tester.pumpAndSettle();

    expect(store.saved, isEmpty);
    await tester.ensureVisible(find.text('Добавить в журнал'));
    await tester.tap(find.text('Добавить в журнал'));
    await tester.pumpAndSettle();

    expect(store.saved.single.key, 'notification:test-event');
    expect(store.saved.single.cents, -12500);
    expect(find.text('Кандидатов для сверки пока нет'), findsOneWidget);
  });
}
