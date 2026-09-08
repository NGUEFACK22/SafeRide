import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/voiceprint_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

/// Écran d'enrôlement vocal guidé, plein écran :
/// 1. Mot de sécurité (rappel + édition possible)
/// 2. 3 prises de 3 s avec anneau de progression, onde de niveau micro,
///    consigne dynamique et feedback qualité audio
/// 3. Réécoute du WAV, puis envoi de l'empreinte moyenne (192 dims)
///
/// Repli automatique : si le modèle ONNX est absent, token sha256 mot-clé.
class VoiceEnrollScreen extends StatefulWidget {
  const VoiceEnrollScreen({super.key, this.initialWord});

  final String? initialWord;

  @override
  State<VoiceEnrollScreen> createState() => _VoiceEnrollScreenState();
}

enum _EnrollPhase { word, recording, review, sending, done, error }

class _VoiceEnrollScreenState extends State<VoiceEnrollScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _voiceprint = VoiceprintService();

  late final TextEditingController _wordController;
  _EnrollPhase _phase = _EnrollPhase.word;
  String _statusText = '';
  String? _errorText;

  // Enregistrement
  static const int _takes = 3;
  static const Duration _takeDuration = Duration(seconds: 3);
  int _currentTake = 0;
  double _takeProgress = 0; // 0..1 pour la prise en cours
  Timer? _tickTimer;
  double _micLevel = 0; // 0..1 niveau micro instantané
  bool _modelAvailable = false;

  // Résultat
  List<double>? _embedding;
  String? _wavPath;
  List<double> _levelHistory = [];

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.initialWord ?? '');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);
    _voiceprint.ensureLoaded().then((ok) {
      if (mounted) setState(() => _modelAvailable = ok);
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _pulseController.dispose();
    _wordController.dispose();
    _voiceprint.onLevel = null;
    super.dispose();
  }

  bool get _wordValid {
    final w = _wordController.text.trim();
    return w.length >= 3 && w.length <= 40;
  }

  /// Token de repli sha256(mot:sel_device) — même formule que SosService,
  /// validé par le backend (64 hex) quand le modèle ONNX est absent.
  Future<String> _deviceToken(String word) async {
    final prefs = await SharedPreferences.getInstance();
    var salt = prefs.getString('voice_device_salt');
    if (salt == null) {
      final rnd = List<int>.generate(16, (_) => DateTime.now().microsecondsSinceEpoch % 256);
      salt = base64UrlEncode(rnd);
      await prefs.setString('voice_device_salt', salt);
    }
    return sha256.convert(utf8.encode('$word:$salt')).toString();
  }

  // ───────────────────────── Phase 1 : mot de sécurité ─────────────────────────

  Future<void> _startEnrollment() async {
    final word = _wordController.text.trim();
    if (!_wordValid) {
      setState(() => _errorText = 'Le mot doit contenir entre 3 et 40 caractères.');
      return;
    }
    _errorText = null;

    // Enregistrer le mot côté backend (non bloquant si hors-ligne).
    try {
      await _api.post('/voice/security-word', {'mot_securite': word});
    } catch (_) {}

    if (!_modelAvailable) {
      // Repli : token sha256(mot:sel_device) identique à SosService.voiceprintToken.
      setState(() {
        _phase = _EnrollPhase.sending;
        _statusText = 'Modèle vocal absent — enrôlement mot-clé seul…';
      });
      try {
        final token = await _deviceToken(word);
        await _api.post('/voice/enroll', {'empreinte': token});
        if (!mounted) return;
        setState(() => _phase = _EnrollPhase.done);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = _EnrollPhase.error;
          _errorText = friendlyError(e);
        });
      }
      return;
    }

    setState(() {
      _phase = _EnrollPhase.recording;
      _currentTake = 0;
      _levelHistory = [];
    });
    _recordTake(word);
  }

  // ───────────────────────── Phase 2 : prises vocales ─────────────────────────

  Future<void> _recordTake(String word) async {
    if (_currentTake >= _takes) {
      _finishRecording(word);
      return;
    }

    setState(() {
      _takeProgress = 0;
      _statusText = 'Prise ${_currentTake + 1}/$_takes — dites « $word »';
    });

    // Callback niveau micro pour l'onde visuelle + historique qualité.
    _voiceprint.onLevel = (level) {
      if (!mounted) return;
      setState(() => _micLevel = level);
      _levelHistory.add(level);
    };

    final ok = await _voiceprint.startCapture();
    if (!ok) {
      setState(() {
        _phase = _EnrollPhase.error;
        _errorText = 'Micro indisponible — vérifiez la permission microphone.';
      });
      return;
    }

    // Anneau : progression réelle de la prise (3 s).
    const tickMs = 100;
    final totalTicks = _takeDuration.inMilliseconds ~/ tickMs;
    var ticks = 0;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      ticks++;
      if (!mounted) return;
      setState(() => _takeProgress = ticks / totalTicks);
      if (ticks >= totalTicks) {
        t.cancel();
        _endTake(word);
      }
    });
  }

  Future<void> _endTake(String word) async {
    _tickTimer?.cancel();
    _voiceprint.onLevel = null;
    final embedding = await _voiceprint.stopAndEmbed();
    if (!mounted) return;

    if (embedding == null) {
      setState(() {
        _phase = _EnrollPhase.error;
        _errorText = 'Audio trop court ou inaudible — rapprochez-vous du micro et parlez plus fort.';
      });
      return;
    }

    if (_embedding == null) {
      _embedding = embedding;
    } else if (_embedding!.length == embedding.length) {
      for (int i = 0; i < _embedding!.length; i++) {
        _embedding![i] = (_embedding![i] * _currentTake + embedding[i]) / (_currentTake + 1);
      }
    }

    _currentTake++;
    if (_currentTake >= _takes) {
      _finishRecording(word);
      return;
    }

    // Petite pause entre les prises.
    setState(() {
      _micLevel = 0;
      _statusText = 'Prise $_currentTake/$_takes validée ✓ — préparez-vous…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _recordTake(word);
  }

  Future<void> _finishRecording(String word) async {
    // Qualité audio globale : niveau moyen trop faible = avertissement.
    final avgLevel = _levelHistory.isEmpty
        ? 0.0
        : _levelHistory.reduce((a, b) => a + b) / _levelHistory.length;
    final db = _voiceprint.lastCaptureDb();

    // Sauver le WAV pour réécoute.
    final wavPath = await _voiceprint.saveLastCaptureAsWav();

    if (!mounted) return;
    setState(() {
      _phase = _EnrollPhase.review;
      _statusText = avgLevel < 0.02
          ? 'Niveau sonore faible (${db.toStringAsFixed(0)} dB) — réenregistrez dans un endroit calme si la reconnaissance semble mauvaise.'
          : 'Enregistrement de bonne qualité (${db.toStringAsFixed(0)} dB)';
      _wavPath = wavPath;
    });
  }

  // ───────────────────────── Phase 3 : validation ─────────────────────────

  Future<void> _confirmAndSend() async {
    setState(() {
      _phase = _EnrollPhase.sending;
      _statusText = 'Calcul de l\'empreinte moyenne…';
    });

    final word = _wordController.text.trim();
    final finalEmbedding = _embedding != null && _embedding!.length == 192
        ? _embedding
        : null;

    try {
      if (finalEmbedding != null) {
        // L2-normalisation de l'empreinte moyenne (cohérence backend cosinus).
        double sq = 0;
        for (final v in finalEmbedding) {
          sq += v * v;
        }
        final norm = sq <= 0 ? 1.0 : math.sqrt(sq);
        final normalized = [for (final v in finalEmbedding) v / norm];
        setState(() => _statusText = 'Envoi de l\'empreinte (192 dims)…');
        await _api.post('/voice/enroll', {'empreinte': normalized});
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('voice_last_embedding', normalized.join(','));
      } else {
        // Repli token.
        setState(() => _statusText = 'Mode léger — envoi du token…');
        final token = await _deviceToken(word);
        await _api.post('/voice/enroll', {'empreinte': token});
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice_security_word', word);

      if (!mounted) return;
      setState(() {
        _phase = _EnrollPhase.done;
        _statusText = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _EnrollPhase.error;
        _errorText = friendlyError(e);
      });
    }
  }

  void _restart() {
    setState(() {
      _phase = _EnrollPhase.word;
      _embedding = null;
      _wavPath = null;
      _errorText = null;
      _statusText = '';
      _currentTake = 0;
      _takeProgress = 0;
      _micLevel = 0;
      _levelHistory = [];
    });
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Enrôlement vocal', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _bodyForPhase(),
        ),
      ),
    );
  }

  Widget _bodyForPhase() {
    switch (_phase) {
      case _EnrollPhase.word:
        return _wordPhase();
      case _EnrollPhase.recording:
        return _recordingPhase();
      case _EnrollPhase.review:
        return _reviewPhase();
      case _EnrollPhase.sending:
        return _spinnerPhase('Envoi en cours…', _statusText);
      case _EnrollPhase.done:
        return _donePhase();
      case _EnrollPhase.error:
        return _errorPhase();
    }
  }

  // Phase 1 : mot
  Widget _wordPhase() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlueBadge,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.record_voice_over, size: 36, color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Configurez votre SOS vocal',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Votre voix devient votre alerte. En cas de danger, prononcez votre mot de sécurité :'
                  ' la reconnaissance vocale (Vosk) + votre empreinte vocale (biométrie ECAPA) déclenchent le SOS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textGrey, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. Votre mot de sécurité', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark)),
                const SizedBox(height: 4),
                const Text('Ce mot devra être prononcé pour déclencher l\'alerte. Choisissez-le simple à retenir.', style: TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                const SizedBox(height: 12),
                TextField(
                  controller: _wordController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'Mot de sécurité',
                    hintText: 'Ex : au secours, aidez-moi…',
                    prefixIcon: const Icon(Icons.mic),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    errorText: _errorText,
                    counterText: '${_wordController.text.length}/40',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _modelAvailable ? Icons.check_circle : Icons.info_outline,
                      size: 14,
                      color: _modelAvailable ? AppTheme.successText : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _modelAvailable
                            ? 'Biométrie vocale active (ECAPA-TDNN embarquée) — 3 prises de 3 s.'
                            : 'Modèle vocal absent — l\'enrôlement se fera en mode mot-clé seul.',
                        style: TextStyle(fontSize: 11, color: _modelAvailable ? AppTheme.successText : Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _wordValid ? _startEnrollment : null,
            icon: const Icon(Icons.mic),
            label: const Text('Commencer l\'enrôlement', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // Phase 2 : enregistrement
  Widget _recordingPhase() {
    final word = _wordController.text.trim();
    final isLastTake = _currentTake == _takes - 1;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Indicateur des 3 prises
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_takes, (i) {
              final done = i < _currentTake;
              final active = i == _currentTake;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _takeDot(done: done, active: active, index: i),
              );
            }),
          ),
          const SizedBox(height: 32),

          // Anneau de progression
          AnimatedBuilder(
            animation: _pulseController,
            builder: (ctx, _) {
              final pulse = (_micLevel > 0.05 && _takeProgress > 0 && _takeProgress < 1)
                  ? 1.0 + (_micLevel * 0.15 * _pulseController.value)
                  : 1.0;
              return Transform.scale(
                scale: pulse,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _takeProgress <= 0 ? 0.02 : _takeProgress,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        color: AppTheme.primaryBlue,
                        backgroundColor: AppTheme.lightBlueBadge,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _takeProgress >= 1 ? Icons.check : Icons.mic,
                            size: 52,
                            color: _micLevel > 0.03 ? AppTheme.primaryBlue : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _takeProgress >= 1
                                ? 'Analyse…'
                                : '${((_takeDuration.inSeconds) * (1 - _takeProgress)).ceil()} s',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          Text(
            'Dites « $word »',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            isLastTake ? 'Dernière prise — encore une fois' : 'Voix normale, à 15-20 cm du micro',
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
          ),
          const SizedBox(height: 28),

          // Onde de niveau micro
          _MicWave(level: _micLevel, active: _takeProgress > 0 && _takeProgress < 1),
          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: () {
              _tickTimer?.cancel();
              _voiceprint.onLevel = null;
              try { _voiceprint.stopAndEmbed(); } catch (_) {}
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Annuler l\'enrôlement'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _takeDot({required bool done, required bool active, required int index}) {
    return Container(
      width: active ? 34 : done ? 30 : 26,
      height: active ? 34 : done ? 30 : 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppTheme.successText
            : active
                ? AppTheme.primaryBlue
                : Colors.grey.shade300,
        boxShadow: active
            ? [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 2)]
            : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : active
              ? const Icon(Icons.mic, size: 15, color: Colors.white)
              : null,
    );
  }

  // Phase 3 : validation
  Widget _reviewPhase() {
    final isAvg = _embedding != null && _embedding!.length == 192;
    final tooQuiet = _levelHistory.isNotEmpty &&
        (_levelHistory.reduce((a, b) => a + b) / _levelHistory.length) < 0.02;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: tooQuiet ? Colors.orange.shade50 : AppTheme.successBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              tooQuiet ? Icons.warning_amber_rounded : Icons.verified,
              size: 44,
              color: tooQuiet ? Colors.orange.shade700 : AppTheme.successText,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tooQuiet ? 'Enregistrement capté mais faible' : 'Empreinte vocale prête !',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            tooQuiet
                ? 'Le niveau sonore détecté est faible. Vous pouvez continuer, mais pour une meilleure reconnaissance, réenregistrez dans un environnement calme.'
                : '3 prises de voix moyennées • ${isAvg ? '192 dimensions' : 'mode léger'} • prête à être envoyée.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(_statusText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _confirmAndSend,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Valider et activer le SOS vocal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.successText,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _wavPath == null ? null : _playLastRecording,
                icon: const Icon(Icons.play_circle_outline, size: 20),
                label: const Text('R��couter'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('R�enregistrer'),
                style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// R��coute du dernier enregistrement WAV via le lecteur audio.
  Future<void> _playLastRecording() async {
    if (_wavPath == null) return;
    try {
      final player = AudioPlayer();
      await player.setFilePath(_wavPath!);
      await player.play();
    } catch (_) {}
  }

  Widget _spinnerPhase(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppTheme.textGrey)),
          ],
        ],
      ),
    );
  }

  Widget _donePhase() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(color: AppTheme.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 56, color: AppTheme.successText),
          ),
          const SizedBox(height: 24),
          const Text(
            'SOS vocal activé !',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textDark),
          ),
          const SizedBox(height: 10),
          Text(
            'En cas de danger, dites « ${_wordController.text.trim()} ».\n'
            'Reconnaissance Vosk offline + biométrie vocale vérifieront que c\'est bien vous.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.6),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Terminer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _errorPhase() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: Icon(Icons.error_outline, size: 44, color: Colors.red.shade700),
          ),
          const SizedBox(height: 20),
          const Text('Enrôlement interrompu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          Text(
            _errorText ?? 'Une erreur est survenue.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.replay),
            label: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

/// Onde visuelle simple du niveau micro (5 barres animées).
class _MicWave extends StatelessWidget {
  const _MicWave({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bars = List.generate(5, (i) {
      final distance = (i - 2).abs();
      final factor = 1.0 - (distance * 0.22);
      final height = active ? (0.12 + level * 0.88 * factor).clamp(0.08, 1.0) : 0.08;
      return height;
    });

    return SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: bars
            .map((h) => AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: (h * 56).clamp(6.0, 56.0),
                  decoration: BoxDecoration(
                    color: level > 0.03 ? AppTheme.primaryBlue : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
