import 'package:flutter/material.dart';

import '../services/api_service.dart';

class LostItemScreen extends StatefulWidget {
  const LostItemScreen({super.key});

  @override
  State<LostItemScreen> createState() => _LostItemScreenState();
}

class _LostItemScreenState extends State<LostItemScreen> {
  final _api = ApiService();
  final _objetController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tripIdController = TextEditingController();
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
      await _api.post('/lost-items', {
        'trip_id': tripId,
        'objet': _objetController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Objet perdu signalé. Le signalement est lié à votre trajet '
              'et au transporteur.'),
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
      appBar: AppBar(title: const Text('Objet perdu')),
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
                hintText: 'Ex : 5',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _objetController,
              decoration: const InputDecoration(
                labelText: 'Objet oublié',
                border: OutlineInputBorder(),
                hintText: 'Ex : Portefeuille noir',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.report_problem),
              label: const Text('Signaler l\'objet perdu'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le signalement est automatiquement associé au trajet, au '
              'transporteur et au véhicule. Un gestionnaire en sera informé.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}