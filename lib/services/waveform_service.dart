import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mixtape_payload.dart';
import 'signed_audio_url_service.dart';
import 'waveform_cache_service.dart';

class WaveformData {
  const WaveformData({
    required this.peaks,
    required this.durationSeconds,
    required this.sampleCount,
    required this.source,
    required this.cacheKey,
  });

  final List<double> peaks;
  final double durationSeconds;
  final int sampleCount;
  final String source;
  final String cacheKey;
}

class WaveformService {
  WaveformService({
    WaveformCacheService? cacheService,
    SignedAudioUrlService? signedAudioUrlService,
  }) : _cacheService = cacheService ?? WaveformCacheService(),
       _signedAudioUrlService =
           signedAudioUrlService ?? SignedAudioUrlService();

  final WaveformCacheService _cacheService;
  final SignedAudioUrlService _signedAudioUrlService;

  Future<WaveformData> loadForClip(MixtapeClip clip) async {
    final key = _cacheKeyForClip(clip);
    final cached = await _cacheService.get(key);
    if (cached != null && cached.peaks.isNotEmpty) {
      return WaveformData(
        peaks: cached.peaks,
        durationSeconds: clip.effectiveDuration,
        sampleCount: cached.peaks.length,
        source: cached.source,
        cacheKey: key,
      );
    }

    final fromMetadata = _fromDescriptor(clip, key);
    if (fromMetadata != null) {
      await _cacheService.put(
        WaveformCacheEntry(
          key: key,
          peaks: fromMetadata.peaks,
          createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          source: fromMetadata.source,
        ),
      );
      return fromMetadata;
    }

    final fromAudio = await _extractFromAudio(clip, key);
    if (fromAudio != null) {
      await _cacheService.put(
        WaveformCacheEntry(
          key: key,
          peaks: fromAudio.peaks,
          createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          source: fromAudio.source,
        ),
      );
      return fromAudio;
    }

    final generated = _generateFallback(clip, key);
    await _cacheService.put(
      WaveformCacheEntry(
        key: key,
        peaks: generated.peaks,
        createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        source: generated.source,
      ),
    );
    return generated;
  }

  WaveformData? _fromDescriptor(MixtapeClip clip, String key) {
    final descriptor = clip.waveform;
    if (descriptor == null) return null;
    final samples = descriptor.samples;
    if (samples == null || samples.isEmpty) return null;
    final normalized = _normalizeSamples(samples);
    return WaveformData(
      peaks: normalized,
      durationSeconds: clip.effectiveDuration,
      sampleCount: normalized.length,
      source: descriptor.source,
      cacheKey: key,
    );
  }

  Future<WaveformData?> _extractFromAudio(MixtapeClip clip, String key) async {
    if (kIsWeb || clip.fileKey.trim().isEmpty) return null;
    try {
      final signedUrl = await _signedAudioUrlService.signedSongUrl(
        clip.fileKey,
      );
      if (signedUrl == null || signedUrl.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/mixd_waveform_audio');
      await cacheDir.create(recursive: true);
      final audioFile = File('${cacheDir.path}/${_safeFileName(key)}.mp3');
      if (!await audioFile.exists()) {
        final response = await http.get(Uri.parse(signedUrl));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty)
          return null;
        await audioFile.writeAsBytes(response.bodyBytes, flush: true);
      }

      final waveFile = File('${cacheDir.path}/${_safeFileName(key)}.wave');
      Waveform? waveform;
      await for (final progress in JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
        zoom: const WaveformZoom.pixelsPerSecond(35),
      )) {
        waveform = progress.waveform ?? waveform;
      }
      waveform ??= await JustWaveform.parse(waveFile);
      final peaks = _peaksFromWaveform(waveform);
      if (peaks.isEmpty) return null;
      return WaveformData(
        peaks: peaks,
        durationSeconds: clip.effectiveDuration,
        sampleCount: peaks.length,
        source: 'local',
        cacheKey: key,
      );
    } catch (_) {
      return null;
    }
  }

  List<double> _peaksFromWaveform(Waveform waveform) {
    final pixels = waveform.length;
    if (pixels <= 0) return const [];
    final targetCount = pixels.clamp(80, 260);
    final step = (pixels / targetCount).clamp(1, 1024).toInt();
    final out = <double>[];
    for (int i = 0; i < pixels; i += step) {
      final min = waveform.getPixelMin(i);
      final max = waveform.getPixelMax(i);
      final amplitude = (max - min).abs().toDouble();
      // `flags == 0` indicates 16-bit style range, otherwise 8-bit style.
      final normalized = waveform.flags == 0
          ? (amplitude / 65535.0)
          : (amplitude / 255.0);
      out.add(normalized.clamp(0.02, 1.0));
    }
    return out;
  }

  WaveformData _generateFallback(MixtapeClip clip, String key) {
    final duration = clip.effectiveDuration <= 0 ? 1.0 : clip.effectiveDuration;
    final targetCount = duration < 20
        ? 100
        : duration < 60
        ? 180
        : 240;
    final seed = clip.fileKey.hashCode ^ clip.songId.hashCode ^ clip.position;
    final rng = Random(seed);
    final peaks = List<double>.generate(targetCount, (i) {
      final base = 0.25 + (sin(i / 9.0) + 1) * 0.25;
      final jitter = rng.nextDouble() * 0.4;
      return (base + jitter).clamp(0.05, 1.0);
    });
    return WaveformData(
      peaks: peaks,
      durationSeconds: duration,
      sampleCount: peaks.length,
      source: 'local',
      cacheKey: key,
    );
  }

  List<double> _normalizeSamples(List<double> raw) {
    if (raw.isEmpty) return const [0.2];
    final out = <double>[];
    for (final v in raw) {
      out.add(v.clamp(0.0, 1.0));
    }
    return out;
  }

  String _cacheKeyForClip(MixtapeClip clip) {
    final start = clip.startSeconds.toStringAsFixed(2);
    final end = clip.endSeconds.toStringAsFixed(2);
    return '${clip.fileKey}|$start|$end';
  }

  String _safeFileName(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
