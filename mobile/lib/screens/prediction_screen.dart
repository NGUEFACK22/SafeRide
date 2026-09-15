import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_helper.dart';

import '../services/ai_service.dart';

/// Écran PRÉDICTION : l'IA analyse l'historique de trajets de l'utilisateur
/// (zones fréquentes, horaires), interroge le climat (Open-Meteo via le
/// backend) et prédit les heures à bouchons + conseils pour les éviter.
class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final _ai = AiService();
  bool _loading = true;
  Map<String, dynamic>? _prediction;
  String? _narratif;
  String? _generateur;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ai.prediction(refresh: refresh);
      final report = data['report'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _prediction = data['prediction'] as Map<String, dynamic>?;
        _narratif = report?['contenu'] as String?;
        _generateur = report?['generateur'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.textDark,
        foregroundColor: Colors.white,
        title: Text(lang.t('prediction_title')),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: AppTheme.primaryBlue),
                const SizedBox(height: 14),
                Text(lang.t('analyse_zone'), style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              ]),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 48, color: AppTheme.textGrey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textGrey)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _load(refresh: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(refresh: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _header(lang),
                      const SizedBox(height: 14),
                      _bouchonsCard(lang),
                      const SizedBox(height: 12),
                      _fluidesCard(lang),
                      const SizedBox(height: 12),
                      _climatCard(lang),
                      const SizedBox(height: 12),
                      _zonesCard(lang),
                      const SizedBox(height: 12),
                      _conseilsCard(lang),
                      const SizedBox(height: 12),
                      if (_narratif != null && _narratif!.isNotEmpty) _iaCard(lang),
                    ],
                  ),
                ),
    );
  }

  Map<String, dynamic> get _p => _prediction ?? const {};

  Widget _header(LanguageService lang) {
    final n = _p['nb_trajets_analyses'] ?? 0;
    final genere = _p['genere_le'] ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.textDark, Color(0xFF1B2F6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.insights, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lang.t('prediction_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 3),
            Text('$n trajets analysés • $genere',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _generateur == 'IA_SafeRide' ? Colors.green.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _generateur == 'IA_SafeRide' ? lang.t('ia_safe') : lang.t('regle'),
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _bouchonsCard(LanguageService lang) {
    final heures = List<String>.from(_p['heures_bouchons'] ?? const []);
    return _card(
      lang.t('bouchons_title'),
      Icons.traffic,
      Colors.red.shade700,
      heures.isEmpty
          ? const Text('Données insuffisantes pour prédire des pics.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in heures)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.access_time, size: 14, color: Colors.red.shade700),
                      const SizedBox(width: 5),
                      Text(h, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red.shade800, fontSize: 13)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 8),
              const Text('Créneaux où votre temps de trajet est susceptible de s’allonger.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ]),
    );
  }

  Widget _fluidesCard(LanguageService lang) {
    final heures = List<String>.from(_p['heures_fluides'] ?? const []);
    return _card(
      lang.t('fluides_title'),
      Icons.timeline,
      Colors.green.shade700,
      heures.isEmpty
          ? const Text('Aucun créneau fluide identifié pour le moment.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey))
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in heures)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 5),
                    Text(h, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade800, fontSize: 13)),
                  ]),
                ),
            ]),
    );
  }

  Widget _climatCard(LanguageService lang) {
    final climats = List<Map<String, dynamic>>.from(
        (_p['climats'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? const []);
    return _card(lang.t('climat_title'), Icons.cloud_outlined, AppTheme.primaryBlue, climats.isEmpty
        ? const Text('Climat indisponible (zones non géolocalisées ou réseau).',
            style: TextStyle(fontSize: 12, color: AppTheme.textGrey))
        : Column(children: [
            for (final c in climats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(_climatIcon(c['code_wmo']), size: 18, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${c['libelle'] ?? c['zone']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                  ),
                  Text('${c['description'] ?? ''} ${c['temperature_c'] != null ? '• ${c['temperature_c']}°C' : ''}${c['pluie_prob'] != null ? ' • pluie ${c['pluie_prob']}%' : ''}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                ]),
              ),
          ]));
  }

  IconData _climatIcon(dynamic code) {
    final c = code is int ? code : int.tryParse('${code ?? ''}') ?? -1;
    if (c <= 1) return Icons.wb_sunny;
    if (c <= 3) return Icons.cloud;
    if (c <= 48) return Icons.wb_twilight;
    if (c <= 67) return Icons.grain;
    if (c <= 82) return Icons.beach_access;
    return Icons.bolt;
  }

  Widget _zonesCard(LanguageService lang) {
    final zones = List<Map<String, dynamic>>.from(
        (_p['zones_frequentes'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? const []);
    return _card(lang.t('zones_title'), Icons.place_outlined, AppTheme.primaryBlue, zones.isEmpty
        ? const Text('Effectuez quelques trajets pour que l’IA apprenne vos zones.',
            style: TextStyle(fontSize: 12, color: AppTheme.textGrey))
        : Column(children: [
            for (final z in zones)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_history, size: 20, color: AppTheme.primaryBlue),
                title: Text('${z['libelle']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)),
                  child: Text('${z['trajets']} x', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                ),
              ),
          ]));
  }

  Widget _conseilsCard(LanguageService lang) {
    final conseils = List<String>.from(_p['conseils'] ?? const []);
    if (conseils.isEmpty) return const SizedBox.shrink();
    return _card(lang.t('conseils_title'), Icons.lightbulb_outline, Colors.amber.shade800, Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in conseils)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('💡 ', style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                Expanded(child: Text(c, style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.4))),
              ]),
            ),
        ]));
  }

  Widget _iaCard(LanguageService lang) {
    return _card(
      _generateur == 'IA_SafeRide' ? 'Analyse IA' : 'Analyse détaillée',
      Icons.auto_awesome,
      const Color(0xFF7C3AED),
      Text(_narratif!, style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.5)),
    );
  }

  Widget _card(String titre, IconData icon, Color couleur, Widget contenu) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: couleur),
          const SizedBox(width: 8),
          Text(titre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
        ]),
        const SizedBox(height: 10),
        contenu,
      ]),
    );
  }
}
