import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/mixtape_payload.dart';
import 'services/signed_audio_url_service.dart';
import 'services/transition_validation_service.dart';
import 'services/waveform_service.dart';
import 'widgets/transition_editor_card.dart';
import 'widgets/waveform_trim_editor.dart';

class MixtapeEditorScreen extends StatefulWidget {
  const MixtapeEditorScreen({super.key, required this.songs, this.onSaved});

  /// Payload passed from Create screen.
  /// Each map should contain: id, title, artist, albumArtUrl, fileKey, durationSeconds.
  final List<Map<String, dynamic>> songs;
  final VoidCallback? onSaved;

  @override
  State<MixtapeEditorScreen> createState() => _MixtapeEditorScreenState();
}

class _MixtapeEditorScreenState extends State<MixtapeEditorScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SignedAudioUrlService _signedAudioUrlService = SignedAudioUrlService();
  final TransitionValidationService _transitionValidationService =
      const TransitionValidationService();
  final WaveformService _waveformService = WaveformService();
  final AudioPlayer _player = AudioPlayer();

  late List<_MixtapeClip> _clips;
  int _selectedIndex = -1;

  // Zoom into timeline while dragging start/end for precision
  int _zoomedClipIndex = -1;
  double _zoomMin = 0;
  double _zoomMax = 300;

  // Playback state
  bool _isPlaying = false;
  bool _isMixMode = true;
  double _mixPositionSeconds = 0;
  int _currentIndexPlaying = 0;
  int? _singleSongIndex;
  bool _isSavingMixtape = false;
  bool _showTransitionPalette = false;
  bool _isLoadingSongLibrary = false;
  List<_LibrarySong> _songLibrary = const [];
  final Map<String, WaveformData> _waveformByClipId = {};
  final Set<String> _loadingWaveforms = {};

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<int?>? _indexSub;

  double get _totalTrimmedDuration =>
      _clips.fold(0, (sum, c) => sum + c.trimmedDuration);

  @override
  void initState() {
    super.initState();
    _clips = widget.songs.map(_MixtapeClip.fromMap).toList();
    for (final clip in _clips) {
      _ensureWaveformLoaded(clip);
    }

    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      _currentIndexPlaying = idx;
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (!_isPlaying || _clips.isEmpty) return;
      final localSeconds = pos.inMilliseconds / 1000.0;

      if (_isMixMode) {
        final offsetBefore = _offsetUntil(_currentIndexPlaying);
        final currentClip = _clips[_currentIndexPlaying];
        final effectiveLocal = localSeconds.clamp(
          0.0,
          currentClip.trimmedDuration,
        );
        final mixPos = (offsetBefore + effectiveLocal).clamp(
          0.0,
          _totalTrimmedDuration,
        );

        if (mounted) {
          setState(() {
            _mixPositionSeconds = mixPos;
          });
        }
      } else if (_singleSongIndex != null) {
        final idx = _singleSongIndex!;
        final clip = _clips[idx];
        final offsetBefore = _offsetUntil(idx);
        final effectiveLocal = localSeconds.clamp(0.0, clip.trimmedDuration);
        final mixPos = (offsetBefore + effectiveLocal).clamp(
          0.0,
          _totalTrimmedDuration,
        );

        if (mounted) {
          setState(() {
            _mixPositionSeconds = mixPos;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _indexSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  double _offsetUntil(int clipIndex) {
    double sum = 0;
    for (int i = 0; i < clipIndex && i < _clips.length; i++) {
      sum += _clips[i].trimmedDuration;
    }
    return sum;
  }

  Future<void> _ensureWaveformLoaded(_MixtapeClip clip) async {
    if (_waveformByClipId.containsKey(clip.id) ||
        _loadingWaveforms.contains(clip.id)) {
      return;
    }
    _loadingWaveforms.add(clip.id);
    final model = clip.toPayloadModel(position: 0);
    final data = await _waveformService.loadForClip(model);
    if (!mounted) return;
    setState(() {
      _waveformByClipId[clip.id] = data;
      _loadingWaveforms.remove(clip.id);
    });
  }

  void _onTransitionChanged(int index, ClipTransition transition) {
    if (index < 0 || index >= _clips.length) return;
    setState(() {
      _clips[index].transitionToNext = transition;
    });
  }

  String _transitionLabel(ClipTransition transition) {
    return switch (transition.type) {
      TransitionType.hardCut => 'Hard cut',
      TransitionType.fade =>
        'Fade (${transition.fadeOutSeconds.toStringAsFixed(1)}s out / ${transition.fadeInSeconds.toStringAsFixed(1)}s in)',
      TransitionType.crossfade =>
        'Crossfade (${transition.crossfadeSeconds.toStringAsFixed(1)}s)',
    };
  }

  ClipTransition _defaultTransitionForType(TransitionType type) {
    return switch (type) {
      TransitionType.hardCut => const ClipTransition.hardCut(),
      TransitionType.fade => const ClipTransition(
        type: TransitionType.fade,
        fadeOutSeconds: 1.0,
        fadeInSeconds: 1.0,
      ),
      TransitionType.crossfade => const ClipTransition(
        type: TransitionType.crossfade,
        crossfadeSeconds: 1.0,
      ),
    };
  }

  Future<void> _loadSongLibraryIfNeeded() async {
    if (_songLibrary.isNotEmpty || _isLoadingSongLibrary) return;
    _isLoadingSongLibrary = true;
    try {
      final rows = await _supabase
          .from('songs')
          .select(
            'id, title, artist, album_art_url, file_key, duration_seconds',
          )
          .order('title');
      final parsed = (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(_LibrarySong.fromMap)
          .where((s) => s.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _songLibrary = parsed;
      });
    } catch (_) {
      // Keep picker optional. If loading fails, we show an inline message.
    } finally {
      _isLoadingSongLibrary = false;
    }
  }

  Future<void> _openQuickAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.library_music_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  'Add songs',
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                subtitle: Text(
                  'Append more songs to this mixtape.',
                  style: GoogleFonts.outfit(color: Colors.white70),
                ),
                onTap: () => Navigator.of(ctx).pop('songs'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  _showTransitionPalette
                      ? 'Hide transition palette'
                      : 'Show transition palette',
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                subtitle: Text(
                  'Drag transition chips between songs.',
                  style: GoogleFonts.outfit(color: Colors.white70),
                ),
                onTap: () => Navigator.of(ctx).pop('transitions'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'songs') {
      await _openAddSongsSheet();
    } else if (choice == 'transitions') {
      setState(() {
        _showTransitionPalette = !_showTransitionPalette;
      });
    }
  }

  Future<void> _openAddSongsSheet() async {
    await _loadSongLibraryIfNeeded();
    if (!mounted) return;

    final existingIds = _clips.map((c) => c.id).toSet();
    final available = _songLibrary
        .where((s) => !existingIds.contains(s.id))
        .toList();
    final selected = <String>{};
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final visible = available
                .where((song) {
                  if (query.trim().isEmpty) return true;
                  final q = query.toLowerCase();
                  return song.title.toLowerCase().contains(q) ||
                      song.artist.toLowerCase().contains(q);
                })
                .toList(growable: false);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(
                    children: [
                      Text(
                        'Add Songs',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (v) => setSheetState(() => query = v),
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search song or artist',
                          hintStyle: GoogleFonts.outfit(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white54,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _isLoadingSongLibrary
                            ? const Center(child: CircularProgressIndicator())
                            : visible.isEmpty
                            ? Center(
                                child: Text(
                                  'No songs available to add.',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white70,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (_, i) {
                                  final song = visible[i];
                                  final isChecked = selected.contains(song.id);
                                  return CheckboxListTile(
                                    value: isChecked,
                                    activeColor: Colors.blueAccent,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                      song.title,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      song.artist,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setSheetState(() {
                                        if (v == true) {
                                          selected.add(song.id);
                                        } else {
                                          selected.remove(song.id);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.outfit(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () {
                                      final add = available
                                          .where((s) => selected.contains(s.id))
                                          .map(
                                            (s) =>
                                                _MixtapeClip.fromMap(s.toMap()),
                                          )
                                          .toList(growable: false);
                                      setState(() {
                                        _clips.addAll(add);
                                      });
                                      for (final clip in add) {
                                        _ensureWaveformLoaded(clip);
                                      }
                                      Navigator.of(ctx).pop();
                                    },
                              child: Text(
                                'Add selected',
                                style: GoogleFonts.outfit(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _buildSongUrl(_MixtapeClip clip) async {
    return _signedAudioUrlService.signedSongUrl(clip.fileKey);
  }

  AudioSource _buildClipSource(_MixtapeClip clip) {
    final uri = Uri.parse(clip.url!);
    return ClippingAudioSource(
      start: Duration(milliseconds: (clip.startSeconds * 1000).round()),
      end: Duration(milliseconds: (clip.endSeconds * 1000).round()),
      child: AudioSource.uri(uri),
    );
  }

  /// Fetches fresh signed URLs for all clips. Signed URLs expire after 5 minutes,
  /// so we always refetch before playing to avoid playback failing "after a while".
  Future<void> _ensureUrls() async {
    for (final clip in _clips) {
      final url = await _buildSongUrl(clip);
      clip.url = url;
    }
  }

  Future<void> _playMix() async {
    if (_clips.isEmpty) return;

    await _ensureUrls();
    final sources = _clips
        .where((c) => c.url != null)
        .map(_buildClipSource)
        .toList();
    if (sources.isEmpty) return;

    try {
      await _player.stop();
      await _player.setAudioSource(ConcatenatingAudioSource(children: sources));
      setState(() {
        _isPlaying = true;
        _isMixMode = true;
        _currentIndexPlaying = 0;
        _singleSongIndex = null;
      });
      _player.play();
    } catch (_) {
      _stopPlayback();
    }
  }

  Future<void> _playSingle(int index) async {
    if (_clips.isEmpty) return;
    await _ensureUrls();

    final clip = _clips[index];
    if (clip.url == null) return;

    try {
      await _player.stop();
      await _player.setAudioSource(_buildClipSource(clip));
      setState(() {
        _isPlaying = true;
        _isMixMode = false;
        _currentIndexPlaying = 0;
        _singleSongIndex = index;
        _mixPositionSeconds = _offsetUntil(index);
      });
      _player.play();
    } catch (_) {
      _stopPlayback();
    }
  }

  Future<void> _seekInMix(double seconds) async {
    if (_clips.isEmpty) return;
    final target = seconds.clamp(0.0, _totalTrimmedDuration);

    double acc = 0;
    int idx = 0;
    for (; idx < _clips.length; idx++) {
      final len = _clips[idx].trimmedDuration;
      if (target < acc + len) break;
      acc += len;
    }
    if (idx >= _clips.length) {
      idx = _clips.length - 1;
      acc -= _clips[idx].trimmedDuration;
    }
    final local = target - acc;

    if (_isMixMode) {
      await _player.seek(
        Duration(milliseconds: (local * 1000).round()),
        index: idx,
      );
    } else {
      await _playSingle(idx);
      await _player.seek(Duration(milliseconds: (local * 1000).round()));
    }

    if (mounted) {
      setState(() {
        _mixPositionSeconds = target;
        _currentIndexPlaying = idx;
      });
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _singleSongIndex = null;
      });
    }
  }

  void _enterZoomForClip(int index) {
    if (index < 0 || index >= _clips.length) return;
    final clip = _clips[index];
    final fullMax = clip.originalDurationSeconds.toDouble().clamp(1, 600);
    final center = (clip.startSeconds + clip.endSeconds) / 2;
    const zoomPadding = 25.0;
    final halfWidth = (clip.trimmedDuration / 2).clamp(zoomPadding, 60.0);
    setState(() {
      _zoomedClipIndex = index;
      _zoomMin = (center - halfWidth).clamp(0.0, fullMax - 10).toDouble();
      _zoomMax = (center + halfWidth).clamp(10.0, fullMax).toDouble();
      if (_zoomMax - _zoomMin < 10) {
        _zoomMin = (_zoomMax - 10).clamp(0.0, fullMax).toDouble();
      }
    });
  }

  void _exitZoom() {
    setState(() {
      _zoomedClipIndex = -1;
    });
  }

  String _defaultMixtapeTitle() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'Mix $month/$day';
  }

  Map<String, dynamic> _buildTracksPayload() {
    final tracks = <MixtapeClip>[];
    for (int i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      final waveform = _waveformByClipId[clip.id];
      final descriptor = waveform == null
          ? clip.waveform
          : WaveformDescriptor(
              peakCacheKey: waveform.cacheKey,
              source: waveform.source,
              sampleCount: waveform.sampleCount,
              samples: waveform.peaks.take(200).toList(growable: false),
              sampleResolution: waveform.sampleCount,
            );
      tracks.add(
        clip.toPayloadModel(position: i, waveformOverride: descriptor),
      );
    }
    final validated = _transitionValidationService.normalizeClipTransitions(
      tracks,
    );
    return MixtapeTracksPayload(version: 2, tracks: validated).toJson();
  }

  Future<void> _saveMixtape({
    required String title,
    required String description,
    required bool isPublic,
  }) async {
    if (_clips.isEmpty || _isSavingMixtape) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please sign in again to save this mixtape.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSavingMixtape = true;
    });

    try {
      final trimmedTitle = title.trim();
      final trimmedDescription = description.trim();
      await _supabase.from('mixtapes').insert({
        'creator_id': user.id,
        'title': trimmedTitle.isEmpty ? _defaultMixtapeTitle() : trimmedTitle,
        'description': trimmedDescription.isEmpty ? null : trimmedDescription,
        'cover_art_url': _clips.first.albumArtUrl,
        'tracks': _buildTracksPayload(),
        'is_public': isPublic,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mixtape saved.', style: GoogleFonts.outfit())),
      );
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save mixtape. Please try again.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingMixtape = false;
        });
      }
    }
  }

  Future<void> _promptAndSaveMixtape() async {
    if (_clips.isEmpty || _isSavingMixtape) return;

    final titleController = TextEditingController(text: _defaultMixtapeTitle());
    final descriptionController = TextEditingController();
    bool isPublic = false;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16213E),
              title: Text(
                'Save Mixtape',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: GoogleFonts.outfit(color: Colors.white70),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      labelStyle: GoogleFonts.outfit(color: Colors.white70),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Switch(
                        value: isPublic,
                        onChanged: (value) {
                          setDialogState(() {
                            isPublic = value;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Make mix public',
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
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
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave == true) {
      await _saveMixtape(
        title: titleController.text,
        description: descriptionController.text,
        isPublic: isPublic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalTrimmedDuration > 0 ? _totalTrimmedDuration : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mixtape Editor',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          IconButton(
            onPressed: _isSavingMixtape ? null : _openQuickAddMenu,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add songs or transitions',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _isSavingMixtape ? null : _promptAndSaveMixtape,
              icon: _isSavingMixtape
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt_rounded),
              tooltip: 'Save mixtape',
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1A1A2E),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tap a song to edit. Trim with the waveform slider, then adjust the view range below it for precise cuts. Drag transition chips between songs to set boundaries.',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
          ),
          if (_showTransitionPalette)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  _TransitionChip(type: TransitionType.hardCut),
                  const SizedBox(width: 8),
                  _TransitionChip(type: TransitionType.fade),
                  const SizedBox(width: 8),
                  _TransitionChip(type: TransitionType.crossfade),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showTransitionPalette = false;
                      });
                    },
                    child: Text('Hide', style: GoogleFonts.outfit()),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _clips.isEmpty
                ? Center(
                    child: Text(
                      'No songs selected',
                      style: GoogleFonts.outfit(color: Colors.white54),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _clips.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _clips.removeAt(oldIndex);
                        _clips.insert(newIndex, item);
                        if (_selectedIndex == oldIndex) {
                          _selectedIndex = newIndex;
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final clip = _clips[index];
                      final isSelected = index == _selectedIndex;
                      final itemTotalOffset = _offsetUntil(index);
                      final isRowPlaying =
                          _isPlaying &&
                          !_isMixMode &&
                          _singleSongIndex == index;

                      return Container(
                        key: ValueKey(clip.id),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blueAccent
                                : Colors.white10,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            setState(() {
                              _selectedIndex = isSelected ? -1 : index;
                            });
                          },
                          minVerticalPadding: isSelected ? 12 : 4,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(
                                  Icons.drag_handle_rounded,
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child:
                                      clip.albumArtUrl != null &&
                                          clip.albumArtUrl!.isNotEmpty
                                      ? Image.network(
                                          clip.albumArtUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: Colors.blueAccent.withAlpha(
                                            60,
                                          ),
                                          child: const Icon(
                                            Icons.music_note_rounded,
                                            color: Colors.white70,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            clip.title,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clip.artist,
                                style: GoogleFonts.outfit(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Clip: ${_formatTime(clip.startSeconds)} - ${_formatTime(clip.endSeconds)} '
                                '(len ${_formatTime(clip.trimmedDuration)})',
                                style: GoogleFonts.outfit(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 6),
                                WaveformTrimEditor(
                                  peaks:
                                      _waveformByClipId[clip.id]?.peaks ??
                                      const <double>[
                                        0.2,
                                        0.4,
                                        0.3,
                                        0.6,
                                        0.5,
                                        0.3,
                                      ],
                                  clipStartSeconds: clip.startSeconds,
                                  clipEndSeconds: clip.endSeconds,
                                  viewportStartSeconds:
                                      _zoomedClipIndex == index ? _zoomMin : 0,
                                  viewportEndSeconds: _zoomedClipIndex == index
                                      ? _zoomMax
                                      : clip.originalDurationSeconds.toDouble(),
                                  songDurationSeconds: clip
                                      .originalDurationSeconds
                                      .toDouble(),
                                  onTrimChanged: (values) {
                                    setState(() {
                                      clip.startSeconds = values.start;
                                      clip.endSeconds = values.end;
                                    });
                                  },
                                  onViewportChanged: (values) {
                                    setState(() {
                                      _zoomedClipIndex = index;
                                      _zoomMin = values.start;
                                      _zoomMax = values.end;
                                    });
                                  },
                                ),
                                Row(
                                  children: [
                                    if (_zoomedClipIndex != index)
                                      TextButton.icon(
                                        onPressed: () =>
                                            _enterZoomForClip(index),
                                        icon: const Icon(
                                          Icons.zoom_in_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Zoom in',
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    if (_zoomedClipIndex == index)
                                      TextButton.icon(
                                        onPressed: _exitZoom,
                                        icon: const Icon(
                                          Icons.zoom_out_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Reset zoom',
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (_loadingWaveforms.contains(clip.id))
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                                if (_zoomedClipIndex == index)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Zoomed view enabled. Use Reset zoom to return.',
                                      style: GoogleFonts.outfit(
                                        color: Colors.blueAccent,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                              if (index < _clips.length - 1) ...[
                                const SizedBox(height: 8),
                                DragTarget<TransitionType>(
                                  onAcceptWithDetails: (details) {
                                    final transition =
                                        _defaultTransitionForType(details.data);
                                    _onTransitionChanged(index, transition);
                                  },
                                  builder: (context, candidates, rejected) {
                                    final highlight = candidates.isNotEmpty;
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        8,
                                        10,
                                        8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: highlight
                                            ? Colors.blueAccent.withValues(
                                                alpha: 0.25,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.04,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: highlight
                                              ? Colors.blueAccent
                                              : Colors.white12,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.compare_arrows_rounded,
                                            size: 16,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Between this song and next: ${_transitionLabel(clip.transitionToNext)}'
                                              '${highlight ? ' (drop to apply)' : ''}',
                                              style: GoogleFonts.outfit(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                if (isSelected)
                                  TransitionEditorCard(
                                    value: clip.transitionToNext,
                                    maxSeconds: clip.trimmedDuration,
                                    onChanged: (next) =>
                                        _onTransitionChanged(index, next),
                                  ),
                              ],
                              const SizedBox(height: 2),
                              const SizedBox(height: 2),
                              Text(
                                'Mix position: starts at ${_formatTime(itemTotalOffset)}',
                                style: GoogleFonts.outfit(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isRowPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              if (isRowPlaying) {
                                _stopPlayback();
                              } else {
                                _playSingle(index);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Full mixtape timeline
          if (_clips.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF16213E),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        iconSize: 30,
                        color: Colors.white,
                        icon: Icon(
                          _isPlaying && _isMixMode
                              ? Icons.stop_circle_rounded
                              : Icons.queue_music_rounded,
                        ),
                        onPressed: () {
                          if (_isPlaying && _isMixMode) {
                            _stopPlayback();
                          } else {
                            _playMix();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Full mixtape',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_formatTime(_mixPositionSeconds)} / ${_formatTime(total)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: Slider(
                      value: _mixPositionSeconds.clamp(0.0, total),
                      min: 0,
                      max: total,
                      onChanged: (value) {
                        _seekInMix(value);
                      },
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

class _MixtapeClip {
  _MixtapeClip({
    required this.id,
    required this.title,
    required this.artist,
    required this.originalDurationSeconds,
    this.albumArtUrl,
    this.fileKey,
    this.url,
    this.waveform,
    this.transitionToNext = const ClipTransition.hardCut(),
    double? startSeconds,
    double? endSeconds,
  }) : startSeconds = startSeconds ?? 0,
       endSeconds = endSeconds ?? originalDurationSeconds.toDouble();

  final String id;
  final String title;
  final String artist;
  final String? albumArtUrl;
  final String? fileKey;
  String? url;
  WaveformDescriptor? waveform;
  ClipTransition transitionToNext;
  final int originalDurationSeconds;

  double startSeconds;
  double endSeconds;

  double get trimmedDuration => (endSeconds - startSeconds).clamp(
    1.0,
    originalDurationSeconds.toDouble(),
  );

  factory _MixtapeClip.fromMap(Map<String, dynamic> map) {
    final duration =
        (map['durationSeconds'] as int?) ??
        (map['duration_seconds'] as int?) ??
        30;
    return _MixtapeClip(
      id: '${map['id']}',
      title: map['title'] as String? ?? 'Untitled',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      albumArtUrl:
          map['albumArtUrl'] as String? ?? map['album_art_url'] as String?,
      fileKey: map['fileKey'] as String? ?? map['file_key'] as String?,
      originalDurationSeconds: duration,
      waveform: WaveformDescriptor.fromJson(map['waveform']),
      transitionToNext:
          ClipTransition.fromJson(map['transition_to_next']) ??
          const ClipTransition.hardCut(),
    );
  }

  MixtapeClip toPayloadModel({
    required int position,
    WaveformDescriptor? waveformOverride,
  }) {
    return MixtapeClip(
      position: position,
      songId: id,
      title: title,
      artist: artist,
      albumArtUrl: albumArtUrl,
      fileKey: fileKey ?? '',
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      originalDurationSeconds: originalDurationSeconds,
      trimmedDurationSeconds: trimmedDuration,
      waveform: waveformOverride ?? waveform,
      transitionToNext: transitionToNext,
    ).normalized();
  }
}

class _LibrarySong {
  const _LibrarySong({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArtUrl,
    this.fileKey,
    this.durationSeconds = 30,
  });

  final String id;
  final String title;
  final String artist;
  final String? albumArtUrl;
  final String? fileKey;
  final int durationSeconds;

  factory _LibrarySong.fromMap(Map<String, dynamic> map) {
    final durationRaw = map['duration_seconds'];
    final duration = durationRaw is int
        ? durationRaw
        : (durationRaw is num ? durationRaw.round() : 30);
    return _LibrarySong(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled').toString(),
      artist: (map['artist'] ?? 'Unknown Artist').toString(),
      albumArtUrl: map['album_art_url'] as String?,
      fileKey: map['file_key'] as String?,
      durationSeconds: duration <= 0 ? 30 : duration,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artist': artist,
      'album_art_url': albumArtUrl,
      'file_key': fileKey,
      'duration_seconds': durationSeconds,
    };
  }
}

class _TransitionChip extends StatelessWidget {
  const _TransitionChip({required this.type});

  final TransitionType type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      TransitionType.hardCut => 'Hard cut',
      TransitionType.fade => 'Fade',
      TransitionType.crossfade => 'Crossfade',
    };
    return LongPressDraggable<TransitionType>(
      data: type,
      feedback: Material(
        color: Colors.transparent,
        child: _chip(label, isActive: true),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: _chip(label)),
      child: _chip(label),
    );
  }

  Widget _chip(String label, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.blueAccent
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _formatTime(double seconds) {
  final total = seconds.round().clamp(0, 359999);
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
}
