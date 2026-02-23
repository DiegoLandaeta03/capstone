import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/supabase/supabase_providers.dart';

class MixdApp extends ConsumerWidget {
  const MixdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final supabaseEnabled = ref.watch(supabaseEnabledProvider);

    return MaterialApp.router(
      title: 'Mixd',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!supabaseEnabled) {
          return Banner(
            message: 'Supabase disabled (mock data)',
            location: BannerLocation.topStart,
            child: content,
          );
        }
        return content;
      },
    );
  }
}

