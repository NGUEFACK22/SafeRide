import 'package:flutter/material.dart';

import '../services/api_service.dart';

class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  final _api = ApiService();
  final _tripIdController = TextEditingController();
  final _motifController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    final tripId = int.tryParse(_tripIdController.text.trim());
    if (tripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez un identifiant de trajet valide')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.post('/disputes', {
        'trip_id': tripId,
        'motif': _motifController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Litige ouvert. Un gestionnaire y est attribué.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ouvrir un litige')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _tripIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ID du trajet',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motifController,
              decoration: const InputDecoration(
                labelText: 'Motif',
                border: OutlineInputBorder(),
                hintText: 'Ex : Détour d\'itinéraire, comportement du chauffeur',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.gavel),
              label: const Text('Ouvrir le litige'),
            ),
          ],
        ),
      ),
    );
  }
}