import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/cards.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/pet_photo_picker.dart';
import 'adoption_requests_screen.dart';
import 'guard_dogs_screen.dart';

const petSpecies = ['dog', 'cat', 'bird', 'fish', 'rabbit', 'other'];

IconData _speciesIcon(String? species) => switch (species) {
      'dog' => Icons.pets_rounded,
      'cat' => Icons.cruelty_free_rounded,
      'bird' => Icons.flutter_dash_rounded,
      'fish' => Icons.water_rounded,
      'rabbit' => Icons.emoji_nature_rounded,
      'other' => Icons.pets_outlined,
      _ => Icons.apps_rounded,
    };

enum _AdoptionSort { featured, likes, name }

class AdoptionScreen extends StatefulWidget {
  const AdoptionScreen({super.key});

  @override
  State<AdoptionScreen> createState() => _AdoptionScreenState();
}

class _AdoptionScreenState extends State<AdoptionScreen> {
  String? _species;
  String? _gender;
  bool _vaccinatedOnly = false;
  bool _neuteredOnly = false;
  _AdoptionSort _sort = _AdoptionSort.featured;
  final _query = TextEditingController();
  String _q = '';

  bool get _hasExtraFilters =>
      _gender != null || _vaccinatedOnly || _neuteredOnly || _sort != _AdoptionSort.featured;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clearAll() {
    _query.clear();
    setState(() {
      _q = '';
      _species = null;
      _gender = null;
      _vaccinatedOnly = false;
      _neuteredOnly = false;
      _sort = _AdoptionSort.featured;
    });
  }

  List<Pet> _applyLocal(List<Pet> pets) {
    var list = pets;
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final hay = [
          p.name,
          p.breed ?? '',
          p.location ?? '',
          p.species,
          p.age ?? '',
          petAgeLabel(context, p.age),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (_gender != null) list = list.where((p) => p.gender == _gender).toList();
    if (_vaccinatedOnly) list = list.where((p) => p.vaccinated).toList();
    if (_neuteredOnly) list = list.where((p) => p.neutered).toList();
    list = [...list];
    if (_sort == _AdoptionSort.likes) {
      list.sort((a, b) => b.likes.compareTo(a.likes));
    } else if (_sort == _AdoptionSort.name) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      list.sort((a, b) {
        final ar = (a.vaccinated ? 2 : 0) + (a.neutered ? 1 : 0);
        final br = (b.vaccinated ? 2 : 0) + (b.neutered ? 1 : 0);
        final r = br.compareTo(ar);
        return r != 0 ? r : b.likes.compareTo(a.likes);
      });
    }
    return list;
  }

  Future<void> _openFilters() async {
    final applied = await showModalBottomSheet<_AdoptionFilterDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdoptionFiltersSheet(
        initial: _AdoptionFilterDraft(
          gender: _gender,
          vaccinatedOnly: _vaccinatedOnly,
          neuteredOnly: _neuteredOnly,
          sort: _sort,
        ),
      ),
    );
    if (applied != null && mounted) {
      setState(() {
        _gender = applied.gender;
        _vaccinatedOnly = applied.vaccinatedOnly;
        _neuteredOnly = applied.neuteredOnly;
        _sort = applied.sort;
      });
    }
  }

  String _sortLabel(_AdoptionSort sort) => context.t(switch (sort) {
        _AdoptionSort.featured => 'adoption_sort_featured',
        _AdoptionSort.likes => 'adoption_sort_likes',
        _AdoptionSort.name => 'adoption_sort_name',
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('adoption')),
        actions: [
          IconButton(
            tooltip: context.t('adoption_requests_title'),
            onPressed: () => context.push('/adoption-requests'),
            icon: const Icon(Icons.inbox_outlined),
          ),
          IconButton(
            tooltip: context.t('adoption_filters'),
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _hasExtraFilters,
              smallSize: 8,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      body: AsyncView<List<Pet>>(
        key: ValueKey(_species),
        loader: () => context.api.pets(status: 'for_adoption', species: _species),
        builder: (context, pets, reload) {
          final filtered = _applyLocal(pets);
          final ready = _species == null &&
                  _q.isEmpty &&
                  !_vaccinatedOnly &&
                  !_neuteredOnly &&
                  _gender == null
              ? pets.where((p) => p.vaccinated && p.neutered).take(8).toList()
              : const <Pet>[];

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _AdoptionHero()),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('adoption_search_hint'),
                    margin: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      0,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                    onClear: () => setState(() => _q = ''),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: PetsySpacing.md),
                    child: _AdoptionSpeciesSelector(
                      selected: _species,
                      onSelected: (s) => setState(() => _species = s),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _AdoptionQuickFilters(
                    gender: _gender,
                    vaccinatedOnly: _vaccinatedOnly,
                    neuteredOnly: _neuteredOnly,
                    hasExtraFilters: _hasExtraFilters,
                    onOpenFilters: _openFilters,
                    onGender: (g) => setState(() => _gender = g),
                    onToggleVaccinated: () => setState(() => _vaccinatedOnly = !_vaccinatedOnly),
                    onToggleNeutered: () => setState(() => _neuteredOnly = !_neuteredOnly),
                  ),
                ),
                if (_species != null ||
                    _gender != null ||
                    _vaccinatedOnly ||
                    _neuteredOnly ||
                    _q.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _AdoptionActiveFilters(
                      species: _species,
                      gender: _gender,
                      vaccinatedOnly: _vaccinatedOnly,
                      neuteredOnly: _neuteredOnly,
                      hasQuery: _q.isNotEmpty,
                      onClearSpecies: () => setState(() => _species = null),
                      onClearGender: () => setState(() => _gender = null),
                      onClearVaccinated: () => setState(() => _vaccinatedOnly = false),
                      onClearNeutered: () => setState(() => _neuteredOnly = false),
                      onClearQuery: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                      onClearAll: _clearAll,
                    ),
                  ),
                if (ready.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        PetsySpacing.lg,
                        PetsySpacing.page,
                        PetsySpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.t('adoption_ready'), style: PetsyType.section),
                          const SizedBox(height: 4),
                          Text(
                            context.t('adoption_ready_hint'),
                            style: PetsyType.meta.copyWith(height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 188,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                        itemCount: ready.length,
                        separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                        itemBuilder: (_, i) => _AdoptionReadyCard(pet: ready[i]),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      PetsySpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            filtered.length == 1
                                ? context.t('adoption_results_one')
                                : context.t('adoption_results').replaceAll('{count}', '${filtered.length}'),
                            style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _AdoptionSortChip(
                          label: _sortLabel(_sort),
                          active: _sort != _AdoptionSort.featured || _hasExtraFilters,
                          onTap: _openFilters,
                        ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageView(
                      icon: Icons.favorite_outline_rounded,
                      text: '${context.t('adoption_empty_title')}\n${context.t('adoption_empty_body')}',
                      action: TextButton(onPressed: _clearAll, child: Text(context.t('clear'))),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 268,
                        crossAxisSpacing: PetsySpacing.md,
                        mainAxisSpacing: PetsySpacing.md,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _AdoptionPetCard(pet: filtered[i]),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdoptionHero extends StatefulWidget {
  const _AdoptionHero();

  @override
  State<_AdoptionHero> createState() => _AdoptionHeroState();
}

class _AdoptionHeroState extends State<_AdoptionHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 0.2, -1),
                  end: Alignment(1, 1 - t * 0.15),
                  colors: const [
                    Color(0xFFC23A55),
                    Color(0xFFE45B6B),
                    Color(0xFFFF8F63),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -12,
                child: Icon(Icons.favorite_rounded, size: 120, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -22,
                bottom: -28,
                child: Icon(Icons.pets_rounded, size: 96, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                      ),
                      child: Text(
                        context.t('adoption_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('adoption_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('adoption_subtitle'),
                      style: PetsyType.meta.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _AdoptionHeroChip(icon: Icons.pets_rounded, label: context.t('dog')),
                        const SizedBox(width: 8),
                        _AdoptionHeroChip(icon: Icons.cruelty_free_rounded, label: context.t('cat')),
                        const SizedBox(width: 8),
                        _AdoptionHeroChip(icon: Icons.vaccines_rounded, label: context.t('vaccinated')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdoptionHeroChip extends StatelessWidget {
  const _AdoptionHeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionSpeciesSelector extends StatelessWidget {
  const _AdoptionSpeciesSelector({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
        itemCount: petSpecies.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _AdoptionSpeciesTile(
              icon: Icons.apps_rounded,
              label: context.t('all'),
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final s = petSpecies[i - 1];
          return _AdoptionSpeciesTile(
            icon: _speciesIcon(s),
            label: context.t(s),
            selected: selected == s,
            onTap: () => onSelected(s),
          );
        },
      ),
    );
  }
}

class _AdoptionSpeciesTile extends StatelessWidget {
  const _AdoptionSpeciesTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 86,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE45B6B), Color(0xFFFF8F63)],
                )
              : null,
          color: selected ? null : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: selected ? Colors.transparent : PetsyColors.border),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFFFF0F2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? Colors.white : const Color(0xFFC23A55), size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : PetsyColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionQuickFilters extends StatelessWidget {
  const _AdoptionQuickFilters({
    required this.gender,
    required this.vaccinatedOnly,
    required this.neuteredOnly,
    required this.hasExtraFilters,
    required this.onOpenFilters,
    required this.onGender,
    required this.onToggleVaccinated,
    required this.onToggleNeutered,
  });

  final String? gender;
  final bool vaccinatedOnly;
  final bool neuteredOnly;
  final bool hasExtraFilters;
  final VoidCallback onOpenFilters;
  final ValueChanged<String?> onGender;
  final VoidCallback onToggleVaccinated;
  final VoidCallback onToggleNeutered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: PetsySpacing.md),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
          children: [
            _AdoptionQuickChip(
              icon: Icons.tune_rounded,
              label: context.t('adoption_filters'),
              selected: hasExtraFilters,
              emphasize: true,
              onTap: onOpenFilters,
            ),
            const SizedBox(width: 8),
            _AdoptionQuickChip(
              icon: Icons.vaccines_rounded,
              label: context.t('vaccinated'),
              selected: vaccinatedOnly,
              onTap: onToggleVaccinated,
            ),
            const SizedBox(width: 8),
            _AdoptionQuickChip(
              icon: Icons.health_and_safety_outlined,
              label: context.t('neutered'),
              selected: neuteredOnly,
              onTap: onToggleNeutered,
            ),
            const SizedBox(width: 8),
            _AdoptionQuickChip(
              icon: Icons.male_rounded,
              label: context.t('male'),
              selected: gender == 'male',
              onTap: () => onGender(gender == 'male' ? null : 'male'),
            ),
            const SizedBox(width: 8),
            _AdoptionQuickChip(
              icon: Icons.female_rounded,
              label: context.t('female'),
              selected: gender == 'female',
              onTap: () => onGender(gender == 'female' ? null : 'female'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionQuickChip extends StatelessWidget {
  const _AdoptionQuickChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFE45B6B);
    final bg = selected
        ? accent
        : emphasize
            ? const Color(0xFFFFF0F2)
            : PetsyColors.surface;
    final fg = selected ? Colors.white : PetsyColors.text;
    final iconColor = selected ? Colors.white : const Color(0xFFC23A55);
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? accent
                : emphasize
                    ? accent.withValues(alpha: 0.28)
                    : PetsyColors.border,
          ),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _AdoptionSortChip extends StatelessWidget {
  const _AdoptionSortChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF0F2) : PetsyColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? const Color(0xFFE45B6B).withValues(alpha: 0.35) : PetsyColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 15, color: Color(0xFFC23A55)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: PetsyColors.text),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: PetsyColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AdoptionActiveFilters extends StatelessWidget {
  const _AdoptionActiveFilters({
    required this.species,
    required this.gender,
    required this.vaccinatedOnly,
    required this.neuteredOnly,
    required this.hasQuery,
    required this.onClearSpecies,
    required this.onClearGender,
    required this.onClearVaccinated,
    required this.onClearNeutered,
    required this.onClearQuery,
    required this.onClearAll,
  });

  final String? species;
  final String? gender;
  final bool vaccinatedOnly;
  final bool neuteredOnly;
  final bool hasQuery;
  final VoidCallback onClearSpecies;
  final VoidCallback onClearGender;
  final VoidCallback onClearVaccinated;
  final VoidCallback onClearNeutered;
  final VoidCallback onClearQuery;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: Row(
        children: [
          if (species != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AdoptionFilterChip(
                icon: _speciesIcon(species),
                label: context.t(species!),
                onDeleted: onClearSpecies,
              ),
            ),
          if (gender != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AdoptionFilterChip(
                icon: gender == 'female' ? Icons.female_rounded : Icons.male_rounded,
                label: context.t(gender!),
                onDeleted: onClearGender,
              ),
            ),
          if (vaccinatedOnly)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AdoptionFilterChip(
                icon: Icons.vaccines_rounded,
                label: context.t('adoption_vaccinated_only'),
                onDeleted: onClearVaccinated,
              ),
            ),
          if (neuteredOnly)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AdoptionFilterChip(
                icon: Icons.health_and_safety_outlined,
                label: context.t('adoption_neutered_only'),
                onDeleted: onClearNeutered,
              ),
            ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AdoptionFilterChip(
                icon: Icons.search_rounded,
                label: context.t('guard_dogs_search_active'),
                onDeleted: onClearQuery,
              ),
            ),
          PetsyPressScale(
            onTap: onClearAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: PetsyColors.shellWash,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: PetsyColors.border),
              ),
              child: Text(
                context.t('clear_all'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: PetsyColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdoptionFilterChip extends StatelessWidget {
  const _AdoptionFilterChip({
    required this.label,
    required this.onDeleted,
    this.icon,
  });

  final String label;
  final VoidCallback onDeleted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC23A55);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F2),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: accent),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(99),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 15, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdoptionReadyCard extends StatelessWidget {
  const _AdoptionReadyCard({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final meta = joinIsolated([
      pet.breed ?? context.t(pet.species),
      if (pet.age != null && pet.age!.trim().isNotEmpty) petAgeLabel(context, pet.age),
    ]);
    return PetsyPressScale(
      onTap: () => context.push('/pet/${pet.id}'),
      child: Container(
        width: 148,
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(pet.image),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: PetsyMetaBadge(
                      label: context.t('adoption_ready'),
                      tone: PetsyMetaTone.accent,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PetsyType.cardTitle.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: PetsyType.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionFilterDraft {
  const _AdoptionFilterDraft({
    required this.gender,
    required this.vaccinatedOnly,
    required this.neuteredOnly,
    required this.sort,
  });

  final String? gender;
  final bool vaccinatedOnly;
  final bool neuteredOnly;
  final _AdoptionSort sort;
}

class _AdoptionFiltersSheet extends StatefulWidget {
  const _AdoptionFiltersSheet({required this.initial});

  final _AdoptionFilterDraft initial;

  @override
  State<_AdoptionFiltersSheet> createState() => _AdoptionFiltersSheetState();
}

class _AdoptionFiltersSheetState extends State<_AdoptionFiltersSheet> {
  late String? _gender = widget.initial.gender;
  late bool _vaccinatedOnly = widget.initial.vaccinatedOnly;
  late bool _neuteredOnly = widget.initial.neuteredOnly;
  late _AdoptionSort _sort = widget.initial.sort;

  int get _activeCount {
    var n = 0;
    if (_gender != null) n++;
    if (_vaccinatedOnly) n++;
    if (_neuteredOnly) n++;
    if (_sort != _AdoptionSort.featured) n++;
    return n;
  }

  void _reset() {
    setState(() {
      _gender = null;
      _vaccinatedOnly = false;
      _neuteredOnly = false;
      _sort = _AdoptionSort.featured;
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: PetsyColors.backgroundAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PetsyColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.lg,
                      PetsySpacing.page,
                      PetsySpacing.md,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F2),
                            borderRadius: BorderRadius.circular(PetsyRadius.md),
                          ),
                          child: const Icon(Icons.favorite_rounded, color: Color(0xFFC23A55)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(context.t('adoption_filters'), style: PetsyType.section),
                        ),
                        if (_activeCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE45B6B),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '$_activeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        0,
                        PetsySpacing.page,
                        PetsySpacing.md,
                      ),
                      child: Column(
                        children: [
                          _AdoptionFilterSection(
                            title: context.t('gender'),
                            icon: Icons.wc_rounded,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _AdoptionChoiceTile(
                                    icon: Icons.apps_rounded,
                                    label: context.t('all'),
                                    selected: _gender == null,
                                    onTap: () => setState(() => _gender = null),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _AdoptionChoiceTile(
                                    icon: Icons.male_rounded,
                                    label: context.t('male'),
                                    selected: _gender == 'male',
                                    onTap: () => setState(() => _gender = 'male'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _AdoptionChoiceTile(
                                    icon: Icons.female_rounded,
                                    label: context.t('female'),
                                    selected: _gender == 'female',
                                    onTap: () => setState(() => _gender = 'female'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: PetsySpacing.md),
                          _AdoptionFilterSection(
                            title: context.t('adoption_sort'),
                            icon: Icons.sort_rounded,
                            child: Column(
                              children: [
                                for (final s in _AdoptionSort.values) ...[
                                  if (s != _AdoptionSort.values.first) const SizedBox(height: 8),
                                  _AdoptionSortOption(
                                    label: context.t(switch (s) {
                                      _AdoptionSort.featured => 'adoption_sort_featured',
                                      _AdoptionSort.likes => 'adoption_sort_likes',
                                      _AdoptionSort.name => 'adoption_sort_name',
                                    }),
                                    icon: switch (s) {
                                      _AdoptionSort.featured => Icons.auto_awesome_rounded,
                                      _AdoptionSort.likes => Icons.favorite_rounded,
                                      _AdoptionSort.name => Icons.sort_by_alpha_rounded,
                                    },
                                    selected: _sort == s,
                                    onTap: () => setState(() => _sort = s),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: PetsySpacing.md),
                          _AdoptionFilterSection(
                            title: context.t('adoption_quick_health'),
                            icon: Icons.health_and_safety_outlined,
                            child: Column(
                              children: [
                                _AdoptionToggleCard(
                                  icon: Icons.vaccines_rounded,
                                  title: context.t('adoption_vaccinated_only'),
                                  value: _vaccinatedOnly,
                                  onChanged: (v) => setState(() => _vaccinatedOnly = v),
                                ),
                                const SizedBox(height: 8),
                                _AdoptionToggleCard(
                                  icon: Icons.health_and_safety_outlined,
                                  title: context.t('adoption_neutered_only'),
                                  value: _neuteredOnly,
                                  onChanged: (v) => setState(() => _neuteredOnly = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      PetsySpacing.page,
                    ),
                    decoration: BoxDecoration(
                      color: PetsyColors.surface,
                      border: Border(top: BorderSide(color: PetsyColors.border.withValues(alpha: 0.8))),
                      boxShadow: PetsyShadows.soft,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reset,
                            child: Text(context.t('clear')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE45B6B)),
                            onPressed: () => Navigator.pop(
                              context,
                              _AdoptionFilterDraft(
                                gender: _gender,
                                vaccinatedOnly: _vaccinatedOnly,
                                neuteredOnly: _neuteredOnly,
                                sort: _sort,
                              ),
                            ),
                            child: Text(context.t('guard_filters_apply')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdoptionFilterSection extends StatelessWidget {
  const _AdoptionFilterSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFFC23A55)),
              const SizedBox(width: 7),
              Text(
                title,
                style: PetsyType.meta.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PetsyColors.text,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AdoptionChoiceTile extends StatelessWidget {
  const _AdoptionChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F2) : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: selected ? const Color(0xFFE45B6B) : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? const Color(0xFFC23A55) : PetsyColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: selected ? const Color(0xFFC23A55) : PetsyColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionSortOption extends StatelessWidget {
  const _AdoptionSortOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F2) : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: selected ? const Color(0xFFE45B6B) : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE45B6B) : PetsyColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: selected ? Colors.white : const Color(0xFFC23A55)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: selected ? const Color(0xFFC23A55) : PetsyColors.text,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected ? const Color(0xFFE45B6B) : PetsyColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionToggleCard extends StatelessWidget {
  const _AdoptionToggleCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE45B6B);
    return PetsyPressScale(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFFFF0F2) : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: value ? accent.withValues(alpha: 0.55) : PetsyColors.border,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value ? accent : PetsyColors.surface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: value ? Colors.white : const Color(0xFFC23A55)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: value ? const Color(0xFFC23A55) : PetsyColors.text,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool? _products;

  Future<(List<Pet>, List<Product>)> _load() async {
    final api = context.api;
    final results = await Future.wait([api.favoritePets(), api.favoriteProducts()]);
    return (results[0] as List<Pet>, results[1] as List<Product>);
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('favorites_title'))),
      child: AsyncView<(List<Pet>, List<Product>)>(
        loader: _load,
        builder: (context, data, reload) {
          final (pets, products) = data;
          final showProducts = _products ??= pets.isEmpty && products.isNotEmpty;
          final count = showProducts ? products.length : pets.length;
          final total = pets.length + products.length;

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _FavoritesHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _FavoritesStatsRow(
                      pets: pets.length,
                      products: products.length,
                      total: total,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: PetsyColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: PetsyColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _FavoritesTab(
                              label: context.t('favorites_tab_pets'),
                              icon: Icons.pets_rounded,
                              count: pets.length,
                              selected: !showProducts,
                              onTap: () => setState(() => _products = false),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _FavoritesTab(
                              label: context.t('favorites_tab_products'),
                              icon: Icons.shopping_bag_outlined,
                              count: products.length,
                              selected: showProducts,
                              onTap: () => setState(() => _products = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (count == 0)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        8,
                        PetsySpacing.page,
                        PetsySpacing.listBottom,
                      ),
                      child: _FavoritesEmptyState(showProducts: showProducts),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      4,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: showProducts ? 250 : 268,
                        crossAxisSpacing: PetsySpacing.md,
                        mainAxisSpacing: PetsySpacing.md,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => showProducts
                            ? ProductCard(
                                product: products[i],
                                onReturn: reload,
                                onAdd: products[i].inStock
                                    ? () {
                                        context.read<CartState>().add(products[i]);
                                        context.snack(
                                          context.t('added_to_cart'),
                                          success: true,
                                          icon: Icons.shopping_bag_outlined,
                                        );
                                      }
                                    : null,
                              )
                            : _AdoptionPetCard(pet: pets[i], onReturn: reload),
                        childCount: count,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FavoritesHero extends StatefulWidget {
  const _FavoritesHero();

  @override
  State<_FavoritesHero> createState() => _FavoritesHeroState();
}

class _FavoritesHeroState extends State<_FavoritesHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 0.2, -1),
                  end: Alignment(1, 1 - t * 0.15),
                  colors: const [
                    Color(0xFFC23A55),
                    PetsyColors.primary,
                    PetsyColors.secondary,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -10,
                child: Icon(Icons.favorite_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -16,
                bottom: -22,
                child: Icon(Icons.pets_rounded, size: 86, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                      ),
                      child: Text(
                        context.t('favorites_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('favorites_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('favorites_subtitle'),
                      style: PetsyType.meta.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesStatsRow extends StatelessWidget {
  const _FavoritesStatsRow({
    required this.pets,
    required this.products,
    required this.total,
  });

  final int pets;
  final int products;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FavoritesStatTile(
            icon: Icons.favorite_rounded,
            label: context.t('favorites_stat_total').replaceAll('{count}', '$total'),
            color: const Color(0xFFC23A55),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FavoritesStatTile(
            icon: Icons.pets_rounded,
            label: context.t('favorites_stat_pets').replaceAll('{count}', '$pets'),
            color: PetsyColors.primaryDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FavoritesStatTile(
            icon: Icons.shopping_bag_outlined,
            label: context.t('favorites_stat_products').replaceAll('{count}', '$products'),
            color: PetsyColors.accent,
          ),
        ),
      ],
    );
  }
}

class _FavoritesStatTile extends StatelessWidget {
  const _FavoritesStatTile({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : PetsyColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: selected ? Colors.white : PetsyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.2) : PetsyColors.mist,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  color: selected ? Colors.white : PetsyColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState({required this.showProducts});

  final bool showProducts;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC23A55).withValues(alpha: 0.18)),
              ),
              child: Icon(
                showProducts ? Icons.shopping_bag_outlined : Icons.favorite_border_rounded,
                size: 36,
                color: const Color(0xFFC23A55),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t(showProducts ? 'favorites_empty_products_title' : 'favorites_empty_title'),
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              context.t(showProducts ? 'favorites_empty_products_body' : 'favorites_empty_body'),
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go(showProducts ? '/shop' : '/adoption'),
                icon: Icon(showProducts ? Icons.storefront_rounded : Icons.pets_rounded),
                label: Text(context.t(showProducts ? 'favorites_browse_shop' : 'favorites_browse')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionPetCard extends StatefulWidget {
  const _AdoptionPetCard({required this.pet, this.onReturn});

  final Pet pet;

  /// Called after coming back from the pet's page, e.g. to drop an unliked favorite.
  final Future<void> Function()? onReturn;

  @override
  State<_AdoptionPetCard> createState() => _AdoptionPetCardState();
}

class _AdoptionPetCardState extends State<_AdoptionPetCard> {
  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    final meta = joinIsolated([
      pet.breed ?? context.t(pet.species),
      if (pet.age != null && pet.age!.trim().isNotEmpty) petAgeLabel(context, pet.age),
    ]);

    return PetsyPressScale(
      onTap: () async {
        await context.push('/pet/${pet.id}');
        await widget.onReturn?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.raised,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(pet.image),
                  PositionedDirectional(
                    top: PetsySpacing.sm,
                    end: PetsySpacing.sm,
                    child: PetsyMetaBadge(
                      label: pet.status == 'for_adoption' ? context.t('adoption_badge') : context.t(pet.status),
                      tone: switch (pet.status) {
                        'for_adoption' || 'for_sale' => PetsyMetaTone.primary,
                        'adopted' => PetsyMetaTone.accent,
                        _ => PetsyMetaTone.neutral,
                      },
                    ),
                  ),
                  PositionedDirectional(
                    top: PetsySpacing.sm,
                    start: PetsySpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: PetsyColors.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Icon(
                        pet.gender == 'female' ? Icons.female_rounded : Icons.male_rounded,
                        size: 14,
                        color: pet.gender == 'female' ? PetsyColors.genderFemale : PetsyColors.genderMale,
                      ),
                    ),
                  ),
                  if (pet.vaccinated || pet.neutered)
                    PositionedDirectional(
                      bottom: PetsySpacing.sm,
                      start: PetsySpacing.sm,
                      child: Row(
                        children: [
                          if (pet.vaccinated)
                            PetsyMetaBadge(
                              label: context.t('vaccinated'),
                              icon: Icons.vaccines_rounded,
                              tone: PetsyMetaTone.accent,
                            ),
                          if (pet.vaccinated && pet.neutered) const SizedBox(width: 4),
                          if (pet.neutered)
                            PetsyMetaBadge(
                              label: context.t('neutered'),
                              icon: Icons.health_and_safety_outlined,
                              tone: PetsyMetaTone.primary,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                PetsySpacing.md,
                PetsySpacing.sm + 2,
                PetsySpacing.md,
                PetsySpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PetsyType.cardTitle,
                  ),
                  const SizedBox(height: PetsySpacing.xs / 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: PetsyType.meta),
                  if (pet.location != null && pet.location!.isNotEmpty) ...[
                    const SizedBox(height: PetsySpacing.sm - 2),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14, color: Color(0xFFE45B6B)),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            pet.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.meta,
                          ),
                        ),
                        const PetsyChevron.forward(size: 11, color: Color(0xFFC23A55)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PetDetailScreen extends StatefulWidget {
  const PetDetailScreen({super.key, required this.petId});

  final String petId;

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  bool _contacting = false;
  bool _liking = false;
  bool? _liked;
  int? _likes;

  Future<void> _contactOwner(BuildContext context, Pet pet) async {
    if (!context.requireLogin() || _contacting) return;
    setState(() => _contacting = true);
    try {
      final conversationId = await context.api.startConversation(
        otherUserId: pet.ownerId,
        petId: pet.id,
        message: '${context.t('hello_about_pet')} ${pet.name}',
      );
      if (context.mounted) context.push('/chat/$conversationId');
    } catch (e) {
      if (context.mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  Future<void> _like(Pet pet, bool wasLiked) async {
    if (!context.requireLogin() || _liking) return;
    final likes = _likes ?? pet.likes;
    setState(() {
      _liking = true;
      _liked = !wasLiked;
      _likes = likes + (wasLiked ? -1 : 1);
    });
    try {
      final liked = await context.api.likePet(pet.id);
      if (!mounted) return;
      if (liked == wasLiked) {
        setState(() {
          _liked = liked;
          _likes = likes;
        });
      }
      context.snack(
        context.t(liked ? 'favorite_added' : 'favorite_removed'),
        success: liked,
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likes = likes;
        });
        context.snack(context.errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _share(Pet pet) async {
    final text = '${pet.name} · ${context.t(pet.status)}\n'
        '${pet.breed ?? context.t(pet.species)}'
        '${pet.location != null && pet.location!.isNotEmpty ? ' · ${pet.location}' : ''}\n'
        'Petsy';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<_PetDetailData> _load(String? userId) async {
    final api = context.api;
    final likedFuture = userId == null ? Future.value(false) : api.isPetLiked(widget.petId);
    final pet = await api.pet(widget.petId);
    _likes = null;
    _liked = null;
    if (userId == null || (pet.status != 'for_adoption' && pet.status != 'adopted')) {
      return _PetDetailData(pet, liked: await likedFuture);
    }
    if (pet.ownerId == userId) {
      final incoming = await api.adoptionRequests('incoming');
      return _PetDetailData(
        pet,
        liked: await likedFuture,
        pendingRequests: incoming.where((r) => r.petId == pet.id && r.isPending).length,
      );
    }
    final request = await api.myAdoptionRequest(pet.id);
    return _PetDetailData(pet, liked: await likedFuture, myRequest: request);
  }

  Future<void> _requestAdoption(Pet pet, Future<void> Function() reload) async {
    if (!context.requireLogin()) return;
    if (!await showAdoptionRequestSheet(context, pet) || !mounted) return;
    context.snack(context.t('adoption_sent_snack'));
    await reload();
  }

  Future<void> _withdraw(AdoptionRequest request, Future<void> Function() reload) async {
    final ok = await confirmAction(
      context,
      title: context.t('adoption_withdraw_title'),
      message: context.t('adoption_withdraw_message'),
      confirmLabel: context.t('adoption_withdraw'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.updateAdoptionRequest(request.id, 'withdraw');
      if (!mounted) return;
      context.snack(context.t('adoption_withdrawn_snack'));
      await reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Widget _adoptionBar(Pet pet, AdoptionRequest? request, Future<void> Function() reload) {
    final chat = _contacting
        ? null
        : () async {
            setState(() => _contacting = true);
            await openAdoptionChat(context, otherUserId: pet.ownerId, petId: pet.id, petName: pet.name);
            if (mounted) setState(() => _contacting = false);
          };
    if (request?.status == 'accepted') {
      return FilledButton.icon(
        onPressed: chat,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(context.t('adoption_message_owner')),
      );
    }
    if (pet.status == 'adopted') {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.home_rounded),
        label: Text(context.t('adopted')),
      );
    }
    if (request != null && request.isPending) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: () => _withdraw(request, reload), child: Text(context.t('adoption_withdraw'))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: chat,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(context.t('adoption_message_owner')),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: chat == null
                ? null
                : () {
                    if (context.requireLogin()) chat();
                  },
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(context.t('adoption_ask_owner')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _requestAdoption(pet, reload),
            icon: const Icon(Icons.favorite_rounded),
            label: Text(context.t('adoption_request_cta')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthState>().user?.id;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      body: AsyncView<_PetDetailData>(
        loader: () => _load(userId),
        builder: (context, data, reload) {
          final pet = data.pet;
          final request = data.myRequest;
          final isOwner = pet.ownerId == userId;
          final isAdoption = pet.status == 'for_adoption';
          final isSale = pet.status == 'for_sale';
          final inAdoptionFlow = isAdoption || pet.status == 'adopted';
          final likes = _likes ?? pet.likes;
          final liked = _liked ?? data.liked;
          final facts = <(IconData, String, String)>[
            (Icons.pets_rounded, context.t('species'), context.t(pet.species)),
            (
              pet.gender == 'female' ? Icons.female_rounded : Icons.male_rounded,
              context.t('gender'),
              context.t(pet.gender),
            ),
            if (pet.age != null && pet.age!.trim().isNotEmpty)
              (Icons.cake_outlined, context.t('age'), petAgeLabel(context, pet.age)),
            if (pet.breed != null && pet.breed!.trim().isNotEmpty)
              (Icons.category_outlined, context.t('breed'), pet.breed!.trim()),
            if (pet.isGuardDog)
              (
                Icons.security_rounded,
                context.t('guard_role_label'),
                context.t(
                  pet.guardRole != null && pet.guardRole!.isNotEmpty
                      ? 'guard_role_${pet.guardRole}'
                      : 'purpose_guard',
                ),
              ),
            if (pet.isGuardDog && pet.sellerType != null && pet.sellerType!.isNotEmpty)
              (Icons.storefront_outlined, context.t('seller_type_label'), context.t('seller_${pet.sellerType}')),
            if (pet.country != null && pet.country!.isNotEmpty)
              (Icons.public_rounded, context.t('country_label'), context.t('country_${pet.country}')),
            if (pet.color != null && pet.color!.trim().isNotEmpty)
              (Icons.palette_outlined, context.t('color'), pet.color!.trim()),
            if (pet.weight != null)
              (Icons.monitor_weight_outlined, context.t('weight'), pet.weight!.toStringAsFixed(1)),
          ];

          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 340,
                      pinned: true,
                      backgroundColor: PetsyColors.background,
                      leading: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.92),
                        ),
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      ),
                      actions: [
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.92),
                          ),
                          tooltip: context.t('pet_share'),
                          onPressed: () => _share(pet),
                          icon: const Icon(Icons.ios_share_rounded),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.92),
                          ),
                          tooltip: context.t(liked ? 'favorite_remove' : 'favorite_add'),
                          onPressed: _liking ? null : () => _like(pet, liked),
                          icon: Icon(
                            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: PetsyColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetImage(pet.image),
                            if ((pet.image ?? '').isNotEmpty)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x33000000),
                                    Color(0x00000000),
                                    Color(0x66000000),
                                  ],
                                  stops: [0, 0.45, 1],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 18,
                              child: Row(
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: StatusChip(pet.status),
                                  ),
                                  if (pet.isGuardDog) ...[
                                    const SizedBox(width: 8),
                                    PetsyMetaBadge(
                                      label: context.t('guard_dog_badge'),
                                      tone: PetsyMetaTone.accent,
                                    ),
                                  ],
                                  const Spacer(),
                                  if (likes > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.92),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        context.t('pet_likes').replaceAll('{count}', '$likes'),
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pet.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
                            if (pet.location != null && pet.location!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.place_outlined, size: 18, color: PetsyColors.primary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      pet.location!,
                                      style: const TextStyle(
                                        color: PetsyColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (pet.price != null && pet.status == 'for_sale') ...[
                              const SizedBox(height: 10),
                              Text(
                                formatPrice(pet.price!, currency: pet.currency),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: PetsyColors.primary,
                                ),
                              ),
                            ],
                            if (pet.isGuardDog) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  PetsyMetaBadge(
                                    label: context.t(
                                      pet.guardRole != null && pet.guardRole!.isNotEmpty
                                          ? 'guard_role_${pet.guardRole}'
                                          : 'guard_dog_badge',
                                    ),
                                    tone: PetsyMetaTone.accent,
                                  ),
                                  if (pet.sellerType != null && pet.sellerType!.isNotEmpty)
                                    PetsyMetaBadge(
                                      label: context.t('seller_${pet.sellerType}'),
                                      tone: PetsyMetaTone.primary,
                                    ),
                                  if (pet.country != null && pet.country!.isNotEmpty)
                                    PetsyMetaBadge(
                                      label: context.t('country_${pet.country}'),
                                      tone: PetsyMetaTone.neutral,
                                    ),
                                ],
                              ),
                            ],
                            if (inAdoptionFlow && !isOwner) ...[
                              const SizedBox(height: 14),
                              _AdoptionStatusBanner(pet: pet, request: request),
                            ],
                            if (inAdoptionFlow && isOwner && data.pendingRequests != null) ...[
                              const SizedBox(height: 14),
                              _OwnerActionTile(
                                icon: Icons.volunteer_activism_rounded,
                                color: PetsyColors.primaryDark,
                                soft: PetsyColors.primarySoft,
                                label: data.pendingRequests! > 0
                                    ? context.t('adoption_requests_count').replaceAll('{count}', '${data.pendingRequests}')
                                    : context.t('adoption_requests_title'),
                                onTap: () async {
                                  await context.push('/adoption-requests?tab=incoming');
                                  if (mounted) reload();
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            Text(
                              context.t('pet_details_section'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            for (var i = 0; i < facts.length; i += 2) ...[
                              if (i > 0) const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _FactTile(icon: facts[i].$1, label: facts[i].$2, value: facts[i].$3)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: i + 1 < facts.length
                                        ? _FactTile(icon: facts[i + 1].$1, label: facts[i + 1].$2, value: facts[i + 1].$3)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                            Text(
                              context.t('pet_care_section'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _CareStatusTile(
                                    icon: Icons.vaccines_rounded,
                                    label: context.t(pet.vaccinated ? 'vaccinated' : 'pet_not_vaccinated'),
                                    ok: pet.vaccinated,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CareStatusTile(
                                    icon: Icons.health_and_safety_outlined,
                                    label: context.t(pet.neutered ? 'neutered' : 'pet_not_neutered'),
                                    ok: pet.neutered,
                                  ),
                                ),
                              ],
                            ),
                            if (pet.description != null && pet.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(
                                context.t('pet_about'),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: PetsyColors.surface,
                                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                                  border: Border.all(color: PetsyColors.border),
                                ),
                                child: Text(
                                  pet.description!,
                                  style: const TextStyle(height: 1.55, color: PetsyColors.text, fontSize: 14.5),
                                ),
                              ),
                            ],
                            if (isOwner) ...[
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                onPressed: () {
                                  if (!context.requireLogin()) return;
                                  context.push('/vets?petId=${pet.id}');
                                },
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text('${context.t('book_for_pet')} ${pet.name}'),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _OwnerActionTile(
                                      icon: Icons.health_and_safety_outlined,
                                      color: PetsyColors.accent,
                                      soft: PetsyColors.accentSoft,
                                      label: context.t('health_records'),
                                      onTap: () => context.push(
                                        '/pet-health/${pet.id}?name=${Uri.encodeComponent(pet.name)}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _OwnerActionTile(
                                      icon: Icons.edit_outlined,
                                      color: PetsyColors.primaryDark,
                                      soft: PetsyColors.primarySoft,
                                      label: context.t('edit_pet'),
                                      onTap: () async {
                                        final updated = await context.push<bool>('/edit-pet/${pet.id}');
                                        if (updated == true && context.mounted) reload();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            SizedBox(height: isOwner ? 12 : 88),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOwner && inAdoptionFlow)
                BottomActionBar(child: _adoptionBar(pet, request, reload))
              else if (!isOwner)
                BottomActionBar(
                  child: FilledButton.icon(
                    onPressed: _contacting ? null : () => _contactOwner(context, pet),
                    icon: _contacting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            isAdoption
                                ? Icons.favorite_rounded
                                : isSale
                                    ? Icons.storefront_rounded
                                    : Icons.chat_bubble_outline_rounded,
                          ),
                    label: Text(
                      isAdoption
                          ? context.t('pet_adopt_cta')
                          : isSale
                              ? context.t('contact_seller')
                              : context.t('contact_owner'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PetDetailData {
  const _PetDetailData(this.pet, {this.liked = false, this.myRequest, this.pendingRequests});

  final Pet pet;
  final bool liked;
  final AdoptionRequest? myRequest;

  /// Pending adoption requests for the owner's pet; null for visitors.
  final int? pendingRequests;
}

/// Tells a visitor where they stand on an adoption pet.
class _AdoptionStatusBanner extends StatelessWidget {
  const _AdoptionStatusBanner({required this.pet, this.request});

  final Pet pet;
  final AdoptionRequest? request;

  @override
  Widget build(BuildContext context) {
    final status = request?.status;
    final (IconData icon, Color color, Color soft, String? title, String body) = switch (status) {
      'pending' => (
          Icons.hourglass_top_rounded,
          PetsyColors.warning,
          PetsyColors.warning.withValues(alpha: 0.1),
          context.t('adoption_status_pending_title'),
          context.t('adoption_status_pending_body'),
        ),
      'accepted' => (
          Icons.celebration_rounded,
          PetsyColors.success,
          PetsyColors.success.withValues(alpha: 0.1),
          context.t('adoption_status_accepted_title'),
          context.t('adoption_status_accepted_body'),
        ),
      'declined' => (
          Icons.info_outline_rounded,
          PetsyColors.textSecondary,
          PetsyColors.backgroundAlt,
          context.t('adoption_status_declined_title'),
          request?.closedReason == 'adopted'
              ? context.t('adoption_status_closed_body').replaceAll('{pet}', pet.name)
              : context.t('adoption_status_declined_body'),
        ),
      _ when pet.status == 'adopted' => (
          Icons.home_rounded,
          PetsyColors.accent,
          PetsyColors.accentSoft,
          context.t('adoption_pet_adopted_title').replaceAll('{pet}', pet.name),
          context.t('adoption_pet_adopted_body'),
        ),
      _ => (
          Icons.volunteer_activism_rounded,
          PetsyColors.primaryDark,
          PetsyColors.primarySoft,
          null,
          context.t('pet_adopt_hint'),
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                ],
                Text(
                  body,
                  style: TextStyle(
                    color: title == null ? color : PetsyColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerActionTile extends StatelessWidget {
  const _OwnerActionTile({
    required this.icon,
    required this.color,
    required this.soft,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PetsyColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: PetsyColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: Bidi.hasAnyRtl(value) ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PetsyColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CareStatusTile extends StatelessWidget {
  const _CareStatusTile({
    required this.icon,
    required this.label,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? PetsyColors.accent : PetsyColors.textSecondary;
    final soft = ok ? PetsyColors.accentSoft : PetsyColors.mist;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class MyPetsScreen extends StatefulWidget {
  const MyPetsScreen({super.key});

  @override
  State<MyPetsScreen> createState() => _MyPetsScreenState();
}

class _MyPetsScreenState extends State<MyPetsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Pet>>>();
  final _query = TextEditingController();
  String _q = '';
  String? _species;
  String? _status; // null = all

  static const _statuses = ['owned', 'for_adoption', 'for_sale'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _addPet() async {
    final added = await context.push<bool>('/add-pet');
    if (added == true) _view.currentState?.reload();
  }

  Future<void> _openEdit(Pet pet) async {
    final updated = await context.push<bool>('/edit-pet/${pet.id}');
    if (updated == true) _view.currentState?.reload();
  }

  List<Pet> _filter(List<Pet> pets) {
    Iterable<Pet> list = pets;
    if (_species != null) list = list.where((p) => p.species == _species);
    if (_status != null) list = list.where((p) => p.status == _status);
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final hay = [
          p.name,
          p.breed ?? '',
          p.species,
          p.status,
          p.age ?? '',
          petAgeLabel(context, p.age),
          p.location ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(q);
      });
    }
    return list.toList();
  }

  bool _needsDetails(Pet pet) =>
      (pet.image == null || pet.image!.isEmpty) ||
      (pet.age == null || pet.age!.isEmpty) ||
      !pet.vaccinated;

  void _clearFilters() {
    _query.clear();
    setState(() {
      _q = '';
      _species = null;
      _status = null;
    });
  }

  Future<void> _openFilters() async {
    var draftSpecies = _species;
    var draftStatus = _status;
    final applied = await showPetsyFiltersSheet(
      context: context,
      title: context.t('filters'),
      onReset: () {
        draftSpecies = null;
        draftStatus = null;
      },
      body: (ctx, setModal) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetsyChoiceField<String>(
            label: context.t('species'),
            prefixIcon: Icons.pets_rounded,
            value: draftSpecies ?? '__all__',
            options: [
              PetsyChoiceOption(value: '__all__', label: context.t('all'), icon: Icons.apps_rounded),
              for (final s in petSpecies)
                PetsyChoiceOption(value: s, label: context.t(s), icon: _speciesIcon(s)),
            ],
            onChanged: (v) => setModal(() => draftSpecies = v == '__all__' ? null : v),
          ),
          const SizedBox(height: 12),
          PetsyChoiceField<String>(
            label: context.t('status'),
            prefixIcon: Icons.flag_outlined,
            value: draftStatus ?? '__all__',
            options: [
              PetsyChoiceOption(value: '__all__', label: context.t('my_pets_status_all'), icon: Icons.apps_rounded),
              for (final s in _statuses)
                PetsyChoiceOption(value: s, label: context.t(s), icon: Icons.label_outline_rounded),
            ],
            onChanged: (v) => setModal(() => draftStatus = v == '__all__' ? null : v),
          ),
        ],
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _species = draftSpecies;
        _status = draftStatus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('my_pets'))),
      floatingActionButton: PetsyFab(
        heroTag: 'my-pets-fab',
        icon: Icons.add_rounded,
        label: context.t('add_pet'),
        onPressed: _addPet,
      ),
      child: AsyncView<List<Pet>>(
        key: _view,
        loader: context.api.myPets,
        builder: (context, pets, reload) {
          final visible = _filter(pets);
          final incomplete = pets.where(_needsDetails).length;
          final vaccinated = pets.where((p) => p.vaccinated).length;
          final countLabel = visible.length == 1
              ? context.t('my_pets_count_one')
              : context.t('my_pets_count').replaceAll('{count}', '${visible.length}');
          final activeFilterCount = (_species != null ? 1 : 0) + (_status != null ? 1 : 0);

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _MyPetsHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _MyPetsStatsRow(
                      totalLabel: pets.isEmpty
                          ? context.t('my_pets_count').replaceAll('{count}', '0')
                          : (pets.length == 1
                              ? context.t('my_pets_count_one')
                              : context.t('my_pets_count').replaceAll('{count}', '${pets.length}')),
                      incompleteLabel: context.t('my_pets_stat_incomplete').replaceAll('{count}', '$incomplete'),
                      vaccinatedLabel: context.t('my_pets_stat_vaccinated').replaceAll('{count}', '$vaccinated'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('my_pets_search_hint'),
                    margin: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    onChanged: (v) => setState(() => _q = v),
                    onClear: () => setState(() => _q = ''),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsyFilterBar(
                    onOpen: _openFilters,
                    activeCount: activeFilterCount,
                    onClearAll: activeFilterCount > 0
                        ? () => setState(() {
                              _species = null;
                              _status = null;
                            })
                        : null,
                    chips: [
                      if (_species != null)
                        PetsyActiveFilter(
                          label: context.t(_species!),
                          icon: _speciesIcon(_species),
                          onClear: () => setState(() => _species = null),
                        ),
                      if (_status != null)
                        PetsyActiveFilter(
                          label: context.t(_status!),
                          icon: Icons.label_outline_rounded,
                          onClear: () => setState(() => _status = null),
                        ),
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        12,
                        PetsySpacing.page,
                        110,
                      ),
                      child: _MyPetsEmptyState(
                        filtered: pets.isNotEmpty,
                        onAdd: _addPet,
                        onClear: _clearFilters,
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 8, PetsySpacing.page, 8),
                      child: Text(countLabel, style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, 110),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final pet = visible[i];
                        return _MyPetCard(
                          pet: pet,
                          needsDetails: _needsDetails(pet),
                          onOpen: () => context.push('/pet/${pet.id}'),
                          onEdit: () => _openEdit(pet),
                          onHealth: () => context.push('/pet-health/${pet.id}'),
                          onBook: () => context.push('/vets?petId=${pet.id}'),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MyPetsHero extends StatefulWidget {
  const _MyPetsHero();

  @override
  State<_MyPetsHero> createState() => _MyPetsHeroState();
}

class _MyPetsHeroState extends State<_MyPetsHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 0.2, -1),
                  end: Alignment(1, 1 - t * 0.15),
                  colors: const [
                    Color(0xFFD44318),
                    PetsyColors.primary,
                    PetsyColors.secondary,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -10,
                child: Icon(Icons.pets_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -16,
                bottom: -22,
                child: Icon(Icons.favorite_rounded, size: 86, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                      ),
                      child: Text(
                        context.t('my_pets_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('my_pets_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('my_pets_subtitle'),
                      style: PetsyType.meta.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyPetsStatsRow extends StatelessWidget {
  const _MyPetsStatsRow({
    required this.totalLabel,
    required this.incompleteLabel,
    required this.vaccinatedLabel,
  });

  final String totalLabel;
  final String incompleteLabel;
  final String vaccinatedLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _MyPetsStatTile(icon: Icons.pets_rounded, label: totalLabel, color: PetsyColors.primaryDark)),
        const SizedBox(width: 8),
        Expanded(child: _MyPetsStatTile(icon: Icons.info_outline_rounded, label: incompleteLabel, color: PetsyColors.warning)),
        const SizedBox(width: 8),
        Expanded(child: _MyPetsStatTile(icon: Icons.vaccines_outlined, label: vaccinatedLabel, color: PetsyColors.success)),
      ],
    );
  }
}

class _MyPetsStatTile extends StatelessWidget {
  const _MyPetsStatTile({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _MyPetsEmptyState extends StatelessWidget {
  const _MyPetsEmptyState({
    required this.filtered,
    required this.onAdd,
    required this.onClear,
  });

  final bool filtered;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: PetsyColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.18)),
              ),
              child: Icon(
                filtered ? Icons.search_off_rounded : Icons.pets_rounded,
                size: 36,
                color: PetsyColors.primaryDark,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t(filtered ? 'my_pets_empty_filter' : 'my_pets_empty_title'),
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              context.t(filtered ? 'my_pets_empty_filter_body' : 'my_pets_empty_body'),
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: filtered
                  ? OutlinedButton(onPressed: onClear, child: Text(context.t('clear')))
                  : FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.t('add_pet')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyPetCard extends StatelessWidget {
  const _MyPetCard({
    required this.pet,
    required this.needsDetails,
    required this.onOpen,
    required this.onEdit,
    required this.onHealth,
    required this.onBook,
  });

  final Pet pet;
  final bool needsDetails;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onHealth;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final meta = joinIsolated([
      pet.breed ?? context.t(pet.species),
      if (pet.age != null && pet.age!.trim().isNotEmpty) petAgeLabel(context, pet.age),
    ]);

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(
              color: needsDetails ? PetsyColors.warning.withValues(alpha: 0.45) : PetsyColors.border,
              width: needsDetails ? 1.3 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: 92,
                        height: 92,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetImage(pet.image),
                            if (needsDetails)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: PetsyColors.warning,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    context.t('my_pets_needs_details'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 92,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pet.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PetsyType.section.copyWith(fontSize: 17),
                                  ),
                                ),
                                Icon(
                                  pet.gender == 'female' ? Icons.female_rounded : Icons.male_rounded,
                                  size: 18,
                                  color: pet.gender == 'female' ? PetsyColors.genderFemale : PetsyColors.genderMale,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PetsyType.meta.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                PetsyMetaBadge(label: context.t(pet.status), tone: PetsyMetaTone.primary),
                                PetsyMetaBadge(
                                  label: context.t(pet.vaccinated ? 'my_pets_vaccinated' : 'my_pets_not_vaccinated'),
                                  tone: pet.vaccinated ? PetsyMetaTone.accent : PetsyMetaTone.neutral,
                                  icon: Icons.vaccines_outlined,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: PetsyChevron.forward(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MyPetActionChip(
                        icon: needsDetails ? Icons.add_a_photo_outlined : Icons.edit_outlined,
                        label: needsDetails ? context.t('complete_pet_details') : context.t('edit_pet'),
                        color: PetsyColors.primarySoft,
                        foreground: PetsyColors.primaryDark,
                        onTap: onEdit,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MyPetActionChip(
                        icon: Icons.monitor_heart_outlined,
                        label: context.t('my_pets_open_health'),
                        color: PetsyColors.accentSoft,
                        foreground: PetsyColors.accent,
                        onTap: onHealth,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: PetsyColors.mist,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        onTap: onBook,
                        borderRadius: BorderRadius.circular(99),
                        child: Tooltip(
                          message: context.t('my_pets_book_vet'),
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(Icons.medical_services_outlined, size: 20, color: PetsyColors.primaryDark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyPetActionChip extends StatelessWidget {
  const _MyPetActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddPetScreen extends StatelessWidget {
  const AddPetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('add_pet'))),
      child: _PetForm(
        submitLabel: context.t('pet_form_save_add'),
        onSubmit: (data) async {
          await context.api.createPet(data);
          if (!context.mounted) return;
          context.snack(context.t('pet_added'), success: true, icon: Icons.pets_rounded);
          context.pop(true);
        },
      ),
    );
  }
}

class EditPetScreen extends StatefulWidget {
  const EditPetScreen({super.key, required this.petId, this.fromOnboarding = false});

  final String petId;
  final bool fromOnboarding;

  @override
  State<EditPetScreen> createState() => _EditPetScreenState();
}

class _EditPetScreenState extends State<EditPetScreen> {
  bool _busy = false;

  Future<void> _leave({bool updated = false}) async {
    if (widget.fromOnboarding) {
      await context.read<AuthState>().completeOnboarding();
      if (mounted) context.go('/home');
      return;
    }
    if (mounted) context.pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(
        title: Text(context.t(widget.fromOnboarding ? 'complete_pet_details' : 'edit_pet')),
        actions: [
          if (widget.fromOnboarding)
            TextButton(
              onPressed: _busy ? null : () => _leave(),
              child: Text(context.t('skip')),
            ),
        ],
      ),
      child: AsyncView<Pet>(
        loader: () => context.api.pet(widget.petId),
        builder: (context, pet, _) => _PetForm(
          initial: pet,
          intro: widget.fromOnboarding ? context.t('complete_pet_support') : null,
          submitLabel: context.t(widget.fromOnboarding ? 'done' : 'pet_form_save_edit'),
          onBusyChanged: (busy) => setState(() => _busy = busy),
          onSubmit: (data) async {
            await context.api.updatePet(widget.petId, data);
            if (!context.mounted) return;
            context.snack(context.t('pet_updated'), success: true, icon: Icons.check_circle_outline_rounded);
            await _leave(updated: true);
          },
        ),
      ),
    );
  }
}

class _PetForm extends StatefulWidget {
  const _PetForm({
    required this.submitLabel,
    required this.onSubmit,
    this.initial,
    this.intro,
    this.onBusyChanged,
  });

  final Pet? initial;
  final String? intro;
  final String submitLabel;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<_PetForm> createState() => _PetFormState();
}

class _PetFormState extends State<_PetForm> {
  static const _listingStatuses = ['owned', 'for_adoption', 'for_sale'];

  final _form = GlobalKey<FormState>();
  late final Pet? _pet = widget.initial;
  late final _name = TextEditingController(text: _pet?.name ?? '');
  late final _breed = TextEditingController(text: _pet?.breed ?? '');
  late final PetAge? _initialAge = PetAge.parse(_pet?.age);
  late final _age = TextEditingController(text: _initialAge?.number ?? _pet?.age ?? '');
  late bool _ageMonths = _initialAge?.months ?? false;
  late final _color = TextEditingController(text: _pet?.color ?? '');
  late final _weight = TextEditingController(text: _formatNumber(_pet?.weight));
  late final _location = TextEditingController(text: _pet?.location ?? '');
  late final _description = TextEditingController(text: _pet?.description ?? '');
  late final _image = TextEditingController(text: _pet?.image ?? '');
  late final _price = TextEditingController(text: _formatNumber(_pet?.price));
  late String _species = petSpecies.contains(_pet?.species) ? _pet!.species : 'cat';
  late String _gender = _pet?.gender == 'female' ? 'female' : 'male';
  late String _status = _pet?.status ?? 'owned';
  late String _purpose = (_pet?.purpose == 'companion') ? 'companion' : 'guard';
  late String _guardRole = guardRoles.contains(_pet?.guardRole) ? _pet!.guardRole! : 'home';
  late String _country = () {
    final c = _pet?.country?.trim();
    return (c != null && c.isNotEmpty) ? c : 'SY';
  }();
  late String _sellerType = sellerTypes.contains(_pet?.sellerType) ? _pet!.sellerType! : 'individual';
  late final _currency = TextEditingController(text: _pet?.currency ?? 'SYP');
  late bool _vaccinated = _pet?.vaccinated ?? false;
  late bool _neutered = _pet?.neutered ?? false;
  bool _busy = false;

  bool get _isEdit => _pet != null;

  static String _formatNumber(double? v) {
    if (v == null) return '';
    return v.truncateToDouble() == v ? v.toStringAsFixed(0) : '$v';
  }

  @override
  void dispose() {
    for (final c in [_name, _breed, _age, _color, _weight, _location, _description, _image, _price, _currency]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nullable(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _setBusy(bool v) {
    setState(() => _busy = v);
    widget.onBusyChanged?.call(v);
  }

  String? _ageText() {
    final raw = _age.text.trim();
    if (raw.isEmpty) return _isEdit ? '' : null;
    return PetAge(num.parse(raw.replaceAll(',', '.')), months: _ageMonths).stored;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    // On edit, empty strings are sent so cleared fields are actually cleared server-side.
    String? text(TextEditingController c) => _isEdit ? c.text.trim() : _nullable(c);
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'species': _species,
      'gender': _gender,
      'status': _status,
      'breed': text(_breed),
      'age': _ageText(),
      'color': text(_color),
      'weight': double.tryParse(_weight.text.trim().replaceAll(',', '.')),
      'location': text(_location),
      'description': text(_description),
      'image': _nullable(_image),
      'price': _status == 'for_sale' ? double.tryParse(_price.text.trim()) : null,
      'purpose': _status == 'for_sale' && _species == 'dog' ? _purpose : null,
      if (_status == 'for_sale' && _species == 'dog' && _purpose == 'guard') ...{
        'guard_role': _guardRole,
        'country': _country,
        'seller_type': _sellerType,
        'currency': _currency.text.trim().isEmpty ? 'SYP' : _currency.text.trim().toUpperCase(),
      },
      'vaccinated': _vaccinated,
      'neutered': _neutered,
    };
    _setBusy(true);
    try {
      await widget.onSubmit(data);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  void _selectSpecies(String s) {
    setState(() {
      _species = s;
      if (s == 'dog' && _status == 'for_sale') _purpose = 'guard';
    });
  }

  @override
  Widget build(BuildContext context) {
    final statuses = [
      ..._listingStatuses,
      if (!_listingStatuses.contains(_status)) _status,
    ];
    return Form(
      key: _form,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 28),
              children: [
                _PetFormHero(isEdit: _isEdit),
                if (widget.intro != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: PetsyColors.accentSoft,
                      borderRadius: BorderRadius.circular(PetsyRadius.md),
                      border: Border.all(color: PetsyColors.accent.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: PetsyColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.intro!,
                            style: const TextStyle(
                              color: PetsyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SectionCard(
                  title: context.t('pet_photo'),
                  icon: Icons.photo_camera_outlined,
                  child: PetPhotoPicker(
                    imageUrl: _image.text.trim().isEmpty ? null : _image.text.trim(),
                    enabled: !_busy,
                    onChanged: (url) => setState(() => _image.text = url ?? ''),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('pet_form_basic'),
                  icon: Icons.badge_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.t('pet_name'),
                          hintText: context.t('pet_name_hint'),
                          prefixIcon: const Icon(Icons.pets_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                      ),
                      const SizedBox(height: 14),
                      PetsyChoiceField<String>(
                        label: context.t('species'),
                        prefixIcon: Icons.pets_rounded,
                        required: true,
                        value: _species,
                        options: [
                          for (final s in petSpecies)
                            PetsyChoiceOption(
                              value: s,
                              label: context.t(s),
                              icon: _speciesIcon(s),
                            ),
                        ],
                        onChanged: _selectSpecies,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel(context.t('gender')),
                      Row(
                        children: [
                          Expanded(
                            child: _GenderOption(
                              label: context.t('male'),
                              icon: Icons.male_rounded,
                              color: PetsyColors.genderMale,
                              selected: _gender == 'male',
                              onTap: () => setState(() => _gender = 'male'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GenderOption(
                              label: context.t('female'),
                              icon: Icons.female_rounded,
                              color: PetsyColors.genderFemale,
                              selected: _gender == 'female',
                              onTap: () => setState(() => _gender = 'female'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('pet_form_listing'),
                  icon: Icons.storefront_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in statuses) ...[
                        _StatusOption(
                          title: context.t(s),
                          subtitle: switch (s) {
                            'owned' => context.t('pet_status_owned_hint'),
                            'for_adoption' => context.t('pet_status_adoption_hint'),
                            'for_sale' => context.t('pet_status_sale_hint'),
                            _ => null,
                          },
                          icon: switch (s) {
                            'owned' => Icons.home_rounded,
                            'for_adoption' => Icons.volunteer_activism_rounded,
                            'for_sale' => Icons.sell_outlined,
                            _ => Icons.help_outline_rounded,
                          },
                          selected: _status == s,
                          onTap: () => setState(() {
                            _status = s;
                            if (s == 'for_sale' && _species == 'dog') _purpose = 'guard';
                          }),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_status == 'for_sale') ...[
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.t('price'),
                            prefixIcon: const Icon(Icons.payments_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                        ),
                        if (_species == 'dog') ...[
                          const SizedBox(height: 14),
                          _FieldLabel(context.t('pet_purpose')),
                          const SizedBox(height: 8),
                          _StatusOption(
                            title: context.t('purpose_guard'),
                            subtitle: context.t('purpose_guard_hint'),
                            icon: Icons.security_rounded,
                            selected: _purpose == 'guard',
                            onTap: () => setState(() => _purpose = 'guard'),
                          ),
                          const SizedBox(height: 8),
                          _StatusOption(
                            title: context.t('purpose_companion'),
                            subtitle: context.t('purpose_companion_hint'),
                            icon: Icons.pets_rounded,
                            selected: _purpose == 'companion',
                            onTap: () => setState(() => _purpose = 'companion'),
                          ),
                          if (_purpose == 'guard') ...[
                            const SizedBox(height: 14),
                            PetsyChoiceField<String>(
                              label: context.t('guard_role_label'),
                              prefixIcon: Icons.security_rounded,
                              required: true,
                              value: _guardRole,
                              options: [
                                for (final role in guardRoles)
                                  PetsyChoiceOption(
                                    value: role,
                                    label: context.t('guard_role_$role'),
                                    icon: guardRoleIcon(role),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _guardRole = v),
                            ),
                            const SizedBox(height: 12),
                            PetsyChoiceField<String>(
                              label: context.t('seller_type_label'),
                              prefixIcon: Icons.storefront_outlined,
                              required: true,
                              value: _sellerType,
                              options: [
                                for (final s in sellerTypes)
                                  PetsyChoiceOption(
                                    value: s,
                                    label: context.t('seller_$s'),
                                    icon: Icons.badge_outlined,
                                  ),
                              ],
                              onChanged: (v) => setState(() => _sellerType = v),
                            ),
                            const SizedBox(height: 12),
                            PetsyChoiceField<String>(
                              label: context.t('country_label'),
                              prefixIcon: Icons.public_rounded,
                              required: true,
                              value: _country,
                              options: [
                                for (final c in guardCountries)
                                  PetsyChoiceOption(
                                        value: c,
                                        label: context.t('country_$c'),
                                        icon: Icons.flag_outlined,
                                        keywords: [c],
                                      ),
                              ],
                              onChanged: (v) => setState(() => _country = v),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _currency,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: context.t('currency'),
                                hintText: 'SYP / USD / AED',
                                prefixIcon: const Icon(Icons.attach_money_rounded),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('pet_form_details'),
                  icon: Icons.tune_rounded,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _breed,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.t('breed'),
                          hintText: context.t('pet_breed_hint'),
                          prefixIcon: const Icon(Icons.category_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _age,
                              textInputAction: TextInputAction.next,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: context.t('age'),
                                hintText: context.t('pet_age_hint'),
                                prefixIcon: const Icon(Icons.cake_outlined),
                              ),
                              validator: (v) {
                                final raw = v?.trim().replaceAll(',', '.') ?? '';
                                if (raw.isEmpty) return null;
                                final n = num.tryParse(raw);
                                return n == null || n <= 0 || n > 100 ? context.t('age_invalid') : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                PetsyPill(
                                  style: PetsyPillStyle.choice,
                                  label: context.t('age_unit_years'),
                                  selected: !_ageMonths,
                                  onTap: () => setState(() => _ageMonths = false),
                                ),
                                const SizedBox(width: 6),
                                PetsyPill(
                                  style: PetsyPillStyle.choice,
                                  label: context.t('age_unit_months'),
                                  selected: _ageMonths,
                                  onTap: () => setState(() => _ageMonths = true),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _weight,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.t('weight'),
                          prefixIcon: const Icon(Icons.monitor_weight_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _color,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.t('color'),
                          hintText: context.t('pet_color_hint'),
                          prefixIcon: const Icon(Icons.palette_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      PetsyCityField(
                        controller: _location,
                        label: context.t('location'),
                        hint: context.t('pet_location_hint'),
                        autofillFromGps: (_pet?.location ?? '').trim().isEmpty,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('pet_form_health'),
                  icon: Icons.health_and_safety_outlined,
                  child: Column(
                    children: [
                      _HealthToggle(
                        icon: Icons.vaccines_outlined,
                        title: context.t('vaccinated'),
                        subtitle: context.t('pet_vaccinated_hint'),
                        value: _vaccinated,
                        onChanged: (v) => setState(() => _vaccinated = v),
                      ),
                      const SizedBox(height: 8),
                      _HealthToggle(
                        icon: Icons.verified_user_outlined,
                        title: context.t('neutered'),
                        subtitle: context.t('pet_neutered_hint'),
                        value: _neutered,
                        onChanged: (v) => setState(() => _neutered = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('pet_form_about'),
                  icon: Icons.notes_rounded,
                  child: TextFormField(
                    controller: _description,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: context.t('pet_desc_hint'),
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 54),
                        child: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _PetFormSaveBar(
            label: widget.submitLabel,
            busy: _busy,
            isEdit: _isEdit,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _PetFormHero extends StatelessWidget {
  const _PetFormHero({required this.isEdit});

  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isEdit
                ? const [Color(0xFF2A6B5E), PetsyColors.accent, Color(0xFF56B8A8)]
                : const [Color(0xFFD44318), PetsyColors.primary, PetsyColors.secondary],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -20,
              bottom: -28,
              child: Icon(
                isEdit ? Icons.edit_note_rounded : Icons.pets_rounded,
                size: 112,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              right: -14,
              top: -18,
              child: Icon(
                Icons.favorite_rounded,
                size: 78,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      context.t(isEdit ? 'pet_form_edit_hero_tag' : 'pet_form_add_hero_tag'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t(isEdit ? 'pet_form_edit_hero_title' : 'pet_form_add_hero_title'),
                    style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.t(isEdit ? 'pet_form_edit_hero_body' : 'pet_form_add_hero_body'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetFormSaveBar extends StatelessWidget {
  const _PetFormSaveBar({
    required this.label,
    required this.busy,
    required this.isEdit,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final bool isEdit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.white,
      shadowColor: PetsyColors.ink.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: PetsyColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_rounded : Icons.pets_rounded,
                      color: PetsyColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t(isEdit ? 'pet_form_edit_hero_title' : 'pet_form_add_subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: PetsyColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy ? null : onPressed,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Icon(isEdit ? Icons.check_rounded : Icons.add_rounded, size: 20),
                  label: Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.1) : PetsyColors.backgroundAlt,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.md),
            border: Border.all(color: selected ? color : PetsyColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? color : PetsyColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? color : PetsyColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? PetsyColors.textLight : (selected ? PetsyColors.primaryDark : PetsyColors.text);
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: selected ? PetsyColors.primarySoft : PetsyColors.backgroundAlt,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.md),
              border: Border.all(
                color: selected ? PetsyColors.primary : PetsyColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : PetsyColors.surface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: fg),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12, height: 1.3),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? PetsyColors.primary : PetsyColors.textLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthToggle extends StatelessWidget {
  const _HealthToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? PetsyColors.accentSoft : PetsyColors.backgroundAlt,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Icon(icon, color: value ? PetsyColors.accent : PetsyColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(subtitle, style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
