import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.scope});
  final String scope;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  static final _database = openDatabase(
    'shubchik_focus.db',
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE focus (
        scope TEXT PRIMARY KEY,
        ends_at INTEGER,
        minutes INTEGER NOT NULL,
        completed INTEGER NOT NULL
      )
    '''),
  );

  late final Timer _ticker;
  DateTime? _endsAt;
  int _minutes = 25;
  int _completed = 0;
  bool _loaded = false;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await (await _database).query(
        'focus', where: 'scope = ?', whereArgs: [widget.scope],
      );
      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty) {
          final row = rows.single;
          final endsAt = row['ends_at'] as int?;
          _endsAt = endsAt == null ? null : DateTime.fromMillisecondsSinceEpoch(endsAt);
          _minutes = row['minutes'] as int;
          _completed = row['completed'] as int;
        }
        _loaded = true;
        _error = '';
      });
      _tick();
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось открыть таймер');
    }
  }

  Future<void> _save({required DateTime? end, required int minutes, required int completed}) async {
    if (!_loaded || _busy) return;
    setState(() => _busy = true);
    try {
      await (await _database).insert('focus', {
        'scope': widget.scope, 'ends_at': end?.millisecondsSinceEpoch,
        'minutes': minutes, 'completed': completed,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (!mounted) return;
      setState(() {
        _endsAt = end;
        _minutes = minutes;
        _completed = completed;
        _error = '';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить таймер');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    final end = _endsAt;
    if (!_loaded || _busy || end == null) return;
    if (!end.isAfter(DateTime.now())) {
      unawaited(_save(end: null, minutes: _minutes, completed: _completed + (_minutes == 25 ? 1 : 0)));
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _endsAt?.difference(DateTime.now()).inMilliseconds;
    final seconds = remaining == null ? _minutes * 60 : (remaining / 1000).ceil().clamp(0, _minutes * 60);
    final time = '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Pomodoro')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(time, style: Theme.of(context).textTheme.displayLarge),
          Text('Завершено рабочих интервалов: $_completed'),
          const SizedBox(height: 16),
          if (!_loaded && _error.isEmpty) const LinearProgressIndicator(),
          if (_error.isNotEmpty) Text(_error),
          if (!_loaded && _error.isNotEmpty)
            TextButton(onPressed: _load, child: const Text('Повторить')),
          if (_endsAt == null) ...[
            FilledButton(
              onPressed: !_loaded || _busy ? null : () => _save(
                end: DateTime.now().add(const Duration(minutes: 25)), minutes: 25, completed: _completed,
              ),
              child: const Text('Начать 25 минут работы'),
            ),
            OutlinedButton(
              onPressed: !_loaded || _busy ? null : () => _save(
                end: DateTime.now().add(const Duration(minutes: 5)), minutes: 5, completed: _completed,
              ),
              child: const Text('Начать 5 минут отдыха'),
            ),
          ] else
            OutlinedButton(
              onPressed: _busy ? null : () => _save(end: null, minutes: _minutes, completed: _completed),
              child: const Text('Остановить'),
            ),
          const Text('Таймер сохраняется при закрытии. Результат отображается при возвращении на этот экран.'),
        ],
      ),
    );
  }
}
