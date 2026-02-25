import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final AnimationController _reelController;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    // Lock this screen to landscape so it feels like holding a walkman.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _player = AudioPlayer();
    _reelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), // fast enough to clearly spin
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
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
              color: colorScheme.primary.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 48,
              color: colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFE8E0C8),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _FullScreenCassette(
                title: widget.title,
                controller: _reelController,
                isPlaying: _isPlaying,
                centerChild: playButton,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF263238),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
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
                        await _player.seek(newPos);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _format(_position),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        _format(_duration),
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
    );
  }
}

/// Full-screen cassette: the phone becomes the walkman. No wobble; reels spin only.
class _FullScreenCassette extends StatelessWidget {
  const _FullScreenCassette({
    required this.title,
    required this.controller,
    required this.isPlaying,
    required this.centerChild,
  });

  final String title;
  final AnimationController controller;
  final bool isPlaying;
  final Widget centerChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE8D5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A4A4A), width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          children: [
            // Top: Mixtape label using title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.black12, width: 1),
                ),
              ),
              child: Text(
                "Deegs Mix",
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.black87,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Colored stripes
            SizedBox(
              height: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Expanded(child: ColoredBox(color: Color(0xFFE57373))),
                  Expanded(child: ColoredBox(color: Color(0xFFFFB74D))),
                  Expanded(child: ColoredBox(color: Color(0xFF64B5F6))),
                ],
              ),
            ),
            // Main area: reels + center play button (no wobble)
            Expanded(
              child: Container(
                color: const Color(0xFFD5D0BC),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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

/// Spinning reel/gear inside the cassette.
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
          color: const Color(0xFF263238),
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 4; i++)
              Transform.rotate(
                angle: i * (math.pi / 2),
                child: Container(
                  width: 32,
                  height: 3,
                  color: Colors.white38,
                ),
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

/// Simple splash / watercolor background behind cassette.
class _SplashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Blue splash bottom-right
    paint.color = const Color(0xFF64B5F6).withOpacity(0.35);
    final path1 = Path()
      ..moveTo(size.width * 0.65, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.9,
        size.height * 0.6,
        size.width * 0.8,
        size.height * 0.9,
      )
      ..quadraticBezierTo(
        size.width * 0.6,
        size.height * 0.95,
        size.width * 0.65,
        size.height * 0.65,
      );
    canvas.drawPath(path1, paint);

    // Orange splash top-left
    paint.color = const Color(0xFFFFB74D).withOpacity(0.4);
    final path2 = Path()
      ..moveTo(size.width * 0.15, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.05,
        size.height * 0.35,
        size.width * 0.3,
        size.height * 0.3,
      )
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.1,
        size.width * 0.15,
        size.height * 0.15,
      );
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}