import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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
        SnackBar(content: Text('Erreur : $e')),
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
        title: const Text('Créer un compte', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
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
                Align(alignment: Alignment.centerRight, child: const Text('Étape 1/3', style: TextStyle(fontSize: 11, color: AppTheme.textGrey))),
                const SizedBox(height: 16),
                const Text('Créer un compte', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                const Text('Rejoignez SafeRide AI pour des trajets sécurisés.', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nomController,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    hintText: 'Jean Dupont',
                    prefixIcon: Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prenomController,
                  decoration: const InputDecoration(
                    labelText: 'Prénom',
                    hintText: 'Jean',
                    prefixIcon: Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Prénom requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    hintText: 'jean.dupont@exemple.com',
                    prefixIcon: Icon(Icons.mail_outline),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Email requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telephoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    hintText: '690000000',
                    prefixIcon: Icon(Icons.phone_outlined),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    hintText: '••••••••',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: Icon(Icons.visibility_off_outlined),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 caractères' : null,
                ),
                const SizedBox(height: 16),
                // Sélecteur de rôle — design maquette compact (corrigé overflow)
                const Text('Vous êtes :', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _roleCard('passager', Icons.person, 'Passager', 'Je cherche')),
                    const SizedBox(width: 10),
                    Expanded(child: _roleCard('transporteur', Icons.local_taxi, 'Transporteur', 'Je propose')),
                  ],
                ),
                // Indicateur force très léger maquette
                Align(alignment: Alignment.centerRight, child: const Text('Force : Faible', style: TextStyle(fontSize: 11, color: AppTheme.textGrey))),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge)), const SizedBox(width: 4), Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge)), const SizedBox(width: 4), Expanded(child: Container(height: 3, color: AppTheme.lightBlueBadge))]),
                const SizedBox(height: 12),
                Row(children: [Checkbox(value: false, onChanged: (_) {}, activeColor: AppTheme.primaryBlue), const Expanded(child: Text.rich(TextSpan(text: "J'accepte les ", style: TextStyle(fontSize: 12), children: [TextSpan(text: "Conditions d'utilisation", style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)), TextSpan(text: " et la "), TextSpan(text: "Politique de confidentialité.", style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))])))]),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Créer mon compte", style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 18)]),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OU S\'INSCRIRE AVEC', style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontWeight: FontWeight.w600))),
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