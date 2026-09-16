import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

import '../services/ai_service.dart';

/// Assistant IA = un simple chat. L'IA répond uniquement aux questions liées
/// à SafeRide (trajets, réservation, QR, SOS, profil, prédiction…) ; toute
/// autre question reçoit « Cette question n'est pas dans mes compétences. »
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final AiService _ai = AiService();
  final TextEditingController _question = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'texte': 'Bonjour ! Je suis l\'assistant SafeRide. Posez-moi une question '
          'sur les trajets, la réservation, le QR, le SOS, votre profil ou la '
          'prédiction de trafic — je ne réponds qu\'à ce sujet.',
    },
  ];
  bool _asking = false;

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _question.text.trim();
    if (q.isEmpty || _asking) return;
    _question.clear();
    setState(() {
      _messages.add({'role': 'user', 'texte': q});
      _asking = true;
    });
    _scrollToBottom();
    try {
      final data = await _ai.ask(q);
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'texte': (data['reponse'] as String?) ??
              'Cette question n\'est pas dans mes compétences.',
        });
        _asking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'texte': friendlyError(e)});
        _asking = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: AppTheme.textDark,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Assistant IA'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_asking ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) return _typingBubble();
                final m = _messages[i];
                final mine = m['role'] == 'user';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(
                      color: mine ? AppTheme.primaryBlue : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(mine ? 16 : 4),
                        bottomRight: Radius.circular(mine ? 4 : 16),
                      ),
                      border: mine
                          ? null
                          : Border.all(color: const Color(0xFFD8E4FB)),
                    ),
                    child: Text(
                      m['texte']!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: mine ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10 + MediaQuery.of(context).viewInsets.bottom + 6,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE3E8F2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _question,
                    enabled: !_asking,
                    maxLength: 500,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Votre question…',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF0F3FA),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _asking ? null : _ask,
                  icon: const Icon(Icons.send, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 16, color: AppTheme.textGrey),
            SizedBox(width: 6),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
            ),
            SizedBox(width: 8),
            Text('L\'assistant réfléchit…',
                style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          ],
        ),
      ),
    );
  }
}
