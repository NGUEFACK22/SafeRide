import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';
import '../widgets/google_sign_in_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _emailController = TextEditingController(text: 'passager@saferide.app');
  final _passwordController = TextEditingController(text: 'password');
  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final User user = await _auth.login(
        _emailController.text.trim(),
        _passwordController.text,
        null,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home', arguments: user);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.shield, size: 32, color: AppTheme.primaryBlue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('SafeRide AI', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                  const SizedBox(height: 6),
                  const Text('Bienvenue sur SafeRide AI', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Adresse e-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                      filled: true,
                      fillColor: AppTheme.background,
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Email requis' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: AppTheme.background,
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contactez le support pour réinitialiser votre mot de passe : support@saferide.app')),
                        );
                      },
                      child: const Text('Mot de passe oublié ?', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Se connecter', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OU CONTINUER AVEC', style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontWeight: FontWeight.w600))),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GoogleSignInButton(
                    onSuccess: (User user) {
                      Navigator.of(context).pushReplacementNamed('/home', arguments: user);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Pas de compte ? ", style: TextStyle(color: AppTheme.textGrey)),
                      GestureDetector(onTap: () => Navigator.pushNamed(context, '/register'), child: const Text("S'inscrire", style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                    icon: const Icon(Icons.visibility_outlined, size: 18, color: AppTheme.textDark),
                    label: const Text('Continuer en tant qu\'invité — explorer', style: TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 6),
                  const Text('Visiteur : consultez toutes les fonctionnalités. L\'interaction nécessite une inscription.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}