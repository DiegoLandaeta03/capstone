import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/signed_audio_url_service.dart';
import 'mixtape_editor_screen.dart';

// 3. Plus/Create Page
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key, this.onMixtapeSaved});

  final VoidCallback? onMixtapeSaved;

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SignedAudioUrlService _signedAudioUrlService = SignedAudioUrlService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isLoading = true;
  String? _errorMessage;
  List<_Song> _songs = [];
  String _searchQuery = '';
  final Set<int> _selectedIndexes = {};
  String? _currentlyPlayingSongId;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _supabase.from('songs').select().order('title');

      final songs = (data as List<dynamic>)
          .map((row) => _Song.fromMap(row as Map<String, dynamic>))
          .toList();

      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load songs. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _toggleSelected(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  Future<void> _playPreview(_Song song) async {
    // Toggle off if this song is already playing
    if (_currentlyPlayingSongId == song.id && _audioPlayer.playing) {
      _previewTimer?.cancel();
      await _audioPlayer.stop();
      setState(() {});
      return;
    }

    final url = await _buildSongAudioUrl(song);
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No audio file configured for this song.',
              style: GoogleFonts.outfit(),
            ),
          ),
        );
      }
      return;
    }

    try {
      _previewTimer?.cancel();
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);

      setState(() {
        _currentlyPlayingSongId = song.id;
      });

      // Start playback without awaiting so we can enforce a 30s limit.
      _audioPlayer.play();

      // Stop automatically after 30 seconds (preview)
      _previewTimer = Timer(const Duration(seconds: 30), () async {
        if (!mounted) return;
        if (_currentlyPlayingSongId == song.id && _audioPlayer.playing) {
          await _audioPlayer.stop();
          if (mounted) {
            setState(() {});
          }
        }
      });
    } catch (_) {
      // Silently ignore for now; you can add error UI if desired
    }
  }

  Future<String?> _buildSongAudioUrl(_Song song) async {
    return _signedAudioUrlService.signedSongUrl(song.fileKey);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_isLoading) {
      body = const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    } else if (_errorMessage != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              style: GoogleFonts.outfit(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadSongs,
              child: Text(
                'Retry',
                style: GoogleFonts.outfit(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      );
    } else if (_songs.isEmpty) {
      body = Center(
        child: Text(
          'No songs found in the library.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
      );
    } else {
      final query = _searchQuery.trim().toLowerCase();
      final filteredSongs = query.isEmpty
          ? _songs
          : _songs.where((song) {
              final title = song.title.toLowerCase();
              final artist = song.artist.toLowerCase();
              final genreText = song.genres
                  .map((g) => g.toLowerCase())
                  .join(' ');

              return title.contains(query) ||
                  artist.contains(query) ||
                  genreText.contains(query);
            }).toList();

      body = ListView.builder(
        itemCount: filteredSongs.length,
        itemBuilder: (context, index) {
          final song = filteredSongs[index];
          final originalIndex = _songs.indexOf(song);
          final isSelected = _selectedIndexes.contains(originalIndex);
          final isPlayingPreview =
              _currentlyPlayingSongId == song.id && _audioPlayer.playing;

          return InkWell(
            onTap: () => _toggleSelected(originalIndex),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? Colors.blueAccent : Colors.white10,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ListTile(
                leading: GestureDetector(
                  onTap: () => _playPreview(song),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child:
                              song.albumArtUrl != null &&
                                  song.albumArtUrl!.isNotEmpty
                              ? Image.network(
                                  song.albumArtUrl!,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.blueAccent.withAlpha(51),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          color: Colors.black.withAlpha(77),
                          child: Icon(
                            isPlayingPreview
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                title: Text(
                  song.title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  song.artist,
                  style: GoogleFonts.outfit(color: Colors.white70),
                ),
                trailing: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? Colors.blueAccent : Colors.white38,
                ),
              ),
            ),
          );
        },
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Mix',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Browse your library and select songs to include in your mix.',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by artist, title, or genre...',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF16213E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: body),
          if (_songs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF16213E),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedIndexes.length} selected',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _selectedIndexes.isEmpty
                        ? null
                        : () async {
                            // Ensure any preview audio stops when moving
                            // into the mixtape creation screen.
                            _previewTimer?.cancel();
                            await _audioPlayer.stop();

                            final selectedSongs = _selectedIndexes
                                .map((index) => _songs[index])
                                .map(
                                  (song) => {
                                    'id': song.id,
                                    'title': song.title,
                                    'artist': song.artist,
                                    'albumArtUrl': song.albumArtUrl,
                                    'fileKey': song.fileKey,
                                    'durationSeconds': song.durationSeconds,
                                  },
                                )
                                .toList();

                            if (!context.mounted) return;

                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MixtapeEditorScreen(
                                  songs: selectedSongs,
                                  onSaved: widget.onMixtapeSaved,
                                ),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Next',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Song {
  const _Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.albumArtUrl,
    this.fileKey,
    this.durationSeconds,
    this.genres = const [],
  });

  /// Supabase `songs.id` (UUID as string)
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArtUrl;
  final String? fileKey;
  final int? durationSeconds;

  /// Supabase `songs.genres` (text[] / jsonb)
  final List<String> genres;

  String? get primaryGenre => genres.isNotEmpty ? genres.first : null;

  factory _Song.fromMap(Map<String, dynamic> map) {
    final rawGenres = map['genres'];
    List<String> parsedGenres;

    if (rawGenres is List) {
      parsedGenres = rawGenres.map((g) => g.toString()).toList();
    } else {
      parsedGenres = const [];
    }

    return _Song(
      id: map['id']?.toString() ?? '',
      title: map['title'] as String? ?? 'Untitled',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String?,
      albumArtUrl: map['album_art_url'] as String?,
      fileKey: map['file_key'] as String?,
      durationSeconds: map['duration_seconds'] is int
          ? map['duration_seconds'] as int
          : (map['duration_seconds'] is num
                ? (map['duration_seconds'] as num).round()
                : null),
      genres: parsedGenres,
    );
  }
}
