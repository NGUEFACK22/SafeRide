import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  /// Affiche le QR code réel du véhicule avec refresh automatique
  Future<void> _showQr(int vehicleId, String immatriculation) async {
    // Charger le QR actuel
    Map<String, dynamic>? qrData;
    try {
      final data = await _api.get('/vehicles/$vehicleId/qr');
      qrData = data['qr'];
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
      return;
    }

    if (qrData == null || qrData['contenu'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun QR actif pour ce véhicule')),
      );
      return;
    }

    // Afficher le QR dans un dialog avec refresh
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _QrDialog(
        vehicleId: vehicleId,
        immatriculation: immatriculation,
        initialToken: qrData!['token'],
      ),
    );
  }

  // _refreshQr supprimé — régénération auto côté backend à chaque scan (TripController.start)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon véhicule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: _vehicles.length >= 1 ? 'Un seul véhicule autorisé' : 'Ajouter un véhicule',
            onPressed: _vehicles.length >= 1 ? null : _addVehicle,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _vehicles.length >= 1 ? null : _addVehicle,
        backgroundColor: _vehicles.length >= 1 ? Colors.grey.shade400 : null,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _vehicles.isEmpty
                  ? const Center(child: Text('Aucun véhicule. Ajoutez-en un.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _vehicles.length,
                        itemBuilder: (context, index) {
                          final v = _vehicles[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                child:
                                    Icon(_typeIcon(v['type'] ?? 'VOITURE')),
                              ),
                              title: Text(
                                  '${v['marque']} ${v['modele']} — ${v['immatriculation']}'),
                              subtitle: Text(
                                  '${v['type']}${v['couleur'] != null ? ' · ${v['couleur']}' : ''} · ${v['statut']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.qr_code_2),
                                tooltip: 'Afficher le QR',
                                onPressed: () => _showQr(
                                    v['id'], v['immatriculation']),
                              ),
                            ),
                          );
                        },
                      ),
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

/// Dialog affichant le QR code avec refresh automatique après chaque scan
class _QrDialog extends StatefulWidget {
  final int vehicleId;
  final String immatriculation;
  final String initialToken;

  const _QrDialog({
    required this.vehicleId,
    required this.immatriculation,
    required this.initialToken,
  });

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  late String _token;
  Timer? _pollTimer;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    // Poller toutes les 3 secondes pour détecter un scan (token changé)
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkRefresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Vérifie si le QR a changé (après un scan par un passager)
  Future<void> _checkRefresh() async {
    try {
      final data = await _api.get('/vehicles/${widget.vehicleId}/qr');
      final qr = data['qr'];
      if (qr != null && qr['token'] != _token && mounted) {
        setState(() => _token = qr['token']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 QR régénéré après scan !'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  /// Régénérer manuellement le QR
  Future<void> _manualRefresh() async {
    try {
      final data = await _api.post('/vehicles/${widget.vehicleId}/qr/refresh', {});
      final qr = data['qr'];
      if (qr != null && mounted) {
        setState(() => _token = qr['token']);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR régénéré !'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_2, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('QR — ${widget.immatriculation}')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Vrai QR code
          QrImageView(
            data: _token,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ce QR se régénère automatiquement après chaque scan.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Bouton refresh manuel
        IconButton(
          onPressed: _manualRefresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Régénérer le QR',
          style: IconButton.styleFrom(
            backgroundColor: Colors.blue.shade50,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
