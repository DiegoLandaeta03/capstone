import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/auth_session.dart';
import '../supabase/supabase_providers.dart';
import 'auth_repository.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository() : _controller = StreamController<AuthSession?>.broadcast();

  final StreamController<AuthSession?> _controller;
  AuthSession? _session;

  @override
  Stream<AuthSession?> get sessionChanges async* {
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    // MVP stub: accept any non-empty credentials.
    if (email.trim().isEmpty || password.isEmpty) {
      throw const FormatException('Email and password required.');
    }
    _session = AuthSession(userId: 'local-user', email: email.trim());
    _controller.add(_session);
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return signInWithEmailPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<AuthSession?> get sessionChanges {
    return _client.auth.onAuthStateChange.map((event) {
      final session = event.session;
      if (session == null) return null;
      return AuthSession(userId: session.user.id, email: session.user.email);
    });
  }

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signUp(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

// Providers live here to keep router/auth integration centralized.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final enabled = ref.watch(supabaseEnabledProvider);
  if (!enabled) {
    final repo = LocalAuthRepository();
    ref.onDispose(repo.dispose);
    return repo;
  }

  final client = ref.watch(supabaseClientProvider);
  return SupabaseAuthRepository(client!);
});

final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  return ref.watch(authRepositoryProvider).sessionChanges;
});

