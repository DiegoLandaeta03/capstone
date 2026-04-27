import 'package:flutter/material.dart';

class WaveformTrimEditor extends StatelessWidget {
  const WaveformTrimEditor({
    super.key,
    required this.peaks,
    required this.clipStartSeconds,
    required this.clipEndSeconds,
    required this.viewportStartSeconds,
    required this.viewportEndSeconds,
    required this.songDurationSeconds,
    required this.onTrimChanged,
    required this.onViewportChanged,
  });

  final List<double> peaks;
  final double clipStartSeconds;
  final double clipEndSeconds;
  final double viewportStartSeconds;
  final double viewportEndSeconds;
  final double songDurationSeconds;
  final ValueChanged<RangeValues> onTrimChanged;
  final ValueChanged<RangeValues> onViewportChanged;

  @override
  Widget build(BuildContext context) {
    final maxDuration = songDurationSeconds <= 1 ? 1.0 : songDurationSeconds;
    final viewStart = viewportStartSeconds.clamp(0.0, maxDuration);
    final viewEnd = viewportEndSeconds.clamp(viewStart + 0.1, maxDuration);
    final trimStart = clipStartSeconds.clamp(viewStart, viewEnd);
    final trimEnd = clipEndSeconds.clamp(trimStart + 0.1, viewEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 60,
          child: CustomPaint(
            painter: _WaveformPainter(
              peaks: peaks,
              viewportStartSeconds: viewStart,
              viewportEndSeconds: viewEnd,
              songDurationSeconds: maxDuration,
              trimStartSeconds: trimStart,
              trimEndSeconds: trimEnd,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        RangeSlider(
          values: RangeValues(trimStart, trimEnd),
          min: viewStart,
          max: viewEnd,
          labels: RangeLabels(
            trimStart.toStringAsFixed(1),
            trimEnd.toStringAsFixed(1),
          ),
          onChanged: onTrimChanged,
        ),
        RangeSlider(
          values: RangeValues(viewStart, viewEnd),
          min: 0.0,
          max: maxDuration,
          labels: RangeLabels(
            'View ${viewStart.toStringAsFixed(0)}s',
            '${viewEnd.toStringAsFixed(0)}s',
          ),
          onChanged: onViewportChanged,
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.viewportStartSeconds,
    required this.viewportEndSeconds,
    required this.songDurationSeconds,
    required this.trimStartSeconds,
    required this.trimEndSeconds,
  });

  final List<double> peaks;
  final double viewportStartSeconds;
  final double viewportEndSeconds;
  final double songDurationSeconds;
  final double trimStartSeconds;
  final double trimEndSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0x221E88E5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      bg,
    );

    if (peaks.isEmpty) return;
    final count = peaks.length;
    final viewPctStart = (viewportStartSeconds / songDurationSeconds).clamp(
      0.0,
      1.0,
    );
    final viewPctEnd = (viewportEndSeconds / songDurationSeconds).clamp(
      viewPctStart,
      1.0,
    );
    final startIndex = (viewPctStart * count).floor().clamp(0, count - 1);
    final endIndex = (viewPctEnd * count).ceil().clamp(startIndex + 1, count);
    final visible = peaks.sublist(startIndex, endIndex);
    final barW = size.width / visible.length;
    final barPaint = Paint()..color = Colors.white70;

    for (int i = 0; i < visible.length; i++) {
      final amp = visible[i].clamp(0.02, 1.0);
      final h = size.height * amp;
      final x = i * barW;
      canvas.drawRect(
        Rect.fromLTWH(x, (size.height - h) / 2, barW * 0.8, h),
        barPaint,
      );
    }

    final trimPaint = Paint()..color = const Color(0x553A7BFF);
    final trimStartX =
        ((trimStartSeconds - viewportStartSeconds) /
                (viewportEndSeconds - viewportStartSeconds))
            .clamp(0.0, 1.0) *
        size.width;
    final trimEndX =
        ((trimEndSeconds - viewportStartSeconds) /
                (viewportEndSeconds - viewportStartSeconds))
            .clamp(0.0, 1.0) *
        size.width;
    canvas.drawRect(
      Rect.fromLTWH(
        trimStartX,
        0,
        (trimEndX - trimStartX).clamp(0.0, size.width),
        size.height,
      ),
      trimPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.viewportStartSeconds != viewportStartSeconds ||
        oldDelegate.viewportEndSeconds != viewportEndSeconds ||
        oldDelegate.trimStartSeconds != trimStartSeconds ||
        oldDelegate.trimEndSeconds != trimEndSeconds;
  }
}
