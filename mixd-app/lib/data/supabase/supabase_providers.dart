import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/env.dart';

final supabaseEnabledProvider = Provider<bool>((ref) {
  return Env.supabaseConfigured;
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!ref.watch(supabaseEnabledProvider)) return null;
  return Supabase.instance.client;
});