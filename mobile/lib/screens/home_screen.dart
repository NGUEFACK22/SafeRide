import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshUnread());
    _refreshUnread();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeRide AI'),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: _openNotifications,
              ),
              if (_unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(_user.fullName),
              accountEmail: Text(_user.email),
              currentAccountPicture: CircleAvatar(
                child: Text(_user.prenom.isNotEmpty ? _user.prenom[0].toUpperCase() : '?'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Accueil'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historique des trajets'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/history');
              },
            ),
            ListTile(
              leading: const Icon(Icons.assistant, color: Colors.green),
              title: const Text('Assistant IA'),
              subtitle: const Text('Résumé et statistiques personnalisés'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/ai');
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_user, color: Colors.blue),
              title: const Text('Vérification d\'identité'),
              subtitle: const Text('Soumettre CNI / passeport (KYC)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/identity');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Déconnexion'),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
      body: _user.hasRole('transporteur')
          ? const _TransporteurView()
          : _user.hasRole('gestionnaire')
              ? const _GestionnaireView()
              : const _PassagerView(),
    );
  }
}

class _PassagerView extends StatelessWidget {
  const _PassagerView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_scanner, size: 32),
              title: const Text('Scanner le QR du transporteur'),
              subtitle: const Text('Démarre le trajet et lance la surveillance'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/scan'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trip_origin, size: 32),
              title: const Text('Mon trajet en cours'),
              subtitle: const Text('Suivi GPS et protection vocale'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/trip-active'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sos, size: 32, color: Colors.red),
              title: const Text('Bouton SOS'),
              subtitle: const Text('Déclenche une alerte d\'urgence'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/sos-button'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.work_outline, size: 32),
              title: const Text('Objet perdu'),
              subtitle: const Text('Signaler un objet oublié — lié à votre trajet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/lost-item'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.gavel_outlined, size: 32),
              title: const Text('Ouvrir un litige'),
              subtitle: const Text('Signaler un problème sur un trajet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/dispute'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user, size: 32, color: Colors.blue),
              title: const Text('Vérification d\'identité'),
              subtitle: const Text('Soumettre CNI / passeport (KYC Didit)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/identity'),
            ),
          ),
        ],
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car, size: 32),
              title: const Text('Mes véhicules'),
              subtitle: const Text('Gérer véhicules et QR codes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/vehicles'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trip_origin, size: 32),
              title: const Text('Trajets en cours'),
              subtitle: const Text('Passagers embarqués dans vos véhicules'),
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
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights, size: 32),
              title: const Text('Mes statistiques'),
              subtitle: const Text('Dossiers traités et taux de résolution'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/manager-stats'),
            ),
          ),
        ],
      ),
    );
  }
}