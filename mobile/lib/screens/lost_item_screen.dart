import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class LostItemScreen extends StatefulWidget {
  const LostItemScreen({super.key});

  @override
  State<LostItemScreen> createState() => _LostItemScreenState();
}

class _LostItemScreenState extends State<LostItemScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Objet perdu'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mes signalements'),
              Tab(text: 'Signaler'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LostReportsTab(),
            _LostItemFormTab(),
          ],
        ),
      ),
    );
  }
}

class _LostReportsTab extends StatefulWidget {
  const _LostReportsTab();

  @override
  State<_LostReportsTab> createState() => _LostReportsTabState();
}

class _LostReportsTabState extends State<_LostReportsTab> {
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
        _error = friendlyError(e);
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
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_reports.isEmpty) {
      return const Center(child: Text('Aucun signalement pour le moment'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          final (label, color) = _reportStatus(report['statut'] as String?);
          final hasImage = report['image_url'] != null && (report['image_url'] as String).isNotEmpty;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: hasImage
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network('${ApiConfig.baseUrl.replaceAll('/api/v1', '')}/storage/${report['image_url']}', width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.work_outline, color: color)))
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
                    label: Text(label, style: TextStyle(fontSize: 11)),
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

class _LostItemFormTab extends StatefulWidget {
  const _LostItemFormTab();

  @override
  State<_LostItemFormTab> createState() => _LostItemFormTabState();
}

class _LostItemFormTabState extends State<_LostItemFormTab> {
  final _api = ApiService();
  final _objet = TextEditingController();
  final _description = TextEditingController();
  int? _selectedTripId;
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _submitting = false;
  final List<XFile> _images = [];
  final _picker = ImagePicker();
  static const int _maxImages = 2;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  @override
  void dispose() {
    _objet.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    try {
      final data = await _api.get('/trips/history');
      if (!mounted) return;
      setState(() {
        _trips = (data['trips'] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
        _loadingTrips = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrips = false);
    }
  }

  Future<bool> _ensurePermission(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.status;
        if (status.isGranted) return true;
        if (status.isPermanentlyDenied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caméra bloquée — activez dans Paramètres > Applications > SafeRide > Autorisations')));
          await openAppSettings();
          return false;
        }
        final req = await Permission.camera.request();
        if (!req.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(req.isPermanentlyDenied ? 'Caméra refusée définitivement' : 'Permission caméra refusée'), action: req.isPermanentlyDenied ? SnackBarAction(label: 'Ouvrir', onPressed: () => openAppSettings()) : null));
        }
        return req.isGranted;
      } else {
        final photos = await Permission.photos.status;
        final storage = await Permission.storage.status;
        if (photos.isGranted || storage.isGranted) return true;
        if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Galerie bloquée — activez dans Paramètres')));
          await openAppSettings();
          return false;
        }
        final pReq = await Permission.photos.request();
        if (pReq.isGranted) return true;
        final sReq = await Permission.storage.request();
        if (!sReq.isGranted && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission galerie refusée')));
        return sReq.isGranted;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Maximum $_maxImages images autorisées'), backgroundColor: Colors.orange));
      return;
    }
    if (!await _ensurePermission(source)) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
      if (picked != null && mounted) {
        setState(() => _images.add(picked));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red, action: SnackBarAction(label: 'Réessayer', onPressed: () => _pickImage(source))));
    }
  }

  Future<void> _submit() async {
    if (_selectedTripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un trajet')),
      );
      return;
    }
    if (_objet.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décrivez l\'objet oublié')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_images.isNotEmpty) {
        final files = <String, File>{};
        files['image'] = File(_images[0].path);
        if (_images.length > 1) files['image2'] = File(_images[1].path);
        await _api.postMultipart(
          '/lost-items',
          {
            'trip_id': _selectedTripId.toString(),
            'objet': _objet.text.trim(),
            'description': _description.text.trim(),
          },
          files: files,
        );
      } else {
        await _api.post('/lost-items', {
          'trip_id': _selectedTripId,
          'objet': _objet.text.trim(),
          'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Objet perdu signalé. Un gestionnaire en est informé.'),
        ),
      );
      _objet.clear();
      _description.clear();
      setState(() {
        _selectedTripId = null;
        _images.clear();
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          TextField(
            controller: _objet,
            decoration: const InputDecoration(
              labelText: 'Objet oublié',
              border: OutlineInputBorder(),
              hintText: 'Ex : Portefeuille noir',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Photos de l\'objet (max 2)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: _images.isNotEmpty ? AppTheme.lightBlueBadge : Colors.grey.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: _images.isNotEmpty ? AppTheme.lightBlueBorder : Colors.grey.shade300)), child: Text('${_images.length}/$_maxImages', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _images.isNotEmpty ? AppTheme.primaryBlue : Colors.grey))),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(border: Border.all(color: _images.isNotEmpty ? AppTheme.primaryBlue : Colors.grey.shade300, width: _images.isNotEmpty ? 1.4 : 1), borderRadius: BorderRadius.circular(12), color: Colors.white),
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _images.length >= _maxImages ? null : () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt, size: 16), label: const Text('Caméra', style: TextStyle(fontSize: 12)))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: _images.length >= _maxImages ? null : () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library, size: 16), label: const Text('Galerie', style: TextStyle(fontSize: 12)))),
                  ],
                ),
                if (_images.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('Aucune photo — ajoutez jusqu\'à $_maxImages images (facultatif)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.1),
                    itemCount: _images.length,
                    itemBuilder: (ctx, i) => Stack(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_images[i].path), height: 140, width: double.infinity, fit: BoxFit.cover)),
                        Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _images.removeAt(i)), child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
                        Positioned(bottom: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)), child: Text('Photo ${i+1}', style: const TextStyle(color: Colors.white, fontSize: 10)))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(onPressed: () => setState(() => _images.clear()), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Retirer toutes les photos')),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.report_problem),
            label: const Text('Signaler l\'objet perdu'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Le signalement est automatiquement associé au trajet, au '
            'transporteur et au véhicule. La chronologie identifie les '
            'passagers suivants.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

String _tripLabel(dynamic trip) {
  final dest = trip['destination_address'] as String?;
  final ended = _dateOnly(trip['ended_at'] as String?);
  return '${dest ?? 'Trajet #${trip['id']}'}${ended.isEmpty ? '' : ' — $ended'}';
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