import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  late User _user;
  int _unread = 0;
  Timer? _timer;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshUnread());
    _refreshUnread();
    PushService.instance.addRefreshListener(_refreshUnread);
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

  Widget _buildBody() {
    if (_selectedIndex == 1) return const _HistoryPreview();
    if (_selectedIndex == 2) return _AlertsPreview(unread: _unread, onOpen: _openNotifications);
    if (_selectedIndex == 3) return ProfileScreen(user: _user, embedded: true);

    // Home (0) -> role view — Scan est dans le dashboard, plus en bas
    if (_user.hasRole('admin')) return const _AdminView();
    if (_user.hasRole('transporteur')) return const _TransporteurView();
    if (_user.hasRole('gestionnaire')) return const _GestionnaireView();
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.lightBlueBadge,
              child: Text(_user.prenom.isNotEmpty ? _user.prenom[0].toUpperCase() : '?', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: const Color(0xFF9AA0AE),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Trips'),
          BottomNavigationBarItem(
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.notifications_outlined),
              if (_unread > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.sosRed, shape: BoxShape.circle)),
                ),
            ]),
            label: 'Alerts',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
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

class _AlertsPreview extends StatelessWidget {
  final int unread;
  final VoidCallback onOpen;
  const _AlertsPreview({required this.unread, required this.onOpen});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.notifications_outlined, size: 48, color: AppTheme.primaryBlue), const SizedBox(height: 8), Text('$unread non lues', style: const TextStyle(fontSize: 14)), FilledButton(onPressed: onOpen, child: const Text('Voir les alertes'))]));
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
                        FittedBox(child: Text('SUPPORT', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13))),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Dernier trajet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/history'), child: const Text('VOIR L\'HISTORIQUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.directions_car, color: AppTheme.primaryBlue)),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Aucun trajet récent', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                    SizedBox(height: 2),
                    Text('Scannez un QR code pour démarrer', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                  ])),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Section ordonnée : Mes services en grille 2x2 (layout manuel)
          const Text('Mes services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          _serviceCard(Icons.trip_origin, 'Trajet en cours', 'Suivi GPS', () => Navigator.pushNamed(context, '/trip-active')),
          const SizedBox(height: 10),
          _serviceCard(Icons.work_outline, 'Objet perdu', 'Signaler', () => Navigator.pushNamed(context, '/lost-item')),
          const SizedBox(height: 10),
          _serviceCard(Icons.gavel_outlined, 'Litige', 'Signaler', () => Navigator.pushNamed(context, '/dispute')),
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

class _TransporteurView extends StatelessWidget {
  const _TransporteurView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carte comme passager — pour transporteur aussi
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Container(
                    height: 110,
                    color: const Color(0xFFEAF0FF),
                    child: Stack(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            image: DecorationImage(image: NetworkImage('https://tile.openstreetmap.org/3/2/1.png'), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: const Text('EN SERVICE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                          ),
                        ),
                        const Center(child: Text('Yaoundé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark))),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.local_taxi, color: AppTheme.primaryBlue)),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Véhicule en service', style: TextStyle(fontWeight: FontWeight.w800)), Text('Prêt à recevoir une course', style: TextStyle(fontSize: 11, color: AppTheme.textGrey))])),
                      const Icon(Icons.my_location, color: AppTheme.primaryBlue, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mic, size: 28, color: AppTheme.sosRed),
              title: const Text('Mot de sécurité', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Configurer votre mot vocal (3 prises)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/profile-edit'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(Icons.hearing, size: 28, color: AppTheme.primaryBlue),
              title: const Text('Course en cours — écoute auto', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Protection vocale active pour vous et le passager'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/trip-active'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dashboard, size: 32, color: Colors.green),
              title: const Text('Tableau de bord'),
              subtitle: const Text('Trajets, notes, distance, passagers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/transporteur-dashboard'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car, size: 32),
              title: const Text('Mes véhicules'),
              subtitle: const Text('Gérer véhicules et QR codes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/vehicles'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history, size: 28),
              title: const Text('Historique'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/history'),
            ),
          ),
        ],
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