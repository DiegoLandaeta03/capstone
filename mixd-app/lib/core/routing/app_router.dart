import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/playback/walkman_player_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          // TODO: replace with a real local MP3 path on your device/emulator.
          const demoPath = '/path/to/local/demo.mp3';
          return const WalkmanPlayerScreen(
            filePath: demoPath,
            title: 'Demo Mix',
            artist: 'You',
          );
        },
      ),
    ],
  );
});
