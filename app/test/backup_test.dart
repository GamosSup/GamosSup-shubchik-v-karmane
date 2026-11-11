import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_store.dart';

void main() {
  Map<String, Object?> backup() => {
    'format': 'shubchik-guest', 'version': 1,
    'tasks': [{'id': 1, 'title': 'Задача', 'done': 0}],
    'ledger': [{'id': 1, 'title': 'Покупка', 'cents': -12345}],
  };
  test('Backup preserves task and integer currency values', () {
    final decoded = decodeBackup(jsonEncode(backup()));
    expect(decoded.tasks.single['title'], 'Задача');
    expect(decoded.ledger.single['cents'], -12345);
  });
  test('Malformed and unknown backups are rejected', () {
    expect(() => decodeBackup('broken'), throwsFormatException);
    final data = backup()..['version'] = 99;
    expect(() => decodeBackup(jsonEncode(data)), throwsFormatException);
  });
  test('Duplicate IDs are rejected before restore', () {
    final data = backup();
    final tasks = data['tasks'] as List;
    tasks.add(tasks.first);
    expect(() => decodeBackup(jsonEncode(data)), throwsFormatException);
  });
  test('Fractional currency and invalid task state are rejected', () {
    final data = backup();
    (data['ledger'] as List).first['cents'] = 1.5;
    expect(() => decodeBackup(jsonEncode(data)), throwsFormatException);
    final invalid = backup();
    (invalid['tasks'] as List).first['done'] = 3;
    expect(() => decodeBackup(jsonEncode(invalid)), throwsFormatException);
  });
}
