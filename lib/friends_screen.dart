import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_screen.dart';

// 4. Friends Page
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Friends',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: const _FriendsTab(),
    );
  }
}

class _FriendsTab extends StatefulWidget {
  const _FriendsTab();

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      final rows = await _supabase.from('Profiles').select('*').order('updated_at');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      // Fallback in case table was created in lowercase.
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

  String _subtitle(Map<String, dynamic> row) {
    final email = row['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    return 'No email available';
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

  Future<Map<String, DateTime>> _loadLastMessageTimes(List<String> friendIds) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || myId.isEmpty || friendIds.isEmpty) return const {};

    final latestByFriend = <String, DateTime>{};

    try {
      final sentRows = await _supabase
          .from('messages')
          .select('receiver_id, created_at')
          .eq('sender_id', myId)
          .inFilter('receiver_id', friendIds);

      for (final row in (sentRows as List).cast<Map<String, dynamic>>()) {
        final friendId = row['receiver_id']?.toString();
        final createdAtRaw = row['created_at']?.toString();
        if (friendId == null || createdAtRaw == null) continue;
        final createdAt = DateTime.tryParse(createdAtRaw);
        if (createdAt == null) continue;
        final previous = latestByFriend[friendId];
        if (previous == null || createdAt.isAfter(previous)) {
          latestByFriend[friendId] = createdAt;
        }
      }

      final receivedRows = await _supabase
          .from('messages')
          .select('sender_id, created_at')
          .eq('receiver_id', myId)
          .inFilter('sender_id', friendIds);

      for (final row in (receivedRows as List).cast<Map<String, dynamic>>()) {
        final friendId = row['sender_id']?.toString();
        final createdAtRaw = row['created_at']?.toString();
        if (friendId == null || createdAtRaw == null) continue;
        final createdAt = DateTime.tryParse(createdAtRaw);
        if (createdAt == null) continue;
        final previous = latestByFriend[friendId];
        if (previous == null || createdAt.isAfter(previous)) {
          latestByFriend[friendId] = createdAt;
        }
      }
    } catch (_) {
      return const {};
    }

    return latestByFriend;
  }

  String _lastMessageSubtitle(DateTime? lastMessageAt) {
    if (lastMessageAt == null) return 'No messages yet';

    final diff = DateTime.now().difference(lastMessageAt.toLocal());
    if (diff.inMinutes < 1) return 'Last message: within a minute';
    if (diff.inHours < 1) return 'Last message: ${diff.inMinutes} min ago';
    if (diff.inDays < 1) return 'Last message: ${diff.inHours} hr ago';
    final days = diff.inDays;
    return 'Last message: $days day${days == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final errorText = snapshot.error?.toString() ?? 'Unknown error';
          return Center(
            child: Text(
              'Error loading users: $errorText',
              style: GoogleFonts.outfit(color: Colors.white70),
            ),
          );
        }

        final users = snapshot.data ?? const <Map<String, dynamic>>[];
        final currentUserId = _supabase.auth.currentUser?.id;
        final visibleUsers = users
            .where((row) => row['id']?.toString() != currentUserId)
            .toList(growable: false);
        if (visibleUsers.isEmpty) {
          return Center(
            child: Text(
              'No users found',
              style: GoogleFonts.outfit(color: Colors.white70),
            ),
          );
        }

        final friendIds = visibleUsers
            .map((row) => row['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(growable: false);

        return FutureBuilder<Map<String, DateTime>>(
          future: _loadLastMessageTimes(friendIds),
          builder: (context, messageSnapshot) {
            final latestByFriend = messageSnapshot.data ?? const <String, DateTime>{};

            return ListView.builder(
              itemCount: visibleUsers.length,
              itemBuilder: (context, index) {
                final row = visibleUsers[index];
                final receiverId = row['id']?.toString() ?? '';
                final receiverName = _displayName(row);
                return ListTile(
                  onTap: receiverId.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                receiverId: receiverId,
                                receiverName: receiverName,
                              ),
                            ),
                          );
                        },
                  leading: _friendAvatar(row),
                  title: Text(
                    receiverName,
                    style: GoogleFonts.outfit(color: Colors.white),
                  ),
                  subtitle: Text(
                    _lastMessageSubtitle(latestByFriend[receiverId]),
                    style: GoogleFonts.outfit(color: Colors.white38),
                  ),
                  trailing: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.blueAccent,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

