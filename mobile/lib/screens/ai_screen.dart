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

  @override
  void initState() {
    super.initState();
    _load();
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