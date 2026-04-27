import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'explore_screen.dart';
import 'models/mixtape_payload.dart';
import 'walkman_player_screen.dart';

/// Virtual pages = `mixtapes.length * _kForYouLoopFactor` so the feed loops forever.
const int _kForYouLoopFactor = 8192;

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PageController _pageController = PageController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _mixtapes = const [];

  final Map<String, int> _likeCounts = {};
  final Map<String, int> _commentCounts = {};
  final Set<String> _likedByMe = {};
  final Map<String, String> _creatorNameById = {};

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  User? get _user => _supabase.auth.currentUser;

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadFeed() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final mixes =
          (await _supabase
                  .from('mixtapes')
                  .select()
                  .eq('is_public', true)
                  .order('created_at', ascending: false)
                  .limit(50))
              .cast<Map<String, dynamic>>();

      final forYou = List<Map<String, dynamic>>.from(mixes);
      forYou.shuffle(Random());

      if (!mounted) return;
      setState(() {
        _mixtapes = forYou;
        _loading = false;
      });

      _prefetchCreatorNames(forYou);

      for (int i = 0; i < forYou.length && i < 8; i++) {
        final id = forYou[i]['id']?.toString();
        if (id != null && id.isNotEmpty) {
          _syncLikesFromRow(forYou[i]);
          _loadSocialForMixtape(id);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load feed.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _prefetchCreatorNames(List<Map<String, dynamic>> mixes) async {
    final ids = <String>{};
    for (final m in mixes) {
      final cid = m['creator_id']?.toString();
      if (cid != null && cid.isNotEmpty && !_creatorNameById.containsKey(cid)) {
        ids.add(cid);
      }
    }
    if (ids.isEmpty) return;

    try {
      final rows = await _supabase
          .from('profiles')
          .select('id, username, full_name')
          .inFilter('id', ids.toList());
      final map = <String, String>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final id = r['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = (r['username'] ?? r['full_name'] ?? '').toString().trim();
        if (name.isNotEmpty) map[id] = name;
      }
      if (!mounted) return;
      setState(() => _creatorNameById.addAll(map));
    } catch (_) {}

    // Fallback: derive something readable from `users.email` if profiles is missing.
    try {
      final rows = await _supabase
          .from('users')
          .select('id, email')
          .inFilter('id', ids.toList());
      final map = <String, String>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final id = r['id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (_creatorNameById.containsKey(id)) continue;
        final email = (r['email'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          final local = email.split('@').first.trim();
          map[id] = local.isEmpty ? email : local;
        }
      }
      if (!mounted) return;
      setState(() => _creatorNameById.addAll(map));
    } catch (_) {}
  }

  String _creatorLabel(String creatorId) {
    final name = _creatorNameById[creatorId];
    if (name != null && name.trim().isNotEmpty) return name.trim();
    if (creatorId.isEmpty) return 'creator';
    if (creatorId.length <= 8) return creatorId;
    return '${creatorId.substring(0, 4)}…${creatorId.substring(creatorId.length - 4)}';
  }

  void _syncLikesFromRow(Map<String, dynamic> mix) {
    final id = mix['id']?.toString();
    if (id == null || id.isEmpty) return;
    final likes = mix['likes'];
    if (likes == null) {
      _likeCounts[id] = 0;
    } else if (likes is num) {
      _likeCounts[id] = likes.toInt();
    } else {
      _likeCounts[id] = int.tryParse(likes.toString()) ?? 0;
    }
  }

  Future<void> _loadSocialForMixtape(
    String mixtapeId, {
    bool force = false,
  }) async {
    if (!force && _commentCounts.containsKey(mixtapeId)) {
      return;
    }

    // Load liked state separately so it can't be swallowed by other failures.
    _loadLikedState(mixtapeId);

    try {
      final rows = await _supabase
          .from('mixtape_comments')
          .select('id')
          .eq('mixtape_id', mixtapeId);

      if (!mounted) return;
      setState(() {
        _commentCounts[mixtapeId] = rows.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentCounts.putIfAbsent(mixtapeId, () => 0);
      });
    }
  }

  Future<void> _loadLikedState(String mixtapeId) async {
    final user = _user;
    if (user == null) return;

    try {
      final rows = await _supabase
          .from('mixtape_likes')
          .select('mixtape_id')
          .eq('mixtape_id', mixtapeId)
          .eq('user_id', user.id)
          .limit(1);

      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty) {
          _likedByMe.add(mixtapeId);
        } else {
          _likedByMe.remove(mixtapeId);
        }
      });
    } catch (_) {
      // mixtape_likes table may not exist yet — don't crash.
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int _trackCountForMix(Map<String, dynamic> mix) {
    return MixtapeTracksPayload.fromJson(mix['tracks']).tracks.length;
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

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  // ---------------------------------------------------------------------------
  // Social actions
  // ---------------------------------------------------------------------------

  Future<void> _toggleLike(String mixtapeId) async {
    final user = _user;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sign in to like mixtapes.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
      return;
    }

    final alreadyLiked = _likedByMe.contains(mixtapeId);
    final current = _likeCounts[mixtapeId] ?? 0;
    final next = (alreadyLiked ? current - 1 : current + 1).clamp(0, 1 << 30);

    setState(() {
      _likeCounts[mixtapeId] = next;
      alreadyLiked ? _likedByMe.remove(mixtapeId) : _likedByMe.add(mixtapeId);
    });

    try {
      // Prefer RPC if available. It should perform exactly one toggle.
      var usedRpc = false;
      try {
        await _supabase.rpc(
          'toggle_mixtape_like',
          params: {'p_mixtape_id': mixtapeId, 'p_user_id': user.id},
        );
        usedRpc = true;
      } catch (_) {
        usedRpc = false;
      }

      if (!usedRpc) {
        // Fallback path when RPC is unavailable: toggle row + counter manually.
        if (alreadyLiked) {
          await _supabase
              .from('mixtape_likes')
              .delete()
              .eq('mixtape_id', mixtapeId)
              .eq('user_id', user.id);
        } else {
          await _supabase.from('mixtape_likes').upsert({
            'mixtape_id': mixtapeId,
            'user_id': user.id,
          });
        }
        // Best effort: keep aggregate likes in sync.
        try {
          await _supabase
              .from('mixtapes')
              .update({'likes': next})
              .eq('id', mixtapeId);
        } catch (_) {}
      }

      // Re-sync from DB to avoid UI drift after optimistic update.
      _loadLikedState(mixtapeId);
      try {
        final row = await _supabase
            .from('mixtapes')
            .select('likes')
            .eq('id', mixtapeId)
            .maybeSingle();
        if (row != null && mounted) {
          setState(() {
            _syncLikesFromRow({'id': mixtapeId, 'likes': row['likes']});
          });
        }
      } catch (_) {}
    } catch (_) {
      // Undo optimistic UI if the like row write failed.
      setState(() {
        _likeCounts[mixtapeId] = current;
        alreadyLiked ? _likedByMe.add(mixtapeId) : _likedByMe.remove(mixtapeId);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update like.', style: GoogleFonts.outfit()),
        ),
      );
    }
  }

  Future<void> _openComments(String mixtapeId) async {
    final user = _user;
    final controller = TextEditingController();

    Future<List<Map<String, dynamic>>> loadComments() async {
      return (await _supabase
              .from('mixtape_comments')
              .select()
              .eq('mixtape_id', mixtapeId)
              .order('created_at', ascending: false)
              .limit(100))
          .cast<Map<String, dynamic>>();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1224),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Comments',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadComments(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(
                          color: Colors.blueAccent,
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Could not load comments.',
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      );
                    }
                    final items = snap.data ?? const [];
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'No comments yet.',
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (_, i) {
                          final c = items[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '@${_creatorLabel((c['user_id'] ?? '').toString())}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              (c['content'] ?? '').toString(),
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 3,
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: user == null
                              ? 'Sign in to comment'
                              : 'Add a comment…',
                          hintStyle: GoogleFonts.outfit(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        enabled: user != null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: user == null
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) return;
                              try {
                                await _supabase
                                    .from('mixtape_comments')
                                    .insert({
                                      'mixtape_id': mixtapeId,
                                      'user_id': user.id,
                                      'content': text,
                                    });
                                controller.clear();
                                if (!ctx.mounted) return;
                                if (Navigator.of(ctx).canPop()) {
                                  Navigator.of(ctx).pop();
                                }
                              } catch (_) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not post comment.',
                                      style: GoogleFonts.outfit(),
                                    ),
                                  ),
                                );
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3A7BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Send',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _loadSocialForMixtape(mixtapeId, force: true);
  }

  Future<void> _shareMixtape(String mixtapeId) async {
    await Clipboard.setData(ClipboardData(text: mixtapeId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mixtape ID copied.', style: GoogleFonts.outfit()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
                onPressed: _loadFeed,
                child: Text('Retry', style: GoogleFonts.outfit()),
              ),
            ],
          ),
        ),
      );
    }
    if (_mixtapes.isEmpty) {
      return Center(
        child: Text(
          'No mixtapes yet.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _mixtapes.isEmpty
              ? 0
              : _mixtapes.length * _kForYouLoopFactor,
          itemBuilder: (context, index) {
            final n = _mixtapes.length;
            final mix = _mixtapes[index % n];
            final id = mix['id']?.toString() ?? '';
            if (id.isNotEmpty) _loadSocialForMixtape(id);

            final title = (mix['title'] as String?)?.trim();
            final creatorId = (mix['creator_id'] ?? '').toString();
            final description = (mix['description'] as String?)?.trim();
            final trackCount = _trackCountForMix(mix);

            final likeCount =
                _likeCounts[id] ??
                (mix['likes'] is num ? (mix['likes'] as num).toInt() : 0);
            final liked = _likedByMe.contains(id);
            final creator = _creatorLabel(creatorId);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF000000),
                        Color(0xFF0A0A1A),
                        Color(0xFF1A1A2E),
                      ],
                    ),
                  ),
                ),

                // Cassette card — centered
                Center(
                  child: _FeedCassetteCard(
                    title: title == null || title.isEmpty
                        ? 'Untitled Mix'
                        : title,
                    artist: creator,
                    trackCount: trackCount,
                    description: description,
                    onTapPlay: () {
                      final tracks = _extractPlayableTracks(mix);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WalkmanPlayerScreen(
                            title: title == null || title.isEmpty
                                ? 'Mixtape'
                                : title,
                            artist: creator,
                            mixTracks: tracks,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Action buttons — right side
                Positioned(
                  right: 14,
                  bottom: 90,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SocialButton(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: _fmt(likeCount),
                        color: liked ? const Color(0xFFFF4D6A) : Colors.white70,
                        onTap: id.isEmpty ? null : () => _toggleLike(id),
                      ),
                      const SizedBox(height: 18),
                      _SocialButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Comments',
                        onTap: id.isEmpty ? null : () => _openComments(id),
                      ),
                      const SizedBox(height: 18),
                      _SocialButton(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: id.isEmpty ? null : () => _shareMixtape(id),
                      ),
                    ],
                  ),
                ),

                // Creator name — bottom left
                Positioned(
                  left: 18,
                  right: 70,
                  bottom: 36,
                  child: Text(
                    '@$creator',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // Explore bar
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: SafeArea(
            bottom: false,
            child: GestureDetector(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ExploreScreen())),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Explore',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Social button widget (right sidebar)
// =============================================================================

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    this.color = Colors.white70,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Cassette card — clean layout with play button properly centered
// =============================================================================

class _FeedCassetteCard extends StatelessWidget {
  const _FeedCassetteCard({
    required this.title,
    required this.artist,
    required this.trackCount,
    required this.description,
    required this.onTapPlay,
  });

  final String title;
  final String artist;
  final int trackCount;
  final String? description;
  final VoidCallback onTapPlay;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.82,
      heightFactor: 0.52,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E2B4A), Color(0xFF18223D), Color(0xFF121A31)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white12, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Column(
            children: [
              // ── Header: title + artist ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@$artist  ·  $trackCount tracks',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Accent divider ──
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: Colors.blueAccent.withValues(alpha: 0.25),
              ),

              // ── Center area: reels + play button ──
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _StaticReel(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: GestureDetector(
                          onTap: onTapPlay,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF3A7BFF),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF3A7BFF,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const _StaticReel(),
                    ],
                  ),
                ),
              ),

              // ── Footer: description (if any) ──
              if (description != null && description!.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Text(
                    description!.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white60,
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Static reel graphic
// =============================================================================

class _StaticReel extends StatelessWidget {
  const _StaticReel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F172A),
        border: Border.all(color: Colors.white38, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 4; i++)
            Transform.rotate(
              angle: i * (3.1415926535 / 2),
              child: Container(width: 26, height: 2, color: Colors.white24),
            ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
