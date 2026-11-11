import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'guest_store.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<Map<String, Object?>> _report;

  @override
  void initState() {
    super.initState();
    _report = widget.store.diagnostics();
  }

  Future<void> _copy(Map<String, Object?> report) async {
    try {
      await Clipboard.setData(ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(report),
      ));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Диагностика скопирована')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось скопировать диагностику')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Диагностика')),
    body: FutureBuilder(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(
          onPressed: () => setState(() => _report = widget.store.diagnostics()),
          child: const Text('Не удалось загрузить диагностику. Повторить'),
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final report = snapshot.data!;
        final counts = report['counts'] as Map<String, int>;
        final events = report['events'] as List<Map<String, Object?>>;
        const labels = {'tasks': 'Задачи', 'ledger': 'Операции', 'habits': 'Привычки', 'finance_items': 'Финансовый план'};
        const actions = {
          'assistant_task_added': 'Помощник добавил задачу после подтверждения',
          'data_restored': 'Данные восстановлены',
          'data_cleared': 'Данные очищены',
        };
        final dates = MaterialLocalizations.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Схема данных: ${report['schema']}'),
            Text('Последняя облачная версия: ${report['cloud_revision']}'),
            for (final entry in counts.entries) Text('${labels[entry.key]}: ${entry.value}'),
            OutlinedButton.icon(
              onPressed: () => _copy(report), icon: const Icon(Icons.copy),
              label: const Text('Копировать диагностику'),
            ),
            const Divider(),
            const ListTile(title: Text('Журнал действий')),
            if (events.isEmpty) const Text('Действий пока нет'),
            for (final row in events) ListTile(
              title: Text(actions[row['event']] ?? 'Изменение данных'),
              subtitle: Text(dates.formatShortDate(
                DateTime.fromMillisecondsSinceEpoch(row['occurred_at'] as int),
              )),
            ),
          ],
        );
      },
    ),
  );
}
