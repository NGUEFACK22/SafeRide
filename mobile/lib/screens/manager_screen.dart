import 'package:flutter/material.dart';

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
        _error = e.toString();
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
        SnackBar(content: Text('Erreur : $e')),
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
        SnackBar(content: Text('Erreur : $e')),
      );
    }
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