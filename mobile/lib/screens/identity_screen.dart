import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final _api = ApiService();
  final _numeroController = TextEditingController();
  final _picker = ImagePicker();

  String _type = 'CNI';
  XFile? _image;
  bool _loading = false;
  Map<String, dynamic>? _current;
  String? _message;
  String? _resultStatut;
  bool _error = false;

  static const _types = ['CNI', 'PASSEPORT', 'AUTRE'];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await _api.get('/identity/status');
      if (mounted) {
        setState(() => _current = data['verification'] as Map<String, dynamic>?);
      }
    } catch (_) {
      // ignore — le statut est optionnel
    }
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _image = picked);
    }
  }

  Color _statusColor(String? statut) {
    switch (statut) {
      case 'VERIFIE':
        return Colors.green;
      case 'ECHOUE':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _submit() async {
    if (_image == null) {
      setState(() {
        _error = true;
        _message = 'Veuillez ajouter une photo du document.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _error = false;
      _resultStatut = null;
    });

    try {
      final data = await _api.postMultipart(
        '/identity/submit',
        {
          'type': _type,
          'numero': _numeroController.text.trim(),
        },
        file: File(_image!.path),
      );
      final verification = data['verification'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _message = data['message'] as String? ?? 'Document soumis.';
          _resultStatut = verification?['statut'] as String?;
          _current = verification;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = 'Erreur réseau : $e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStatut = _current?['statut'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Vérification d\'identité')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_current != null)
              Card(
                color: _statusColor(currentStatut).withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(Icons.verified_user, color: _statusColor(currentStatut)),
                  title: const Text('Statut actuel'),
                  subtitle: Text(currentStatut ?? '—'),
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type de document',
                border: OutlineInputBorder(),
              ),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _numeroController,
              decoration: const InputDecoration(
                labelText: 'Numéro du document (optionnel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Photo du document (CNI / passeport)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Appareil photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galerie'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_image!.path), height: 200, fit: BoxFit.cover),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Soumettre la vérification'),
            ),
            const SizedBox(height: 16),
            if (_message != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_error ? Colors.red : _statusColor(_resultStatut))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _error ? Colors.red : _statusColor(_resultStatut),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Votre document est analysé automatiquement (Didit KYC). '
              'En cas d\'anomalie, un gestionnaire examine manuellement le dossier.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
