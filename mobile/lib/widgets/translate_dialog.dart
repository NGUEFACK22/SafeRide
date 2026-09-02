import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/translation_service.dart';
import '../theme/app_theme.dart';

class TranslateDialog extends StatefulWidget {
  const TranslateDialog({super.key});
  @override
  State<TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<TranslateDialog> {
  final _service = TranslationService();
  final _stt = stt.SpeechToText();
  final _controller = TextEditingController();
  String _from = 'fr';
  String _to = 'en';
  String _result = '';
  bool _loading = false;
  bool _listening = false;

  void _swap() => setState(() { final tmp = _from; _from = _to; _to = tmp; final r = _result; _result = _controller.text; _controller.text = r; });

  Future<void> _translate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    final res = await _service.translate(text, from: _from, to: _to);
    setState(() { _result = res; _loading = false; });
  }

  Future<void> _listen() async {
    if (_listening) { await _stt.stop(); setState(() => _listening = false); return; }
    final avail = await _stt.initialize();
    if (!avail) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Micro indisponible'))); return; }
    setState(() => _listening = true);
    await _stt.listen(localeId: _from == 'fr' ? 'fr_FR' : 'en_US', onResult: (r) => setState(() => _controller.text = r.recognizedWords));
    _stt.statusListener = (s) { if (s == 'notListening' && mounted) setState(() => _listening = false); };
  }

  @override
  void dispose() { _stt.cancel(); _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.translate, size: 18, color: AppTheme.primaryBlue)), const SizedBox(width: 8), const Text('Traduction vocale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Chip(label: Text(_from == 'fr' ? 'Français' : 'Anglais', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), backgroundColor: AppTheme.lightBlueBadge),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 16, color: AppTheme.textGrey)),
          Chip(label: Text(_to == 'fr' ? 'Français' : 'Anglais', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), backgroundColor: Colors.grey.shade100),
          const Spacer(), IconButton(onPressed: _swap, icon: const Icon(Icons.swap_horiz, size: 20, color: AppTheme.primaryBlue), tooltip: 'Inverser'),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _controller, minLines: 2, maxLines: 3, decoration: InputDecoration(hintText: _from == 'fr' ? 'Parlez ou tapez en français…' : 'Speak or type in English…', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), suffixIcon: IconButton(onPressed: _listen, icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? AppTheme.sosRed : AppTheme.primaryBlue))), onSubmitted: (_) => _translate()),
        const SizedBox(height: 10),
        Row(children: [FilledButton.icon(onPressed: _loading ? null : _translate, icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.translate, size: 16), label: const Text('Traduire')), const SizedBox(width: 8), OutlinedButton.icon(onPressed: _listen, icon: Icon(_listening ? Icons.stop : Icons.mic, size: 16), label: Text(_listening ? 'Arrêter' : 'Parler'))]),
        const SizedBox(height: 12),
        if (_result.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.successBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.successBorder)), child: SelectableText(_result, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.successText))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}
