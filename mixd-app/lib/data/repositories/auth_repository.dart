import '../models/auth_session.dart';

abstract interface class AuthRepository {
  Stream<AuthSession?> get sessionChanges;

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

