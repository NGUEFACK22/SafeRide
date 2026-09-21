import 'package:flutter/material.dart';
import '../utils/error_helper.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import '../widgets/rating_stars.dart';

class HistoryScreen extends StatefulWidget {
  /// embedded=true : contenu seul (onglet "Trajets" de l'accueil), sans
  /// Scaffold/AppBar — même pattern que ProfileScreen(embedded:).
  final bool embedded;
  const HistoryScreen({super.key, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    final content = DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(lang.t('history_trips'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(lang.t('view_recent_trips'), style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: AppTheme.primaryBlue,
              unselectedLabelColor: AppTheme.textGrey,
              indicatorColor: AppTheme.primaryBlue,
              tabs: [
                Tab(text: lang.t('trips_ongoing')),
                Tab(text: lang.t('trips_finished')),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _HistoryList(scope: 'en_cours'),
                _HistoryList(scope: 'fini'),
              ],
            ),
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
        title: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/logo_round.png', height: 28, fit: BoxFit.contain)),
        centerTitle: true,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: CircleAvatar(radius: 16, backgroundColor: AppTheme.lightBlueBadge, child: Icon(Icons.person, size: 16, color: AppTheme.primaryBlue)))],
      ),
      body: content,
    );
  }
}

/// Une vue d'historique (scope 'en_cours' ou 'fini') avec son propre
/// chargement : les trajets en cours affichent "Reprendre" (retour direct
/// vers trip-active), les terminés gardent "Détails".
class _HistoryList extends StatefulWidget {
  final String scope;
  const _HistoryList({required this.scope});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  final _tripService = TripService();
  List<Trip> _trips = [];
  bool _loading = true;
  String? _error;

  /// Heure locale HH:mm depuis un ISO API (UTC) — substring direct affichait
  /// l'heure UTC = -1h.
  String _localHm(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

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
      final trips = await _tripService.history(scope: widget.scope);
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
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue));
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_trips.isEmpty) {
      return Center(
        child: Text(LanguageService.instance.t(
          widget.scope == 'en_cours' ? 'no_ongoing_trip' : 'no_finished_trip',
        )),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primaryBlue,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(LanguageService.instance.t('today'), _trips.take(1).toList()),
          const SizedBox(height: 16),
          _section(LanguageService.instance.t('this_week'), _trips.skip(1).toList()),
        ],
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
          final finished = trip.statut == 'TERMINE';
          final ongoing = trip.statut != 'TERMINE' && trip.statut != 'ANNULE';
          final badge = finished
              ? LanguageService.instance.t('terminated')
              : trip.statut;
          final badgeColor = finished
              ? AppTheme.successBg
              : (ongoing ? AppTheme.lightBlueBadge : Colors.grey.shade200);
          final badgeTextColor = finished
              ? AppTheme.successText
              : (ongoing ? AppTheme.primaryBlue : Colors.grey.shade600);
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
                  Text(trip.destinationAddress ?? LanguageService.instance.t('trip_no_destination'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [const Icon(Icons.person_outline, size: 14, color: AppTheme.textGrey), const SizedBox(width: 4), Text(trip.transporteurFullName.isEmpty ? '—' : trip.transporteurFullName, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)), const SizedBox(width: 8), Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppTheme.textGrey, shape: BoxShape.circle)), const SizedBox(width: 8), Text(_localHm(trip.startedAt), style: const TextStyle(fontSize: 12, color: AppTheme.textGrey))]),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Text(trip.distanceKm != null && trip.distanceKm! > 0 ? '${trip.distanceKm!.toStringAsFixed(1)} km' : '—'),
                      if (trip.durationSeconds != null) Text('${(trip.durationSeconds! / 60).round()} min', style: const TextStyle(color: AppTheme.textGrey)),
                      if (trip.ratingsAvg != null && trip.ratingsAvg! > 0) ...[const SizedBox(width: 8), RatingStars(rating: trip.ratingsAvg!, size: 12)],
                      const Spacer(),
                      if (ongoing)
                        FilledButton(
                          onPressed: () => Navigator.of(context).pushNamed('/trip-active', arguments: trip),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          child: Text(LanguageService.instance.t('resume_trip')),
                        )
                      else
                        FilledButton(
                          onPressed: () => Navigator.of(context).pushNamed('/trip-map', arguments: trip.id),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.lightBlueBadge, foregroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          child: Text(LanguageService.instance.t('details')),
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
