import 'package:flutter_test/flutter_test.dart';
import 'package:mixd/models/mixtape_payload.dart';

void main() {
  test('parses legacy payload and defaults transition', () {
    final payload = MixtapeTracksPayload.fromJson({
      'tracks': [
        {
          'position': 0,
          'song_id': 'a',
          'title': 'Song',
          'artist': 'Artist',
          'file_key': 'fk',
          'start_seconds': 2,
          'end_seconds': 5,
          'original_duration_seconds': 120,
        },
      ],
    });

    expect(payload.tracks.length, 1);
    expect(payload.tracks.first.transitionToNext.type, TransitionType.hardCut);
    expect(payload.tracks.first.trimmedDurationSeconds, 3);
  });

  test('parses new payload and ignores malformed fields safely', () {
    final payload = MixtapeTracksPayload.fromJson({
      'version': 2,
      'tracks': [
        {
          'position': 0,
          'song_id': 'b',
          'title': 'Song',
          'artist': 'Artist',
          'file_key': 'fk',
          'start_seconds': -10,
          'end_seconds': 1,
          'original_duration_seconds': 180,
          'transition_to_next': {
            'type': 'crossfade',
            'crossfade_seconds': 'bad',
          },
          'waveform': {
            'source': 'precomputed',
            'samples': [0.1, 0.3, 'x', 2.0],
          },
        },
      ],
    });

    expect(payload.version, 2);
    expect(payload.tracks.first.startSeconds, 0);
    expect(payload.tracks.first.endSeconds, 1);
    expect(payload.tracks.first.waveform?.samples?.length, 3);
  });

  test('payload toJson roundtrip keeps track count', () {
    final original = MixtapeTracksPayload.fromJson({
      'tracks': [
        {
          'position': 0,
          'song_id': '1',
          'title': 'S1',
          'artist': 'A1',
          'file_key': 'k1',
          'start_seconds': 0,
          'end_seconds': 10,
          'original_duration_seconds': 100,
        },
        {
          'position': 1,
          'song_id': '2',
          'title': 'S2',
          'artist': 'A2',
          'file_key': 'k2',
          'start_seconds': 0,
          'end_seconds': 8,
          'original_duration_seconds': 90,
        },
      ],
    });

    final reparsed = MixtapeTracksPayload.fromJson(original.toJson());
    expect(reparsed.tracks.length, 2);
  });
}
