import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'guest_store.dart';

class BankNotificationsScreen extends StatefulWidget {
  const BankNotificationsScreen({super.key, required this.store});

  final GuestStore store;

  @override
  State<BankNotificationsScreen> createState() => _BankNotificationsScreenState();
}

class _BankNotificationsScreenState extends State<BankNotificationsScreen> {
  static const _channel = MethodChannel('shubchik/bank_notifications');
  List<Map<String, dynamic>> _items = [];
  bool _enabled = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _run(_read);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось выполнить действие');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('read');
    final items = jsonDecode(result?['items'] as String? ?? '[]') as List;
    if (!mounted) return;
    setState(() {
      _enabled = result?['enabled'] == true;
      _items = items.cast<Map<String, dynamic>>().reversed.toList();
    });
  }

  Future<void> _updateAccess(bool enabled) async {
    await _channel.invokeMethod<void>(enabled ? 'enable' : 'disable');
    await _read();
  }

  Future<void> _review(Map<String, dynamic> item, {required bool save}) async {
    final id = item['id'] as String;
    if (save) {
      final date = DateTime.fromMillisecondsSinceEpoch(item['time'] as int)
          .toIso8601String().split('T').first;
      await widget.store.importBankRows([(
        key: 'notification:$id',
        date: date,
        title: _bankName(item['bank']),
        cents: item['cents'] as int,
      )]);
    }
    await _channel.invokeMethod<void>('dismiss', {'id': id});
    await _read();
  }

  String _bankName(Object? bank) => bank == 'sber' ? 'Сбер' : 'Ozon Банк';

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Банковские уведомления')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Экспериментальная сверка. Android запрашивает доступ к уведомлениям. '
            'Шубчик отбирает сообщения Сбера и Ozon Банка на устройстве '
            'и сохраняет для сверки сумму, банк и время. '
            'Сравните кандидатов с выпиской перед добавлением в журнал.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : () => _run(() => _updateAccess(true)),
            child: Text(_enabled ? 'Открыть доступ Android' : 'Настроить доступ'),
          ),
          if (_enabled)
            TextButton(
              onPressed: _busy ? null : () => _run(() => _updateAccess(false)),
              child: const Text('Остановить сбор и очистить список'),
            ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(_read),
            child: const Text('Обновить список'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
          if (_items.isEmpty && !_busy) const Text('Кандидатов для сверки пока нет'),
          for (final item in _items)
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(_bankName(item['bank'])),
                    subtitle: Text(
                      '${formatMoney(item['cents'] as int)} · '
                      '${MaterialLocalizations.of(context).formatMediumDate(
                        DateTime.fromMillisecondsSinceEpoch(item['time'] as int),
                      )}',
                    ),
                  ),
                  Wrap(children: [
                    TextButton(
                      onPressed: _busy ? null : () => _run(() => _review(item, save: true)),
                      child: const Text('Добавить в журнал'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run(() => _review(item, save: false)),
                      child: const Text('Пропустить'),
                    ),
                  ]),
                ],
              ),
            ),
        ],
      ),
  );
}
