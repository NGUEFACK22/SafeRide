import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/error_helper.dart';
import '../theme/app_theme.dart';

import '../services/api_service.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  final _api = ApiService();
  List<dynamic> _assignments = [];
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await _api.get('/manager/dashboard');
      final assignments = await _api.get('/manager/assignments');
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _assignments = assignments['assignments']['data'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _take(int id) async {
    try {
      await _api.post('/manager/assignments/$id/take', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossier pris en charge')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _close(int id) async {
    try {
      await _api.post('/manager/assignments/$id/close', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossier clôturé')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  /// Charge le détail complet d'une alerte SOS puis ouvre le dialogue de gestion.
  Future<void> _openSosDetail(int sosId) async {
    try {
      final data = await _api.get('/sos/$sosId');
      if (!mounted) return;
      final sos = (data['sos'] as Map<String, dynamic>?) ?? {};
      await _showSosDialog(sos, sosId);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  /// Résout l'alerte SOS (RESOLU / FAUSSE_ALERTE / EN_COURS).
  Future<void> _resolveSos(int sosId, String statut) async {
    try {
      await _api.put('/sos/$sosId/resolve', {'statut': statut});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerte SOS marquée : $statut')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _showSosDialog(Map<String, dynamic> sos, int sosId) async {
    final statut = (sos['statut'] as String?) ?? 'INCONNU';
    final lat = (sos['latitude'] as num?)?.toString() ?? '—';
    final lng = (sos['longitude'] as num?)?.toString() ?? '—';
    final mapsLink = lat != '—'
        ? 'https://maps.google.com/?q=$lat,$lng'
        : null;
    final passager = (sos['passager'] as Map<String, dynamic>?) ?? {};
    final trip = (sos['trip'] as Map<String, dynamic>?) ?? {};
    final transporteur = (trip['transporteur'] as Map<String, dynamic>?) ?? {};
    final passagerNom =
        '${passager['prenom'] ?? ''} ${passager['nom'] ?? ''}'.trim();
    final transporteurNom =
        '${transporteur['prenom'] ?? ''} ${transporteur['nom'] ?? ''}'.trim();

    final resolved = statut == 'RESOLU' ||
        statut == 'CLOTE' ||
        statut == 'FAUSSE_ALERTE';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.sos, color: AppTheme.sosRed),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Alerte SOS',
                style: TextStyle(fontSize: 18)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Statut', statut),
              _infoRow('Déclenchement',
                  (sos['declenchement'] as String?) ?? '—'),
              _infoRow('Passager', passagerNom.isEmpty ? '—' : passagerNom),
              _infoRow('Transporteur',
                  transporteurNom.isEmpty ? '—' : transporteurNom),
              _infoRow('Trajet #', '${sos['trip_id'] ?? '—'}'),
              _infoRow('Heure',
                  (sos['heure_detection'] as String?) ?? '—'),
              if (mapsLink != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: () => _openMaps(mapsLink),
                    child: Text(
                      '🗺️ Voir la position GPS',
                      style: const TextStyle(
                        color: AppTheme.primaryBlue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!resolved) ...[
            TextButton(
              onPressed: () => _resolveSos(sosId, 'RESOLU'),
              child: const Text('Résoudre'),
            ),
            TextButton(
              onPressed: () => _resolveSos(sosId, 'FAUSSE_ALERTE'),
              child: const Text('Fausse alerte'),
            ),
            TextButton(
              onPressed: () => _resolveSos(sosId, 'EN_COURS'),
              child: const Text('En cours'),
            ),
          ] else
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _openMaps(String link) async {
    final uri = Uri.parse(link);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  /// Examine une demande de vérification d'identité (VERIFIE / ECHOUE / A_EXAMINER).
  Future<void> _openIdentityReview(
      int verificationId, Map<String, dynamic> dossier) async {
    if (!mounted) return;
    await _showIdentityDialog(verificationId, dossier);
    _load();
  }

  Future<void> _submitIdentityReview(int verificationId, String statut) async {
    try {
      await _api.put('/identity/$verificationId/review', {'statut': statut});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vérification d\'identité : $statut')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _showIdentityDialog(
      int verificationId, Map<String, dynamic> knownUser) async {
    final statut = (knownUser['statut'] as String?) ?? '—';
    final type = (knownUser['type'] as String?) ?? '—';
    final userId = (knownUser['user_id'] as num?)?.toInt() ?? '—';
    final alreadyReviewed = (statut == 'VERIFIE' || statut == 'ECHOUE');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.verified_user, color: Colors.purple),
          SizedBox(width: 8),
          Expanded(
            child: Text('Demande d\'identité #',
                style: TextStyle(fontSize: 18)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Utilisateur #', '$userId'),
              _infoRow('Type', type),
              _infoRow('Statut', statut),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Documents : recto, verso, selfie — vérifiez la concordance avant de valider.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!alreadyReviewed) ...[
            TextButton(
              onPressed: () => _submitIdentityReview(verificationId, 'VERIFIE'),
              child: const Text('Vérifier'),
            ),
            TextButton(
              onPressed: () => _submitIdentityReview(verificationId, 'ECHOUE'),
              child: const Text('Échouer'),
            ),
            TextButton(
              onPressed: () => _submitIdentityReview(verificationId, 'A_EXAMINER'),
              child: const Text('À examiner'),
            ),
          ] else
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'SOS':
        return 'SOS';
      case 'OBJET_PERDU':
        return 'Objet perdu';
      case 'LITIGE':
        return 'Litige';
      case 'IDENTITE':
        return 'Identité';
      default:
        return type;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'SOS':
        return Colors.red;
      case 'OBJET_PERDU':
        return Colors.orange;
      case 'LITIGE':
        return Colors.blue;
      case 'IDENTITE':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes dossiers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      if (_dashboard != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      Text(
                                        '${_dashboard!['open'] ?? 0}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(color: Colors.orange),
                                      ),
                                      const Text('Ouverts'),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        '${_dashboard!['closed'] ?? 0}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(color: Colors.green),
                                      ),
                                      const Text('Clôturés'),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        '${_dashboard!['total'] ?? 0}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium,
                                      ),
                                      const Text('Total'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_assignments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text('Aucun dossier attribué')),
                        )
                      else
                        for (final a in _assignments)
                          Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _typeColor(a['dossier_type'])
                                    .withValues(alpha: 0.15),
                                foregroundColor: _typeColor(a['dossier_type']),
                                child: Text(
                                  _typeLabel(a['dossier_type'])
                                      .substring(0, 1),
                                ),
                              ),
                              title: Text(
                                '${_typeLabel(a['dossier_type'])} #${a['dossier_id']}',
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Statut : ${a['statut']}'),
                                  if (a['dossier'] != null)
                                    Text(
                                      _dossierExtra(a),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (a['dossier_type'] == 'SOS')
                                    IconButton(
                                      icon: const Icon(Icons.visibility,
                                          color: AppTheme.sosRed),
                                      tooltip: 'Détails de l\'alerte SOS',
                                      onPressed: () =>
                                          _openSosDetail(
                                              (a['dossier_id'] as num?)?.toInt() ?? 0),
                                    ),
                                  if (a['dossier_type'] == 'IDENTITE')
                                    IconButton(
                                      icon: const Icon(Icons.verified_user,
                                          color: Colors.purple),
                                      tooltip: 'Examiner la demande d\'identité',
                                      onPressed: () => _openIdentityReview(
                                        (a['dossier_id'] as num?)?.toInt() ?? 0,
                                        (a['dossier'] as Map<String, dynamic>?) ?? {},
                                      ),
                                    ),
                                  if (a['statut'] == 'ATTRIBUE') ...[
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow,
                                          color: Colors.green),
                                      tooltip: 'Prendre en charge',
                                      onPressed: () => _take(a['id']),
                                    ),
                                  ],
                                  if (a['statut'] != 'CLOTURE')
                                    IconButton(
                                      icon: const Icon(Icons.check_circle,
                                          color: Colors.blue),
                                      tooltip: 'Clôturer',
                                      onPressed: () => _close(a['id']),
                                    ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }

  String _dossierExtra(Map<String, dynamic> assignment) {
    final dossier = assignment['dossier'];
    if (dossier is! Map<String, dynamic>) return '';

    if (assignment['dossier_type'] == 'SOS') {
      return 'SOS en position ${dossier['latitude'] ?? '—'}, ${dossier['longitude'] ?? '—'}';
    }
    if (assignment['dossier_type'] == 'OBJET_PERDU') {
      return 'Objet : ${dossier['objet'] ?? '—'}';
    }
    if (assignment['dossier_type'] == 'LITIGE') {
      return 'Motif : ${dossier['motif'] ?? '—'}';
    }
    if (assignment['dossier_type'] == 'IDENTITE') {
      return 'Identité de l\'utilisateur #${dossier['user_id'] ?? '—'}';
    }
    return '';
  }
}