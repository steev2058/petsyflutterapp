import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

import '../../data/region_countries.dart';
import '../../widgets/choice_field.dart';

const trainerCategories = ['obedience', 'guard', 'puppy', 'agility', 'behavior', 'service_dog'];
const trainerCountries = petsyRegionCountries;

IconData trainerCategoryIcon(String c) => switch (c) {
      'obedience' => Icons.psychology_alt_rounded,
      'guard' => Icons.security_rounded,
      'puppy' => Icons.cruelty_free_rounded,
      'agility' => Icons.sports_rounded,
      'behavior' => Icons.hearing_rounded,
      'service_dog' => Icons.accessibility_new_rounded,
      _ => Icons.school_rounded,
    };

enum _TrainerSort { topRated, experience, priceLow }

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final _query = TextEditingController();
  String _q = '';
  String? _category;
  String? _country;
  bool _internationalOnly = false;
  _TrainerSort _sort = _TrainerSort.topRated;

  bool get _hasExtraFilters =>
      _country != null || _internationalOnly || _sort != _TrainerSort.topRated;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Trainer> _applyLocal(List<Trainer> trainers) {
    var list = trainers;
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final hay = [
          t.name,
          t.title ?? '',
          t.bio ?? '',
          t.city ?? '',
          t.country ?? '',
          ...t.categories,
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    list = [...list];
    if (_sort == _TrainerSort.experience) {
      list.sort((a, b) => b.experienceYears.compareTo(a.experienceYears));
    } else if (_sort == _TrainerSort.priceLow) {
      list.sort((a, b) => (a.priceFrom ?? double.infinity).compareTo(b.priceFrom ?? double.infinity));
    } else {
      list.sort((a, b) {
        final r = b.rating.compareTo(a.rating);
        return r != 0 ? r : b.ratingCount.compareTo(a.ratingCount);
      });
    }
    return list;
  }

  Future<void> _openFilters() async {
    var draftCountry = _country;
    var draftIntl = _internationalOnly;
    var draftSort = _sort;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PetsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx);
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.82;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      PetsySpacing.page,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.t('training_filters'), style: PetsyType.section),
                        const SizedBox(height: PetsySpacing.md),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PetsyChoiceField<String>(
                                  label: context.t('country_label'),
                                  prefixIcon: Icons.public_rounded,
                                  value: draftIntl
                                      ? '__intl__'
                                      : (draftCountry ?? '__all__'),
                                  options: [
                                    PetsyChoiceOption(
                                      value: '__all__',
                                      label: context.t('country_all'),
                                      icon: Icons.public_rounded,
                                    ),
                                    PetsyChoiceOption(
                                      value: '__intl__',
                                      label: context.t('training_international'),
                                      icon: Icons.flight_rounded,
                                    ),
                                    for (final c in trainerCountries)
                                      PetsyChoiceOption(
                                        value: c,
                                        label: context.t('country_$c'),
                                        icon: Icons.flag_outlined,
                                        keywords: [c],
                                      ),
                                  ],
                                  onChanged: (v) => setModal(() {
                                    if (v == '__intl__') {
                                      draftIntl = true;
                                      draftCountry = null;
                                    } else if (v == '__all__') {
                                      draftIntl = false;
                                      draftCountry = null;
                                    } else {
                                      draftIntl = false;
                                      draftCountry = v;
                                    }
                                  }),
                                ),
                                const SizedBox(height: PetsySpacing.lg),
                                PetsyChoiceField<_TrainerSort>(
                                  label: context.t('training_sort'),
                                  prefixIcon: Icons.sort_rounded,
                                  value: draftSort,
                                  options: [
                                    for (final s in _TrainerSort.values)
                                      PetsyChoiceOption(
                                        value: s,
                                        label: context.t(switch (s) {
                                          _TrainerSort.topRated => 'training_sort_rated',
                                          _TrainerSort.experience => 'training_sort_experience',
                                          _TrainerSort.priceLow => 'guard_sort_price_low',
                                        }),
                                        icon: Icons.sort_rounded,
                                      ),
                                  ],
                                  onChanged: (v) => setModal(() => draftSort = v),
                                ),
                                const SizedBox(height: PetsySpacing.md),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: PetsySpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setModal(() {
                                  draftCountry = null;
                                  draftIntl = false;
                                  draftSort = _TrainerSort.topRated;
                                }),
                                child: Text(context.t('clear')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(context.t('guard_filters_apply')),
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
          },
        );
      },
    );
    if (applied == true && mounted) {
      setState(() {
        _country = draftCountry;
        _internationalOnly = draftIntl;
        _sort = draftSort;
      });
    }
  }

  void _clearAll() {
    _query.clear();
    setState(() {
      _q = '';
      _category = null;
      _country = null;
      _internationalOnly = false;
      _sort = _TrainerSort.topRated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('training')),
        actions: [
          IconButton(
            tooltip: context.t('training_filters'),
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _hasExtraFilters,
              smallSize: 8,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: PetsyFab(
        heroTag: 'training-apply-fab',
        icon: Icons.person_add_alt_1_rounded,
        label: context.t('trainer_apply_fab'),
        onPressed: () async {
          if (!context.requireLogin()) return;
          await context.push('/training/apply');
        },
      ),
      body: AsyncView<List<Trainer>>(
        key: ValueKey('$_category|$_country|$_internationalOnly'),
        loader: () => context.api.trainers(
          category: _category,
          country: _country,
          international: _internationalOnly ? true : null,
        ),
        builder: (context, trainers, reload) {
          final filtered = _applyLocal(trainers);
          final featured = _category == null && _q.isEmpty && !_internationalOnly
              ? trainers.where((t) => t.servesInternational).take(6).toList()
              : const <Trainer>[];

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _TrainingHero()),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('training_search_hint'),
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
                    child: _CategorySelector(
                      selected: _category,
                      onSelected: (c) => setState(() => _category = c),
                    ),
                  ),
                ),
                if (_category != null || _country != null || _internationalOnly || _q.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ActiveTrainingFilters(
                      category: _category,
                      country: _country,
                      internationalOnly: _internationalOnly,
                      hasQuery: _q.isNotEmpty,
                      onClearCategory: () => setState(() => _category = null),
                      onClearCountry: () => setState(() {
                        _country = null;
                        _internationalOnly = false;
                      }),
                      onClearQuery: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                      onClearAll: _clearAll,
                    ),
                  ),
                if (featured.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        PetsySpacing.lg,
                        PetsySpacing.page,
                        PetsySpacing.sm,
                      ),
                      child: Text(context.t('training_featured'), style: PetsyType.section),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 156,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                        itemCount: featured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                        itemBuilder: (_, i) => _FeaturedTrainerCard(trainer: featured[i]),
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
                                ? context.t('training_results_one')
                                : context.t('training_results').replaceAll('{count}', '${filtered.length}'),
                            style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openFilters,
                          icon: const Icon(Icons.sort_rounded, size: 18),
                          label: Text(
                            context.t(switch (_sort) {
                              _TrainerSort.topRated => 'training_sort_rated',
                              _TrainerSort.experience => 'training_sort_experience',
                              _TrainerSort.priceLow => 'guard_sort_price_low',
                            }),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageView(
                      icon: Icons.school_rounded,
                      text: '${context.t('training_empty_title')}\n${context.t('training_empty_body')}',
                      action: TextButton(onPressed: _clearAll, child: Text(context.t('clear'))),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: PetsySpacing.md),
                      itemBuilder: (_, i) => _TrainerListingCard(trainer: filtered[i], index: i),
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

class _TrainingHero extends StatefulWidget {
  const _TrainingHero();

  @override
  State<_TrainingHero> createState() => _TrainingHeroState();
}

class _TrainingHeroState extends State<_TrainingHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
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
                  begin: Alignment(-1 + t * 0.25, -1),
                  end: Alignment(1, 1 - t * 0.15),
                  colors: const [
                    Color(0xFF1F4A45),
                    Color(0xFF2F9E8F),
                    Color(0xFF3BB8A5),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -16,
                child: Icon(Icons.school_rounded, size: 130, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Positioned(
                left: -24,
                bottom: -28,
                child: Icon(Icons.pets_rounded, size: 100, color: Colors.white.withValues(alpha: 0.07)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: Text(
                        context.t('training_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('training_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('training_subtitle'),
                      style: PetsyType.meta.copyWith(color: Colors.white.withValues(alpha: 0.85), height: 1.4, fontSize: 13.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _HeroChip(icon: Icons.psychology_alt_rounded, label: context.t('trainer_cat_obedience')),
                        const SizedBox(width: 8),
                        _HeroChip(icon: Icons.security_rounded, label: context.t('trainer_cat_guard')),
                        const SizedBox(width: 8),
                        _HeroChip(icon: Icons.flight_rounded, label: context.t('training_international')),
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

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
        itemCount: trainerCategories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _CategoryTile(
              icon: Icons.apps_rounded,
              label: context.t('all'),
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final cat = trainerCategories[i - 1];
          return _CategoryTile(
            icon: trainerCategoryIcon(cat),
            label: context.t('trainer_cat_$cat'),
            selected: selected == cat,
            onTap: () => onSelected(cat),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
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
        width: 92,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.accent : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(
            color: selected ? PetsyColors.accent : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : PetsyColors.accent, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : PetsyColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTrainingFilters extends StatelessWidget {
  const _ActiveTrainingFilters({
    required this.category,
    required this.country,
    required this.internationalOnly,
    required this.hasQuery,
    required this.onClearCategory,
    required this.onClearCountry,
    required this.onClearQuery,
    required this.onClearAll,
  });

  final String? category;
  final String? country;
  final bool internationalOnly;
  final bool hasQuery;
  final VoidCallback onClearCategory;
  final VoidCallback onClearCountry;
  final VoidCallback onClearQuery;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: Row(
        children: [
          if (category != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('trainer_cat_$category'), onDeleted: onClearCategory),
            ),
          if (internationalOnly)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('training_international'), onDeleted: onClearCountry),
            )
          else if (country != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('country_$country'), onDeleted: onClearCountry),
            ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('guard_dogs_search_active'), onDeleted: onClearQuery),
            ),
          TextButton(onPressed: onClearAll, child: Text(context.t('clear_all'))),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      onDeleted: onDeleted,
      deleteIconColor: PetsyColors.accent,
      backgroundColor: PetsyColors.accentSoft,
      side: BorderSide(color: PetsyColors.accent.withValues(alpha: 0.22)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
  }
}

class _FeaturedTrainerCard extends StatelessWidget {
  const _FeaturedTrainerCard({required this.trainer});

  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: () => context.push('/trainers/${trainer.id}'),
      child: SizedBox(
        width: 210,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(trainer.image, icon: Icons.school_rounded),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0xCC1F4A45)],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 10,
                end: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PetsyMetaBadge(label: context.t('training_intl_badge'), tone: PetsyMetaTone.accent),
                    const SizedBox(height: 6),
                    Text(
                      trainer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    if ((trainer.title ?? '').isNotEmpty)
                      Text(
                        trainer.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
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

class _TrainerListingCard extends StatelessWidget {
  const _TrainerListingCard({required this.trainer, required this.index});

  final Trainer trainer;
  final int index;

  @override
  Widget build(BuildContext context) {
    final place = [
      if (trainer.country != null && trainer.country!.isNotEmpty) context.t('country_${trainer.country}'),
      if (trainer.city != null && trainer.city!.trim().isNotEmpty) trainer.city!.trim(),
    ].join(' · ');
    final hasImage = trainer.image != null && trainer.image!.startsWith('http');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + (index.clamp(0, 8) * 40)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: PetsyPressScale(
        onTap: () => context.push('/trainers/${trainer.id}'),
        child: Material(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              border: Border.all(color: PetsyColors.border),
              boxShadow: PetsyShadows.soft,
            ),
            child: Padding(
              padding: const EdgeInsets.all(PetsySpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: hasImage
                          ? NetImage(trainer.image, icon: Icons.school_rounded)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [PetsyColors.accentSoft, Color(0xFFD3EEE9)],
                                ),
                              ),
                              child: Icon(Icons.school_rounded, color: PetsyColors.accent, size: 30),
                            ),
                    ),
                  ),
                  const SizedBox(width: PetsySpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                trainer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PetsyType.cardTitle.copyWith(fontSize: 16),
                              ),
                            ),
                            if (trainer.servesInternational)
                              PetsyMetaBadge(label: context.t('training_intl_badge'), tone: PetsyMetaTone.accent),
                          ],
                        ),
                        if ((trainer.title ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            trainer.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.meta,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in trainer.categories.take(3))
                              PetsyMetaBadge(label: context.t('trainer_cat_$c'), tone: PetsyMetaTone.primary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (trainer.rating > 0) ...[
                              PetsyRating(trainer.rating, compact: true),
                              const SizedBox(width: 8),
                            ],
                            if (place.isNotEmpty)
                              Expanded(
                                child: Text(
                                  place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              )
                            else
                              const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (trainer.experienceYears > 0)
                              Text(
                                context.t('training_experience').replaceAll('{years}', '${trainer.experienceYears}'),
                                style: PetsyType.meta.copyWith(fontSize: 12),
                              ),
                            const Spacer(),
                            if (trainer.priceFrom != null)
                              Text(
                                context
                                    .t('training_from_price')
                                    .replaceAll('{price}', formatPrice(trainer.priceFrom!, currency: trainer.currency)),
                                style: PetsyType.price.copyWith(fontSize: 14),
                              ),
                          ],
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

class TrainerDetailScreen extends StatelessWidget {
  const TrainerDetailScreen({super.key, required this.trainerId});

  final String trainerId;

  Future<void> _call(String? phone) async {
    final raw = (phone ?? '').trim();
    if (raw.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: raw);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _message(BuildContext context, Trainer trainer) async {
    if (!context.requireLogin()) return;
    final userId = trainer.userId;
    if (userId == null || userId.isEmpty) {
      context.snack(context.t('training_no_chat'), error: true);
      return;
    }
    try {
      final id = await context.api.startConversation(
        otherUserId: userId,
        message: context.t('training_chat_opening').replaceAll('{name}', trainer.name),
      );
      if (context.mounted) context.push('/chat/$id');
    } catch (e) {
      if (context.mounted) context.snack(context.errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      body: AsyncView<Trainer>(
        loader: () => context.api.trainer(trainerId),
        builder: (context, trainer, reload) {
          final place = [
            if (trainer.country != null && trainer.country!.isNotEmpty) context.t('country_${trainer.country}'),
            if (trainer.city != null && trainer.city!.trim().isNotEmpty) trainer.city!.trim(),
            if (trainer.location != null && trainer.location!.trim().isNotEmpty) trainer.location!.trim(),
          ].join(' · ');
          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      expandedHeight: 240,
                      backgroundColor: PetsyColors.background,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetImage(trainer.image, icon: Icons.school_rounded),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x33000000), Color(0x00000000), Color(0x99000000)],
                                  stops: [0, 0.45, 1],
                                ),
                              ),
                            ),
                            if (trainer.servesInternational)
                              PositionedDirectional(
                                start: 16,
                                bottom: 16,
                                child: PetsyMetaBadge(
                                  label: context.t('training_intl_badge'),
                                  tone: PetsyMetaTone.accent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 18, PetsySpacing.page, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(trainer.name, style: PetsyType.title.copyWith(fontSize: 26)),
                            if ((trainer.title ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(trainer.title!, style: PetsyType.subtitle),
                            ],
                            if (trainer.rating > 0) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  PetsyRating(trainer.rating),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${trainer.ratingCount})',
                                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in trainer.categories)
                                  PetsyMetaBadge(label: context.t('trainer_cat_$c'), tone: PetsyMetaTone.primary),
                              ],
                            ),
                            if (place.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Icon(Icons.place_outlined, size: 18, color: PetsyColors.accent),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(place, style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ],
                            if (trainer.experienceYears > 0 || trainer.priceFrom != null) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  if (trainer.experienceYears > 0)
                                    Expanded(
                                      child: _InfoTile(
                                        icon: Icons.workspace_premium_outlined,
                                        label: context
                                            .t('training_experience')
                                            .replaceAll('{years}', '${trainer.experienceYears}'),
                                      ),
                                    ),
                                  if (trainer.experienceYears > 0 && trainer.priceFrom != null)
                                    const SizedBox(width: 10),
                                  if (trainer.priceFrom != null)
                                    Expanded(
                                      child: _InfoTile(
                                        icon: Icons.payments_outlined,
                                        label: context.t('training_from_price').replaceAll(
                                              '{price}',
                                              formatPrice(trainer.priceFrom!, currency: trainer.currency),
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if ((trainer.bio ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(context.t('training_about'), style: PetsyType.section),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: PetsyColors.surface,
                                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                                  border: Border.all(color: PetsyColors.border),
                                ),
                                child: Text(trainer.bio!, style: PetsyType.body.copyWith(height: 1.55)),
                              ),
                            ],
                            if (trainer.petTypes.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(context.t('training_pet_types'), style: PetsyType.section),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final p in trainer.petTypes)
                                    PetsyMetaBadge(
                                      label: context.t(p == 'all' ? 'all' : p),
                                      tone: PetsyMetaTone.neutral,
                                    ),
                                ],
                              ),
                            ],
                            if (trainer.languages.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(context.t('training_languages'), style: PetsyType.section),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final lang in trainer.languages)
                                    PetsyMetaBadge(
                                      label: context.t('lang_$lang'),
                                      tone: PetsyMetaTone.accent,
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 88),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              BottomActionBar(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (trainer.phone ?? '').isEmpty ? null : () => _call(trainer.phone),
                        icon: const Icon(Icons.call_outlined),
                        label: Text(context.t('call')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _message(context, trainer),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: Text(context.t('message')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: PetsyColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
