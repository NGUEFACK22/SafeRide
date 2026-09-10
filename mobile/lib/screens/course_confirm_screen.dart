import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../theme/app_theme.dart';
import '../widgets/rating_stars.dart';

class CourseConfirmScreen extends StatefulWidget {
  final Trip trip;
  final Map<String, dynamic> transporteur;
  final Map<String, dynamic> vehicle;

  const CourseConfirmScreen({
    super.key,
    required this.trip,
    required this.transporteur,
    required this.vehicle,
  });

  @override
  State<CourseConfirmScreen> createState() => _CourseConfirmScreenState();
}

class _CourseConfirmScreenState extends State<CourseConfirmScreen> {
  final _tripService = TripService();
  bool _loading = false;
  bool _waiting = false;
  bool _cancelling = false;
  Timer? _statusPoll;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      final trip = await _tripService.confirmEmbarquement(widget.trip.id);
      if (!mounted) return;
      if (trip.statut == 'EN_ATTENTE_TRANSPORTEUR') {
        // Le transporteur doit accepter : on attend sa décision en pollant.
        setState(() {
          _waiting = true;
          _loading = false;
        });
        _startPolling(widget.trip.id);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course acceptée — protection vocale active des deux côtés'), backgroundColor: AppTheme.primaryBlue),
      );
      Navigator.of(context).pushReplacementNamed('/trip-active', arguments: trip);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() => _loading = false);
    }
  }

  /// Annulation passager : termine la demande (SCANNE/EN_ATTENTE → ANNULE)
  /// pour pouvoir scanner un autre véhicule immédiatement.
  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _statusPoll?.cancel();
    try {
      await _tripService.cancelByPassenger(widget.trip.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande annulée. Vous pouvez scanner un autre véhicule.')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  void _startPolling(int tripId) {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 3), (_) => _pollStatus(tripId));
    _pollStatus(tripId);
  }

  Future<void> _pollStatus(int tripId) async {
    Trip trip;
    try {
      trip = await _tripService.tripStatus(tripId);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    switch (trip.statut) {
      case 'CONFIRME':
        _statusPoll?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⭐ Transporteur a accepté la course'), backgroundColor: AppTheme.primaryBlue),
        );
        Navigator.of(context).pushReplacementNamed('/trip-active', arguments: trip);
      case 'ANNULE':
        _statusPoll?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le transporteur a refusé la course. Vous pouvez scanner un autre véhicule.'), backgroundColor: AppTheme.sosRed),
        );
        Navigator.of(context).pop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    super.dispose();
  }

  Widget _waitingView() {
    final t = widget.transporteur;
    final fullName = '${t['prenom'] ?? ''} ${t['nom'] ?? ''}'.trim();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppTheme.textDark), onPressed: () => Navigator.pop(context)),
        title: const Text('Course proposée', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
              const SizedBox(height: 20),
              const Icon(Icons.handshake, size: 40, color: AppTheme.primaryBlue),
              const SizedBox(height: 12),
              Text('Demande envoyée à $fullName', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
              const SizedBox(height: 8),
              const Text('Le transporteur doit confirmer qu\'il accepte la course.\nDès son accord, vous pourrez définir votre destination.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppTheme.textGrey)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _cancelling ? null : _cancel,
                icon: const Icon(Icons.close, size: 18),
                label: _cancelling
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Annuler la demande'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.sosRed,
                  side: const BorderSide(color: AppTheme.sosRed),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _cancelling ? null : _cancel,
                icon: _cancelling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined),
                label: const Text('Annuler la demande'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.sosRed,
                  side: BorderSide(color: AppTheme.sosRed.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting) return _waitingView();
    final t = widget.transporteur;
    final v = widget.vehicle;
    final fullName = '${t['prenom'] ?? ''} ${t['nom'] ?? ''}'.trim();
    final rating = (t['average_rating'] as num?)?.toDouble() ?? 0;
    final ratingCount = t['ratings_count'] as int? ?? 0;
    final verifie = t['verifie'] as String?;
    final tripsCount = t['trips_count'] as int? ?? 0;
    final reviews = (t['reviews'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppTheme.textDark), onPressed: () => Navigator.pop(context)),
        title: const Text('Course proposée', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Transporteur identifié — carte blanche
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.lightBlueBadge,
                    backgroundImage: t['photo_url'] != null ? NetworkImage(t['photo_url']) : null,
                    child: t['photo_url'] == null ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w800)) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName.isEmpty ? 'Transporteur' : fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.verified, size: 14, color: AppTheme.successText),
                          const SizedBox(width: 4),
                          Text(verifie == 'VERIFIE' ? 'Vérifié' : verifie ?? 'Non vérifié', style: TextStyle(fontSize: 11, color: verifie == 'VERIFIE' ? AppTheme.successText : AppTheme.textGrey, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          if (rating > 0) RatingStars(rating: rating, count: ratingCount, size: 13),
                        ]),
                        const SizedBox(height: 4),
                        Text(t['telephone'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.route, size: 14, color: AppTheme.primaryBlue),
                          const SizedBox(width: 4),
                          Text('$tripsCount course(s) réalisée(s)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Véhicule
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)), child: Icon(_vehicleIcon(v['type'] as String? ?? 'VOITURE'), color: AppTheme.primaryBlue)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${v['marque'] ?? ''} ${v['modele'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${v['immatriculation'] ?? ''} • ${v['type'] ?? ''}${v['couleur'] != null ? ' • ${v['couleur']}' : ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    ]),
                  ),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.successBg, borderRadius: BorderRadius.circular(8)), child: const Text('Certifié', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successText))),
                ],
              ),
            ),
            // Avis des autres passagers
            if (reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.rate_review, size: 16, color: AppTheme.primaryBlue),
                      const SizedBox(width: 6),
                      Text('Avis des passagers', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
                    ]),
                    const SizedBox(height: 8),
                    ...reviews.take(3).map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                              Text(' ${r['rating'] ?? ''}  ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                              Text('${r['prenom'] ?? 'Passager'} ${r['nom'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                            ]),
                            if (r['comment'] != null && (r['comment'] as String).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 18, top: 2),
                                child: Text(r['comment'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                              ),
                          ]),
                        )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.security, size: 18, color: AppTheme.primaryBlue),
                  SizedBox(width: 8),
                  Expanded(child: Text('En acceptant, la protection vocale démarre automatiquement pour vous et le transporteur.', style: TextStyle(fontSize: 12, color: AppTheme.textDark))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _confirm,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Oui, commencer la course', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: (_loading || _cancelling) ? null : _cancel,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _cancelling
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Annuler la demande'),
            ),
            const SizedBox(height: 8),
            const Text('Le transporteur sera notifié : "Vous débutez une nouvelle course"', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          ],
        ),
      ),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case 'MOTO':
        return Icons.two_wheeler;
      case 'MINIBUS':
      case 'BUS':
        return Icons.airport_shuttle;
      default:
        return Icons.directions_car;
    }
  }
}