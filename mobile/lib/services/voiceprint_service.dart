import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart' as ort;
import 'package:record/record.dart';

/// Biométrie vocale embarquée : exécute un modèle ONNX ECAPA-TDNN sur l'appareil
/// pour produire un embedding de voix (192 valeurs) depuis un enregistrement 16 kHz.
/// Si le modèle est absent (assets/models/ecapa_tdnn.onnx), le service est
/// indisponible et l'application retombe sur la vérification mot-clé seule.
class VoiceprintService {
  static const int sampleRate = 16000;
  static const String modelAsset = 'assets/models/ecapa_tdnn.onnx';

  ort.OrtSession? _session;
  bool _loading = false;
  bool _loaded = false;

  AudioRecorder? _recorder;
  final List<int> _samples = [];
  StreamSubscription<Uint8List>? _streamSub;

  /// Charge le modèle ONNX depuis les assets. Retourne false si indisponible.
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    if (_loading) return false;

    _loading = true;
    try {
      // Requis par onnxruntime >=1.1 : init du OrtEnv sinon Session créer lève
      try { ort.OrtEnv.instance.init(); } catch (_) {}
      final data = await rootBundle.load(modelAsset);
      // 84 Mo : chargement visible dans logcat si échec
      final options = ort.OrtSessionOptions()..setIntraOpNumThreads(1);
      _session = ort.OrtSession.fromBuffer(data.buffer.asUint8List(), options);
      _loaded = true;
    } catch (e) {
      // Garder l'erreur pour debug : flutter logs
      // ignore: avoid_print
      print('[Voiceprint] ensureLoaded échec: $e');
      _loaded = false;
    }
    _loading = false;
    return _loaded;
  }

  bool get isAvailable => _loaded;

  /// Démarre un enregistrement PCM 16 bits / 16 kHz / mono en streaming.
  /// La permission doit déjà avoir été accordée via PermissionService.microphone().
  Future<bool> startCapture() async {
    _samples.clear();
    final recorder = AudioRecorder();

    try {
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        bitRate: sampleRate * 16,
      ));
      _recorder = recorder;
      _streamSub = stream.listen(_appendChunk);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _appendChunk(Uint8List chunk) {
    final bytes = chunk.buffer.asUint8List();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _samples.add((bytes[i] | (bytes[i + 1] << 8)).toSigned(16));
    }
  }

  /// Arrête l'enregistrement puis calcule l'embedding de voix.
  /// Retourne null si le modèle est absent ou l'audio trop court (< 1 s).
  Future<List<double>?> stopAndEmbed() async {
    await _streamSub?.cancel();
    _streamSub = null;
    try {
      await _recorder?.stop();
    } catch (_) {
      // déjà arrêté
    }
    _recorder = null;

    if (!await ensureLoaded() || _samples.length < sampleRate) {
      return null;
    }

    final input = Float32List(_samples.length);
    for (var i = 0; i < _samples.length; i++) {
      input[i] = _samples[i] / 32768.0;
    }

    try {
      final tensor = ort.OrtValueTensor.createTensorWithDataList(
        [input],
        [1, input.length],
      );
      final outputs = _session!.run(
        ort.OrtRunOptions(),
        {_session!.inputNames.first: tensor},
        _session!.outputNames,
      );
      return _flattenEmbedding(outputs);
    } catch (_) {
      return null;
    }
  }

  List<double>? _flattenEmbedding(List<ort.OrtValue?> outputs) {
    final value = outputs.isNotEmpty ? outputs.first?.value : null;
    if (value is! List) return null;

    final flat = <double>[];
    for (final element in value) {
      if (element is List) {
        for (final inner in element) {
          if (inner is num) flat.add(inner.toDouble());
        }
      } else if (element is num) {
        flat.add(element.toDouble());
      }
    }
    return flat.isEmpty ? null : flat;
  }

  /// Import : calcule l'embedding depuis des bytes WAV (RIFF 16-bit PCM mono/stéréo). MP3/M4A non supportés.
  Future<List<double>?> embeddingFromWavBytes(Uint8List bytes) async {
    if (!await ensureLoaded()) return null;
    final samples = _decodeWav16kMono(bytes);
    if (samples.length < sampleRate) return null; // <1s
    final input = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) input[i] = samples[i] / 32768.0;
    try {
      final tensor = ort.OrtValueTensor.createTensorWithDataList([input], [1, input.length]);
      final outputs = _session!.run(ort.OrtRunOptions(), {_session!.inputNames.first: tensor}, _session!.outputNames);
      return _flattenEmbedding(outputs);
    } catch (e) {
      print('[Voiceprint] embeddingFromWavBytes échec: $e');
      return null;
    }
  }

  List<int> _decodeWav16kMono(Uint8List bytes) {
    if (bytes.length < 44) return _bytesToInt16(bytes);
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') return _bytesToInt16(bytes);
    int offset = 12;
    int fmtSampleRate = 16000;
    int fmtChannels = 1;
    int fmtBits = 16;
    int dataStart = -1;
    int dataLen = 0;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24);
      if (id == 'fmt ') {
        fmtChannels = bytes[offset + 10] | (bytes[offset + 11] << 8);
        fmtSampleRate = bytes[offset + 12] | (bytes[offset + 13] << 8) | (bytes[offset + 14] << 16) | (bytes[offset + 15] << 24);
        fmtBits = bytes[offset + 22] | (bytes[offset + 23] << 8);
      } else if (id == 'data') {
        dataStart = offset + 8;
        dataLen = size;
        break;
      }
      offset += 8 + size;
    }
    if (dataStart == -1 || fmtBits != 16) return [];
    final raw = bytes.sublist(dataStart, (dataStart + dataLen).clamp(0, bytes.length));
    final pcm = _bytesToInt16(raw, channels: fmtChannels);
    if (fmtSampleRate == sampleRate) return pcm;
    final ratio = fmtSampleRate / sampleRate;
    final outLen = (pcm.length / ratio).floor();
    final out = List<int>.filled(outLen, 0);
    for (int i = 0; i < outLen; i++) {
      final src = i * ratio;
      final idx = src.floor();
      final frac = src - idx;
      final a = pcm[idx.clamp(0, pcm.length - 1)];
      final b = pcm[(idx + 1).clamp(0, pcm.length - 1)];
      out[i] = (a * (1 - frac) + b * frac).round();
    }
    return out;
  }

  List<int> _bytesToInt16(Uint8List bytes, {int channels = 1}) {
    final out = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2 * channels) {
      int sum = 0;
      for (int c = 0; c < channels; c++) {
        final off = i + c * 2;
        if (off + 1 >= bytes.length) break;
        sum += (bytes[off] | (bytes[off + 1] << 8)).toSigned(16);
      }
      out.add((sum / channels).round());
    }
    return out;
  }

  /// Enregistre pendant [duration] puis retourne l'embedding, ou null.
  Future<List<double>?> captureEmbedding(Duration duration) async {
    if (!await startCapture()) return null;
    await Future<void>.delayed(duration);
    return stopAndEmbed();
  }

  /// Enrôlement robuste : capture [samples] embeddings et retourne leur moyenne
  /// (plus stable que 1 seule prise). L2-normalisée pour la comparaison cosinus.
  Future<List<double>?> captureAverageEmbedding({
    int samples = 3,
    Duration perSample = const Duration(seconds: 3),
    void Function(int current, int total)? onProgress,
  }) async {
    if (!await ensureLoaded()) return null;
    final List<List<double>> all = [];
    for (int i = 0; i < samples; i++) {
      onProgress?.call(i + 1, samples);
      final emb = await captureEmbedding(perSample);
      if (emb == null) return null;
      all.add(emb);
      // Petite pause entre les prises pour laisser l'utilisateur respirer
      if (i < samples - 1) await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return averageEmbeddings(all);
  }

  /// Moyenne élément-par-élément + normalisation L2 (pour cosine similarity).
  List<double> averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) throw ArgumentError('embeddings vide');
    final dim = embeddings.first.length;
    final avg = List<double>.filled(dim, 0);
    for (final emb in embeddings) {
      for (int i = 0; i < dim; i++) {
        avg[i] += emb[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      avg[i] /= embeddings.length;
    }
    // Normalisation L2 pour que cosine = dot product
    double norm = 0;
    for (final v in avg) norm += v * v;
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dim; i++) avg[i] /= norm;
    }
    return avg;
  }
}