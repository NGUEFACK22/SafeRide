import 'package:flutter/material.dart';

import '../services/transporteur_service.dart';
import '../widgets/rating_stars.dart';

class TransporteurDashboardScreen extends StatefulWidget {
  const TransporteurDashboardScreen({super.key});

  @override
  State<TransporteurDashboardScreen> createState() => _TransporteurDashboardScreenState();
}

class _TransporteurDashboardScreenState extends State<TransporteurDashboardScreen> {
  final _service = TransporteurService();
  Map<String, dynamic>? _data;
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
      final data = await _service.dashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord Transporteur'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 16),
                        _tripsCard(),
                        const SizedBox(height: 12),
                        _ratingsCard(),
                        const SizedBox(height: 12),
                        _recentTrips(),
                        const SizedBox(height: 12),
                        _recentRatings(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _header() {
    final v = _data!['vehicles_count'];
    final dist = _data!['distance_totale_km'];
    final pass = _data!['passagers_distinct'];
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('Véhicules', '$v', Icons.directions_car),
            _stat('Distance', '${dist}km', Icons.route),
            _stat('Passagers', '$pass', Icons.people),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 28),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _tripsCard() {
    final t = _data!['trips'] as Map<String, dynamic>;
    final ecarts = _data!['ecarts_alert'];
    final duree = _data!['duree_moy_minutes'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trajets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _chip('Total', '${t['total']}', Colors.blue),
                _chip('Terminés', '${t['termine']}', Colors.green),
                _chip('En cours', '${t['en_cours']}', Colors.orange),
                _chip('En attente', '${t['en_attente']}', Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            Text('Durée moyenne: $duree min · Écarts d\'itinéraire: $ecarts',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Column(
      children: [
        CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _ratingsCard() {
    final r = _data!['ratings'] as Map<String, dynamic>;
    final avg = (r['average'] as num).toDouble();
    final count = r['count'] as int;
    final dist = r['distribution'] as Map<String, dynamic>;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes reçues', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                RatingStars(rating: avg, count: count, size: 22),
                const Spacer(),
                Text('$count avis', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            ...[5, 4, 3, 2, 1].map((s) {
              final c = (dist['$s'] as num?)?.toInt() ?? 0;
              final pct = count > 0 ? c / count : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text('$s★', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade200),
                    ),
                    const SizedBox(width: 8),
                    Text('$c', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _recentTrips() {
    final list = _data!['recent_trips'] as List<dynamic>? ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Derniers trajets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...list.map((t) => ListTile(
                  dense: true,
                  leading: Icon(t['statut'] == 'TERMINE' ? Icons.check_circle : Icons.timelapse, color: t['statut'] == 'TERMINE' ? Colors.green : Colors.orange),
                  title: Text(t['destination_address'] ?? 'Trajet #${t['id']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t['distance_km'] ?? '—'} km · ${t['statut']}'),
                  trailing: Text('#${t['id']}'),
                )),
          ],
        ),
      ),
    );
  }

  Widget _recentRatings() {
    final list = (_data!['ratings']['recent'] as List<dynamic>? ?? []);
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Derniers avis', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...list.map((r) => ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text('${r['rating']}')),
                  title: Row(children: List.generate(5, (i) => Icon(i < (r['rating'] as int) ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
                  subtitle: Text(r['comment'] ?? '', maxLines: 2),
                  trailing: Text('${r['rater']?['prenom'] ?? ''}'),
                )),
          ],
        ),
      ),
    );
  }
}
