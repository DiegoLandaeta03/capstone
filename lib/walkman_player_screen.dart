import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'models/mixtape_payload.dart';
import 'services/mixtape_playback_builder.dart';
import 'services/signed_audio_url_service.dart';

class WalkmanMixTrack {
  const WalkmanMixTrack({
    required this.fileKey,
    required this.startSeconds,
    required this.endSeconds,
    this.title,
    this.artist,
    this.coverArtUrl,
    this.transitionToNext = const ClipTransition.hardCut(),
  });

  final String fileKey;
  final double startSeconds;
  final double endSeconds;
  final String? title;
  final String? artist;
  final String? coverArtUrl;
  final ClipTransition transitionToNext;
}

class WalkmanPlayerScreen extends StatefulWidget {
  const WalkmanPlayerScreen({
    super.key,
    this.filePath = '',
    this.title = 'Mixtape',
    this.artist = 'Unknown',
    this.mixTracks,
  });

  /// Accepts either a local file path OR an `http(s)` URL.
  final String filePath;
  final String title;
  final String artist;
  final List<WalkmanMixTrack>? mixTracks;

  @override
  State<WalkmanPlayerScreen> createState() => _WalkmanPlayerScreenState();
}

class _WalkmanPlayerScreenState extends State<WalkmanPlayerScreen>
    with SingleTickerProviderStateMixin {
  final SignedAudioUrlService _signedAudioUrlService = SignedAudioUrlService();
  final MixtapePlaybackBuilder _playbackBuilder = MixtapePlaybackBuilder(
    enableOverlapCrossfade: false,
  );
  late final AudioPlayer _player;
  late final AudioPlayer _previewPlayer;
  late final AnimationController _reelController;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _mixPosition = Duration.zero;
  Duration _mixTotalDuration = Duration.zero;
  List<Duration> _mixTrackDurations = const [];
  int _currentIndexPlaying = 0;
  bool _isPlaying = false;
  int? _previewPlayingIndex;
  MixtapePlaybackPlan? _playbackPlan;
  List<ClipTransition> _appliedTransitions = const [];

  @override
  void initState() {
    super.initState();

    _player = AudioPlayer();
    _previewPlayer = AudioPlayer();
    _reelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    );

    _init();
  }

  bool get _isHttpSource =>
      widget.filePath.startsWith('http://') ||
      widget.filePath.startsWith('https://');

  bool get _isAssetSource => widget.filePath.startsWith('assets/');
  bool get _hasMixTracks =>
      widget.mixTracks != null && widget.mixTracks!.isNotEmpty;

  Duration _mixOffsetUntil(int clipIndex) {
    var sumMs = 0;
    for (int i = 0; i < clipIndex && i < _mixTrackDurations.length; i++) {
      sumMs += _mixTrackDurations[i].inMilliseconds;
    }
    return Duration(milliseconds: sumMs);
  }

  Future<void> _seekInMix(Duration target) async {
    if (_mixTrackDurations.isEmpty) return;

    final totalMs = _mixTotalDuration.inMilliseconds;
    final clampedMs = target.inMilliseconds.clamp(0, totalMs);

    var acc = 0;
    var idx = 0;
    for (; idx < _mixTrackDurations.length; idx++) {
      final len = _mixTrackDurations[idx].inMilliseconds;
      if (clampedMs < acc + len) break;
      acc += len;
    }
    if (idx >= _mixTrackDurations.length) {
      idx = _mixTrackDurations.length - 1;
      acc -= _mixTrackDurations[idx].inMilliseconds;
    }

    final localMs = (clampedMs - acc).clamp(
      0,
      _mixTrackDurations[idx].inMilliseconds,
    );
    await _player.seek(Duration(milliseconds: localMs), index: idx);
  }

  Future<void> _setMixAudioSource() async {
    final tracks = widget.mixTracks ?? const <WalkmanMixTrack>[];
    final clips = <MixtapeClip>[];
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      clips.add(
        MixtapeClip(
          position: i,
          songId: t.fileKey,
          title: (t.title ?? '').trim().isEmpty ? 'Track ${i + 1}' : t.title!,
          artist: t.artist ?? '',
          albumArtUrl: t.coverArtUrl,
          fileKey: t.fileKey,
          startSeconds: t.startSeconds,
          endSeconds: t.endSeconds,
          originalDurationSeconds: (t.endSeconds > 0 ? t.endSeconds.ceil() : 1),
          trimmedDurationSeconds: t.endSeconds - t.startSeconds,
          transitionToNext: t.transitionToNext,
        ),
      );
    }
    final plan = _playbackBuilder.build(clips);
    final sources = <AudioSource>[];
    final trackDurations = <Duration>[];

    final appliedTransitions = <ClipTransition>[];
    for (final clip in plan.clips) {
      final signedUrl = await _signedAudioUrlService.signedSongUrl(
        clip.fileKey,
      );
      if (signedUrl == null) continue;
      final startMs = (clip.startSeconds * 1000)
          .round()
          .clamp(0, 36000000)
          .toInt();
      final endMs = (clip.endSeconds * 1000).round().clamp(0, 36000000).toInt();
      final boundedEndMs = endMs <= startMs ? startMs + 1 : endMs;
      trackDurations.add(Duration(milliseconds: boundedEndMs - startMs));

      sources.add(
        ClippingAudioSource(
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: boundedEndMs),
          child: AudioSource.uri(Uri.parse(signedUrl)),
        ),
      );
      appliedTransitions.add(clip.transitionToNext);
    }

    if (sources.isEmpty) {
      throw Exception('No playable tracks in this mix.');
    }

    _mixTrackDurations = trackDurations;
    _mixTotalDuration = trackDurations.fold(Duration.zero, (sum, d) => sum + d);

    await _player.setAudioSource(ConcatenatingAudioSource(children: sources));
    _playbackPlan = plan;
    _appliedTransitions = appliedTransitions;
  }

  Future<String> _signedUrlForFileKey(String fileKey) async {
    return (await _signedAudioUrlService.signedSongUrl(fileKey)) ?? '';
  }

  Future<void> _init() async {
    try {
      if (_hasMixTracks) {
        await _setMixAudioSource();
      } else if (_isAssetSource) {
        await _player.setAsset(widget.filePath);
      } else if (_isHttpSource) {
        await _player.setUrl(widget.filePath);
      } else {
        await _player.setFilePath(widget.filePath);
      }

      _duration = _player.duration ?? Duration.zero;

      _player.positionStream.listen((pos) {
        if (!mounted) return;
        _applyFadeVolumeForPosition(pos);
        if (_hasMixTracks) {
          final localMs = pos.inMilliseconds;
          final offsetMs = _mixOffsetUntil(_currentIndexPlaying).inMilliseconds;
          final totalMs = _mixTotalDuration.inMilliseconds;
          final mixMs = (offsetMs + localMs).clamp(0, totalMs);
          setState(() {
            _position = pos;
            _mixPosition = Duration(milliseconds: mixMs);
          });
        } else {
          setState(() => _position = pos);
        }
      });

      _player.currentIndexStream.listen((idx) {
        if (!mounted || idx == null) return;
        setState(() {
          _currentIndexPlaying = idx;
        });
      });

      _player.durationStream.listen((d) {
        if (!mounted || _hasMixTracks) return;
        setState(() {
          _duration = d ?? Duration.zero;
        });
      });

      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        final playing = state.playing;
        setState(() => _isPlaying = playing);

        if (playing) {
          _reelController.repeat();
        } else {
          _reelController.stop();
        }
      });

      _previewPlayer.playerStateStream.listen((state) {
        if (!mounted) return;
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _previewPlayingIndex = null;
          });
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading audio: $e')));
    }
  }

  void _applyFadeVolumeForPosition(Duration pos) {
    if (_currentIndexPlaying < 0 ||
        _currentIndexPlaying >= _appliedTransitions.length) {
      _player.setVolume(1.0);
      return;
    }
    final transition = _appliedTransitions[_currentIndexPlaying];
    if (transition.type != TransitionType.fade) {
      _player.setVolume(1.0);
      return;
    }

    final currentTrackLen = (_currentIndexPlaying < _mixTrackDurations.length)
        ? _mixTrackDurations[_currentIndexPlaying].inMilliseconds / 1000.0
        : 0.0;
    if (currentTrackLen <= 0) {
      _player.setVolume(1.0);
      return;
    }
    final localSec = pos.inMilliseconds / 1000.0;

    var volume = 1.0;
    final fadeOut = transition.fadeOutSeconds;
    if (fadeOut > 0) {
      final fadeOutStart = (currentTrackLen - fadeOut).clamp(
        0.0,
        currentTrackLen,
      );
      if (localSec >= fadeOutStart) {
        final t = ((localSec - fadeOutStart) / fadeOut).clamp(0.0, 1.0);
        volume = 1.0 - t;
      }
    }
    final fadeIn = transition.fadeInSeconds;
    if (fadeIn > 0 && localSec <= fadeIn) {
      final t = (localSec / fadeIn).clamp(0.0, 1.0);
      volume = volume < t ? volume : t;
    }
    _player.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _reelController.dispose();
    _previewPlayer.dispose();
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _playTrackPreview(int index) async {
    final tracks = widget.mixTracks ?? const <WalkmanMixTrack>[];
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];

    if (_previewPlayingIndex == index) {
      if (_previewPlayer.playing) {
        await _previewPlayer.pause();
      } else {
        await _previewPlayer.play();
      }
      if (!mounted) return;
      setState(() {});
      return;
    }

    try {
      await _previewPlayer.stop();
      if (!mounted) return;
      setState(() {
        _previewPlayingIndex = index;
      });

      final signedUrl = await _signedUrlForFileKey(track.fileKey);
      if (signedUrl.isEmpty) throw Exception('Missing signed URL');
      await _previewPlayer.setAudioSource(
        ClippingAudioSource(
          start: Duration.zero,
          end: const Duration(seconds: 30),
          child: AudioSource.uri(Uri.parse(signedUrl)),
        ),
      );
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewPlayingIndex = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not play preview.')));
    }
  }

  Future<void> _openTrackListSheet() async {
    final tracks = widget.mixTracks ?? const <WalkmanMixTrack>[];
    if (tracks.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121B35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Tracklist',
                      style: Theme.of(sheetContext).textTheme.titleMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${tracks.length} tracks',
                      style: Theme.of(
                        sheetContext,
                      ).textTheme.labelMedium?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final t = tracks[index];
                      final localTitle = (t.title ?? '').trim().isEmpty
                          ? 'Track ${index + 1}'
                          : t.title!.trim();
                      final localArtist = (t.artist ?? '').trim();
                      final rangeText =
                          '${_format(Duration(milliseconds: (t.startSeconds * 1000).round()))} - ${_format(Duration(milliseconds: (t.endSeconds * 1000).round()))}';

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child:
                                t.coverArtUrl != null &&
                                    t.coverArtUrl!.isNotEmpty
                                ? Image.network(
                                    t.coverArtUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.blueAccent.withValues(
                                      alpha: 0.2,
                                    ),
                                    child: const Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(
                          localTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          localArtist.isEmpty
                              ? rangeText
                              : '$localArtist · $rangeText',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: StreamBuilder<PlayerState>(
                          stream: _previewPlayer.playerStateStream,
                          builder: (context, snapshot) {
                            final isPreviewPlaying =
                                _previewPlayingIndex == index &&
                                (snapshot.data?.playing ??
                                    _previewPlayer.playing);
                            return IconButton(
                              icon: Icon(
                                isPreviewPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () async {
                                await _playTrackPreview(index);
                              },
                            );
                          },
                        ),
                        onTap: () async {
                          await _seekInMix(_mixOffsetUntil(index));
                          if (!sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveDuration = _hasMixTracks ? _mixTotalDuration : _duration;
    final effectivePosition = _hasMixTracks ? _mixPosition : _position;
    final durationMs = effectiveDuration.inMilliseconds <= 0
        ? 1.0
        : effectiveDuration.inMilliseconds.toDouble();
    final positionMs = effectivePosition.inMilliseconds
        .clamp(
          0,
          effectiveDuration.inMilliseconds <= 0
              ? 0
              : effectiveDuration.inMilliseconds,
        )
        .toDouble();

    final playButton = Semantics(
      label: _isPlaying ? 'Pause mixtape' : 'Play mixtape',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _togglePlayPause,
          customBorder: const CircleBorder(),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF3A7BFF),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3A7BFF).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Now Playing',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _FullScreenCassette(
                  title: widget.title,
                  artist: widget.artist,
                  controller: _reelController,
                  centerChild: playButton,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _hasMixTracks
                                ? 'Track ${_currentIndexPlaying + 1} of ${(widget.mixTracks ?? const []).length}'
                                : widget.artist,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        if (_hasMixTracks)
                          TextButton.icon(
                            onPressed: _openTrackListSheet,
                            icon: const Icon(
                              Icons.format_list_bulleted_rounded,
                              size: 18,
                              color: Colors.blueAccent,
                            ),
                            label: const Text(
                              'Tracklist',
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                          ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        activeTrackColor: colorScheme.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: colorScheme.primary,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: durationMs,
                        value: positionMs,
                        onChanged: (v) async {
                          final newPos = Duration(milliseconds: v.toInt());
                          if (_hasMixTracks) {
                            await _seekInMix(newPos);
                          } else {
                            await _player.seek(newPos);
                          }
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _format(effectivePosition),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          _format(effectiveDuration),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenCassette extends StatelessWidget {
  const _FullScreenCassette({
    required this.title,
    required this.artist,
    required this.controller,
    required this.centerChild,
  });

  final String title;
  final String artist;
  final AnimationController controller;
  final Widget centerChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E2B4A), Color(0xFF18223D), Color(0xFF121A31)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 16,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.withValues(alpha: 0.35),
                      Colors.blueAccent.withValues(alpha: 0.12),
                      Colors.blueAccent.withValues(alpha: 0.35),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Row(
                  children: const [
                    SizedBox(width: 14),
                    Expanded(
                      child: Divider(color: Colors.white24, thickness: 0.8),
                    ),
                    SizedBox(width: 10),
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Divider(color: Colors.white24, thickness: 0.8),
                    ),
                    SizedBox(width: 14),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(child: _Reel(controller: controller)),
                    ),
                    centerChild,
                    Expanded(
                      child: Center(child: _Reel(controller: controller)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reel extends StatelessWidget {
  const _Reel({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: Tween<double>(begin: 0, end: 1).animate(controller),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0F172A),
          border: Border.all(color: Colors.white54, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 4; i++)
              Transform.rotate(
                angle: i * (math.pi / 2),
                child: Container(width: 32, height: 3, color: Colors.white30),
              ),
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
