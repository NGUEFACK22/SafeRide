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
  static const String modelAssetInt8 = 'assets/models/ecapa_tdnn_int8.onnx';

  ort.OrtSession? _session;
  bool _loading = false;
  bool _loaded = false;

  // Silero VAD (optionnel, 0,3 Mo) — filtrer bruit/silence avant ECAPA
  ort.OrtSession? _vadSession;
  bool _vadLoaded = false;
  bool _vadLoading = false;
  static const String vadAsset = 'assets/models/silero_vad.onnx';

  AudioRecorder? _recorder;
  final List<int> _samples = [];
  StreamSubscription<Uint8List>? _streamSub;

  /// Charge le modèle ONNX depuis les assets. Retourne false si indisponible.
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    if (_loading) return false;

    _loading = true;
    try {
      try { ort.OrtEnv.instance.init(); } catch (_) {}
      ByteData data;
      try {
        data = await rootBundle.load(modelAssetInt8);
        print('[Voiceprint] chargement quantifié int8 (${data.lengthInBytes/1e6} MB)');
      } catch (_) {
        data = await rootBundle.load(modelAsset);
        print('[Voiceprint] chargement FP32 (${data.lengthInBytes/1e6} MB)');
      }
      final options = ort.OrtSessionOptions()..setIntraOpNumThreads(1);
      _session = ort.OrtSession.fromBuffer(data.buffer.asUint8List(), options);
      _loaded = true;
    } catch (e) {
      print('[Voiceprint] ensureLoaded échec: $e');
      _loaded = false;
    }
    _loading = false;
    return _loaded;
  }

  bool get isAvailable => _loaded;

  Future<bool> ensureVadLoaded() async {
    if (_vadLoaded) return true;
    if (_vadLoading) return false;
    _vadLoading = true;
    try {
      try { ort.OrtEnv.instance.init(); } catch (_) {}
      final data = await rootBundle.load(vadAsset);
      final opts = ort.OrtSessionOptions()..setIntraOpNumThreads(1);
      _vadSession = ort.OrtSession.fromBuffer(data.buffer.asUint8List(), opts);
      _vadLoaded = true;
      print('[VAD] silero_vad chargé: inputs=${_vadSession!.inputNames} outputs=${_vadSession!.outputNames}');
    } catch (e) {
      print('[VAD] échec chargement silero: $e');
      _vadLoaded = false;
    }
    _vadLoading = false;
    return _vadLoaded;
  }

  /// Filtrage VAD : découpe en fenêtres 512 @16k, garde uniquement fenêtres avec prob >0,5.
  /// Si VAD indisponible ou tout filtré, retourne l'original (fallback).
  Future<List<int>> _applyVad(List<int> pcm) async {
    if (pcm.length < 512) return pcm;
    // Essayer Silero, sinon fallback énergie
    if (await ensureVadLoaded() && _vadSession != null) {
      try {
        return await _sileroFilter(pcm);
      } catch (e) {
        print('[VAD] sileroFilter échec fallback énergie: $e');
      }
    }
    return _energyVadFilter(pcm);
  }

  Future<List<int>> _sileroFilter(List<int> pcm) async {
    const win = 512;
    const sr = 16000;
    // États récurrents Silero [2,1,64] initialisés à 0
    var h = Float32List(2 * 1 * 64);
    var c = Float32List(2 * 1 * 64);
    final kept = <int>[];
    final inputNames = _vadSession!.inputNames;
    final outputNames = _vadSession!.outputNames;
    // Détection nommage : input / sr / h / c ou variantes
    String findInput(List<String> names, List<String> candidates) {
      for (final cand in candidates) {
        for (final n in names) if (n.toLowerCase().contains(cand)) return n;
      }
      return names.first;
    }
    final inAudio = findInput(inputNames, ['input', 'audio', 'wave']);
    final inSr = inputNames.firstWhere((n) => n.toLowerCase().contains('sr') || n.contains('sample'), orElse: () => inputNames.length > 1 ? inputNames[1] : '');
    final inH = inputNames.firstWhere((n) => n.toLowerCase() == 'h' || n.contains('h0'), orElse: () => '');
    final inC = inputNames.firstWhere((n) => n.toLowerCase() == 'c' || n.contains('c0'), orElse: () => '');

    for (int off = 0; off + win <= pcm.length; off += win) {
      final chunk = Float32List(win);
      for (int i = 0; i < win; i++) chunk[i] = pcm[off + i] / 32768.0;
      final inputs = <String, ort.OrtValue>{};
      inputs[inAudio] = ort.OrtValueTensor.createTensorWithDataList([chunk], [1, win]);
      if (inSr.isNotEmpty) inputs[inSr] = ort.OrtValueTensor.createTensorWithDataList([sr], [1]);
      if (inH.isNotEmpty) inputs[inH] = ort.OrtValueTensor.createTensorWithDataList(h, [2, 1, 64]);
      if (inC.isNotEmpty) inputs[inC] = ort.OrtValueTensor.createTensorWithDataList(c, [2, 1, 64]);
      final outs = _vadSession!.run(ort.OrtRunOptions(), inputs, outputNames);
      // Mise à jour états si modèle retourne h/c
      if (outs.length >= 3) {
        try {
          final oh = outs[1]?.value;
          final oc = outs[2]?.value;
          if (oh is List) h = _flattenToFloat32(oh);
          if (oc is List) c = _flattenToFloat32(oc);
        } catch (_) {}
      }
      final prob = _extractProb(outs.first);
      if (prob > 0.5) {
        kept.addAll(pcm.sublist(off, off + win));
      }
    }
    if (kept.length < sampleRate) return pcm; // trop agressif → garde original
    return kept;
  }

  double _extractProb(ort.OrtValue? out) {
    final v = out?.value;
    if (v is List && v.isNotEmpty) {
      final first = v[0];
      if (first is List && first.isNotEmpty && first[0] is num) return (first[0] as num).toDouble();
      if (first is num) return first.toDouble();
    }
    if (v is num) return v.toDouble();
    return 0;
  }

  Float32List _flattenToFloat32(dynamic v) {
    final flat = <double>[];
    void rec(dynamic x) {
      if (x is List) { for (final e in x) rec(e); } else if (x is num) flat.add(x.toDouble());
    }
    rec(v);
    return Float32List.fromList(flat);
  }

  /// Fallback VAD énergie : garde fenêtres dont RMS > -40dB
  List<int> _energyVadFilter(List<int> pcm) {
    const win = 512;
    final kept = <int>[];
    for (int off = 0; off + win <= pcm.length; off += win) {
      double sum = 0;
      for (int i = 0; i < win; i++) { final s = pcm[off + i] / 32768.0; sum += s * s; }
      final rms = math.sqrt(sum / win);
      final db = 20 * (math.log(rms + 1e-9) / math.ln10);
      if (db > -40) kept.addAll(pcm.sublist(off, off + win));
    }
    return kept.length >= sampleRate ? kept : pcm;
  }

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

    // VAD : filtrer silence/bruit avant ECAPA (30s → ~30s utiles)
    final filtered = await _applyVad(List<int>.from(_samples));
    final useSamples = filtered.length >= sampleRate ? filtered : _samples;

    final input = Float32List(useSamples.length);
    for (var i = 0; i < useSamples.length; i++) {
      input[i] = useSamples[i] / 32768.0;
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
      final emb = _flattenEmbedding(outputs);
      print('[Voiceprint] stopAndEmbed ${useSamples.length} samples (${_samples.length} bruts) → ${emb?.length} dim');
      return emb;
    } catch (e) {
      print('[Voiceprint] stopAndEmbed échec: $e');
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
    final filtered = await _applyVad(samples);
    final useSamples = filtered.length >= sampleRate ? filtered : samples;
    final input = Float32List(useSamples.length);
    for (var i = 0; i < useSamples.length; i++) input[i] = useSamples[i] / 32768.0;
    try {
      final tensor = ort.OrtValueTensor.createTensorWithDataList([input], [1, input.length]);
      final outputs = _session!.run(ort.OrtRunOptions(), {_session!.inputNames.first: tensor}, _session!.outputNames);
      final emb = _flattenEmbedding(outputs);
      print('[Voiceprint] wav ${useSamples.length}/${samples.length} samples → ${emb?.length} dim');
      return emb;
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

  /// Capture brute PCM (pour diarization fenêtrée) — retourne les samples 16k mono
  Future<List<int>?> capturePcm(Duration duration) async {
    if (!await startCapture()) return null;
    await Future<void>.delayed(duration);
    await _streamSub?.cancel();
    _streamSub = null;
    try { await _recorder?.stop(); } catch (_) {}
    _recorder = null;
    if (_samples.length < sampleRate) return null;
    return List<int>.from(_samples);
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

  /// Diarization légère : découpe PCM en fenêtres 3s hop 1,5s, calcule embedding/window
  /// et retourne le meilleur cosinus vs référence. Gère multi-locuteurs/bruit.
  Future<double> bestWindowCosine(List<int> pcm, List<double> reference) async {
    if (!await ensureLoaded()) return 0;
    final filtered = await _applyVad(pcm);
    final use = filtered.length >= sampleRate ? filtered : pcm;
    const winLen = 48000; // 3s @16k
    const hop = 24000; // 1,5s
    if (use.length < winLen) {
      final emb = await _embeddingForSamples(use);
      if (emb == null) return 0;
      return _cosine(emb, reference);
    }
    double best = 0;
    for (int off = 0; off + winLen <= use.length; off += hop) {
      final win = use.sublist(off, off + winLen);
      final emb = await _embeddingForSamples(win);
      if (emb == null) continue;
      final cos = _cosine(emb, reference);
      if (cos > best) best = cos;
    }
    return best;
  }

  Future<List<double>?> _embeddingForSamples(List<int> samples) async {
    if (samples.length < sampleRate) return null;
    final input = Float32List(samples.length);
    for (int i = 0; i < samples.length; i++) input[i] = samples[i] / 32768.0;
    try {
      final tensor = ort.OrtValueTensor.createTensorWithDataList([input], [1, input.length]);
      final outs = _session!.run(ort.OrtRunOptions(), {_session!.inputNames.first: tensor}, _session!.outputNames);
      return _flattenEmbedding(outs);
    } catch (_) {
      return null;
    }
  }

  Future<List<double>?> embeddingForWindow(List<int> pcm) => _embeddingForSamples(pcm);

  double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
    return dot / (math.sqrt(na) * math.sqrt(nb) + 1e-9);
  }
}