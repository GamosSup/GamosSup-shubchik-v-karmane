import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _player = AudioPlayer();
  late final Future<Database> _library = openDatabase(
    'shubchik_music.db',
    version: 1,
    onCreate: (db, _) => db.execute(
      'CREATE TABLE tracks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, '
      'file_path TEXT NOT NULL UNIQUE, played_at INTEGER)',
    ),
  );
  late Future<List<Map<String, Object?>>> _tracks;
  Timer? _sleep;
  String? _title;
  bool _busy = false;
  bool _recent = false;

  @override
  void initState() {
    super.initState();
    _tracks = _load();
  }

  Future<List<Map<String, Object?>>> _load() async =>
      (await _library).query('tracks', orderBy: _recent ? 'played_at DESC, id DESC' : 'id DESC');

  @override
  void dispose() {
    _sleep?.cancel();
    unawaited(_player.dispose());
    unawaited(_closeLibrary());
    super.dispose();
  }

  Future<void> _closeLibrary() async {
    try {
      await (await _library).close();
    } catch (_) {
      // The open error is displayed by the library list.
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _message('Операция не выполнена. Проверьте файл или подключение.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (!mounted || result == null) return;
    final selected = result.files.single;
    final source = selected.path;
    if (source == null || selected.size == 0 || selected.size > 100 * 1024 * 1024) {
      _message('Выберите аудиофайл размером до 100 МБ');
      return;
    }
    final db = await _library;
    final folder = await Directory('${await getDatabasesPath()}/music').create(recursive: true);
    final extension = selected.extension ?? '';
    final safeExtension = RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension) ? '.$extension' : '';
    final path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}$safeExtension';
    final saved = File(path);
    try {
      await File(source).copy(path);
      await db.insert('tracks', {'title': selected.name, 'file_path': path});
    } catch (_) {
      if (await saved.exists()) await saved.delete();
      rethrow;
    }
    if (mounted) setState(() => _tracks = _load());
  }

  Future<void> _start(Map<String, Object?> track) async {
    await _player.stop();
    if (mounted) setState(() => _title = null);
    await _player.setFilePath(track['file_path'] as String);
    if (!mounted) return;
    setState(() => _title = track['title'] as String);
    unawaited(_play());
    await (await _library).update('tracks', {
      'played_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [track['id']]);
    if (mounted && _recent) setState(() => _tracks = _load());
  }

  Future<void> _play() async {
    try {
      if (_player.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      if (mounted) _message('Не удалось воспроизвести аудио');
    }
  }

  void _setSleep(int minutes) {
    _sleep?.cancel();
    _sleep = minutes == 0 ? null : Timer(Duration(minutes: minutes), () {
      if (mounted) unawaited(_perform(_player.pause));
    });
    _message(minutes == 0 ? 'Таймер отключён' : 'Пауза через $minutes мин');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Музыка')),
    body: FutureBuilder(
      future: _tracks,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_title ?? 'Выберите аудиофайл', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing == true &&
                  snapshot.data?.processingState != ProcessingState.completed;
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: playing ? 'Пауза' : 'Воспроизвести',
                    onPressed: _title == null || _busy ? null : () {
                      if (playing) {
                        unawaited(_perform(_player.pause));
                      } else {
                        unawaited(_play());
                      }
                    },
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Таймер сна',
                    icon: const Icon(Icons.timer_outlined),
                    onSelected: _setSleep,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 15, child: Text('15 минут')),
                      PopupMenuItem(value: 30, child: Text('30 минут')),
                      PopupMenuItem(value: 0, child: Text('Отключить таймер')),
                    ],
                  ),
                ],
              );
            },
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _perform(_import),
            icon: const Icon(Icons.add),
            label: const Text('Добавить аудиофайл'),
          ),
          SwitchListTile(
            title: const Text('Недавно прослушанные'),
            value: _recent,
            onChanged: (value) => setState(() {
              _recent = value;
              _tracks = _load();
            }),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (snapshot.hasError) const Text('Не удалось открыть локальную библиотеку'),
          for (final track in snapshot.data ?? <Map<String, Object?>>[])
            if (!_recent || track['played_at'] != null)
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(track['title'] as String),
                onTap: _busy ? null : () => _perform(() => _start(track)),
              ),
          const Divider(),
          const ListTile(title: Text('Открыть музыкальный сервис')),
          for (final service in const {
            'Spotify': 'https://open.spotify.com/',
            'YouTube Music': 'https://music.youtube.com/',
            'Apple Music': 'https://music.apple.com/',
            'Яндекс Музыка': 'https://music.yandex.ru/',
          }.entries)
            ListTile(
              title: Text(service.key),
              trailing: const Icon(Icons.open_in_new),
              onTap: _busy ? null : () => _perform(() async {
                final opened = await launchUrl(Uri.parse(service.value), mode: LaunchMode.externalApplication);
                if (!opened && mounted) _message('Не удалось открыть сервис');
              }),
            ),
        ],
      ),
    ),
  );
}
