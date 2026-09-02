import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../services/offline_service.dart';
import '../services/background_location_service.dart';
import '../services/geocoding_service.dart';
import '../services/permission_service.dart';
import '../services/voiceprint_service.dart';
import '../services/sos_service.dart';
import '../services/whatsapp_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import 'rating_screen.dart';

class TripActiveScreen extends StatefulWidget {
  final Trip? initialTrip;

  const TripActiveScreen({super.key, this.initialTrip});

  @override
  State<TripActiveScreen> createState() => _TripActiveScreenState();
}

class _TripActiveScreenState extends State<TripActiveScreen> {
  final _tripService = TripService();
  final _offline = OfflineService.instance;
  final _speech = stt.SpeechToText();
  final _voiceprint = VoiceprintService();
  final _sosService = SosService();
  Trip? _trip;
  bool _loading = true;
  bool _busy = false;

  final _destinationController = TextEditingController();
  bool _editingDestination = false;
  bool _offlineBanner = false;
  int _pendingCount = 0;
  Timer? _tracker;

  // Surveillance vocale automatique pendant EN_COURS (flux 3-5)
  String? _securityWord;
  bool _voiceAvailable = false;
  bool _voiceMonitoring = false;
  bool _autoSosSending = false;
  DateTime? _lastAutoSosAt;
  String _voiceStatus = '';
  bool _voiceConsentGiven = false;

  // Météo pendant le trajet
  WeatherData? _weather;
  bool _weatherLoading = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.initialTrip;
    _offline.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      setState(() => _offlineBanner = !online);
      _refreshPending();
    });
    _refreshPending();
    _load();
  }

  @override
  void dispose() {
    _tracker?.cancel();
    _stopVoiceMonitoring();
    _speech.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_trip != null) {
      setState(() => _loading = false);
      _enterState();
      return;
    }
    try {
      final trip = await _tripService.currentTrip();
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _loading = false;
      });
      _enterState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Déclenche les actions liées à l'état courant (suivi GPS + écoute vocale en EN_COURS).
  void _enterState() {
    if (_trip?.statut == 'EN_COURS') {
      _startTracking();
      // Foreground Service Android : suivi GPS en arrière-plan
      Geolocator.requestPermission().then((_) {}, onError: (_) {});
      BackgroundLocationService().startTripTracking(_trip!.id);
      _loadWeather();
      _askVoiceConsent();
    } else {
      _tracker?.cancel();
      _stopVoiceMonitoring();
    }
  }

  /// Charge la météo pour la position actuelle du trajet.
  Future<void> _loadWeather() async {
    if (_weatherLoading) return;
    setState(() => _weatherLoading = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final weather = await WeatherService.instance
          .getCurrentWeather(position.latitude, position.longitude);
      if (mounted) setState(() { _weather = weather; _weatherLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  /// Demande à l'utilisateur s'il souhaite activer l'écoute vocale automatique.
  Future<void> _askVoiceConsent() async {
    // Vérifier si un mot de sécurité est configuré
    final prefs = await SharedPreferences.getInstance();
    _securityWord = prefs.getString('voice_security_word');
    if (_securityWord == null || _securityWord!.trim().isEmpty) return;
    // Vérifier si consentement déjà donné (pour ce trajet)
    if (_voiceConsentGiven) {
      _startVoiceMonitoring();
      return;
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.hearing, color: AppTheme.primaryBlue, size: 36),
        title: const Text('Écoute vocale'),
        content: Text(
          'Activer l\'écoute automatique de votre mot de sécurité ("$_securityWord") pendant ce trajet ?\n\n'
          'Votre microphone sera utilisé pour détecter le mot et déclencher l\'alerte SOS si nécessaire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, merci'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    if (result == true) {
      _voiceConsentGiven = true;
      _startVoiceMonitoring();
    }
  }

  void _startTracking() {
    _tracker?.cancel();
    _tracker = Timer.periodic(const Duration(seconds: 10), (_) => _sendLocation());
    _sendLocation();
  }

  Future<void> _refreshPending() async {
    final count = await _offline.pendingLocationCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  Future<void> _confirmEmbarquement() async {
    if (_trip == null) return;
    setState(() => _busy = true);
    try {
      final trip = await _tripService.confirmEmbarquement(_trip!.id);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Embarquement confirmé. Définissez la destination.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _confirmDestination() async {
    final address = _destinationController.text.trim();
    if (address.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Géocodage réel de l'adresse (OpenStreetMap Nominatim, gratuit)
      final coords = await GeocodingService().geocode(address);
      if (coords == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adresse introuvable, veuillez reformuler la destination.'),
          ),
        );
        return;
      }
      final trip = await _tripService.setDestination(
        _trip!.id,
        address,
        coords.latitude,
        coords.longitude,
      );
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _validateDestination(bool confirmed) async {
    setState(() => _busy = true);
    try {
      final trip = await _tripService.confirmDestination(_trip!.id, confirmed);
      if (!mounted) return;
      if (!confirmed) {
        setState(() {
          _trip = trip;
          _editingDestination = true;
          _busy = false;
        });
        return;
      }
      setState(() {
        _trip = trip;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Destination confirmée. Trajet en cours.')),
      );
      _enterState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _sendLocation() async {
    if (_trip == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _offline.sendLocation(
        _trip!.id,
        position.latitude,
        position.longitude,
        position.speed * 3.6,
      );
    } catch (_) {
      // GPS indisponible : le service de fond réessaiera
    }
    await _refreshPending();
  }

  Future<void> _endTrip() async {
    if (_trip == null) return;
    setState(() => _busy = true);
    try {
      final trip = await _tripService.endTrip(_trip!.id);
      if (!mounted) return;
      _tracker?.cancel();
      BackgroundLocationService().stopTripTracking();
      await _stopVoiceMonitoring();
      setState(() {
        _trip = trip;
        _busy = false;
      });
      _showTripSummary(trip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  // ===== Surveillance vocale automatique avec speech_to_text (flux 3-5) =====

  Future<void> _startVoiceMonitoring() async {
    if (_voiceMonitoring) return;
    try {
      if (_securityWord == null || _securityWord!.trim().isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        _securityWord = prefs.getString('voice_security_word');
      }
      if (_securityWord == null || _securityWord!.trim().isEmpty) {
        if (mounted) setState(() => _voiceStatus = 'Mot de sécurité non configuré');
        return;
      }
      // Demander permission microphone
      if (!await PermissionService.microphone(context)) {
        if (mounted) setState(() => _voiceStatus = 'Permission microphone refusée');
        return;
      }
      // Initialiser speech_to_text
      final available = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() => _voiceStatus = 'Erreur écoute: ${e.errorMsg}');
          // Auto-redémarrer après 3s sauf si errorListening
          if (e.errorMsg != 'errorListening' && _voiceMonitoring) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _voiceMonitoring) _startListeningContinuous();
            });
          }
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' && _voiceMonitoring) {
            // Relancer automatiquement
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && _voiceMonitoring) _startListeningContinuous();
            });
          }
        },
      );
      if (!available) {
        if (mounted) setState(() => _voiceStatus = 'Reconnaissance vocale indisponible');
        return;
      }
      _voiceAvailable = await _voiceprint.ensureLoaded();
      if (mounted) {
        setState(() {
          _voiceMonitoring = true;
          _voiceStatus = 'Écoute automatique active ("$_securityWord")';
        });
      }
      _startListeningContinuous();
    } catch (e) {
      if (mounted) setState(() => _voiceStatus = 'Écoute impossible: $e');
    }
  }

  void _startListeningContinuous() {
    if (!_voiceMonitoring) return;
    _speech.listen(
      onResult: (result) {
        if (!mounted || _autoSosSending) return;
        final text = result.recognizedWords;
        if (text.isNotEmpty) {
          setState(() => _voiceStatus = 'Écoute… "$text"');
          if (_securityWord != null && text.toLowerCase().contains(_securityWord!.toLowerCase())) {
            if (_lastAutoSosAt != null && DateTime.now().difference(_lastAutoSosAt!).inSeconds < 30) return;
            _onAutoKeywordDetected(text);
          }
        }
      },
      listenOptions: stt.SpeechListenOptions(listenMode: stt.ListenMode.dictation),
    );
  }

  Future<void> _stopVoiceMonitoring() async {
    if (!_voiceMonitoring) return;
    try {
      await _speech.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _voiceMonitoring = false;
        _voiceStatus = 'Écoute arrêtée';
      });
    }
  }

  Future<void> _onAutoKeywordDetected(String text) async {
    final word = _securityWord;
    if (word == null || _trip == null) return;
    if (!text.toLowerCase().contains(word.toLowerCase())) return;
    _lastAutoSosAt = DateTime.now();
    if (mounted) setState(() => _voiceStatus = 'Mot détecté "$word" → vérification vocale…');
    await _autoVerifyAndSend(word);
  }

  Future<void> _autoVerifyAndSend(String keyword) async {
    if (_autoSosSending) return;
    _autoSosSending = true;
    try {
      // Pause temporaire de l'écoute pendant la vérif biométrique
      await _speech.stop();
      if (mounted) setState(() => _voiceStatus = 'Vérification biométrique (ECAPA)…');
      Object empreinte;
      if (_voiceAvailable) {
        final emb = await _voiceprint.captureEmbedding(const Duration(seconds: 3));
        empreinte = emb ?? await _sosService.voiceprintToken(keyword);
      } else {
        empreinte = await _sosService.voiceprintToken(keyword);
      }
      final pos = await _autoPosition();
      final data = await _sosService.triggerVocal(_trip!.id, pos.latitude, pos.longitude, keyword, empreinte);
      // WhatsApp automatique
      try {
        final contacts = data['emergency_contacts'] as List<dynamic>? ?? [];
        final sms = data['sms_message'] as String?;
        if (contacts.isNotEmpty && sms != null) {
          final phones = contacts
              .map((c) => ((c['whatsapp_telephone'] as String?)?.trim().isNotEmpty == true
                      ? c['whatsapp_telephone'] as String
                      : c['telephone'] as String?)?.trim())
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .toList();
          if (phones.isNotEmpty) await WhatsAppService.instance.sendBulk(phones, sms);
        }
      } catch (_) {}
      final details = (data['sos'] as Map<String, dynamic>?)?['details'] as Map<String, dynamic>?;
      final passed = details?['verification_passed'] == true;
      if (!mounted) return;
      setState(() => _voiceStatus = passed ? 'SOS vérifié et transmis !' : 'Voix différente — alerte en vérification');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: passed ? Colors.green.shade700 : Colors.orange.shade800,
          content: Text(passed ? 'Voix correspondante — SOS déclenché !' : 'Voix différente — alerte en vérification'),
          duration: const Duration(seconds: 4),
        ),
      );
      // Relancer l'écoute après 5s
      await Future<void>.delayed(const Duration(seconds: 5));
      if (mounted && _trip?.statut == 'EN_COURS') {
        _voiceMonitoring = false; // forcer restart
        await _startVoiceMonitoring();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _voiceStatus = 'Erreur auto SOS: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SOS auto erreur: $e')));
      }
      // Relancer quand même après erreur
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted && _trip?.statut == 'EN_COURS') {
        _voiceMonitoring = false;
        await _startVoiceMonitoring();
      }
    } finally {
      _autoSosSending = false;
    }
  }

  Future<({double latitude, double longitude})> _autoPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      return (latitude: p.latitude, longitude: p.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (latitude: last.latitude, longitude: last.longitude);
      rethrow;
    }
  }

  void _showTripSummary(Trip trip) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(LanguageService.instance.t('trip_finished')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transporteur : ${trip.transporteurFullName}'),
            Text('Distance : ${trip.distanceKm?.toStringAsFixed(1) ?? '—'} km'),
            Text('Durée : ${(trip.durationSeconds ?? 0) ~/ 60} min'),
            Text(
              'Écart itinéraire réel vs prévu : '
              '${trip.deviationKm?.toStringAsFixed(2) ?? '—'} km',
            ),
            const SizedBox(height: 8),
            Text(
              'Fin : ${trip.endMethod == 'AUTO_10MIN' ? 'automatique (10 min sans action)' : 'manuelle'}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacementNamed('/home');
            },
            child: Text(LanguageService.instance.t('close')),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (!mounted) return;
              // Navigation vers notation
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _RatingWrapper(trip: trip),
                ),
              ).then((_) {
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed('/home');
              });
            },
            icon: const Icon(Icons.star_rate),
            label: Text('Noter le trajet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_trip == null) {
      return Scaffold(
        appBar: AppBar(title: Text(LanguageService.instance.t('trip_title'))),
        body: Center(child: Text(LanguageService.instance.t('no_trip'))),
      );
    }

    final trip = _trip!;

    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.instance.t('trip_title')),
        actions: [
          if (trip.statut == 'EN_COURS')
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: LanguageService.instance.t('send_location'),
              onPressed: _sendLocation,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_offlineBanner)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                'En attente de connexion — $_pendingCount position(s) en file de synchronisation',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            )
          else if (_pendingCount > 0)
            Container(
              width: double.infinity,
              color: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Text(
                'Synchronisation en cours ($_pendingCount restante(s))…',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _bodyFor(trip),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyFor(Trip trip) {
    switch (trip.statut) {
      case 'SCANNE':
        return _embarquementStep(trip);
      case 'CONFIRME':
        return _destinationStep(trip, editing: _editingDestination);
      case 'DESTINATION_PROPOSEE':
        return _destinationConfirmStep(trip);
      case 'EN_COURS':
        return _enCoursStep(trip);
      default:
        return Center(child: Text('Trajet cloturé.'));
    }
  }

  Widget _embarquementStep(Trip trip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text('Véhicule de ${trip.transporteurFullName}'),
            subtitle: Text(LanguageService.instance.t('boarding_pending')),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          LanguageService.instance.t('confirm_your_boarding'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _confirmEmbarquement,
          icon: const Icon(Icons.check_circle),
          label: Text(LanguageService.instance.t('confirm_boarding')),
        ),
      ],
    );
  }

  Widget _destinationStep(Trip trip, {bool editing = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text('Véhicule de ${trip.transporteurFullName}'),
            subtitle: const Text('Embarquement confirmé'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          LanguageService.instance.t('enter_destination'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _destinationController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Ex : Place de la Nation, Yaoundé',
            prefixIcon: const Icon(Icons.place_outlined),
            labelText: editing ? 'Nouvelle destination' : null,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _confirmDestination,
          icon: const Icon(Icons.check),
          label: Text(LanguageService.instance.t('propose_destination')),
        ),
      ],
    );
  }

  Widget _destinationConfirmStep(Trip trip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.flag),
            title: Text(trip.destinationAddress ?? ''),
            subtitle: Text(LanguageService.instance.t('destination_proposed')),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          LanguageService.instance.t('is_destination_correct'),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _validateDestination(true),
          icon: const Icon(Icons.check_circle),
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          label: Text(LanguageService.instance.t('yes_confirm')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _validateDestination(false),
          icon: const Icon(Icons.edit),
          label: Text(LanguageService.instance.t('no_edit')),
        ),
      ],
    );
  }

  Widget _enCoursStep(Trip trip) {
    // E.23 : hiérarchie priorité — destination + SOS toujours visibles
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header priorité 1 : destination + statut
        Card(
          color: Colors.white,
          elevation: 1,
          child: ListTile(
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.flag, color: AppTheme.primaryBlue)),
            title: Text(trip.destinationAddress ?? 'Destination en cours', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: const Text('Destination confirmée • EN COURS', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            trailing: const Icon(Icons.check_circle, color: Colors.green, size: 22),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car, color: AppTheme.primaryBlue),
            title: Text('Véhicule de ${trip.transporteurFullName.isNotEmpty ? trip.transporteurFullName : 'Transporteur'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Surveillance GPS + vocale active', style: TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 10),
        // Météo en cours de trajet
        if (_weatherLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Météo en cours…', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                ],
              ),
            ),
          )
        else if (_weather != null)
          Card(
            color: AppTheme.primaryBlue.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(_weather!.icon, size: 28, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_weather!.description, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${_weather!.tempDisplay} · Vent ${_weather!.windDisplay} ${_weather!.windDirectionText}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
                        ),
                      ],
                    ),
                  ),
                  if (_weather!.precipitationProbability != null && _weather!.precipitationProbability! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.water_drop, size: 12, color: Colors.blue),
                          const SizedBox(width: 3),
                          Text('${_weather!.precipitationProbability}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (trip.deviationKm != null && trip.deviationKm! > 0.5)
          Card(
            color: Colors.orange.shade50,
            child: const ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text('Écart d\'itinéraire détecté'),
              subtitle: Text('Le trajet réel s\'écarte significativement de l\'itinéraire prévu. Une alerte a été enregistrée.', style: TextStyle(fontSize: 11)),
            ),
          )
        else if (trip.plannedRoutePolyline != null && trip.plannedRoutePolyline!.isNotEmpty)
          Card(
            color: Colors.blue.shade50,
            child: const ListTile(
              leading: Icon(Icons.route, color: Colors.blue),
              title: Text('Itinéraire prévu chargé', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Comparaison trajet réel vs prévu active.', style: TextStyle(fontSize: 11)),
            ),
          ),
        const SizedBox(height: 10),
        Card(
          color: _voiceMonitoring ? Colors.green.shade50 : Colors.orange.shade50,
          child: ListTile(
            leading: Icon(_voiceMonitoring ? Icons.hearing : Icons.hearing_disabled, color: _voiceMonitoring ? Colors.green : Colors.orange),
            title: Text(_voiceMonitoring ? 'Protection vocale active (auto)' : 'Protection vocale inactive', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(
              _voiceStatus.isNotEmpty
                  ? _voiceStatus
                  : 'Le mot de sécurité est écouté automatiquement pendant le trajet. Vosk (mot-clé) + ECAPA (voix) — vérification automatique.',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Bouton fin + SOS toujours visibles (E.21/23)
        ElevatedButton.icon(
          onPressed: _busy ? null : _endTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.stop_circle_outlined),
          label: Text(_busy ? LanguageService.instance.t('processing') : LanguageService.instance.t('end_trip'), style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Si vous ne cliquez pas dans les 10 minutes après l\'arrivée, le trajet se termine automatiquement.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textGrey),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _autoSosSending || _busy
                ? null
                : () => Navigator.pushNamed(context, '/sos-button', arguments: trip),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.sosRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _autoSosSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sos),
            label: Text(_autoSosSending ? LanguageService.instance.t('processing') : LanguageService.instance.t('sos'), style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }
}

class _RatingWrapper extends StatelessWidget {
  final Trip trip;
  const _RatingWrapper({required this.trip});
  @override
  Widget build(BuildContext context) => RatingScreen(trip: trip);
}