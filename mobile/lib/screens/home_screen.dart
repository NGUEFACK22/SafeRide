import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/sos_service.dart';
import '../services/trip_service.dart';
import '../services/whatsapp_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../widgets/translate_dialog.dart';
import 'profile_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

class HomeScreen extends StatefulWidget {
  final User? user;

  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  User? _user;
  int _unread = 0;
  Timer? _timer;
  int _selectedIndex = 0;

  bool get _isGuest => _user == null;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    if (!_isGuest) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshUnread());
      _refreshUnread();
      PushService.instance.addRefreshListener(_refreshUnread);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
        title: const Row(children: [Icon(Icons.lock, color: AppTheme.primaryBlue), SizedBox(width: 8), Text('Inscription requise')]),
        content: const Text('Visiteur — vous pouvez consulter toutes les fonctionnalités, mais pour interagir avec le système (scanner, SOS, signaler, etc.), veuillez vous inscrire.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Rester en visite')),
          FilledButton(onPressed: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/register'); }, child: const Text('S\'inscrire')),
        ],
      ),
    );
  }

  Future<void> _triggerManualSos() async {
    if (_isGuest) { _requireAuth(); return; }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning, color: AppTheme.sosRed), SizedBox(width: 8), Text('SOS URGENCE')]),
        content: const Text('Déclencher une alerte SOS manuelle ?\nVos contacts d\'urgence, le gestionnaire et les services seront notifiés avec votre position.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')), FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.sosRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Déclencher SOS'))],
      ),
    );
    if (confirm != true) return;
    try {
      final trip = await TripService().currentTrip();
      if (trip == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun trajet actif — scannez le QR pour démarrer un trajet'), backgroundColor: Colors.orange));
        Navigator.pushNamed(context, '/trip-active');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception('Permission localisation refusée');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final data = await SosService().triggerButton(trip.id, pos.latitude, pos.longitude);
      final sms = data['sms_message'] as String?;
      final contacts = data['emergency_contacts'] as List<dynamic>? ?? [];
      final phones = contacts.map((c) => ((c['whatsapp_telephone'] as String?)?.trim().isNotEmpty == true ? c['whatsapp_telephone'] : c['telephone']) as String?).where((p) => p != null && p!.isNotEmpty).cast<String>().toList();
      if (phones.isNotEmpty && sms != null) await WhatsAppService.instance.sendBulk(phones, sms);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS manuel déclenché ✓ — contacts notifiés'), backgroundColor: AppTheme.sosRed, duration: Duration(seconds: 4)));
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

    // Home (0) -> role view — disposition similaire passager/transporteur
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
        title: const Text('SafeRide AI', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 15)),
        centerTitle: true,
        actions: [
          if (_isGuest)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.translate, color: AppTheme.primaryBlue), tooltip: 'Traduction EN↔FR', onPressed: () => showDialog(context: context, builder: (_) => const TranslateDialog())),
              Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(onPressed: () => Navigator.pushNamed(context, '/register'), style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)), child: const Text('S\'inscrire', style: TextStyle(fontSize: 12)))),
            ]),
          if (!_isGuest)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.translate, color: AppTheme.primaryBlue), tooltip: 'Traduction vocale EN↔FR', onPressed: () => showDialog(context: context, builder: (_) => const TranslateDialog())),
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
        label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w800)),
        tooltip: 'SOS manuel — appui pour déclencher',
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
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Accueil'),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Trajets'),
          const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Carte'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

// Petites vues pour bottom nav
class _HistoryPreview extends StatelessWidget {
  const _HistoryPreview();
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.history, size: 48, color: AppTheme.primaryBlue), const SizedBox(height: 12), const Text('Historique', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), FilledButton(onPressed: () => Navigator.pushNamed(context, '/history'), child: const Text('Voir l\'historique complet'))])));
}

class _LocationPreview extends StatefulWidget {
  const _LocationPreview();
  @override
  State<_LocationPreview> createState() => _LocationPreviewState();
}

class _LocationPreviewState extends State<_LocationPreview> {
  final _mapController = MapController();
  LatLng? _userLocation;
  bool _loading = true;
  bool _locating = false;

  static const LatLng _fallback = LatLng(3.8480, 11.5021); // Yaoundé

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
        if (mounted) setState(() {
          _userLocation = last != null ? LatLng(last.latitude, last.longitude) : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      _mapController.move(loc, 15);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Localisation indisponible')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Localisation en cours…')]));
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _userLocation ?? _fallback, initialZoom: _userLocation != null ? 15 : 12),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.tech.saveride'),
            if (_userLocation != null)
              MarkerLayer(markers: [Marker(point: _userLocation!, width: 24, height: 24, alignment: Alignment.center, child: Container(decoration: BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38)])))]),
          ],
        ),
        Positioned(bottom: 16, right: 16, child: FloatingActionButton.small(onPressed: _centerOnUser, tooltip: 'Ma position', child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location))),
        Positioned(bottom: 4, left: 0, right: 0, child: Container(color: Colors.grey.shade200, padding: const EdgeInsets.all(4), child: const Text('Cartes © OpenStreetMap', textAlign: TextAlign.center, style: TextStyle(fontSize: 11))))
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
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied) {
          if (mounted) setState(() => _weatherLoading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _weatherLoading = false);
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final name = (widget.user?.prenom as String?) ?? 'Jean';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bonjour, $name', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user, size: 16, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Expanded(child: Text('VOTRE COMPTE EST VÉRIFIÉ ET SÉCURISÉ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ]),
          ),
          const SizedBox(height: 10),
          // Carte météo
          if (_weatherLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Chargement de la météo…', style: TextStyle(fontSize: 13, color: AppTheme.textGrey)),
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
                              Text(' (ressenti ${_weather!.feelsLike!.round()}°)', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
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
                  const Text('Scanner un QR Code', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Appuyez ici pour démarrer ou vérifier une course sécurisée.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
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
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.sos, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        FittedBox(child: Text('SOS URGENCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
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
                       child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.support_agent, size: 18, color: AppTheme.textDark),
                        SizedBox(width: 6),
                        FittedBox(child: Text('ASSISTANCE', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13))),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Section ordonnée : Mes services en grille 2x2
          const Text('Mes services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _serviceCard(Icons.trip_origin, 'Trajet', 'Suivi GPS', () => Navigator.pushNamed(context, '/trip-active'))),
              const SizedBox(width: 10),
              Expanded(child: _serviceCard(Icons.gavel_outlined, 'Litige', 'Objets & SOS', () => Navigator.pushNamed(context, '/dispute'))),
            ],
          ),
          const SizedBox(height: 10),
          _serviceCard(Icons.verified_user, 'Identité', 'Vérifier', () => Navigator.pushNamed(context, '/identity'), color: AppTheme.primaryBlue),
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

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied) {
          if (mounted) setState(() => _weatherLoading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _weatherLoading = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
      );
      final weather = await WeatherService.instance.getCurrentWeather(position.latitude, position.longitude);
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
          Text('Bonjour, $name', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user, size: 16, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Expanded(child: Text('VOTRE COMPTE TRANSPORTEUR EST VÉRIFIÉ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ]),
          ),
          const SizedBox(height: 10),
          if (_weatherLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
              child: const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Chargement de la météo…', style: TextStyle(fontSize: 13, color: AppTheme.textGrey))]),
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
                      Row(children: [Text(_weather!.tempDisplay, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark)), if (_weather!.feelsLike != null) Text(' (ressenti ${_weather!.feelsLike!.round()}°)', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))]),
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
              Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, '/sos-button'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), decoration: BoxDecoration(color: AppTheme.sosRed, borderRadius: BorderRadius.circular(14)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sos, color: Colors.white, size: 16), SizedBox(width: 6), FittedBox(child: Text('SOS URGENCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))) ])))),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, '/ai'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.lightBlueBorder)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.support_agent, size: 18, color: AppTheme.textDark), SizedBox(width: 6), FittedBox(child: Text('ASSISTANCE', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13))) ])))),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('Mes services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _serviceCard(Icons.dashboard, 'Tableau de bord', 'Stats & notes', '/transporteur-dashboard')), const SizedBox(width: 10), Expanded(child: _serviceCard(Icons.directions_car, 'Véhicule', 'QR unique', '/vehicles'))]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _serviceCard(Icons.hearing, 'Course', 'Écoute auto', '/trip-active')), const SizedBox(width: 10), Expanded(child: _serviceCard(Icons.verified_user, 'Identité', 'Vérifier', '/identity', color: AppTheme.primaryBlue))]),
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

/// QR Code du transporteur affiché sur le Home à la place de l'espace SCAN passager
/// Règle : un seul véhicule autorisé — affiche directement le QR du véhicule unique
class _TransporteurQrCard extends StatefulWidget {
  const _TransporteurQrCard();

  @override
  State<_TransporteurQrCard> createState() => _TransporteurQrCardState();
}

class _TransporteurQrCardState extends State<_TransporteurQrCard> {
  final _api = ApiService();
  String? _token;
  String? _immat;
  int? _vehicleId;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkRefresh());
  }

  Future<void> _checkRefresh() async {
    if (_vehicleId == null || _token == null) return;
    try {
      final data = await _api.get('/vehicles/$_vehicleId/qr');
      final qr = data['qr'] as Map<String, dynamic>?;
      final newToken = qr?['token'] as String?;
      if (newToken != null && newToken != _token && mounted) {
        setState(() => _token = newToken);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QR régénéré après scan !'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/vehicles');
      final vehicles = data['vehicles'] as List<dynamic>? ?? [];
      if (vehicles.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = 'Aucun véhicule'; });
        return;
      }
      // Un seul véhicule autorisé — prendre le premier
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
        _startPolling();
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
        child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
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
              Text(_error == 'Aucun véhicule' ? 'Aucun véhicule' : 'QR indisponible', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_error == 'Aucun véhicule' ? 'Ajoutez votre véhicule unique pour générer le QR' : 'Erreur: $_error', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/vehicles'), icon: const Icon(Icons.add), label: const Text('Ajouter mon véhicule')),
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
              const Text('Mon QR Code', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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
          Text('Présentez ce QR au passager pour démarrer la course', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('QR actif • régénération auto après chaque scan', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [Icon(Icons.visibility, color: Colors.orange.shade700, size: 18), const SizedBox(width: 8), const Expanded(child: Text('Mode invité — explorez librement. Inscrivez-vous pour interagir.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)))), const SizedBox(width: 8), FilledButton(onPressed: () => Navigator.pushNamed(context, '/register'), style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), child: const Text('S\'inscrire', style: TextStyle(fontSize: 11)))]),
          ),
          const SizedBox(height: 12),
          const Text('Bienvenue sur SafeRide AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          const Text('Consultez toutes les fonctionnalités. L\'interaction nécessite un compte.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
          const SizedBox(height: 14),
          // Aperçu carte
          Container(
            height: 140,
            decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.lightBlueBorder)),
            child: Stack(children: [const Center(child: Icon(Icons.map, size: 48, color: AppTheme.primaryBlue)), Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: const Text('Yaoundé • Carte', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))))]),
          ),
          const SizedBox(height: 14),
          // Scanner verrouillé
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.cardBlack, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))), child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28)), const SizedBox(height: 12), const Text('Scanner un QR Code', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text('Fonctionnalité verrouillée — inscrivez-vous', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)), const SizedBox(height: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock, size: 12, color: Colors.white), SizedBox(width: 4), Text('Invité', style: TextStyle(color: Colors.white, fontSize: 11))]))]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: GestureDetector(onTap: onAction, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppTheme.sosRed.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sos, color: Colors.white, size: 16), SizedBox(width: 6), Text('SOS URGENCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)), SizedBox(width: 4), Icon(Icons.lock, size: 12, color: Colors.white)])))), const SizedBox(width: 10), Expanded(child: GestureDetector(onTap: onAction, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.support_agent, size: 16, color: AppTheme.textGrey), SizedBox(width: 6), Text('ASSISTANCE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), SizedBox(width: 4), Icon(Icons.lock, size: 12, color: AppTheme.textGrey)]))))]),
          const SizedBox(height: 18),
          const Text('Aperçu des services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          _guestCard(Icons.trip_origin, 'Trajet', 'Suivi GPS + SOS', onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.gavel_outlined, 'Litige', 'Objets perdus & SOS', onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.verified_user, 'Identité', 'CNI / Passeport', onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.directions_car, 'Véhicules', 'QR transporteur', onAction),
          const SizedBox(height: 8),
          _guestCard(Icons.dashboard, 'Tableau de bord', 'Stats transporteur', onAction),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/register'), icon: const Icon(Icons.person_add), label: const Text('Créer mon compte — interagir')),
          const SizedBox(height: 6),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Déjà inscrit ? Se connecter')),
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
        child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: Colors.grey)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)), const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock, size: 10, color: Colors.grey), SizedBox(width: 3), Text('Invité', style: TextStyle(fontSize: 10, color: Colors.grey))]))]), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])), const Icon(Icons.chevron_right, size: 16, color: Colors.grey)]),
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 48, color: Colors.grey.shade400), const SizedBox(height: 12), Text('$label — mode invité', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), const Text('Inscrivez-vous pour accéder à cette section', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textGrey, fontSize: 12)), const SizedBox(height: 16), FilledButton.icon(onPressed: () => Navigator.pushNamed(context, '/register'), icon: const Icon(Icons.person_add), label: const Text('S\'inscrire')), TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Se connecter'))]),
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
              subtitle: const Text('Litiges, objets perdus, SOS, identités'),
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