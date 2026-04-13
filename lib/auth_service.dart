import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _lastSignInError;

  // Stream to listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;
  String? get lastSignInError => _lastSignInError;

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _lastSignInError = null;
      if (kIsWeb) {
        // WEB FLOW: Use Supabase's built-in OAuth redirect
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'http://localhost:${Uri.base.port}/', 
        );
        return true; // Redirecting...
      } else {
        // MOBILE FLOW: Use native Google Sign-In
        final GoogleSignIn googleSignIn = GoogleSignIn.instance;

        final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
        final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
        if (webClientId == null || iosClientId == null) {
          throw Exception('Missing GOOGLE_WEB_CLIENT_ID or GOOGLE_IOS_CLIENT_ID in .env');
        }

        await googleSignIn.initialize(
          clientId: iosClientId,
          serverClientId: webClientId,
        );

        final googleUser = await googleSignIn.authenticate();

        final googleAuth = googleUser.authentication;
        final idToken = googleAuth.idToken;

        if (idToken == null) throw 'No ID Token found.';

        await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
        return true;
      }
    } catch (e) {
      _lastSignInError = e.toString();
      debugPrint("Error in Google Sign-In: $e");
      return false;
    }
  }



  // Sign out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        // Only attempt Google Sign-Out on Native (iOS/Android/macOS)
        // Ensure initialization before calling sign-out
        final GoogleSignIn googleSignIn = GoogleSignIn.instance;
        
        final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
        final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
        if (webClientId == null || iosClientId == null) {
          debugPrint('Missing Google client IDs in .env, skipping Google sign-out');
        } else {
          await googleSignIn.initialize(
            clientId: iosClientId,
            serverClientId: webClientId,
          );
          await googleSignIn.signOut();
        }
      }
      
      // Sign out from Supabase (Web and Mobile)
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint("Error signing out: $e");
    }
  }

}
