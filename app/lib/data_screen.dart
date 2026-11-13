import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'guest_store.dart';
import 'diagnostics_screen.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  static const _crypto = MethodChannel('shubchik/backup_crypto');
  static const _magic = [83, 72, 85, 66, 75, 48, 49];
  bool _busy = false;
  String _status = '';

  Future<bool> _confirm(String title) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text('Текущие задачи, привычки и финансовые записи будут заменены. Сначала сохраните резервную копию.'),
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

  Future<String?> _passphrase({required bool creating}) async {
    var password = '';
    var repeated = '';
    String? error;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(creating ? 'Пароль резервной копии' : 'Введите пароль копии'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              obscureText: true,
              maxLength: 256,
              decoration: const InputDecoration(labelText: 'Пароль'),
              onChanged: (value) => password = value,
            ),
            if (creating)
              TextField(
                obscureText: true,
                maxLength: 256,
                decoration: const InputDecoration(labelText: 'Повторите пароль'),
                onChanged: (value) => repeated = value,
              ),
            if (error != null) Text(error!),
          ]),
          scrollable: true,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (password.length < 12 || password.length > 256) {
                  update(() => error = 'Введите от 12 до 256 символов');
                } else if (creating && password != repeated) {
                  update(() => error = 'Пароли не совпадают');
                } else {
                  Navigator.pop(context, password);
                }
              },
              child: const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _crypt(String method, Uint8List bytes, String password) async {
    final result = await _crypto.invokeMethod<Uint8List>(
      method, {'bytes': bytes, 'password': password},
    );
    if (result == null) throw const FormatException('Нет данных');
    return result;
  }

  Future<String> _export() async {
    final password = await _passphrase(creating: true);
    if (password == null) return 'Сохранение отменено';
    final text = await widget.store.exportBackup();
    final bytes = await _crypt('encrypt', Uint8List.fromList(utf8.encode(text)), password);
    if (!mounted) return 'Сохранение отменено';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить резервную копию',
      fileName: 'shubchik-backup.shubk',
      bytes: bytes,
    );
    return path == null ? 'Сохранение отменено' : 'Резервная копия сохранена';
  }

  Future<String> _restore() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return 'Выбор файла отменён';
    final file = result.files.single;
    if (file.size > 10000051 || file.bytes == null) {
      throw const FormatException('Некорректный файл');
    }
    var bytes = file.bytes!;
    final encrypted = bytes.length >= _magic.length &&
        List.generate(_magic.length, (index) => bytes[index] == _magic[index])
            .every((matches) => matches);
    if (encrypted) {
      if (!mounted) return 'Восстановление отменено';
      final password = await _passphrase(creating: false);
      if (password == null) return 'Восстановление отменено';
      try {
        bytes = await _crypt('decrypt', bytes, password);
      } on PlatformException {
        return 'Пароль неверен или копия повреждена';
      }
    }
    final text = utf8.decode(bytes);
    decodeBackup(text);
    if (!mounted || !await _confirm('Восстановить данные из файла?')) {
      return 'Восстановление отменено';
    }
    await widget.store.restoreBackup(text);
    return 'Данные восстановлены';
  }

  Future<String> _restoreLocal() async {
    final text = await widget.store.latestRecoveryPoint();
    if (text == null) return 'Автоматических копий пока нет';
    if (!mounted || !await _confirm('Вернуть данные из последней локальной копии?')) {
      return 'Восстановление отменено';
    }
    await widget.store.restoreBackup(text);
    return 'Локальная копия восстановлена';
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
        const Text('Сохраните зашифрованную копию вне телефона. Для восстановления понадобится пароль. Старые копии JSON можно открыть.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : () => _run(_export), child: const Text('Сохранить резервную копию')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_restore), child: const Text('Восстановить из файла')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_restoreLocal), child: const Text('Вернуть последнюю локальную копию')),
        TextButton(onPressed: _busy ? null : () => _run(_delete), child: const Text('Удалить гостевые данные')),
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => DiagnosticsScreen(store: widget.store),
          )),
          child: const Text('Диагностика'),
        ),
        if (_busy) const LinearProgressIndicator(),
        Text(_status, semanticsLabel: _status),
      ],
    ),
  );
}
