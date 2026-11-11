import 'dart:convert';
import 'package:sqflite/sqflite.dart';

class GuestStore {
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      return await openDatabase(
        'shubchik_guest.db',
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0, 1))
            )
          ''');
          await db.execute('''
            CREATE TABLE ledger (
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              cents INTEGER NOT NULL CHECK (cents != 0)
            )
          ''');
        },
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> entries(String table) async =>
      (await database).query(table, orderBy: 'id DESC');

  Future<void> addTask(String title) async {
    await (await database).insert('tasks', {'title': title});
  }

  Future<void> setDone(int id, bool done) async {
    await (await database).update(
      'tasks', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id],
    );
  }

  Future<void> addMoney(String title, int cents) async {
    await (await database).insert('ledger', {'title': title, 'cents': cents});
  }

  Future<void> remove(String table, int id) async {
    await (await database).delete(table, where: 'id = ?', whereArgs: [id]);
  }
  Future<String> exportBackup() async {
    final db = await database;
    return db.transaction((tx) async => jsonEncode({
      'format': 'shubchik-guest',
      'version': 1,
      'tasks': await tx.query('tasks', orderBy: 'id'),
      'ledger': await tx.query('ledger', orderBy: 'id'),
    }));
  }

  Future<void> restoreBackup(String text) async {
    final backup = decodeBackup(text);
    final db = await database;
    await db.transaction((tx) async {
      await tx.delete('tasks');
      await tx.delete('ledger');
      for (final row in backup.tasks) {
        await tx.insert('tasks', row);
      }
      for (final row in backup.ledger) {
        await tx.insert('ledger', row);
      }
    });
  }

  Future<void> clear() async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.delete('tasks');
      await tx.delete('ledger');
    });
  }

}

int? parseCents(String input) {
  final match = RegExp(r'^(\d{1,9})(?:[,.](\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final cents = int.parse(match.group(1)!) * 100 + int.parse(fraction);
  return cents == 0 ? null : cents;
}

String formatMoney(int cents) {
  final value = cents.abs();
  final fraction = (value % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '−' : ''}${value ~/ 100},$fraction ₽';
}

({List<Map<String, Object?>> tasks, List<Map<String, Object?>> ledger})
    decodeBackup(String text) {
  if (text.length > 10000000) throw const FormatException('Слишком большой файл');
  final data = jsonDecode(text);
  if (data is! Map || data['format'] != 'shubchik-guest' || data['version'] != 1) {
    throw const FormatException('Неизвестный формат резервной копии');
  }

  List<Map<String, Object?>> rows(String table) {
    final values = data[table];
    if (values is! List || values.length > 50000) {
      throw const FormatException('Некорректный список записей');
    }
    final ids = <int>{};
    return values.map<Map<String, Object?>>((row) {
      if (row is! Map || row['id'] is! int ||
          row['id'] <= 0 || !ids.add(row['id'] as int) ||
          row['title'] is! String || (row['title'] as String).trim().isEmpty ||
          (row['title'] as String).length > 120) {
        throw const FormatException('Некорректная запись');
      }
      final result = <String, Object?>{'id': row['id'], 'title': row['title']};
      if (table == 'tasks') {
        if (row['done'] != 0 && row['done'] != 1) {
          throw const FormatException('Некорректное состояние задачи');
        }
        result['done'] = row['done'];
      } else {
        if (row['cents'] is! int || row['cents'] == 0 ||
            (row['cents'] as int).abs() > 99999999999) {
          throw const FormatException('Некорректная сумма');
        }
        result['cents'] = row['cents'];
      }
      return result;
    }).toList();
  }

  return (tasks: rows('tasks'), ledger: rows('ledger'));
}
