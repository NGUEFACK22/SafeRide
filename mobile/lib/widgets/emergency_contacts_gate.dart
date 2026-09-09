import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

/// Vérifie et garantit qu'un utilisateur possède au moins [minimum] contacts
/// d'urgence avant de pouvoir déclencher un SOS.
///
/// - Si l'utilisateur a déjà assez de contacts → retourne true immédiatement.
/// - Sinon ouvre un dialogue **non annulable** avec un formulaire permettant
///   d'enregistrer les contacts manquants (nom + téléphone + relation) ;
///   chaque contact est sauvegardé via POST /emergency-contacts dès que
///   le champ téléphone est valide. Le dialogue ne se ferme que lorsque le
///   quota est atteint (ou si l'utilisateur choisit explicitement d'annuler
///   le SOS).
/// - En cas d'erreur réseau (hors-ligne) : fail-open — un SOS d'urgence ne
///   doit jamais être bloqué par une panne de connexion (retourne true).
Future<bool> ensureEmergencyContacts(
  BuildContext context, {
  int minimum = 2,
}) async {
  int count;
  try {
    final data = await ApiService().get('/emergency-contacts');
    final raw = data['contacts'];
    if (raw is List) {
      count = raw.length;
    } else if (raw is Map && raw['data'] is List) {
      count = (raw['data'] as List).length;
    } else {
      count = 0;
    }
  } catch (_) {
    // Hors-ligne / erreur réseau : on ne bloque jamais un SOS.
    return true;
  }

  if (count >= minimum) return true;

  if (!context.mounted) return true;

  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MinContactsDialog(
      minimum: minimum,
      alreadyRegistered: count,
    ),
  );

  return completed == true;
}

class _MinContactsDialog extends StatefulWidget {
  const _MinContactsDialog({required this.minimum, this.alreadyRegistered = 0});

  final int minimum;
  final int alreadyRegistered;

  @override
  State<_MinContactsDialog> createState() => _MinContactsDialogState();
}

class _MinContactsDialogState extends State<_MinContactsDialog> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _relation = TextEditingController();
  bool _submitting = false;
  int _saved = 0;
  String? _error;

  int get _total => widget.alreadyRegistered + _saved;
  int get _remaining => widget.minimum - _total;
  bool get _quotaReached => _remaining <= 0;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _email.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    final nom = _nom.text.trim();
    final tel = _telephone.text.trim();
    final email = _email.text.trim();

    if (nom.isEmpty) {
      setState(() => _error = 'Le nom est requis');
      return;
    }
    if (tel.length < 6) {
      setState(() => _error = 'Numéro de téléphone invalide');
      return;
    }
    if (email.isEmpty || !(email.contains('@') && email.contains('.'))) {
      setState(() => _error = 'Un email valide est requis');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService().post('/emergency-contacts', {
        'nom': nom,
        'telephone': tel,
        'email': email,
        if (_relation.text.trim().isNotEmpty) 'relation': _relation.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _saved++;
        _submitting = false;
        _nom.clear();
        _telephone.clear();
        _email.clear();
        _relation.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.contacts, color: AppTheme.sosRed),
          const SizedBox(width: 8),
          const Expanded(child: Text('Contacts d\'urgence requis')),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _quotaReached
                    ? 'Parfait ! Vos ${widget.minimum} contacts d\'urgence sont enregistrés.\n'
                        'Ils seront notifiés par SMS, WhatsApp et email en cas d\'alerte.'
                    : 'Pour déclencher un SOS, au moins ${widget.minimum} contacts d\'urgence '
                        'doivent être enregistrés (ils reçoivent l\'alerte par SMS/WhatsApp/email).\n\n'
                        'Encore ${_remaining > 0 ? _remaining : 0} contact(s) à ajouter.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (!_quotaReached) ...[
                TextField(
                  controller: _nom,
                  decoration: const InputDecoration(
                    labelText: 'Nom du contact',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _telephone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    hintText: 'Ex : +237690000000',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Ex : nom@email.com',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _relation,
                  decoration: const InputDecoration(
                    labelText: 'Relation (facultatif)',
                    hintText: 'Ex : Mère, frère…',
                    prefixIcon: Icon(Icons.family_restroom),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
                if (_saved > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$_saved contact(s) ajouté(s) ✓',
                    style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          if (!_quotaReached)
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context, false),
              child: const Text('Annuler le SOS'),
            ),
          if (!_quotaReached)
            FilledButton.icon(
              onPressed: _submitting ? null : _saveContact,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.sosRed),
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt),
              label: const Text('Ajouter'),
            ),
          if (_quotaReached)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.sosRed),
              icon: const Icon(Icons.sos),
              label: const Text('Déclencher le SOS'),
            ),
        ],
      ),
    );
  }
}
