import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/error_helper.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../data/douala_places.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_service.dart';
import '../services/offline_service.dart';
import '../services/background_location_service.dart';
import '../services/geocoding_service.dart';
import '../services/osrm_service.dart';
import '../services/permission_service.dart';
import '../services/voiceprint_service.dart';
import '../services/sos_service.dart';
import '../services/alert_counter_service.dart';
import '../services/whatsapp_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../utils/root_message.dart';
import '../services/language_service.dart';
import '../widgets/emergency_contacts_gate.dart';
import 'rating_screen.dart';

class TripActiveScreen extends StatefulWidget {
  final Trip? initialTrip;

  const TripActiveScreen({super.key, this.initialTrip});

  @override
  State<TripActiveScreen> createState() => _TripActiveScreenState();
}

class _TripActiveScreenState extends State<TripActiveScreen>
    with WidgetsBindingObserver {
  final _tripService = TripService();
  final _offline = OfflineService.instance;
  final _speech = stt.SpeechToText();
  final _voiceprint = VoiceprintService();
  final _sosService = SosService();
  final _api = ApiService();
  Trip? _trip;
  bool _loading = true;
  bool _busy = false;
  bool _isTransporteur = false;

  final _destinationController = TextEditingController();
  bool _editingDestination = false;
  bool _offlineBanner = false;
  int _pendingCount = 0;
  Timer? _tracker;
  Timer? _waitingPoll;
  Timer? _endPoll;

  // Autocomplete destination (liste locale Douala) + carte de tracé
  final _destinationMapController = MapController();
  List<DoualaPlace> _placeSuggestions = [];
  DoualaPlace? _selectedPlace;
  LatLng? _previewOrigin;
  List<LatLng> _previewRoute = [];
  bool _previewRouteLoading = false;
  Timer? _destinationDebounce;
  bool _applyingSuggestion = false;

  // Surveillance vocale automatique pendant EN_COURS (flux 3-5)
  String? _securityWord;
  bool _voiceAvailable = false;
  bool _voiceMonitoring = false;
  bool _autoSosSending = false;
  bool _shareBusy = false;
  DateTime? _lastAutoSosAt;
  String _voiceStatus = '';
  bool _voiceConsentGiven = false;

  // Séquençage EN_COURS : anti double-entrée + zones natives isolées
  // (un échec local ne doit jamais faire fermer l'application).
  bool _enterStateInProgress = false;
  // Zones natives déjà démarrées pour le cycle en cours : passer de EN_COURS
  // à FIN_EN_ATTENTE ne doit PAS relancer GPS/service/météo (pic mémoire).
  bool _zonesStarted = false;

  // Météo pendant le trajet
  WeatherData? _weather;
  bool _weatherLoading = false;

  // Carte live : position + itinéraire (zoom précis pour se voir sur la route)
  final _mapController = MapController();
  LatLng? _livePosition;
  List<LatLng> _liveRoute = [];
  List<LatLng> _plannedRoute = [];
  // Itinéraire RESTANT recalculé (position live → destination) via OSRM :
  // suit toujours les vraies routes, contrairement au fil brut GPS qui coupe
  // à travers les îlots. Recalcul throttlé (45 s / 100 m) dans
  // _maybeRecalcRemainingRoute. Exige > 2 points (le repli OSRM hors-ligne
  // renvoie juste [from, to], qu'on n'affiche pas comme itinéraire routier).
  List<LatLng> _remainingRoute = [];
  DateTime _lastRouteRecalcAt = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _lastRouteRecalcPos;
  static const LatLng _mapFallback = LatLng(
    DoualaPlaces.centerLatitude,
    DoualaPlaces.centerLongitude,
  ); // Douala (Akwa)

  // Service de fond : démarrage PARESSEUX (voir didChangeAppLifecycleState).
  // Le démarrer en même temps que le GPS + la météo + la carte, à l'instant
  // exact de la confirmation de destination, empilait un pic mémoire/CPU
  // (nouvel isolate + startForeground) qui tuait le process — côté passager
  // ET transporteur, au même moment. Le tracker in-app (10 s) couvre le
  // premier plan ; le service ne démarre qu'au passage en arrière-plan.
  bool _bgServiceStarted = false;

  // Garde anti-chevauchement GPS : le timer 10 s ne doit jamais empiler des
  // getCurrentPosition concurrents (sans timeLimit, un fix qui pendait
  // accumulait les requêtes natives jusqu'à tuer le process).
  bool _sendingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _tracker?.cancel();
    _waitingPoll?.cancel();
    _endPoll?.cancel();
    _destinationDebounce?.cancel();
    _stopVoiceMonitoring();
    _speech.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Trajet actif (EN_COURS ou FIN_EN_ATTENTE) + app envoyée en
    // arrière-plan → on démarre le service de fond ICI (et seulement ici)
    // pour poursuivre le suivi GPS.
    // `paused` = vraiment en arrière-plan (les dialogues système donnent
    // `inactive`, pas `paused` : pas de démarrage prématuré).
    if (state != AppLifecycleState.paused || !mounted) return;
    if (_bgServiceStarted) return;
    final trip = _trip;
    if (trip == null ||
        (trip.statut != 'EN_COURS' && trip.statut != 'FIN_EN_ATTENTE')) {
      return;
    }
    _bgServiceStarted = true;
    try {
      BackgroundLocationService().startTripTracking(trip.id).catchError((_) {});
    } catch (_) {
      _bgServiceStarted = false;
    }
  }

  Future<void> _load() async {
    final user = await _api.getUser();
    if (user != null) {
      final roles = List<String>.from(user['roles'] ?? []);
      _isTransporteur = roles.contains('transporteur');
    }
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

  /// Décode la polyline OSRM prévue (stockée au setDestination) en points.
  void _decodePlannedRoute(Trip trip) {
    final encoded = trip.plannedRoutePolyline;
    if (encoded == null || encoded.isEmpty) {
      _plannedRoute = [];
      return;
    }
    _plannedRoute = OsrmService.decodePolyline(encoded);
  }

    /// Retour à l'accueil EN CONSERVANT la session : on dépile jusqu'à la
  /// première route (le Home d'origine, avec son User) au lieu de recréer
  /// un Home sans arguments (= mode invité, l'utilisateur se retrouve
  /// "déconnecté" après notation / fin de trajet).
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Variante avec petit message affiché SUR l'accueil (le Scaffold du
  /// trajet est détruit : on passe par le messenger racine, après la frame).
  void _goHomeWithMessage(String message, {Color? color}) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showRootMessage(message, backgroundColor: color ?? Colors.green);
    });
  }

  /// Déclenche les actions liées à l'état courant (suivi GPS + écoute vocale en EN_COURS).
  void _enterState() {
    // Vérification défensive : si le trajet est null ou terminé, on nettoie avant de lire le statut.
    if (_trip == null) {
      _tracker?.cancel();
      _endPoll?.cancel();
      _stopVoiceMonitoring();
      return;
    }

    final statut = _trip!.statut;

    if (statut == 'EN_COURS' || statut == 'FIN_EN_ATTENTE') {
      // Garde anti double-entrée : `_validateDestination`, le poll transporteur
      // et `_load()` peuvent tous arriver au même instant. Une seule séquence
      // de démarrage s'exécute à la fois — le crash venait du lancement
      // SIMULTANÉ des zones natives (fire-and-forget, non isolées).
      if (_enterStateInProgress) return;
      _enterStateInProgress = true;
      _waitingPoll?.cancel();
      _decodePlannedRoute(_trip!);
      _startEndPoll();
      if (_zonesStarted) {
        // EN_COURS → FIN_EN_ATTENTE : suivi déjà en route, on ne relance
        // rien (relancer GPS + service + météo empilait un pic mémoire).
        _enterStateInProgress = false;
        return;
      }
      _zonesStarted = true;
      // Nouveau cycle EN_COURS : on repart d'une carte vierge (sinon le fil
      // GPS et l'itinéraire restant du trajet PRÉCÉDENT resteraient affichés).
      _liveRoute = [];
      _remainingRoute = [];
      _livePosition = null;
      _lastRouteRecalcPos = null;
      _lastRouteRecalcAt = DateTime.fromMillisecondsSinceEpoch(0);
      // Premier tracé routier immédiat (départ → destination) : la carte
      // affiche l'itinéraire sur routes avant même le 1er fix GPS.
      final seedPos = _trip!.startLatitude != null && _trip!.startLongitude != null
          ? LatLng(_trip!.startLatitude!, _trip!.startLongitude!)
          : null;
      if (seedPos != null) _maybeRecalcRemainingRoute(seedPos);
      // Position connue immédiate (cache GPS) : la carte se centre sur
      // l'utilisateur sans attendre le 1er fix (fini le voile de chargement).
      _seedLivePosition();
      // Nouveau cycle EN_COURS : le service de fond (s'il démarre au
      // backgrounding) devra prendre ce trajet-ci, pas le précédent.
      _bgServiceStarted = false;
      // Différé après la 1re frame : la transition de route (teardown caméra
      // côté scan, animation) ne se chevauche plus avec le démarrage GPS /
      // service de fond / météo. Sur les appareils lents, ce chevauchement
      // (mémoire + sessions natives simultanées) tuait le process à
      // l'ouverture — "l'app se ferme" juste après le scan.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runEnCoursZones();
      });
    } else if (statut == 'TERMINE' || statut == 'ANNULE') {
      // Le trajet est terminé ou annulé : arrêt du suivi et retour à l'accueil.
      _tracker?.cancel();
      _endPoll?.cancel();
      _zonesStarted = false;
      _stopVoiceMonitoring();
      try {
        BackgroundLocationService().stopTripTracking();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(statut == 'TERMINE' ? 'Le trajet est terminé.' : 'Le trajet a été annulé.'), backgroundColor: AppTheme.sosRed),
        );
        _goHome();
      }
    } else {
      // Autres états (SCANNE, EN_ATTENTE_TRANSPORTEUR, CONFIRME, DESTINATION_PROPOSEE) : on nettoie les timers mais on ne démarre pas le suivi
      _tracker?.cancel();
      _endPoll?.cancel();
      _zonesStarted = false;
      _stopVoiceMonitoring();
    }
  }

  /// Démarrage SÉQUENCÉ et ISOLÉ des zones natives du trajet (GPS, service de
  /// fond Android, micro/ONNX). Chaque zone est isolée dans son propre
  /// try/catch : une défaillance locale (permission refusée, service
  /// indisponible, mémoire insuffisante) s'affiche en SnackBar diagnostique et
  /// est persistée — elle ne peut plus faire fermer l'application.
  Future<void> _runEnCoursZones() async {
    try {
      // Zone 1 — permission de localisation puis tracking GPS (toutes les 10 s).
      try {
        if (await PermissionService.location(context)) {
          _startTracking();
        } else {
          _recordZoneFailure('gps', 'Localisation refusée — suivi GPS désactivé');
        }
      } catch (e) {
        _recordZoneFailure('gps', '$e');
      }

      // Zone 2 — permission de notification demandée MAINTENANT (Android 13+ :
      // requise avant tout startForeground), mais service de fond démarré en
      // DIFFÉRÉ (backgrounding, voir didChangeAppLifecycleState) : le lancer
      // ici, en pleine transition EN_COURS (GPS + météo + carte), tuait le
      // process des deux côtés au moment de la confirmation de destination.
      try {
        if (mounted) await PermissionService.notification(context);
      } catch (e) {
        _recordZoneFailure('notifications', '$e');
      }
    } catch (e) {
      _recordZoneFailure('démarrage', '$e');
    }

    // Zone 3 — météo (simple HTTP, déjà défensive).
    try {
      await _loadWeather();
    } catch (e) {
      _recordZoneFailure('météo', '$e');
    }

    // Pause : laisse la carte live terminer son rendu avant d'ouvrir le micro
    // + modèle ONNX (20 Mo) — évite le pic mémoire qui tue le process.
    await Future<void>.delayed(const Duration(seconds: 1));

    // Zone 4 — écoute vocale automatique (micro + ONNX). Jamais bloquant.
    try {
      await _askVoiceConsent();
    } catch (e) {
      _recordZoneFailure('vocal', '$e');
    }

    _enterStateInProgress = false;
  }

  /// Persiste une défaillance de zone dans SharedPreferences
  /// (`trip_active_zone_errors`) et l'affiche en SnackBar : permet de tracer
  /// la cause exacte du prochain échec sur l'appareil.
  Future<void> _recordZoneFailure(String zone, String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('trip_active_zone_errors') ?? '';
      final line = DateTime.now().toIso8601String();
      await prefs.setString(
        'trip_active_zone_errors',
        '$existing\n$line [$zone] $message',
      );
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zone « $zone » : $message', maxLines: 3),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Pendant EN_COURS, détecte une clôture automatique (10 min sans action)
  /// ou une fin déclenchée par l'autre partie : dès que le statut redevient
  /// TERMINE/ANNULE, on arrête le suivi et on affiche le récapitulatif (P6).
  void _startEndPoll() {
    _endPoll?.cancel();
    if (_trip == null) return;
    final tripId = _trip!.id;
    _endPoll = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final fresh = await _tripService.tripStatus(tripId);
        if (!mounted) return;
        if (fresh.statut == 'TERMINE' || fresh.statut == 'ANNULE') {
          _endPoll?.cancel();
          _tracker?.cancel();
          BackgroundLocationService().stopTripTracking();
          await _stopVoiceMonitoring();
          if (!mounted) return;
          setState(() => _trip = fresh);
          if (fresh.statut == 'TERMINE') {
            _showTripSummary(fresh);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
              content: Text('Le trajet a été annulé.'),
              backgroundColor: AppTheme.sosRed,
            ),
          );
          _goHome();
          }
        }
      } catch (_) {
        // Réseau indisponible — on réessaiera au prochain tick.
      }
    });
  }

  /// Charge la météo pour la position actuelle du trajet.
  Future<void> _loadWeather() async {
    if (_weatherLoading || !mounted) return;
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
      // Gate contacts AVANT d'activer l'écoute : un SOS vocal automatique ne
      // doit pouvoir partir que si les contacts d'urgence sont enregistrés
      // (le déclenchement est ensuite non interactif).
      if (!mounted) return;
      final contactsOk = await ensureEmergencyContacts(context);
      if (!mounted) return;
      if (!contactsOk) {
        setState(() => _voiceStatus = 'Écoute non activée : contacts d\'urgence requis');
        return;
      }
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
      // EN_ATTENTE_TRANSPORTEUR : le transporteur doit maintenant accepter.
      if (trip.statut == 'EN_ATTENTE_TRANSPORTEUR') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course proposée au transporteur. En attente de son accord…')),
        );
        return;
      }
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
      double lat;
      double lng;
      // Lieu choisi depuis l'autocomplete Douala : coordonnées déjà connues.
      if (_selectedPlace != null) {
        lat = _selectedPlace!.latitude;
        lng = _selectedPlace!.longitude;
      } else {
        // Saisie libre : géocodage réel (OpenStreetMap Nominatim, gratuit)
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
        lat = coords.latitude;
        lng = coords.longitude;
      }
      final trip = await _tripService.setDestination(
        _trip!.id,
        address,
        lat,
        lng,
      );
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _busy = false;
        _placeSuggestions = [];
        _editingDestination = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Recherche des lieux de Douala à la frappe (liste locale, hors-ligne).
  void _onDestinationChanged(String value) {
    if (_applyingSuggestion) return;
    _destinationDebounce?.cancel();
    setState(() {
      _selectedPlace = null;
      _placeSuggestions = DoualaPlaces.search(value);
      _previewRoute = [];
      _previewOrigin = null;
    });
  }

  /// Sélection d'un lieu proposé : remplit le champ, trace le circuit
  /// (OSRM, repli ligne droite) depuis la position GPS vers le lieu.
  Future<void> _selectPlace(DoualaPlace place) async {
    _destinationDebounce?.cancel();
    _applyingSuggestion = true;
    _destinationController.text = place.name;
    _applyingSuggestion = false;
    setState(() {
      _selectedPlace = place;
      _placeSuggestions = [];
      _previewRoute = [];
      _previewOrigin = null;
      _previewRouteLoading = true;
    });

    LatLng? origin;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
      );
      origin = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) origin = LatLng(last.latitude, last.longitude);
      } catch (_) {
        if (_trip?.startLatitude != null && _trip!.startLongitude != null) {
          origin = LatLng(_trip!.startLatitude!, _trip!.startLongitude!);
        }
      }
    }

    if (!mounted) return;
    final to = LatLng(place.latitude, place.longitude);
    final route = await OsrmService.route(origin ?? _mapFallback, to);
    if (!mounted) return;
    setState(() {
      _previewOrigin = origin;
      _previewRoute = route;
      _previewRouteLoading = false;
    });
    _fitDestination(route, origin);
  }

  /// Recentre + zoom la carte d'aperçu sur le circuit proposé.
  void _fitDestination(List<LatLng> route, LatLng? origin) {
    final points = <LatLng>[
      ?origin,
      if (route.isNotEmpty) route.last,
      ...route,
    ];
    if (points.isEmpty) return;
    try {
      _destinationMapController.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(60)),
      );
    } catch (_) {
      // caméra pas encore attachée — initialCenter gère le premier affichage
    }
  }

  /// Carte embarquée dans l'étape destination : lieu choisi (marqueur) +
  /// circuit tracé (OSRM, repli ligne droite) depuis la position GPS.
  ///
  /// La carte reste montée même quand aucun lieu n'est sélectionné
  /// (`maintainState: true`) : la démonter à chaque frappe déclencherait un
  /// re-montage brusque de son InheritedElement et l'assertion
  /// `_dependents.isEmpty` en debug. On la masque simplement.
  Widget _destinationPreviewMapCard() {
    final place = _selectedPlace;
    final hasPlace = place != null;

    final to = place != null ? LatLng(place.latitude, place.longitude) : null;
    final origin = _previewOrigin;

    return Visibility(
      visible: hasPlace,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: true,
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
              child: Row(
                children: [
                  const Icon(Icons.route, size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 6),
                  Text(
                    place != null ? 'Circuit vers ${place.name}' : '',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (origin != null && hasPlace)
                    IconButton(
                      icon: const Icon(Icons.center_focus_strong, size: 18),
                      tooltip: 'Voir tout le circuit',
                      onPressed: () => _fitDestination(_previewRoute, _previewOrigin),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _destinationMapController,
                    options: MapOptions(
                      initialCenter: origin ?? to ?? _mapFallback,
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.tech.saveride',
                      ),
                      if (_previewRoute.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _previewRoute,
                              color: Colors.blue,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (origin != null)
                            Marker(
                              point: origin,
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38)],
                                ),
                              ),
                            ),
                          if (to != null)
                            Marker(
                              point: to,
                              width: 34,
                              height: 34,
                              child: const Icon(Icons.flag, color: Colors.red, size: 30),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (_previewRouteLoading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    // Single-flight : le timer 10 s ne doit jamais empiler des fix GPS
    // concurrents (requêtes natives simultanées = crash sur appareils lents).
    if (_sendingLocation) return;
    _sendingLocation = true;
    try {
      // Haute précision, avec borne : un fix qui pend ne doit pas bloquer
      // les ticks suivants ni accumuler les requêtes natives.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      // Vitesse parfois négative quand indisponible (iOS : -1) : le backend
      // exige min:0 — on borne pour ne jamais créer de ligne 422 empoisonnée.
      final speedKmh = (position.speed * 3.6).clamp(0.0, double.infinity);
      await _offline.sendLocation(
        _trip!.id,
        position.latitude,
        position.longitude,
        speedKmh,
      );
      // Transporteur : publie aussi la position de son VÉHICULE (toutes les
      // ~30 s via le throttle) — indispensable pour que la vérification de
      // proximité ±50m au scan suivant soit réellement active.
      _publishVehiclePositionThrottled(position.latitude, position.longitude);
      _updateLiveMap(
        LatLng(position.latitude, position.longitude),
        speedKmh: speedKmh,
      );
    } catch (_) {
      // GPS indisponible : le service de fond réessaiera
    } finally {
      _sendingLocation = false;
    }
    await _refreshPending();
  }

  // ── Position véhicule (transporteur) ────────────────────────────────
  DateTime _lastVehiclePositionAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Publie POST /vehicles/{id}/position au plus toutes les 30 s pendant
  /// un trajet actif — active la vérification de proximité au scan QR.
  void _publishVehiclePositionThrottled(double lat, double lng) {
    if (!_isTransporteur) return;
    // Suivi maintenu aussi pendant la négociation de fin (FIN_EN_ATTENTE) :
    // la proximité du prochain scan en dépend.
    if (_trip?.statut != 'EN_COURS' && _trip?.statut != 'FIN_EN_ATTENTE') {
      return;
    }
    if (_trip?.vehicleId == null) return;

    final now = DateTime.now();
    if (now.difference(_lastVehiclePositionAt).inSeconds < 30) return;
    _lastVehiclePositionAt = now;

    // Silencieux : la position véhicule est un service d'appui, jamais bloquant.
    _api
        .post('/vehicles/${_trip!.vehicleId}/position', {
          'latitude': lat,
          'longitude': lng,
        })
        .then((_) {}, onError: (_) {});
  }

  /// Position GPS connue (cache) affichée aussitôt à l'entrée EN_COURS,
  /// en attendant le 1er fix : la carte n'est jamais "en chargement".
  Future<void> _seedLivePosition() async {
    if (_livePosition != null || !mounted) return;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;
      final pos = LatLng(last.latitude, last.longitude);
      setState(() {
        _livePosition = pos;
        _liveRoute = [..._liveRoute, pos];
      });
      try {
        _mapController.move(pos, 18);
      } catch (_) {}
      _maybeRecalcRemainingRoute(pos);
    } catch (_) {}
  }

  /// Met à jour la carte live : position de l'utilisateur + itinéraire réel
  /// accumulé. Recentre + zoom précis (18) sur la position pour que
  /// l'utilisateur se voie clairement sur la route.
  ///
  /// Filtre ANTI-DÉRIVE GPS : à l'arrêt, le capteur erre de ±15 m et chaque
  /// tick dessinait un faux déplacement (spaghetti bleu + "il s'est déplacé
  /// alors qu'il est sur place"). En dessous de 15 m ET sous 11 km/h, le
  /// point est ignoré pour l'affichage (marqueur figé, pas de setState).
  /// L'envoi serveur continue normalement (heartbeat pour la clôture auto).
  static const double _driftThresholdM = 15;
  static const double _movingSpeedKmh = 11;

  void _updateLiveMap(LatLng position, {double speedKmh = 0}) {
    if (!mounted) return;
    final reference =
        _liveRoute.isNotEmpty ? _liveRoute.last : _livePosition;
    if (reference != null && _liveRoute.isNotEmpty) {
      final movedM = const Distance()(reference, position);
      if (movedM < _driftThresholdM && speedKmh < _movingSpeedKmh) {
        return; // bruit de capteur à l'arrêt : on fige l'affichage
      }
    }
    setState(() {
      _livePosition = position;
      _liveRoute = [..._liveRoute, position];
    });
    try {
      if (_livePosition != null) {
        _mapController.move(position, 18);
      }
    } catch (_) {
      // caméra non encore attachée — le initialZoom s'occupe du premier affichage
    }
    // Recalcule l'itinéraire restant (collé aux routes) de façon throttlée.
    _maybeRecalcRemainingRoute(position);
  }

  /// Recalcule l'itinéraire restant position → destination via OSRM (routes
  /// réelles). Throttle : 45 s minimum ET 100 m de déplacement — évite de
  /// spammer le serveur public à chaque fix GPS (10 s).
  Future<void> _maybeRecalcRemainingRoute(LatLng position) async {
    final trip = _trip;
    if (trip == null ||
        (trip.statut != 'EN_COURS' && trip.statut != 'FIN_EN_ATTENTE')) {
      return;
    }
    final destLat = trip.destinationLatitude;
    final destLng = trip.destinationLongitude;
    if (destLat == null || destLng == null) return;
    final now = DateTime.now();
    final lastPos = _lastRouteRecalcPos;
    if (lastPos != null) {
      final movedM = const Distance()(lastPos, position);
      if (now.difference(_lastRouteRecalcAt).inSeconds < 45 && movedM < 100) {
        return;
      }
    }
    _lastRouteRecalcAt = now;
    _lastRouteRecalcPos = position;
    try {
      final pts = await OsrmService.route(
        position,
        LatLng(destLat, destLng),
      );
      if (!mounted) return;
      // > 2 points = vrai itinéraire routier (le repli hors-ligne [from, to]
      // ne compte pas : on garde l'ancien tracé plutôt qu'une ligne droite).
      if (pts.length > 2) setState(() => _remainingRoute = pts);
    } catch (_) {}
  }

  /// Centre la carte sur la position courante de l'utilisateur (zoom précis).
  static Widget _mapLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textGrey)),
      ],
    );
  }
  void _centerMapOnUser() {
    final pos = _livePosition;
    if (pos == null) {
      _sendLocation();
      return;
    }
    _mapController.move(pos, 18);
  }

  /// Fin à DOUBLE confirmation : le 1er clic propose (on reste, le poll
  /// détectera le TERMINE et ouvrira le récapitulatif), le 2e clic de
  /// l'AUTRE partie termine réellement.
  Future<void> _endTrip() async {
    if (_trip == null) return;
    setState(() => _busy = true);
    try {
      final trip = await _tripService.endTrip(_trip!.id);
      if (!mounted) return;
      if (trip.statut == 'TERMINE') {
        _tracker?.cancel();
        BackgroundLocationService().stopTripTracking();
        await _stopVoiceMonitoring();
        setState(() {
          _trip = trip;
          _busy = false;
        });
        _showTripSummary(trip);
        return;
      }
      // Fin proposée, en attente de l'autre partie : suivi maintenu.
      setState(() {
        _trip = trip;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fin proposée. En attente de confirmation de l\'autre partie (clôture auto après 24h sans réponse).',
          ),
        ),
      );
      _enterState();
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
      if (!mounted) return;
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
      if (mounted) setState(() => _voiceStatus = 'Mot détecté "$word" : vérification vocale…');
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
      if (data['queued'] == true) {
        if (!mounted) return;
        setState(() => _voiceStatus = 'SOS vocal enregistré hors-ligne — sera transmis à la reconnexion');
        await Future<void>.delayed(const Duration(seconds: 5));
        if (mounted && _trip?.statut == 'EN_COURS' || _trip?.statut == 'FIN_EN_ATTENTE') {
          _voiceMonitoring = false;
          await _startVoiceMonitoring();
        }
        return;
      }
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
      if (mounted && _trip?.statut == 'EN_COURS' || _trip?.statut == 'FIN_EN_ATTENTE') {
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
      if (mounted && _trip?.statut == 'EN_COURS' || _trip?.statut == 'FIN_EN_ATTENTE') {
        _voiceMonitoring = false;
        await _startVoiceMonitoring();
      }
    } finally {
      _autoSosSending = false;
    }
  }

  /// SOS DIRECT depuis le trajet : un simple clic déclenche immédiatement
  /// l'alerte (sans passer par l'écran SOS vocal) puis affiche "c'est fait".
  /// Même séquence que le bouton SOS de l'accueil : gate contacts d'urgence,
  /// position GPS, trigger bouton, WhatsApp best-effort, compteur, message.
  Future<void> _triggerSosDirect() async {
    final trip = _trip;
    if (trip == null || _autoSosSending || _busy) return;
    if (!mounted) return;
    if (!await ensureEmergencyContacts(context)) return;
    if (!mounted) return;
    setState(() => _autoSosSending = true);
    try {
      final pos = await _autoPosition();
      final data = await _sosService.triggerButton(
        trip.id,
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      if (data['queued'] == true) {
        _goHomeWithMessage(
          'Alerte SOS enregistrée hors-ligne — sera transmise à la reconnexion.',
          color: Colors.orange.shade800,
        );
        return;
      }
      // WhatsApp best-effort aux contacts d'urgence.
      try {
        final contacts = data['emergency_contacts'] as List<dynamic>? ?? [];
        final sms = data['sms_message'] as String?;
        if (contacts.isNotEmpty && sms != null && sms.isNotEmpty) {
          final phones = contacts
              .map(
                (c) => ((c['whatsapp_telephone'] as String?)?.trim().isNotEmpty == true
                        ? c['whatsapp_telephone'] as String
                        : c['telephone'] as String?)
                    ?.trim(),
              )
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .toList();
          if (phones.isNotEmpty) {
            await WhatsAppService.instance.sendBulk(phones, sms);
          }
        }
      } catch (_) {}
      try {
        await AlertCounterService.increment();
      } catch (_) {}
      if (!mounted) return;
      _goHomeWithMessage('Alerte SOS envoyée. Vos contacts ont été notifiés.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS en attente de connexion : $e')),
      );
    } finally {
      if (mounted) setState(() => _autoSosSending = false);
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
            const SizedBox(height: 14),
            const Icon(Icons.star_outline, color: AppTheme.primaryBlue),
            const SizedBox(height: 4),
            Text(
              LanguageService.instance.t('rate_trip_optional'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!mounted) return;
              _goHomeWithMessage('Trajet terminé avec succès.');
            },
            child: Text(LanguageService.instance.t('rate_later')),
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
                _goHomeWithMessage('Merci pour votre avis. Trajet terminé.');
              });
            },
            icon: const Icon(Icons.star_rate),
            label: Text(LanguageService.instance.t('rate_trip')),
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
          if (trip.statut == 'EN_COURS' || trip.statut == 'FIN_EN_ATTENTE')
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
      case 'EN_ATTENTE_TRANSPORTEUR':
        if (_isTransporteur) return _transporteurWaitingStep(trip);
        return _waitingTransporteurStep(trip);
      case 'CONFIRME':
        if (_isTransporteur) return _transporteurWaitingStep(trip);
        return _destinationStep(trip, editing: _editingDestination);
      case 'DESTINATION_PROPOSEE':
        if (_isTransporteur) return _transporteurWaitingStep(trip);
        // Après un refus ("Non, corriger"), on réaffiche le formulaire
        // d'édition au lieu de boucler sur l'écran de confirmation.
        if (_editingDestination) return _destinationStep(trip, editing: true);
        return _destinationConfirmStep(trip);
      case 'DESTINATION_CONFIRMEE':
        // État transitoire (confirm_destination bascule aussitôt en
        // EN_COURS) : afficher l'étape en cours plutôt que "cloturé".
        return _enCoursStep(trip);
      case 'EN_COURS':
        return _enCoursStep(trip);
      case 'FIN_EN_ATTENTE':
        return _finEnAttenteStep(trip);
      default:
        return Center(child: Text('Trajet cloturé.'));
    }
  }

  /// Le transporteur a accepté la course : il attend que le passager
  /// définisse/confirme la destination. Poll du statut pour détecter la
  /// transition CONFIRME → DESTINATION_PROPOSEE → EN_COURS et démarrer
  /// automatiquement le suivi (T3).
  Widget _transporteurWaitingStep(Trip trip) {
    _scheduleWaitingPoll(trip.id);
    final passager = trip.passager;
    final passagerName = passager != null
        ? '${passager['prenom'] ?? ''} ${passager['nom'] ?? ''}'.trim()
        : 'le passager';
    final waitingFor = trip.statut == 'CONFIRME'
        ? 'Le passager définit sa destination…'
        : 'Le passager confirme la destination…\nDès confirmation, le trajet démarre automatiquement.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: AppTheme.primaryBlue),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Icon(Icons.hourglass_top, size: 40, color: AppTheme.primaryBlue),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Course de $passagerName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            waitingFor,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
          ),
        ),
      ],
    );
  }

  /// Le passager attend que le transporteur accepte la course.
  /// Poll du statut toutes les 3 s jusqu'à CONFIRME (→ destination) ou ANNULE.
  Widget _waitingTransporteurStep(Trip trip) {
    _scheduleWaitingPoll(trip.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Center(child: SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: AppTheme.primaryBlue))),
        const SizedBox(height: 20),
        const Center(child: Icon(Icons.handshake, size: 40, color: AppTheme.primaryBlue)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Demande envoyée à ${trip.transporteurFullName.isEmpty ? "votre transporteur" : trip.transporteurFullName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Le transporteur doit accepter la course.\nDès son accord, vous pourrez définir votre destination.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textGrey),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _cancelByPassenger(trip.id),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Annuler la demande'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.sosRed,
            side: BorderSide(color: AppTheme.sosRed.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  /// Ouvre la fiche de partage : lien de suivi GPS public, à envoyer
  /// à un proche. La page se met à jour en direct tant que le trajet est actif.
  Future<void> _sharePosition(int tripId) async {
    setState(() => _shareBusy = true);
    String? url;
    try {
      final res = await _api.get('/trips/$tripId/share-link');
      url = res['url'] as String?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de générer le lien : $e')),
        );
      }
    }
    if (mounted) setState(() => _shareBusy = false);
    if (url == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suivi GPS en direct'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Envoyez ce lien à un proche : il verra votre position bouger '
              'en direct sur une carte, sans installer l\'application. '
              'Le suivi se coupe automatiquement à la fin du trajet.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              url!,
              style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url!));
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lien copié')),
                );
              }
            },
            child: const Text('Copier le lien'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final wa = Uri.parse(
                'https://wa.me/?text=${Uri.encodeComponent('Je suis en trajet SafeRide, suis ma position en direct : $url')}',
              );
              if (!await launchUrl(wa, mode: LaunchMode.externalApplication)) {
                await launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Partager'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelByPassenger(int tripId) async {
    setState(() => _busy = true);
    try {
      await _api.post('/trips/$tripId/cancel', {});
      _waitingPoll?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.instance.t('trip_cancelled_by_passenger'))),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Démarre le poll du statut seulement APRÈS la frame du build courant.
  /// Lancer un `Timer.periodic` pendant `build` (où ces widgets sont
  /// construits) peut faire tomber un tick pendant la transition de route
  /// → `_dependents.isEmpty`. Le post-frame garantit un élément stable.
  void _scheduleWaitingPoll(int tripId) {
    if (_waitingPoll?.isActive ?? false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startWaitingPoll(tripId);
    });
  }

  void _startWaitingPoll(int tripId) {
    if (_waitingPoll?.isActive ?? false) return;
    _waitingPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final trip = await _tripService.tripStatus(tripId);
        if (!mounted) return;
        if (trip.statut != _trip?.statut) {
          setState(() => _trip = trip);
          _enterState();
        }
      } catch (_) {}
    });
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _cancelByPassenger(trip.id),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Annuler la demande'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.sosRed,
            side: BorderSide(color: AppTheme.sosRed.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _destinationStep(Trip trip, {bool editing = false}) {
    return SingleChildScrollView(
      child: Column(
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
            onChanged: _onDestinationChanged,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Ex : Marché Central, Douala',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _selectedPlace != null
                  ? IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      tooltip: 'Destination sélectionnée',
                      onPressed: () {},
                    )
                  : null,
              labelText: editing ? 'Nouvelle destination' : null,
            ),
          ),
          if (_placeSuggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Card(
              elevation: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _placeSuggestions.length,
                  itemBuilder: (context, index) {
                    final place = _placeSuggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, color: AppTheme.primaryBlue),
                      title: Text(place.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${place.category} • ${place.ville}', style: const TextStyle(fontSize: 11)),
                      onTap: () => _selectPlace(place),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _destinationPreviewMapCard(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _confirmDestination,
            icon: const Icon(Icons.check),
            label: Text(LanguageService.instance.t('propose_destination')),
          ),
        ],
      ),
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

  /// Carte live du trajet en cours : position GPS de l'utilisateur
  /// superposée à l'itinéraire, zoom précis (18) pour se voir sur la route.
  Widget _liveMapCard(Trip trip) {
    // Centre : position live, sinon point de DÉPART du trajet (le passager
    // voit sa zone même avant le 1er fix GPS), sinon Douala. Avant, le repli
    // générique affichait une carte "vide" côté passager sans fix.
    final tripStart = trip.startLatitude != null && trip.startLongitude != null
        ? LatLng(trip.startLatitude!, trip.startLongitude!)
        : null;
    final center = _livePosition ?? tripStart ?? _mapFallback;
    final destination = trip.destinationLatitude != null && trip.destinationLongitude != null
        ? LatLng(trip.destinationLatitude!, trip.destinationLongitude!)
        : null;
    // Carte XXL : plus de la moitié de l'écran sur tout appareil (55 % de
    // la hauteur, bornée 340–600 px pour très petits/grands écrans).
    final mapHeight =
        (MediaQuery.of(context).size.height * 0.55).clamp(340.0, 600.0).toDouble();

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
            child: Row(
              children: [
                const Icon(Icons.my_location, size: 16, color: AppTheme.primaryBlue),
                const SizedBox(width: 6),
                Text(
                  _livePosition != null ? 'Ma position — zoom 18' : 'Localisation…',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                  tooltip: 'Recentrer sur moi',
                  onPressed: _centerMapOnUser,
                ),
              ],
            ),
          ),
          // Légende : bleu = déjà parcouru (GPS), vert = reste à parcourir
          // (routes réelles), orange = itinéraire prévu au départ.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                _mapLegendDot(Colors.blue, 'Parcouru'),
                _mapLegendDot(Colors.green.shade700, 'Reste (routes)'),
                _mapLegendDot(Colors.orange, 'Prévu'),
              ],
            ),
          ),
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      // Secours si les tuiles OSM sont bloquées/rates (réseau
                      // opérateur) : fond Carto Voyager, même système de tuiles.
                      fallbackUrl:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                      userAgentPackageName: 'com.tech.saveride',
                      maxZoom: 19,
                    ),
                    if (_liveRoute.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _liveRoute,
                            color: Colors.blue,
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    if (_plannedRoute.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _plannedRoute,
                            color: Colors.orange,
                            strokeWidth: 2,
                            pattern: StrokePattern.dashed(segments: const [8.0, 6.0]),
                          ),
                        ],
                      ),
                    // Itinéraire RESTANT (position → destination) recalculé via
                    // OSRM : suit toujours les vraies routes. Remplace l'ancien
                    // trait pointillé droit qui coupait à travers les îlots.
                    if (_remainingRoute.length > 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _remainingRoute,
                            color: Colors.green.shade700,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_livePosition != null)
                          Marker(
                            point: _livePosition!,
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38)],
                              ),
                            ),
                          ),
                        // Destination à son VRAI emplacement + NOM affiché :
                        // à l'arrivée on voit où et comment s'appelle le lieu.
                        if (destination != null)
                          Marker(
                            point: destination,
                            width: 180,
                            height: 72,
                            alignment: Alignment.bottomCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.shade300),
                                      boxShadow: const [
                                        BoxShadow(
                                          blurRadius: 4,
                                          color: Colors.black26,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      trip.destinationAddress?.isNotEmpty == true
                                          ? trip.destinationAddress!
                                          : 'Destination',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                  size: 30,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Pas de fix GPS : la carte RESTE visible et interactive (centrée
                // sur le départ) + simple pastille d'attente avec bouton
                // réessayer. Avant, un voile spinner bloquait toute la carte
                // "sans fin" quand le GPS ne fixait pas.
                if (_livePosition == null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Position GPS en attente…',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _sendLocation,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Réessayer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Fin proposée, en attente de co-confirmation (FIN_EN_ATTENTE).
  /// - Demandeur : "en attente de l'autre" (pas de bouton, la demande est faite).
  /// - Autre partie : "X dit que la course est terminée, confirmez-vous ?"
  ///   + bouton "Oui, terminer" (2e clic → TERMINE côté serveur).
  Widget _finEnAttenteStep(Trip trip) {
    final iAmTransporteur = _isTransporteur;
    final askedBy = trip.finDemandeePar;
    final iAsked = askedBy != null &&
        ((askedBy == 'transporteur') == iAmTransporteur);
    final otherName = iAmTransporteur
        ? ((trip.passager?['prenom']?.toString() ?? '') +
                ' ' +
                (trip.passager?['nom']?.toString() ?? ''))
            .trim()
        : trip.transporteurFullName;
    final otherLabel =
        otherName.isNotEmpty ? otherName : 'l\'autre partie';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    size: 40,
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    iAsked
                        ? 'Fin de course proposée'
                        : '$otherLabel indique que la course est terminée',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    iAsked
                        ? 'En attente de confirmation de $otherLabel.\nSans réponse sous 24h, le trajet sera clôturé automatiquement.'
                        : 'Confirmez-vous que la course est bien terminée ?\nSans réponse sous 24h, le trajet sera clôturé automatiquement.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!iAsked) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _endTrip,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text(
                'Oui, terminer la course',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Text(
            'Le suivi GPS reste actif jusqu\'à la confirmation des deux côtés.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppTheme.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _enCoursStep(Trip trip) {
    // E.23 : hiérarchie priorité — destination + SOS toujours visibles.
    // Scrollable : la carte + les cartes + les boutons dépassent la hauteur
    // utile sur la plupart des téléphones (les boutons Terminer/SOS étaient
    // coupés — "on ne voit pas toutes les informations").
    return SingleChildScrollView(
      child: Column(
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
        // Carte live : position de l'utilisateur sur la route, zoom précis.
        _liveMapCard(trip),
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
          // Clic direct = déclenchement immédiat de l'alerte (pas de détour
          // par l'écran SOS vocal) + message de confirmation.
          child: ElevatedButton.icon(
            onPressed: _autoSosSending || _busy ? null : _triggerSosDirect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.sosRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _autoSosSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sos),
            label: Text(_autoSosSending ? LanguageService.instance.t('processing') : LanguageService.instance.t('sos'), style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (_shareBusy || _busy || _autoSosSending) ? null : () => _sharePosition(trip.id),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: const BorderSide(color: AppTheme.primaryBlue),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: _shareBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share_location_outlined),
          label: Text(LanguageService.instance.t('share_position'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
      ],
      ),
    );
  }
}

class _RatingWrapper extends StatelessWidget {
  final Trip trip;
  const _RatingWrapper({required this.trip});
  @override
  Widget build(BuildContext context) => RatingScreen(trip: trip);
}