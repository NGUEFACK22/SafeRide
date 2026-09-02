import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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

  static const _types = ['CNI', 'PASSEPORT'];

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

  Future<bool> _ensurePermission(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        // Android 13+ : READ_MEDIA_IMAGES via photos, sinon storage
        final photos = await Permission.photos.status;
        final storage = await Permission.storage.status;
        if (photos.isGranted || storage.isGranted) return true;
        if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission galerie refusée définitivement — ouvrez les paramètres de l\'app')));
            await openAppSettings();
          }
          return false;
        }
        final photosReq = await Permission.photos.request();
        if (photosReq.isGranted) return true;
        final storageReq = await Permission.storage.request();
        final granted = storageReq.isGranted;
        if (!granted && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission galerie refusée — activez-la dans les paramètres')));
        return granted;
      } else {
        final status = await Permission.camera.status;
        if (status.isGranted) return true;
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission caméra refusée définitivement — ouvrez les paramètres')));
            await openAppSettings();
          }
          return false;
        }
        final req = await Permission.camera.request();
        if (req.isGranted) return true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(req.isPermanentlyDenied ? 'Caméra bloquée — activez dans Paramètres > Applications > SafeRide > Autorisations' : 'Permission caméra refusée'),
              action: req.isPermanentlyDenied ? SnackBarAction(label: 'Ouvrir', onPressed: () => openAppSettings()) : null,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return false;
    }
  }

  Future<void> _pickRecto(ImageSource source) async {
    if (!await _ensurePermission(source)) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
      if (picked != null && mounted) setState(() => _recto = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red, action: SnackBarAction(label: 'Galerie', onPressed: () => _pickRecto(ImageSource.gallery))));
    }
  }

  Future<void> _pickVerso(ImageSource source) async {
    if (!await _ensurePermission(source)) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
      if (picked != null && mounted) setState(() => _verso = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red, action: SnackBarAction(label: 'Galerie', onPressed: () => _pickVerso(ImageSource.gallery))));
    }
  }

  Future<void> _pickSelfie(ImageSource source) async {
    if (!await _ensurePermission(source)) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 60, preferredCameraDevice: CameraDevice.front, maxWidth: 1280);
      if (picked != null && mounted) setState(() => _selfie = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Caméra selfie indisponible: $e — essayez la galerie ou redémarrez l\'app'), backgroundColor: Colors.red));
    }
  }

  String _labelForType(String t) {
    switch (t) {
      case 'CNI':
        return 'CNI';
      case 'PASSEPORT':
        return 'Passeport';
      default:
        return t;
    }
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
      if (mounted) setState(() {_error = true; _message = friendlyError(e);});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _pickCard({required String title, required String subtitle, required XFile? file, required VoidCallback onCamera, required VoidCallback onGallery, bool galleryAllowed = true}) {
    final isDone = file != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDone ? AppTheme.primaryBlue : Colors.grey.shade200, width: isDone ? 1.4 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDone ? AppTheme.lightBlueBadge : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDone ? AppTheme.lightBlueBorder : Colors.grey.shade200),
                ),
                child: Icon(isDone ? Icons.check_circle : Icons.image_outlined, color: isDone ? AppTheme.primaryBlue : const Color(0xFF9CA3AF), size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark)), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])),
              if (isDone) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: AppTheme.successBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.successBorder)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check, size: 12, color: AppTheme.successText), SizedBox(width: 3), Text('Prêt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successText))])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(galleryAllowed ? 'Caméra' : 'Caméra', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.textDark, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              if (galleryAllowed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Galerie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textDark, side: BorderSide(color: Colors.grey.shade300), padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), backgroundColor: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          if (!galleryAllowed)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.lightBlueBorder)),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 13, color: AppTheme.primaryBlue),
                  SizedBox(width: 6),
                  Expanded(child: Text('Selfie en direct uniquement — galerie désactivée pour sécurité', style: TextStyle(fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          if (isDone) ...[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(file.path), height: 130, width: double.infinity, fit: BoxFit.cover)),
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
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(_labelForType(t)))).toList(),
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
            _pickCard(title: 'Selfie + pièce', subtitle: 'Visage + document (direct)', file: _selfie, onCamera: () => _pickSelfie(ImageSource.camera), onGallery: () {}, galleryAllowed: false),
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
