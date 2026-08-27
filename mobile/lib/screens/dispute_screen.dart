import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Litiges & Objets perdus'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Litiges'),
              Tab(text: 'Objets perdus'),
              Tab(text: 'Ouvrir'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DisputesTab(),
            _LostItemsTab(),
            _CreateTab(),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1 : Mes litiges ──────────────────────────────────────
class _DisputesTab extends StatefulWidget {
  const _DisputesTab();

  @override
  State<_DisputesTab> createState() => _DisputesTabState();
}

class _DisputesTabState extends State<_DisputesTab> {
  final _api = ApiService();
  List<dynamic> _disputes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/disputes');
      if (!mounted) return;
      setState(() {
        _disputes = (data['disputes'] as Map<String, dynamic>)['data']
                as List<dynamic>? ??
            [];
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }
    if (_disputes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gavel_outlined, size: 48, color: AppTheme.textGrey),
            SizedBox(height: 12),
            Text('Aucun litige pour le moment'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _disputes.length,
        itemBuilder: (context, index) {
          final dispute = _disputes[index];
          final (label, color) = _disputeStatus(dispute['statut'] as String?);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(Icons.gavel_outlined, color: color),
              title: Text(dispute['motif'] ?? 'Litige'),
              subtitle: Text(
                'Trajet #${dispute['trip_id']} · '
                '${_dateOnly(dispute['created_at'] as String?)}'
                '${dispute['description'] != null ? '\n${dispute['description']}' : ''}',
              ),
              trailing: Chip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                backgroundColor: color.withValues(alpha: 0.15),
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Tab 2 : Objets perdus ────────────────────────────────────
class _LostItemsTab extends StatefulWidget {
  const _LostItemsTab();

  @override
  State<_LostItemsTab> createState() => _LostItemsTabState();
}

class _LostItemsTabState extends State<_LostItemsTab> {
  final _api = ApiService();
  List<dynamic> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/lost-items');
      if (!mounted) return;
      setState(() {
        _reports = (data['reports'] as Map<String, dynamic>)['data']
                as List<dynamic>? ??
            [];
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

  Future<void> _openChronology(dynamic report) async {
    try {
      final data = await _api.get('/lost-items/${report['id']}/chronology');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => _ChronologySheet(data: data),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }
    if (_reports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline, size: 48, color: AppTheme.textGrey),
            SizedBox(height: 12),
            Text('Aucun objet perdu signalé'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          final (label, color) = _reportStatus(report['statut'] as String?);
          final hasImage = report['image_url'] != null &&
              (report['image_url'] as String).isNotEmpty;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        '${ApiConfig.baseUrl.replaceAll('/api/v1', '')}/storage/${report['image_url']}',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.work_outline, color: color),
                      ),
                    )
                  : Icon(Icons.work_outline, color: color),
              title: Text(report['objet'] ?? 'Objet'),
              subtitle: Text(
                'Trajet #${report['trip_id']} · '
                '${_dateOnly(report['created_at'] as String?)}${hasImage ? ' · image jointe' : ''}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Chip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    backgroundColor: color.withValues(alpha: 0.15),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Text(
                    'Chronologie',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ),
              onTap: () => _openChronology(report),
            ),
          );
        },
      ),
    );
  }
}

// ── Tab 3 : Ouvrir (litige OU objet perdu) ───────────────────
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
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
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
          'description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
        });
      } else {
        await _api.post('/disputes', {
          'trip_id': _selectedTripId,
          'motif': _motif.text.trim(),
          'description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
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
        SnackBar(content: Text('Erreur : $e')),
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
                    onTap: () => setState(() => _reportType = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _reportType == 0
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _reportType == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
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
                    onTap: () => setState(() => _reportType = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _reportType == 1
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _reportType == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
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
            onChanged: (v) => setState(() => _selectedTripId = v),
          ),
          const SizedBox(height: 16),
          // Champ motif / objet
          TextField(
            controller: _motif,
            decoration: InputDecoration(
              labelText: isLostItem ? 'Objet oublié' : 'Motif',
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
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('Caméra',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library, size: 16),
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
                      onPressed: () => setState(() => _image = null),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Retirer la photo'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: Icon(isLostItem ? Icons.report_problem : Icons.gavel),
            label: Text(isLostItem ? 'Signaler l\'objet perdu' : 'Ouvrir le litige'),
          ),
          const SizedBox(height: 12),
          Text(
            isLostItem
                ? 'Le signalement est automatiquement associé au trajet, au transporteur et au véhicule. La chronologie identifie les passagers suivants.'
                : 'Le litige sera examiné par un gestionnaire. Vous serez notifié de l\'avancement.',
            style: const TextStyle(
                fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textGrey),
          ),
        ],
      ),
    );
  }
}

// ── Chronologie (bottom sheet) ────────────────────────────────
class _ChronologySheet extends StatelessWidget {
  const _ChronologySheet({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final related = data['related_trips'] as List<dynamic>? ?? [];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chronologie du véhicule #${data['vehicle_id'] ?? '—'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Passagers ayant utilisé ce véhicule entre la fin de votre '
              'trajet et le signalement.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            if (related.isEmpty)
              const Text('Aucun autre passager détecté sur cette période.')
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in related)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person),
                        title: Text(
                          t['passager_nom'] ?? 'Passager #${t['passager_id']}',
                        ),
                        subtitle: Text(
                          'Trajet #${t['trip_id']} · '
                          '${_dateOnly(t['ended_at'] as String?)}',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
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

String _dateOnly(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  return iso.split('T').first;
}
