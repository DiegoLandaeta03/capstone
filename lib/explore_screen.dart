import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/mixtape_payload.dart';
import 'walkman_player_screen.dart';

// 2. Explore Page
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _allMixtapes = const [];
  List<Map<String, dynamic>> _results = const [];
  Map<String, List<String>> _genresBySongId = const {};
  Map<String, List<String>> _genresByMixtapeId = const {};
  Map<String, String> _creatorNameById = const {};

  @override
  void initState() {
    super.initState();
    _loadMixtapes();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMixtapes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _supabase
            .from('mixtapes')
            .select()
            .eq('is_public', true)
            .order('created_at', ascending: false)
            .limit(200),
        _supabase.from('songs').select('id, genres'),
      ]);

      final mixes = (results[0] as List).cast<Map<String, dynamic>>();
      final songs = (results[1] as List).cast<Map<String, dynamic>>();
      final genresBySongId = <String, List<String>>{};
      for (final s in songs) {
        final id = (s['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final raw = s['genres'];
        if (raw is List) {
          genresBySongId[id] = raw.map((g) => g.toString()).toList();
        } else {
          genresBySongId[id] = const [];
        }
      }

      final creatorIds = <String>{};
      for (final m in mixes) {
        final cid = (m['creator_id'] ?? '').toString();
        if (cid.isNotEmpty) creatorIds.add(cid);
      }
      Map<String, String> creatorNameById = const {};
      if (creatorIds.isNotEmpty) {
        try {
          final rows = await _supabase
              .from('profiles')
              .select('id, username, full_name')
              .inFilter('id', creatorIds.toList());
          final map = <String, String>{};
          for (final r in (rows as List).cast<Map<String, dynamic>>()) {
            final id = (r['id'] ?? '').toString();
            if (id.isEmpty) continue;
            final name = (r['username'] ?? r['full_name'] ?? '')
                .toString()
                .trim();
            if (name.isNotEmpty) map[id] = name;
          }
          creatorNameById = map;
        } catch (_) {
          creatorNameById = const {};
        }
      }

      if (!mounted) return;
      setState(() {
        _allMixtapes = mixes;
        _genresBySongId = genresBySongId;
        _genresByMixtapeId = _buildGenresByMixtapeId(
          mixes: mixes,
          genresBySongId: genresBySongId,
        );
        _creatorNameById = creatorNameById;
        _loading = false;
      });

      _applySearch(_controller.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load mixtapes.\n$e';
        _loading = false;
      });
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _applySearch(_controller.text);
    });
  }

  void _applySearch(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _results = _allMixtapes;
      });
      return;
    }

    final hits = _allMixtapes.where((m) {
      final title = (m['title'] ?? '').toString().toLowerCase();
      final description = (m['description'] ?? '').toString().toLowerCase();
      final id = (m['id'] ?? '').toString().toLowerCase();
      final creatorId = (m['creator_id'] ?? '').toString();
      final creatorName =
          (_creatorNameById[creatorId] ?? _creatorLabel(creatorId))
              .toLowerCase();
      final mixGenres = _genresForMixtape(
        m,
      ).map((g) => g.toLowerCase()).join(' ');
      return title.contains(query) ||
          description.contains(query) ||
          id.contains(query) ||
          creatorName.contains(query) ||
          mixGenres.contains(query);
    }).toList();

    setState(() {
      _results = hits;
    });
  }

  String _creatorLabel(String creatorId) {
    final name = _creatorNameById[creatorId];
    if (name != null && name.trim().isNotEmpty) return name.trim();
    if (creatorId.isEmpty) return 'creator';
    if (creatorId.length <= 8) return creatorId;
    return '${creatorId.substring(0, 4)}…${creatorId.substring(creatorId.length - 4)}';
  }

  Map<String, List<String>> _buildGenresByMixtapeId({
    required List<Map<String, dynamic>> mixes,
    required Map<String, List<String>> genresBySongId,
  }) {
    final out = <String, List<String>>{};
    for (final mix in mixes) {
      final mixId = (mix['id'] ?? '').toString();
      if (mixId.isEmpty) continue;
      out[mixId] = _extractGenresFromMix(
        mix: mix,
        genresBySongId: genresBySongId,
      );
    }
    return out;
  }

  List<String> _extractGenresFromMix({
    required Map<String, dynamic> mix,
    required Map<String, List<String>> genresBySongId,
  }) {
    final set = <String>{};
    final payload = MixtapeTracksPayload.fromJson(mix['tracks']);
    for (final clip in payload.tracks) {
      final songId = clip.songId;
      if (songId.isEmpty) continue;
      for (final g in (genresBySongId[songId] ?? const <String>[])) {
        final trimmed = g.trim();
        if (trimmed.isNotEmpty) set.add(trimmed);
      }
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> _genresForMixtape(Map<String, dynamic> mix) {
    final id = (mix['id'] ?? '').toString();
    if (id.isEmpty) return const [];
    final cached = _genresByMixtapeId[id];
    if (cached != null) return cached;
    // Fallback if cache wasn't built yet.
    return _extractGenresFromMix(mix: mix, genresBySongId: _genresBySongId);
  }

  List<WalkmanMixTrack> _extractPlayableTracks(Map<String, dynamic> mix) {
    final payload = MixtapeTracksPayload.fromJson(mix['tracks']);
    return payload.tracks
        .where((c) => c.isPlayable)
        .map(
          (c) => WalkmanMixTrack(
            fileKey: c.fileKey,
            startSeconds: c.startSeconds,
            endSeconds: c.endSeconds,
            title: c.title,
            artist: c.artist,
            coverArtUrl: c.albumArtUrl,
            transitionToNext: c.transitionToNext,
          ),
        )
        .toList(growable: false);
  }

  int _trackCountForMix(Map<String, dynamic> mix) {
    return MixtapeTracksPayload.fromJson(mix['tracks']).tracks.length;
  }

  Future<void> _openMix(Map<String, dynamic> mix) async {
    final title = (mix['title'] as String?)?.trim();
    final creatorId = (mix['creator_id'] ?? '').toString();
    final creator = _creatorLabel(creatorId);
    final tracks = _extractPlayableTracks(mix);
    if (tracks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No playable tracks found for this mix.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalkmanPlayerScreen(
          title: (title == null || title.isEmpty) ? 'Mixtape' : title,
          artist: creator,
          mixTracks: tracks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Explore',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText:
                      'Search title, description, username, or mixtape ID...',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  suffixIcon: _controller.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                          ),
                          onPressed: () {
                            _controller.clear();
                            _applySearch('');
                          },
                        ),
                  filled: true,
                  fillColor: const Color(0xFF16213E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.blueAccent,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadMixtapes,
                              child: Text('Retry', style: GoogleFonts.outfit()),
                            ),
                          ],
                        ),
                      )
                    : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No results.',
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.92,
                            ),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final mix = _results[index];
                          final title = (mix['title'] as String?)?.trim();
                          final description = (mix['description'] as String?)
                              ?.trim();
                          final coverArtUrl = (mix['cover_art_url'] ?? '')
                              .toString()
                              .trim();
                          final id = (mix['id'] ?? '').toString();
                          final creatorId = (mix['creator_id'] ?? '')
                              .toString();
                          final creator = _creatorLabel(creatorId);
                          final trackCount = _trackCountForMix(mix);
                          final genres = _genresForMixtape(mix);

                          return InkWell(
                            onTap: () => _openMix(mix),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: const Color(0xFF16213E),
                                border: Border.all(color: Colors.white10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: coverArtUrl.isNotEmpty
                                          ? Image.network(
                                              coverArtUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stack) {
                                                    return Container(
                                                      color: Colors.blueAccent
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                      child: const Icon(
                                                        Icons
                                                            .queue_music_rounded,
                                                        color: Colors.white70,
                                                        size: 34,
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Container(
                                              color: Colors.blueAccent
                                                  .withValues(alpha: 0.12),
                                              child: const Icon(
                                                Icons.queue_music_rounded,
                                                color: Colors.white70,
                                                size: 34,
                                              ),
                                            ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (title == null || title.isEmpty)
                                                ? 'Untitled Mix'
                                                : title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (description == null ||
                                                    description.isEmpty)
                                                ? '$trackCount tracks'
                                                : description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              height: 1.25,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '@$creator',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white54,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (genres.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              genres.take(3).join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.outfit(
                                                color: Colors.blueAccent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Text(
                                            id.isEmpty ? '' : id,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
