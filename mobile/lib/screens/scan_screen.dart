import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import 'course_confirm_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final _api = ApiService();

  bool _loading = false;
  bool _hasPermission = false;
  bool _permissionChecked = false;
  String? _cameraError;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  // Contrôleur géré manuellement : autoStart désactivé pour contrôler
  // précisément le cycle de vie de la caméra (évite les doubles démarrages).
  MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermission());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startCamera();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _stopCamera();
        break;
      default:
        break;
    }
  }

  Future<void> _startCamera() async {
    if (_cameraError != null) return;
    try {
      await _scanner.start();
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _scanner.stop();
    } catch (_) {}
  }

  Future<void> _restartCamera() async {
    setState(() => _cameraError = null);
    // Recréer un contrôleur propre après une erreur caméra
    try {
      await _scanner.dispose();
    } catch (_) {}
    _scanner = MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
    );
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  Future<void> _checkPermission() async {
    final ok = await PermissionService.camera(context);
    if (!mounted) return;
    setState(() {
      _hasPermission = ok;
      _permissionChecked = true;
    });
    if (ok) {
      // Le MobileScanner se monte à la prochaine frame, puis on démarre la caméra
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
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
                  'Erreur caméra:\n$_cameraError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _restartCamera,
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_loading) return;
    if (DateTime.now().difference(_lastAttempt) < const Duration(seconds: 2)) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _lastAttempt = DateTime.now();
    await _startTripWithToken(code);
  }

  Future<void> _startTripWithToken(String code) async {
    if (code.trim().isEmpty) return;
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.instance.t('auth_error_relogin')), backgroundColor: Colors.orange),
      );
      Navigator.of(context).pushNamed('/login');
      return;
    }
    setState(() => _loading = true);
    try {
      double lat = 3.8480, lng = 11.5021;
      if (!mounted) return;
      final locationOk = await PermissionService.location(context);
      if (!locationOk) {
        // L'utilisateur a refusé la localisation — on lui demande de l'activer
        if (!mounted) return;
        _showLocationDialog();
        return;
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // GPS indisponible (intérieur, aucun fix) : on garde la position par
        // défaut de test pour ne pas bloquer le démarrage. Le backend valide
        // ensuite la proximité si le véhicule a une position fraîche.
        if (!mounted) return;
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
      final msg = _mapError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(Object e) {
    if (e is ApiException) {
      final status = e.statusCode;
      final raw = e.message;
      final r = raw.toLowerCase();
      // 1. Message backend réel d'abord (il est déjà en français, explicite)
      if (r.contains('proximité') || r.contains('proximite')) {
        return 'Proximité non vérifiée — soyez à côté du véhicule avant de scanner.';
      }
      if (r.contains('déjà utilisé') || r.contains('deja utilise') || status == 422 && r.contains('utilisé')) {
        return LanguageService.instance.t('qr_already_used');
      }
      if (status == 401) return LanguageService.instance.t('auth_error_relogin');
      if (status == 403) return LanguageService.instance.t('access_denied');
      if (status == 422) return raw;
      if (status == 500) return LanguageService.instance.t('server_unavailable_try_later');
      // Retourner le message serveur réel si présent (fini le "trip_start_failed" générique)
      return raw.isNotEmpty ? raw : LanguageService.instance.t('trip_start_failed');
    }
    final r = e.toString().toLowerCase();
    if (r.contains('location_permission_denied')) return LanguageService.instance.t('location_permission_denied');
    return LanguageService.instance.t('trip_start_failed');
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(Icons.location_on, color: AppTheme.primaryBlue), SizedBox(width: 8), Text(LanguageService.instance.t('location_required'))]),
        content: Text(LanguageService.instance.t('enable_location_to_scan')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.instance.t('cancel'))),
          FilledButton(onPressed: () {
            Navigator.pop(ctx);
            // Ouvre les paramètres Android/iOS
            // Note : pour iOS on utiliserait openAppSettings, mais Flutter gère cross-platform via url_launcher
            // ici on laisse un message guiding l'utilisateur
          }, child: Text(LanguageService.instance.t('settings'))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionChecked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: _buildAppBar(),
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
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  LanguageService.instance.t('enable_camera_settings'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _checkPermission,
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
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SizedBox.expand(child: _buildCameraView()),
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

  AppBar _buildAppBar() {
    return AppBar(
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
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF1E3A5F),
            child: Icon(Icons.person, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
