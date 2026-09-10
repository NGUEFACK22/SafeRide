import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _api = ApiService();
  final _auth = AuthService();

  // Étape 1 — envoi du lien
  final _emailController = TextEditingController();
  bool _linkSent = false;
  bool _sending = false;

  // Étape 2 — réinitialisation (code + nouveau mot de passe)
  final _resetEmailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _resetting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _resetEmailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack(LanguageService.instance.t('email_required'));
      return;
    }
    setState(() => _sending = true);
    try {
      final data = await _api.post('/auth/forgot-password', {'email': email}, auth: false);
      if (!mounted) return;
      if (data.containsKey('message')) {
        setState(() {
          _linkSent = true;
          _resetEmailController.text = email;
        });
        _snack(LanguageService.instance.t('reset_link_sent'));
      } else {
        _snack(LanguageService.instance.t('reset_email_not_found'));
      }
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_passwordController.text.length < 8) {
      _snack(LanguageService.instance.t('min_8_chars'));
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      _snack(LanguageService.instance.t('password_mismatch'));
      return;
    }
    setState(() => _resetting = true);
    try {
      await _api.post('/auth/reset-password', {
        'email': _resetEmailController.text.trim(),
        'token': _codeController.text.trim(),
        'password': _passwordController.text,
        'password_confirmation': _confirmController.text,
      }, auth: false);
      if (!mounted) return;
      _snack(LanguageService.instance.t('password_reset_done'));
      await _auth.logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      _snack(LanguageService.instance.t('password_reset_invalid'));
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  TextStyle get _titleStyle => const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.instance.t('reset_password'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Étape 1 : email ────────────────────────────────────────────
              Text(LanguageService.instance.t('reset_step1'), style: _titleStyle),
              const SizedBox(height: 10),
              _linkedCard(Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    readOnly: _linkSent,
                    decoration: const InputDecoration(
                      hintText: 'email@exemple.com',
                      prefixIcon: Icon(Icons.mail_outline),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_sending || _linkSent) ? null : _sendLink,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(LanguageService.instance.t('send_reset_link')),
                  ),
                ],
              ), 1, _linkSent),
              const SizedBox(height: 26),
              // ── Étape 2 : code + nouveau mot de passe ──────────────────────
              Text(LanguageService.instance.t('reset_step2'), style: _titleStyle),
              const SizedBox(height: 6),
              Text(LanguageService.instance.t('reset_link_note'), style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              const SizedBox(height: 10),
              _linkedCard(Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'email@exemple.com',
                      prefixIcon: Icon(Icons.mail_outline),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: 'code',
                      prefixIcon: Icon(Icons.token),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: LanguageService.instance.t('new_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      hintText: LanguageService.instance.t('confirm_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _resetting ? null : _resetPassword,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlueDark, padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: _resetting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(LanguageService.instance.t('reset_password')),
                  ),
                ],
              ), 2, false),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(LanguageService.instance.t('back_to_login'), style: TextStyle(color: AppTheme.textGrey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkedCard(Widget child, int step, bool done) {
    return Card(
      elevation: 0,
      color: AppTheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: done ? Colors.green.shade300 : Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (done)
              Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                Text(LanguageService.instance.t('reset_link_sent'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}