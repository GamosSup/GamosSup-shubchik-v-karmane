import 'package:flutter/material.dart';

import 'guest_store.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  late Future<List<Map<String, Object?>>> _rows;
  bool _busy = false;

  String get _day => _date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _rows = widget.store.habitsFor(_day);
  }

  void _refresh() => setState(() => _rows = widget.store.habitsFor(_day));

  Future<void> _save(Future<void> Function() change) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await change();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить изменение')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    var title = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая привычка'),
        content: TextField(
          autofocus: true, maxLength: 120,
          decoration: const InputDecoration(labelText: 'Название'),
          onChanged: (text) => title = text.trim(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () { if (title.isNotEmpty) Navigator.pop(context, title); },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (result != null && mounted) await _save(() => widget.store.addHabit(result));
  }

  Future<void> _delete(Map<String, Object?> habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить привычку и её отметки?'),
        content: Text(habit['title'] as String),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(() => widget.store.remove('habits', habit['id'] as int));
    }
  }

  Future<void> _choose() async {
    final date = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime(2000), lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      _date = date;
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Привычки')),
    floatingActionButton: FloatingActionButton(
      onPressed: _busy ? null : _add,
      tooltip: 'Добавить привычку',
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(
          onPressed: _refresh, child: const Text('Не удалось открыть привычки. Повторить'),
        ));
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _choose, icon: const Icon(Icons.today),
              label: Text(MaterialLocalizations.of(context).formatMediumDate(_date)),
            ),
            if (rows.isEmpty) const ListTile(title: Text('Добавьте первую привычку')),
            for (final habit in rows)
              ListTile(
                leading: Checkbox(
                  value: habit['done'] == 1,
                  onChanged: _busy ? null : (done) => _save(
                    () => widget.store.setHabitDay(habit['id'] as int, _day, done!),
                  ),
                ),
                title: Text(habit['title'] as String),
                subtitle: Text('Отмечено дней: ${habit['total']}'),
                trailing: IconButton(
                  tooltip: 'Удалить привычку', icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _delete(habit),
                ),
              ),
          ],
        );
      },
    ),
  );
}
