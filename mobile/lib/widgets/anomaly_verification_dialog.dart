import 'package:flutter/material.dart';
import '../services/anomaly_service.dart';
import '../services/language_service.dart';
import '../utils/error_helper.dart';

/// Type lisible de l'anomalie pour l'affichage.
String _anomalyLabel(String type) {
  switch (type) {
    case 'SPEED':
      return LanguageService.instance.t('anomaly_speed');
    case 'STOP':
      return LanguageService.instance.t('anomaly_stop');
    case 'MOVEMENT_LOSS':
      return LanguageService.instance.t('anomaly_movement_loss');
    case 'DETOUR':
      return LanguageService.instance.t('anomaly_detour');
    default:
      return type;
  }
}

IconData _anomalyIcon(String type) {
  switch (type) {
    case 'SPEED':
      return Icons.speed;
    case 'STOP':
      return Icons.pause_circle_outline;
    case 'MOVEMENT_LOSS':
      return Icons.signal_wifi_off;
    case 'DETOUR':
      return Icons.alt_route;
    default:
      return Icons.warning_amber;
  }
}

Color _graviteColor(String gravite) {
  switch (gravite) {
    case 'ELEVEE':
      return Colors.red;
    case 'MOYENNE':
      return Colors.orange;
    default:
      return Colors.amber;
  }
}

/// Affiche une boîte de dialogue interactive quand une anomalie est détectée.
/// L'utilisateur confirme "normal" (course continue) ou signale un problème (SOS).
Future<void> showAnomalyDialog(
  BuildContext context,
  Map<String, dynamic> verification,
) async {
  final id = verification['id'] as int;
  final type = verification['anomaly_type'] as String? ?? 'UNKNOWN';
  final description = verification['description'] as String? ?? '';
  final gravite = verification['gravite'] as String? ?? 'MOYENNE';

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(_anomalyIcon(type), color: _graviteColor(gravite), size: 48),
      title: Text(LanguageService.instance.t('anomaly_detected')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _graviteColor(gravite).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_anomalyIcon(type), size: 16, color: _graviteColor(gravite)),
                const SizedBox(width: 8),
                Text(
                  _anomalyLabel(type),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _graviteColor(gravite),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            LanguageService.instance.t('anomaly_ask_normal'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(ctx, 'normal'),
          icon: const Icon(Icons.check_circle, color: Colors.green),
          label: Text(
            LanguageService.instance.t('anomaly_confirm_normal'),
            style: const TextStyle(color: Colors.green),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, 'abnormal'),
          icon: const Icon(Icons.warning, color: Colors.white),
          label: Text(
            LanguageService.instance.t('anomaly_report_problem'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  if (result == null || !context.mounted) return;

  try {
    await AnomalyService().respond(id, result);

    if (!context.mounted) return;

    if (result == 'normal') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.instance.t('anomaly_confirmed')),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.instance.t('anomaly_sos_triggered')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
    );
  }
}
