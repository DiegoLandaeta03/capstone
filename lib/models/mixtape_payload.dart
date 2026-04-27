class MixtapeTracksPayload {
  const MixtapeTracksPayload({this.version, required this.tracks});

  final int? version;
  final List<MixtapeClip> tracks;

  factory MixtapeTracksPayload.empty() =>
      const MixtapeTracksPayload(version: 2, tracks: <MixtapeClip>[]);

  factory MixtapeTracksPayload.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return MixtapeTracksPayload.empty();
    }

    final rawTracks = raw['tracks'];
    final tracks = <MixtapeClip>[];
    if (rawTracks is List) {
      for (int i = 0; i < rawTracks.length; i++) {
        final parsed = MixtapeClip.fromJson(rawTracks[i], fallbackPosition: i);
        if (parsed != null) tracks.add(parsed.normalized());
      }
    }

    tracks.sort((a, b) => a.position.compareTo(b.position));
    final version = _asInt(raw['version']);
    return MixtapeTracksPayload(version: version, tracks: tracks);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version ?? 2,
      'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
    };
  }
}

class MixtapeClip {
  const MixtapeClip({
    required this.position,
    required this.songId,
    required this.title,
    required this.artist,
    required this.fileKey,
    required this.startSeconds,
    required this.endSeconds,
    required this.originalDurationSeconds,
    required this.trimmedDurationSeconds,
    this.albumArtUrl,
    this.waveform,
    this.transitionToNext = const ClipTransition.hardCut(),
  });

  final int position;
  final String songId;
  final String title;
  final String artist;
  final String? albumArtUrl;
  final String fileKey;
  final double startSeconds;
  final double endSeconds;
  final int originalDurationSeconds;
  final double trimmedDurationSeconds;
  final WaveformDescriptor? waveform;
  final ClipTransition transitionToNext;

  double get effectiveDuration => (endSeconds - startSeconds).clamp(0.0, 1e9);
  bool get isPlayable => fileKey.trim().isNotEmpty && effectiveDuration > 0;

  MixtapeClip copyWith({
    int? position,
    String? songId,
    String? title,
    String? artist,
    String? albumArtUrl,
    String? fileKey,
    double? startSeconds,
    double? endSeconds,
    int? originalDurationSeconds,
    double? trimmedDurationSeconds,
    WaveformDescriptor? waveform,
    ClipTransition? transitionToNext,
  }) {
    return MixtapeClip(
      position: position ?? this.position,
      songId: songId ?? this.songId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      fileKey: fileKey ?? this.fileKey,
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      originalDurationSeconds:
          originalDurationSeconds ?? this.originalDurationSeconds,
      trimmedDurationSeconds:
          trimmedDurationSeconds ?? this.trimmedDurationSeconds,
      waveform: waveform ?? this.waveform,
      transitionToNext: transitionToNext ?? this.transitionToNext,
    );
  }

  MixtapeClip normalized() {
    final safeStart = startSeconds < 0 ? 0.0 : startSeconds;
    final maxEnd = originalDurationSeconds > 0
        ? originalDurationSeconds.toDouble()
        : (safeStart + 1.0);
    var safeEnd = endSeconds;
    if (safeEnd <= safeStart) safeEnd = safeStart + 1.0;
    if (safeEnd > maxEnd) safeEnd = maxEnd;
    final computedTrim = (safeEnd - safeStart).clamp(0.0, maxEnd);
    final safeTrim = trimmedDurationSeconds <= 0
        ? computedTrim
        : (trimmedDurationSeconds - computedTrim).abs() > 0.05
        ? computedTrim
        : trimmedDurationSeconds;

    return copyWith(
      startSeconds: safeStart,
      endSeconds: safeEnd,
      trimmedDurationSeconds: safeTrim,
      transitionToNext: transitionToNext.normalized(),
    );
  }

  factory MixtapeClip.fromEditorSelection(
    Map<String, dynamic> raw, {
    required int position,
  }) {
    final duration =
        _asInt(raw['durationSeconds']) ?? _asInt(raw['duration_seconds']) ?? 30;
    return MixtapeClip(
      position: position,
      songId: (raw['id'] ?? raw['song_id'] ?? '').toString(),
      title: (raw['title'] ?? 'Untitled').toString(),
      artist: (raw['artist'] ?? 'Unknown Artist').toString(),
      albumArtUrl: _asNullableString(
        raw['albumArtUrl'] ?? raw['album_art_url'],
      ),
      fileKey: (raw['fileKey'] ?? raw['file_key'] ?? '').toString(),
      startSeconds: 0.0,
      endSeconds: duration.toDouble(),
      originalDurationSeconds: duration,
      trimmedDurationSeconds: duration.toDouble(),
      waveform: null,
      transitionToNext: const ClipTransition.hardCut(),
    );
  }

  factory MixtapeClip.fromJson(dynamic raw, {required int fallbackPosition}) {
    if (raw is! Map<String, dynamic>) {
      return MixtapeClip(
        position: fallbackPosition,
        songId: '',
        title: 'Untitled',
        artist: 'Unknown Artist',
        fileKey: '',
        startSeconds: 0,
        endSeconds: 1,
        originalDurationSeconds: 1,
        trimmedDurationSeconds: 1,
      );
    }

    final start = _asDouble(raw['start_seconds']) ?? 0.0;
    final end =
        _asDouble(raw['end_seconds']) ??
        (_asDouble(raw['trimmed_duration_seconds']) ?? 1.0) + start;
    final originalDuration =
        _asInt(raw['original_duration_seconds']) ??
        (_asInt(raw['duration_seconds']) ?? 1);

    return MixtapeClip(
      position: _asInt(raw['position']) ?? fallbackPosition,
      songId: (raw['song_id'] ?? raw['songId'] ?? raw['id'] ?? '').toString(),
      title: (raw['title'] ?? 'Untitled').toString(),
      artist: (raw['artist'] ?? 'Unknown Artist').toString(),
      albumArtUrl: _asNullableString(
        raw['album_art_url'] ?? raw['albumArtUrl'],
      ),
      fileKey: (raw['file_key'] ?? raw['fileKey'] ?? '').toString(),
      startSeconds: start,
      endSeconds: end,
      originalDurationSeconds: originalDuration <= 0 ? 1 : originalDuration,
      trimmedDurationSeconds:
          _asDouble(raw['trimmed_duration_seconds']) ?? (end - start),
      waveform: WaveformDescriptor.fromJson(raw['waveform']),
      transitionToNext:
          ClipTransition.fromJson(raw['transition_to_next']) ??
          const ClipTransition.hardCut(),
    );
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'position': position,
      'song_id': songId,
      'title': title,
      'artist': artist,
      'album_art_url': albumArtUrl,
      'file_key': fileKey,
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'original_duration_seconds': originalDurationSeconds,
      'trimmed_duration_seconds': trimmedDurationSeconds,
      'transition_to_next': transitionToNext.toJson(),
    };
    if (waveform != null) out['waveform'] = waveform!.toJson();
    return out;
  }
}

enum TransitionType { hardCut, fade, crossfade }

class ClipTransition {
  const ClipTransition({
    required this.type,
    this.fadeOutSeconds = 0,
    this.fadeInSeconds = 0,
    this.crossfadeSeconds = 0,
  });

  const ClipTransition.hardCut()
    : type = TransitionType.hardCut,
      fadeOutSeconds = 0,
      fadeInSeconds = 0,
      crossfadeSeconds = 0;

  final TransitionType type;
  final double fadeOutSeconds;
  final double fadeInSeconds;
  final double crossfadeSeconds;

  ClipTransition normalized() {
    final out = fadeOutSeconds < 0 ? 0.0 : fadeOutSeconds;
    final input = fadeInSeconds < 0 ? 0.0 : fadeInSeconds;
    final cross = crossfadeSeconds < 0 ? 0.0 : crossfadeSeconds;
    if (type == TransitionType.hardCut) return const ClipTransition.hardCut();
    return ClipTransition(
      type: type,
      fadeOutSeconds: out,
      fadeInSeconds: input,
      crossfadeSeconds: cross,
    );
  }

  factory ClipTransition.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return const ClipTransition.hardCut();
    final typeRaw = (raw['type'] ?? '').toString().trim().toLowerCase();
    final type = switch (typeRaw) {
      'fade' => TransitionType.fade,
      'crossfade' => TransitionType.crossfade,
      'hard_cut' => TransitionType.hardCut,
      'hardcut' => TransitionType.hardCut,
      _ => TransitionType.hardCut,
    };
    return ClipTransition(
      type: type,
      fadeOutSeconds: _asDouble(raw['fade_out_seconds']) ?? 0,
      fadeInSeconds: _asDouble(raw['fade_in_seconds']) ?? 0,
      crossfadeSeconds: _asDouble(raw['crossfade_seconds']) ?? 0,
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': switch (type) {
        TransitionType.hardCut => 'hard_cut',
        TransitionType.fade => 'fade',
        TransitionType.crossfade => 'crossfade',
      },
      'fade_out_seconds': fadeOutSeconds,
      'fade_in_seconds': fadeInSeconds,
      'crossfade_seconds': crossfadeSeconds,
    };
  }
}

class WaveformDescriptor {
  const WaveformDescriptor({
    this.peakCacheKey,
    this.source = 'unknown',
    this.samples,
    this.sampleCount,
    this.sampleResolution,
  });

  final String? peakCacheKey;
  final String source;
  final List<double>? samples;
  final int? sampleCount;
  final int? sampleResolution;

  factory WaveformDescriptor.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const WaveformDescriptor();
    }
    final sampleList = <double>[];
    final rawSamples = raw['samples'];
    if (rawSamples is List) {
      for (final v in rawSamples) {
        final d = _asDouble(v);
        if (d != null) sampleList.add(d.clamp(0.0, 1.0));
      }
    }
    return WaveformDescriptor(
      peakCacheKey: _asNullableString(raw['peak_cache_key']),
      source: (_asNullableString(raw['source']) ?? 'unknown'),
      samples: sampleList.isEmpty ? null : sampleList,
      sampleCount: _asInt(raw['sample_count']),
      sampleResolution: _asInt(raw['sample_resolution']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'peak_cache_key': peakCacheKey,
      'source': source,
      'samples': samples,
      'sample_count': sampleCount,
      'sample_resolution': sampleResolution,
    };
  }
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

String? _asNullableString(dynamic value) {
  final out = value?.toString();
  if (out == null) return null;
  final trimmed = out.trim();
  return trimmed.isEmpty ? null : trimmed;
}
