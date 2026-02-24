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
          const demoPath = '/Users/diegolandaeta/Documents/music/Ácido Pantera - Sonido Campechano  (Ft. Digital Charanga) [ ezmp3.cc ].mp3';
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
