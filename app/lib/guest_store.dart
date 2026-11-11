import 'dart:convert';
import 'package:sqflite/sqflite.dart';

class GuestStore {
  GuestStore({this.fileName = 'shubchik_guest.db'});

  final String fileName;
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      return await openDatabase(
        fileName,
        version: 3,
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createSyncState(db);
          if (oldVersion < 3) await _createBankFields(db);
        },
        onCreate: (db, version) async {
          await _createSyncState(db);
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
          await _createBankFields(db);
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

  Future<void> _createBankFields(Database db) async {
    await db.execute('ALTER TABLE ledger ADD COLUMN source_key TEXT');
    await db.execute('ALTER TABLE ledger ADD COLUMN posted_on TEXT');
    await db.execute('CREATE UNIQUE INDEX ledger_source_key ON ledger(source_key)');
  }

  Future<int> importBankRows(List<BankRow> rows) async {
    final db = await database;
    return db.transaction((tx) async {
      var inserted = 0;
      for (final row in rows) {
        final previous = await tx.query('ledger', where: 'source_key = ?', whereArgs: [row.key]);
        if (previous.isNotEmpty) {
          final record = previous.single;
          if (record['title'] != row.title || record['cents'] != row.cents ||
              record['posted_on'] != row.date) {
            throw const FormatException('Операция с таким ID уже есть, но её данные отличаются');
          }
          continue;
        }
        await tx.insert('ledger', {
          'source_key': row.key, 'posted_on': row.date,
          'title': row.title, 'cents': row.cents,
        });
        inserted++;
      }
      return inserted;
    });
  }

  Future<void> remove(String table, int id) async {
    await (await database).delete(table, where: 'id = ?', whereArgs: [id]);
  }
  Future<String> exportBackup() async {
    final db = await database;
    return db.transaction(_export);
  }

  Future<String> _export(Transaction tx) async => encodeBackup(
    await tx.query('tasks', orderBy: 'id'),
    await tx.query('ledger', orderBy: 'id'),
  );

  Future<void> restoreBackup(String text) async {
    final backup = decodeBackup(text);
    final db = await database;
    await db.transaction((tx) => _replace(tx, backup));
  }

  Future<void> _replace(Transaction tx, GuestBackup backup) async {
    await tx.delete('tasks');
    await tx.delete('ledger');
    for (final row in backup.tasks) {
      await tx.insert('tasks', row);
    }
    for (final row in backup.ledger) {
      await tx.insert('ledger', row);
    }
  }

  Future<void> _createSyncState(Database db) => db.execute('''
    CREATE TABLE sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      revision INTEGER NOT NULL,
      payload TEXT NOT NULL
    )
  ''');

  Future<({String local, String base, int revision})> readSyncState() async {
    final db = await database;
    return db.transaction((tx) async {
      final rows = await tx.query('sync_state', where: 'id = 1');
      final row = rows.firstOrNull;
      return (
        local: await _export(tx),
        base: row?['payload'] as String? ?? encodeBackup([], []),
        revision: row?['revision'] as int? ?? 0,
      );
    });
  }

  Future<bool> acceptSync({
    required int revision,
    required String payload,
    required String expectedLocal,
    required bool replaceLocal,
  }) async {
    final backup = decodeBackup(payload);
    final db = await database;
    return db.transaction((tx) async {
      if (replaceLocal) {
        if (await _export(tx) != expectedLocal) return false;
        await _replace(tx, backup);
      }
      await tx.insert('sync_state', {
        'id': 1, 'revision': revision, 'payload': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<bool> importIfEmpty(String payload) async {
    final backup = decodeBackup(payload);
    final db = await database;
    return db.transaction((tx) async {
      if (await _export(tx) != encodeBackup([], [])) return false;
      await _replace(tx, backup);
      return true;
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

typedef BankRow = ({String key, String date, String title, int cents});

bool validStatementDate(String value) {
  final date = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      date != null && date.toIso8601String().startsWith(value + 'T');
}

typedef GuestBackup = ({
  List<Map<String, Object?>> tasks,
  List<Map<String, Object?>> ledger,
});

String encodeBackup(List<Map<String, Object?>> tasks, List<Map<String, Object?>> ledger) {
  final money = ledger.map((row) => {
    'id': row['id'], 'title': row['title'], 'cents': row['cents'],
    if (row['source_key'] != null) ...{
      'source_key': row['source_key'], 'posted_on': row['posted_on'],
    },
  }).toList();
  return jsonEncode({
    'format': 'shubchik-guest',
    'version': money.any((row) => row.containsKey('source_key')) ? 2 : 1,
    'tasks': tasks,
    'ledger': money,
  });
}

GuestBackup decodeBackup(String text) {
  if (text.length > 10000000) throw const FormatException('Слишком большой файл');
  final data = jsonDecode(text);
  if (data is! Map || data['format'] != 'shubchik-guest' || !const {1, 2}.contains(data['version'])) {
    throw const FormatException('Неизвестный формат резервной копии');
  }

  List<Map<String, Object?>> rows(String table) {
    final values = data[table];
    if (values is! List || values.length > 50000) {
      throw const FormatException('Некорректный список записей');
    }
    final ids = <int>{};
    final sourceKeys = <String>{};
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
        final source = row['source_key'];
        final date = row['posted_on'];
        if (source != null || date != null) {
          if (data['version'] != 2 || source is! String ||
              source.isEmpty || source.length > 1024 || !sourceKeys.add(source) ||
              date is! String || !validStatementDate(date)) {
            throw const FormatException('Некорректный идентификатор банковской операции');
          }
          result['source_key'] = source;
          result['posted_on'] = date;
        }
      }
      return result;
    }).toList();
  }

  return (tasks: rows('tasks'), ledger: rows('ledger'));
}
