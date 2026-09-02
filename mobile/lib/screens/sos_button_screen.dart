import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../utils/error_helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import '../services/whatsapp_service.dart';
import '../services/sos_service.dart';
import '../services/trip_service.dart';
import '../services/permission_service.dart';
import '../services/voiceprint_service.dart';
import '../services/vosk_service.dart';

class SosButtonScreen extends StatefulWidget {
  final Trip? trip;

  const SosButtonScreen({super.key, this.trip});

  @override
  State<SosButtonScreen> createState() => _SosButtonScreenState();
}

class _SosButtonScreenState extends State<SosButtonScreen> {
  final _sosService = SosService();
  final _voiceprint = VoiceprintService();
  final _tripService = TripService();
  final _vosk = VoskService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  Trip? _trip;
  bool _loading = false;
  bool _vocalMode = false;
  bool _hasActiveTrip = true;

  // État du profil vocal
  bool _enrolled = false;
  bool _voiceAvailable = false;
  bool _voskAvailable = false;
  String? _securityWord;
  final _wordController = TextEditingController();
  bool _listening = false;
  String _heard = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadActiveTrip();
    _loadProfile();
    _initVoiceprint();
  }

  /// Charge le trajet actif si aucun trajet n'a été passé (accès depuis l'accueil).
  Future<void> _loadActiveTrip() async {
    if (_trip != null) return;
    try {
      final trip = await _tripService.currentTrip();
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _hasActiveTrip = trip != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasActiveTrip = false);
    }
  }

  Future<void> _initVoiceprint() async {
    final available = await _voiceprint.ensureLoaded();
    if (mounted) setState(() => _voiceAvailable = available);
    // Tenter Vosk en arrière-plan (ne bloque pas l'UI)
    final voskOk = await _vosk.ensureLoaded(securityWord: _securityWord);
    if (mounted) setState(() => _voskAvailable = voskOk);
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _securityWord = prefs.getString('voice_security_word');
    _wordController.text = _securityWord ?? '';
    try {
      final data = await _sosService.profile();
      final profile = data['profile'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() => _enrolled = profile != null && (profile['enrolled'] == true));
        if (profile != null && profile['mot_securite'] != null) {
          _wordController.text = profile['mot_securite'] as String;
          _securityWord = profile['mot_securite'] as String;
        }
      }
    } catch (_) {
      // hors-ligne : on se base sur le cache local
    }
  }

  Future<void> _enroll() async {
    final word = (_wordController.text.trim().isNotEmpty ? _wordController.text.trim() : _securityWord?.trim());
    if (word == null || word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Veuillez saisir un mot de sécurité (3-40 caractères)')));
      return;
    }
    if (word.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mot trop court (min 3 caractères)')));
      return;
    }
    // Demander la permission microphone avant l'enrôlement
    if (!await PermissionService.microphone(context)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission microphone requise pour l\'enrôlement vocal')));
      return;
    }
    _securityWord = word;
    setState(() => _loading = true);
    try {
      await _sosService.setSecurityWord(word);

      Object empreinte;
      if (_voiceAvailable) {
        // Flux 1-2 : 3 phrases -> empreinte moyenne robuste
        setState(() => _status = 'Enrôlement 1/3 : dites « $word » clairement…');
        final avg = await _voiceprint.captureAverageEmbedding(
          samples: 3,
          perSample: const Duration(seconds: 3),
          onProgress: (cur, total) {
            if (!mounted) return;
            setState(() => _status = 'Enrôlement $cur/$total : dites « $word » clairement… (${cur == 1 ? 'parlez naturellement' : cur == 2 ? 'encore une fois' : 'dernière prise'})');
          },
        );
        if (avg != null) {
          empreinte = avg;
          if (mounted) setState(() => _status = 'Empreinte moyenne créée (${avg.length} dims) — envoi…');
        } else {
          empreinte = await _sosService.voiceprintToken(word);
        }
      } else {
        setState(() => _status = 'Modèle vocal absent — enrôlement mot-clé seul…');
        empreinte = await _sosService.voiceprintToken(word);
      }

      await _sosService.enroll(empreinte);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice_security_word', word);
      if (!mounted) return;
      setState(() {
        _enrolled = true;
        _status = '';
      });
      final isAvg = empreinte is List && empreinte.length == 192;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAvg
              ? 'Empreinte vocale créée (3 prises moyennées). SOS vocal activé.'
              : 'Profil vocal enrôlé (mode repli : modèle vocal absent).'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startListening() async {
    if (_trip == null) {
      _noTripMessage();
      return;
    }
    final word = _securityWord?.trim();
    if (word == null || word.isEmpty) {
      if (!mounted) return;
      setState(() => _status = 'Définissez d\'abord un mot de sécurité.');
      return;
    }

    // Demander la permission microphone avant de commencer
    if (!await PermissionService.microphone(context)) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _status = 'Permission microphone refusée. Activez-la dans les paramètres.';
      });
      return;
    }

    setState(() {
      _listening = true;
      _heard = '';
      _status = 'Écoute du mot de sécurité…';
    });

    // 1) Tenter Vosk offline en priorité
    final voskStarted = await _vosk.startListening(
      securityWord: word,
      onPartial: (partial) {
        if (!mounted) return;
        setState(() {
          _heard = partial;
          _status = 'Vosk offline — écoute… "$partial"';
        });
      },
      onResult: (text) {
        if (!mounted) return;
        setState(() => _heard = text);
        if (text.toLowerCase().contains(word.toLowerCase())) {
          _vosk.stopListening();
          _verifyVoiceAndSend(word);
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _status = 'Vosk erreur: $e');
      },
    );

    if (voskStarted) {
      if (mounted) setState(() => _voskAvailable = true);
      return; // Vosk a pris le relais
    }

    // 2) Fallback Google speech_to_text
    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _status = 'Reconnaissance vocale indisponible — utilisez le bouton.';
      });
      return;
    }
    await _speech.listen(onResult: (result) {
      final text = result.recognizedWords;
      if (!mounted) return;
      setState(() => _heard = text);
      if (text.toLowerCase().contains(word.toLowerCase())) {
        _speech.stop();
        _verifyVoiceAndSend(word);
      }
    });
  }

  /// Vérification vocale : capture la voix, calcule l'embedding (biométrie),
  /// puis envoie le SOS. Repli sur le token si le modèle est absent.
  Future<void> _verifyVoiceAndSend(String keyword) async {
    // Couper toute écoute en cours (Vosk + Google)
    try { await _vosk.stopListening(); } catch (_) {}
    try { await _speech.stop(); } catch (_) {}
    setState(() {
      _listening = false;
      _loading = true;
      _status = _voiceAvailable
          ? 'Vérification de la voix — redites le mot « $keyword »…'
          : 'Vérification vocale…';
    });
    try {
      Object empreinte;
      if (_voiceAvailable) {
        final embedding = await _voiceprint.captureEmbedding(const Duration(seconds: 3));
        empreinte = embedding ?? await _sosService.voiceprintToken(keyword);
      } else {
        empreinte = await _sosService.voiceprintToken(keyword);
      }
      await _sendVocalSos(keyword, empreinte);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'SOS vocal en attente de connexion : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendVocalSos(String keyword, Object empreinte) async {
    try {
      final trip = _trip;
      if (trip == null) {
        _noTripMessage();
        return;
      }
      final pos = await _position();
      final data = await _sosService.triggerVocal(
        trip.id,
        pos.latitude,
        pos.longitude,
        keyword,
        empreinte,
      );

      // Envoyer des SOS via WhatsApp aux contacts d'urgence
      await _sendWhatsAppSos(data);

      final sos = data['sos'] as Map<String, dynamic>?;
      final details = sos?['details'] as Map<String, dynamic>?;
      final passed = details?['verification_passed'] == true;
      if (!mounted) return;
      setState(() => _status = passed
          ? 'Alerte vocale vérifiée et transmise + SMS envoyés.'
          : 'Alerte vocale reçue mais non vérifiée — en vérification.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_status)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'SOS vocal en attente de connexion : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fallbackButton() async {
    setState(() => _loading = true);
    try {
      final trip = _trip;
      if (trip == null) {
        _noTripMessage();
        return;
      }
      final pos = await _position();
      final data = await _sosService.triggerButton(trip.id, pos.latitude, pos.longitude);

      // Envoyer des SOS via WhatsApp aux contacts d'urgence
      await _sendWhatsAppSos(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alerte SOS (bouton) déclenchée et transmise : '
              'SMS, contacts, gestionnaire et services d\'urgence notifiés.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS en attente de connexion : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Position GPS réelle (haute précision), avec repli sur la dernière connue.
  Future<({double latitude, double longitude})> _position() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return (latitude: p.latitude, longitude: p.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (latitude: last.latitude, longitude: last.longitude);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.instance.t('sos')),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (_hasActiveTrip)
            TextButton(
              onPressed: () => setState(() => _vocalMode = !_vocalMode),
              child: Text(
                _vocalMode ? LanguageService.instance.t('sos') : LanguageService.instance.t('voice_trigger_title'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: !_hasActiveTrip
          ? _noTripBody()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _vocalMode ? _vocalBody() : _buttonBody(),
              ),
            ),
    );
  }

  Widget _noTripBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(LanguageService.instance.t('no_trip_body'), style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              LanguageService.instance.t('no_trip_sos_msg'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/trip-active'),
              icon: const Icon(Icons.trip_origin),
              label: Text(LanguageService.instance.t('see_current_trip')),
            ),
          ],
        ),
      ),
    );
  }

  void _noTripMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Aucun trajet actif : scannez le QR du transporteur '
            'pour démarrer un trajet.'),
      ),
    );
  }

  Widget _buttonBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(LanguageService.instance.t('in_danger'), style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        Text(
          LanguageService.instance.t('hold_to_trigger_sos'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        GestureDetector(
          onLongPress: _loading ? null : _fallbackButton,
          child: _bigButton(Icons.sos, 'Appui long'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() => _vocalMode = true),
          child: Text(LanguageService.instance.t('use_voice_trigger')),
        ),
      ],
    );
  }

  Widget _vocalBody() {
    if (!_enrolled) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(LanguageService.instance.t('configure_voice_sos'), style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          const Text(
            'Définissez un mot de sécurité puis enrôlez votre voix en 3 prises. '
            'Au déclenchement, dites ce mot : mot-clé (Vosk) + biométrie vocale (ECAPA) vérifiés '
            'avant l\'alerte.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _voiceAvailable
                ? 'Biométrie vocale embarquée (ECAPA-TDNN) : active.'
                : 'Modèle vocal absent — repli sur vérification mot-clé.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _voiceAvailable ? Colors.green.shade700 : Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _voskAvailable
                ? 'Reconnaissance offline Vosk (FR) : active — SOS sans internet.'
                : 'Vosk offline absent — repli Google (nécessite internet).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: _voskAvailable ? Colors.green.shade700 : Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _wordController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Mot de sécurité (3-40 caractères)',
              prefixIcon: Icon(Icons.mic),
              helperText: 'Ex: au secours, help me, danger',
            ),
            onChanged: (v) => _securityWord = v,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _enroll,
            icon: const Icon(Icons.save),
            label: Text(LanguageService.instance.t('enroll_voice_profile')),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(LanguageService.instance.t('voice_trigger_title'), style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(
          'Dites votre mot de sécurité (« $_securityWord ») pour alerter.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        GestureDetector(
          onTap: _listening || _loading ? null : _startListening,
          child: _bigButton(
            _listening ? Icons.graphic_eq : Icons.mic,
            _listening ? 'Écoute…' : 'Parler',
          ),
        ),
        const SizedBox(height: 12),
        if (_heard.isNotEmpty) Text('Entendu : "$_heard"'),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _listening ? null : _fallbackButton,
          icon: const Icon(Icons.sos),
          label: Text(LanguageService.instance.t('fallback_sos_button')),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _bigButton(IconData icon, String label) {
    final size = MediaQuery.of(context).size.width * 0.42;
    final clamped = size.clamp(120.0, 180.0);
    return Container(
      width: clamped,
      height: clamped,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red,
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: _loading
          ? Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: clamped * 0.35, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
    );
  }

  /// Envoie le message SOS via WhatsApp aux contacts d'urgence.
  /// Le backend retourne la liste des contacts et le message SMS à envoyer.
  Future<void> _sendWhatsAppSos(Map<String, dynamic> data) async {
    try {
      final contacts = data['emergency_contacts'] as List<dynamic>? ?? [];
      final smsMessage = data['sms_message'] as String?;
      if (contacts.isEmpty || smsMessage == null || smsMessage.isEmpty) return;

      final phones = contacts
          .map((c) => ((c['whatsapp_telephone'] as String?)?.trim().isNotEmpty == true
                  ? c['whatsapp_telephone'] as String
                  : c['telephone'] as String?)?.trim())
          .where((p) => p != null && p.isNotEmpty)
          .cast<String>()
          .toList();

      if (phones.isEmpty) return;

      final sent = await WhatsAppService.instance.sendBulk(phones, smsMessage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WhatsApp envoyés : $sent/${phones.length} contacts'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // Échec WhatsApp silencieux — les autres canaux (email, push) restent actifs
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _vosk.stopListening();
    _wordController.dispose();
    super.dispose();
  }
}