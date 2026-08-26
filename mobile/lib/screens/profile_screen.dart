import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final User? user;
  const ProfileScreen({super.key, this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _verifStatut;
  bool _verifLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVerif();
  }

  Future<void> _loadVerif() async {
    try {
      final data = await ApiService().get('/identity/status');
      final v = data['verification'] as Map<String, dynamic>?;
      if (mounted) setState(() {_verifStatut = v?['statut'] as String?; _verifLoading = false;});
    } catch (_) {
      if (mounted) setState(() => _verifLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user != null ? '${widget.user!.prenom} ${widget.user!.nom}' : 'Alexandre Dubois';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppTheme.textDark), onPressed: () => Navigator.pop(context)),
        title: const Text('SafeRide AI', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: CircleAvatar(radius: 16, backgroundImage: NetworkImage('https://i.pravatar.cc/100?img=12')))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                const CircleAvatar(radius: 44, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=15')),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.verified, size: 12, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
            const SizedBox(height: 6),
            _verifLoading
                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _verifStatut == 'VERIFIE' ? AppTheme.successBg : _verifStatut == 'ECHOUE' ? Colors.red.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _verifStatut == 'VERIFIE' ? AppTheme.successBorder : _verifStatut == 'ECHOUE' ? Colors.red.shade200 : Colors.orange.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_verifStatut == 'VERIFIE' ? Icons.verified : _verifStatut == 'ECHOUE' ? Icons.error_outline : Icons.hourglass_empty, size: 12, color: _verifStatut == 'VERIFIE' ? AppTheme.successText : _verifStatut == 'ECHOUE' ? Colors.red : Colors.orange.shade800),
                      const SizedBox(width: 4),
                      Text(
                        _verifStatut == 'VERIFIE'
                            ? 'IDENTITÉ VÉRIFIÉE'
                            : _verifStatut == 'ECHOUE'
                                ? 'VÉRIFICATION ÉCHOUÉE'
                                : _verifStatut == 'A_EXAMINER'
                                    ? 'À EXAMINER'
                                    : _verifStatut == 'EN_ATTENTE'
                                        ? 'EN ATTENTE'
                                        : 'NON VÉRIFIÉE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _verifStatut == 'VERIFIE' ? AppTheme.successText : _verifStatut == 'ECHOUE' ? Colors.red : Colors.orange.shade800),
                      ),
                    ]),
                  ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _statBox('142', 'TRAJETS')),
                const SizedBox(width: 8),
                Expanded(child: _statBox('1.2k', 'KM TOTAL')),
                const SizedBox(width: 8),
                Expanded(child: _statBoxBlue('99%', 'SCORE')),
              ],
            ),
            const SizedBox(height: 16),
            _menuTile(Icons.person_outline, 'Informations personnelles', onTap: () => _showInfo(context)),
            _menuTile(Icons.settings_outlined, 'Paramètres', onTap: () => Navigator.pushNamed(context, '/profile-edit'), color: Colors.grey.shade100, iconColor: AppTheme.textDark),
            _menuTile(Icons.mic, 'Mot de sécurité', onTap: () => Navigator.pushNamed(context, '/sos-button'), color: AppTheme.lightBlueBadge, iconColor: AppTheme.primaryBlue),
            _menuTile(Icons.shield_outlined, 'Sécurité & SOS', onTap: () => Navigator.pushNamed(context, '/emergency-contacts'), color: const Color(0xFFFFE9E9), iconColor: AppTheme.sosRed),
            _menuTile(Icons.history, 'Historique des trajets', onTap: () => Navigator.pushNamed(context, '/history')),
            _menuTile(Icons.support_agent, 'Support • Assistant IA', onTap: () => Navigator.pushNamed(context, '/ai')),
            _menuTile(Icons.verified_user, 'Vérification d\'identité', onTap: () => Navigator.pushNamed(context, '/identity')),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () async { await AuthService().logout(); if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.sosRed, side: BorderSide(color: Colors.grey.shade300)), icon: const Icon(Icons.logout), label: const Text('Déconnexion')),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 4,
        onTap: (i) {
          if (i == 0) Navigator.pushReplacementNamed(context, '/home');
          if (i == 1) Navigator.pushNamed(context, '/history');
          if (i == 2) Navigator.pushNamed(context, '/scan');
        },
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: const Color(0xFF9AA0AE),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  static void _showInfo(BuildContext context) {
    final user = (ModalRoute.of(context)?.settings.arguments as dynamic);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Informations personnelles'),
        content: const Text('Nom, email, téléphone et statut sont visibles dans votre profil.\n\nPour modifier, contactez le support.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  static void _showPayment(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Moyens de paiement'),
        content: const Text('Paiement hors périmètre SafeRide (sécurisation des trajets uniquement).\n\nAucun paiement n\'est géré dans l\'app.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  static Widget _statBox(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textGrey))]),
    );
  }

  static Widget _statBoxBlue(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.lightBlueBorder)),
      child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)), const SizedBox(width: 4), const Icon(Icons.verified, size: 14, color: AppTheme.primaryBlue)]), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue))]),
    );
  }

  static Widget _menuTile(IconData icon, String title, {VoidCallback? onTap, Color? color, Color? iconColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: color ?? AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor ?? AppTheme.primaryBlue, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textGrey),
        onTap: onTap,
      ),
    );
  }
}
