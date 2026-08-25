import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
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

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  Widget _buildBody() {
    // Bottom nav index mapping
    if (_selectedIndex == 1) return const _HistoryPreview();
    if (_selectedIndex == 2) return const _ScanPreview();
    if (_selectedIndex == 3) return _AlertsPreview(unread: _unread, onOpen: _openNotifications);
    if (_selectedIndex == 4) return _ProfilePreview(user: _user, onLogout: _logout);

    // Home (0) -> role view
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
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.sosRed,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pushNamed(context, '/sos-button'),
              icon: const Icon(Icons.sos),
              label: const Text('SOS URGENCE', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          if (i == 2) {
            if (_user.hasRole('transporteur')) {
              Navigator.pushNamed(context, '/vehicles');
            } else {
              Navigator.pushNamed(context, '/scan');
            }
            return;
          }
          setState(() => _selectedIndex = i);
        },
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: const Color(0xFF9AA0AE),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Trips'),
          BottomNavigationBarItem(
            icon: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle),
              child: Icon(_user.hasRole('transporteur') ? Icons.qr_code : Icons.qr_code_scanner, color: Colors.white, size: 22),
            ),
            label: _user.hasRole('transporteur') ? 'QR' : 'Scan',
          ),
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

class _ScanPreview extends StatelessWidget {
  const _ScanPreview();
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.qr_code_scanner, size: 56, color: AppTheme.primaryBlue), const SizedBox(height: 12), const Text('Scanner', style: TextStyle(fontWeight: FontWeight.w700)), FilledButton(onPressed: () => Navigator.pushNamed(context, '/scan'), child: const Text('Ouvrir le scanner'))])));
}

class _AlertsPreview extends StatelessWidget {
  final int unread;
  final VoidCallback onOpen;
  const _AlertsPreview({required this.unread, required this.onOpen});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.notifications_outlined, size: 48, color: AppTheme.primaryBlue), Text('$unread non lues'), FilledButton(onPressed: onOpen, child: const Text('Voir les alertes'))]));
}

class _ProfilePreview extends StatelessWidget {
  final dynamic user;
  final VoidCallback onLogout;
  const _ProfilePreview({required this.user, required this.onLogout});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(child: ListTile(leading: const Icon(Icons.person), title: Text(user.fullName), subtitle: Text(user.email))),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pushNamed(context, '/profile', arguments: user), child: const Text('Voir le profil complet (maquette)')),
            const SizedBox(height: 12),
            ListTile(leading: const Icon(Icons.verified_user, color: AppTheme.primaryBlue), title: const Text('Vérification d\'identité'), onTap: () => Navigator.pushNamed(context, '/identity')),
            ListTile(leading: const Icon(Icons.contact_emergency, color: AppTheme.sosRed), title: const Text('Contacts d\'urgence'), onTap: () => Navigator.pushNamed(context, '/emergency-contacts')),
            ListTile(leading: const Icon(Icons.logout, color: AppTheme.sosRed), title: const Text('Déconnexion'), onTap: onLogout),
          ],
        ),
      );
}

class _PassagerView extends StatelessWidget {
  final dynamic user;
  const _PassagerView({this.user});

  @override
  Widget build(BuildContext context) {
    final name = (user?.prenom as String?) ?? 'Jean';
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
          const SizedBox(height: 16),
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
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/sos-button'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(color: AppTheme.sosRed, borderRadius: BorderRadius.circular(14)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('✳', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      SizedBox(width: 8),
                      Text('SOS URGENCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/ai'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.lightBlueBorder)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.support_agent, size: 20, color: AppTheme.textDark),
                      SizedBox(width: 6),
                      Text('SUPPORT', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Course Récente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/history'), child: const Text('VOIR L\'HISTORIQUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
            ],
          ),
          const SizedBox(height: 8),
          // Card course récente (mockup Paris map)
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
                        // Fausse carte (placeholder)
                        Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: NetworkImage('https://tile.openstreetmap.org/3/2/1.png'),
                              fit: BoxFit.cover,
                              onError: (_, __) {},
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.timelapse, size: 12, color: AppTheme.successText),
                              SizedBox(width: 4),
                              Text('TERMINÉ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successText)),
                            ]),
                          ),
                        ),
                        const Center(child: Text('Paris', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.directions_car, color: AppTheme.primaryBlue)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Peugeot 508', style: TextStyle(fontWeight: FontWeight.w800)),
                          Row(children: [Icon(Icons.person_outline, size: 14, color: AppTheme.textGrey), SizedBox(width: 4), Text('Marc D. • Plaque vérif...', style: TextStyle(fontSize: 11, color: AppTheme.textGrey))]),
                        ]),
                      ),
                      const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('14:30', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('4.2 km', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Accès rapides secondaires (blanc/bleu)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickChip(Icons.trip_origin, 'Trajet en cours', () => Navigator.pushNamed(context, '/trip-active')),
              _quickChip(Icons.work_outline, 'Objet perdu', () => Navigator.pushNamed(context, '/lost-item')),
              _quickChip(Icons.gavel_outlined, 'Litige', () => Navigator.pushNamed(context, '/dispute')),
              _quickChip(Icons.verified_user, 'Identité', () => Navigator.pushNamed(context, '/identity')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.primaryBlue),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey.shade200),
      onPressed: onTap,
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