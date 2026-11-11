import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/bank_csv.dart';
import 'package:shubchik/guest_store.dart';

const header = 'id;date;title;amount\n';

List<BankRow> parse(String rows, {String account = 'Основной'}) =>
    parseBankCsv('$header$rows', bank: 'sber', account: account);

void main() {
  test('Preserves distinct identical purchases and skips the same bank ID', () {
    final rows = parse('A;2026-11-11;"Чай; кофе";-5,20\n'
        'B;2026-11-11;"Чай; кофе";-5,20\n'
        'A;2026-11-11;"Чай; кофе";-5,20');
    expect(rows.length, 2);
    expect(rows.first.cents, -520);
    expect(rows.first.title, 'Чай; кофе');
    expect(rows.first.key, isNot(rows.last.key));
    expect(parse('A;2026-11-11;"Чай; кофе";-5,20', account: ' основной ').first.key, rows.first.key);
  });

  test('Rejects invalid dates and conflicting rows', () {
    expect(() => parse('A;2026-02-30;Чай;-5,20'), throwsFormatException);
    expect(() => parse('A;2026-11-11;Чай;-5\nA;2026-11-11;Кофе;-9'), throwsFormatException);
  });

  test('Preserves imported ID across backup export and decode', () {
    final row = parse('A;2026-11-11;Чай;-5,20').single;
    final backup = encodeBackup([], [{
      'id': 1, 'title': row.title, 'cents': row.cents,
      'source_key': row.key, 'posted_on': row.date,
    }]);
    expect((jsonDecode(backup) as Map)['version'], 2);
    expect(decodeBackup(backup).ledger.single['source_key'], row.key);
    expect((jsonDecode(encodeBackup([], [])) as Map)['version'], 1);
  });
}
