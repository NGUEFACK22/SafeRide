import 'package:flutter/material.dart';

import '../services/api_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _api = ApiService();
  List<dynamic> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/emergency-contacts');
      if (!mounted) return;
      setState(() {
        _contacts = data['contacts'] as List<dynamic>? ?? [];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openForm([dynamic contact]) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ContactFormDialog(contact: contact as Map<String, dynamic>?),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved['message'] as String? ?? '')),
      );
      _load();
    }
  }

  Future<void> _delete(dynamic contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le contact'),
        content: Text(
            'Supprimer « ${contact['nom']} » des contacts d\'urgence ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.delete('/emergency-contacts/${contact['id']}');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts d\'urgence'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _contacts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucun contact d\'urgence.\nCes personnes seront notifiées '
                          'en priorité lors d\'une alerte SOS.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (contact['nom'] as String? ?? '?')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                ),
                              ),
                              title: Text(contact['nom'] ?? ''),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('📞 ${contact['telephone'] ?? ''}'),
                                  if (contact['whatsapp_telephone'] != null)
                                    Text('💬 WhatsApp: ${contact['whatsapp_telephone']}'),
                                  if (contact['relation'] != null)
                                    Text('Relation : ${contact['relation']}'),
                                  Text('✉️ ${contact['email'] ?? ''}'),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Modifier',
                                    onPressed: () => _openForm(contact),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: 'Supprimer',
                                    onPressed: () => _delete(contact),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({this.contact});

  final Map<String, dynamic>? contact;

  @override
  State<_ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<_ContactFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _telephone;
  late final TextEditingController _relation;
  late final TextEditingController _email;
  late final TextEditingController _whatsapp;
  bool _submitting = false;

  bool get _isEdit => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nom = TextEditingController(text: c?['nom'] as String? ?? '');
    _telephone = TextEditingController(text: c?['telephone'] as String? ?? '');
    _relation = TextEditingController(text: c?['relation'] as String? ?? '');
    _email = TextEditingController(text: c?['email'] as String? ?? '');
    _whatsapp = TextEditingController(text: c?['whatsapp_telephone'] as String? ?? c?['whatsapp'] as String? ?? '');
  }

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _relation.dispose();
    _email.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'nom': _nom.text.trim(),
        'telephone': _telephone.text.trim(),
        'relation': _relation.text.trim().isEmpty ? null : _relation.text.trim(),
        'email': _email.text.trim(),
        'whatsapp_telephone': _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      };
      final Map<String, dynamic> data = _isEdit
          ? await ApiService().put(
              '/emergency-contacts/${widget.contact!['id']}', body)
          : await ApiService().post('/emergency-contacts', body);
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Modifier le contact' : 'Ajouter un contact'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nom,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _telephone,
                decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    hintText: 'Ex : 690000000'),
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _relation,
                decoration: const InputDecoration(
                    labelText: 'Relation (facultatif)',
                    hintText: 'Ex : Mère, frère, conjoint'),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email *',
                    hintText: 'Obligatoire - notifié à chaque SOS'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v != null && v.contains('@') && v.contains('.'))
                        ? null
                        : 'Email invalide (obligatoire)',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _whatsapp,
                decoration: const InputDecoration(
                    labelText: 'Numéro WhatsApp *',
                    hintText: 'Ex: 690000000 (numéro qui a WhatsApp)'),
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Numéro WhatsApp requis' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}