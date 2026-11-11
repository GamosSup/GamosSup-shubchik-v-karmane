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
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createSyncState(db);
          if (oldVersion < 3) await _createBankFields(db);
          if (oldVersion < 4) await _createPlannerFields(db);
          if (oldVersion < 5) await _createFinanceFields(db);
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
          await _createPlannerFields(db);
          await _createFinanceFields(db);
        },
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> entries(String table) async =>
      (await database).query(table, orderBy: 'id DESC');

  Future<void> addTask(String title, {String? dueOn, String? project}) async {
    await (await database).insert('tasks', {
      'title': title, 'due_on': dueOn, 'project': project,
    });
  }

  Future<void> updateTask(int id, String title, {String? dueOn, String? project}) async {
    await (await database).update('tasks', {
      'title': title, 'due_on': dueOn, 'project': project,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _createPlannerFields(Database db) async {
    await db.execute('ALTER TABLE tasks ADD COLUMN due_on TEXT');
    await db.execute('ALTER TABLE tasks ADD COLUMN project TEXT');
    await db.execute('CREATE TABLE habits (id INTEGER PRIMARY KEY, title TEXT NOT NULL)');
    await db.execute('''
      CREATE TABLE habit_entries (
        habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
        day TEXT NOT NULL,
        PRIMARY KEY (habit_id, day)
      )
    ''');
  }

  Future<List<Map<String, Object?>>> habitsFor(String day) async =>
      (await database).rawQuery('''
        SELECT h.id, h.title,
          EXISTS(SELECT 1 FROM habit_entries e WHERE e.habit_id = h.id AND e.day = ?) AS done,
          (SELECT COUNT(*) FROM habit_entries e WHERE e.habit_id = h.id) AS total
        FROM habits h ORDER BY h.id DESC
      ''', [day]);

  Future<void> addHabit(String title) async {
    await (await database).insert('habits', {'title': title});
  }

  Future<void> setHabitDay(int id, String day, bool done) async {
    final db = await database;
    if (done) {
      await db.insert('habit_entries', {'habit_id': id, 'day': day},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('habit_entries', where: 'habit_id = ? AND day = ?', whereArgs: [id, day]);
    }
  }


  Future<void> setDone(int id, bool done) async {
    await (await database).update(
      'tasks', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id],
    );
  }

  Future<void> _createFinanceFields(Database db) async {
    await db.execute('ALTER TABLE ledger ADD COLUMN account TEXT');
    await db.execute('ALTER TABLE ledger ADD COLUMN category TEXT');
    await db.execute('ALTER TABLE ledger ADD COLUMN recorded_on TEXT');
    await db.execute("""
      CREATE TABLE finance_items (
        id INTEGER PRIMARY KEY,
        kind TEXT NOT NULL CHECK (kind IN ('account', 'budget', 'goal', 'debt', 'subscription')),
        title TEXT NOT NULL,
        target INTEGER NOT NULL,
        current INTEGER NOT NULL DEFAULT 0,
        due_on TEXT,
        UNIQUE (kind, title)
      )
    """);
  }

  Future<void> addMoney(String title, int cents, {
    String? account, String? category, String? recordedOn,
  }) async {
    await (await database).insert('ledger', {
      'title': title, 'cents': cents, 'account': account,
      'category': category, 'recorded_on': recordedOn,
    });
  }

  Future<void> updateMoneyTags(int id, String? account, String? category) async {
    await (await database).update('ledger', {
      'account': account, 'category': category,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveFinanceItem({
    int? id, required String kind, required String title,
    required int target, required int current, String? dueOn,
  }) async {
    final db = await database;
    final values = {
      'kind': kind, 'title': title, 'target': target, 'current': current, 'due_on': dueOn,
    };
    if (id == null) {
      await db.insert('finance_items', values);
    } else {
      await db.transaction((tx) async {
        final before = await tx.query('finance_items', where: 'id = ?', whereArgs: [id]);
        if (before.isEmpty) throw StateError('Missing item');
        if (kind == 'account' && title != before.single['title']) {
          await tx.update('ledger', {'account': title},
            where: 'account = ?', whereArgs: [before.single['title']]);
        }
        if (kind == 'budget' && title != before.single['title']) {
          await tx.update('ledger', {'category': title},
            where: 'category = ?', whereArgs: [before.single['title']]);
        }
        await tx.update('finance_items', values, where: 'id = ?', whereArgs: [id]);
      });
    }
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
          'category': suggestCategory(row.title, row.cents),
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
    habits: await tx.query('habits', orderBy: 'id'),
    habitEntries: await tx.query('habit_entries', orderBy: 'habit_id, day'),
    financeItems: await tx.query('finance_items', orderBy: 'id'),
  );

  Future<void> restoreBackup(String text) async {
    final backup = decodeBackup(text);
    final db = await database;
    await db.transaction((tx) => _replace(tx, backup));
  }

  Future<void> _replace(Transaction tx, GuestBackup backup) async {
    await _clearData(tx);
    for (final row in backup.tasks) {
      await tx.insert('tasks', row);
    }
    for (final row in backup.ledger) {
      await tx.insert('ledger', row);
    }
    for (final row in backup.habits) {
      await tx.insert('habits', row);
    }
    for (final row in backup.habitEntries) {
      await tx.insert('habit_entries', row);
    }
    for (final row in backup.financeItems) {
      await tx.insert('finance_items', row);
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
    await db.transaction(_clearData);
  }

  Future<void> _clearData(Transaction tx) async {
    await tx.delete('finance_items');
    await tx.delete('habit_entries');
    await tx.delete('habits');
    await tx.delete('tasks');
    await tx.delete('ledger');
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

const financeKinds = {'account', 'budget', 'goal', 'debt', 'subscription'};

String suggestCategory(String title, int cents) {
  if (cents > 0) return 'Доход';
  final text = title.toLowerCase();
  const hints = {
    'Продукты': ['продукт', 'пятёрочка', 'пятерочка', 'магнит', 'перекрёсток', 'вкусвилл'],
    'Транспорт': ['такси', 'метро', 'бензин', 'проезд', 'парковк'],
    'Здоровье': ['аптек', 'клиник', 'стоматолог'],
    'Связь': ['интернет', 'мтс', 'мегафон', 'билайн'],
    'Развлечения': ['кино', 'музык', 'театр'],
  };
  for (final item in hints.entries) {
    if (item.value.any(text.contains)) return item.key;
  }
  return 'Прочее';
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
  List<Map<String, Object?>> habits,
  List<Map<String, Object?>> habitEntries,
  List<Map<String, Object?>> financeItems,
});

String encodeBackup(
  List<Map<String, Object?>> tasks,
  List<Map<String, Object?>> ledger, {
  List<Map<String, Object?>> habits = const [],
  List<Map<String, Object?>> habitEntries = const [],
  List<Map<String, Object?>> financeItems = const [],
}) {
  final planned = tasks.map((row) => {
    'id': row['id'], 'title': row['title'], 'done': row['done'],
    if (row['due_on'] != null) 'due_on': row['due_on'],
    if (row['project'] != null) 'project': row['project'],
  }).toList();
  final planner = habits.isNotEmpty || habitEntries.isNotEmpty ||
      planned.any((row) => row.containsKey('due_on') || row.containsKey('project'));
  final money = ledger.map((row) => {
    'id': row['id'], 'title': row['title'], 'cents': row['cents'],
    if (row['account'] != null) 'account': row['account'],
    if (row['category'] != null) 'category': row['category'],
    if (row['recorded_on'] != null) 'recorded_on': row['recorded_on'],
    if (row['source_key'] != null) ...{
      'source_key': row['source_key'], 'posted_on': row['posted_on'],
    },
  }).toList();
  final finance = financeItems.isNotEmpty || money.any((row) =>
      row.containsKey('account') || row.containsKey('category') || row.containsKey('recorded_on'));
  return jsonEncode({
    'format': 'shubchik-guest',
    'version': finance ? 4 : planner ? 3 : money.any((row) => row.containsKey('source_key')) ? 2 : 1,
    'tasks': planned,
    'ledger': money,
    if (planner || finance) 'habits': habits,
    if (planner || finance) 'habit_entries': habitEntries,
    if (finance) 'finance_items': financeItems,
  });
}

GuestBackup decodeBackup(String text) {
  if (text.length > 10000000) throw const FormatException('Слишком большой файл');
  final data = jsonDecode(text);
  if (data is! Map || data['format'] != 'shubchik-guest' || !const {1, 2, 3, 4}.contains(data['version'])) {
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
        final due = row['due_on'];
        final project = row['project'];
        if (due != null) {
          if ((data['version'] as int) < 3 || due is! String || !validStatementDate(due)) {
            throw const FormatException('Некорректный срок задачи');
          }
          result['due_on'] = due;
        }
        if (project != null) {
          if ((data['version'] as int) < 3 || project is! String ||
              project.trim().isEmpty || project.length > 80) {
            throw const FormatException('Некорректное название проекта');
          }
          result['project'] = project;
        }
      } else if (table == 'ledger') {
        if (row['cents'] is! int || row['cents'] == 0 ||
            (row['cents'] as int).abs() > 99999999999) {
          throw const FormatException('Некорректная сумма');
        }
        result['cents'] = row['cents'];
        for (final key in ['account', 'category', 'recorded_on']) {
          final value = row[key];
          if (value == null) continue;
          if (data['version'] != 4 || value is! String || value.trim().isEmpty ||
              value.length > 80 || (key == 'recorded_on' && !validStatementDate(value))) {
            throw const FormatException('Некорректная информация об операции');
          }
          result[key] = value;
        }
        final source = row['source_key'];
        final date = row['posted_on'];
        if (source != null || date != null) {
          if (data['version'] == 1 || source is! String ||
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

  final tasks = rows('tasks');
  final ledger = rows('ledger');
  if ((data['version'] as int) < 3) {
    return (tasks: tasks, ledger: ledger, habits: [], habitEntries: [], financeItems: []);
  }
  final habits = rows('habits');
  final ids = habits.map((row) => row['id']).toSet();
  final entries = data['habit_entries'];
  if (entries is! List || entries.length > 50000) {
    throw const FormatException('Некорректный журнал привычек');
  }
  final keys = <(int, String)>{};
  final habitEntries = entries.map<Map<String, Object?>>((row) {
    if (row is! Map) throw const FormatException('Некорректная отметка привычки');
    final id = row['habit_id'];
    final day = row['day'];
    if (id is! int || !ids.contains(id) || day is! String ||
        !validStatementDate(day) || !keys.add((id, day))) {
      throw const FormatException('Некорректная отметка привычки');
    }
    return {'habit_id': id, 'day': day};
  }).toList();
  final financeItems = <Map<String, Object?>>[];
  if (data['version'] == 4) {
    final records = data['finance_items'];
    if (records is! List || records.length > 5000) {
      throw const FormatException('Некорректный финансовый план');
    }
    final itemIds = <int>{};
    final itemNames = <(String, String)>{};
    for (final row in records) {
      if (row is! Map) throw const FormatException('Некорректный финансовый план');
      final id = row['id'];
      final kind = row['kind'];
      final title = row['title'];
      final target = row['target'];
      final current = row['current'];
      final due = row['due_on'];
      if (id is! int || id <= 0 || !itemIds.add(id) ||
          kind is! String || !financeKinds.contains(kind) ||
          title is! String || title.trim().isEmpty || title.length > 80 ||
          !itemNames.add((kind, title)) ||
          target is! int || target.abs() > 99999999999 ||
          (kind != 'account' && target <= 0) ||
          current is! int || current < 0 || current > 99999999999 ||
          (due != null && (due is! String || !validStatementDate(due)))) {
        throw const FormatException('Некорректный финансовый план');
      }
      financeItems.add({
        'id': id, 'kind': kind, 'title': title, 'target': target, 'current': current, 'due_on': due,
      });
    }
  }
  return (
    tasks: tasks, ledger: ledger, habits: habits, habitEntries: habitEntries, financeItems: financeItems,
  );
}
