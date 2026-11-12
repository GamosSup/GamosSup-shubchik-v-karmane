import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  static final _equalizer = AndroidEqualizer();
  static final _player = _createPlayer();
  static Timer? _sleep;

  static AudioPlayer _createPlayer() {
    final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]));
    player.sequenceStateStream.map((state) => state.currentSource?.tag).distinct().listen((tag) async {
      if (tag is! MediaItem) return;
      try {
        await (await _library).update('tracks', {
          'played_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = ?', whereArgs: [tag.id]);
      } catch (_) {
        // A playback history failure must not stop the current track.
      }
    });
    return player;
  }
  static final Future<Database> _library = openDatabase(
    'shubchik_music.db',
    version: 2,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onUpgrade: (db, old, _) async { if (old < 2) await _createPlaylists(db); },
    onCreate: (db, _) async {
      await db.execute(
      'CREATE TABLE tracks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, '
      'file_path TEXT NOT NULL UNIQUE, played_at INTEGER)',
      );
      await _createPlaylists(db);
    },
  );

  static Future<void> _createPlaylists(Database db) async {
    await db.execute('CREATE TABLE playlists (id INTEGER PRIMARY KEY, title TEXT NOT NULL UNIQUE)');
    await db.execute("""
      CREATE TABLE playlist_tracks (
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        PRIMARY KEY (playlist_id, track_id)
      )
    """);
  }
  late Future<List<Map<String, Object?>>> _tracks;
  bool _busy = false;
  bool _recent = false;
  String _query = '';

  final _recordings = <String, List<Map<String, dynamic>>>{};
  static DateTime? _lastLookup;

  Future<void> _searchMusicBrainz() async {
    final query = _query;
    var recordings = _recordings[query];
    if (recordings == null) {
      final lastLookup = _lastLookup;
      if (lastLookup != null &&
          DateTime.now().difference(lastLookup) < const Duration(seconds: 1)) {
        _message('Повторите поиск через секунду');
        return;
      }
      _lastLookup = DateTime.now();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final url = Uri.https('musicbrainz.org', '/ws/2/recording', {
          'query': query, 'fmt': 'json', 'limit': '8',
        });
        final request = await client.getUrl(url);
        request.headers.set(HttpHeaders.userAgentHeader,
            'Shubchik/0.17 (https://github.com/GamosSup/GamosSup-shubchik-v-karmane)');
        final response = await request.close().timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          if (mounted) _message('MusicBrainz временно недоступен');
          return;
        }
        final data = jsonDecode(await response.transform(utf8.decoder).join()
            .timeout(const Duration(seconds: 10))) as Map<String, dynamic>;
        recordings = (data['recordings'] as List).cast<Map<String, dynamic>>();
        if (_recordings.length >= 32) _recordings.remove(_recordings.keys.first);
        _recordings[query] = recordings;
      } finally {
        client.close(force: true);
      }
    }
    if (!mounted) return;
    final results = recordings;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Записи в MusicBrainz'),
        content: results.isEmpty
            ? const Text('Записи не найдены')
            : SizedBox(
                width: 360,
                child: ListView(shrinkWrap: true, children: [
                  for (final recording in results)
                    ListTile(
                      title: Text(recording['title'] as String),
                      subtitle: Text((recording['artist-credit'] as List? ?? [])
                          .map((credit) => credit['name']).join(', ')),
                      onTap: () => launchUrl(
                        Uri.https('musicbrainz.org', '/recording/${recording['id']}'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                ]),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _searchYandex() async {
    final uri = Uri.https('music.yandex.ru', '/search', {'text': _query});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _message('Не удалось открыть Яндекс Музыку');
  }
  bool _recommended = false;
  int? _playlist;
  late Future<List<Map<String, Object?>>> _playlists;

  @override
  void initState() {
    super.initState();
    _tracks = _load();
    _playlists = _loadPlaylists();
  }

  Future<List<Map<String, Object?>>> _load() async {
    final db = await _library;
    final playlist = _playlist;
    if (playlist != null) {
      return db.rawQuery('''
        SELECT tracks.* FROM tracks JOIN playlist_tracks ON track_id = tracks.id
        WHERE playlist_id = ? ORDER BY playlist_tracks.rowid
      ''', [playlist]);
    }
    return db.query('tracks',
      where: _recent ? 'played_at IS NOT NULL' : null,
      orderBy: _recent ? 'played_at DESC' : _recommended ? 'played_at ASC, id DESC' : 'id DESC',
    );
  }

  Future<List<Map<String, Object?>>> _loadPlaylists() async =>
      (await _library).query('playlists', orderBy: 'title');

  Future<void> _newPlaylist() async {
    var title = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          autofocus: true, maxLength: 80,
          onChanged: (value) => title = value.trim(),
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (title.isNotEmpty) Navigator.pop(context, title);
          }, child: const Text('Создать')),
        ],
      ),
    );
    if (!mounted || name == null) return;
    await (await _library).insert('playlists', {'title': name});
    if (mounted) setState(() => _playlists = _loadPlaylists());
  }

  Future<void> _addToPlaylist(int trackId) async {
    final playlists = await _loadPlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      _message('Сначала создайте плейлист');
      return;
    }
    final id = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Добавить в плейлист'),
        children: [
          for (final playlist in playlists) SimpleDialogOption(
            onPressed: () => Navigator.pop(context, playlist['id'] as int),
            child: Text(playlist['title'] as String),
          ),
        ],
      ),
    );
    if (!mounted || id == null) return;
    await (await _library).insert('playlist_tracks', {
      'playlist_id': id, 'track_id': trackId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (mounted) setState(() => _tracks = _load());
  }

  Future<void> _removeFromPlaylist(int trackId) async {
    final playlist = _playlist;
    if (playlist == null) return;
    await (await _library).delete('playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?', whereArgs: [playlist, trackId]);
    if (mounted) setState(() => _tracks = _load());
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

  Future<void> _start(List<Map<String, Object?>> tracks, int index) async {
    await _player.stop();
    await _player.setAudioSources([
      for (final track in tracks) AudioSource.uri(
        Uri.file(track['file_path'] as String),
        tag: MediaItem(id: track['id'].toString(), title: track['title'] as String),
      ),
    ], initialIndex: index);
    unawaited(_play());
  }

  Future<void> _play() async {
    try {
      if (_player.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      if (mounted) _message('Не удалось воспроизвести аудио');
    }
  }

  Future<void> _pauseForTimer() async {
    try {
      await _player.pause();
    } catch (_) {
      if (mounted) _message('Не удалось поставить музыку на паузу');
    }
  }

  Future<void> _remove(Map<String, Object?> track) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аудиофайл из приложения?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await _player.stop();
    await _player.clearAudioSources();
    final file = File(track['file_path'] as String);
    if (await file.exists()) await file.delete();
    await (await _library).delete('tracks', where: 'id = ?', whereArgs: [track['id']]);
    if (mounted) setState(() => _tracks = _load());
  }

  void _setSleep(int minutes) {
    _sleep?.cancel();
    _sleep = minutes == 0 ? null : Timer(Duration(minutes: minutes), () {
      unawaited(_pauseForTimer());
    });
    _message(minutes == 0 ? 'Таймер отключён' : 'Пауза через $minutes мин');
  }

  Future<void> _showEqualizer() async {
    await _equalizer.setEnabled(true);
    final parameters = await _equalizer.parameters;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Эквалайзер', style: Theme.of(context).textTheme.titleLarge),
              for (final band in parameters.bands) StreamBuilder<double>(
                stream: band.gainStream,
                initialData: band.gain,
                builder: (context, snapshot) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${band.centerFrequency.round()} Гц'),
                    Slider(
                      min: parameters.minDecibels, max: parameters.maxDecibels,
                      value: (snapshot.data ?? 0).clamp(parameters.minDecibels, parameters.maxDecibels).toDouble(),
                      onChanged: (gain) => unawaited(_setGain(band, gain)),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await _equalizer.setEnabled(false);
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (mounted) _message('Эквалайзер недоступен');
                  }
                },
                child: const Text('Отключить эквалайзер'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setGain(AndroidEqualizerBand band, double gain) async {
    try {
      await band.setGain(gain);
    } catch (_) {
      if (mounted) _message('Настройка частоты недоступна');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Музыка')),
    body: FutureBuilder(
      future: _tracks,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder(
            stream: _player.sequenceStateStream,
            builder: (context, state) {
              final tag = state.data?.currentSource?.tag;
              return Text(tag is MediaItem ? tag.title : 'Выберите аудиофайл',
                style: Theme.of(context).textTheme.titleLarge);
            },
          ),
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
                    onPressed: _player.sequence.isEmpty || _busy ? null : () {
                      if (playing) {
                        unawaited(_perform(_player.pause));
                      } else {
                        unawaited(_play());
                      }
                    },
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: 'Следующая запись', icon: const Icon(Icons.skip_next),
                    onPressed: _busy || !_player.hasNext ? null : () => _perform(_player.seekToNext),
                  ),
                  IconButton(
                    tooltip: 'Эквалайзер', icon: const Icon(Icons.equalizer),
                    onPressed: _busy || _player.sequence.isEmpty ? null : () => _perform(_showEqualizer),
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
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _perform(_newPlaylist),
            icon: const Icon(Icons.playlist_add), label: const Text('Создать плейлист'),
          ),
          FutureBuilder(
            future: _playlists,
            builder: (context, state) => DropdownButton<int>(
              value: _playlist,
              hint: const Text('Локальная библиотека'),
              isExpanded: true,
              onChanged: _busy ? null : (value) => setState(() {
                _playlist = value;
                _recent = false;
                _recommended = false;
                _tracks = _load();
              }),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('Локальная библиотека')),
                for (final row in state.data ?? <Map<String, Object?>>[])
                  DropdownMenuItem(value: row['id'] as int, child: Text(row['title'] as String)),
              ],
            ),
          ),
          if (_playlist == null)
            Wrap(spacing: 8, children: [
              FilterChip(
                label: const Text('Недавние'), selected: _recent,
                onSelected: (value) => setState(() {
                  _recent = value; _recommended = false; _tracks = _load();
                }),
              ),
              FilterChip(
                label: const Text('Рекомендации'), selected: _recommended,
                onSelected: (value) => setState(() {
                  _recommended = value; _recent = false; _tracks = _load();
                }),
              ),
            ]),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Поиск в музыке',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          if (_query.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _perform(_searchYandex),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Искать в Яндекс Музыке'),
            ),
          if (_query.isNotEmpty)
            OutlinedButton(
              onPressed: _busy ? null : () => _perform(_searchMusicBrainz),
              child: const Text('Найти запись в MusicBrainz'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (snapshot.hasError) const Text('Не удалось открыть локальную библиотеку'),
          if (snapshot.hasData)
            for (final (index, track) in snapshot.data!.indexed)
              if ((track['title'] as String).toLowerCase().contains(_query.toLowerCase()))
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(track['title'] as String),
                onTap: _busy ? null : () => _perform(() => _start(snapshot.data!, index)),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия с аудио',
                  enabled: !_busy,
                  onSelected: (action) {
                    final id = track['id'] as int;
                    if (action == 'add') unawaited(_perform(() => _addToPlaylist(id)));
                    if (action == 'unlink') unawaited(_perform(() => _removeFromPlaylist(id)));
                    if (action == 'delete') unawaited(_perform(() => _remove(track)));
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'add', child: Text('Добавить в плейлист')),
                    if (_playlist != null)
                      const PopupMenuItem(value: 'unlink', child: Text('Убрать из плейлиста')),
                    const PopupMenuItem(value: 'delete', child: Text('Удалить из приложения')),
                  ],
                ),
              ),
          if (_query.isNotEmpty &&
              snapshot.hasData &&
              !snapshot.data!.any((track) =>
                  (track['title'] as String).toLowerCase().contains(_query.toLowerCase())))
            const ListTile(title: Text('Ничего не найдено')),
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
