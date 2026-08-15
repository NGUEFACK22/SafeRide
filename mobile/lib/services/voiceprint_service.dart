import 'dart:async';
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
      final data = await rootBundle.load(modelAsset);
      final options = ort.OrtSessionOptions()..setIntraOpNumThreads(2);
      _session = ort.OrtSession.fromBuffer(data.buffer.asUint8List(), options);
      _loaded = true;
    } catch (_) {
      _loaded = false;
    }
    _loading = false;
    return _loaded;
  }

  bool get isAvailable => _loaded;

  /// Démarre un enregistrement PCM 16 bits / 16 kHz / mono en streaming.
  Future<bool> startCapture() async {
    _samples.clear();
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return false;

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

  /// Enregistre pendant [duration] puis retourne l'embedding, ou null.
  Future<List<double>?> captureEmbedding(Duration duration) async {
    if (!await startCapture()) return null;
    await Future<void>.delayed(duration);
    return stopAndEmbed();
  }
}