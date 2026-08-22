import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Service de reconnaissance vocale OFFLINE via Vosk (100% embarqué, sans internet).
/// - Modèle français léger à placer dans `assets/models/vosk-model-small-fr-0.22.zip`
///   (~40 Mo, Apache 2.0, https://alphacephei.com/vosk/models )
/// - Si le modèle est absent, le service est indisponible et l'app retombe
///   automatiquement sur `speech_to_text` (Google, online).
/// - Supporte le *keyword spotting* via grammaire : on ne détecte que le mot de
///   sécurité => plus rapide et plus fiable pour le SOS.
class VoskService {
  static const String _assetModel = 'assets/models/vosk-model-small-fr-0.22.zip';
  static const String _fallbackAsset = 'assets/models/vosk-model-small-fr.zip';
  static const int _sampleRate = 16000;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _loader = ModelLoader();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _loaded = false;
  bool _loading = false;

  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;

  bool get isAvailable => _loaded && _model != null && _speechService != null;

  /// Charge le modèle depuis les assets (zip). Retourne false si absent.
  /// Si [securityWord] est fourni, le recognizer est optimisé pour ce mot-clé.
  Future<bool> ensureLoaded({String? securityWord}) async {
    if (_loaded) {
      // Re-créer le recognizer si la grammaire change (nouveau mot)
      if (securityWord != null) {
        try {
          await _createRecognizer(securityWord);
        } catch (_) {}
      }
      return true;
    }
    if (_loading) return false;
    _loading = true;
    try {
      String modelPath;
      try {
        modelPath = await _loader.loadFromAssets(_assetModel);
      } catch (_) {
        // fallback sans version
        modelPath = await _loader.loadFromAssets(_fallbackAsset);
      }
      _model = await _vosk.createModel(modelPath);
      await _createRecognizer(securityWord);
      // SpeechService uniquement sur Android (MethodChannel)
      if (Platform.isAndroid) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
      }
      _loaded = true;
      if (kDebugMode) debugPrint('[Vosk] modèle chargé: $modelPath (grammar: $securityWord)');
      return true;
    } catch (e) {
      _loaded = false;
      if (kDebugMode) debugPrint('[Vosk] indisponible: $e');
      return false;
    } finally {
      _loading = false;
    }
  }

  Future<void> _createRecognizer(String? securityWord) async {
    if (_model == null) return;
    // Nettoyage ancien recognizer
    _recognizer = null;
    final grammar = (securityWord != null && securityWord.trim().isNotEmpty)
        ? [securityWord.trim().toLowerCase(), '[unk]']
        : null;
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
      grammar: grammar,
    );
    // Si service déjà créé, le re-init est nécessaire (Android)
    if (_speechService != null && Platform.isAndroid) {
      try {
        await _speechService!.dispose();
      } catch (_) {}
      _speechService = await _vosk.initSpeechService(_recognizer!);
    }
  }

  /// Démarre l'écoute continue.
  /// [onKeyword] est appelé dès que le mot de sécurité est détecté (partial ou final).
  /// Retourne false si Vosk n'est pas disponible ou l'écoute n'a pas pu démarrer.
  Future<bool> startListening({
    required String securityWord,
    required void Function(String text) onPartial,
    required void Function(String text) onResult,
    void Function(String error)? onError,
  }) async {
    final ok = await ensureLoaded(securityWord: securityWord);
    if (!ok || _speechService == null) return false;

    // S'assurer que le recognizer est bien filtré sur le mot actuel
    final needsGrammar = _recognizer == null;
    if (needsGrammar) await _createRecognizer(securityWord);

    // Abonner les streams (éviter double abonnement)
    await _resultSub?.cancel();
    await _partialSub?.cancel();

    _partialSub = _speechService!.onPartial().listen((jsonStr) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final partial = (map['partial'] as String?)?.trim() ?? '';
        if (partial.isNotEmpty) {
          onPartial(partial);
          if (partial.toLowerCase().contains(securityWord.toLowerCase())) {
            onResult(partial);
          }
        }
      } catch (_) {
        onPartial(jsonStr);
      }
    });

    _resultSub = _speechService!.onResult().listen((jsonStr) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final text = (map['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          onResult(text);
        }
      } catch (_) {
        onResult(jsonStr);
      }
    });

    try {
      final started = await _speechService!.start(onRecognitionError: onError);
      return started == true;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _speechService?.stop();
    } catch (_) {}
    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = null;
    _partialSub = null;
  }

  Future<void> dispose() async {
    await stopListening();
    try {
      await _speechService?.dispose();
    } catch (_) {}
    _speechService = null;
    _recognizer = null;
    _model = null;
    _loaded = false;
  }

  /// Pour affichage UI : quel mode est actif
  String get modeLabel => isAvailable ? 'Vosk offline (FR)' : 'Google online (fallback)';
}
