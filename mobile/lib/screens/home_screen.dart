import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import '../utils/safe_dialog.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip.dart';
import '../models/user.dart';
import '../data/douala_places.dart';
import '../services/alert_counter_service.dart';
import '../services/api_service.dart';
import '../services/anomaly_service.dart';
import '../services/language_service.dart';
import '../services/push_service.dart';
import '../services/sos_service.dart';
import '../services/trip_service.dart';
import '../services/whatsapp_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../widgets/anomaly_verification_dialog.dart';
import '../widgets/emergency_contacts_gate.dart';
import 'profile_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

class HomeScreen extends StatefulWidget {
  final User? user;

  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  User? _user;
  int _unread = 0;
  Timer? _timer;
  Timer? _pendingPoll;
  int _selectedIndex = 0;
  bool _checkingAnomalies = false;
  int? _handledRequestId;
  bool _requestDialogOpen = false;

  bool get _isGuest => _user == null;
  bool get _isTransporteur => _user?.hasRole('transporteur') == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = widget.user;
    if (!_isGuest) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        _refreshUnread();
        _checkAnomalies();
      });
      _refreshUnread();
      _checkAnomalies();
      PushService.instance.addRefreshListener(_refreshUnread);
      PushService.instance.addRefreshListener(_checkPendingRequest);
      _startPendingPoll();
      // RafraÃ®chir le user depuis le serveur (source de vÃ©ritÃ©) : le rÃ´le
      // en cache peut Ãªtre obsolÃ¨te (rÃ´le transporteur attribuÃ© aprÃ¨s le
      // login, connexion Google, etc.). Si le rÃ´le change (ex : devient
      // transporteur), on dÃ©marre le polling de demandes de course.
      _refreshUserFromServer();
    }
  }

  /// Recharge le profil serveur (rÃ´les Ã  jour) et dÃ©marre le polling
  /// transporteur si le rÃ´le vient d'Ãªtre dÃ©tectÃ©.
  Future<void> _refreshUserFromServer() async {
    try {
      final data = await _api.get('/auth/profile');
      final user = User.fromJson(data['user']);
      final wasTransporteur = _isTransporteur;
      if (!mounted) return;
      setState(() => _user = user);
      if (!wasTransporteur && _isTransporteur) {
        // Le rÃ´le est arrivÃ© aprÃ¨s le boot : dÃ©marrer le polling maintenant.
        _startPendingPoll();
      }
    } catch (_) {
      // Hors-ligne : on reste sur le user en cache.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pendingPoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isTransporteur) {
      // Au retour au premier plan : vÃ©rifie immÃ©diatement une demande en attente
      // (sinon la fenÃªtre n'apparaÃ®t jamais si l'app Ã©tait en arriÃ¨re-plan).
      _checkPendingRequest();
    }
  }

  void _startPendingPoll() {
    if (!_isTransporteur) return;
    // Idempotent : un seul timer de polling, mÃªme aprÃ¨s refresh du rÃ´le.
    if (_pendingPoll?.isActive ?? false) return;
    _pendingPoll = Timer.periodic(const Duration(seconds: 3), (_) => _checkPendingRequest());
    _checkPendingRequest();
  }

  /// Interroge le backend : un passager attend l'accord du transporteur
  /// (statut EN_ATTENTE_TRANSPORTEUR). Si oui â†’ fenÃªtre Accepter/Refuser.
  Future<void> _checkPendingRequest() async {
    if (_requestDialogOpen || !mounted) return;
    try {
      final trip = await TripService().pendingTrip();
      if (!mounted || trip == null) return;
      // Nouveau trajet (id diffÃ©rent) â†’ on affiche la fenÃªtre.
      if (trip.id == _handledRequestId) return;
      _handledRequestId = trip.id;
      _showAcceptRequestDialog(trip);
    } catch (_) {
      // route/ rÃ©seau : on rÃ©-essaiera au prochain tick
    }
  }

  Future<void> _showAcceptRequestDialog(Trip trip) async {
    if (_requestDialogOpen) return;
    _requestDialogOpen = true;
    final name = '${trip.passager?['prenom'] ?? ''} ${trip.passager?['nom'] ?? ''}'.trim();
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.notifications_active, color: AppTheme.primaryBlue),
          SizedBox(width: 8),
          Text('Nouvelle course'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$name souhaite dÃ©buter une course avec vous.', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          if (trip.vehicle != null) Text('${trip.vehicle?['marque']} ${trip.vehicle?['modele']} â€¢ ${trip.vehicle?['immatriculation']}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Refuser', style: TextStyle(color: AppTheme.sosRed))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue), child: const Text('Accepter la course')),
        ],
      ),
    );
    if (!mounted) return;
    _requestDialogOpen = false;
    if (accept == true) {
      try {
        final updated = await TripService().acceptCourse(trip.id);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/trip-active', arguments: updated);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } else {
      try {
        await TripService().declineCourse(trip.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course refusÃ©e')));
      } catch (_) {}
    }
  }

  /// VÃ©rifie les anomalies dÃ©tectÃ©es par l'IA en temps rÃ©el et demande
  /// confirmation Ã  l'utilisateur si une vÃ©rification est en attente.
  Future<void> _checkAnomalies() async {
    if (_checkingAnomalies) return;
    _checkingAnomalies = true;
    try {
      final verifications = await AnomalyService().getPending();
      if (!mounted || verifications.isEmpty) return;

      // Affiche les vÃ©rifications en attente une Ã  une.
      for (final v in verifications) {
        if (!mounted) return;
        await showAnomalyDialog(context, v);
      }
    } catch (_) {
      // silent â€” non bloquant
    } finally {
      _checkingAnomalies = false;
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final count = await _api.fetchUnreadCount();
      if (!mounted || count == _unread) return;
      setState(() => _unread = count);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.pushNamed(context, '/notifications');
    _refreshUnread();
  }

  void _requireAuth() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(Icons.lock, color: AppTheme.primaryBlue), SizedBox(width: 8), Text(LanguageService.instance.t('signup_required'))]),
        content: Text(LanguageService.instance.t('visitor_restricted_msg')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.instance.t('stay_as_guest'))),
          FilledButton(onPressed: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/register'); }, child: Text(LanguageService.instance.t('register'))),
        ],
      ),
    );
  }

  Future<void> _triggerManualSos() async {
    if (_isGuest) { _requireAuth(); return; }
    // Gate : au moins 2 contacts d'urgence (formulaire intÃ©grÃ© si manque) â€”
    // identique Ã  l'Ã©cran SOS dÃ©diÃ©, le bouton accueil ne doit pas contourner.
    if (!await ensureEmergencyContacts(context)) return;
    if (!mounted) return;
    final trip = await TripService().currentTrip();
    // Ne lier le trajet au SOS que s'il est rÃ©ellement EN_COURS :
    // un trajet SCANNE / EN_ATTENTE_TRANSPORTEUR serait rejetÃ© par le
    // backend (422 "Aucun trajet actif"). Sans trajet en cours, l'alerte
    // part avec position + destination saisie (SOS hors trajet).
    final linkable = (trip != null && trip.statut == 'EN_COURS') ? trip : null;
    final controller = TextEditingController();
    // Dialog unique : confirmation + destination facultative (SOS hors trajet).
    // Un seul showDialog Ã©vite d'ouvrir un second dialog pendant la transition
    // de sortie du premier (assertion _dependents.isEmpty).
    if (!mounted) return;
    final result = await showDialogSafe<({bool confirmed, String destination})>(
      context,
      (ctx) => AlertDialog(
        title: Row(children: [Icon(Icons.warning, color: AppTheme.sosRed), SizedBox(width: 8), Text(LanguageService.instance.t('sos'))]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(LanguageService.instance.t('sos_confirm_msg')),
            if (linkable == null) ...[
              const SizedBox(height: 16),
              // SÃ©lection rapide de destination (quartiers/marchÃ©s de Douala)
              // au lieu de la saisie libre : un tap remplit le champ.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final place in DoualaPlaces.all.take(12))
                    ActionChip(
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      label: Text(place.name),
                      onPressed: () => controller.text = place.name,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: LanguageService.instance.t('destination_optional'),
                  hintText: LanguageService.instance.t('destination_hint'),
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, (confirmed: false, destination: '')), child: Text(LanguageService.instance.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.sosRed),
            onPressed: () => Navigator.pop(ctx, (confirmed: true, destination: controller.text.trim())),
            child: Text(LanguageService.instance.t('trigger_sos')),
          ),
        ],
      ),
    );
    // La libÃ©ration est diffÃ©rÃ©e : le TextField de destination Ã©coute encore
    // le controller pendant l'animation de sortie du dialog. Un dispose()
    // synchrone dÃ©clencherait l'assertion ChangeNotifier `_dependents.isEmpty`
    // (framework.dart) â†’ Ã©cran rouge Ã  la premiÃ¨re saisie SOS hors trajet.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
    if (result == null || !result.confirmed) return;
    final destination = result.destination;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception(LanguageService.instance.t('location_permission_denied'));
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final data = await SosService().triggerButton(linkable?.id, pos.latitude, pos.longitude, destination: destination);
      if (data['queued'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.instance.t('sos_queued')), backgroundColor: AppTheme.sosRed, duration: Duration(seconds: 4)),
        );
        return;
      }
      final sms = data['sms_message'] as String?;
      final contacts = data['emergency_contacts'] as List<dynamic>? ?? [];
      final phones = contacts.map((c) => ((c['whatsapp_telephone'] as String?)?.trim().isNotEmpty == true ? c['whatsapp_telephone'] : c['telephone']) as String?).where((p) => p != null && p.isNotEmpty).cast<String>().toList();
      if (phones.isNotEmpty && sms != null) await WhatsAppService.instance.sendBulk(phones, sms);
      await AlertCounterService.increment();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SosService().resultMessage(data, bouton: true)),
        backgroundColor: AppTheme.sosRed,
        duration: Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
    }
  }

  Widget _buildBody() {
    if (_isGuest) {
      if (_selectedIndex == 1) return _GuestBlockedCard(onUnlock: _requireAuth, label: 'Historique');
      if (_selectedIndex == 2) return const _LocationPreview();
      if (_selectedIndex == 3) return _GuestBlockedCard(onUnlock: _requireAuth, label: 'Profil');
      return _GuestView(onAction: _requireAuth);
    }
    if (_selectedIndex == 1) return const _HistoryPreview();
    if (_selectedIndex == 2) return const _LocationPreview();
    if (_selectedIndex == 3) return ProfileScreen(user: _user, embedded: true);

    // Home (0) -> role view â€” disposition similaire passager/transporteur
    if (_user!.hasRole('admin')) return const _AdminView();
    if (_user!.hasRole('transporteur')) return _TransporteurView(user: _user);
    if (_user!.hasRole('gestionnaire')) return const _GestionnaireView();
    return _PassagerView(user: _user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.shield, color: AppTheme.textDark, size: 22),
        ),
        title: Text('SafeRide AI', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 15)),
        centerTitle: true,
        actions: [
          if (_isGuest)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.translate, color: LanguageService.instance.isFr ? AppTheme.primaryBlue : Colors.orange), tooltip: LanguageService.instance.t('translate_tooltip'), onPressed: () async { await LanguageService.instance.toggle(); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Langue : ${LanguageService.instance.t('language')}'))); }),
              Padding(padding: EdgeInsets.only(right: 12), child: FilledButton(onPressed: () => Navigator.pushNamed(context, '/register'), style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6)), child: Text(LanguageService.instance.isFr ? 'S\'inscrire' : 'Sign up', style: TextStyle(fontSize: 12)))),
            ]),
          if (!_isGuest)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.translate, color: LanguageService.instance.isFr ? AppTheme.primaryBlue : Colors.orange), tooltip: LanguageService.instance.t('translate_tooltip'), onPressed: () async { await LanguageService.instance.toggle(); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Langue : ${LanguageService.instance.t('language')}'))); }),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: AppTheme.textDark),
                    onPressed: _openNotifications,
                  ),
                  if (_unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: const BoxDecoration(color: AppTheme.sosRed, shape: BoxShape.circle),
                        child: Text('$_unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
            ]),
          if (!_isGuest)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.lightBlueBadge,
                child: Text(_user!.prenom.isNotEmpty ? _user!.prenom[0].toUpperCase() : '?', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _triggerManualSos,
        backgroundColor: AppTheme.sosRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.sos),
        label: Text(LanguageService.instance.t('sos').split(' ').first, style: TextStyle(fontWeight: FontWeight.w800)),
        tooltip: LanguageService.instance.t('sos_manual_tooltip'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: const Color(0xFF9AA0AE),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: LanguageService.instance.t('home')),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: LanguageService.instance.t('trips')),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: LanguageService.instance.t('map')),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: LanguageService.instance.t('profile')),
        ],
      ),
    );
  }
}

// Petites vues pour bottom nav
class _HistoryPreview extends StatelessWidget {
  const _HistoryPreview();
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history, size: 48, color: AppTheme.primaryBlue), SizedBox(height: 12), Text(LanguageService.instance.t('history'), style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 8), FilledButton(onPressed: () => Navigator.pushNamed(context, '/history'), child: Text(LanguageService.instance.t('history_full')))])));
}

class _LocationPreview extends StatefulWidget {
  const _LocationPreview();
  @override
  State<_LocationPreview> createState() => _LocationPreviewState();
}

class _LocationPreviewState extends State<_LocationPreview> {
  final _mapController = MapController();
  LatLng? _userLocation;
  StreamSubscription<Position>? _userTrackSub;
  bool _loading = true;
  bool _locating = false;

  static const LatLng _fallback =
      LatLng(DoualaPlaces.centerLatitude, DoualaPlaces.centerLongitude); // Douala (Akwa)

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
        );
        if (mounted) setState(() { _userLocation = LatLng(pos.latitude, pos.longitude); _loading = false; });
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (mounted) {
          setState(() {
            _userLocation = last != null ? LatLng(last.latitude, last.longitude) : null;
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // Suivi temps rÃ©el : le marqueur utilisateur doit suivre vos dÃ©placements
    // au lieu d'Ãªtre figÃ© sur une capture unique (position "respectÃ©e").
    _userTrackSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // ne rÃ©-Ã©met que si on bouge d'au moins 5 m
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
    });
  }

  Future<void> _centerOnUser() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final loc = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _userLocation = loc);
      _mapController.move(loc, 17);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.instance.t('location_unavailable'))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text(LanguageService.instance.t('locating'))]));
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _userLocation ?? _fallback, initialZoom: _userLocation != null ? 18 : 12),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.tech.saveride'),
            if (_userLocation != null)
              MarkerLayer(markers: [Marker(point: _userLocation!, width: 24, height: 24, alignment: Alignment.center, child: Container(decoration: BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38)])))]),
          ],
        ),
        Positioned(bottom: 16, right: 16, child: FloatingActionButton.small(onPressed: _centerOnUser, tooltip: LanguageService.instance.t('my_location'), child: _locating ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.my_location))),
        Positioned(bottom: 4, left: 0, right: 0, child: Container(color: Colors.grey.shade200, padding: EdgeInsets.all(4), child: Text(LanguageService.instance.t('map_credits'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11))))
      ],
    );
  }
}

class _PassagerView extends StatefulWidget {
  final dynamic user;
  const _PassagerView({this.user});

  @override
  State<_PassagerView> createState() => _PassagerViewState();
}

class _PassagerViewState extends State<_PassagerView> {
  WeatherData? _weather;
  bool _weatherLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    try {
      double lat = DoualaPlaces.centerLatitude, lng = DoualaPlaces.centerLongitude;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          final req = await Geolocator.requestPermission();
          if (req == LocationPermission.denied || req == LocationPermission.deniedForever) {
            if (mounted) setState(() => _weatherLoading = false);
            return;
          }
        } else if (permission == LocationPermission.deniedForever) {
          if (mounted) setState(() => _weatherLoading = false);
          return;
        }
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          );
          lat = position.latitude;
          lng = position.longitude;
        } catch (_) {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) { lat = last.latitude; lng = last.longitude; }
        }
      } catch (_) {}
      final weather = await WeatherService.instance.getCurrentWeather(lat, lng);
      if (mounted) setState(() { _weather = weather; _weatherLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.user?.prenom as String?) ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name.isEmpty ? LanguageService.instance.t('hello') : '${LanguageService.instance.t('hello')}, $name', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user, size: 16, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Expanded(child: Text(LanguageService.instance.t('verified_secure'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ]),
          ),
          const SizedBox(height: 10),
          // Carte mÃ©tÃ©o
          if (_weatherLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Chargement de la mÃ©tÃ©oâ€¦', style: TextStyle(fontSize: 13, color: AppTheme.textGrey)),
                ],
              ),
            )
          else if (_weather != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryBlue.withValues(alpha: 0.06),
                    AppTheme.primaryBlue.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.lightBlueBorder),
              ),
              child: Row(
                children: [
                  Icon(_weather!.icon, size: 32, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_weather!.tempDisplay, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                            if (_weather!.feelsLike != null)
                              Text(' (ressenti ${_weather!.feelsLike!.round()}Â°)', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                          ],
                        ),
                        Text(_weather!.description, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_weather!.precipitationProbability != null && _weather!.precipitationProbability! > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400),
                            const SizedBox(width: 3),
                            Text('${_weather!.precipitationProbability}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.air, size: 14, color: AppTheme.textGrey),
                          const SizedBox(width: 3),
                          Text('${_weather!.windDisplay} ${_weather!.windDirectionText}', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          // Carte noire scanner (maquette)
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/scan'),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBlack,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
                    child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(LanguageService.instance.t('scan_qr'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(LanguageService.instance.t('scan_qr_desc'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/sos-button'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: BoxDecoration(color: AppTheme.sosRed, borderRadius: BorderRadius.circular(14)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.sos, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        FittedBox(child: Text(LanguageService.instance.t('sos'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/ai'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.lightBlueBorder)),
                       child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.support_agent, size: 18, color: AppTheme.textDark),
                        SizedBox(width: 6),
                        FittedBox(child: Text(LanguageService.instance.t('assistance'), style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13))),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Section ordonnÃ©e : Mes services en grille 2x2
          Text(LanguageService.instance.t('services'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _serviceCard(Icons.trip_origin, LanguageService.instance.t('trip'), LanguageService.instance.t('trip_tracking'), () => Navigator.pushNamed(context, '/trip-active'))),
              const SizedBox(width: 10),
              Expanded(child: _serviceCard(Icons.gavel_outlined, LanguageService.instance.t('dispute'), LanguageService.instance.t('dispute_sub'), () => Navigator.pushNamed(context, '/dispute'))),
            ],
          ),
          const SizedBox(height: 10),
          _serviceCard(Icons.verified_user, LanguageService.instance.t('identity'), LanguageService.instance.t('identity_sub'), () => Navigator.pushNamed(context, '/identity'), color: AppTheme.primaryBlue),
        ],
      ),
    );
  }

  Widget _serviceCard(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: (color ?? AppTheme.primaryBlue).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: color ?? AppTheme.primaryBlue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppTheme.textGrey),
          ],
        ),
      ),
    );
  }
}

class _TransporteurView extends StatefulWidget {
  final dynamic user;
  const _TransporteurView({this.user});
  @override
  State<_TransporteurView> createState() => _TransporteurViewState();
}

class _TransporteurViewState extends State<_TransporteurView> {
  WeatherData? _weather;
  bool _weatherLoading = true;
  Trip? _pendingTrip;
  bool _handling = false;
  Timer? _pendingPoll;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _pollPending();
  }

  @override
  void dispose() {
    _pendingPoll?.cancel();
    super.dispose();
  }

  /// Poll la demande de course en attente â€” la carte reste visible en
  /// continu (pas seulement le dialogue automatique du HomeScreen) tant
  /// que le passager attend la rÃ©ponse du transporteur.
  void _pollPending() {
    _pendingPoll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_handling) return;
      try {
        final trip = await TripService().pendingTrip();
        if (!mounted) return;
        if ((trip?.id) != (_pendingTrip?.id)) {
          setState(() => _pendingTrip = trip);
        }
      } catch (_) {}
    });
  }

  Future<void> _respond(bool accept) async {
    if (_pendingTrip == null || _handling) return;
    setState(() => _handling = true);
    try {
      if (accept) {
        final updated = await TripService().acceptCourse(_pendingTrip!.id);
        if (!mounted) return;
        setState(() { _pendingTrip = null; _handling = false; });
        Navigator.of(context).pushReplacementNamed('/trip-active', arguments: updated);
      } else {
        await TripService().declineCourse(_pendingTrip!.id);
        if (!mounted) return;
        setState(() { _pendingTrip = null; _handling = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course refusÃ©e')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _handling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Widget _pendingRequestCard() {
    final trip = _pendingTrip!;
    final name = '${trip.passager?['prenom'] ?? ''} ${trip.passager?['nom'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue, width: 1.5),
        boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, shape: BoxShape.circle), child: const Icon(Icons.notifications_active, color: AppTheme.primaryBlue, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nouvelle course demandÃ©e', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
              const Text('Le passager attend votre rÃ©ponse', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ])),
          ]),
          const SizedBox(height: 12),
          Text(name.isEmpty ? 'Un passager' : name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          if (trip.vehicle != null)
            Text('${trip.vehicle?['marque']} ${trip.vehicle?['modele']} â€¢ ${trip.vehicle?['immatriculation']}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _handling ? null : () => _respond(false),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Refuser'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.sosRed, side: const BorderSide(color: AppTheme.sosRed)),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _handling ? null : () => _respond(true),
              icon: _handling ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 18),
              label: const Text('Accepter'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            )),
          ]),
        ],
      ),
    );
  }

  Future<void> _loadWeather() async {
    try {
      double lat = DoualaPlaces.centerLatitude, lng = DoualaPlaces.centerLongitude;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          final req = await Geolocator.requestPermission();
          if (req == LocationPermission.denied || req == LocationPermission.deniedForever) {
            if (mounted) setState(() => _weatherLoading = false);
            return;
          }
        } else if (permission == LocationPermission.deniedForever) {
          if (mounted) setState(() => _weatherLoading = false);
          return;
        }
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          );
          lat = position.latitude;
          lng = position.longitude;
        } catch (_) {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) { lat = last.latitude; lng = last.longitude; }
        }
      } catch (_) {}
      final weather = await WeatherService.instance.getCurrentWeather(lat, lng);
      if (mounted) setState(() { _weather = weather; _weatherLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.user?.prenom as String?) ?? 'Transporteur';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${LanguageService.instance.t('hello')}, $name', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user, size: 16, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Expanded(child: Text(LanguageService.instance.t('verified_carrier'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ]),
          ),
          const SizedBox(height: 10),
          // Demande de course en attente : carte persistante Accepter/Refuser
          if (_pendingTrip != null) _pendingRequestCard(),
          if (_weatherLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
              child: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Expanded(child: Text('Chargement de la mÃ©tÃ©oâ€¦', maxLines: 1, overflow: TextOverflow.ellipsis))]),
            )
          else if (_weather != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppTheme.primaryBlue.withValues(alpha: 0.06), AppTheme.primaryBlue.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.lightBlueBorder),
              ),
              child: Row(
                children: [
                  Icon(_weather!.icon, size: 32, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Text(_weather!.tempDisplay, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark)), if (_weather!.feelsLike != null) Text(' (ressenti ${_weather!.feelsLike!.round()}Â°)', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))]),
                      Text(_weather!.description, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (_weather!.precipitationProbability != null && _weather!.precipitationProbability! > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400), const SizedBox(width: 3), Text('${_weather!.precipitationProbability}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700))]),
                    Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.air, size: 14, color: AppTheme.textGrey), const SizedBox(width: 3), Text('${_weather!.windDisplay} ${_weather!.windDirectionText}', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))]),
                  ]),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const _TransporteurQrCard(),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, '/sos-button'), child: Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12), decoration: BoxDecoration(color: AppTheme.sosRed, borderRadius: BorderRadius.circular(14)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sos, color: Colors.white, size: 16), SizedBox(width: 6), FittedBox(child: Text(LanguageService.instance.t('sos'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))) ])))),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, '/ai'), child: Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12), decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.lightBlueBorder)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.support_agent, size: 18, color: AppTheme.textDark), SizedBox(width: 6), FittedBox(child: Text(LanguageService.instance.t('assistance'), style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13))) ])))),
            ]),
          ),
          const SizedBox(height: 18),
          Text(LanguageService.instance.t('services'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _serviceCard(Icons.dashboard, LanguageService.instance.t('dashboard'), LanguageService.instance.t('stats_notes'), '/transporteur-dashboard')), SizedBox(width: 10), Expanded(child: _serviceCard(Icons.directions_car, LanguageService.instance.t('vehicle'), LanguageService.instance.t('vehicle_qr'), '/vehicles'))]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _serviceCard(Icons.hearing, LanguageService.instance.t('hearing_course'), LanguageService.instance.t('auto_listening'), '/trip-active')), SizedBox(width: 10), Expanded(child: _serviceCard(Icons.verified_user, LanguageService.instance.t('identity'), LanguageService.instance.t('identity_sub'), '/identity', color: AppTheme.primaryBlue))]),
        ],
      ),
    );
  }

  Widget _serviceCard(IconData icon, String title, String subtitle, String route, {Color? color}) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: (color ?? AppTheme.primaryBlue).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: color ?? AppTheme.primaryBlue)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])),
          const Icon(Icons.chevron_right, size: 16, color: AppTheme.textGrey),
        ]),
      ),
    );
  }
}

/// QR Code du transporteur affichÃ© sur le Home Ã  la place de l'espace SCAN passager
/// RÃ¨gle : un seul vÃ©hicule autorisÃ© â€” affiche directement le QR du vÃ©hicule unique
class _TransporteurQrCard extends StatefulWidget {
  const _TransporteurQrCard();

  @override
  State<_TransporteurQrCard> createState() => _TransporteurQrCardState();
}

class _TransporteurQrCardState extends State<_TransporteurQrCard> with WidgetsBindingObserver {
  final _api = ApiService();
  String? _token;
  String? _immat;
  int? _vehicleId;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  int _refreshFailures = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadQr();
    // Le polling dÃ©marre TOUJOURS, mÃªme si le premier chargement Ã©choue :
    // _checkRefresh se ressynchronise automatiquement au tick suivant.
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Au retour au premier plan : le QR peut avoir Ã©tÃ© consommÃ© pendant
      // l'arriÃ¨re-plan (scan par le passager) â€” re-synchronisation immÃ©diate.
      _checkRefresh();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkRefresh());
  }

  Future<void> _checkRefresh() async {
    if (!mounted) return;
    // Pas encore de token (Ã©chec initial) â†’ on recharge complÃ¨tement le QR.
    if (_vehicleId == null || _token == null) {
      _loadQr();
      return;
    }
    try {
      final data = await _api.get('/vehicles/$_vehicleId/qr');
      final qr = data['qr'] as Map<String, dynamic>?;
      final newToken = qr?['token'] as String?;
      _refreshFailures = 0;
      if (newToken != null && newToken != _token && mounted) {
        setState(() => _token = newToken);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.instance.t('qr_regenerated')), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (_) {
      // Erreur rÃ©seau/401 : aprÃ¨s 5 Ã©checs consÃ©cutifs (â‰ˆ15 s), on recharge
      // entiÃ¨rement le QR (rÃ©-authentification + nouvelle lecture) au lieu
      // d'abandonner silencieusement.
      _refreshFailures++;
      if (_refreshFailures >= 5) {
        _refreshFailures = 0;
        _vehicleId = null;
        _token = null;
        _loadQr();
      }
    }
  }

  Future<void> _loadQr() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _api.get('/vehicles');
      final vehicles = data['vehicles'] as List<dynamic>? ?? [];
      if (vehicles.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = 'Aucun vÃ©hicule'; });
        return;
      }
      // Un seul vÃ©hicule autorisÃ© â€” prendre le premier
      final v = vehicles.first as Map<String, dynamic>;
      final immat = v['immatriculation'] as String? ?? '';
      final vehicleId = v['id'] as int;
      final qrData = await _api.get('/vehicles/$vehicleId/qr');
      final qr = qrData['qr'] as Map<String, dynamic>?;
      final token = qr?['token'] as String?;
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        setState(() { _loading = false; _error = 'QR indisponible'; _immat = immat; _vehicleId = vehicleId; });
      } else {
        setState(() { _token = token; _immat = immat; _vehicleId = vehicleId; _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Carte noire style passager "Scanner un QR Code" mais pour transporteur : affiche son QR
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppTheme.cardBlack, borderRadius: BorderRadius.circular(20)),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
      );
    }
    if (_error != null && _token == null) {
      return GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/vehicles'),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.cardBlack,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
                child: const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              Text(_error == 'Aucun vÃ©hicule' ? LanguageService.instance.t('no_vehicle') : LanguageService.instance.t('qr_unavailable'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_error == 'Aucun vÃ©hicule' ? LanguageService.instance.t('add_vehicle_hint') : 'Erreur: $_error', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/vehicles'), icon: Icon(Icons.add), label: Text(LanguageService.instance.t('add_vehicle'))),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBlack,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(LanguageService.instance.t('my_qr'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(_immat ?? '', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(
              data: _token!,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            ),
          ),
          const SizedBox(height: 10),
          Text(LanguageService.instance.t('present_qr'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(LanguageService.instance.t('qr_active'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _GuestView extends StatelessWidget {
  final VoidCallback onAction;
  const _GuestView({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(LanguageService.instance.t('welcome'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          Text(LanguageService.instance.t('guest_consult_text'), style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
          const SizedBox(height: 14),
          // AperÃ§u carte
          Container(
            height: 140,
            decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: Stack(children: [Center(child: Icon(Icons.map, size: 48, color: AppTheme.primaryBlue)), Positioned(top: 8, right: 8, child: Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Text(LanguageService.instance.t('yaounde_map'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))))]),
          ),
          const SizedBox(height: 14),
          // Scanner verrouillÃ©
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.cardBlack, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))), child: Icon(Icons.qr_code_scanner, color: Colors.white, size: 28)), SizedBox(height: 12), Text(LanguageService.instance.t('scan_qr'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)), SizedBox(height: 6), Text(LanguageService.instance.t('guest_locked'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)), SizedBox(height: 8), Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock, size: 12, color: Colors.white), SizedBox(width: 4), Text('InvitÃ©', style: TextStyle(color: Colors.white, fontSize: 11))]))]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: GestureDetector(onTap: onAction, child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppTheme.sosRed.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sos, color: Colors.white, size: 16), SizedBox(width: 6), Text('SOS URGENCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)), SizedBox(width: 4), Icon(Icons.lock, size: 12, color: Colors.white)])))), SizedBox(width: 10), Expanded(child: GestureDetector(onTap: onAction, child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.support_agent, size: 16, color: AppTheme.textGrey), SizedBox(width: 6), Text(LanguageService.instance.t('assistance'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), SizedBox(width: 4), Icon(Icons.lock, size: 12, color: AppTheme.textGrey)]))))]),
          const SizedBox(height: 18),
          Text(LanguageService.instance.t('services_preview'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          _guestCard(Icons.trip_origin, LanguageService.instance.t('trip'), '${LanguageService.instance.t('trip_tracking')} + SOS', onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.gavel_outlined, LanguageService.instance.t('dispute'), LanguageService.instance.t('lost_and_sos'), onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.verified_user, LanguageService.instance.t('identity'), LanguageService.instance.t('cni_passport'), onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.directions_car, LanguageService.instance.t('vehicles'), LanguageService.instance.t('vehicle_qr_label'), onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.dashboard, LanguageService.instance.t('dashboard'), LanguageService.instance.t('stats_carrier'), onAction),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/register'), icon: Icon(Icons.person_add), label: Text(LanguageService.instance.t('create_account_interact'))),
          const SizedBox(height: 6),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: Text(LanguageService.instance.t('has_account'))),
        ],
      ),
    );
  }

  static Widget _guestCard(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: Colors.grey)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)), const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock, size: 10, color: Colors.grey), SizedBox(width: 3), Text('InvitÃ©', style: TextStyle(fontSize: 10, color: Colors.grey))]))]), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])), const Icon(Icons.chevron_right, size: 16, color: Colors.grey)]),
      ),
    );
  }
}

class _GuestBlockedCard extends StatelessWidget {
  final VoidCallback onUnlock;
  final String label;
  const _GuestBlockedCard({required this.onUnlock, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 48, color: Colors.grey.shade400), const SizedBox(height: 12), Text('$label â€” mode invitÃ©', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), const Text('Inscrivez-vous pour accÃ©der Ã  cette section', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textGrey, fontSize: 12)), const SizedBox(height: 16), FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/register'), icon: const Icon(Icons.person_add), label: const Text('S\'inscrire')), TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Se connecter'))]),
      ),
    );
  }
}

class _GestionnaireView extends StatelessWidget {
  const _GestionnaireView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_open, size: 32),
              title: const Text('Mes dossiers'),
              subtitle: const Text('Litiges, objets perdus, SOS, identitÃ©s'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/manager'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminView extends StatelessWidget {
  const _AdminView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings, size: 32),
              title: const Text('Administration'),
              subtitle: const Text('Tableau de bord, utilisateurs, gestionnaires'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/admin'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history, size: 32),
              title: const Text('Historique des trajets'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/history'),
            ),
          ),
        ],
      ),
    );
  }
}
