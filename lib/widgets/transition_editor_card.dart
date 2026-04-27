import 'package:flutter/material.dart';

import '../models/mixtape_payload.dart';

class TransitionEditorCard extends StatelessWidget {
  const TransitionEditorCard({
    super.key,
    required this.value,
    required this.maxSeconds,
    required this.onChanged,
  });

  final ClipTransition value;
  final double maxSeconds;
  final ValueChanged<ClipTransition> onChanged;

  @override
  Widget build(BuildContext context) {
    final max = maxSeconds <= 0 ? 1.0 : maxSeconds;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<TransitionType>(
            value: value.type,
            isExpanded: true,
            dropdownColor: const Color(0xFF16213E),
            items: const [
              DropdownMenuItem(
                value: TransitionType.hardCut,
                child: Text('Hard cut'),
              ),
              DropdownMenuItem(value: TransitionType.fade, child: Text('Fade')),
              DropdownMenuItem(
                value: TransitionType.crossfade,
                child: Text('Crossfade'),
              ),
            ],
            onChanged: (next) {
              if (next == null) return;
              if (next == TransitionType.hardCut) {
                onChanged(const ClipTransition.hardCut());
              } else if (next == TransitionType.fade) {
                onChanged(
                  ClipTransition(
                    type: TransitionType.fade,
                    fadeInSeconds: value.fadeInSeconds > 0
                        ? value.fadeInSeconds
                        : 1,
                    fadeOutSeconds: value.fadeOutSeconds > 0
                        ? value.fadeOutSeconds
                        : 1,
                  ),
                );
              } else {
                onChanged(
                  ClipTransition(
                    type: TransitionType.crossfade,
                    crossfadeSeconds: value.crossfadeSeconds > 0
                        ? value.crossfadeSeconds
                        : 1,
                  ),
                );
              }
            },
          ),
          if (value.type == TransitionType.fade) ...[
            Slider(
              min: 0,
              max: max,
              value: value.fadeOutSeconds.clamp(0.0, max),
              label: 'Fade out ${value.fadeOutSeconds.toStringAsFixed(1)}s',
              onChanged: (v) => onChanged(
                ClipTransition(
                  type: TransitionType.fade,
                  fadeOutSeconds: v,
                  fadeInSeconds: value.fadeInSeconds,
                ),
              ),
            ),
            Slider(
              min: 0,
              max: max,
              value: value.fadeInSeconds.clamp(0.0, max),
              label: 'Fade in ${value.fadeInSeconds.toStringAsFixed(1)}s',
              onChanged: (v) => onChanged(
                ClipTransition(
                  type: TransitionType.fade,
                  fadeOutSeconds: value.fadeOutSeconds,
                  fadeInSeconds: v,
                ),
              ),
            ),
          ],
          if (value.type == TransitionType.crossfade)
            Slider(
              min: 0,
              max: max,
              value: value.crossfadeSeconds.clamp(0.0, max),
              label: 'Crossfade ${value.crossfadeSeconds.toStringAsFixed(1)}s',
              onChanged: (v) => onChanged(
                ClipTransition(
                  type: TransitionType.crossfade,
                  crossfadeSeconds: v,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
