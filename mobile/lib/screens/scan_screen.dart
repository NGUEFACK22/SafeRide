import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import '../utils/error_helper.dart';
import 'course_confirm_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _api = ApiService();
  bool _loading = false;
  bool _hasPermission = false;
  bool _permissionChecked = false;
  String? _cameraError;

  final MobileScannerController _scanner = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    final ok = await PermissionService.camera(context);
    if (!mounted) return;
    setState(() { _hasPermission = ok; _permissionChecked = true; _cameraError = null; });
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
    await _startTripWithToken(code);
  }

  Future<void> _startTripWithToken(String code) async {
    if (code.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      double lat = 3.8480, lng = 11.5021;
      try {
        if (!await PermissionService.location(context)) {
          throw Exception(LanguageService.instance.t('location_permission_denied'));
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            lat = last.latitude;
            lng = last.longitude;
          }
        } catch (_) {}
      }
      final data = await _api.post('/trips/start', {
        'token': code.trim(),
        'latitude': lat,
        'longitude': lng,
      });
      if (!mounted) return;
      final trip = Trip.fromJson(data['trip'] as Map<String, dynamic>);
      final transporteur = (data['transporteur'] as Map<String, dynamic>?) ?? {};
      final vehicle = (data['vehicle'] as Map<String, dynamic>?) ?? {};
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CourseConfirmScreen(trip: trip, transporteur: transporteur, vehicle: vehicle),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildCameraView() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 48, color: Colors.white70),
                const SizedBox(height: 12),
                Text(
                  'Erreur caméra: $_cameraError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _initCamera,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MobileScanner(
      controller: _scanner,
      onDetect: _onDetect,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionChecked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.shield, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('SafeRide AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.shield, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('SafeRide AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, size: 56, color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  LanguageService.instance.t('permission_camera_denied'),
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  LanguageService.instance.t('enable_camera_settings'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _initCamera,
                  icon: const Icon(Icons.refresh),
                  label: Text(LanguageService.instance.t('retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.shield, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('SafeRide AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            tooltip: LanguageService.instance.t('torch'),
            onPressed: () => _scanner.toggleTorch(),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF1E3A5F),
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SizedBox.expand(child: _buildCameraView()),
          if (_cameraError == null) Container(color: Colors.black.withValues(alpha: 0.12)),
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Text(
                  LanguageService.instance.t('scan_instruction'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primaryBlue, width: 2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlueBadge,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.instance.t('mode_scan_active'),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        Text(
                          LanguageService.instance.t('align_qr'),
                          style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                        ),
                      ],
                    ),
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
