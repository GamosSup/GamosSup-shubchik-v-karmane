import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';

import 'voice_button.dart';

typedef Poem = ({String author, String title, String language, List<String> lines, String? translation});

const List<Poem> _poems = [
  (author: 'Александр Пушкин', title: 'Руслан и Людмила · Пролог', language: 'ru-RU', lines: [
    'У лукоморья дуб зелёный;',
    'Златая цепь на дубе том:',
    'И днём и ночью кот учёный',
    'Всё ходит по цепи кругом;',
  ], translation: null),
  (author: 'Михаил Лермонтов', title: 'Парус', language: 'ru-RU', lines: [
    'Белеет парус одинокой',
    'В тумане моря голубом!..',
    'Что ищет он в стране далёкой?',
    'Что кинул он в краю родном?..',
  ], translation: null),
  (author: 'Фёдор Тютчев', title: 'Весенняя гроза', language: 'ru-RU', lines: [
    'Люблю грозу в начале мая,',
    'Когда весенний, первый гром,',
    'Как бы резвяся и играя,',
    'Грохочет в небе голубом.',
  ], translation: null),
  (author: 'Уильям Шекспир', title: 'Сонет 18', language: 'en-GB', lines: [
    'Shall I compare thee to a summer’s day?',
    'Thou art more lovely and more temperate:',
    'Rough winds do shake the darling buds of May,',
    'And summer’s lease hath all too short a date;',
  ], translation: 'Сравнить ли мне тебя с летним днём?\nТы прекраснее и мягче.\nРезкий ветер трясёт любимые бутоны мая,\nИ лету отведён слишком короткий срок.'),
  (author: 'Эмили Дикинсон', title: '«Надежда» — существо в перьях', language: 'en-US', lines: [
    '“Hope” is the thing with feathers —',
    'That perches in the soul —',
    'And sings the tune without the words —',
    'And never stops — at all —',
  ], translation: '«Надежда» — существо в перьях,\nОно сидит в душе,\nПоёт мелодию без слов\nИ вовсе не смолкает.'),
];

typedef Practice = ({int poem, int completed, int correct, int sessions});

class PoetryScreen extends StatefulWidget {
  const PoetryScreen({super.key});
  @override
  State<PoetryScreen> createState() => _PoetryScreenState();
}

class _PoetryScreenState extends State<PoetryScreen> {
  static final _database = openDatabase(
    'shubchik_practice.db',
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE sessions (
        day TEXT PRIMARY KEY,
        poem INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        correct INTEGER NOT NULL DEFAULT 0,
        next_day TEXT
      )
    '''),
  );

  final _tts = FlutterTts();
  final _answer = TextEditingController();
  late Future<Practice> _practice;
  late final _day = _date(DateTime.now());
  bool _saving = false;
  bool? _result;

  String _date(DateTime date) => date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _practice = _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    unawaited(_stopSpeech());
    super.dispose();
  }

  Future<void> _stopSpeech() async {
    try {
      await _tts.stop();
    } catch (_) {
      // TTS is optional on devices without a configured engine.
    }
  }

  Future<Practice> _load() async {
    final db = await _database;
    return db.transaction((tx) async {
      final rows = await tx.query('sessions', where: 'day = ?', whereArgs: [_day]);
      final history = await tx.query(
        'sessions', where: 'completed = 5 AND day < ?', whereArgs: [_day],
        orderBy: 'day DESC',
      );
      if (rows.isNotEmpty) {
        final row = rows.single;
        return (
          poem: row['poem'] as int, completed: row['completed'] as int,
          correct: row['correct'] as int,
          sessions: history.length + (row['completed'] == 5 ? 1 : 0),
        );
      }
      final nextDays = <int, String>{};
      for (final row in history) {
        nextDays.putIfAbsent(row['poem'] as int, () => row['next_day'] as String);
      }
      final candidates = List<int>.generate(_poems.length, (i) => i)
        ..sort((a, b) {
          final order = (nextDays[a] ?? '').compareTo(nextDays[b] ?? '');
          return order == 0 ? a.compareTo(b) : order;
        });
      final poem = candidates.first;
      await tx.insert('sessions', {'day': _day, 'poem': poem});
      return (poem: poem, completed: 0, correct: 0, sessions: history.length);
    });
  }

  Future<void> _advance(Practice practice, bool correct) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final completed = practice.completed + 1;
      final score = practice.correct + (correct ? 1 : 0);
      final today = DateTime.parse(_day);
      final interval = score >= 4 ? 3 : 1;
      final nextDay = DateTime(today.year, today.month, today.day + interval);
      await (await _database).update('sessions', {
        'completed': completed,
        'correct': score,
        if (completed == 5) 'next_day': _date(nextDay),
      }, where: 'day = ? AND completed = ?', whereArgs: [_day, practice.completed]);
      if (mounted) {
        _answer.clear();
        setState(() {
          _result = null;
          _practice = _load();
        });
      }
    } catch (_) {
      if (mounted) _message('Не удалось сохранить результат');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _speak(Poem poem) async {
    try {
      await _tts.setLanguage(poem.language);
      if (!mounted) return;
      if (await _tts.speak(poem.lines.join('\n')) != 1 && mounted) {
        _message('Озвучивание недоступно');
      }
    } catch (_) {
      if (mounted) _message('Озвучивание недоступно');
    }
  }

  String _normalize(String text) => text.toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9 ]'), '')
      .replaceAll(RegExp(r' +'), ' ').trim();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Развитие')),
    body: FutureBuilder(
      future: _practice,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(
          onPressed: () => setState(() => _practice = _load()),
          child: const Text('Не удалось открыть занятия. Повторить'),
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final practice = snapshot.data!;
        final poem = _poems[practice.poem];
        final step = practice.completed;
        if (step == 5) return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Занятие завершено', style: Theme.of(context).textTheme.headlineSmall),
            Text('Упражнений успешно выполнено: ${practice.correct} из 5'),
            Text('Завершённых занятий: ${practice.sessions}'),
          ],
        );
        final first = poem.lines.first;
        final lastWord = RegExp(r'[a-zA-Zа-яА-ЯёЁ]+(?=[^a-zA-Zа-яА-ЯёЁ]*$)').firstMatch(first)!;
        final missing = lastWord.group(0)!;
        final expected = step == 2 ? missing : poem.lines[1];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Упражнение ${step + 1} из 5 · около 4 минут'),
            LinearProgressIndicator(value: step / 5),
            const SizedBox(height: 20),
            if (step != 1) Text(poem.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (step == 0) ...[
              Text(poem.author),
              Text(poem.lines.join('\n')),
              if (poem.translation != null) ...[
                const SizedBox(height: 12),
                const Text('Подстрочный перевод'),
                Text(poem.translation!),
              ],
              OutlinedButton.icon(onPressed: () => _speak(poem), icon: const Icon(Icons.volume_up), label: const Text('Прослушать')),
              FilledButton(onPressed: _saving ? null : () => _advance(practice, true), child: const Text('Дальше')),
            ],
            if (step == 1) ...[
              const Text('Кто написал этот отрывок?'),
              Text(poem.lines.join('\n')),
              for (final candidate in _poems)
                OutlinedButton(
                  onPressed: _saving || _result != null ? null : () => setState(() => _result = candidate.author == poem.author),
                  child: Text(candidate.author),
                ),
              if (_result != null) Text('Автор: ${poem.author}'),
            ],
            if (step == 2 || step == 3) ...[
              Text(step == 2 ? 'Вставьте последнее слово' : 'Напишите вторую строку'),
              Text(step == 2 ? '${first.substring(0, lastWord.start).trimRight()} …' : first),
              TextField(controller: _answer, enabled: _result == null, decoration: const InputDecoration(labelText: 'Ответ')),
              OutlinedButton(
                onPressed: _result == null ? () => setState(() {
                  _result = _normalize(_answer.text) == _normalize(expected);
                }) : null,
                child: const Text('Проверить'),
              ),
              if (_result != null) Text('Ответ: $expected'),
            ],
            if (step >= 1 && step <= 3 && _result != null)
              FilledButton(
                onPressed: _saving ? null : () => _advance(practice, _result!),
                child: Text(_result! ? 'Верно · дальше' : 'Дальше'),
              ),
            if (step == 4) ...[
              const Text('Прочитайте отрывок по памяти. Можно проверить распознанный текст или оценить себя.'),
              VoiceButton(
                enabled: !_saving, locale: poem.language.replaceAll('-', '_'),
                onWords: (words) => _answer.text = words,
              ),
              TextField(
                controller: _answer, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Распознанный текст'),
              ),
              OutlinedButton(
                onPressed: _saving ? null : () {
                  final spoken = _normalize(_answer.text);
                  if (spoken.isEmpty) {
                    _message('Продиктуйте или введите текст');
                    return;
                  }
                  _advance(practice, spoken == _normalize(poem.lines.join(' ')));
                },
                child: const Text('Проверить и завершить'),
              ),
              ExpansionTile(title: const Text('Сверить с текстом'), children: [Text(poem.lines.join('\n'))]),
              FilledButton(onPressed: _saving ? null : () => _advance(practice, true), child: const Text('Прочитал без ошибок')),
              OutlinedButton(onPressed: _saving ? null : () => _advance(practice, false), child: const Text('Нужно повторить')),
            ],
          ],
        );
      },
    ),
  );
}
