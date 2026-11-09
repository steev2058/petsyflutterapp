import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/cards.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/common.dart';
import '../../widgets/filter_bar.dart';
import '../auth/auth_screens.dart';
import '../pets/health_screens.dart';

String _petQuery(String? petId) => (petId == null || petId.isEmpty) ? '' : '?petId=$petId';

enum _VetSort { rating, experience, name }

class VetsScreen extends StatefulWidget {
  const VetsScreen({super.key, this.petId});

  final String? petId;

  @override
  State<VetsScreen> createState() => _VetsScreenState();
}

class _VetsScreenState extends State<VetsScreen> {
  final _query = TextEditingController();
  String _q = '';
  String? _city;
  _VetSort _sort = _VetSort.rating;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Vet> _filterAndSort(List<Vet> vets) {
    final q = _q.trim().toLowerCase();
    final filtered = vets.where((v) {
      if (_city != null && (v.city ?? '').trim() != _city) return false;
      if (q.isEmpty) return true;
      final hay = [v.name, v.specialty, v.clinicName ?? '', v.city ?? ''].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case _VetSort.rating:
          final byRating = b.rating.compareTo(a.rating);
          if (byRating != 0) return byRating;
          return b.ratingCount.compareTo(a.ratingCount);
        case _VetSort.experience:
          return b.experienceYears.compareTo(a.experienceYears);
        case _VetSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return filtered;
  }

  void _clearFilters() {
    _query.clear();
    setState(() {
      _q = '';
      _city = null;
      _sort = _VetSort.rating;
    });
  }

  String _sortLabel(_VetSort sort) => context.t(switch (sort) {
        _VetSort.rating => 'vets_sort_rating',
        _VetSort.experience => 'vets_sort_experience',
        _VetSort.name => 'vets_sort_name',
      });

  Future<void> _openFilters(List<String> cities) async {
    var draftCity = _city;
    var draftSort = _sort;
    final applied = await showPetsyFiltersSheet(
      context: context,
      title: context.t('filters'),
      onReset: () {
        draftCity = null;
        draftSort = _VetSort.rating;
      },
      body: (ctx, setModal) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetsyChoiceField<_VetSort>(
            label: context.t('sort'),
            prefixIcon: Icons.sort_rounded,
            value: draftSort,
            options: [
              for (final s in _VetSort.values)
                PetsyChoiceOption(
                  value: s,
                  label: _sortLabel(s),
                  icon: switch (s) {
                    _VetSort.rating => Icons.star_rounded,
                    _VetSort.experience => Icons.workspace_premium_outlined,
                    _VetSort.name => Icons.sort_by_alpha_rounded,
                  },
                ),
            ],
            onChanged: (v) => setModal(() => draftSort = v),
          ),
          if (cities.isNotEmpty) ...[
            const SizedBox(height: 12),
            PetsyChoiceField<String>(
              label: context.t('city'),
              prefixIcon: Icons.location_city_outlined,
              value: draftCity ?? '__all__',
              options: [
                PetsyChoiceOption(
                  value: '__all__',
                  label: context.t('vets_all_cities'),
                  icon: Icons.public_rounded,
                ),
                for (final c in cities)
                  PetsyChoiceOption(
                    value: c,
                    label: c,
                    icon: Icons.location_on_outlined,
                  ),
              ],
              onChanged: (v) => setModal(() => draftCity = v == '__all__' ? null : v),
            ),
          ],
        ],
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _city = draftCity;
        _sort = draftSort;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingForPet = widget.petId != null && widget.petId!.isNotEmpty;
    return PetsyPage(
      appBar: AppBar(title: Text(context.t(bookingForPet ? 'choose_vet_for_pet' : 'vets'))),
      child: AsyncView<List<Vet>>(
        loader: () => context.api.vets(),
        builder: (context, vets, reload) {
          final cities = {
            for (final v in vets)
              if ((v.city ?? '').trim().isNotEmpty) v.city!.trim(),
          }.toList()
            ..sort();
          final visible = _filterAndSort(vets);
          final rated = vets.where((v) => v.ratingCount > 0).length;
          final countLabel = visible.length == 1
              ? context.t('vets_count_one')
              : context.t('vets_count').replaceAll('{count}', '${visible.length}');
          final activeFilterCount =
              (_city != null ? 1 : 0) + (_sort != _VetSort.rating ? 1 : 0);

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _VetsHero()),
                if (bookingForPet)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 0),
                      child: _PetBookingBanner(),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _VetsStatsRow(
                      totalLabel: countLabel,
                      ratedLabel: context.t('vets_stat_rated').replaceAll('{count}', '$rated'),
                      citiesLabel: context.t('vets_stat_cities').replaceAll('{count}', '${cities.length}'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('vets_search_hint'),
                    margin: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    onChanged: (v) => setState(() => _q = v),
                    onClear: () => setState(() => _q = ''),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsyFilterBar(
                    onOpen: () => _openFilters(cities),
                    activeCount: activeFilterCount,
                    onClearAll: activeFilterCount > 0
                        ? () => setState(() {
                              _city = null;
                              _sort = _VetSort.rating;
                            })
                        : null,
                    chips: [
                      if (_sort != _VetSort.rating)
                        PetsyActiveFilter(
                          label: _sortLabel(_sort),
                          icon: Icons.sort_rounded,
                          onClear: () => setState(() => _sort = _VetSort.rating),
                        ),
                      if (_city != null)
                        PetsyActiveFilter(
                          label: _city!,
                          icon: Icons.location_on_outlined,
                          onClear: () => setState(() => _city = null),
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
                        16,
                        PetsySpacing.page,
                        PetsySpacing.listBottom,
                      ),
                      child: _VetsEmptyState(
                        canClear: vets.isNotEmpty,
                        onClear: _clearFilters,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      12,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => VetCard(vet: visible[i], petId: widget.petId),
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

class _VetsHero extends StatefulWidget {
  const _VetsHero();

  @override
  State<_VetsHero> createState() => _VetsHeroState();
}

class _VetsHeroState extends State<_VetsHero> with SingleTickerProviderStateMixin {
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
                    Color(0xFF1F7A6E),
                    PetsyColors.accent,
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
                child: Icon(Icons.medical_services_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
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
                        context.t('vets_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('vets_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('vets_subtitle'),
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

class _VetsStatsRow extends StatelessWidget {
  const _VetsStatsRow({
    required this.totalLabel,
    required this.ratedLabel,
    required this.citiesLabel,
  });

  final String totalLabel;
  final String ratedLabel;
  final String citiesLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _VetsStatTile(icon: Icons.medical_services_outlined, label: totalLabel, color: PetsyColors.accent)),
        const SizedBox(width: 8),
        Expanded(child: _VetsStatTile(icon: Icons.star_rounded, label: ratedLabel, color: PetsyColors.warning)),
        const SizedBox(width: 8),
        Expanded(child: _VetsStatTile(icon: Icons.location_city_outlined, label: citiesLabel, color: PetsyColors.primaryDark)),
      ],
    );
  }
}

class _VetsStatTile extends StatelessWidget {
  const _VetsStatTile({required this.icon, required this.label, required this.color});

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

class _VetsEmptyState extends StatelessWidget {
  const _VetsEmptyState({required this.canClear, required this.onClear});

  final bool canClear;
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
                color: PetsyColors.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: PetsyColors.accent.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.medical_services_outlined, size: 36, color: PetsyColors.accent),
            ),
            const SizedBox(height: 16),
            Text(context.t('vets_empty_title'), textAlign: TextAlign.center, style: PetsyType.section.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              context.t('vets_empty_body'),
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
            ),
            if (canClear) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onClear,
                  child: Text(context.t('vets_empty_browse')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PetBookingBanner extends StatelessWidget {
  const _PetBookingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PetsyColors.primarySoft,
            PetsyColors.mist,
            Colors.white.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.pets_rounded, color: PetsyColors.primaryDark, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.t('choose_vet_for_pet'),
              style: PetsyType.subtitle.copyWith(color: PetsyColors.primaryDark, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _VetAvatar extends StatelessWidget {
  const _VetAvatar({required this.vet, this.size = 72});

  final Vet vet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasImage = vet.image != null && vet.image!.startsWith('http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? NetImage(vet.image, icon: Icons.medical_services_rounded)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [PetsyColors.accentSoft, Color(0xFFD3EEE9)],
                  ),
                ),
                child: Icon(Icons.medical_services_rounded, color: PetsyColors.accent, size: size * 0.42),
              ),
      ),
    );
  }
}

class VetDetailScreen extends StatelessWidget {
  const VetDetailScreen({super.key, required this.vetId, this.petId});

  final String vetId;
  final String? petId;

  String _mapQuery(Vet vet) {
    final parts = [
      if ((vet.clinicName ?? '').trim().isNotEmpty) vet.clinicName!.trim(),
      if ((vet.location ?? '').trim().isNotEmpty) vet.location!.trim(),
      if ((vet.city ?? '').trim().isNotEmpty) vet.city!.trim(),
      if (vet.name.trim().isNotEmpty) vet.name.trim(),
    ];
    return parts.toSet().join(', ');
  }

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      context.snack(context.t('vet_open_failed'), error: true);
    }
  }

  Future<void> _call(BuildContext context, Vet vet) async {
    final phone = (vet.phone ?? '').trim();
    if (phone.isEmpty) {
      context.snack(context.t('vet_no_phone'), error: true);
      return;
    }
    await _openUri(context, Uri(scheme: 'tel', path: phone));
  }

  Future<void> _directions(BuildContext context, Vet vet) async {
    final query = _mapQuery(vet);
    if (query.trim().isEmpty) {
      context.snack(context.t('vet_no_location'), error: true);
      return;
    }
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encoded&travelmode=driving');
    await _openUri(context, uri);
  }

  Future<void> _message(BuildContext context, Vet vet) async {
    if (!context.requireLogin() || vet.userId == null) return;
    try {
      final id = await context.api.startConversation(otherUserId: vet.userId!, message: '${context.t('hello')} 👋');
      if (context.mounted) context.push('/chat/$id');
    } catch (e) {
      if (context.mounted) context.snack(context.errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('vets'))),
      child: AsyncView<Vet>(
        loader: () => context.api.vet(vetId),
        builder: (context, vet, _) {
          final location = [vet.location, vet.city].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
          final hasPhone = (vet.phone ?? '').trim().isNotEmpty;
          final hasMap = _mapQuery(vet).trim().isNotEmpty;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1F7A6E), PetsyColors.accent, PetsyColors.secondary],
                        ),
                        borderRadius: BorderRadius.circular(PetsyRadius.xl),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _VetAvatar(vet: vet, size: 104),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            vet.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                          if (vet.specialty.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              vet.specialty,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _VetStat(
                                icon: Icons.star_rounded,
                                iconColor: PetsyColors.warning,
                                value: vet.rating.toStringAsFixed(1),
                                label: context.t('vet_reviews').replaceAll('{count}', '${vet.ratingCount}'),
                                onDark: true,
                              ),
                              const SizedBox(width: 10),
                              _VetStat(
                                icon: Icons.workspace_premium_rounded,
                                iconColor: PetsyColors.primary,
                                value: '${vet.experienceYears}',
                                label: context.t('years_experience'),
                                onDark: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: context.t('vet_quick_actions'),
                      child: Row(
                        children: [
                          Expanded(
                            child: _VetQuickAction(
                              icon: Icons.phone_rounded,
                              label: context.t('vet_call_quick'),
                              color: PetsyColors.success,
                              enabled: hasPhone,
                              onTap: () => _call(context, vet),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _VetQuickAction(
                              icon: Icons.directions_rounded,
                              label: context.t('vet_directions'),
                              color: PetsyColors.primary,
                              enabled: hasMap,
                              onTap: () => _directions(context, vet),
                            ),
                          ),
                          if (vet.userId != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _VetQuickAction(
                                icon: Icons.chat_bubble_rounded,
                                label: context.t('message'),
                                color: PetsyColors.accent,
                                enabled: true,
                                onTap: () => _message(context, vet),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (vet.clinicName != null || location.isNotEmpty || hasPhone) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        title: context.t('vet_clinic_info'),
                        child: Column(
                          children: [
                            if (vet.clinicName != null)
                              _InfoRow(icon: Icons.local_hospital_outlined, text: vet.clinicName!),
                            if (location.isNotEmpty)
                              _InfoRow(
                                icon: Icons.location_on_outlined,
                                text: location,
                                actionIcon: Icons.directions_rounded,
                                actionTooltip: context.t('vet_directions'),
                                onAction: () => _directions(context, vet),
                              ),
                            if (hasPhone)
                              _InfoRow(
                                icon: Icons.phone_outlined,
                                text: vet.phone!,
                                textDirection: TextDirection.ltr,
                                actionIcon: Icons.call_rounded,
                                actionTooltip: context.t('vet_call_quick'),
                                onAction: () => _call(context, vet),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (vet.bio != null && vet.bio!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        title: context.t('vet_about'),
                        child: Text(vet.bio!, style: const TextStyle(height: 1.6, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (vet.services.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        title: context.t('vet_services'),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in vet.services)
                              PetsyMetaBadge(
                                label: s,
                                icon: Icons.check_circle_outline_rounded,
                                tone: PetsyMetaTone.accent,
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 72),
                  ],
                ),
              ),
              BottomActionBar(
                child: Row(
                  children: [
                    if (hasPhone) ...[
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: PetsyColors.success,
                            side: BorderSide(color: PetsyColors.success.withValues(alpha: 0.45)),
                          ),
                          onPressed: () => _call(context, vet),
                          child: Tooltip(
                            message: context.t('vet_call_quick'),
                            child: const Icon(Icons.phone_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasMap) ...[
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: PetsyColors.primaryDark,
                            side: const BorderSide(color: PetsyColors.border),
                          ),
                          onPressed: () => _directions(context, vet),
                          child: Tooltip(
                            message: context.t('vet_directions'),
                            child: const Icon(Icons.directions_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (vet.userId != null) ...[
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => _message(context, vet),
                          child: Tooltip(
                            message: context.t('message'),
                            child: const Icon(Icons.chat_bubble_outline_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          if (!context.requireLogin()) return;
                          context.push('/book-appointment/${vet.id}${_petQuery(petId)}', extra: vet);
                        },
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(context.t('book_appointment')),
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

class _VetQuickAction extends StatelessWidget {
  const _VetQuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: PetsyShadows.soft,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VetStat extends StatelessWidget {
  const _VetStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.onDark = false,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.16) : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.22) : PetsyColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: onDark ? Colors.white : iconColor, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: onDark ? Colors.white : PetsyColors.text,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: onDark ? Colors.white.withValues(alpha: 0.85) : PetsyColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    this.textDirection,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final TextDirection? textDirection;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: PetsyColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: PetsyColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                text,
                textDirection: textDirection,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (actionIcon != null && onAction != null)
            Tooltip(
              message: actionTooltip ?? '',
              child: Material(
                color: PetsyColors.mist,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAction,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(actionIcon, size: 18, color: PetsyColors.primaryDark),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _reasonKeys = ['reason_checkup', 'reason_vaccination', 'reason_illness', 'reason_grooming'];

/// Reasons are stored as text in the booker's language; show known ones in the current language.
String appointmentReasonLabel(BuildContext context, String raw) {
  final text = raw.trim();
  for (final key in _reasonKeys) {
    if (text == translate('ar', key) || text == translate('en', key)) return context.t(key);
  }
  return raw;
}

String appointmentPaymentLabel(BuildContext context, Appointment a) => switch (a.paymentStatus) {
      'paid' => context.t('paid'),
      'pending' => context.t('payment_pending'),
      'pay_at_clinic' => context.t('pay_at_clinic_status'),
      _ => context.t('unpaid'),
    };

Color appointmentPaymentColor(Appointment a) => switch (a.paymentStatus) {
      'paid' => PetsyColors.success,
      _ when a.status == 'cancelled' => PetsyColors.textSecondary,
      _ => PetsyColors.primaryDark,
    };

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, required this.vetId, this.vet, this.initialPetId});

  final String vetId;
  final Vet? vet;
  final String? initialPetId;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  static const _morning = ['09:00', '10:00', '11:00', '12:00'];
  static const _afternoon = ['14:00', '15:00', '16:00', '17:00'];
  static const _reasons = <(String, IconData)>[
    ('reason_checkup', Icons.health_and_safety_outlined),
    ('reason_vaccination', Icons.vaccines_outlined),
    ('reason_illness', Icons.sick_outlined),
    ('reason_grooming', Icons.content_cut_rounded),
  ];
  static const _stripDays = 14;

  late DateTime _date = _today.add(const Duration(days: 1));
  String _time = _morning.first;
  String _reason = _reasons.first.$1;
  late String? _petId = widget.initialPetId;
  final _notes = TextEditingController();
  late final Future<List<Pet>> _pets = context.api.myPets();
  bool _busy = false;
  Set<String> _booked = const {};
  bool get _petLocked => widget.initialPetId != null && widget.initialPetId!.isNotEmpty;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _loadBooked();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  static String _dateKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  Future<void> _loadBooked() async {
    try {
      final booked = await context.api.bookedSlots(widget.vetId, start: _dateKey(_today));
      if (!mounted) return;
      setState(() {
        _booked = booked;
        _ensureValidTime();
      });
    } catch (_) {
      // Availability is a hint; the server still rejects taken slots on submit.
    }
  }

  /// Booked by someone, or already past for today.
  Set<String> _unavailableOn(DateTime day) {
    final key = _dateKey(day);
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(day, now);
    return {
      for (final t in [..._morning, ..._afternoon])
        if (_booked.contains('$key $t') ||
            (isToday && int.parse(t.split(':').first) <= now.hour))
          t,
    };
  }

  /// Keeps the selection on a free slot; empty when the whole day is taken.
  void _ensureValidTime() {
    final unavailable = _unavailableOn(_date);
    if (_time.isNotEmpty && !unavailable.contains(_time)) return;
    _time = [..._morning, ..._afternoon].firstWhere((t) => !unavailable.contains(t), orElse: () => '');
  }

  void _selectDate(DateTime day) {
    setState(() {
      _date = day;
      _ensureValidTime();
    });
  }

  Future<void> _pickFromCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 90)),
    );
    if (picked != null) _selectDate(picked);
  }

  Future<void> _submit() async {
    if (_time.isEmpty) {
      context.snack(context.t('book_day_full'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await context.api.createAppointment({
        'vet_id': widget.vetId,
        'pet_id': _petId,
        'date': _date.toIso8601String().split('T').first,
        'time': _time,
        'reason': context.t(_reason),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      await PushNotificationService.instance.scheduleAppointmentReminder(
        appointment: created,
        title: context.t('appointment_reminder'),
        body: '${context.t(_reason)} · ${created.when(Localizations.localeOf(context).languageCode)}',
      );
      if (!mounted) return;
      context.snack(context.t('appointment_booked'), success: true, icon: Icons.event_available_rounded);
      final confirmed = await showConfirmAppointmentSheet(
        context,
        appointment: created,
        vetName: widget.vet?.name,
      );
      if (!mounted) return;
      if (confirmed == true) {
        context.snack(context.t('payment_choice_saved'));
        await PushNotificationService.instance.showNow(
          title: context.t('payment_choice_saved'),
          body: '${widget.vet?.name ?? context.t('vets')} · ${created.when(Localizations.localeOf(context).languageCode)}',
        );
      }
      if (!mounted) return;
      context.pushReplacement('/appointments');
    } catch (e) {
      if (!mounted) return;
      context.snack(context.errorText(e), error: true);
      if (e is ApiException && e.code == 'SLOT_TAKEN') await _loadBooked();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dayLabel(BuildContext context, DateTime day) {
    final diff = day.difference(_today).inDays;
    if (diff == 0) return context.t('vet_today');
    if (diff == 1) return context.t('vet_tomorrow');
    return DateFormat.E(Localizations.localeOf(context).languageCode).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final days = [for (var i = 0; i < _stripDays; i++) _today.add(Duration(days: i))];
    final unavailable = _unavailableOn(_date);
    final freeCount = [..._morning, ..._afternoon].where((t) => !unavailable.contains(t)).length;
    final dateInStrip = days.any((d) => DateUtils.isSameDay(d, _date));

    return PetsyPage(
      appBar: AppBar(title: Text(context.t('book_appointment'))),
      bottomNavigationBar: _BookConfirmBar(
        busy: _busy,
        summary: _time.isEmpty ? context.formatDate(_date) : '${context.formatDate(_date)} · $_time',
        reason: context.t(_reason),
        enabled: _time.isNotEmpty,
        hint: context.t('book_pick_slot_hint'),
        onPressed: _submit,
      ),
      child: FutureBuilder<List<Pet>>(
        future: _pets,
        builder: (context, snapshot) {
          final pets = snapshot.data ?? const <Pet>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 28),
            children: [
              const _BookHero(),
              if (widget.vet != null) ...[
                const SizedBox(height: 14),
                _BookingVetHeader(vet: widget.vet!),
              ],
              const SizedBox(height: 14),
              _BookStepsRow(
                hasTime: _time.isNotEmpty,
                hasPetSection: pets.isNotEmpty,
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: context.t('book_pick_day'),
                icon: Icons.calendar_month_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 86,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final day = days[i];
                          final selected = DateUtils.isSameDay(day, _date);
                          return _DayChip(
                            top: _dayLabel(context, day),
                            day: '${day.day}',
                            bottom: DateFormat.MMM(locale).format(day),
                            selected: selected,
                            onTap: () => _selectDate(day),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _pickFromCalendar,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(
                          dateInStrip
                              ? context.t('book_calendar')
                              : '${context.t('book_calendar')} · ${context.formatDate(_date)}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: context.t('book_pick_time'),
                icon: Icons.schedule_rounded,
                trailing: Text(
                  context.t('book_slots_free').replaceAll('{count}', '$freeCount'),
                  style: const TextStyle(
                    color: PetsyColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_time.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: PetsyColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(PetsyRadius.md),
                          border: Border.all(color: PetsyColors.error.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          context.t('book_day_full'),
                          style: const TextStyle(color: PetsyColors.error, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _TimeGroup(
                      label: context.t('book_morning'),
                      icon: Icons.wb_sunny_rounded,
                      times: _morning,
                      selected: _time,
                      unavailable: unavailable,
                      onSelect: (t) => setState(() => _time = t),
                    ),
                    const SizedBox(height: 14),
                    _TimeGroup(
                      label: context.t('book_afternoon'),
                      icon: Icons.wb_twilight_rounded,
                      times: _afternoon,
                      selected: _time,
                      unavailable: unavailable,
                      onSelect: (t) => setState(() => _time = t),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: context.t('reason'),
                icon: Icons.healing_outlined,
                child: PetsyChoiceField<String>(
                  label: context.t('reason'),
                  prefixIcon: Icons.healing_outlined,
                  required: true,
                  value: _reason,
                  options: [
                    for (final (key, icon) in _reasons)
                      PetsyChoiceOption(
                        value: key,
                        label: context.t(key),
                        icon: icon,
                      ),
                  ],
                  onChanged: (v) => setState(() => _reason = v),
                ),
              ),
              if (pets.isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: context.t('book_pet'),
                  icon: Icons.pets_rounded,
                  child: _petLocked
                      ? _LockedPetRow(name: pets.where((p) => p.id == _petId).firstOrNull?.name ?? '')
                      : PetsyChoiceField<String>(
                          label: context.t('book_pet'),
                          prefixIcon: Icons.pets_rounded,
                          value: _petId ?? '__none__',
                          options: [
                            for (final p in pets)
                              PetsyChoiceOption(
                                value: p.id,
                                label: p.name,
                                icon: Icons.pets_rounded,
                              ),
                            PetsyChoiceOption(
                              value: '__none__',
                              label: context.t('book_pet_none'),
                              icon: Icons.remove_circle_outline_rounded,
                            ),
                          ],
                          onChanged: (v) => setState(() => _petId = v == '__none__' ? null : v),
                        ),
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: context.t('notes'),
                icon: Icons.notes_rounded,
                child: TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: context.t('book_notes_hint'),
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: Icon(Icons.edit_note_rounded),
                    ),
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

class _BookHero extends StatelessWidget {
  const _BookHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF1F7A6E), PetsyColors.accent, Color(0xFF56B8A8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -18,
              bottom: -24,
              child: Icon(Icons.event_available_rounded, size: 108, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned(
              right: -12,
              top: -16,
              child: Icon(Icons.pets_rounded, size: 84, color: Colors.white.withValues(alpha: 0.1)),
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
                      context.t('book_hero_tag'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t('book_hero_title'),
                    style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.t('book_hero_body'),
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

class _BookStepsRow extends StatelessWidget {
  const _BookStepsRow({required this.hasTime, required this.hasPetSection});

  final bool hasTime;
  final bool hasPetSection;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, IconData, bool)>[
      (context.t('book_step_when'), Icons.schedule_rounded, hasTime),
      (context.t('book_step_why'), Icons.healing_outlined, true),
      if (hasPetSection) (context.t('book_step_who'), Icons.pets_rounded, true),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: steps[i].$3 ? PetsyColors.accentSoft : PetsyColors.surface,
                borderRadius: BorderRadius.circular(PetsyRadius.md),
                border: Border.all(
                  color: steps[i].$3 ? PetsyColors.accent.withValues(alpha: 0.35) : PetsyColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    steps[i].$2,
                    size: 16,
                    color: steps[i].$3 ? PetsyColors.accent : PetsyColors.textLight,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      steps[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: steps[i].$3 ? PetsyColors.accent : PetsyColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BookConfirmBar extends StatelessWidget {
  const _BookConfirmBar({
    required this.busy,
    required this.summary,
    required this.reason,
    required this.enabled,
    required this.hint,
    required this.onPressed,
  });

  final bool busy;
  final String summary;
  final String reason;
  final bool enabled;
  final String hint;
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
                      enabled ? Icons.event_available_rounded : Icons.event_busy_rounded,
                      color: PetsyColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enabled ? summary : hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: enabled ? PetsyColors.text : PetsyColors.textSecondary,
                          ),
                        ),
                        if (enabled)
                          Text(
                            reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PetsyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: (!enabled || busy) ? null : onPressed,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(context.t('book_confirm_cta')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingVetHeader extends StatelessWidget {
  const _BookingVetHeader({required this.vet});

  final Vet vet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PetsySpacing.md),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: PetsyColors.border),
        boxShadow: PetsyShadows.soft,
      ),
      child: Row(
        children: [
          _VetAvatar(vet: vet, size: 56),
          const SizedBox(width: PetsySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vet.name, style: PetsyType.cardTitle.copyWith(fontSize: 16)),
                if (vet.specialty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    vet.specialty,
                    style: PetsyType.subtitle.copyWith(
                      color: PetsyColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if ((vet.city ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: PetsyColors.textLight),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          vet.city!,
                          style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PetsyRating(vet.rating),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.top,
    required this.day,
    required this.bottom,
    required this.selected,
    required this.onTap,
  });

  final String top;
  final String day;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : PetsyColors.text;
    final sub = selected ? Colors.white.withValues(alpha: 0.88) : PetsyColors.textSecondary;
    return PetsyPressScale(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 68,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [PetsyColors.primary, PetsyColors.primaryDark],
                )
              : null,
          color: selected ? null : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: selected ? PetsyColors.primaryDark : PetsyColors.border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: PetsyColors.primary.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(top, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sub)),
            Text(day, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg, height: 1.15)),
            Text(bottom, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
          ],
        ),
      ),
    );
  }
}

class _TimeGroup extends StatelessWidget {
  const _TimeGroup({
    required this.label,
    required this.icon,
    required this.times,
    required this.selected,
    required this.onSelect,
    this.unavailable = const {},
  });

  final String label;
  final IconData icon;
  final List<String> times;
  final String selected;
  final ValueChanged<String> onSelect;
  final Set<String> unavailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: PetsyColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: PetsyColors.accent),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < times.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _TimeSlotChip(
                  time: times[i],
                  selected: selected == times[i],
                  unavailable: unavailable.contains(times[i]),
                  onTap: () => onSelect(times[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TimeSlotChip extends StatelessWidget {
  const _TimeSlotChip({
    required this.time,
    required this.selected,
    required this.unavailable,
    required this.onTap,
  });

  final String time;
  final bool selected;
  final bool unavailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: unavailable ? null : onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [PetsyColors.primary, PetsyColors.primaryDark],
                )
              : null,
          color: selected
              ? null
              : unavailable
                  ? PetsyColors.border.withValues(alpha: 0.35)
                  : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: selected
                ? PetsyColors.primaryDark
                : unavailable
                    ? PetsyColors.border.withValues(alpha: 0.5)
                    : PetsyColors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: PetsyColors.primary.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          time,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: selected
                ? Colors.white
                : unavailable
                    ? PetsyColors.textLight
                    : PetsyColors.text,
            decoration: unavailable ? TextDecoration.lineThrough : null,
            decorationColor: PetsyColors.textLight,
          ),
        ),
      ),
    );
  }
}

class _LockedPetRow extends StatelessWidget {
  const _LockedPetRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PetsyColors.primarySoft,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.pets_rounded, color: PetsyColors.primaryDark, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${context.t('appointment_for_pet')} $name',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const Icon(Icons.lock_outline_rounded, size: 16, color: PetsyColors.primaryDark),
        ],
      ),
    );
  }
}

enum _ApptFilter { upcoming, past, cancelled }

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  _ApptFilter _filter = _ApptFilter.upcoming;

  Future<(List<Appointment>, Map<String, String>, Map<String, String>)> _load() async {
    final api = context.api;
    final appointments = await api.appointments();
    final vets = await api.vets().catchError((_) => <Vet>[]);
    final pets = await api.myPets().catchError((_) => <Pet>[]);
    return (
      appointments,
      {for (final v in vets) v.id: v.name},
      {for (final p in pets) p.id: p.name},
    );
  }

  static DateTime? _dateOf(Appointment a) => DateTime.tryParse(a.date);

  bool _matches(Appointment a) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = _dateOf(a);
    final isPastDate = date != null && date.isBefore(today);
    return switch (_filter) {
      _ApptFilter.cancelled => a.status == 'cancelled',
      _ApptFilter.past => a.status != 'cancelled' && (a.status == 'completed' || isPastDate),
      _ApptFilter.upcoming => a.status != 'cancelled' && a.status != 'completed' && !isPastDate,
    };
  }

  Future<void> _cancel(Appointment a, Future<void> Function() reload) async {
    final ok = await confirmAction(
      context,
      title: context.t('cancel_appointment'),
      message: context.t('appt_cancel_confirm'),
      confirmLabel: context.t('cancel_appointment'),
      cancelLabel: context.t('appt_keep'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.cancelAppointment(a.id);
      await PushNotificationService.instance.cancelAppointment(a.id);
      await reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _confirm(Appointment a, String? vetName, Future<void> Function() reload) async {
    final ok = await showConfirmAppointmentSheet(context, appointment: a, vetName: vetName);
    if (ok != true || !mounted) return;
    context.snack(context.t('payment_choice_saved'));
    final reminderTitle = context.t('appointment_reminder');
    final confirmedTitle = context.t('payment_choice_saved');
    final fallbackVet = context.t('vets');
    final when = a.when(Localizations.localeOf(context).languageCode);
    await PushNotificationService.instance.scheduleAppointmentReminder(
      appointment: a,
      title: reminderTitle,
      body: '${appointmentReasonLabel(context, a.reason)} · $when',
    );
    await PushNotificationService.instance.showNow(
      title: confirmedTitle,
      body: '${vetName ?? fallbackVet} · $when',
    );
    await reload();
  }

  Future<void> _addToHealth(Appointment a, String? vetName) async {
    final reason = a.reason.toLowerCase();
    final type = (reason.contains('vaccin') || reason.contains('تطعيم')) ? 'vaccination' : 'checkup';
    await showAddHealthFromAppointment(
      context,
      petId: a.petId!,
      title: '${context.t('appointments')}: ${appointmentReasonLabel(context, a.reason)}',
      date: a.date,
      vetName: vetName,
      appointmentId: a.id,
      recordType: type,
    );
  }

  bool _isToday(Appointment a) {
    final date = _dateOf(a);
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final filters = <(_ApptFilter, String, IconData)>[
      (_ApptFilter.upcoming, 'appt_filter_upcoming', Icons.event_available_rounded),
      (_ApptFilter.past, 'appt_filter_past', Icons.history_rounded),
      (_ApptFilter.cancelled, 'appt_filter_cancelled', Icons.event_busy_rounded),
    ];

    return PetsyPage(
      appBar: AppBar(title: Text(context.t('appointments'))),
      child: AsyncView<(List<Appointment>, Map<String, String>, Map<String, String>)>(
        loader: _load,
        builder: (context, data, reload) {
          final (items, vetNames, petNames) = data;
          PushNotificationService.instance.syncAppointments(
            appointments: items,
            title: context.t('appointment_reminder'),
            bodyFor: (a) =>
                '${appointmentReasonLabel(context, a.reason)} · ${a.when(Localizations.localeOf(context).languageCode)}',
          );

          final upcomingCount = items.where((a) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final date = _dateOf(a);
            final isPastDate = date != null && date.isBefore(today);
            return a.status != 'cancelled' && a.status != 'completed' && !isPastDate;
          }).length;
          final pastCount = items.where((a) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final date = _dateOf(a);
            final isPastDate = date != null && date.isBefore(today);
            return a.status != 'cancelled' && (a.status == 'completed' || isPastDate);
          }).length;
          final cancelledCount = items.where((a) => a.status == 'cancelled').length;

          final visible = items.where(_matches).toList()
            ..sort((a, b) {
              final cmp = '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}');
              return _filter == _ApptFilter.upcoming ? cmp : -cmp;
            });

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _AppointmentsHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _AppointmentsStatsRow(
                      upcoming: upcomingCount,
                      past: pastCount,
                      cancelled: cancelledCount,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsyFilterRow(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 4),
                    children: [
                      for (final (value, label, icon) in filters)
                        PetsyPill(
                          label: context.t(label),
                          icon: icon,
                          selected: _filter == value,
                          count: switch (value) {
                            _ApptFilter.upcoming => upcomingCount,
                            _ApptFilter.past => pastCount,
                            _ApptFilter.cancelled => cancelledCount,
                          },
                          onTap: () => setState(() => _filter = value),
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
                        PetsySpacing.listBottom,
                      ),
                      child: _AppointmentsEmptyState(
                        showFindVet: _filter == _ApptFilter.upcoming,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      8,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final a = visible[i];
                        final vetName = vetNames[a.vetId];
                        final canCancel = a.status == 'pending' || a.status == 'confirmed';
                        return _AppointmentCard(
                          appointment: a,
                          vetName: vetName ?? context.t('vets'),
                          petName: a.petId == null ? null : petNames[a.petId!],
                          isToday: _isToday(a) && _filter == _ApptFilter.upcoming,
                          onOpenVet: a.vetId.isEmpty ? null : () => context.push('/vet/${a.vetId}'),
                          onConfirm: a.needsPaymentConfirm && _filter == _ApptFilter.upcoming
                              ? () => _confirm(a, vetName, reload)
                              : null,
                          onAddHealth:
                              (a.petId != null && a.petId!.isNotEmpty) ? () => _addToHealth(a, vetName) : null,
                          onCancel: canCancel && _filter == _ApptFilter.upcoming ? () => _cancel(a, reload) : null,
                        );
                      },
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

class _AppointmentsHero extends StatefulWidget {
  const _AppointmentsHero();

  @override
  State<_AppointmentsHero> createState() => _AppointmentsHeroState();
}

class _AppointmentsHeroState extends State<_AppointmentsHero> with SingleTickerProviderStateMixin {
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
                    Color(0xFF1F7A6E),
                    PetsyColors.accent,
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
                child: Icon(Icons.calendar_month_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
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
                        context.t('appointments_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('appointments_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('appointments_subtitle'),
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

class _AppointmentsStatsRow extends StatelessWidget {
  const _AppointmentsStatsRow({
    required this.upcoming,
    required this.past,
    required this.cancelled,
  });

  final int upcoming;
  final int past;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ApptStatTile(
            icon: Icons.event_available_rounded,
            label: context.t('appt_stat_upcoming').replaceAll('{count}', '$upcoming'),
            color: PetsyColors.accent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ApptStatTile(
            icon: Icons.history_rounded,
            label: context.t('appt_stat_past').replaceAll('{count}', '$past'),
            color: PetsyColors.primaryDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ApptStatTile(
            icon: Icons.event_busy_rounded,
            label: context.t('appt_stat_cancelled').replaceAll('{count}', '$cancelled'),
            color: PetsyColors.error,
          ),
        ),
      ],
    );
  }
}

class _ApptStatTile extends StatelessWidget {
  const _ApptStatTile({required this.icon, required this.label, required this.color});

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

class _AppointmentsEmptyState extends StatelessWidget {
  const _AppointmentsEmptyState({required this.showFindVet});

  final bool showFindVet;

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
                color: PetsyColors.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: PetsyColors.accent.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.calendar_month_outlined, size: 36, color: PetsyColors.accent),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('appointments_empty_title'),
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('appointments_empty_body'),
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
            ),
            if (showFindVet) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push('/vets'),
                  icon: const Icon(Icons.medical_services_outlined),
                  label: Text(context.t('appt_find_vet')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.vetName,
    this.petName,
    this.isToday = false,
    this.onOpenVet,
    this.onConfirm,
    this.onAddHealth,
    this.onCancel,
  });

  final Appointment appointment;
  final String vetName;
  final String? petName;
  final bool isToday;
  final VoidCallback? onOpenVet;
  final VoidCallback? onConfirm;
  final VoidCallback? onAddHealth;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final locale = Localizations.localeOf(context).languageCode;
    final date = DateTime.tryParse(a.date);
    final payLabel = appointmentPaymentLabel(context, a);
    final cancelled = a.status == 'cancelled';
    final hasMenu = onAddHealth != null || onCancel != null || onOpenVet != null;
    final menu = PopupMenuButton<String>(
      tooltip: context.t('appt_more'),
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        if (v == 'vet') onOpenVet?.call();
        if (v == 'health') onAddHealth?.call();
        if (v == 'cancel') onCancel?.call();
      },
      itemBuilder: (ctx) => [
        if (onOpenVet != null)
          PopupMenuItem(
            value: 'vet',
            child: Row(
              children: [
                const Icon(Icons.medical_services_outlined, color: PetsyColors.accent),
                const SizedBox(width: 10),
                Text(ctx.t('appt_view_vet')),
              ],
            ),
          ),
        if (onAddHealth != null)
          PopupMenuItem(
            value: 'health',
            child: Row(
              children: [
                const Icon(Icons.monitor_heart_outlined, color: PetsyColors.accent),
                const SizedBox(width: 10),
                Text(ctx.t('add_from_appointment')),
              ],
            ),
          ),
        if (onCancel != null)
          PopupMenuItem(
            value: 'cancel',
            child: Row(
              children: [
                const Icon(Icons.event_busy_rounded, color: PetsyColors.error),
                const SizedBox(width: 10),
                Text(ctx.t('cancel_appointment'), style: const TextStyle(color: PetsyColors.error)),
              ],
            ),
          ),
      ],
    );

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenVet,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(
              color: isToday ? PetsyColors.accent.withValues(alpha: 0.45) : PetsyColors.border,
              width: isToday ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 62,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: cancelled
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [PetsyColors.accentSoft, PetsyColors.mist],
                            ),
                      color: cancelled ? PetsyColors.backgroundAlt : null,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cancelled ? PetsyColors.border : PetsyColors.accent.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          date == null ? '—' : '${date.day}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: cancelled ? PetsyColors.textLight : PetsyColors.primaryDark,
                          ),
                        ),
                        Text(
                          date == null ? a.date : DateFormat.MMM(locale).format(date),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: cancelled ? PetsyColors.textLight : PetsyColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.time,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: PetsyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                vetName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                              ),
                            ),
                            StatusChip(a.status),
                            if (onConfirm == null && hasMenu)
                              SizedBox(width: 32, height: 28, child: Center(child: menu)),
                          ],
                        ),
                        if (isToday) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: PetsyColors.accentSoft,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              context.t('appt_today_badge'),
                              style: const TextStyle(
                                color: PetsyColors.accent,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          appointmentReasonLabel(context, a.reason),
                          style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w700),
                        ),
                        if (petName != null && petName!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.pets_rounded, size: 15, color: PetsyColors.primaryDark),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${context.t('appointment_for_pet')} $petName',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: PetsyColors.mist,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${context.t('appointment_fee')}: ${formatPrice(a.fee)} · $payLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: appointmentPaymentColor(a),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (onConfirm != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: PetsyColors.border),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        onPressed: onConfirm,
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: Text(context.t('confirm_and_pay')),
                      ),
                    ),
                    if (hasMenu) menu,
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showConfirmAppointmentSheet(
  BuildContext context, {
  required Appointment appointment,
  String? vetName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PetsyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
    ),
    builder: (context) => _ConfirmAppointmentSheet(appointment: appointment, vetName: vetName),
  );
}

class _ConfirmAppointmentSheet extends StatefulWidget {
  const _ConfirmAppointmentSheet({required this.appointment, this.vetName});

  final Appointment appointment;
  final String? vetName;

  @override
  State<_ConfirmAppointmentSheet> createState() => _ConfirmAppointmentSheetState();
}

class _ConfirmAppointmentSheetState extends State<_ConfirmAppointmentSheet> {
  String _method = 'cash_on_delivery';
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await context.api.confirmAppointment(widget.appointment.id, paymentMethod: _method);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.t('confirm_and_pay'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              widget.vetName == null || widget.vetName!.isEmpty
                  ? a.when(Localizations.localeOf(context).languageCode)
                  : '${widget.vetName} · ${a.when(Localizations.localeOf(context).languageCode)}',
              style: const TextStyle(color: PetsyColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PetsyColors.mist,
                borderRadius: BorderRadius.circular(PetsyRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: PetsyColors.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.t('appointment_fee'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(formatPrice(a.fee), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(context.t('payment_method'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _PayMethodTile(
              selected: _method == 'cash_on_delivery',
              icon: Icons.storefront_outlined,
              title: context.t('pay_at_clinic'),
              onTap: () => setState(() => _method = 'cash_on_delivery'),
            ),
            const SizedBox(height: 8),
            _PayMethodTile(
              selected: _method == 'shamcash',
              icon: Icons.qr_code_2_rounded,
              title: context.t('shamcash'),
              onTap: () => setState(() => _method = 'shamcash'),
            ),
            const SizedBox(height: 18),
            SubmitButton(label: context.t('confirm_and_pay'), busy: _busy, onPressed: _confirm),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(context.t('cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  const _PayMethodTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PetsyColors.primarySoft : PetsyColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        side: BorderSide(
          color: selected ? PetsyColors.primary : PetsyColors.border,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: PetsyColors.primaryDark),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? PetsyColors.primary : PetsyColors.textLight,
        ),
      ),
    );
  }
}
