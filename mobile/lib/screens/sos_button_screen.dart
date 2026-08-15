import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import '../services/sos_service.dart';

class SosButtonScreen extends StatefulWidget {
  final Trip? trip;

  const SosButtonScreen({super.key, this.trip});

  @override
  State<SosButtonScreen> createState() => _SosButtonScreenState();
}

class _SosButtonScreenState extends State<SosButtonScreen> {
  final _sosService = SosService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _loading = false;
  bool _vocalMode = false;

  // État du profil vocal
  bool _enrolled = false;
  String? _securityWord;
  bool _listening = false;
  String _heard = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _securityWord = prefs.getString('voice_security_word');
    try {
      final data = await _sosService.profile();
      final profile = data['profile'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() => _enrolled = profile != null && (profile['enrolled'] == true));
      }
    } catch (_) {
      // hors-ligne : on se base sur le cache local
    }
  }

  Future<void> _enroll() async {
    final word = _securityWord?.trim();
    if (word == null || word.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _sosService.setSecurityWord(word);
      final token = await _sosService.voiceprintToken(word);
      await _sosService.enroll(token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice_security_word', word);
      if (!mounted) return;
      setState(() => _enrolled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil vocal enrôlé. SOS vocal activé.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startListening() async {
    if (widget.trip == null) {
      _fallbackButton();
      return;
    }
    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      setState(() => _status = 'Reconnaissance vocale indisponible — utilisez le bouton.');
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
      _status = 'Écoute du mot de sécurité…';
    });
    await _speech.listen(onResult: (result) {
      final text = result.recognizedWords;
      if (!mounted) return;
      setState(() => _heard = text);
      if (_securityWord != null &&
          text.toLowerCase().contains(_securityWord!.toLowerCase())) {
        _speech.stop();
        _sendVocalSos(_securityWord!);
      }
    });
  }

  Future<void> _sendVocalSos(String keyword) async {
    setState(() {
      _listening = false;
      _loading = true;
      _status = 'Vérification vocale…';
    });
    try {
      final token = await _sosService.voiceprintToken(keyword);
      final pos = await _position();
      final data = await _sosService.triggerVocal(
        widget.trip!.id,
        pos.latitude,
        pos.longitude,
        keyword,
        token,
      );
      final sos = data['sos'] as Map<String, dynamic>?;
      final details = sos?['details'] as Map<String, dynamic>?;
      final passed = details?['verification_passed'] == true;
      if (!mounted) return;
      setState(() => _status = passed
          ? 'Alerte vocale vérifiée et transmise.'
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
      final trip = widget.trip;
      if (trip == null) throw Exception('Aucun trajet actif');
      final pos = await _position();
      await _sosService.triggerButton(trip.id, pos.latitude, pos.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alerte SOS (bouton) déclenchée et transmise : '
              'contacts, gestionnaire et services d\'urgence notifiés.'),
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
        title: const Text('SOS'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => setState(() => _vocalMode = !_vocalMode),
            child: Text(
              _vocalMode ? 'Mode bouton' : 'Mode vocal',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _vocalMode ? _vocalBody() : _buttonBody(),
        ),
      ),
    );
  }

  Widget _buttonBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Vous êtes en danger ?', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        const Text(
          'Maintenez le bouton pour déclencher une alerte SOS transmise à vos '
          'contacts d\'urgence, au gestionnaire et aux services d\'urgence.',
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
          child: const Text('Utiliser le déclenchement vocal'),
        ),
      ],
    );
  }

  Widget _vocalBody() {
    if (!_enrolled) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Configurer le SOS vocal', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          const Text(
            'Définissez un mot de sécurité puis enrôlez votre empreinte vocale. '
            'Au déclenchement, dites ce mot : le serveur vérifie mot-clé + empreinte.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Mot de sécurité',
              prefixIcon: Icon(Icons.mic),
            ),
            onChanged: (v) => _securityWord = v,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _enroll,
            icon: const Icon(Icons.save),
            label: const Text('Enrôler mon profil vocal'),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Déclenchement vocal', style: TextStyle(fontSize: 20)),
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
          label: const Text('Fallback : bouton SOS'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _bigButton(IconData icon, String label) {
    return Container(
      width: 160,
      height: 160,
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
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 56, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}
