import 'package:supabase_flutter/supabase_flutter.dart';

class SignedAudioUrlService {
  SignedAudioUrlService({SupabaseClient? supabaseClient, this.ttlSeconds = 300})
    : _supabaseClient = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabaseClient;
  final int ttlSeconds;

  final Map<String, ({String url, DateTime expiresAt})> _cache = {};

  Future<String?> signedSongUrl(String? fileKey) async {
    final key = (fileKey ?? '').trim();
    if (key.isEmpty) return null;
    final objectPath = key.endsWith('.mp3') ? key : '$key.mp3';
    final now = DateTime.now();
    final cached = _cache[objectPath];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return cached.url;
    }

    try {
      final signed = await _supabaseClient.storage
          .from('song-files')
          .createSignedUrl(objectPath, ttlSeconds);
      _cache[objectPath] = (
        url: signed,
        expiresAt: now.add(Duration(seconds: ttlSeconds - 10)),
      );
      return signed;
    } catch (_) {
      return null;
    }
  }
}
