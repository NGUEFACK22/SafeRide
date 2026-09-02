import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/error_helper.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../services/language_service.dart';

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
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _addVehicle() async {
    final hasExisting = _vehicles.isNotEmpty;
    final marque = TextEditingController();
    final modele = TextEditingController();
    final immatriculation = TextEditingController();
    String type = 'VOITURE';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasExisting ? LanguageService.instance.t('replace_vehicle') : LanguageService.instance.t('add_vehicle_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasExisting)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18), SizedBox(width: 8), Expanded(child: Text(LanguageService.instance.t('single_vehicle_warning'), style: TextStyle(fontSize: 12, color: Colors.orange.shade800)))]),
                ),
              TextField(
                controller: marque,
                decoration: InputDecoration(labelText: LanguageService.instance.t('brand')),
              ),
              TextField(
                controller: modele,
                decoration: InputDecoration(labelText: LanguageService.instance.t('model')),
              ),
              TextField(
                controller: immatriculation,
                decoration: InputDecoration(labelText: LanguageService.instance.t('registration')),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  DropdownMenuItem(value: 'MOTO', child: Text(LanguageService.instance.t('moto'))),
                  DropdownMenuItem(value: 'VOITURE', child: Text(LanguageService.instance.t('car'))),
                  DropdownMenuItem(value: 'MINIBUS', child: Text(LanguageService.instance.t('minibus'))),
                  DropdownMenuItem(value: 'BUS', child: Text(LanguageService.instance.t('bus'))),
                ],
                onChanged: (v) => type = v ?? 'VOITURE',
                decoration: InputDecoration(labelText: LanguageService.instance.t('type')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(LanguageService.instance.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasExisting ? LanguageService.instance.t('replace') : LanguageService.instance.t('add')),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final res = await _api.post('/vehicles', {
        'marque': marque.text.trim(),
        'modele': modele.text.trim(),
        'immatriculation': immatriculation.text.trim().toUpperCase(),
        'type': type,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(res['message'] as String? ?? 'Véhicule enregistré avec son QR code associé')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
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
        SnackBar(content: Text(friendlyError(e))),
      );
      return;
    }

    if (qrData == null || qrData['contenu'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.instance.t('no_active_qr'))),
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

  Future<void> _deleteVehicle(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(LanguageService.instance.t('delete_vehicle_confirm')),
        content: Text(LanguageService.instance.t('delete_vehicle_msg')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.instance.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(LanguageService.instance.t('delete'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete('/vehicles/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.instance.t('vehicle_deleted'))));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVehicle = _vehicles.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(hasVehicle ? LanguageService.instance.t('my_unique_vehicle') : LanguageService.instance.t('my_vehicle')),
        actions: [
          IconButton(
            icon: Icon(hasVehicle ? Icons.swap_horiz : Icons.add),
            tooltip: hasVehicle ? LanguageService.instance.t('replace_vehicle') : LanguageService.instance.t('add_vehicle_title'),
            onPressed: _addVehicle,
          ),
        ],
      ),
      floatingActionButton: hasVehicle
          ? null
          : FloatingActionButton(
              onPressed: _addVehicle,
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _vehicles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.directions_car, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(LanguageService.instance.t('no_vehicle_add_unique'), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(onPressed: _addVehicle, icon: Icon(Icons.add), label: Text(LanguageService.instance.t('add_vehicle'))),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                            child: Row(children: [Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18), const SizedBox(width: 8), const Expanded(child: Text('Un seul véhicule autorisé par transporteur. Ajouter un nouveau véhicule remplacera l\'ancien.', style: TextStyle(fontSize: 12)))]),
                          ),
                          const SizedBox(height: 12),
                          ..._vehicles.map((v) => Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: ListTile(
                                  leading: CircleAvatar(child: Icon(_typeIcon(v['type'] ?? 'VOITURE'))),
                                  title: Text('${v['marque']} ${v['modele']} — ${v['immatriculation']}'),
                                  subtitle: Text('${v['type']}${v['couleur'] != null ? ' · ${v['couleur']}' : ''} · ${v['statut']}'),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(icon: Icon(Icons.qr_code_2), tooltip: LanguageService.instance.t('show_qr'), onPressed: () => _showQr(v['id'], v['immatriculation'])),
                                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Supprimer (bloqué si seul)', onPressed: () => _deleteVehicle(v['id'])),
                                  ]),
                                ),
                              )),
                        ],
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
            SnackBar(                  content: Text('QR régénéré après scan !'),
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
          SnackBar(
            content: Text(LanguageService.instance.t('qr_regenerated_simple')),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
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
                    LanguageService.instance.t('qr_auto_regen'),
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
          tooltip: LanguageService.instance.t('regenerate_qr'),
          style: IconButton.styleFrom(
            backgroundColor: Colors.blue.shade50,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(LanguageService.instance.t('close')),
        ),
      ],
    );
  }
}