import 'package:flutter/material.dart';
import 'guest_store.dart';
import 'device_calendar.dart';
import 'bank_import_screen.dart';
import 'habit_screen.dart';
import 'finance_plans_screen.dart';

enum PlannerView { all, day, week, month, timeline }

enum _TaskAction { calendar, reminder, cancel, delete }

String plannerDay(DateTime value) => value.toIso8601String().substring(0, 10);

List<Map<String, Object?>> filterPlannerTasks(
  List<Map<String, Object?>> rows, PlannerView view, DateTime date, String? project,
) {
  final scoped = rows.where((row) => project == null || row['project'] == project);
  if (view == PlannerView.all) return scoped.toList();
  if (view == PlannerView.timeline) {
    return scoped.toList()..sort((a, b) {
      final order = (a['due_on'] as String? ?? '9999-12-31')
          .compareTo(b['due_on'] as String? ?? '9999-12-31');
      return order == 0 ? (b['id'] as int).compareTo(a['id'] as int) : order;
    });
  }
  final weekStart = date.day - date.weekday + 1;
  final start = switch (view) {
    PlannerView.week => DateTime(date.year, date.month, weekStart),
    PlannerView.month => DateTime(date.year, date.month),
    _ => date,
  };
  final end = switch (view) {
    PlannerView.week => DateTime(date.year, date.month, weekStart + 7),
    PlannerView.month => DateTime(date.year, date.month + 1),
    _ => DateTime(date.year, date.month, date.day + 1),
  };
  final first = plannerDay(start);
  final next = plannerDay(end);
  return scoped.where((row) {
    final due = row['due_on'] as String?;
    return due != null && due.compareTo(first) >= 0 && due.compareTo(next) < 0;
  }).toList();
}

typedef _Entry = ({String title, int cents, String? dueOn, String? project, String? account, String? category});

class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key, required this.store, required this.finance});

  final GuestStore store;
  final bool finance;

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  late Future<List<Map<String, Object?>>> _entries;
  bool _saving = false;
  PlannerView _view = PlannerView.all;
  DateTime _anchor = DateTime.now();
  String? _project;
  String get _table => widget.finance ? 'ledger' : 'tasks';

  @override
  void initState() {
    super.initState();
    _entries = widget.store.entries(_table);
  }

  void _refresh() => setState(() => _entries = widget.store.entries(_table));

  Future<void> _save(Future<void> Function() change) async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      await change();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить изменение')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    final entry = await showDialog<_Entry>(
      context: context,
      builder: (context) => _EntryDialog(finance: widget.finance, initial: row),
    );
    if (entry == null || !mounted) return;
    await _save(() {
      if (widget.finance) {
        if (row != null) {
          return widget.store.updateMoneyTags(row['id'] as int, entry.account, entry.category);
        }
        return widget.store.addMoney(
          entry.title, entry.cents, account: entry.account,
          category: entry.category, recordedOn: plannerDay(DateTime.now()),
        );
      }
      if (row == null) {
        return widget.store.addTask(entry.title, dueOn: entry.dueOn, project: entry.project);
      }
      return widget.store.updateTask(
        row['id'] as int, entry.title, dueOn: entry.dueOn, project: entry.project,
      );
    });
  }

  Future<void> _chooseDate() async {
    final day = await showDatePicker(
      context: context, initialDate: _anchor, firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (day != null && mounted) setState(() => _anchor = day);
  }

  Widget _filters(List<Map<String, Object?>> rows) {
    final projects = rows.map((row) => row['project']).whereType<String>().toSet().toList()..sort();
    const labels = {
      PlannerView.all: 'Все', PlannerView.day: 'День', PlannerView.week: 'Неделя',
      PlannerView.month: 'Месяц', PlannerView.timeline: 'Таймлайн',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final item in labels.entries) ChoiceChip(
          label: Text(item.value), selected: _view == item.key,
          onSelected: (_) => setState(() => _view = item.key),
        ),
        if (_view != PlannerView.all && _view != PlannerView.timeline)
          OutlinedButton.icon(
            onPressed: _chooseDate, icon: const Icon(Icons.today),
            label: Text(MaterialLocalizations.of(context).formatMediumDate(_anchor)),
          ),
        if (projects.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Проект',
            onSelected: (value) => setState(() => _project = value.isEmpty ? null : value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Все проекты')),
              for (final project in projects) PopupMenuItem(value: project, child: Text(project)),
            ],
            child: Chip(label: Text(_project ?? 'Все проекты')),
          ),
      ]),
    );
  }

  Future<void> _remove(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(() async {
        await widget.store.remove(_table, id);
        if (!widget.finance) await cancelTaskReminder(_reminderKey(id));
      });
    }
  }

  String _reminderKey(int id) => '${widget.store.fileName}:$id';

  Future<void> _taskAction(_TaskAction action, Map<String, Object?> row) async {
    final id = row['id'] as int;
    final dueOn = row['due_on'] as String?;
    switch (action) {
      case _TaskAction.calendar:
        await composeCalendarEvent(context, row['title'] as String, dueOn: dueOn);
      case _TaskAction.reminder:
        await scheduleTaskReminder(context, _reminderKey(id), dueOn);
      case _TaskAction.cancel:
        final cancelled = await cancelTaskReminder(_reminderKey(id));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cancelled ? 'Напоминание отменено' : 'Не удалось отменить напоминание')),
        );
      case _TaskAction.delete:
        await _remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.finance ? 'Финансы' : 'Планировщик'),
        actions: [
          if (!widget.finance) IconButton(
            tooltip: 'Привычки', icon: const Icon(Icons.repeat),
            onPressed: _saving ? null : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => HabitScreen(store: widget.store)),
            ),
          ),
          if (widget.finance) IconButton(
            tooltip: 'Финансовый план', icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: _saving ? null : () async {
              await Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => FinancePlansScreen(store: widget.store),
              ));
              if (mounted) _refresh();
            },
          ),
          if (widget.finance) IconButton(
            tooltip: 'Импорт CSV', icon: const Icon(Icons.upload_file),
            onPressed: _saving ? null : () async {
              final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => BankImportScreen(store: widget.store),
              ));
              if (changed == true && mounted) _refresh();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить', onPressed: _saving ? null : () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: TextButton(
              onPressed: _refresh, child: const Text('Ошибка загрузки. Повторить'),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allRows = snapshot.data!;
          final rows = widget.finance ? allRows : filterPlannerTasks(allRows, _view, _anchor, _project);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final summary = widget.finance
                    ? 'Баланс: ${formatMoney(rows.fold<int>(0, (sum, row) => sum + (row['cents'] as int)))}'
                    : rows.isEmpty ? 'Добавьте первую задачу' : 'Задачи';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.finance) _filters(allRows),
                    ListTile(title: Text(summary), subtitle: const Text('На этом устройстве')),
                  ],
                );
              }
              final row = rows[index - 1];
              final id = row['id'] as int;
              final details = [row['due_on'], row['project']].whereType<String>().join(' · ');
              return ListTile(
                title: Text(row['title'] as String),
                onTap: _saving ? null : () => _edit(row),
                subtitle: widget.finance ? Text([
                  formatMoney(row['cents'] as int),
                  row['posted_on'] ?? row['recorded_on'],
                  row['account'], row['category'],
                ].whereType<String>().join(' · ')) : details.isEmpty ? null : Text(details),
                leading: widget.finance ? null : Checkbox(
                  value: row['done'] == 1,
                  onChanged: _saving ? null : (done) => _save(() async {
                    await widget.store.setDone(id, done!);
                    if (done == true) await cancelTaskReminder(_reminderKey(id));
                  }),
                ),
                trailing: widget.finance
                    ? IconButton(
                        tooltip: 'Удалить', icon: const Icon(Icons.delete_outline),
                        onPressed: _saving ? null : () => _remove(id),
                      )
                    : PopupMenuButton<_TaskAction>(
                        tooltip: 'Действия с задачей',
                        enabled: !_saving,
                        onSelected: (action) => _taskAction(action, row),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: _TaskAction.calendar, child: Text('Открыть в календаре')),
                          PopupMenuItem(value: _TaskAction.reminder, child: Text('Напомнить')),
                          PopupMenuItem(value: _TaskAction.cancel, child: Text('Отменить напоминание')),
                          PopupMenuItem(value: _TaskAction.delete, child: Text('Удалить')),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.finance, this.initial});
  final bool finance;
  final Map<String, Object?>? initial;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?['title'] as String?);
  late final _project = TextEditingController(text: widget.initial?['project'] as String?);
  late DateTime? _due = DateTime.tryParse(widget.initial?['due_on'] as String? ?? '');
  final _amount = TextEditingController();
  late final _account = TextEditingController(text: widget.initial?['account'] as String? ?? (widget.initial == null ? 'Наличные' : ''));
  late final _category = TextEditingController(text: widget.initial?['category'] as String?);
  bool get _tagsOnly => widget.finance && widget.initial != null;
  bool _expense = true;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _project.dispose();
    _account.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.finance ? (_tagsOnly ? 'Счёт и категория' : 'Новая операция') : widget.initial == null ? 'Новая задача' : 'Изменить задачу'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title, autofocus: !_tagsOnly, maxLength: 120, readOnly: _tagsOnly,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (value) => value!.trim().isEmpty ? 'Введите название' : null,
            ),
            if (!widget.finance) ...[
              TextFormField(
                controller: _project, maxLength: 80,
                decoration: const InputDecoration(labelText: 'Проект'),
              ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.today),
                  label: Text(_due == null ? 'Назначить дату' : MaterialLocalizations.of(context).formatMediumDate(_due!)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context, initialDate: _due ?? DateTime.now(),
                      firstDate: DateTime(2000), lastDate: DateTime(2100),
                    );
                    if (picked != null && mounted) setState(() => _due = picked);
                  },
                ),
                if (_due != null) IconButton(
                  tooltip: 'Убрать дату', onPressed: () => setState(() => _due = null),
                  icon: const Icon(Icons.clear),
                ),
              ]),
            ],
            if (widget.finance && !_tagsOnly) ...[
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Сумма в рублях'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => parseCents(value!) == null ? 'Введите сумму больше нуля' : null,
              ),
              SwitchListTile(
                title: Text(_expense ? 'Расход' : 'Доход'),
                value: _expense,
                onChanged: (value) => setState(() => _expense = value),
              ),
            ],
            if (widget.finance) ...[
              TextFormField(
                controller: _account, maxLength: 80,
                decoration: const InputDecoration(labelText: 'Название счёта'),
              ),
              TextFormField(
                controller: _category, maxLength: 80,
                decoration: const InputDecoration(labelText: 'Категория', helperText: 'Пустое поле включает автокатегорию'),
              ),
            ],
          ],
        ),
      ),
      scrollable: true,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final cents = _tagsOnly ? widget.initial!['cents'] as int
                : widget.finance ? parseCents(_amount.text)! * (_expense ? -1 : 1) : 0;
            final project = _project.text.trim();
            final account = _account.text.trim();
            final category = _category.text.trim();
            Navigator.pop(context, (
              title: _title.text.trim(), cents: cents,
              dueOn: _due == null ? null : plannerDay(_due!),
              project: project.isEmpty ? null : project,
              account: account.isEmpty ? null : account,
              category: !widget.finance ? null : category.isEmpty ? suggestCategory(_title.text, cents) : category,
            ));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
