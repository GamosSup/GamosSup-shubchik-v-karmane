import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_client.dart';
import 'guest_store.dart';
import 'voice_button.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.store, this.accountId});

  final GuestStore store;
  final String? accountId;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _storage = FlutterSecureStorage();
  final _prompt = TextEditingController();
  final _memory = TextEditingController();
  bool _busy = false;
  bool _taskPermission = false;
  bool _sendMemory = false;
  String _answer = '';

  String get _memoryKey => 'assistant.memory.${widget.accountId ?? 'guest'}';

  @override
  void initState() {
    super.initState();
    unawaited(_readMemory());
  }

  @override
  void dispose() {
    _prompt.dispose();
    _memory.dispose();
    super.dispose();
  }

  Future<void> _readMemory() async {
    try {
      final text = await _storage.read(key: _memoryKey);
      if (mounted && _memory.text.isEmpty) _memory.text = text ?? '';
    } catch (_) {
      if (mounted) _setAnswer('Память недоступна');
    }
  }

  void _setAnswer(String answer) => setState(() => _answer = answer);

  Future<bool> _confirm(String title, String detail) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(detail)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Подтвердить')),
      ],
    ),
  ) ?? false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _setAnswer('Действие недоступно. Повторите позже.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMemory() async {
    await _storage.write(key: _memoryKey, value: _memory.text.trim());
    if (mounted) _setAnswer('Память сохранена на телефоне');
  }

  Future<void> _clearMemory() async {
    if (!await _confirm('Удалить память?', 'Заметка помощника будет удалена с телефона.')) return;
    await _storage.delete(key: _memoryKey);
    if (mounted) {
      _memory.clear();
      setState(() {
        _sendMemory = false;
        _answer = 'Память удалена';
      });
    }
  }

  Future<void> _createTask(String title) async {
    if (!_taskPermission) {
      _setAnswer('Разрешите помощнику добавлять задачи на этом экране');
      return;
    }
    if (title.isEmpty || title.length > 120) {
      _setAnswer('Название задачи должно содержать от 1 до 120 символов');
      return;
    }
    if (!await _confirm('Добавить задачу?', title) || !mounted) return;
    if (widget.accountId != null && (await authClient()).auth.currentUser?.id != widget.accountId) {
      if (mounted) _setAnswer('Войдите в аккаунт снова');
      return;
    }
    await widget.store.addTask(title, fromAssistant: true);
    if (mounted) _setAnswer('Задача добавлена');
  }

  bool _useOpenRouter = false;

  Future<void> _submit() async {
    final question = _prompt.text.trim();
    if (question.isEmpty) {
      _setAnswer('Введите вопрос или команду');
      return;
    }
    if (question.toLowerCase().startsWith('задача:')) {
      await _createTask(question.substring('задача:'.length).trim());
      return;
    }
    final client = await authClient();
    if (!mounted) return;
    final user = client.auth.currentUser;
    if (user == null || (widget.accountId != null && user.id != widget.accountId)) {
      _setAnswer('Для отправки запроса Kimi войдите в аккаунт');
      return;
    }
    final memory = _sendMemory ? _memory.text.trim() : '';
    final detail = memory.isEmpty ? question : '$question\n\nПамять:\n$memory';
    final openRouter = _useOpenRouter;
    final recipient = openRouter ? 'Kimi через OpenRouter' : 'Kimi (Moonshot AI)';
    if (!await _confirm('Отправить текст в $recipient?', detail) || !mounted) return;
    if (client.auth.currentUser?.id != user.id) {
      _setAnswer('Войдите в аккаунт снова');
      return;
    }
    try {
      final function = openRouter ? 'assistant-openrouter' : 'assistant';
      final response = await client.functions.invoke(function, body: {
        'question': question,
        if (openRouter) 'provider': 'openrouter',
        if (memory.isNotEmpty) 'memory': memory,
      });
      if (!mounted) return;
      final data = response.data;
      _setAnswer(data is Map && data['answer'] is String ? data['answer'] as String : 'Ответ недоступен');
    } on FunctionException catch (error) {
      if (!mounted) return;
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      _setAnswer(switch (code) {
        'not_configured' => 'Облачный Kimi ещё не включён. Локальные команды доступны.',
        'monthly_limit' => 'Месячный лимит запросов исчерпан',
        _ => 'Kimi недоступен. Повторите позже.',
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Помощник')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _prompt, enabled: !_busy,
          maxLines: 4, maxLength: 1500,
          decoration: const InputDecoration(
            labelText: 'Вопрос или команда', hintText: 'Задача: купить продукты',
          ),
        ),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: _busy ? null : () => _run(_submit), child: const Text('Продолжить')),
          VoiceButton(
            enabled: !_busy,
            onWords: (words) => _prompt.text = words.length > 1500 ? words.substring(0, 1500) : words,
          ),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (_answer.isNotEmpty) SelectableText(_answer),
        const Divider(),
        SwitchListTile(
          title: const Text('Разрешить добавление задач'),
          subtitle: const Text('Каждую задачу нужно подтвердить'),
          value: _taskPermission,
          onChanged: _busy ? null : (value) => setState(() => _taskPermission = value),
        ),
        SwitchListTile(
          title: const Text('Kimi через OpenRouter'),
          subtitle: const Text('Бесплатная модель. Запрос передаётся OpenRouter.'),
          value: _useOpenRouter,
          onChanged: _busy ? null : (value) => setState(() => _useOpenRouter = value),
        ),
        ExpansionTile(title: const Text('Память помощника'), children: [
          TextField(
            controller: _memory, enabled: !_busy, maxLength: 1000, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Заметка'),
          ),
          SwitchListTile(
            title: const Text('Включать заметку в запрос Kimi'),
            value: _sendMemory,
            onChanged: _busy ? null : (value) => setState(() => _sendMemory = value),
          ),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _run(_saveMemory), child: const Text('Сохранить на телефоне')),
            TextButton(onPressed: _busy ? null : () => _run(_clearMemory), child: const Text('Удалить память')),
          ]),
        ]),
      ],
    ),
  );
}
