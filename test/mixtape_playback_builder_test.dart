import 'package:flutter_test/flutter_test.dart';
import 'package:mixd/models/mixtape_payload.dart';
import 'package:mixd/services/mixtape_playback_builder.dart';

void main() {
  MixtapeClip clip({
    required int position,
    required double start,
    required double end,
    ClipTransition transition = const ClipTransition.hardCut(),
  }) {
    return MixtapeClip(
      position: position,
      songId: '$position',
      title: 'Song $position',
      artist: 'Artist',
      fileKey: 'k$position',
      startSeconds: start,
      endSeconds: end,
      originalDurationSeconds: end.ceil(),
      trimmedDurationSeconds: end - start,
      transitionToNext: transition,
    );
  }

  test('hard cut total duration is sum of clip durations', () {
    final builder = MixtapePlaybackBuilder(enableOverlapCrossfade: false);
    final plan = builder.build([
      clip(position: 0, start: 0, end: 10),
      clip(position: 1, start: 0, end: 5),
    ]);
    expect(plan.totalDurationSeconds, 15);
    final mapped = plan.mapGlobalToClip(12);
    expect(mapped.index, 1);
    expect(mapped.localSeconds, 2);
  });

  test('crossfade overlap reduces total duration when enabled', () {
    final builder = MixtapePlaybackBuilder(enableOverlapCrossfade: true);
    final plan = builder.build([
      clip(
        position: 0,
        start: 0,
        end: 10,
        transition: const ClipTransition(
          type: TransitionType.crossfade,
          crossfadeSeconds: 2,
        ),
      ),
      clip(position: 1, start: 0, end: 5),
    ]);
    expect(plan.totalDurationSeconds, 13);
  });
}
