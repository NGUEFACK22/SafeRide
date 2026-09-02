import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import '../utils/error_helper.dart';
import '../widgets/google_sign_in_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String _selectedRole = 'passager';
  bool _acceptTerms = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.instance.t('accept_terms_required'))),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final User user = await _auth.register(
        nom: _nomController.text.trim(),
        prenom: _prenomController.text.trim(),
        email: _emailController.text.trim(),
        telephone: _telephoneController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(LanguageService.instance.t('create_account'), style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: 0.33,
                  backgroundColor: AppTheme.lightBlueBadge,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primaryBlue),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                ),
                Align(alignment: Alignment.centerRight, child: Text(LanguageService.instance.t('step_1_of_3'), style: TextStyle(fontSize: 11, color: AppTheme.textGrey))),
                const SizedBox(height: 16),
                Text(LanguageService.instance.t('create_account'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                Text(LanguageService.instance.t('welcome_sub'), style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nomController,
                  decoration: InputDecoration(
                    labelText: LanguageService.instance.t('name'),
                    hintText: 'Jean Dupont',
                    prefixIcon: Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? LanguageService.instance.t('name_required') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prenomController,
                  decoration: InputDecoration(
                    labelText: LanguageService.instance.t('first_name'),
                    hintText: 'Jean',
                    prefixIcon: Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? LanguageService.instance.t('first_name_required') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: LanguageService.instance.t('email'),
                    hintText: LanguageService.instance.t('email_hint'),
                    prefixIcon: Icon(Icons.mail_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? LanguageService.instance.t('email_required') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telephoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: LanguageService.instance.t('phone'),
                    hintText: '690000000',
                    prefixIcon: Icon(Icons.phone_outlined),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? LanguageService.instance.t('phone_required') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: LanguageService.instance.t('password'),
                    hintText: '••••••••',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: Icon(Icons.visibility_off_outlined),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.length < 8) ? LanguageService.instance.t('min_8_chars') : null,
                ),
                const SizedBox(height: 16),
                // Sélecteur de rôle — design maquette compact (corrigé overflow)
                Text(LanguageService.instance.t('you_are'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _roleCard('passager', Icons.person, LanguageService.instance.t('passenger'), LanguageService.instance.t('searching'))),
                    const SizedBox(width: 10),
                    Expanded(child: _roleCard('transporteur', Icons.local_taxi, LanguageService.instance.t('driver'), LanguageService.instance.t('offering'))),
                  ],
                ),
                // Indicateur force très léger maquette
                Align(alignment: Alignment.centerRight, child: Text(LanguageService.instance.t('strength_weak'), style: TextStyle(fontSize: 11, color: AppTheme.textGrey))),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge)), const SizedBox(width: 4), Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge)), const SizedBox(width: 4), Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge))]),
                const SizedBox(height: 12),
                Row(children: [Checkbox(value: _acceptTerms, onChanged: (v) => setState(() => _acceptTerms = v ?? false), activeColor: AppTheme.primaryBlue), Expanded(child: Text(LanguageService.instance.t('accept_terms'), style: TextStyle(fontSize: 12)))]),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(LanguageService.instance.t('create_account_btn'), style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 18)]),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text(LanguageService.instance.t('or_register_with'), style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontWeight: FontWeight.w600))),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 16),
                GoogleSignInButton(
                  onSuccess: (User user) {
                    Navigator.of(context).pushReplacementNamed('/home', arguments: user);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleCard(String value, IconData icon, String title, String subtitle) {
    final selected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.lightBlueBadge : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primaryBlue : Colors.grey.shade300, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: selected ? AppTheme.primaryBlue : Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: selected ? Colors.white : AppTheme.textGrey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppTheme.primaryBlue : AppTheme.textDark)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle, size: 18, color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }
}