import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/env.dart';

class SupabaseInitializer {
  static Future<void> maybeInitialize() async {
    if (!Env.supabaseConfigured) return;

    // Throws if URL/key are invalid; keep failure loud so it’s caught early in
    // dev, but still allow the app to run without any config.
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }
}

