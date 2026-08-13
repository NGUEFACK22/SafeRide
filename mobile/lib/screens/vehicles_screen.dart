import 'package:flutter/material.dart';

import '../services/api_service.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final _api = ApiService();
  List<dynamic> _vehicles = [];
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
      final data = await _api.get('/vehicles');
      if (!mounted) return;
      setState(() {
        _vehicles = data['vehicles'] as List<dynamic>? ?? [];
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

  Future<void> _addVehicle() async {
    final marque = TextEditingController();
    final modele = TextEditingController();
    final immatriculation = TextEditingController();
    String type = 'VOITURE';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un véhicule'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: marque,
                decoration: const InputDecoration(labelText: 'Marque'),
              ),
              TextField(
                controller: modele,
                decoration: const InputDecoration(labelText: 'Modèle'),
              ),
              TextField(
                controller: immatriculation,
                decoration: const InputDecoration(labelText: 'Immatriculation'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'MOTO', child: Text('Moto')),
                  DropdownMenuItem(value: 'VOITURE', child: Text('Voiture')),
                  DropdownMenuItem(value: 'MINIBUS', child: Text('Minibus')),
                  DropdownMenuItem(value: 'BUS', child: Text('Bus')),
                ],
                onChanged: (v) => type = v ?? 'VOITURE',
                decoration: const InputDecoration(labelText: 'Type'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await _api.post('/vehicles', {
        'marque': marque.text.trim(),
        'modele': modele.text.trim(),
        'immatriculation': immatriculation.text.trim().toUpperCase(),
        'type': type,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Véhicule ajouté avec son QR code associé')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _toggleQr(int vehicleId, String immatriculation) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre QR code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 120),
            const SizedBox(height: 12),
            Text('Véhicule : $immatriculation'),
            const Text(
              'Placez le QR dans le véhicule. Scannez quand un passager '
              'démarre un trajet.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes véhicules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un véhicule',
            onPressed: _addVehicle,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addVehicle,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _vehicles.isEmpty
                  ? const Center(child: Text('Aucun véhicule. Ajoutez-en un.'))
                  : ListView.builder(
                      itemCount: _vehicles.length,
                      itemBuilder: (context, index) {
                        final v = _vehicles[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(_typeIcon(v['type'] ?? 'VOITURE')),
                            ),
                            title: Text(
                                '${v['marque']} ${v['modele']} — ${v['immatriculation']}'),
                            subtitle: Text(
                                '${v['type']}${v['couleur'] != null ? ' · ${v['couleur']}' : ''} · ${v['statut']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.qr_code_2),
                              tooltip: 'Afficher le QR',
                              onPressed: () => _toggleQr(
                                  v['id'], v['immatriculation']),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  IconData _typeIcon(String type) {
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