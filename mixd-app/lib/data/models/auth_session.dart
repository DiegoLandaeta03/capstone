class AuthSession {
  const AuthSession({
    required this.userId,
    this.email,
  });

  final String userId;
  final String? email;
}

