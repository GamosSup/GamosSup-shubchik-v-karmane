import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'guest_store.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;
  String _status = '';

  Future<bool> _confirm(String title) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text('Текущие задачи и финансовые записи будут заменены. Сначала сохраните резервную копию.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Продолжить')),
      ],
    ),
  ) ?? false;

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final status = await action();
      if (mounted) setState(() => _status = status);
    } on FormatException {
      if (mounted) setState(() => _status = 'Файл повреждён или имеет неподдерживаемый формат');
    } catch (_) {
      if (mounted) setState(() => _status = 'Операция не выполнена. Повторите попытку');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _export() async {
    final text = await widget.store.exportBackup();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить резервную копию',
      fileName: 'shubchik-backup.json',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    return path == null ? 'Сохранение отменено' : 'Резервная копия сохранена';
  }

  Future<String> _restore() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return 'Выбор файла отменён';
    final file = result.files.single;
    if (file.size > 10000000 || file.bytes == null) {
      throw const FormatException('Некорректный файл');
    }
    final text = utf8.decode(file.bytes!);
    decodeBackup(text);
    if (!mounted || !await _confirm('Восстановить данные из файла?')) {
      return 'Восстановление отменено';
    }
    await widget.store.restoreBackup(text);
    return 'Данные восстановлены';
  }

  Future<String> _delete() async {
    if (!await _confirm('Удалить все гостевые данные?')) return 'Удаление отменено';
    await widget.store.clear();
    return 'Гостевые данные удалены';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои данные')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Копия содержит задачи и финансовые записи открытым текстом. Храните её в защищённом месте.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : () => _run(_export), child: const Text('Сохранить резервную копию')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_restore), child: const Text('Восстановить из файла')),
        TextButton(onPressed: _busy ? null : () => _run(_delete), child: const Text('Удалить гостевые данные')),
        if (_busy) const LinearProgressIndicator(),
        Text(_status, semanticsLabel: _status),
      ],
    ),
  );
}
