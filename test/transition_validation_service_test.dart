import 'package:flutter_test/flutter_test.dart';
import 'package:mixd/models/mixtape_payload.dart';
import 'package:mixd/services/transition_validation_service.dart';

void main() {
  final service = TransitionValidationService();

  MixtapeClip clip({
    required int position,
    required double len,
    ClipTransition transition = const ClipTransition.hardCut(),
  }) {
    return MixtapeClip(
      position: position,
      songId: '$position',
      title: 't',
      artist: 'a',
      fileKey: 'k$position',
      startSeconds: 0,
      endSeconds: len,
      originalDurationSeconds: len.ceil(),
      trimmedDurationSeconds: len,
      transitionToNext: transition,
    );
  }

  test('defaults last track to hard cut', () {
    final out = service.normalizeClipTransitions([
      clip(position: 0, len: 5),
      clip(
        position: 1,
        len: 6,
        transition: const ClipTransition(
          type: TransitionType.fade,
          fadeInSeconds: 2,
          fadeOutSeconds: 2,
        ),
      ),
    ]);
    expect(out.last.transitionToNext.type, TransitionType.hardCut);
  });

  test('clamps invalid fade values', () {
    final out = service.normalizeClipTransitions([
      clip(
        position: 0,
        len: 2,
        transition: const ClipTransition(
          type: TransitionType.fade,
          fadeOutSeconds: 10,
          fadeInSeconds: 3,
        ),
      ),
      clip(position: 1, len: 1),
    ]);
    expect(out.first.transitionToNext.fadeOutSeconds, 2);
    expect(out.first.transitionToNext.fadeInSeconds, 1);
  });

  test('downgrades invalid crossfade to hard cut', () {
    final out = service.normalizeClipTransitions([
      clip(
        position: 0,
        len: 3,
        transition: const ClipTransition(
          type: TransitionType.crossfade,
          crossfadeSeconds: -1,
        ),
      ),
      clip(position: 1, len: 3),
    ]);
    expect(out.first.transitionToNext.type, TransitionType.hardCut);
  });
}
