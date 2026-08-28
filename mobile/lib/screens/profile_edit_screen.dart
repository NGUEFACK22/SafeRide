import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _email = TextEditingController();
  final _telephone = TextEditingController();
  final _motSecurite = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _api.get('/auth/profile');
      final user = profile['user'] as Map<String, dynamic>;
      final voice = await _api.get('/voice/profile').catchError((_) => <String, dynamic>{});
      final vp = voice['profile'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _nom.text = user['nom'] ?? '';
        _prenom.text = user['prenom'] ?? '';
        _email.text = user['email'] ?? '';
        _telephone.text = user['telephone'] ?? '';
        _motSecurite.text = vp?['mot_securite'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // 1. Profil (email, telephone) — nom/prenom non modifiables
      await _api.put('/auth/profile', {
        'email': _email.text.trim(),
        'telephone': _telephone.text.trim(),
      });
      // 2. Mot de sécurité (si renseigné)
      final mot = _motSecurite.text.trim();
      if (mot.isNotEmpty) {
        await _api.post('/voice/security-word', {'mot_securite': mot});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paramètres enregistrés'), backgroundColor: AppTheme.primaryBlue));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _telephone.dispose();
    _motSecurite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: Colors.white, title: const Text('Paramètres', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)), centerTitle: true, iconTheme: const IconThemeData(color: AppTheme.textDark)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Informations personnelles', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    const Text('Contact, numéro d\'urgence et sécurité regroupés — pas de division.', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                    const SizedBox(height: 12),
                    TextFormField(controller: _nom, readOnly: true, decoration: InputDecoration(labelText: 'Nom', prefixIcon: const Icon(Icons.person_outline), filled: true, fillColor: Colors.grey.shade100, suffixIcon: const Icon(Icons.lock_outline, size: 18, color: AppTheme.textGrey))),
                    const SizedBox(height: 10),
                    TextFormField(controller: _prenom, readOnly: true, decoration: InputDecoration(labelText: 'Prénom', prefixIcon: const Icon(Icons.person_outline), filled: true, fillColor: Colors.grey.shade100, suffixIcon: const Icon(Icons.lock_outline, size: 18, color: AppTheme.textGrey))),
                    const SizedBox(height: 10),
                    TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline), filled: true, fillColor: Colors.white), validator: (v) => v != null && v.contains('@') ? null : 'Email invalide'),
                    const SizedBox(height: 10),
                    TextFormField(controller: _telephone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined), filled: true, fillColor: Colors.white), validator: (v) => v == null || v.isEmpty ? 'Requis' : null),
                    const SizedBox(height: 10),
                    TextFormField(controller: _motSecurite, decoration: const InputDecoration(labelText: 'Mot de sécurité (SOS vocal)', hintText: 'Ex: au secours — déclenche alerte', prefixIcon: Icon(Icons.mic), filled: true, fillColor: Colors.white), validator: (v) => null),
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.lightBlueBorder)), child: Row(children: const [Icon(Icons.info_outline, size: 14, color: AppTheme.primaryBlue), SizedBox(width: 6), Expanded(child: Text('Vos contacts d\'urgence (numéro à appeler) se gèrent aussi depuis Profil > Contacts d\'urgence — téléphone seul suffit.', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue)))])),
                    const SizedBox(height: 4),
                    const Text('Vérifiez aussi vos 3 prises vocales et l\'empreinte via Profil > Identité / Voix.', style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
