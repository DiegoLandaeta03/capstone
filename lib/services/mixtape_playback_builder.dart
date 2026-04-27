import '../models/mixtape_payload.dart';
import 'transition_validation_service.dart';

class PlaybackSegment {
  const PlaybackSegment({
    required this.index,
    required this.clip,
    required this.startsAtSeconds,
    required this.durationSeconds,
  });

  final int index;
  final MixtapeClip clip;
  final double startsAtSeconds;
  final double durationSeconds;
}

class MixtapePlaybackPlan {
  const MixtapePlaybackPlan({
    required this.clips,
    required this.segments,
    required this.totalDurationSeconds,
  });

  final List<MixtapeClip> clips;
  final List<PlaybackSegment> segments;
  final double totalDurationSeconds;

  ({int index, double localSeconds}) mapGlobalToClip(double seconds) {
    if (segments.isEmpty) return (index: 0, localSeconds: 0.0);
    final target = seconds.clamp(0.0, totalDurationSeconds);
    for (final segment in segments) {
      final end = segment.startsAtSeconds + segment.durationSeconds;
      if (target < end) {
        return (
          index: segment.index,
          localSeconds: target - segment.startsAtSeconds,
        );
      }
    }
    final last = segments.last;
    return (index: last.index, localSeconds: last.durationSeconds);
  }

  double mapClipToGlobal({
    required int clipIndex,
    required double localSeconds,
  }) {
    if (segments.isEmpty) return 0.0;
    final idx = clipIndex.clamp(0, segments.length - 1);
    final seg = segments[idx];
    final boundedLocal = localSeconds.clamp(0.0, seg.durationSeconds);
    return (seg.startsAtSeconds + boundedLocal).clamp(
      0.0,
      totalDurationSeconds,
    );
  }
}

class MixtapePlaybackBuilder {
  MixtapePlaybackBuilder({
    TransitionValidationService? transitionValidationService,
    this.enableOverlapCrossfade = false,
  }) : _transitionValidationService =
           transitionValidationService ?? const TransitionValidationService();

  final TransitionValidationService _transitionValidationService;
  final bool enableOverlapCrossfade;

  MixtapePlaybackPlan build(List<MixtapeClip> rawClips) {
    final filtered = rawClips
        .where((c) => c.isPlayable)
        .toList(growable: false);
    final clips = _transitionValidationService.normalizeClipTransitions(
      filtered,
    );

    final segments = <PlaybackSegment>[];
    var cursor = 0.0;
    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final duration = clip.effectiveDuration;
      segments.add(
        PlaybackSegment(
          index: i,
          clip: clip,
          startsAtSeconds: cursor,
          durationSeconds: duration,
        ),
      );

      double overlap = 0.0;
      if (enableOverlapCrossfade &&
          clip.transitionToNext.type == TransitionType.crossfade &&
          i < clips.length - 1) {
        overlap = clip.transitionToNext.crossfadeSeconds.clamp(0.0, duration);
      }
      cursor += (duration - overlap).clamp(0.0, duration);
    }

    return MixtapePlaybackPlan(
      clips: clips,
      segments: segments,
      totalDurationSeconds: cursor,
    );
  }
}
