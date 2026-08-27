import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import 'course_confirm_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _api = ApiService();
  final MobileScannerController _scanner = MobileScannerController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => PermissionService.camera(context));
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_loading) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _loading = true);
    await _scanner.stop();
    try {
      if (!await PermissionService.location(context)) {
        throw Exception('Permission localisation refusée');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      // Appel direct pour récupérer transporteur + véhicule (nouveau flux)
      final data = await _api.post('/trips/start', {
        'token': code,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
      if (!mounted) return;
      final trip = Trip.fromJson(data['trip'] as Map<String, dynamic>);
      final transporteur = (data['transporteur'] as Map<String, dynamic>?) ?? {};
      final vehicle = (data['vehicle'] as Map<String, dynamic>?) ?? {};

      // Afficher les infos transporteur + bouton "Commencer la course ?"
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CourseConfirmScreen(trip: trip, transporteur: transporteur, vehicle: vehicle),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
      await _scanner.start();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.shield, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('SafeRide AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: CircleAvatar(radius: 14, backgroundColor: Color(0xFF1E3A5F), child: Icon(Icons.person, size: 16, color: Colors.white)))],
      ),
      body: Stack(
        children: [
          // Overlay sombre + consigne
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Column(
              children: [
                const Text('Scannez le QR Code du\ntransporteur pour démarrer\nvotre trajet', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                Container(
                  height: 220,
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.primaryBlue, width: 2), borderRadius: BorderRadius.circular(20)),
                  child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(18), child: MobileScanner(controller: _scanner, onDetect: _onDetect)),
                    Positioned.fill(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.15))))),
                  ]),
                ),
              ],
            ),
          ),
          if (_loading)
            Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))),
          // Bottom sheet maquette "Mode scan"
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryBlue)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Mode scan actif', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      Text('Alignez le QR code du transporteur', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}