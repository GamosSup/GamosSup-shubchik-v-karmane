import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_screen.dart';
import 'package:shubchik/guest_store.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  setUpAll(() {
    ffi.sqfliteFfiInit();
    sqlite.databaseFactory = ffi.databaseFactoryFfi;
  });

  test('Filters week and project, and sorts dated tasks on the timeline', () {
    final rows = <Map<String, Object?>>[
      {'id': 1, 'due_on': '2026-11-16', 'project': 'Работа'},
      {'id': 2, 'due_on': null},
      {'id': 3, 'due_on': '2026-11-09', 'project': 'Работа'},
      {'id': 4, 'due_on': '2026-11-11', 'project': 'Личное'},
    ];
    final anchor = DateTime(2026, 11, 11);
    expect(filterPlannerTasks(rows, PlannerView.week, anchor, 'Работа').map((row) => row['id']), [3]);
    expect(filterPlannerTasks(rows, PlannerView.day, anchor, null).map((row) => row['id']), [4]);
    expect(filterPlannerTasks(rows, PlannerView.month, anchor, null).map((row) => row['id']), [1, 3, 4]);
    expect(filterPlannerTasks(rows, PlannerView.timeline, anchor, null).map((row) => row['id']), [3, 4, 1, 2]);
  });

  test('Task deadlines and one habit entry per day survive backup restore', () async {
    final store = GuestStore(fileName: sqlite.inMemoryDatabasePath);
    addTearDown(() async => (await store.database).close());
    await store.addTask('Написать отчёт', dueOn: '2026-11-11', project: 'Работа');
    await store.addHabit('Чтение');
    final id = (await store.habitsFor('2026-11-11')).single['id'] as int;
    await store.setHabitDay(id, '2026-11-11', true);
    await store.setHabitDay(id, '2026-11-11', true);
    final backup = await store.exportBackup();
    await store.clear();
    expect(await store.habitsFor('2026-11-11'), isEmpty);
    await store.restoreBackup(backup);
    expect((await store.entries('tasks')).single['due_on'], '2026-11-11');
    final habit = (await store.habitsFor('2026-11-11')).single;
    expect(habit['done'], 1);
    expect(habit['total'], 1);
    await store.remove('habits', id);
    expect(decodeBackup(await store.exportBackup()).habitEntries, isEmpty);
  });
}
