import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  final User? user;
  const ProfileScreen({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    final displayName = user != null ? '${user!.prenom} ${user!.nom}' : 'Alexandre Dubois';
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.successBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.successBorder)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified, size: 12, color: AppTheme.successText), SizedBox(width: 4), Text('IDENTITÉ VÉRIFIÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.successText))]),
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
            _menuTile(Icons.person_outline, 'Informations personnelles', onTap: () {}),
            _menuTile(Icons.shield_outlined, 'Sécurité & SOS', onTap: () => Navigator.pushNamed(context, '/emergency-contacts'), color: const Color(0xFFFFE9E9), iconColor: AppTheme.sosRed),
            _menuTile(Icons.credit_card, 'Moyens de paiement', onTap: () {}),
            _menuTile(Icons.history, 'Historique des trajets', onTap: () => Navigator.pushNamed(context, '/history')),
            _menuTile(Icons.support_agent, 'Support', onTap: () => Navigator.pushNamed(context, '/ai')),
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
