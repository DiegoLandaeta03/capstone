import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/supabase/supabase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // For local/dev runs without Supabase configured, the app still boots and
  // shows mocked data. Provide these at runtime to enable Supabase:
  // --dart-define=SUPABASE_URL=...
  // --dart-define=SUPABASE_ANON_KEY=...
  await SupabaseInitializer.maybeInitialize();

  runApp(const ProviderScope(child: MixdApp()));
}
