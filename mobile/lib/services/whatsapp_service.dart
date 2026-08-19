import 'package:url_launcher/url_launcher.dart';

/// Ouvre WhatsApp avec un message SOS pré-rempli pour chaque contact d'urgence.
/// Gratuit, fonctionne avec WiFi ou données mobiles (pas besoin de forfait SMS).
class WhatsAppService {
  WhatsAppService._();
  static final WhatsAppService instance = WhatsAppService._();

  /// Nettoie un numéro de téléphone : ne garde que les chiffres et le +.
  String _cleanPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    return cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
  }

  /// Ouvre WhatsApp avec un message SOS pré-rempli pour un contact.
  /// Renvoie true si WhatsApp a été ouvert avec succès.
  Future<bool> sendSosMessage(String phone, String message) async {
    final cleanNumber = _cleanPhone(phone);
    if (cleanNumber.isEmpty) return false;

    final encodedMessage = Uri.encodeComponent(message);

    // WhatsApp URL : wa.me/<numéro>?text=<message>
    final whatsappUrl = Uri.parse('https://wa.me/$cleanNumber?text=$encodedMessage');

    // Fallback : URL directe WhatsApp (certains pays)
    final alternativeUrl = Uri.parse(
      'whatsapp://send?phone=$cleanNumber&text=$encodedMessage',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return true;
      } else if (await canLaunchUrl(alternativeUrl)) {
        await launchUrl(alternativeUrl, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Envoie le message SOS via WhatsApp à plusieurs contacts.
  /// Ouvre WhatsApp pour chaque contact.
  Future<int> sendBulk(List<String> phones, String message) async {
    int sent = 0;
    for (final phone in phones) {
      if (await sendSosMessage(phone, message)) sent++;
    }
    return sent;
  }
}
