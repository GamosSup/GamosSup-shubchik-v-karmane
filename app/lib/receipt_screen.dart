import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'guest_store.dart';

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.store, required this.ledgerId});
  final GuestStore store;
  final int ledgerId;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Future<({String name, Uint8List bytes})?> _receipt;
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _receipt = widget.store.receiptFor(widget.ledgerId);
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) setState(() {
        _message = message;
        _receipt = widget.store.receiptFor(widget.ledgerId);
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось открыть или сохранить чек');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (!mounted || result == null) return 'Выбор отменён';
    final file = result.files.single;
    final path = file.path;
    if (path == null || file.size > receiptFileLimit) {
      throw const FormatException('Нужен JPEG, PNG или PDF до 512 КиБ');
    }
    final bytes = await File(path).readAsBytes();
    if (!mounted) return 'Выбор отменён';
    await widget.store.setReceipt(widget.ledgerId, file.name, bytes);
    return 'Чек сохранён';
  }

  Future<String> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чек из операции?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (!mounted || ok != true) return 'Удаление отменено';
    await widget.store.setReceipt(widget.ledgerId, null, null);
    return 'Чек удалён из операции';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Чек')),
    body: FutureBuilder(
      future: _receipt,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final receipt = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Фото или PDF до 512 КиБ. Чек включается в резервную копию операции.'),
            if (snapshot.hasError) const Text('Не удалось прочитать вложение'),
            if (receipt != null) ...[
              ListTile(leading: const Icon(Icons.receipt_long), title: Text(receipt.name)),
              if (!receipt.name.toLowerCase().endsWith('.pdf'))
                Image.memory(receipt.bytes, cacheWidth: 800, errorBuilder: (_, _, _) => const Text('Предпросмотр недоступен')),
              OutlinedButton(onPressed: _busy ? null : () => _run(() async {
                final path = await FilePicker.platform.saveFile(
                  fileName: receipt.name, bytes: receipt.bytes,
                );
                return path == null ? 'Сохранение отменено' : 'Файл сохранён';
              }), child: const Text('Сохранить копию файла')),
              TextButton(onPressed: _busy ? null : () => _run(_remove), child: const Text('Удалить чек')),
            ],
            FilledButton(
              onPressed: _busy ? null : () => _run(_pick),
              child: Text(receipt == null ? 'Прикрепить чек' : 'Заменить чек'),
            ),
            if (_busy) const LinearProgressIndicator(),
            Text(_message),
          ],
        );
      },
    ),
  );
}
