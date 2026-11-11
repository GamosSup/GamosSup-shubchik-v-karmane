import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'bank_csv.dart';
import 'guest_store.dart';

class BankImportScreen extends StatefulWidget {
  const BankImportScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  final _account = TextEditingController();
  String _bank = 'sber';
  List<BankRow> _rows = [];
  String _status = '';
  bool _busy = false;

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await operation();
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = 'Не удалось обработать файл или сохранить операции');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    final account = _account.text.trim();
    if (account.isEmpty) {
      setState(() => _status = 'Укажите постоянный код счёта для повторных импортов');
      return;
    }
    setState(() => _rows = []);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv'],
    );
    if (!mounted || result == null) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null || file.size > 1000000) {
      throw const FormatException('Нужен CSV размером до 1 МБ');
    }
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    final rows = parseBankCsv(utf8.decode(bytes), bank: _bank, account: account);
    setState(() => _rows = rows);
  }

  Future<void> _save() async {
    final rows = _rows;
    final count = await widget.store.importBankRows(rows, account: _account.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено: $count. Уже были в журнале: ${rows.length - count}.')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Импорт операций')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Подготовьте CSV в UTF-8 с колонками id;date;title;amount. Дата — ГГГГ-ММ-ДД. Расход указывайте со знаком минус. ID операции должен совпадать в повторных выгрузках.'),
        const SizedBox(height: 12),
        const SelectableText('id;date;title;amount\nA001;2026-11-11;Продукты;-450,30'),
        DropdownButtonFormField<String>(
          initialValue: _bank,
          decoration: const InputDecoration(labelText: 'Банк'),
          items: const [
            DropdownMenuItem(value: 'sber', child: Text('Сбер')),
            DropdownMenuItem(value: 'ozon', child: Text('Ozon Банк')),
            DropdownMenuItem(value: 'other', child: Text('Другой')),
          ],
          onChanged: _busy ? null : (bank) => setState(() {
            _bank = bank!;
            _rows = [];
          }),
        ),
        TextField(
          controller: _account, enabled: !_busy, maxLength: 64,
          decoration: const InputDecoration(labelText: 'Код счёта, например «основной»'),
          onChanged: (_) { if (_rows.isNotEmpty) setState(() => _rows = []); },
        ),
        FilledButton(onPressed: _busy ? null : () => _run(_choose), child: const Text('Выбрать CSV')),
        if (_status.isNotEmpty) Text(_status),
        if (_busy) const LinearProgressIndicator(),
        if (_rows.isNotEmpty) ...[
          Text('К импорту: ${_rows.length} операций'),
          for (final row in _rows.take(10)) ListTile(
            title: Text(row.title), subtitle: Text(row.date), trailing: Text(formatMoney(row.cents)),
          ),
          FilledButton(onPressed: _busy ? null : () => _run(_save), child: const Text('Подтвердить импорт')),
        ],
      ],
    ),
  );
}
