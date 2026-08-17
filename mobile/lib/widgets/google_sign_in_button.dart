import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';

class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.onSuccess});

  final ValueChanged<User> onSuccess;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  final _auth = AuthService();
  final _google = GoogleAuthService();
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final idToken = await _google.getIdToken();
      if (idToken == null || idToken.isEmpty) return; // annulé par l'utilisateur

      final User user = await _auth.loginWithGoogle(idToken);
      if (!mounted) return;
      widget.onSuccess(user);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connexion Google impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ApiConfig.googleClientId.isEmpty &&
        ApiConfig.googleAndroidClientId.isEmpty) {
      return const SizedBox.shrink();
    }

    return OutlinedButton.icon(
      onPressed: _loading ? null : _signIn,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
      icon: _loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.g_mobiledata, size: 26),
      label: const Text('Continuer avec Google'),
    );
  }
}