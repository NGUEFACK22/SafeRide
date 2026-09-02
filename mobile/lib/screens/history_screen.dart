import 'package:flutter/material.dart';
import '../utils/error_helper.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../theme/app_theme.dart';
import '../widgets/rating_stars.dart';

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
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.shield, color: AppTheme.textDark), onPressed: () => Navigator.pop(context)),
        title: const Text('SafeRide AI', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: CircleAvatar(radius: 16, backgroundColor: AppTheme.lightBlueBadge, child: Icon(Icons.person, size: 16, color: AppTheme.primaryBlue)))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _error != null
              ? Center(child: Text(_error!))
              : _trips.isEmpty
                  ? const Center(child: Text('Aucun trajet terminé'))
                  : RefreshIndicator(
                      color: AppTheme.primaryBlue,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text('Historique des trajets', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                          const Text('Consultez vos trajets récents', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                          const SizedBox(height: 16),
                          _section('Aujourd\'hui', _trips.take(1).toList()),
                          const SizedBox(height: 16),
                          _section('Cette semaine', _trips.skip(1).toList()),
                        ],
                      ),
                    ),
    );
  }

  Widget _section(String title, List<Trip> trips) {
    if (trips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle)), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark))]),
        const SizedBox(height: 8),
        ...trips.map((trip) {
          final isMoto = (trip.destinationAddress ?? '').toLowerCase().contains('moto');
          final badge = trip.statut == 'TERMINE' ? 'TERMINÉ' : trip.statut;
          final badgeColor = trip.statut == 'TERMINE' ? AppTheme.successBg : Colors.grey.shade200;
          final badgeTextColor = trip.statut == 'TERMINE' ? AppTheme.successText : Colors.grey.shade600;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)), child: Icon(isMoto ? Icons.two_wheeler : Icons.directions_car, color: AppTheme.primaryBlue)),
                      const Spacer(),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)), child: Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badgeTextColor))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(trip.destinationAddress ?? 'Trajet sans destination', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [const Icon(Icons.person_outline, size: 14, color: AppTheme.textGrey), const SizedBox(width: 4), Text(trip.transporteurFullName.isEmpty ? 'Jean Dupont' : trip.transporteurFullName, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)), const SizedBox(width: 8), Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppTheme.textGrey, shape: BoxShape.circle)), const SizedBox(width: 8), Text(trip.startedAt?.substring(11, 16) ?? '14:30', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey))]),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Text('${trip.distanceKm?.toStringAsFixed(1) ?? '5.2'} km', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 12),
                      Text('${(trip.durationSeconds ?? 720) ~/ 60} min', style: const TextStyle(color: AppTheme.textGrey)),
                      if (trip.ratingsAvg != null && trip.ratingsAvg! > 0) ...[const SizedBox(width: 8), RatingStars(rating: trip.ratingsAvg!, size: 12)],
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushNamed('/trip-map', arguments: trip.id),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.lightBlueBadge, foregroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        child: const Text('Détails'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}