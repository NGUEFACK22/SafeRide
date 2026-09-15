import 'package:flutter/material.dart';
import '../data/douala_places.dart';
import '../theme/app_theme.dart';

/// Sélecteur de destination **inline** à insérer dans un dialog existant.
///
/// Contrairement à [showDestinationPickerDialog] (qui ouvre un second dialog),
/// ce widget s'incruste directement dans la `Column` du dialog SOS déjà ouvert.
/// C'est indispensable ici : le code actuel ouvre les dialogs en **série**
/// (commentaire « Un seul showDialog évite d'ouvrir un second dialog pendant
/// la transition de sortie du premier ») pour éviter l'assertion Flutter
/// `_dependents.isEmpty` (framework.dart).
///
/// Affiche **tous** les quartiers, établissements et lieux d'intérêt de Douala
/// présents sur la carte, triés par **ordre alphabétique**, sous forme de
/// liste type « todo » avec un **champ de recherche** en haut. Chaque tap
/// rappelle [onSelected] avec le nom du lieu choisi.
class InlineDestinationPicker extends StatefulWidget {
  final void Function(String name) onSelected;
  final String? initiallyFilled;

  const InlineDestinationPicker({super.key, required this.onSelected, this.initiallyFilled});

  @override
  State<InlineDestinationPicker> createState() => _InlineDestinationPickerState();
}

class _InlineDestinationPickerState extends State<InlineDestinationPicker> {
  late final TextEditingController _search;
  String _query = '';

  /// Tous les lieux, tri alphabétique (insensible à la casse/accents).
  late final List<DoualaPlace> _sorted = [...DoualaPlaces.all]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<DoualaPlace> get _filtered {
    final q = DoualaPlaces.fold(_query.trim());
    if (q.isEmpty) return _sorted;
    return _sorted
        .where((p) => DoualaPlaces.fold(p.name).contains(q) ||
            DoualaPlaces.fold(p.category).contains(q) ||
            DoualaPlaces.fold(p.ville).contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initiallyFilled ?? '');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Rechercher un quartier, un hôpital, une gare…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: AppTheme.lightBlueBadge,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 6),
        Text(
          '${_filtered.length} lieu(x) · tri alphabétique',
          style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
        ),
        const SizedBox(height: 4),
        Container(
          height: 232,
          decoration: BoxDecoration(
            color: AppTheme.lightBlueBadge,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lightBlueBorder),
          ),
          child: _filtered.isEmpty
              ? const Center(child: Text('Aucun lieu ne correspond à votre recherche.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 46),
                  itemBuilder: (context, i) {
                    final place = _filtered[i];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.lightBlueBadge,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppTheme.lightBlueBorder),
                        ),
                        child: const Icon(Icons.place_outlined, size: 16, color: AppTheme.primaryBlue),
                      ),
                      title: Text(place.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                      subtitle: Text('${place.category} • ${place.ville}', style: const TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                      onTap: () => widget.onSelected(place.name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
