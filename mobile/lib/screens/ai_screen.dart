import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

import '../services/ai_advice_service.dart';
import '../services/ai_service.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _ai = AiService();
  final _advice = AiAdviceService();
  bool _loading = true;
  String? _summary;
  String? _weekly;
  List<dynamic> _insights = [];
  String? _error;
  TravelAdvice? _travelAdvice;
  bool _adviceLoading = false;

  // ── Assistant conversationnel (périmètre SafeRide uniquement) ──
  final TextEditingController _question = TextEditingController();
  final List<Map<String, String>> _messages = []; // {role: user|assistant, texte}
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
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
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    try {
      final data = await _ai.summary(refresh: refresh);
      final report = data['report'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() => _summary = report?['contenu'] as String?);

      // Résumé hebdomadaire IA (le dimanche / disponible à tout moment)
      try {
        final weekly = await _ai.weekly(refresh: refresh);
        if (mounted) {
          setState(() {
            _weekly =
                (weekly['report'] as Map<String, dynamic>?)?['contenu'] as String?;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _weekly = null);
      }

      // Anomalies (silencieusement ignorées si l'utilisateur n'a pas le droit)
      try {
        final anomalies = await _ai.anomalies();
        if (mounted) {
          setState(() => _insights = anomalies['insights'] as List<dynamic>? ?? []);
        }
      } catch (_) {
        if (mounted) setState(() => _insights = []);
      }

      // Conseil déplacements (historique + météo + bouchons)
      await _loadTravelAdvice();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Analyse l'historique des déplacements pour un conseil récapitulatif
  /// (destinations fréquentes + météo + conseils anti-bouchons).
  Future<void> _loadTravelAdvice() async {
    setState(() => _adviceLoading = true);
    try {
      final advice = await _advice.analyze();
      if (!mounted) return;
      setState(() {
        _travelAdvice = advice;
        _adviceLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _travelAdvice = null;
          _adviceLoading = false;
        });
      }
    }
  }

  Color _graviteColor(String? g) {
    return switch (g) {
      'ELEVEE' => Colors.red,
      'MOYENNE' => Colors.orange,
      _ => Colors.blue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant IA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Erreur : $_error'),
                      ),
                    )
                  else ...[
                    _buildChat(),
                    const SizedBox(height: 24),
                    const Text(
                      'Votre bilan personnalisé',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _summary ?? 'Aucun résumé disponible.',
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ),
                    if (_weekly != null && _weekly!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Résumé hebdomadaire',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer
                            .withValues(alpha: 0.35),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _weekly!,
                            style: const TextStyle(height: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (_insights.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Anomalies détectées',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ..._insights.map((raw) {
                      final insight = raw as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.warning,
                              color: _graviteColor(insight['gravite'])),
                          title: Text(insight['titre'] ?? ''),
                          subtitle: insight['description'] != null
                              ? Text(insight['description'])
                              : null,
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Conseil déplacements',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildAdvice(),
                ],
              ),
            ),
    );
  }

  /// Carte « Posez une question » : l'assistant ne répond que sur SafeRide.
  Widget _buildChat() {
    return Card(
      color: AppTheme.lightBlueBadge,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.smart_toy_outlined, size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Posez une question à l\'assistant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Trajets, réservation, QR, SOS, profil, prédiction… — uniquement en lien avec SafeRide.',
              style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
            ),
            const SizedBox(height: 10),
            for (final m in _messages)
              Align(
                alignment: m['role'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: m['role'] == 'user' ? AppTheme.primaryBlue : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: m['role'] == 'user'
                        ? null
                        : Border.all(color: AppTheme.lightBlueBorder),
                  ),
                  child: Text(
                    m['texte']!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: m['role'] == 'user' ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ),
              ),
            if (_asking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)),
                  SizedBox(width: 10),
                  Text('L\'assistant réfléchit…', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                ]),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _question,
                  enabled: !_asking,
                  maxLength: 500,
                  maxLines: 2,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Ex : comment réserver un trajet ?',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _asking ? null : _ask,
                icon: const Icon(Icons.send, size: 20),
                style: IconButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Carte "Conseil déplacements" : destinations fréquentes + météo + conseils.
  Widget _buildAdvice() {
    if (_adviceLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final advice = _travelAdvice;
    if (advice == null || advice.destinations.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucun historique suffisant pour générer un conseil déplacements.',
            style: TextStyle(color: AppTheme.textGrey),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final d in advice.destinations) ...[
              Row(
                children: [
                  Icon(d.weather?.icon ?? Icons.place,
                      size: 20,
                      color: d.weather == null
                          ? AppTheme.textGrey
                          : Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          '${d.count} trajet${d.count > 1 ? 's' : ''} • '
                          '${d.weather?.description ?? 'météo indisponible'} '
                          '${d.weather?.tempDisplay ?? ''}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
            ],
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 16, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(advice.recap,
                      style: const TextStyle(height: 1.4, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}