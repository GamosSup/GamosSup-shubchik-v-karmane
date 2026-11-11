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
