import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
  XFile? _recto;
  XFile? _verso;
  XFile? _selfie;
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
    } catch (_) {}
  }

  Future<void> _pickRecto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null && mounted) setState(() => _recto = picked);
  }

  Future<void> _pickVerso(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null && mounted) setState(() => _verso = picked);
  }

  Future<void> _pickSelfie(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80, preferredCameraDevice: CameraDevice.front);
    if (picked != null && mounted) setState(() => _selfie = picked);
  }

  Color _statusColor(String? statut) {
    switch (statut) {
      case 'VERIFIE':
        return Colors.green;
      case 'ECHOUE':
        return Colors.red;
      default:
        return AppTheme.primaryBlue;
    }
  }

  Future<void> _submit() async {
    if (_recto == null || _verso == null || _selfie == null) {
      setState(() {
        _error = true;
        _message = 'Veuillez fournir les 3 photos : recto, verso et selfie avec pièce en main (obligatoires).';
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
        files: {
          'fichier_recto': File(_recto!.path),
          'fichier_verso': File(_verso!.path),
          'fichier_selfie': File(_selfie!.path),
        },
      );
      final verification = data['verification'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _message = data['message'] as String? ?? 'Documents soumis.';
          _resultStatut = verification?['statut'] as String?;
          _current = verification;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() {_error = true; _message = e.message;});
    } catch (e) {
      if (mounted) setState(() {_error = true; _message = 'Erreur réseau : $e';});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _pickCard({required String title, required String subtitle, required XFile? file, required VoidCallback onCamera, required VoidCallback onGallery}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: file != null ? AppTheme.primaryBlue : Colors.grey.shade300, width: file != null ? 1.4 : 1)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: file != null ? AppTheme.lightBlueBadge : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Icon(file != null ? Icons.check_circle : Icons.image, color: file != null ? AppTheme.primaryBlue : Colors.grey, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])),
              if (file != null) const Icon(Icons.verified, size: 18, color: Colors.green),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: onCamera, icon: const Icon(Icons.camera_alt, size: 16), label: const Text('Caméra', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: onGallery, icon: const Icon(Icons.photo_library, size: 16), label: const Text('Galerie', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)))),
            ],
          ),
          if (file != null) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(file.path), height: 120, width: double.infinity, fit: BoxFit.cover)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStatut = _current?['statut'] as String?;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: Colors.white, title: const Text('Vérification d\'identité', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_current != null)
              Card(
                color: _statusColor(currentStatut).withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _statusColor(currentStatut).withValues(alpha: 0.2))),
                child: ListTile(
                  leading: Icon(Icons.verified_user, color: _statusColor(currentStatut)),
                  title: const Text('Statut actuel', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(currentStatut ?? '—'),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de document', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numeroController,
              decoration: const InputDecoration(labelText: 'Numéro du document (optionnel)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('1. Recto de la carte (obligatoire)', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
            const SizedBox(height: 6),
            _pickCard(title: 'Recto', subtitle: 'Face avant claire', file: _recto, onCamera: () => _pickRecto(ImageSource.camera), onGallery: () => _pickRecto(ImageSource.gallery)),
            const SizedBox(height: 12),
            const Text('2. Verso de la carte (obligatoire)', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
            const SizedBox(height: 6),
            _pickCard(title: 'Verso', subtitle: 'Face arrière claire', file: _verso, onCamera: () => _pickVerso(ImageSource.camera), onGallery: () => _pickVerso(ImageSource.gallery)),
            const SizedBox(height: 12),
            const Text('3. Selfie avec pièce en main (obligatoire)', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
            const SizedBox(height: 4),
            const Text('Tenez votre CNI / passeport à côté de votre visage, bien visible.', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            const SizedBox(height: 6),
            _pickCard(title: 'Selfie + pièce', subtitle: 'Visage + document', file: _selfie, onCamera: () => _pickSelfie(ImageSource.camera), onGallery: () => _pickSelfie(ImageSource.gallery)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Soumettre la vérification (3 photos)', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            if (_message != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: (_error ? Colors.red : _statusColor(_resultStatut)).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: (_error ? Colors.red : _statusColor(_resultStatut)).withValues(alpha: 0.2))),
                child: Text(_message!, style: TextStyle(color: _error ? Colors.red : _statusColor(_resultStatut), fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            const Text('Vos 3 photos sont analysées (Didit recto/verso + selfie manuel par un gestionnaire).', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          ],
        ),
      ),
    );
  }
}
