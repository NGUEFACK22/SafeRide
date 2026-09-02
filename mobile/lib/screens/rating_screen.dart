import 'package:flutter/material.dart';
import '../utils/error_helper.dart';

import '../models/trip.dart';
import '../services/rating_service.dart';
import '../models/trip_rating.dart';

class RatingScreen extends StatefulWidget {
  final Trip trip;
  final TripRating? existingRating;

  const RatingScreen({super.key, required this.trip, this.existingRating});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final _service = RatingService();
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _loading = false;
  List<TripRating> _others = [];
  bool _loadingOthers = true;

  @override
  void initState() {
    super.initState();
    _rating = widget.existingRating?.rating ?? 5;
    _commentCtrl.text = widget.existingRating?.comment ?? '';
    _loadOthers();
  }

  Future<void> _loadOthers() async {
    try {
      final meta = await _service.getTripRatingsWithMeta(widget.trip.id);
      final list = (meta['ratings'] as List).map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _others = list;
        _loadingOthers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOthers = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      if (widget.existingRating != null) {
        await _service.updateRating(widget.trip.id, _rating, comment: _commentCtrl.text);
      } else {
        await _service.rateTrip(widget.trip.id, _rating, comment: _commentCtrl.text);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci pour votre note !')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _stars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final idx = i + 1;
        return IconButton(
          icon: Icon(idx <= _rating ? Icons.star : Icons.star_border, size: 40, color: Colors.amber.shade700),
          onPressed: () => setState(() => _rating = idx),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.existingRating != null;
    return Scaffold(
      appBar: AppBar(title: Text(isUpdate ? 'Modifier ma note' : 'Noter le trajet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text('Trajet #${widget.trip.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(widget.trip.destinationAddress ?? 'Trajet sans destination', textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(widget.trip.transporteurFullName.isEmpty ? '' : 'avec ${widget.trip.transporteurFullName}',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Votre note', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            _stars(),
            Text('$_rating / 5', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Commentaire (optionnel)',
                hintText: 'Conduite, ponctualité, confort...',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              label: Text(isUpdate ? 'Mettre à jour' : 'Envoyer la note'),
            ),
            const Divider(height: 32),
            Text('Avis sur ce trajet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loadingOthers) const Center(child: CircularProgressIndicator())
            else if (_others.isEmpty) const Text('Aucun avis pour ce trajet')
            else ..._others.map((r) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${r.rating}')),
                    title: Row(
                      children: List.generate(5, (i) => Icon(i < r.rating ? Icons.star : Icons.star_border, size: 16, color: Colors.amber)),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r.comment != null && r.comment!.isNotEmpty) Text(r.comment!),
                        Text('${r.rater?['prenom'] ?? ''} ${r.rater?['nom'] ?? ''} · ${r.createdAt?.substring(0, 10) ?? ''}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }
}
