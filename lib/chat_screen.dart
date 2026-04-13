import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'walkman_player_screen.dart';

class _ChatData {
  const _ChatData({
    required this.messages,
    required this.mixtapeById,
  });

  final List<Map<String, dynamic>> messages;
  final Map<String, Map<String, dynamic>> mixtapeById;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  final String receiverId;
  final String receiverName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;
  String? _error;

  String? get _myUserId => _supabase.auth.currentUser?.id;

  static final RegExp _mixRefPattern = RegExp(r'^mix\{([^}]+)\}$');

  String? _extractMixtapeId(String content) {
    final match = _mixRefPattern.firstMatch(content.trim());
    if (match == null) return null;
    final id = (match.group(1) ?? '').trim();
    return id.isEmpty ? null : id;
  }

  Future<_ChatData> _loadChatData() async {
    final myId = _myUserId;
    if (myId == null || myId.isEmpty) {
      throw Exception('You must be signed in to view messages.');
    }

    final rows = await _supabase
        .from('messages')
        .select('message_id, sender_id, receiver_id, content, created_at')
        .or(
          'and(sender_id.eq.$myId,receiver_id.eq.${widget.receiverId}),and(sender_id.eq.${widget.receiverId},receiver_id.eq.$myId)',
        )
        .order('created_at', ascending: true);

    final messages = (rows as List).cast<Map<String, dynamic>>();
    final mixtapeIds = <String>{};
    for (final msg in messages) {
      final content = msg['content']?.toString() ?? '';
      final mixId = _extractMixtapeId(content);
      if (mixId != null) mixtapeIds.add(mixId);
    }

    final mixtapeById = <String, Map<String, dynamic>>{};
    if (mixtapeIds.isNotEmpty) {
      final mixtapeRows = await _supabase
          .from('mixtapes')
          .select('id, title, description, tracks, cover_art_url, cover_art_url')
          .inFilter('id', mixtapeIds.toList());
      for (final row in (mixtapeRows as List).cast<Map<String, dynamic>>()) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        mixtapeById[id] = row;
      }
    }

    return _ChatData(messages: messages, mixtapeById: mixtapeById);
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    await _sendRawContent(content, clearTextField: true);
  }

  Future<void> _sendRawContent(
    String content, {
    bool clearTextField = false,
  }) async {
    final myId = _myUserId;
    if (myId == null || myId.isEmpty) {
      setState(() => _error = 'You must be signed in to send a message.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': widget.receiverId,
        'content': content,
      });

      final mixtapeId = _extractMixtapeId(content);
      if (mixtapeId != null) {
        await _appendSharedUserToMixtape(
          mixtapeId: mixtapeId,
          receiverId: widget.receiverId,
        );
      }

      if (clearTextField) _messageController.clear();
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _appendSharedUserToMixtape({
    required String mixtapeId,
    required String receiverId,
  }) async {
    final rows = await _supabase
        .from('mixtapes')
        .select('shared_users')
        .eq('id', mixtapeId)
        .limit(1);

    if (rows is! List || rows.isEmpty) return;
    final row = rows.first;
    if (row is! Map<String, dynamic>) return;

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

  Future<List<Map<String, dynamic>>> _loadMyMixtapes() async {
    final myId = _myUserId;
    if (myId == null || myId.isEmpty) {
      throw Exception('You must be signed in to share mixtapes.');
    }

    final rows = await _supabase
        .from('mixtapes')
        .select('id, title, cover_art_url, cover_art_url')
        .eq('creator_id', myId)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _openMixtapePickerAndSend() async {
    if (_sending) return;

    try {
      final mixes = await _loadMyMixtapes();
      if (!mounted) return;

      if (mixes.isEmpty) {
        setState(() => _error = 'You do not have any mixtapes to share yet.');
        return;
      }

      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: const Color(0xFF16213E),
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Share a mixtape',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: mixes.length,
                      itemBuilder: (context, index) {
                        final mix = mixes[index];
                        final title = (mix['title'] ?? 'Untitled mixtape').toString();
                        final coverUrl =
                            (mix['cover_art_url'] ?? mix['cover_art_url'] ?? '')
                                .toString()
                                .trim();
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(mix),
                          leading: coverUrl.isEmpty
                              ? const CircleAvatar(
                                  backgroundColor: Colors.blueAccent,
                                  child: Icon(Icons.album, color: Colors.white),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    coverUrl,
                                    width: 42,
                                    height: 42,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                          title: Text(
                            title,
                            style: GoogleFonts.outfit(color: Colors.white),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
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
      final mixId = chosen['id']?.toString() ?? '';
      if (mixId.isEmpty) {
        setState(() => _error = 'Could not share that mixtape.');
        return;
      }

      await _sendRawContent('mix{$mixId}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildMessageBody({
    required Map<String, dynamic> msg,
    required bool isMine,
    required Map<String, Map<String, dynamic>> mixtapeById,
  }) {
    final content = msg['content']?.toString() ?? '';
    final mixId = _extractMixtapeId(content);
    if (mixId == null) {
      return Text(
        content,
        style: GoogleFonts.outfit(color: Colors.white),
      );
    }

    final mix = mixtapeById[mixId];
    final title = (mix?['title'] ?? 'Shared mixtape').toString();
    final coverUrl = (mix?['cover_art_url'] ?? mix?['cover_art_url'] ?? '').toString().trim();
    final tracks = mix == null ? const <WalkmanMixTrack>[] : _extractPlayableTracks(mix);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: tracks.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WalkmanPlayerScreen(
                    title: title,
                    artist: (mix?['description'] ?? '${tracks.length} track mix').toString(),
                    mixTracks: tracks,
                  ),
                ),
              );
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coverUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                coverUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (coverUrl.isNotEmpty) const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            mix == null
                ? 'Mixtape unavailable'
                : tracks.isEmpty
                    ? 'Mixtape has no playable tracks'
                    : 'Tap to open mixtape',
            style: GoogleFonts.outfit(
              color: isMine ? Colors.white70 : Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  List<WalkmanMixTrack> _extractPlayableTracks(Map<String, dynamic> mix) {
    final tracksPayload = mix['tracks'];
    if (tracksPayload is! Map<String, dynamic>) return const [];

    final rawTracks = tracksPayload['tracks'];
    if (rawTracks is! List) return const [];

    final playableTracks = <WalkmanMixTrack>[];
    for (final raw in rawTracks) {
      if (raw is! Map<String, dynamic>) continue;
      final fileKey = (raw['file_key'] ?? raw['fileKey'])?.toString() ?? '';
      if (fileKey.isEmpty) continue;

      final start = _asDouble(raw['start_seconds']);
      final end = _asDouble(raw['end_seconds']);
      if (end <= start) continue;

      playableTracks.add(
        WalkmanMixTrack(
          fileKey: fileKey,
          startSeconds: start,
          endSeconds: end,
          title: (raw['title'] ?? '').toString(),
          artist: (raw['artist'] ?? '').toString(),
          coverArtUrl: (raw['cover_art_url'] ?? raw['albumArtUrl'])?.toString(),
        ),
      );
    }

    return playableTracks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text(
          widget.receiverName,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<_ChatData>(
              future: _loadChatData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error loading chat: ${snapshot.error}',
                        style: GoogleFonts.outfit(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final data = snapshot.data;
                final messages = data?.messages ?? const <Map<String, dynamic>>[];
                final mixtapeById = data?.mixtapeById ?? const <String, Map<String, dynamic>>{};
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: GoogleFonts.outfit(color: Colors.white70),
                    ),
                  );
                }

                final myId = _myUserId;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg['sender_id']?.toString() == myId;

                    return Align(
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        decoration: BoxDecoration(
                          color: isMine ? Colors.blueAccent : const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _buildMessageBody(
                          msg: msg,
                          isMine: isMine,
                          mixtapeById: mixtapeById,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                _error!,
                style: GoogleFonts.outfit(color: Colors.redAccent),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        hintStyle: GoogleFonts.outfit(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF16213E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _openMixtapePickerAndSend,
                    icon: const Icon(Icons.add, color: Colors.blueAccent),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.blueAccent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
