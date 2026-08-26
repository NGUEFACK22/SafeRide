import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service centralisé pour demander les permissions à chaque fonctionnalité
/// Affiche un Snackbar explicite si refusé, et propose d'ouvrir les paramètres
class PermissionService {
  static Future<bool> _request(Permission permission, BuildContext context, String label) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    if (status.isDenied) {
      final res = await permission.request();
      if (res.isGranted) return true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission $label refusée')));
      }
      return false;
    }
    if (status.isPermanentlyDenied && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permission $label refusée définitivement — activez-la dans Paramètres'),
          action: SnackBarAction(label: 'Paramètres', onPressed: () => openAppSettings()),
        ),
      );
    }
    return false;
  }

  static Future<bool> camera(BuildContext context) => _request(Permission.camera, context, 'Caméra');
  static Future<bool> photos(BuildContext context) async {
    // Android 13+ : photos, sinon storage
    if (await Permission.photos.status.isGranted || await Permission.storage.status.isGranted) return true;
    final p = await Permission.photos.request();
    if (p.isGranted) return true;
    final s = await Permission.storage.request();
    return s.isGranted;
  }
  static Future<bool> location(BuildContext context) => _request(Permission.locationWhenInUse, context, 'Localisation');
  static Future<bool> microphone(BuildContext context) => _request(Permission.microphone, context, 'Microphone');
  static Future<bool> notification(BuildContext context) => _request(Permission.notification, context, 'Notifications');
}
