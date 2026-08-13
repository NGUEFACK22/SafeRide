import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _tripService = TripService();
  List<Trip> _trips = [];
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
      final trips = await _tripService.history();
      if (!mounted) return;
      setState(() {
        _trips = trips;
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
      appBar: AppBar(title: const Text('Historique des trajets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _trips.isEmpty
                  ? const Center(child: Text('Aucun trajet terminé'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _trips.length,
                        itemBuilder: (context, index) {
                          final trip = _trips[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: const Icon(Icons.route),
                              title: Text(
                                trip.destinationAddress ?? 'Trajet sans destination',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${trip.startedAt?.substring(0, 16).replaceAll('T', ' ') ?? ''} · '
                                '${trip.distanceKm?.toStringAsFixed(1) ?? '—'} km · '
                                'fin ${trip.endMethod == 'AUTO_10MIN' ? 'auto' : 'manuelle'}',
                              ),
                              trailing: Text(
                                '${(trip.durationSeconds ?? 0) ~/ 60} min',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}