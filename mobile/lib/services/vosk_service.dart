import 'dart:async';

/// STUB temporaire — Vosk désactivé pour build (AGP namespace + permission_handler v1)
/// L'app retombe automatiquement sur speech_to_text (Google) sans crash.
/// Réactivation prévue après fix AGP/permission_handler.
class VoskService {
  bool get isAvailable => false;
  String get modeLabel => 'Google online (fallback — Vosk en attente de fix)';

  Future<bool> ensureLoaded({String? securityWord}) async => false;

  Future<bool> startListening({
    required String securityWord,
    required void Function(String text) onPartial,
    required void Function(String text) onResult,
    void Function(String error)? onError,
  }) async =>
      false;

  Future<void> stopListening() async {}

  Future<void> dispose() async {}
}
