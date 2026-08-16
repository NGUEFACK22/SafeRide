import 'package:flutter/material.dart';

import '../services/api_service.dart';

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
            _DisputesTab(),
            _DisputeFormTab(),
          ],
        ),
      ),
    );
  }
}

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
      return Center(child: Text(_error!));
    }
    if (_disputes.isEmpty) {
      return const Center(child: Text('Aucun litige pour le moment'));
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

class _DisputeFormTab extends StatefulWidget {
  const _DisputeFormTab();

  @override
  State<_DisputeFormTab> createState() => _DisputeFormTabState();
}

class _DisputeFormTabState extends State<_DisputeFormTab> {
  final _api = ApiService();
  final _motif = TextEditingController();
  final _description = TextEditingController();
  int? _selectedTripId;
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _submitting = false;

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
        _trips = (data['trips'] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
        _loadingTrips = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrips = false);
    }
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
        const SnackBar(content: Text('Indiquez le motif')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _api.post('/disputes', {
        'trip_id': _selectedTripId,
        'motif': _motif.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Litige ouvert. Un gestionnaire est attribué.')),
      );
      _motif.clear();
      _description.clear();
      setState(() => _selectedTripId = null);
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
            controller: _motif,
            decoration: const InputDecoration(
              labelText: 'Motif',
              border: OutlineInputBorder(),
              hintText: 'Ex : Détour d\'itinéraire, comportement du chauffeur',
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.gavel),
            label: const Text('Ouvrir le litige'),
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

String _dateOnly(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  return iso.split('T').first;
}