import 'package:flutter/material.dart';

/// Messenger racine, branché sur MaterialApp (voir main.dart).
/// Permet d'afficher un message APRÈS une navigation qui détruit le Scaffold
/// courant (ex. fin de trajet → accueil + "Trajet terminé").
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showRootMessage(String message, {Color backgroundColor = Colors.green}) {
  try {
    rootMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
      ),
    );
  } catch (_) {}
}
