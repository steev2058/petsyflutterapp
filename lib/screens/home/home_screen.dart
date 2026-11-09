import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/petsy_app_bar.dart';
import '../pets/lost_found_screens.dart';

class _HomeData {
  _HomeData({
    required this.pets,
    required this.vets,
    required this.products,
    required this.lostFound,
    required this.myPets,
    required this.community,
    this.nextAppointment,
  });

  final List<Pet> pets;
  final List<Vet> vets;
  final List<Product> products;
  final List<LostFoundPost> lostFound;
  final List<Pet> myPets;
  final List<CommunityPost> community;
  final Appointment? nextAppointment;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<_HomeData> _load(BuildContext context) async {
    final api = context.api;
    final loggedIn = context.read<AuthState>().isLoggedIn;
    final city = context.read<AuthState>().user?.city?.trim();
    final results = await Future.wait([
      api.pets(status: 'for_adoption'),
      api.vets(),
      api.products(),
      if (loggedIn) api.myPets() else Future<List<Pet>>.value(const []),
      api.lostFound(city: city).catchError((_) => api.lostFound()),
      api.communityPosts().catchError((_) => <CommunityPost>[]),
      if (loggedIn) api.appointments().catchError((_) => <Appointment>[]) else Future<List<Appointment>>.value(const []),
    ]);

    final mine = results[3] as List<Pet>;
    var lost = results[4] as List<LostFoundPost>;
    if (lost.isEmpty && city != null && city.isNotEmpty) {
      lost = await api.lostFound();
    }

    Appointment? next;
    final appointments = results[6] as List<Appointment>;
    final upcoming = appointments.where((a) {
      final status = a.status.toLowerCase();
      return status == 'pending' || status == 'confirmed' || status == 'scheduled';
    }).toList();
    if (upcoming.isNotEmpty) {
      upcoming.sort((a, b) => '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}'));
      next = upcoming.first;
    }

    return _HomeData(
      pets: (results[0] as List<Pet>).take(8).toList(),
      vets: (results[1] as List<Vet>).take(3).toList(),
      products: (results[2] as List<Product>).take(8).toList(),
      lostFound: lost.take(8).toList(),
      myPets: mine.take(8).toList(),
      community: (results[5] as List<CommunityPost>).take(5).toList(),
      nextAppointment: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PetsyHomeAppBar(),
      body: AsyncView<_HomeData>(
        loader: () => _load(context),
        builder: (context, data, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: PetsySpacing.listBottom),
          children: [
            _HomeHero(user: user),
            const _HomeSearchBar(),
            const _ServicesRail(),
            if (user != null) ...[
              const SizedBox(height: 6),
              _MyPetsSection(pets: data.myPets),
            ],
            if (data.nextAppointment != null) _UpcomingAppointmentCard(appointment: data.nextAppointment!),
            SectionHeader(title: context.t('latest_pets'), onSeeAll: () => context.go('/adoption')),
            if (data.pets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                child: _EmptyActionCard(
                  icon: Icons.favorite_outline_rounded,
                  title: context.t('latest_pets'),
                  body: context.t('home_empty_pets'),
                  onTap: () => context.go('/adoption'),
                ),
              )
            else
              SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                  itemCount: data.pets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                  itemBuilder: (_, i) => PetCard(pet: data.pets[i], width: 160, compact: true),
                ),
              ),
            if (data.lostFound.isNotEmpty) ...[
              SectionHeader(
                title: context.t('lost_found'),
                onSeeAll: () => context.push('/lost-found/map'),
              ),
              SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                  itemCount: data.lostFound.length,
                  separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                  itemBuilder: (_, i) => LostFoundCard(
                    post: data.lostFound[i],
                    width: 188,
                    onTap: () => context.push('/lost-found/${data.lostFound[i].id}'),
                  ),
                ),
              ),
            ],
            SectionHeader(title: context.t('top_vets'), onSeeAll: () => context.push('/vets')),
            if (data.vets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                child: _EmptyActionCard(
                  icon: Icons.medical_services_outlined,
                  title: context.t('top_vets'),
                  body: context.t('home_empty_vets'),
                  onTap: () => context.push('/vets'),
                ),
              )
            else
              for (final vet in data.vets)
                Padding(
                  padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, PetsySpacing.sm + 2),
                  child: VetCard(vet: vet),
                ),
            SectionHeader(title: context.t('featured_products'), onSeeAll: () => context.go('/shop')),
            if (data.products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                child: _EmptyActionCard(
                  icon: Icons.storefront_outlined,
                  title: context.t('featured_products'),
                  body: context.t('home_empty_products'),
                  onTap: () => context.go('/shop'),
                ),
              )
            else
              SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                  itemCount: data.products.length,
                  separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                  itemBuilder: (context, i) => ProductCard(
                    product: data.products[i],
                    width: 160,
                    compact: true,
                    onAdd: () {
                      context.read<CartState>().add(data.products[i]);
                      context.snack(context.t('added_to_cart'), success: true, icon: Icons.shopping_bag_outlined);
                    },
                  ),
                ),
              ),
            if (data.community.isNotEmpty) ...[
              SectionHeader(
                title: context.t('home_community'),
                onSeeAll: () => context.push('/community'),
              ),
              _CommunityStrip(posts: data.community),
            ],
          ],
        ),
      ),
    );
  }
}

String _homeGreetingKey() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'home_greeting_morning';
  if (hour < 18) return 'home_greeting_afternoon';
  return 'home_greeting_evening';
}

class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar();

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: PetsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
      builder: (ctx) {
        final items = [
          (Icons.favorite_rounded, 'adoption', PetsyColors.primary, () => ctx.go('/adoption')),
          (Icons.security_rounded, 'guard_dogs', PetsyColors.secondary, () => ctx.push('/guard-dogs')),
          (Icons.school_rounded, 'training', PetsyColors.accent, () => ctx.push('/training')),
          (Icons.search_off_rounded, 'lost_found', PetsyColors.error, () => ctx.push('/lost-found')),
          (Icons.groups_rounded, 'community', PetsyColors.accent, () => ctx.push('/community')),
          (Icons.person_search_rounded, 'friends', PetsyColors.secondary, () {
            if (!ctx.requireLogin()) return;
            ctx.push('/friends/search');
          }),
          (Icons.medical_services_rounded, 'vets', PetsyColors.accent, () => ctx.push('/vets')),
          (Icons.storefront_rounded, 'shop', PetsyColors.primaryDark, () => ctx.go('/shop')),
        ];
        final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, PetsySpacing.page),
              children: [
                Text(context.t('home_search_title'), style: PetsyType.section),
                const SizedBox(height: PetsySpacing.xs),
                Text(
                  context.t('home_search_subtitle'),
                  style: PetsyType.subtitle.copyWith(height: 1.35),
                ),
                const SizedBox(height: 14),
                for (final (icon, label, color, onTap) in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(context.t(label), style: PetsyType.body.copyWith(fontWeight: FontWeight.w700)),
                    trailing: const PetsyChevron.forward(),
                    onTap: () {
                      Navigator.pop(ctx);
                      onTap();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(PetsySpacing.page, 14, PetsySpacing.page, 0),
      child: Material(
        color: PetsyColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.lg),
              border: Border.all(color: PetsyColors.border),
              boxShadow: PetsyShadows.soft,
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: PetsyColors.primary),
                const SizedBox(width: PetsySpacing.sm + 2),
                Expanded(
                  child: Text(
                    context.t('home_search_hint'),
                    style: PetsyType.body.copyWith(color: PetsyColors.textLight, fontWeight: FontWeight.w600),
                  ),
                ),
                PetsyMetaBadge(label: context.t('home_search_chip'), tone: PetsyMetaTone.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHero extends StatefulWidget {
  const _HomeHero({required this.user});

  final User? user;

  @override
  State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 980),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.75, curve: Curves.easeOutCubic),
  ));
  late final Animation<double> _mark = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.2, 1, curve: Curves.easeOutBack),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = user?.name.trim();
    final city = user?.city?.trim();
    final greeting = context.t(_homeGreetingKey());
    final who = (name != null && name.isNotEmpty) ? name : context.t('home_guest_title');

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 248),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF7A45),
                PetsyColors.primary,
                PetsyColors.primaryDark,
              ],
              stops: [0, 0.52, 1],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.directional(
                textDirection: Directionality.of(context),
                top: -48,
                end: -36,
                child: ScaleTransition(
                  scale: _mark,
                  child: Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
              Positioned.directional(
                textDirection: Directionality.of(context),
                bottom: -54,
                start: -28,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned.directional(
                textDirection: Directionality.of(context),
                end: 8,
                bottom: 12,
                child: ScaleTransition(
                  scale: _mark,
                  child: Icon(
                    Icons.pets_rounded,
                    size: 132,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PetsySpacing.page,
                  18,
                  PetsySpacing.page,
                  26,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.t('home_hero_brand'),
                                style: PetsyType.display.copyWith(
                                  color: Colors.white,
                                  fontSize: 34,
                                  height: 1.05,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$greeting · $who',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.2,
                                ),
                              ),
                              if (city != null && city.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.82),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        city,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.82),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (user != null)
                          Tooltip(
                            message: context.t('invite_friend'),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () {
                                  if (!context.requireLogin()) return;
                                  context.push('/friends/invite');
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      context.t('hero_title'),
                      style: PetsyType.title.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.t('hero_subtitle'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: PetsyColors.primaryDark,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          onPressed: () => context.go('/adoption'),
                          child: Text(context.t('explore_now')),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onPressed: () => context.push('/lost-found'),
                          child: Text(context.t('home_hero_lost_cta')),
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
    );
  }
}

class _ServicesRail extends StatelessWidget {
  const _ServicesRail();

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String labelKey, Color color, Color soft, VoidCallback onTap})>[
      (
        icon: Icons.favorite_rounded,
        labelKey: 'adoption',
        color: PetsyColors.primary,
        soft: PetsyColors.primarySoft,
        onTap: () => context.go('/adoption'),
      ),
      (
        icon: Icons.security_rounded,
        labelKey: 'guard_dogs',
        color: PetsyColors.secondary,
        soft: PetsyColors.mist,
        onTap: () => context.push('/guard-dogs'),
      ),
      (
        icon: Icons.school_rounded,
        labelKey: 'training',
        color: PetsyColors.accent,
        soft: PetsyColors.accentSoft,
        onTap: () => context.push('/training'),
      ),
      (
        icon: Icons.travel_explore_rounded,
        labelKey: 'lost_found',
        color: PetsyColors.error,
        soft: PetsyColors.primarySoft,
        onTap: () => context.push('/lost-found'),
      ),
      (
        icon: Icons.medical_services_rounded,
        labelKey: 'home_svc_vets',
        color: PetsyColors.accent,
        soft: PetsyColors.accentSoft,
        onTap: () => context.push('/vets'),
      ),
      (
        icon: Icons.storefront_rounded,
        labelKey: 'shop',
        color: PetsyColors.secondary,
        soft: PetsyColors.mist,
        onTap: () => context.go('/shop'),
      ),
      (
        icon: Icons.groups_rounded,
        labelKey: 'community',
        color: PetsyColors.primaryDark,
        soft: PetsyColors.shellWash,
        onTap: () => context.push('/community'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            PetsySpacing.page,
            PetsySpacing.page,
            PetsySpacing.page,
            PetsySpacing.sm,
          ),
          child: Text(context.t('home_services'), style: PetsyType.section),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final item = items[i];
              return _ServiceTile(
                icon: item.icon,
                label: context.t(item.labelKey),
                color: item.color,
                soft: item.soft,
                onTap: item.onTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.94),
      onTapCancel: () => setState(() => _scale = 1),
      onTapUp: (_) {
        setState(() => _scale = 1);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.1,
                  color: PetsyColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyPetsSection extends StatelessWidget {
  const _MyPetsSection({required this.pets});

  final List<Pet> pets;

  String _countLabel(BuildContext context) {
    if (pets.isEmpty) return context.t('home_add_pet_nudge_body');
    if (pets.length == 1) return context.t('home_pets_count_one');
    return context.t('home_pets_count').replaceAll('{count}', '${pets.length}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('my_pets'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      _countLabel(context),
                      style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (pets.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => context.push('/my-pets'),
                  child: Text(context.t('see_all')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (pets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MyPetsEmptyCard(onAdd: () => context.push('/add-pet')),
          )
        else
          SizedBox(
            height: 228,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: pets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                if (i == pets.length) {
                  return _MyPetAddCard(onTap: () => context.push('/add-pet'));
                }
                return _MyPetHomeCard(pet: pets[i]);
              },
            ),
          ),
      ],
    );
  }
}

class _MyPetsEmptyCard extends StatelessWidget {
  const _MyPetsEmptyCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PetsyColors.primarySoft,
                Color.lerp(PetsyColors.primarySoft, Colors.white, 0.35)!,
              ],
            ),
            border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.pets_rounded, color: PetsyColors.primaryDark, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('home_add_pet_nudge_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      context.t('home_add_pet_nudge_body'),
                      style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              const PetsyChevron.forward(color: PetsyColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyPetHomeCard extends StatefulWidget {
  const _MyPetHomeCard({required this.pet});

  final Pet pet;

  @override
  State<_MyPetHomeCard> createState() => _MyPetHomeCardState();
}

class _MyPetHomeCardState extends State<_MyPetHomeCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    final meta = joinIsolated([
      context.t(pet.species),
      if (pet.age != null && pet.age!.trim().isNotEmpty) petAgeLabel(context, pet.age),
    ]);

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapCancel: () => setState(() => _scale = 1),
      onTapUp: (_) {
        setState(() => _scale = 1);
        context.push('/pet/${pet.id}');
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 158,
          decoration: BoxDecoration(
            color: PetsyColors.surface,
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(color: PetsyColors.border),
            boxShadow: [
              BoxShadow(
                color: PetsyColors.primary.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
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
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Icon(
                          pet.gender == 'female' ? Icons.female_rounded : Icons.male_rounded,
                          size: 14,
                          color: pet.gender == 'female' ? const Color(0xFFE05A8C) : PetsyColors.accent,
                        ),
                      ),
                    ),
                    if (pet.vaccinated)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: PetsyColors.accentSoft.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Icon(Icons.vaccines_rounded, size: 13, color: PetsyColors.accent),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.t('home_open_pet'),
                            style: const TextStyle(
                              color: PetsyColors.primaryDark,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Material(
                          color: PetsyColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => context.push('/pet-health/${pet.id}'),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.monitor_heart_outlined, size: 14, color: PetsyColors.primaryDark),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.t('home_pet_health_quick'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: PetsyColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    );
  }
}

class _MyPetAddCard extends StatelessWidget {
  const _MyPetAddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: Ink(
          width: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            color: PetsyColors.mist,
            border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add_rounded, color: PetsyColors.primaryDark, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  context.t('home_pet_add_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: PetsyColors.primaryDark),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('home_pet_add_body'),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 11.5, height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingAppointmentCard extends StatelessWidget {
  const _UpcomingAppointmentCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: PetsyColors.accentSoft,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: InkWell(
          onTap: () => context.push('/appointments'),
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.event_available_rounded, color: PetsyColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('home_upcoming_appointment'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        appointment.when(Localizations.localeOf(context).languageCode),
                        style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 13),
                      ),
                      if (appointment.reason.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          appointment.reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                StatusChip(appointment.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityStrip extends StatelessWidget {
  const _CommunityStrip({required this.posts});

  final List<CommunityPost> posts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: posts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final post = posts[i];
          return InkWell(
            onTap: () => context.push('/community/${post.id}'),
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            child: Container(
              width: 240,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PetsyColors.surface,
                borderRadius: BorderRadius.circular(PetsyRadius.lg),
                border: Border.all(color: PetsyColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: PetsyColors.primarySoft,
                        backgroundImage: (post.userAvatar != null && post.userAvatar!.isNotEmpty)
                            ? NetworkImage(post.userAvatar!)
                            : null,
                        child: (post.userAvatar == null || post.userAvatar!.isEmpty)
                            ? const Icon(Icons.person, size: 16, color: PetsyColors.primaryDark)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          post.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${post.likes}',
                        style: const TextStyle(fontSize: 11.5, color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.favorite, size: 13, color: PetsyColors.primary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post.title.isNotEmpty ? post.title : post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                  const Spacer(),
                  Text(
                    post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyActionCard extends StatelessWidget {
  const _EmptyActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: PetsyColors.primarySoft,
                child: Icon(icon, color: PetsyColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(body, style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              const PetsyChevron.forward(),
            ],
          ),
        ),
      ),
    );
  }
}
