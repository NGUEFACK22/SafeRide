import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'safe_dialog.dart';

/// Gate KYC : vérifie que le compte est vérifié (identité VERIFIE).
/// Retourne true si OK. Sinon affiche un dialogue "Compte non vérifié"
/// avec un bouton vers l'écran de vérification, et retourne false.
///
/// À appeler AVANT scan QR / création véhicule / acceptation de course.
/// Le backend refuse de toute façon en 403 — ce gate évite l'aller-retour
/// sec et guide l'utilisateur. En cas de doute réseau, on laisse passer
/// (le backend tranche, message 403 explicite en filet).
Future<bool> ensureIdentityVerified(BuildContext context) async {
  bool verified = false;
  try {
    final data = await ApiService().get('/identity/status');
    verified = data['identite_verifiee'] == true;
  } catch (_) {
    return true;
  }
  if (verified || !context.mounted) return verified;

  final go = await showDialogSafe<bool>(
    context,
    (ctx) => AlertDialog(
      icon: const Icon(
        Icons.verified_user_outlined,
        color: AppTheme.primaryBlue,
        size: 36,
      ),
      title: const Text('Compte non vérifié'),
      content: const Text(
        'Vérifiez votre identité pour lancer une course '
        '(passager comme transporteur). Cela prend quelques minutes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Plus tard'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.verified_user, size: 18),
          label: const Text('Vérifier mon identité'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
          ),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    Navigator.pushNamed(context, '/identity');
  }
  return false;
}
