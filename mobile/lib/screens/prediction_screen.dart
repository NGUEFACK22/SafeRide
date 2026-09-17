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
                      _circulationBlock(lang),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.textDark, Color(0xFF1B2F6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0F62FE), Color(0xFF7C3AED)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.insights, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang.t('prediction_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 3),
              Text(lang.t('analyse_zone'), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _generateur == 'IA_SafeRide' ? Colors.green.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              _generateur == 'IA_SafeRide' ? lang.t('ia_safe') : lang.t('regle'),
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _statChip(Icons.route_outlined, '$n', lang.t('trips').toLowerCase(), Colors.blue.shade300),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text(genere.isEmpty ? '' : '${lang.t('analyzed_on')} $genere', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _statChip(IconData icon, String valeur, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(valeur, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10)),
      ]),
    );
  }

  /// Bloc « Circulation » : heures à bouchons + créneaux fluides côte à côte.
  Widget _circulationBlock(LanguageService lang) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(Icons.traffic, lang.t('bouchons_title'), Colors.red.shade700),
        const SizedBox(height: 12),
        _bouchonsContent(lang),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _cardHeader(Icons.timeline, lang.t('fluides_title'), Colors.green.shade700),
        const SizedBox(height: 12),
        _fluidesContent(lang),
      ]),
    );
  }

  Widget _cardHeader(IconData icon, String titre, Color couleur) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: couleur),
      ),
      const SizedBox(width: 10),
      Text(titre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
    ]);
  }

  Widget _bouchonsContent(LanguageService lang) {
    final heures = List<String>.from(_p['heures_bouchons'] ?? const []);
    if (heures.isEmpty) {
      return const Text('Données insuffisantes pour prédire des pics.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ]);
  }

  Widget _fluidesContent(LanguageService lang) {
    final heures = List<String>.from(_p['heures_fluides'] ?? const []);
    if (heures.isEmpty) {
      return const Text('Aucun créneau fluide identifié pour le moment.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
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
    ]);
  }

  Widget _climatCard(LanguageService lang) {
    final climats = List<Map<String, dynamic>>.from(
        (_p['climats'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? const []);
    if (climats.isEmpty) {
      return _card(lang.t('climat_title'), Icons.cloud_outlined, AppTheme.primaryBlue,
          const Text('Climat indisponible (zones non géolocalisées ou réseau).',
              style: TextStyle(fontSize: 12, color: AppTheme.textGrey)));
    }
    return _card(lang.t('climat_title'), Icons.cloud_outlined, AppTheme.primaryBlue,
        Column(children: [
          for (var i = 0; i < climats.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlueBadge,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_climatIcon(climats[i]['code_wmo']), size: 18, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${climats[i]['libelle'] ?? climats[i]['zone']}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                    if (climats[i]['temperature_c'] != null)
                      Text('${climats[i]['temperature_c']}°C', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (climats[i]['pluie_prob'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)),
                      child: Text('💧 ${climats[i]['pluie_prob']}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                    ),
                  if (climats[i]['description'] != null && climats[i]['description'] != '')
                    Text('${climats[i]['description']}', style: const TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                ]),
              ]),
            ),
            if (i < climats.length - 1) const Divider(height: 12),
          ]
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
    if (zones.isEmpty) {
      return _card(lang.t('zones_title'), Icons.place_outlined, AppTheme.primaryBlue,
          const Text('Effectuez quelques trajets pour que l’IA apprenne vos zones.',
              style: TextStyle(fontSize: 12, color: AppTheme.textGrey)));
    }
    final maxTrajets = zones.fold<int>(1, (m, z) {
      final n = int.tryParse('${z['trajets'] ?? 0}') ?? 0;
      return n > m ? n : m;
    });
    return _card(lang.t('zones_title'), Icons.place_outlined, AppTheme.primaryBlue,
        Column(children: [
          for (final z in zones)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.location_history, size: 18, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${z['libelle']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (int.tryParse('${z['trajets'] ?? 0}') ?? 0) / maxTrajets,
                        minHeight: 5,
                        backgroundColor: AppTheme.lightBlueBorder,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.primaryBlue),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.lightBlueBadge, borderRadius: BorderRadius.circular(10)),
                  child: Text('${z['trajets']} x', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                ),
              ]),
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
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.lightbulb, size: 13, color: Colors.amber),
                ),
                const SizedBox(width: 10),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(icon, titre, couleur),
        const SizedBox(height: 10),
        contenu,
      ]),
    );
  }
}
