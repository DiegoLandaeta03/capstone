import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class WalkmanPlayerScreen extends StatefulWidget {
  const WalkmanPlayerScreen({
    super.key,
    required this.filePath,
    this.title = 'Mixtape',
    this.artist = 'Unknown',
  });

  final String filePath;
  final String title;
  final String artist;

  @override
  State<WalkmanPlayerScreen> createState() => _WalkmanPlayerScreenState();
}

class _WalkmanPlayerScreenState extends State<WalkmanPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  late final AnimationController _reelController;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _reelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.filePath);
      _duration = _player.duration ?? Duration.zero;

      _player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading audio: $e')),
      );
    }
  }

  @override
  void dispose() {
    _reelController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final durationMs =
        _duration.inMilliseconds <= 0 ? 1.0 : _duration.inMilliseconds.toDouble();
    final positionMs = _position.inMilliseconds
        .clamp(0, _duration.inMilliseconds <= 0 ? 0 : _duration.inMilliseconds)
        .toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: colorScheme.onPrimary,
        title: const Text('Now Playing'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: _WalkmanCard(
                    title: widget.title,
                    artist: widget.artist,
                    controller: _reelController,
                    isPlaying: _isPlaying,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  min: 0.0,
                  max: durationMs,
                  value: positionMs,
                  onChanged: (v) async {
                    final newPos = Duration(milliseconds: v.toInt());
                    await _player.seek(newPos);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(_position),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    _format(_duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    label: _isPlaying ? 'Pause mixtape' : 'Play mixtape',
                    button: true,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(20),
                      ),
                      onPressed: _togglePlayPause,
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalkmanCard extends StatelessWidget {
  const _WalkmanCard({
    required this.title,
    required this.artist,
    required this.controller,
    required this.isPlaying,
  });

  final String title;
  final String artist;
  final AnimationController controller;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF222222),
              Color(0xFF111111),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 12),
            ),
          ],
          border: Border.all(color: Colors.white10, width: 1),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withOpacity(0.6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Reel(controller: controller),
                _TapeStrip(isPlaying: isPlaying),
                _Reel(controller: controller),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MIXD WALKMAN',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white54,
                        letterSpacing: 2,
                      ),
                ),
                Icon(
                  Icons.graphic_eq_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ],
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
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(color: Colors.white30, width: 3),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _TapeStrip extends StatelessWidget {
  const _TapeStrip({required this.isPlaying});

  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: isPlaying ? 80 : 60,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFB3E5FC),
            Color(0xFF7C4DFF),
            Color(0xFFFFC400),
          ],
        ),
      ),
    );
  }
}

