import 'package:flutter/material.dart';

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

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      final trip = await _tripService.confirmEmbarquement(widget.trip.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course acceptée — protection vocale active des deux côtés'), backgroundColor: AppTheme.primaryBlue),
      );
      Navigator.of(context).pushReplacementNamed('/trip-active', arguments: trip);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transporteur;
    final v = widget.vehicle;
    final fullName = '${t['prenom'] ?? ''} ${t['nom'] ?? ''}'.trim();
    final rating = (t['average_rating'] as num?)?.toDouble() ?? 0;
    final ratingCount = t['ratings_count'] as int? ?? 0;
    final verifie = t['verifie'] as String?;

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
              onPressed: _loading ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Annuler'),
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
