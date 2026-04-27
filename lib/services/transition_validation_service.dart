import '../models/mixtape_payload.dart';

class TransitionValidationService {
  const TransitionValidationService();

  List<MixtapeClip> normalizeClipTransitions(List<MixtapeClip> clips) {
    if (clips.isEmpty) return const [];
    final out = <MixtapeClip>[];
    for (int i = 0; i < clips.length; i++) {
      final current = clips[i].normalized();
      if (i == clips.length - 1) {
        out.add(
          current.copyWith(transitionToNext: const ClipTransition.hardCut()),
        );
        continue;
      }
      final next = clips[i + 1].normalized();
      out.add(
        current.copyWith(
          transitionToNext: _normalizeTransitionBetween(
            transition: current.transitionToNext,
            currentClip: current,
            nextClip: next,
          ),
        ),
      );
    }
    return out;
  }

  ClipTransition _normalizeTransitionBetween({
    required ClipTransition transition,
    required MixtapeClip currentClip,
    required MixtapeClip nextClip,
  }) {
    final currentLen = currentClip.effectiveDuration;
    final nextLen = nextClip.effectiveDuration;
    if (currentLen <= 0 || nextLen <= 0) {
      return const ClipTransition.hardCut();
    }

    switch (transition.type) {
      case TransitionType.hardCut:
        return const ClipTransition.hardCut();
      case TransitionType.fade:
        final fadeOut = transition.fadeOutSeconds.clamp(0.0, currentLen);
        final fadeIn = transition.fadeInSeconds.clamp(0.0, nextLen);
        if (fadeOut <= 0 && fadeIn <= 0) return const ClipTransition.hardCut();
        return ClipTransition(
          type: TransitionType.fade,
          fadeOutSeconds: fadeOut,
          fadeInSeconds: fadeIn,
          crossfadeSeconds: 0,
        );
      case TransitionType.crossfade:
        final maxCross = currentLen < nextLen ? currentLen : nextLen;
        final safeCross = transition.crossfadeSeconds.clamp(0.0, maxCross);
        if (safeCross <= 0) return const ClipTransition.hardCut();
        return ClipTransition(
          type: TransitionType.crossfade,
          crossfadeSeconds: safeCross,
          fadeOutSeconds: 0,
          fadeInSeconds: 0,
        );
    }
  }
}
