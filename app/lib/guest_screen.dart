import 'package:flutter/material.dart';
import 'guest_store.dart';

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

  Future<void> _add() async {
    final entry = await showDialog<({String title, int cents})>(
      context: context,
      builder: (context) => _EntryDialog(finance: widget.finance),
    );
    if (entry == null || !mounted) return;
    await _save(() => widget.finance
        ? widget.store.addMoney(entry.title, entry.cents)
        : widget.store.addTask(entry.title));
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
      await _save(() => widget.store.remove(_table, id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.finance ? 'Финансы' : 'Планировщик')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить', onPressed: _saving ? null : _add,
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
          final rows = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final summary = widget.finance
                    ? 'Баланс: ${formatMoney(rows.fold<int>(0, (sum, row) => sum + (row['cents'] as int)))}'
                    : rows.isEmpty ? 'Добавьте первую задачу' : 'Задачи';
                return ListTile(title: Text(summary), subtitle: const Text('На этом устройстве'));
              }
              final row = rows[index - 1];
              final id = row['id'] as int;
              return ListTile(
                title: Text(row['title'] as String),
                subtitle: widget.finance ? Text(formatMoney(row['cents'] as int)) : null,
                leading: widget.finance ? null : Checkbox(
                  value: row['done'] == 1,
                  onChanged: _saving ? null : (done) => _save(() => widget.store.setDone(id, done!)),
                ),
                trailing: IconButton(
                  tooltip: 'Удалить', icon: const Icon(Icons.delete_outline),
                  onPressed: _saving ? null : () => _remove(id),
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
  const _EntryDialog({required this.finance});
  final bool finance;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  bool _expense = true;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.finance ? 'Новая операция' : 'Новая задача'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title, autofocus: true, maxLength: 120,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (value) => value!.trim().isEmpty ? 'Введите название' : null,
            ),
            if (widget.finance) ...[
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
          ],
        ),
      ),
      scrollable: true,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final cents = widget.finance ? parseCents(_amount.text)! : 0;
            Navigator.pop(context, (title: _title.text.trim(), cents: _expense ? -cents : cents));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
