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
        SnackBar(
          content: Text('Connexion Google impossible : $e'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notConfiguredMsg = ApiConfig.googleNotConfiguredMessage;

    return OutlinedButton.icon(
      onPressed: _loading
          ? null
          : notConfiguredMsg == null
              ? _signIn
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(notConfiguredMsg),
                      duration: const Duration(seconds: 4),
                    ),
                  ),
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
      label: Text(
        _loading ? 'Connexion en cours...' : 'Continuer avec Google',
        style: TextStyle(
          color: notConfiguredMsg != null ? Colors.grey : null,
        ),
      ),
    );
  }
}
