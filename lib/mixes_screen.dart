import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/mixtape_payload.dart';
import 'walkman_player_screen.dart';

class MixesScreen extends StatefulWidget {
  const MixesScreen({super.key});

  @override
  State<MixesScreen> createState() => _MixesScreenState();
}

class _MixesScreenState extends State<MixesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _myMixes = const [];
  List<Map<String, dynamic>> _sharedMixes = const [];
  Map<String, String> _creatorNameById = const {};
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadMixes();
  }

  Future<List<Map<String, dynamic>>> _fetchSharedMixesForUser(
    String userId,
  ) async {
    // Try Postgres array contains syntax first (works for uuid[] and text[]).
    try {
      final rows = await _supabase
          .from('mixtapes')
          .select()
          .filter('shared_users', 'cs', '{$userId}')
          .neq('creator_id', userId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {}

    // Fallback for jsonb arrays.
    try {
      final rows = await _supabase
          .from('mixtapes')
          .select()
          .contains('shared_users', [userId])
          .neq('creator_id', userId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {}

    return const <Map<String, dynamic>>[];
  }

  Future<void> _loadMixes() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign in to view your mixes.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final myMixesFuture = _supabase
          .from('mixtapes')
          .select()
          .eq('creator_id', user.id)
          .order('created_at', ascending: false);

      final sharedMixesFuture = _fetchSharedMixesForUser(user.id);

      final results = await Future.wait([myMixesFuture, sharedMixesFuture]);
      final myMixes = (results[0] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final sharedMixes = (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final creatorIds = sharedMixes
          .map((m) => m['creator_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final creatorNameById = <String, String>{};

      if (creatorIds.isNotEmpty) {
        try {
          final rows = await _supabase
              .from('profiles')
              .select('id, username')
              .inFilter('id', creatorIds);
          for (final row
              in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final username = (row['username'] ?? '').toString().trim();
            if (username.isNotEmpty) {
              creatorNameById[id] = username;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _myMixes = myMixes;
        _sharedMixes = sharedMixes;
        _creatorNameById = creatorNameById;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load mixes right now.';
        _isLoading = false;
      });
    }
  }

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

  Future<void> _confirmAndDeleteMix(Map<String, dynamic> mix) async {
    final mixId = mix['id']?.toString();
    if (mixId == null || mixId.isEmpty) return;

    final title = (mix['title'] as String?)?.trim();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          title: Text(
            'Delete mixtape?',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'This will permanently delete "${title == null || title.isEmpty ? 'Untitled Mix' : title}".',
            style: GoogleFonts.outfit(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(color: Colors.white70),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Delete',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await _supabase.from('mixtapes').delete().eq('id', mixId);
      if (!mounted) return;

      setState(() {
        _myMixes = _myMixes.where((m) => '${m['id']}' != mixId).toList();
        _sharedMixes = _sharedMixes
            .where((m) => '${m['id']}' != mixId)
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mixtape deleted.', style: GoogleFonts.outfit()),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete mixtape.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      final rows = await _supabase.from('Profiles').select('*').order('updated_at');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await _supabase.from('profiles').select('*').order('updated_at');
      return (rows as List).cast<Map<String, dynamic>>();
    }
  }

  String _displayName(Map<String, dynamic> row) {
    final metadata = row['user_metadata'];
    if (metadata is Map<String, dynamic>) {
      final fullName = metadata['full_name']?.toString().trim();
      if (fullName != null && fullName.isNotEmpty) return fullName;
      final name = metadata['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }

    final email = row['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;

    final username = row['username']?.toString() ?? 'Unknown user';
    return username;
  }

  String? _avatarUrl(Map<String, dynamic> row) {
    final direct = row['avatar_url']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final metadata = row['user_metadata'];
    if (metadata is Map<String, dynamic>) {
      final fromMeta = metadata['avatar_url']?.toString().trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      final picture = metadata['picture']?.toString().trim();
      if (picture != null && picture.isNotEmpty) return picture;
    }
    return null;
  }

  Widget _friendAvatar(Map<String, dynamic> row) {
    final avatarUrl = _avatarUrl(row);
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        backgroundColor: Colors.blueAccent.withAlpha(128),
        child: const Icon(Icons.person, color: Colors.white),
      );
    }
    return CircleAvatar(
      backgroundColor: Colors.blueAccent.withAlpha(90),
      backgroundImage: NetworkImage(avatarUrl),
      onBackgroundImageError: (_, __) {},
      child: const SizedBox.shrink(),
    );
  }

  Future<void> _appendSharedUserToMixtape({
    required String mixtapeId,
    required String receiverId,
  }) async {
    final rows = (await _supabase
        .from('mixtapes')
        .select('shared_users')
        .eq('id', mixtapeId)
        .limit(1)) as List<dynamic>;

    if (rows.isEmpty) return;
    final row = rows.first as Map<String, dynamic>;

    final existingRaw = row['shared_users'];
    final existing = <String>{};
    if (existingRaw is List) {
      for (final value in existingRaw) {
        final id = value?.toString() ?? '';
        if (id.isNotEmpty) existing.add(id);
      }
    }

    if (existing.contains(receiverId)) return;
    existing.add(receiverId);

    await _supabase
        .from('mixtapes')
        .update({'shared_users': existing.toList()}).eq('id', mixtapeId);
  }

  Future<void> _shareMix(Map<String, dynamic> mix) async {
    if (_sharing) return;

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || myId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign in to share mixes.', style: GoogleFonts.outfit())),
      );
      return;
    }

    final mixId = mix['id']?.toString() ?? '';
    if (mixId.isEmpty) return;

    setState(() => _sharing = true);
    try {
      final users = await _loadUsers();
      if (!mounted) return;

      final visibleUsers = users.where((u) => u['id']?.toString() != myId).toList();
      if (visibleUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No friends found to share with.', style: GoogleFonts.outfit())),
        );
        return;
      }

      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: const Color(0xFF16213E),
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Share mix with…',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visibleUsers.length,
                      itemBuilder: (context, index) {
                        final row = visibleUsers[index];
                        final receiverId = row['id']?.toString() ?? '';
                        final receiverName = _displayName(row);
                        return ListTile(
                          enabled: receiverId.isNotEmpty,
                          leading: _friendAvatar(row),
                          title: Text(
                            receiverName,
                            style: GoogleFonts.outfit(color: Colors.white),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                          onTap: receiverId.isEmpty ? null : () => Navigator.of(context).pop(row),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (chosen == null) return;
      final receiverId = chosen['id']?.toString() ?? '';
      final receiverName = _displayName(chosen);
      if (receiverId.isEmpty) return;

      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': receiverId,
        'content': 'mix{$mixId}',
      });
      await _appendSharedUserToMixtape(mixtapeId: mixId, receiverId: receiverId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared with $receiverName', style: GoogleFonts.outfit()),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share mix right now.', style: GoogleFonts.outfit())),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _buildMixCard(
    Map<String, dynamic> mix, {
    bool canDelete = false,
    String? sharedByLabel,
  }) {
    final title = (mix['title'] as String?)?.trim();
    final description = (mix['description'] as String?)?.trim();
    final isPublic = mix['is_public'] == true;
    final coverArtUrl = mix['cover_art_url'] as String?;
    final trackCount = _trackCountForMix(mix);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: coverArtUrl != null && coverArtUrl.isNotEmpty
                ? Image.network(coverArtUrl, fit: BoxFit.cover)
                : Container(
                    color: Colors.blueAccent.withAlpha(45),
                    child: const Icon(
                      Icons.queue_music_rounded,
                      color: Colors.white70,
                    ),
                  ),
          ),
        ),
        title: Text(
          title == null || title.isEmpty ? 'Untitled Mix' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              description == null || description.isEmpty
                  ? '$trackCount tracks'
                  : '$description · $trackCount tracks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            if (sharedByLabel != null)
              Text(
                'Shared by $sharedByLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.blueAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPublic
                      ? Colors.greenAccent.withAlpha(30)
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPublic ? 'Public' : 'Private',
                  style: GoogleFonts.outfit(
                    color: isPublic ? Colors.greenAccent : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        trailing: canDelete
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white70),
                    tooltip: 'Share mixtape',
                    onPressed: _sharing ? null : () => _shareMix(mix),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    tooltip: 'Delete mixtape',
                    onPressed: () => _confirmAndDeleteMix(mix),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: () {
          final playableTracks = _extractPlayableTracks(mix);
          if (playableTracks.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This mix has no playable tracks yet.',
                  style: GoogleFonts.outfit(),
                ),
              ),
            );
            return;
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WalkmanPlayerScreen(
                title: title == null || title.isEmpty ? 'Untitled Mix' : title,
                artist: description == null || description.isEmpty
                    ? '${playableTracks.length} track mix'
                    : description,
                mixTracks: playableTracks,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> mixes,
    required String emptyMessage,
    bool canDelete = false,
    bool showSharedBy = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        if (mixes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              emptyMessage,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          ...mixes.map((mix) {
            final creatorId = mix['creator_id']?.toString() ?? '';
            final sharedBy = showSharedBy ? _creatorNameById[creatorId] : null;
            return _buildMixCard(
              mix,
              canDelete: canDelete,
              sharedByLabel: sharedBy,
            );
          }),
      ],
    );
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
              onPressed: _loadMixes,
              child: Text(
                'Retry',
                style: GoogleFonts.outfit(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _loadMixes,
        color: Colors.blueAccent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Mixes',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _buildSection(
              title: 'My mixes',
              mixes: _myMixes,
              emptyMessage: 'No mixes yet. Create and save your first mix.',
              canDelete: true,
            ),
            const SizedBox(height: 22),
            _buildSection(
              title: 'Shared with you',
              mixes: _sharedMixes,
              emptyMessage: 'No shared mixes yet.',
              showSharedBy: true,
            ),
          ],
        ),
      );
    }

    return SafeArea(child: body);
  }
}
