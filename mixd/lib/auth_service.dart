import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Stream to listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
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

        const webClientId = '214249329097-u3l2f7tpkat618lb28ck4fmqf0ib0b22.apps.googleusercontent.com';
        const iosClientId = '214249329097-4q242msfso6b852bjngvhs8fg4gf6751.apps.googleusercontent.com';

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
        
        const webClientId = '214249329097-u3l2f7tpkat618lb28ck4fmqf0ib0b22.apps.googleusercontent.com';
        const iosClientId = '214249329097-4q242msfso6b852bjngvhs8fg4gf6751.apps.googleusercontent.com';

        await googleSignIn.initialize(
          clientId: iosClientId,
          serverClientId: webClientId,
        );
        
        await googleSignIn.signOut();
      }
      
      // Sign out from Supabase (Web and Mobile)
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint("Error signing out: $e");
    }
  }

}
