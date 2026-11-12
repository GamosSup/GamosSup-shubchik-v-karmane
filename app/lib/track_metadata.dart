import 'dart:convert';

import 'package:csv/csv.dart';

typedef TrackMetadata = ({String title, String artist});

List<TrackMetadata> parseTrackList(String source, {required bool json}) {
  final input = source.replaceFirst('\uFEFF', '');
  final Object? rows;
  if (json) {
    rows = jsonDecode(input);
  } else {
    final delimiter = input.split('\n').first.contains(';') ? ';' : ',';
    final records = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
      allowInvalid: false,
    ).convert(input.replaceAll('\r\n', '\n'));
    if (records.isEmpty ||
        records.first.map((value) => value.toString().trim().toLowerCase())
                .join(',') != 'artist,title') {
      throw const FormatException('Ожидаются колонки artist и title');
    }
    rows = records.skip(1).where((row) => row.any((cell) => cell != ''))
        .map((row) {
          if (row.length != 2) throw const FormatException('Неверная строка CSV');
          return {'artist': row[0], 'title': row[1]};
        }).toList();
  }
  if (rows is! List || rows.isEmpty || rows.length > 500) {
    throw const FormatException('В списке должно быть от 1 до 500 треков');
  }
  final tracks = <(String, String), TrackMetadata>{};
  for (final row in rows) {
    if (row is! Map || row['artist'] is! String || row['title'] is! String) {
      throw const FormatException('У каждой записи нужны artist и title');
    }
    final artist = (row['artist'] as String).trim();
    final title = (row['title'] as String).trim();
    if (artist.isEmpty || title.isEmpty || artist.length > 160 || title.length > 160) {
      throw const FormatException('Проверьте длину исполнителя и названия');
    }
    tracks.putIfAbsent(
      (artist.toLowerCase(), title.toLowerCase()),
      () => (artist: artist, title: title),
    );
  }
  return tracks.values.toList(growable: false);
}

String trackFileKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool hasMatchingTrackFile(TrackMetadata track, Set<String> fileNames) {
  final artist = trackFileKey(track.artist);
  final title = trackFileKey(track.title);
  return fileNames.contains('$artist - $title') ||
      fileNames.contains('$title - $artist');
}
