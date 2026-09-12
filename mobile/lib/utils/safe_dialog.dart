import 'package:flutter/material.dart';

/// Ouvre un [showDialog] seulement une fois toute transition de route terminée.
///
/// Flutter lance l'assertion `_dependents.isEmpty` (`framework.dart`) quand un
/// dialog est poussé pendant la transition de sortie d'un dialog/route
/// précédent (ex : gate contacts puis dialog de confirmation). Basculer
/// l'Overlay à ce moment désactive un InheritedElement qui a encore des
/// dépendants. On attend la fin de la frame + un délai court : les transitions
/// de dialogs durent ~150-200 ms.
Future<T?> showDialogSafe<T extends Object?>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!context.mounted) return null;
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
}