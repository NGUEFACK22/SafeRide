import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import '../services/voiceprint_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final User? user;
  /// Si true, le profil est affiché comme body du HomeScreen (pas de Scaffold).
  final bool embedded;
  const ProfileScreen({super.key, this.user, this.embedded = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  String? _verifStatut;
  bool _verifLoading = true;
  int _tripsCount = 0;
  double _totalKm = 0;
  double _avgRating = 0;
  bool _statsLoading = true;

  // Champs éditables inline
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _motSecuriteController = TextEditingController();
  bool _fieldsLoading = true;
  bool _saving = false;

  bool _animateEntry = false;

  // Voix — empreinte vocale 3 prises
  final _voiceprint = VoiceprintService();
  bool _voiceEnrolled = false;
  bool _voiceActive = false;
  bool _voiceLoading = true;
  bool _voiceEnrolling = false;
  String _voiceProgress = '';
  bool _voiceAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadVerif();
    _loadStats();
    _loadFields();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateEntry = true);
    });
  }

  Future<void> _loadVerif() async {
    try {
      final data = await _api.get('/identity/status');
      final v = data['verification'] as Map<String, dynamic>?;
      if (mounted) setState(() {_verifStatut = v?['statut'] as String?; _verifLoading = false;});
    } catch (_) {
      if (mounted) setState(() => _verifLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final historyData = await _api.get('/trips/history');
      final tripsList = (historyData['trips'] as Map<String, dynamic>?)?['data'] as List<dynamic>? ?? [];
      double totalKm = 0;
      double totalRating = 0;
      int ratingCount = 0;
      for (final t in tripsList) {
        totalKm += (t['distance_km'] as num?)?.toDouble() ?? 0;
        if (t['ratings_avg'] != null && (t['ratings_avg'] as num) > 0) {
          totalRating += (t['ratings_avg'] as num).toDouble();
          ratingCount++;
        }
      }
      if (mounted) {
        setState(() {
          _tripsCount = tripsList.length;
          _totalKm = totalKm;
          _avgRating = ratingCount > 0 ? totalRating / ratingCount : 0;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadFields() async {
    try {
      final profile = await _api.get('/auth/profile');
      final user = profile['user'] as Map<String, dynamic>;
      final voice = await _api.get('/voice/profile').catchError((_) => <String, dynamic>{});
      final vp = voice['profile'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _emailController.text = user['email'] ?? '';
        _telephoneController.text = user['telephone'] ?? '';
        _motSecuriteController.text = vp?['mot_securite'] ?? '';
        _voiceEnrolled = vp?['enrolled'] == true;
        _voiceActive = vp?['actif'] == true;
        _fieldsLoading = false;
        _voiceLoading = false;
      });
      _voiceprint.ensureLoaded().then((ok) { if (mounted) setState(() => _voiceAvailable = ok); });
    } catch (_) {
      if (mounted) setState(() { _fieldsLoading = false; _voiceLoading = false; });
    }
  }

  Future<void> _enrollVoice() async {
    final mot = _motSecuriteController.text.trim();
    if (mot.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Définissez d\'abord un mot de sécurité (≥3 caractères) ci-dessus et enregistrez.')));
      return;
    }
    if (!await PermissionService.microphone(context)) return;
    // S'assurer que le mot est enregistré côté backend
    try {
      await _api.post('/voice/security-word', {'mot_securite': mot});
    } catch (_) {}
    setState(() { _voiceEnrolling = true; _voiceProgress = 'Initialisation…'; });
    try {
      final available = await _voiceprint.ensureLoaded();
      if (!available) {
        // Fallback token si modèle absent
        final token = DateTime.now().millisecondsSinceEpoch.toString();
        await _api.post('/voice/enroll', {'empreinte': token.padLeft(64, '0').substring(0, 64)});
        if (!mounted) return;
        setState(() { _voiceEnrolled = true; _voiceActive = true; _voiceEnrolling = false; _voiceProgress = ''; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voix enregistrée (mode léger)'), backgroundColor: AppTheme.primaryBlue));
        return;
      }
      setState(() => _voiceAvailable = true);
      // Enregistrement 30 secondes — l'utilisateur prononce son mot de sécurité plusieurs fois
      setState(() => _voiceProgress = 'Préparation micro — prononcez "$mot" dès que le compteur démarre…');
      final okStart = await _voiceprint.startCapture();
      if (!okStart) throw Exception('Micro indisponible — vérifiez la permission');
      // Compte à rebours 30s avec guidage vocal à l'écran
      for (int s = 30; s > 0; s--) {
        if (!mounted || !_voiceEnrolling) break;
        setState(() => _voiceProgress = 'Parlez : prononcez "$mot" — $s s restantes • répétez clairement, voix normale');
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted || !_voiceEnrolling) {
        setState(() { _voiceEnrolling = false; _voiceProgress = ''; });
        return;
      }
      final avg = await _voiceprint.stopAndEmbed();
      if (avg == null) throw Exception('Audio trop court ou modèle indisponible — parlez plus fort/près du micro');
      await _api.post('/voice/enroll', {'empreinte': avg});
      try { final p = await SharedPreferences.getInstance(); await p.setString('voice_last_embedding', avg.join(',')); } catch (_) {}
      if (!mounted) return;
      setState(() { _voiceEnrolled = true; _voiceActive = true; _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Empreinte vocale enregistrée (30s) ✓ — mot "$mot"'), backgroundColor: AppTheme.successText));
    } catch (e) {
      if (!mounted) return;
      setState(() { _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur voix : $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _importVoice() async {
    final mot = _motSecuriteController.text.trim();
    if (mot.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Définissez d\'abord un mot de sécurité (≥3 caractères)')));
      return;
    }
    try {
      await _api.post('/voice/security-word', {'mot_securite': mot});
    } catch (_) {}
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['wav']);
    if (files.isEmpty) return;
    final picked = files.first;
    Uint8List bytes;
    try {
      // readAsBytes gère déjà path/web; fallback File si vide
      final b = await picked.readAsBytes();
      if (b.isNotEmpty) {
        bytes = b;
      } else if (picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      } else {
        throw Exception('bytes vides');
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fichier illisible'), backgroundColor: Colors.red));
      return;
    }
    if (bytes.length < 32000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fichier trop court (<2s) — enregistrez 30s WAV mono 16kHz'), backgroundColor: Colors.red));
      return;
    }
    setState(() { _voiceEnrolling = true; _voiceProgress = 'Analyse du fichier…'; });
    try {
      final available = await _voiceprint.ensureLoaded();
      if (!available) throw Exception('Modèle vocal absent (84 Mo) — réinstallez l\'APK');
      final emb = await _voiceprint.embeddingFromWavBytes(bytes);
      if (emb == null) throw Exception('Fichier WAV invalide — utilisez WAV 16-bit PCM mono 16kHz, ≥1s');
      if (emb.length != 192) throw Exception('Embedding invalide: ${emb.length} au lieu de 192');
      await _api.post('/voice/enroll', {'empreinte': emb});
      try { final p = await SharedPreferences.getInstance(); await p.setString('voice_last_embedding', emb.join(',')); } catch (_) {}
      if (!mounted) return;
      setState(() { _voiceEnrolled = true; _voiceActive = true; _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voix importée depuis ${picked.name} ✓'), backgroundColor: AppTheme.successText));
    } catch (e) {
      if (!mounted) return;
      setState(() { _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import échoué: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _testVoice() async {
    if (!_voiceEnrolled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enrôlez d\'abord votre voix (30s)')));
      return;
    }
    if (!await PermissionService.microphone(context)) return;
    setState(() { _voiceEnrolling = true; _voiceProgress = 'Test 3s — prononcez votre mot…'; });
    try {
      final ok = await _voiceprint.startCapture();
      if (!ok) throw Exception('Micro indisponible');
      for (int s = 3; s > 0; s--) {
        if (!mounted || !_voiceEnrolling) break;
        setState(() => _voiceProgress = 'Test : prononcez mot — $s s');
        await Future.delayed(const Duration(seconds: 1));
      }
      final emb = await _voiceprint.stopAndEmbed();
      if (emb == null) throw Exception('Audio trop court');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('voice_last_embedding');
      if (stored == null) throw Exception('Aucune empreinte locale — ré-enrôlez');
      final ref = stored.split(',').map((e) => double.tryParse(e) ?? 0).toList();
      if (ref.length != emb.length) throw Exception('Taille empreinte mismatch');
      double dot = 0, na = 0, nb = 0;
      for (int i = 0; i < emb.length; i++) { dot += ref[i] * emb[i]; na += ref[i] * ref[i]; nb += emb[i] * emb[i]; }
      final cos = dot / (math.sqrt(na) * math.sqrt(nb) + 1e-9);
      final passed = cos >= 0.5;
      if (!mounted) return;
      setState(() { _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(passed ? 'Voix reconnue ✓ cos=${cos.toStringAsFixed(3)} (seuil 0,5)' : 'Voix différente ✗ cos=${cos.toStringAsFixed(3)} — bruit ou autre locuteur'),
        backgroundColor: passed ? AppTheme.successText : Colors.orange.shade700,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _voiceEnrolling = false; _voiceProgress = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test échoué: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveFields() async {
    setState(() => _saving = true);
    try {
      await _api.put('/auth/profile', {
        'email': _emailController.text.trim(),
        'telephone': _telephoneController.text.trim(),
      });
      final mot = _motSecuriteController.text.trim();
      if (mot.isNotEmpty) {
        await _api.post('/voice/security-word', {'mot_securite': mot});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètres enregistrés'), backgroundColor: AppTheme.primaryBlue),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _telephoneController.dispose();
    _motSecuriteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user != null ? '${widget.user!.prenom} ${widget.user!.nom}' : 'Alexandre Dubois';
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar + nom + badge — animation d'entrée (scale + fade) ──
          const SizedBox(height: 8),
          AnimatedScale(
            scale: _animateEntry ? 1.0 : 0.85,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _animateEntry ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.lightBlueBorder, width: 2), boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.15), blurRadius: 12)]),
                      child: CircleAvatar(radius: 44, backgroundColor: AppTheme.primaryBlue, child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))),
                    ),
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(color: _verifStatut == 'VERIFIE' ? AppTheme.successText : AppTheme.primaryBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: Icon(_verifStatut == 'VERIFIE' ? Icons.verified : Icons.person, size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSlide(
            offset: _animateEntry ? Offset.zero : const Offset(0, 0.3),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            child: AnimatedOpacity(opacity: _animateEntry ? 1 : 0, duration: const Duration(milliseconds: 400), child: Center(child: Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)))),
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            opacity: _animateEntry ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: Center(
              child: _verifLoading
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _verifStatut == 'VERIFIE' ? AppTheme.successBg : _verifStatut == 'ECHOUE' ? Colors.red.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _verifStatut == 'VERIFIE' ? AppTheme.successBorder : _verifStatut == 'ECHOUE' ? Colors.red.shade200 : Colors.orange.shade200),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_verifStatut == 'VERIFIE' ? Icons.verified : _verifStatut == 'ECHOUE' ? Icons.error_outline : Icons.hourglass_empty, size: 12, color: _verifStatut == 'VERIFIE' ? AppTheme.successText : _verifStatut == 'ECHOUE' ? Colors.red : Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text(
                          _verifStatut == 'VERIFIE' ? 'IDENTITÉ VÉRIFIÉE' : _verifStatut == 'ECHOUE' ? 'VÉRIFICATION ÉCHOUÉE' : _verifStatut == 'A_EXAMINER' ? 'À EXAMINER' : _verifStatut == 'EN_ATTENTE' ? 'EN ATTENTE' : 'NON VÉRIFIÉE',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _verifStatut == 'VERIFIE' ? AppTheme.successText : _verifStatut == 'ECHOUE' ? Colors.red : Colors.orange.shade800),
                        ),
                      ]),
                    ),
            ),
          ),

          // ── Stats — animation slide + fade ──
          const SizedBox(height: 14),
          AnimatedOpacity(
            opacity: _animateEntry ? 1 : 0,
            duration: const Duration(milliseconds: 700),
            child: AnimatedSlide(
              offset: _animateEntry ? Offset.zero : const Offset(0, 0.2),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              child: _statsLoading
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      children: [
                        Expanded(child: _statBox(_tripsCount.toString(), 'TRAJETS')),
                        const SizedBox(width: 8),
                        Expanded(child: _statBox(_totalKm.toStringAsFixed(0), 'KM TOTAL')),
                        const SizedBox(width: 8),
                        Expanded(child: _statBoxBlue(_avgRating.toStringAsFixed(1), 'NOTE')),
                      ],
                    ),
            ),
          ),

          // ── Informations personnelles (regroupe contact & sécurité — non divisé) ──
          const SizedBox(height: 20),
          const Text('Informations personnelles', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          const Text('Vos coordonnées et votre sécurité (numéro d\'urgence inclus) — tout est centralisé ici.', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          _fieldRow(Icons.person_outline, 'Nom', widget.user?.nom ?? '—', editable: false),
          const SizedBox(height: 8),
          _fieldRow(Icons.person_outline, 'Prénom', widget.user?.prenom ?? '—', editable: false),
          const SizedBox(height: 8),
          if (_fieldsLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            _editableField(Icons.mail_outline, 'Email', _emailController, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 8),
            _editableField(Icons.phone_outlined, 'Téléphone', _telephoneController, keyboardType: TextInputType.phone),
            const SizedBox(height: 8),
            _editableField(Icons.mic, 'Mot de sécurité', _motSecuriteController, hint: 'Ex: au secours — déclenche SOS vocal'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.lightBlueBorder)),
              child: Row(children: const [Icon(Icons.info_outline, size: 14, color: AppTheme.primaryBlue), SizedBox(width: 6), Expanded(child: Text('Le numéro d\'urgence à contacter est géré ci-dessous dans « Contacts d\'urgence ». Ajoutez au moins un contact (téléphone seul suffit).', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue)))]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveFields,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                label: const Text('Enregistrer les informations', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],

          // ── Empreinte vocale — 30s pour reconnaissance ──
          const SizedBox(height: 20),
          const Text('Reconnaissance vocale', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          const Text('Enregistrez votre voix pendant 30 secondes : prononcez votre mot de sécurité plusieurs fois, clairement, pour que le SOS ne se déclenche que sur votre voix.', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _voiceEnrolled ? AppTheme.successBorder : Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: _voiceEnrolled ? AppTheme.successBg : AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10), border: Border.all(color: _voiceEnrolled ? AppTheme.successBorder : AppTheme.lightBlueBorder)), child: Icon(_voiceEnrolled ? Icons.hearing : Icons.mic_outlined, color: _voiceEnrolled ? AppTheme.successText : AppTheme.primaryBlue, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_voiceEnrolled ? 'Voix enrôlée' : 'Voix non enrôlée', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _voiceEnrolled ? AppTheme.successText : AppTheme.textDark)), const SizedBox(height: 2), Text(_voiceActive ? 'Active • 30s' : _voiceEnrolled ? 'Enrôlée' : '30 secondes d\'enregistrement', style: const TextStyle(fontSize: 11, color: AppTheme.textGrey))])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _voiceEnrolled ? AppTheme.successBg : Colors.orange.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: _voiceEnrolled ? AppTheme.successBorder : Colors.orange.shade200)), child: Text(_voiceEnrolled ? 'OK' : 'À FAIRE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _voiceEnrolled ? AppTheme.successText : Colors.orange.shade800))),
                  ],
                ),
                if (_voiceEnrolling) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.lightBlueBorder)),
                    child: Column(children: [
                      Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)), const SizedBox(width: 10), Expanded(child: Text(_voiceProgress, style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)))]),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(color: AppTheme.primaryBlue, backgroundColor: Colors.white),
                      const SizedBox(height: 6),
                      const Text('Restez à 15-20cm du micro • parlez à voix normale • répétez votre mot 5-6 fois pendant les 30s', style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: () async { setState(() { _voiceEnrolling = false; _voiceProgress = ''; }); try { await _voiceprint.stopAndEmbed(); } catch (_) {} }, icon: const Icon(Icons.close, size: 16), label: const Text('Annuler l\'enregistrement')),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _voiceEnrolling ? null : _enrollVoice,
                  icon: _voiceEnrolling ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_voiceEnrolled ? Icons.refresh : Icons.record_voice_over),
                  label: Text(_voiceEnrolled ? 'Ré-enregistrer ma voix (30s)' : 'Enregistrer ma voix (30s)', style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(backgroundColor: _voiceEnrolled ? AppTheme.textDark : AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _voiceEnrolling ? null : _importVoice,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Importer un fichier WAV (analyse)', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4))),
                ),
                const SizedBox(height: 4),
                const Text('WAV 16-bit PCM mono 16kHz, ≥1s — sinon enregistrez via micro', style: TextStyle(fontSize: 10, color: AppTheme.textGrey), textAlign: TextAlign.center),
                if (_voiceEnrolled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _voiceEnrolling ? null : _testVoice,
                    icon: const Icon(Icons.verified, size: 18, color: AppTheme.successText),
                    label: const Text('Tester ma voix (3s) — vérif locale', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.successText)),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), side: const BorderSide(color: AppTheme.successBorder)),
                  ),
                ],
                const SizedBox(height: 6),
                Text(_voiceAvailable ? 'ECAPA int8 21Mo + VAD 0,3Mo disponibles' : 'Modèle vocal en chargement… (fallback léger possible)', style: const TextStyle(fontSize: 10, color: AppTheme.textGrey)),
              ],
            ),
          ),

          // ── Menu actions ──
          const SizedBox(height: 20),
          _menuTile(Icons.shield_outlined, 'Gestion Contacts Urgence', onTap: () => Navigator.pushNamed(context, '/emergency-contacts'), color: const Color(0xFFFFE9E9), iconColor: AppTheme.sosRed),
          _menuTile(Icons.history, 'Historique des trajets', onTap: () => Navigator.pushNamed(context, '/history')),
          _menuTile(Icons.support_agent, 'Support • Assistant IA', onTap: () => Navigator.pushNamed(context, '/ai')),
          _menuTile(Icons.verified_user, 'Vérification d\'identité', onTap: () => Navigator.pushNamed(context, '/identity')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async { await AuthService().logout(); if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); },
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.sosRed, side: BorderSide(color: Colors.grey.shade300)),
            icon: const Icon(Icons.logout),
            label: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppTheme.textDark), onPressed: () => Navigator.pop(context)),
        title: const Text('SafeRide AI', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: content,
    );
  }

  // ── Champ non éditable (nom, prénom) ──
  static Widget _fieldRow(IconData icon, String label, String value, {bool editable = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textGrey),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textGrey))),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 14, color: AppTheme.textGrey),
        ],
      ),
    );
  }

  // ── Champ éditable inline ──
  static Widget _editableField(IconData icon, String label, TextEditingController controller, {TextInputType? keyboardType, String? hint}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  static Widget _statBox(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textGrey))]),
    );
  }

  static Widget _statBoxBlue(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.lightBlueBorder)),
      child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)), const SizedBox(width: 4), const Icon(Icons.verified, size: 14, color: AppTheme.primaryBlue)]), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue))]),
    );
  }

  static Widget _menuTile(IconData icon, String title, {VoidCallback? onTap, Color? color, Color? iconColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: color ?? AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor ?? AppTheme.primaryBlue, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textGrey),
        onTap: onTap,
      ),
    );
  }
}
