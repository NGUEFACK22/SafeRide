import 'dart:convert';
import 'package:http/http.dart' as http;

/// Traducteur léger EN↔FR via MyMemory (gratuit, sans clé). Fallback simple.
class TranslationService {
  Future<String> translate(String text, {required String from, required String to}) async {
    if (text.trim().isEmpty) return '';
    final uri = Uri.parse('https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$from|$to');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final trans = (data['responseData'] as Map<String, dynamic>?)?['translatedText'] as String?;
        if (trans != null && trans.isNotEmpty) return trans;
      }
    } catch (_) {}
    // Fallback : retourne texte original avec note
    return text;
  }
}
