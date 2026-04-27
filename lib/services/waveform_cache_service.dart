import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class WaveformCacheEntry {
  const WaveformCacheEntry({
    required this.key,
    required this.peaks,
    required this.createdAtEpochMs,
    required this.source,
    this.sampleResolution,
  });

  final String key;
  final List<double> peaks;
  final int createdAtEpochMs;
  final String source;
  final int? sampleResolution;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': 1,
    'k': key,
    'p': peaks,
    't': createdAtEpochMs,
    's': source,
    'r': sampleResolution,
  };

  factory WaveformCacheEntry.fromJson(Map<String, dynamic> json) {
    final peaks = <double>[];
    final rawPeaks = json['p'];
    if (rawPeaks is List) {
      for (final v in rawPeaks) {
        if (v is num) peaks.add(v.toDouble().clamp(0.0, 1.0));
      }
    }
    return WaveformCacheEntry(
      key: (json['k'] ?? '').toString(),
      peaks: peaks,
      createdAtEpochMs: (json['t'] is num) ? (json['t'] as num).toInt() : 0,
      source: (json['s'] ?? 'unknown').toString(),
      sampleResolution: (json['r'] is num) ? (json['r'] as num).toInt() : null,
    );
  }
}

class WaveformCacheService {
  WaveformCacheService({
    this.maxEntries = 300,
    this.maxAge = const Duration(days: 30),
  });

  final int maxEntries;
  final Duration maxAge;
  final Map<String, WaveformCacheEntry> _memory = {};

  Future<WaveformCacheEntry?> get(String key) async {
    final cached = _memory[key];
    if (cached != null && !_isExpired(cached)) return cached;
    if (kIsWeb) return null;

    try {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final entry = WaveformCacheEntry.fromJson(decoded);
      if (_isExpired(entry)) {
        await file.delete();
        return null;
      }
      _memory[key] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(WaveformCacheEntry entry) async {
    _memory[entry.key] = entry;
    _trimMemory();
    if (kIsWeb) return;
    try {
      final file = await _fileFor(entry.key);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (_) {}
  }

  bool _isExpired(WaveformCacheEntry entry) {
    final created = DateTime.fromMillisecondsSinceEpoch(entry.createdAtEpochMs);
    return DateTime.now().difference(created) > maxAge;
  }

  void _trimMemory() {
    if (_memory.length <= maxEntries) return;
    final items = _memory.values.toList()
      ..sort((a, b) => a.createdAtEpochMs.compareTo(b.createdAtEpochMs));
    final removeCount = _memory.length - maxEntries;
    for (int i = 0; i < removeCount; i++) {
      _memory.remove(items[i].key);
    }
  }

  Future<File> _fileFor(String key) async {
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final dir = Directory('${Directory.systemTemp.path}/mixd_waveforms');
    return File('${dir.path}/$safe.json');
  }
}
