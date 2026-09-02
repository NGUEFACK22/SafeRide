import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Type de dossier dans l'onglet unifié.
enum _DossierType { dispute, lostItem, sos }

/// Objet unifié affiché dans la liste "Mes litiges".
class _UnifiedDossier {
  final _DossierType type;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;
  final DateTime? date;
  final dynamic raw;

  _UnifiedDossier({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
    this.date,
    required this.raw,
  });
}

// ── Écran principal ───────────────────────────────────────────
class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Litiges'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mes litiges'),
              Tab(text: 'Ouvrir'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UnifiedLitigesTab(),
            _CreateTab(),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1 : Mes litiges (unifié) ─────────────────────────────
class _UnifiedLitigesTab extends StatefulWidget {
  const _UnifiedLitigesTab();

  @override
  State<_UnifiedLitigesTab> createState() => _UnifiedLitigesTabState();
}

class _UnifiedLitigesTabState extends State<_UnifiedLitigesTab> {
  final _api = ApiService();
  List<_UnifiedDossier> _dossiers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Chargement parallèle des 3 sources
      final results = await Future.wait([
        _api.get('/disputes'),
        _api.get('/lost-items'),
        _api.get('/sos/my'),
      ]);

      final disputesData = results[0];
      final lostItemsData = results[1];
      final sosData = results[2];

      final dossiers = <_UnifiedDossier>[];

      // 1) Litiges
      final disputes =
          (disputesData['disputes'] as Map<String, dynamic>)['data']
                  as List<dynamic>? ??
              [];
      for (final d in disputes) {
        final (label, color) = _disputeStatus(d['statut'] as String?);
        dossiers.add(_UnifiedDossier(
          type: _DossierType.dispute,
          title: d['motif'] ?? 'Litige',
          subtitle: 'Trajet #${d['trip_id']}',
          statusLabel: label,
          statusColor: color,
          icon: Icons.gavel_outlined,
          date: _parseDate(d['created_at'] as String?),
          raw: d,
        ));
      }

      // 2) Objets perdus
      final lostItems =
          (lostItemsData['reports'] as Map<String, dynamic>)['data']
                  as List<dynamic>? ??
              [];
      for (final l in lostItems) {
        final (label, color) = _reportStatus(l['statut'] as String?);
        final hasImage = l['image_url'] != null &&
            (l['image_url'] as String).isNotEmpty;
        dossiers.add(_UnifiedDossier(
          type: _DossierType.lostItem,
          title: l['objet'] ?? 'Objet perdu',
          subtitle:
              'Trajet #${l['trip_id']}${hasImage ? ' · image jointe' : ''}',
          statusLabel: label,
          statusColor: color,
          icon: Icons.work_outline,
          date: _parseDate(l['created_at'] as String?),
          raw: l,
        ));
      }

      // 3) Alertes SOS
      final sosAlerts =
          (sosData['alerts'] as Map<String, dynamic>?)?['data']
                  as List<dynamic>? ??
              [];
      for (final s in sosAlerts) {
        final (label, color) = _sosStatus(s['statut'] as String?);
        final declenchement = s['declenchement'] ?? 'BOUTON';
        dossiers.add(_UnifiedDossier(
          type: _DossierType.sos,
          title: 'Alerte SOS ($declenchement)',
          subtitle: 'Trajet #${s['trip_id']}',
          statusLabel: label,
          statusColor: color,
          icon: Icons.sos,
          date: _parseDate(s['created_at'] as String?),
          raw: s,
        ));
      }

      // Tri par date décroissante
      dossiers.sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      });

      if (!mounted) return;
      setState(() {
        _dossiers = dossiers;
        _error = null;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.sosRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    if (_dossiers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 56, color: AppTheme.textGrey),
            SizedBox(height: 16),
            Text('Aucun litige pour le moment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Signalez un litige ou un objet perdu depuis l\'onglet "Ouvrir"',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _dossiers.length,
        itemBuilder: (context, index) {
          final d = _dossiers[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: d.statusColor.withValues(alpha: 0.12),
                child: Icon(d.icon, color: d.statusColor, size: 20),
              ),
              title: Text(d.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(d.subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              trailing: Chip(
                label: Text(d.statusLabel,
                    style: const TextStyle(fontSize: 10)),
                backgroundColor: d.statusColor.withValues(alpha: 0.15),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              onTap: () => _showDetails(d),
            ),
          );
        },
      ),
    );
  }

  void _showDetails(_UnifiedDossier dossier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DossierDetailSheet(dossier: dossier),
    );
  }
}

// ── Bottom sheet détail ───────────────────────────────────────
class _DossierDetailSheet extends StatelessWidget {
  const _DossierDetailSheet({required this.dossier});
  final _UnifiedDossier dossier;

  @override
  Widget build(BuildContext context) {
    final raw = dossier.raw;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CircleAvatar(
              backgroundColor: dossier.statusColor.withValues(alpha: 0.12),
              child: Icon(dossier.icon, color: dossier.statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dossier.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(dossier.subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textGrey)),
                ],
              ),
            ),
            Chip(
              label: Text(dossier.statusLabel,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
              backgroundColor:
                  dossier.statusColor.withValues(alpha: 0.15),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        // Détails selon le type
        if (dossier.type == _DossierType.dispute) ...[
          _detailRow('Trajet', '#${raw['trip_id']}'),
          if (raw['description'] != null &&
              (raw['description'] as String).isNotEmpty)
            _detailRow('Description', raw['description']),
          _detailRow(
              'Date', _dateStr(raw['created_at'] as String?)),
        ] else if (dossier.type == _DossierType.lostItem) ...[
          _detailRow('Trajet', '#${raw['trip_id']}'),
          if (raw['description'] != null &&
              (raw['description'] as String).isNotEmpty)
            _detailRow('Description', raw['description']),
          if (raw['image_url'] != null &&
              (raw['image_url'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  '${ApiConfig.baseUrl.replaceAll('/api/v1', '')}/storage/${raw['image_url']}',
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
          _detailRow(
              'Date', _dateStr(raw['created_at'] as String?)),
        ] else if (dossier.type == _DossierType.sos) ...[
          _detailRow('Trajet', '#${raw['trip_id']}'),
          _detailRow('Déclenchement',
              raw['declenchement'] ?? 'BOUTON'),
          if (raw['latitude'] != null && raw['longitude'] != null)
            _detailRow('Position',
                '${raw['latitude']}, ${raw['longitude']}'),
          _detailRow(
              'Date', _dateStr(raw['created_at'] as String?)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ),
      ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGrey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _dateStr(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    return iso.split('T').first;
  }
}

// ── Tab 2 : Ouvrir (litige OU objet perdu) ───────────────────
class _CreateTab extends StatefulWidget {
  const _CreateTab();

  @override
  State<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends State<_CreateTab> {
  final _api = ApiService();
  final _motif = TextEditingController();
  final _description = TextEditingController();
  int? _selectedTripId;
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _submitting = false;
  int _reportType = 0; // 0 = litige, 1 = objet perdu
  XFile? _image;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  @override
  void dispose() {
    _motif.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    try {
      final data = await _api.get('/trips/history');
      if (!mounted) return;
      setState(() {
        _trips = (data['trips'] as Map<String, dynamic>)['data']
                as List<dynamic>? ??
            [];
        _loadingTrips = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrips = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked =
        await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) setState(() => _image = picked);
  }

  Future<void> _submit() async {
    if (_selectedTripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un trajet')),
      );
      return;
    }
    if (_motif.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_reportType == 0
              ? 'Indiquez le motif du litige'
              : 'Décrivez l\'objet oublié'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_reportType == 1 && _image != null) {
        await _api.postMultipart(
          '/lost-items',
          {
            'trip_id': _selectedTripId.toString(),
            'objet': _motif.text.trim(),
            'description': _description.text.trim(),
          },
          files: {'image': File(_image!.path)},
        );
      } else if (_reportType == 1) {
        await _api.post('/lost-items', {
          'trip_id': _selectedTripId,
          'objet': _motif.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        });
      } else {
        await _api.post('/disputes', {
          'trip_id': _selectedTripId,
          'motif': _motif.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_reportType == 0
              ? 'Litige ouvert. Un gestionnaire est attribué.'
              : 'Objet perdu signalé. Un gestionnaire en est informé.'),
        ),
      );
      _motif.clear();
      _description.clear();
      setState(() {
        _selectedTripId = null;
        _image = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLostItem = _reportType == 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sélecteur de type
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _reportType = 0),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _reportType == 0
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _reportType == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.06),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel_outlined,
                              size: 18,
                              color: _reportType == 0
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textGrey),
                          const SizedBox(width: 6),
                          Text(
                            'Litige',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _reportType == 0
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _reportType = 1),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _reportType == 1
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _reportType == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.06),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.work_outline,
                              size: 18,
                              color: _reportType == 1
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textGrey),
                          const SizedBox(width: 6),
                          Text(
                            'Objet perdu',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _reportType == 1
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Champ trajet
          DropdownButtonFormField<int?>(
            initialValue: _selectedTripId,
            decoration: const InputDecoration(
              labelText: 'Trajet concerné',
              border: OutlineInputBorder(),
            ),
            items: _loadingTrips
                ? [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Chargement…'),
                    ),
                  ]
                : [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Choisir un trajet terminé'),
                    ),
                    for (final trip in _trips)
                      DropdownMenuItem<int?>(
                        value: trip['id'] as int,
                        child: Text(_tripLabel(trip)),
                      ),
                  ],
            onChanged: (v) =>
                setState(() => _selectedTripId = v),
          ),
          const SizedBox(height: 16),
          // Champ motif / objet
          TextField(
            controller: _motif,
            decoration: InputDecoration(
              labelText:
                  isLostItem ? 'Objet oublié' : 'Motif',
              border: const OutlineInputBorder(),
              hintText: isLostItem
                  ? 'Ex : Portefeuille noir, clés, téléphone…'
                  : 'Ex : Détour d\'itinéraire, comportement du chauffeur',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          // Photo (uniquement pour objet perdu)
          if (isLostItem) ...[
            const SizedBox(height: 16),
            const Text('Photo de l\'objet (facultatif)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _image != null
                      ? AppTheme.primaryBlue
                      : Colors.grey.shade300,
                  width: _image != null ? 1.4 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt,
                              size: 16),
                          label: const Text('Caméra',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _pickImage(ImageSource.gallery),
                          icon: const Icon(
                              Icons.photo_library,
                              size: 16),
                          label: const Text('Galerie',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  if (_image != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_image!.path),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _image = null),
                      icon: const Icon(Icons.delete_outline,
                          size: 16),
                      label:
                          const Text('Retirer la photo'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon:
                Icon(isLostItem ? Icons.report_problem : Icons.gavel),
            label: Text(isLostItem
                ? 'Signaler l\'objet perdu'
                : 'Ouvrir le litige'),
          ),
          const SizedBox(height: 12),
          Text(
            isLostItem
                ? 'Le signalement est automatiquement associé au trajet, au transporteur et au véhicule.'
                : 'Le litige sera examiné par un gestionnaire. Vous serez notifié de l\'avancement.',
            style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.textGrey),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────
String _tripLabel(dynamic trip) {
  final dest = trip['destination_address'] as String?;
  final ended = _dateOnly(trip['ended_at'] as String?);
  final label = dest ?? 'Trajet #${trip['id']}';
  return ended.isEmpty ? label : '$label — $ended';
}

DateTime? _parseDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso);
}

(String, Color) _disputeStatus(String? statut) {
  switch (statut) {
    case 'OUVERT':
      return ('Ouvert', Colors.orange);
    case 'EN_COURS':
      return ('En cours', Colors.blue);
    case 'CLOTURE':
      return ('Clôturé', Colors.grey);
    default:
      return (statut ?? '', Colors.grey);
  }
}

(String, Color) _reportStatus(String? statut) {
  switch (statut) {
    case 'SIGNALE':
      return ('Signalé', Colors.orange);
    case 'EN_RECHERCHE':
      return ('En recherche', Colors.blue);
    case 'RETROUVE':
      return ('Retrouvé', Colors.green);
    case 'RESTITUE':
      return ('Restitué', Colors.teal);
    case 'NON_RETROUVE':
      return ('Non retrouvé', Colors.red);
    case 'CLOTURE':
      return ('Clôturé', Colors.grey);
    default:
      return (statut ?? '', Colors.grey);
  }
}

(String, Color) _sosStatus(String? statut) {
  switch (statut) {
    case 'DECLENCHE':
      return ('Déclenché', Colors.red);
    case 'NOTIFIE':
      return ('Notifié', Colors.orange);
    case 'EN_COURS':
      return ('En cours', Colors.blue);
    case 'RESOLU':
      return ('Résolu', Colors.green);
    case 'FAUSSE_ALERTE':
      return ('Fausse alerte', Colors.grey);
    case 'VERIFICATION':
      return ('Vérification', Colors.amber);
    default:
      return (statut ?? '', Colors.grey);
  }
}

String _dateOnly(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  return iso.split('T').first;
}
