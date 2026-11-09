import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/region_countries.dart';
import '../../models/models.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/common.dart';

const guardRoles = ['home', 'facility', 'police', 'military', 'personal_protection'];
const guardCountries = petsyRegionCountries;
const sellerTypes = ['individual', 'kennel', 'security_company', 'agency'];

IconData guardRoleIcon(String role) => switch (role) {
      'home' => Icons.home_rounded,
      'facility' => Icons.apartment_rounded,
      'police' => Icons.local_police_rounded,
      'military' => Icons.military_tech_rounded,
      'personal_protection' => Icons.shield_rounded,
      _ => Icons.security_rounded,
    };

enum _GuardSort { newest, priceLow, priceHigh }

/// Professional / international guard-dog marketplace.
class GuardDogsScreen extends StatefulWidget {
  const GuardDogsScreen({super.key});

  @override
  State<GuardDogsScreen> createState() => _GuardDogsScreenState();
}

class _GuardDogsScreenState extends State<GuardDogsScreen> {
  final _query = TextEditingController();
  String _q = '';
  String? _role;
  String? _country;
  String? _sellerType;
  _GuardSort _sort = _GuardSort.newest;
  int _reloadToken = 0;

  bool get _hasExtraFilters => _country != null || _sellerType != null || _sort != _GuardSort.newest;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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
          p.country ?? '',
          p.sellerType ?? '',
          p.guardRole ?? '',
          p.description ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (_sort == _GuardSort.priceLow) {
      list = [...list]..sort((a, b) => (a.price ?? double.infinity).compareTo(b.price ?? double.infinity));
    } else if (_sort == _GuardSort.priceHigh) {
      list = [...list]..sort((a, b) => (b.price ?? 0).compareTo(a.price ?? 0));
    }
    return list;
  }

  Future<void> _openFilters() async {
    var draftCountry = _country;
    var draftSeller = _sellerType;
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
                        Text(context.t('guard_dogs_filters'), style: PetsyType.section),
                        const SizedBox(height: PetsySpacing.md),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PetsyChoiceField<String>(
                                  label: context.t('country_label'),
                                  prefixIcon: Icons.public_rounded,
                                  value: draftCountry ?? '__all__',
                                  options: [
                                    PetsyChoiceOption(
                                      value: '__all__',
                                      label: context.t('country_all'),
                                      icon: Icons.public_rounded,
                                    ),
                                    for (final c in guardCountries)
                                      PetsyChoiceOption(
                                        value: c,
                                        label: context.t('country_$c'),
                                        icon: Icons.flag_outlined,
                                        keywords: [c],
                                      ),
                                  ],
                                  onChanged: (v) => setModal(() => draftCountry = v == '__all__' ? null : v),
                                ),
                                const SizedBox(height: PetsySpacing.lg),
                                PetsyChoiceField<String>(
                                  label: context.t('seller_type_label'),
                                  prefixIcon: Icons.storefront_outlined,
                                  value: draftSeller ?? '__all__',
                                  options: [
                                    PetsyChoiceOption(
                                      value: '__all__',
                                      label: context.t('seller_all'),
                                      icon: Icons.apps_rounded,
                                    ),
                                    for (final s in sellerTypes)
                                      PetsyChoiceOption(
                                        value: s,
                                        label: context.t('seller_$s'),
                                        icon: Icons.badge_outlined,
                                      ),
                                  ],
                                  onChanged: (v) => setModal(() => draftSeller = v == '__all__' ? null : v),
                                ),
                                const SizedBox(height: PetsySpacing.lg),
                                PetsyChoiceField<_GuardSort>(
                                  label: context.t('guard_dogs_sort'),
                                  prefixIcon: Icons.sort_rounded,
                                  value: draftSort,
                                  options: [
                                    for (final s in _GuardSort.values)
                                      PetsyChoiceOption(
                                        value: s,
                                        label: context.t(switch (s) {
                                          _GuardSort.newest => 'sort_newest',
                                          _GuardSort.priceLow => 'guard_sort_price_low',
                                          _GuardSort.priceHigh => 'guard_sort_price_high',
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
                                onPressed: () {
                                  setModal(() {
                                    draftCountry = null;
                                    draftSeller = null;
                                    draftSort = _GuardSort.newest;
                                  });
                                },
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
        _sellerType = draftSeller;
        _sort = draftSort;
      });
    }
  }

  void _clearAll() {
    _query.clear();
    setState(() {
      _q = '';
      _role = null;
      _country = null;
      _sellerType = null;
      _sort = _GuardSort.newest;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('guard_dogs')),
        actions: [
          IconButton(
            tooltip: context.t('guard_dogs_filters'),
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
        heroTag: 'guard-dogs-fab',
        icon: Icons.add_rounded,
        label: context.t('add_guard_dog'),
        onPressed: () async {
          if (!context.requireLogin()) return;
          final created = await context.push<bool>('/guard-dogs/offer');
          if (created == true && mounted) setState(() => _reloadToken++);
        },
      ),
      body: AsyncView<List<Pet>>(
        key: ValueKey('$_role|$_country|$_sellerType|$_reloadToken'),
        loader: () => context.api.pets(
          status: 'for_sale',
          species: 'dog',
          purpose: 'guard',
          guardRole: _role,
          country: _country,
          sellerType: _sellerType,
        ),
        builder: (context, pets, reload) {
          final filtered = _applyLocal(pets);
          final featured = _role == null && _q.isEmpty
              ? pets.where((p) => p.guardRole == 'police' || p.guardRole == 'facility').take(6).toList()
              : const <Pet>[];

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _GuardHero()),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('guard_dogs_search_hint'),
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
                    child: _RoleSelector(
                      selected: _role,
                      onSelected: (role) => setState(() => _role = role),
                    ),
                  ),
                ),
                if (_role != null || _country != null || _sellerType != null || _q.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ActiveFiltersBar(
                      role: _role,
                      country: _country,
                      sellerType: _sellerType,
                      hasQuery: _q.isNotEmpty,
                      onClearRole: () => setState(() => _role = null),
                      onClearCountry: () => setState(() => _country = null),
                      onClearSeller: () => setState(() => _sellerType = null),
                      onClearQuery: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                      onClearAll: _clearAll,
                    ),
                  ),
                if (featured.isNotEmpty) ...[
                  SpiverSectionHeader(title: context.t('guard_dogs_featured')),
                  SpiverFeaturedStrip(pets: featured),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, PetsySpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            filtered.length == 1
                                ? context.t('guard_dogs_results_one')
                                : context.t('guard_dogs_results').replaceAll('{count}', '${filtered.length}'),
                            style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openFilters,
                          icon: const Icon(Icons.sort_rounded, size: 18),
                          label: Text(
                            context.t(switch (_sort) {
                              _GuardSort.newest => 'sort_newest',
                              _GuardSort.priceLow => 'guard_sort_price_low',
                              _GuardSort.priceHigh => 'guard_sort_price_high',
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
                      icon: Icons.security_rounded,
                      text: '${context.t('guard_dogs_empty_title')}\n${context.t('guard_dogs_empty_body')}',
                      action: _hasExtraFilters || _role != null || _q.isNotEmpty
                          ? TextButton(onPressed: _clearAll, child: Text(context.t('clear')))
                          : FilledButton.icon(
                              onPressed: () async {
                                if (!context.requireLogin()) return;
                                final created = await context.push<bool>('/guard-dogs/offer');
                                if (created == true && mounted) setState(() => _reloadToken++);
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: Text(context.t('add_guard_dog')),
                            ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      100,
                    ),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: PetsySpacing.md),
                      itemBuilder: (_, i) => _GuardListingCard(pet: filtered[i], index: i),
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

class SpiverSectionHeader extends StatelessWidget {
  const SpiverSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.lg, PetsySpacing.page, PetsySpacing.sm),
        child: Text(title, style: PetsyType.section),
      ),
    );
  }
}

class SpiverFeaturedStrip extends StatelessWidget {
  const SpiverFeaturedStrip({super.key, required this.pets});

  final List<Pet> pets;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 168,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
          itemCount: pets.length,
          separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
          itemBuilder: (_, i) => _FeaturedGuardCard(pet: pets[i]),
        ),
      ),
    );
  }
}

class _GuardHero extends StatefulWidget {
  const _GuardHero();

  @override
  State<_GuardHero> createState() => _GuardHeroState();
}

class _GuardHeroState extends State<_GuardHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
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
                  begin: Alignment(-1 + t * 0.3, -1),
                  end: Alignment(1, 1 - t * 0.2),
                  colors: const [
                    Color(0xFF1A2330),
                    Color(0xFF2B3A4D),
                    Color(0xFF1F4A45),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -28,
                top: -24,
                child: Icon(Icons.security_rounded, size: 140, color: Colors.white.withValues(alpha: 0.06)),
              ),
              Positioned(
                left: -20,
                bottom: -30,
                child: Icon(Icons.pets_rounded, size: 110, color: Colors.white.withValues(alpha: 0.05)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: PetsyColors.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: PetsyColors.accent.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        context.t('guard_dogs_intl_tag'),
                        style: const TextStyle(
                          color: Color(0xFFB8F0E6),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('guard_dogs_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('guard_dogs_subtitle'),
                      style: PetsyType.meta.copyWith(color: Colors.white70, height: 1.4, fontSize: 13.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _HeroStat(icon: Icons.apartment_rounded, label: context.t('guard_role_facility')),
                        const SizedBox(width: 8),
                        _HeroStat(icon: Icons.local_police_rounded, label: context.t('guard_role_police')),
                        const SizedBox(width: 8),
                        _HeroStat(icon: Icons.public_rounded, label: context.t('guard_dogs_intl_tag')),
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFFB8F0E6)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
        itemCount: guardRoles.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _RoleTile(
              icon: Icons.apps_rounded,
              label: context.t('guard_role_all'),
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final role = guardRoles[i - 1];
          return _RoleTile(
            icon: guardRoleIcon(role),
            label: context.t('guard_role_$role'),
            selected: selected == role,
            onTap: () => onSelected(role),
          );
        },
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
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
          color: selected ? PetsyColors.ink : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(
            color: selected ? PetsyColors.ink : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : PetsyColors.primaryDark, size: 24),
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

class _ActiveFiltersBar extends StatelessWidget {
  const _ActiveFiltersBar({
    required this.role,
    required this.country,
    required this.sellerType,
    required this.hasQuery,
    required this.onClearRole,
    required this.onClearCountry,
    required this.onClearSeller,
    required this.onClearQuery,
    required this.onClearAll,
  });

  final String? role;
  final String? country;
  final String? sellerType;
  final bool hasQuery;
  final VoidCallback onClearRole;
  final VoidCallback onClearCountry;
  final VoidCallback onClearSeller;
  final VoidCallback onClearQuery;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: Row(
        children: [
          if (role != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('guard_role_$role'), onDeleted: onClearRole),
            ),
          if (country != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('country_$country'), onDeleted: onClearCountry),
            ),
          if (sellerType != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(label: context.t('seller_$sellerType'), onDeleted: onClearSeller),
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
      deleteIconColor: PetsyColors.primaryDark,
      backgroundColor: PetsyColors.primarySoft,
      side: BorderSide(color: PetsyColors.primary.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
  }
}

class _FeaturedGuardCard extends StatelessWidget {
  const _FeaturedGuardCard({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final role = pet.guardRole != null && pet.guardRole!.isNotEmpty
        ? context.t('guard_role_${pet.guardRole}')
        : context.t('guard_dog_badge');
    return PetsyPressScale(
      onTap: () => context.push('/pet/${pet.id}'),
      child: SizedBox(
        width: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(pet.image),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0xCC1A2330)],
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
                    PetsyMetaBadge(label: role, tone: PetsyMetaTone.accent),
                    const SizedBox(height: 6),
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    if (pet.price != null)
                      Text(
                        formatPrice(pet.price!, currency: pet.currency),
                        style: const TextStyle(color: Color(0xFFB8F0E6), fontWeight: FontWeight.w800, fontSize: 13),
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

class _GuardListingCard extends StatelessWidget {
  const _GuardListingCard({required this.pet, required this.index});

  final Pet pet;
  final int index;

  @override
  Widget build(BuildContext context) {
    final role = pet.guardRole != null && pet.guardRole!.isNotEmpty
        ? context.t('guard_role_${pet.guardRole}')
        : context.t('guard_dog_badge');
    final place = [
      if (pet.country != null && pet.country!.isNotEmpty) context.t('country_${pet.country}'),
      if (pet.location != null && pet.location!.trim().isNotEmpty) pet.location!.trim(),
    ].join(' · ');
    final seller = pet.sellerType != null && pet.sellerType!.isNotEmpty ? context.t('seller_${pet.sellerType}') : null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + (index.clamp(0, 8) * 40)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: PetsyPressScale(
        onTap: () => context.push('/pet/${pet.id}'),
        child: Material(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              border: Border.all(color: PetsyColors.border),
              boxShadow: PetsyShadows.soft,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(PetsyRadius.xl),
                      bottomStart: Radius.circular(PetsyRadius.xl),
                    ),
                    child: SizedBox(
                      width: 118,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetImage(pet.image),
                          PositionedDirectional(
                            top: 8,
                            start: 8,
                            child: PetsyMetaBadge(label: role, tone: PetsyMetaTone.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                                  style: PetsyType.cardTitle.copyWith(fontSize: 16),
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
                            joinIsolated(
                              [
                                pet.breed ?? context.t('dog'),
                                if ((pet.age ?? '').trim().isNotEmpty) petAgeLabel(context, pet.age),
                              ],
                              ' · ',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.meta,
                          ),
                          if (place.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.public_rounded, size: 14, color: PetsyColors.accent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    place,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (seller != null) PetsyMetaBadge(label: seller, tone: PetsyMetaTone.primary),
                              if (pet.vaccinated)
                                PetsyMetaBadge(label: context.t('vaccinated'), tone: PetsyMetaTone.neutral),
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (pet.price != null)
                                Expanded(
                                  child: Text(
                                    formatPrice(pet.price!, currency: pet.currency),
                                    style: PetsyType.price.copyWith(fontSize: 16),
                                  ),
                                )
                              else
                                const Spacer(),
                              Text(
                                context.t('guard_dogs_view'),
                                style: const TextStyle(
                                  color: PetsyColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 18, color: PetsyColors.primaryDark),
                            ],
                          ),
                        ],
                      ),
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
