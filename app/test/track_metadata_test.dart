import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/track_metadata.dart';

void main() {
  test('CSV preserves quoted titles and removes repeated entries', () {
    final tracks = parseTrackList(
      '\uFEFFartist;title\r\nBand;"Hello; world"\r\nband;"hello; world"\r\n',
      json: false,
    );
    expect(tracks, [(artist: 'Band', title: 'Hello; world')]);
  });

  test('JSON compares artist and title to the local file name', () {
    final tracks = parseTrackList(
      '[{"artist":"Band","title":"Song"},{"artist":"Other","title":"Song"}]',
      json: true,
    );
    final files = {trackFileKey('  BAND - Song ')};
    expect(hasMatchingTrackFile(tracks.first, files), isTrue);
    expect(hasMatchingTrackFile(tracks.last, files), isFalse);
  });

  test('rejects incomplete metadata', () {
    expect(() => parseTrackList('[{"title":"Song"}]', json: true),
        throwsFormatException);
  });
}
