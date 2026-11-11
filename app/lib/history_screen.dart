import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'guest_store.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key, required this.client, required this.accountId, required this.store,
  });

  final SupabaseClient client;
  final String accountId;
  final GuestStore store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _history;
  bool _busy = false;
  String _status = '';

  bool get _sameAccount => widget.client.auth.currentUser?.id == widget.accountId;

  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!_sameAccount) throw StateError('Account changed');
    return widget.client.from('account_snapshot_history')
        .select('backed_up_on,revision')
        .eq('owner_id', widget.accountId)
        .order('backed_up_on', ascending: false)
        .limit(7);
  }

  Future<void> _restore(String day) async {
    if (!_sameAccount || _busy) return;
    setState(() => _busy = true);
    try {
      final row = await widget.client.from('account_snapshot_history')
          .select('payload').eq('owner_id', widget.accountId)
          .eq('backed_up_on', day).single();
      final payload = jsonEncode(row['payload']);
      final data = decodeBackup(payload);
      if (!mounted || !_sameAccount) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Восстановить копию за $day?'),
          content: Text('Задач: ${data.tasks.length}. Операций: ${data.ledger.length}. '
              'Текущие записи аккаунта на телефоне будут заменены. Сначала можно экспортировать их из «Моих данных».'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Восстановить')),
          ],
        ),
      );
      if (confirm != true || !mounted || !_sameAccount) return;
      await widget.store.restoreBackup(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Копия восстановлена на телефоне. Синхронизация проверит облачную версию.')),
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _status = 'Не удалось восстановить выбранную копию');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Облачные копии')),
    body: FutureBuilder(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(
          onPressed: () => setState(() => _history = _load()),
          child: const Text('Не удалось загрузить копии. Повторить'),
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('При первом обновлении за день сохраняется предыдущая версия задач и финансов. Здесь доступно до семи дат.'),
            if (_busy) const LinearProgressIndicator(),
            if (_status.isNotEmpty) Text(_status),
            if (snapshot.data!.isEmpty) const ListTile(title: Text('Облачных копий пока нет')),
            for (final row in snapshot.data!) ListTile(
              title: Text(row['backed_up_on'] as String),
              subtitle: Text('Версия ${row['revision']}'),
              trailing: const Icon(Icons.restore),
              onTap: _busy ? null : () => _restore(row['backed_up_on'] as String),
            ),
          ],
        );
      },
    ),
  );
}
