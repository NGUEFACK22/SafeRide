import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../services/offline_service.dart';
import '../services/background_location_service.dart';
import '../services/geocoding_service.dart';
import '../services/vosk_service.dart';
import '../services/voiceprint_service.dart';
import '../services/sos_service.dart';
import '../services/whatsapp_service.dart';
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
  final _voskMonitor = VoskService();
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
      _startVoiceMonitoring();
    } else {
      _tracker?.cancel();
      _stopVoiceMonitoring();
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
        const SnackBar(content: Text('Embarquement confirmé. Définissez la destination.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
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
          const SnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
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
        const SnackBar(content: Text('Destination confirmée. Trajet en cours.')),
      );
      _enterState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  // ===== Surveillance vocale automatique (flux 3-5) =====

  Future<void> _startVoiceMonitoring() async {
    if (_voiceMonitoring) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _securityWord = prefs.getString('voice_security_word');
      if (_securityWord == null || _securityWord!.trim().isEmpty) {
        if (mounted) setState(() => _voiceStatus = 'Mot de sécurité non configuré');
        return;
      }
      _voiceAvailable = await _voiceprint.ensureLoaded();
      final voskOk = await _voskMonitor.ensureLoaded(securityWord: _securityWord);
      if (!voskOk) {
        if (mounted) setState(() => _voiceStatus = 'Vosk absent — écoute automatique désactivée');
        return;
      }
      if (mounted) setState(() => _voiceStatus = 'Écoute automatique active…');
      final started = await _voskMonitor.startListening(
        securityWord: _securityWord!,
        onPartial: (partial) {
          if (!mounted) return;
          setState(() => _voiceStatus = 'Écoute… "$partial"');
        },
        onResult: (text) async {
          if (_autoSosSending) return;
          // Cooldown 30s pour éviter double déclenchement
          if (_lastAutoSosAt != null && DateTime.now().difference(_lastAutoSosAt!).inSeconds < 30) return;
          await _onAutoKeywordDetected(text);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _voiceStatus = 'Erreur écoute: $e');
        },
      );
      if (started && mounted) {
        setState(() {
          _voiceMonitoring = true;
          _voiceStatus = '🔴 Écoute automatique Vosk active ("$_securityWord")';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _voiceStatus = 'Écoute impossible: $e');
    }
  }

  Future<void> _stopVoiceMonitoring() async {
    if (!_voiceMonitoring) return;
    try {
      await _voskMonitor.stopListening();
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
      await _voskMonitor.stopListening();
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
              .map((c) => (c['telephone'] as String?)?.trim())
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .toList();
          if (phones.isNotEmpty) await WhatsAppService.instance.sendBulk(phones, sms);
        }
      } catch (_) {}
      final details = (data['sos'] as Map<String, dynamic>?)?['details'] as Map<String, dynamic>?;
      final passed = details?['verification_passed'] == true;
      if (!mounted) return;
      setState(() => _voiceStatus = passed ? '✅ SOS vérifié et transmis !' : '❌ Voix différente — alerte en vérification');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: passed ? Colors.green.shade700 : Colors.orange.shade800,
          content: Text(passed ? '✅ Voix correspondante — SOS déclenché !' : '❌ Voix différente — alerte en vérification'),
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
        title: const Text('Trajet terminé'),
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
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigation vers notation
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _RatingWrapper(trip: trip),
                ),
              ).then((_) => Navigator.of(context).pushReplacementNamed('/home'));
            },
            icon: const Icon(Icons.star_rate),
            label: const Text('Noter le trajet'),
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
        appBar: AppBar(title: const Text('Trajet')),
        body: const Center(child: Text('Aucun trajet en cours')),
      );
    }

    final trip = _trip!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trajet'),
        actions: [
          if (trip.statut == 'EN_COURS')
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'Envoyer la position',
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
        return const Center(child: Text('Trajet cloturé.'));
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
            subtitle: const Text('QR scanné — embarquement en attente'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Confirmez votre embarquement dans ce véhicule :',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _confirmEmbarquement,
          icon: const Icon(Icons.check_circle),
          label: const Text('Confirmer l\'embarquement'),
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
        const Text(
          'Saisissez votre destination :',
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
          label: const Text('Proposer la destination'),
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
            subtitle: const Text('Destination proposée'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Votre destination est-elle correcte ?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _validateDestination(true),
          icon: const Icon(Icons.check_circle),
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          label: const Text('Oui, confirmer'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _validateDestination(false),
          icon: const Icon(Icons.edit),
          label: const Text('Non, la modifier'),
        ),
      ],
    );
  }

  Widget _enCoursStep(Trip trip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text('Véhicule de ${trip.transporteurFullName}'),
            subtitle: const Text('Statut : EN COURS — surveillance active'),
          ),
        ),
        const SizedBox(height: 16),
        if (trip.destinationAddress != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag),
              title: Text(trip.destinationAddress!),
              subtitle: const Text('Destination confirmée'),
              trailing: const Icon(Icons.check_circle, color: Colors.green),
            ),
          ),
        const SizedBox(height: 16),
        if (trip.deviationKm != null && trip.deviationKm! > 0.5)
          Card(
            color: Colors.orange.shade50,
            child: const ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text('Écart d\'itinéraire détecté'),
              subtitle: Text(
                'Le trajet réel s\'écarte significativement de l\'itinéraire prévu. '
                'Une alerte a été enregistrée.',
              ),
            ),
          )
        else if (trip.plannedRoutePolyline != null && trip.plannedRoutePolyline!.isNotEmpty)
          Card(
            color: Colors.blue.shade50,
            child: const ListTile(
              leading: Icon(Icons.route, color: Colors.blue),
              title: Text('Itinéraire prévu chargé'),
              subtitle: Text('Comparaison trajet réel vs prévu active.'),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          color: _voiceMonitoring ? Colors.green.shade50 : Colors.orange.shade50,
          child: ListTile(
            leading: Icon(_voiceMonitoring ? Icons.hearing : Icons.hearing_disabled,
                color: _voiceMonitoring ? Colors.green : Colors.orange),
            title: Text(_voiceMonitoring ? 'Protection vocale active (auto)' : 'Protection vocale inactive'),
            subtitle: Text(
              _voiceStatus.isNotEmpty
                  ? _voiceStatus
                  : 'Le mot de sécurité est écouté automatiquement pendant le trajet. '
                      'Vosk (mot-clé) + ECAPA (voix) -> ✅/❌ automatique.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _busy ? null : _endTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Fin de trajet'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si vous ne cliquez pas dans les 10 minutes après l\'arrivée, '
          'le trajet se termine automatiquement.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.pushNamed(context, '/sos-button', arguments: trip),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
          icon: const Icon(Icons.sos),
          label: const Text('Bouton SOS (secours)'),
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
