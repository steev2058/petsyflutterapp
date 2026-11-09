import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/geo_service.dart';
import '../../state/app_state.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/pet_photo_picker.dart';
import '../../widgets/phone_field.dart';
import '../auth/auth_screens.dart';
import '../community/community_screens.dart' show relativeTime;
import 'lost_found_map_screen.dart';
import 'pet_screens.dart';

const _listRadiusOptions = <double?>[5, 10, 25, 50, null];

String _seenDate(BuildContext context, String raw) {
  final date = DateTime.tryParse(raw);
  return date == null ? raw : context.formatDate(date);
}

String _petTitle(BuildContext context, LostFoundPost post) =>
    [context.t(post.petSpecies), if (post.breed != null && post.breed!.trim().isNotEmpty) post.breed!.trim()].join(' · ');

class LostFoundScreen extends StatefulWidget {
  const LostFoundScreen({super.key, this.initialType});

  final String? initialType;

  @override
  State<LostFoundScreen> createState() => _LostFoundScreenState();
}

class _LostFoundScreenState extends State<LostFoundScreen> {
  late String? _type = widget.initialType;
  String? _species;
  double? _radiusKm = 25;
  bool _sortNearest = true;
  LatLng _origin = petsyMapCenter;
  bool _originFromDevice = false;
  bool _locating = false;
  int _reloadToken = 0;
  List<_RankedLostFound> _all = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final result = await GeoService.instance.currentLocation();
      if (!mounted) return;
      setState(() {
        _origin = result.point;
        _originFromDevice = result.fromDevice;
        _reloadToken++;
      });
      if (result.denied) {
        context.snack(context.t('location_permission_denied'), error: true);
      } else if (result.serviceDisabled) {
        context.snack(context.t('location_disabled'), error: true);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<List<_RankedLostFound>> _load(BuildContext context) async {
    final userCity = context.read<AuthState>().user?.city?.trim();
    var posts = await context.api.lostFound(type: _type);
    if (_species != null) {
      posts = posts.where((e) => e.petSpecies == _species).toList();
    }

    final geo = GeoService.instance;
    final ranked = <_RankedLostFound>[];
    for (final p in posts) {
      LatLng? point;
      if (p.hasCoords) {
        point = LatLng(p.lat!, p.lng!);
      } else {
        point = await geo.geocode(p.lastSeenLocation);
      }
      final km = point == null ? null : geo.kmBetween(_origin, point);
      ranked.add(_RankedLostFound(post: p, km: km, point: point));
    }

    // Soft boost: if user has a city and no GPS, prefer matching city when distances tie.
    ranked.sort((a, b) {
      if (_sortNearest) {
        final ak = a.km ?? double.infinity;
        final bk = b.km ?? double.infinity;
        final byKm = ak.compareTo(bk);
        if (byKm != 0) return byKm;
      } else {
        final ad = a.post.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.post.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final byDate = bd.compareTo(ad);
        if (byDate != 0) return byDate;
      }
      if (userCity != null && userCity.isNotEmpty) {
        final aCity = a.post.lastSeenLocation.toLowerCase().contains(userCity.toLowerCase());
        final bCity = b.post.lastSeenLocation.toLowerCase().contains(userCity.toLowerCase());
        if (aCity != bCity) return aCity ? -1 : 1;
      }
      return 0;
    });

    _all = ranked;
    return _applyFilter(ranked);
  }

  List<_RankedLostFound> _applyFilter(List<_RankedLostFound> source) {
    final radius = _radiusKm;
    if (radius == null) return source;
    return source.where((e) => e.km != null && e.km! <= radius).toList();
  }

  void _setSpecies(String? value) => setState(() {
        _species = value;
        _reloadToken++;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('lost_found')),
        actions: [
          IconButton(
            tooltip: context.t('lost_found_map'),
            onPressed: () => context.push('/lost-found/map${_type == null ? '' : '?type=$_type'}'),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      floatingActionButton: PetsyFab(
        heroTag: 'lost-found-fab',
        icon: Icons.add_alert_rounded,
        label: context.t('report_lost_found'),
        onPressed: () async {
          if (!context.requireLogin()) return;
          final created = await context.push<bool>('/lost-found/report');
          if (created == true && mounted) setState(() => _reloadToken++);
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.page,
              PetsySpacing.xs,
              PetsySpacing.page,
              0,
            ),
            child: LostFoundTypeSwitch(
              value: _type,
              onChanged: (v) => setState(() {
                _type = v;
                _reloadToken++;
              }),
            ),
          ),
          PetsyFilterBar(
            margin: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.page,
              PetsySpacing.sm + 2,
              PetsySpacing.page,
              0,
            ),
            activeCount: _species == null ? 0 : 1,
            onOpen: () async {
              var draft = _species ?? '__all__';
              final applied = await showPetsyFiltersSheet(
                context: context,
                title: context.t('filters'),
                onReset: () => draft = '__all__',
                body: (ctx, setModal) => PetsyChoiceField<String>(
                  label: context.t('species'),
                  prefixIcon: Icons.pets_rounded,
                  value: draft,
                  options: [
                    PetsyChoiceOption(value: '__all__', label: context.t('all'), icon: Icons.apps_rounded),
                    for (final s in petSpecies)
                      PetsyChoiceOption(value: s, label: context.t(s), icon: Icons.pets_outlined),
                  ],
                  onChanged: (v) => setModal(() => draft = v),
                ),
              );
              if (applied == true && mounted) {
                _setSpecies(draft == '__all__' ? null : draft);
              }
            },
            onClearAll: _species == null ? null : () => _setSpecies(null),
            chips: [
              if (_species != null)
                PetsyActiveFilter(
                  label: context.t(_species!),
                  icon: Icons.pets_rounded,
                  onClear: () => _setSpecies(null),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.page,
              PetsySpacing.sm + 2,
              PetsySpacing.page,
              PetsySpacing.sm - 2,
            ),
            child: _LocationBar(
              fromDevice: _originFromDevice,
              locating: _locating,
              sortNearest: _sortNearest,
              radiusKm: _radiusKm,
              onLocate: _locate,
              onToggleSort: () => setState(() {
                _sortNearest = !_sortNearest;
                _reloadToken++;
              }),
              onRadius: (r) => setState(() => _radiusKm = r),
            ),
          ),
          Expanded(
            child: AsyncView<List<_RankedLostFound>>(
              key: ValueKey('$_type-$_species-$_sortNearest-$_reloadToken'),
              loader: () => _load(context),
              isEmpty: (items) => _all.isEmpty,
              emptyIcon: Icons.travel_explore_rounded,
              emptyText: context.t('lost_found_empty'),
              builder: (context, loaded, reload) {
                final items = _applyFilter(_all.isEmpty ? loaded : _all);
                return RefreshIndicator(
                  onRefresh: reload,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96),
                          children: [
                            MessageView(
                              icon: Icons.social_distance_outlined,
                              text: context.t('lost_found_map_empty_radius'),
                              action: OutlinedButton.icon(
                                onPressed: () => setState(() => _radiusKm = null),
                                icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                                label: Text(context.t('any_distance')),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            PetsySpacing.page,
                            PetsySpacing.xs,
                            PetsySpacing.page,
                            96,
                          ),
                          itemCount: items.length + 1,
                          separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 8 : 12),
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return Text(
                                context.t('lf_count').replaceAll('{count}', '${items.length}'),
                                style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700),
                              );
                            }
                            final item = items[i - 1];
                            return LostFoundCard(
                              post: item.post,
                              distanceKm: item.km,
                              onTap: () => context.push('/lost-found/${item.post.id}'),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationBar extends StatelessWidget {
  const _LocationBar({
    required this.fromDevice,
    required this.locating,
    required this.sortNearest,
    required this.radiusKm,
    required this.onLocate,
    required this.onToggleSort,
    required this.onRadius,
  });

  final bool fromDevice;
  final bool locating;
  final bool sortNearest;
  final double? radiusKm;
  final VoidCallback onLocate;
  final VoidCallback onToggleSort;
  final ValueChanged<double?> onRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(PetsyRadius.md),
              onTap: locating ? null : onLocate,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: fromDevice ? PetsyColors.primarySoft : PetsyColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: locating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              fromDevice ? Icons.my_location_rounded : Icons.location_searching_rounded,
                              size: 18,
                              color: PetsyColors.primaryDark,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t(fromDevice ? 'lf_near_you' : 'lf_default_city'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                          Text(
                            context.t(fromDevice ? 'lf_tap_refresh_location' : 'lf_tap_use_location'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.t(sortNearest ? 'sort_nearest' : 'sort_newest'),
            onPressed: onToggleSort,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              sortNearest ? Icons.near_me_outlined : Icons.schedule_rounded,
              color: PetsyColors.primaryDark,
              size: 20,
            ),
          ),
          PopupMenuButton<int>(
            tooltip: context.t('lf_radius'),
            initialValue: _listRadiusOptions.indexOf(radiusKm),
            onSelected: (i) => onRadius(_listRadiusOptions[i]),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
            itemBuilder: (context) => [
              for (var i = 0; i < _listRadiusOptions.length; i++)
                PopupMenuItem(value: i, child: Text(radiusLabel(context, _listRadiusOptions[i]))),
            ],
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: PetsyColors.primarySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.radar_rounded, size: 15, color: PetsyColors.primaryDark),
                  const SizedBox(width: 4),
                  Text(
                    radiusLabel(context, radiusKm),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: PetsyColors.primaryDark),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 20, color: PetsyColors.primaryDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankedLostFound {
  const _RankedLostFound({required this.post, this.km, this.point});
  final LostFoundPost post;
  final double? km;
  final LatLng? point;
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.type, {this.large = false});

  final String type;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: lostFoundColor(type),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.26), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(lostFoundIcon(type), size: large ? 15 : 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            context.t(type),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: large ? 12.5 : 11),
          ),
        ],
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  const _DistancePill(this.km, {this.onImage = false});

  final double km;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onImage ? Colors.white : PetsyColors.primarySoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.near_me_rounded, size: 12, color: PetsyColors.primaryDark),
          const SizedBox(width: 3),
          Text(
            GeoService.instance.formatKm(km, Localizations.localeOf(context).languageCode),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(this.icon, this.text, {this.small = false});

  final IconData icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: small ? 13 : 14, color: PetsyColors.textLight),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: small ? 11.5 : 12.5, color: PetsyColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class LostFoundCard extends StatelessWidget {
  const LostFoundCard({super.key, required this.post, this.onTap, this.width, this.distanceKm});

  final LostFoundPost post;
  final VoidCallback? onTap;
  final double? width;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PetsyRadius.xl);
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: PetsyColors.primary.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: PetsyColors.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: PetsyColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: width != null ? _compact(context) : _full(context),
        ),
      ),
    );
  }

  Widget _resolvedOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: PetsyColors.ink.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(context.t('resolved'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(post.image, fit: BoxFit.cover),
              if (post.status != 'active') _resolvedOverlay(context),
              PositionedDirectional(top: 8, start: 8, child: _TypeBadge(post.type)),
              if (distanceKm != null)
                PositionedDirectional(top: 8, end: 8, child: _DistancePill(distanceKm!, onImage: true)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _petTitle(context, post),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 4),
              _MetaLine(Icons.place_outlined, post.lastSeenLocation, small: true),
              const SizedBox(height: 2),
              _MetaLine(Icons.event_outlined, _seenDate(context, post.lastSeenDate), small: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _full(BuildContext context) {
    final posted = relativeTime(context, post.createdAt);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            child: SizedBox(
              width: 104,
              height: 118,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(post.image, fit: BoxFit.cover),
                  if (post.status != 'active') _resolvedOverlay(context),
                  PositionedDirectional(top: 6, start: 6, child: _TypeBadge(post.type)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _petTitle(context, post),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      if (distanceKm != null) ...[
                        const SizedBox(width: 6),
                        _DistancePill(distanceKm!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  _MetaLine(Icons.place_outlined, post.lastSeenLocation),
                  const SizedBox(height: 3),
                  _MetaLine(
                    Icons.event_outlined,
                    [_seenDate(context, post.lastSeenDate), if (posted.isNotEmpty) posted].join(' · '),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LostFoundDetailScreen extends StatefulWidget {
  const LostFoundDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<LostFoundDetailScreen> createState() => _LostFoundDetailScreenState();
}

class _LostFoundDetailScreenState extends State<LostFoundDetailScreen> {
  String? _distanceLabel;
  LostFoundPost? _distanceFor;
  LatLng? _point;

  Future<void> _refreshDistance(LostFoundPost post) async {
    if (_distanceFor?.id == post.id && _distanceLabel != null) return;
    LatLng? point;
    if (post.hasCoords) {
      point = LatLng(post.lat!, post.lng!);
    } else {
      point = await GeoService.instance.geocode(post.lastSeenLocation);
    }
    if (point == null || !mounted) return;
    final loc = await GeoService.instance.currentLocation();
    if (!mounted) return;
    final km = GeoService.instance.kmBetween(loc.point, point);
    setState(() {
      _distanceFor = post;
      _point = point;
      _distanceLabel = context.t('distance_from_you').replaceAll('{km}', GeoService.instance.formatKm(km, Localizations.localeOf(context).languageCode));
    });
  }

  String _shareText(BuildContext context, LostFoundPost post) {
    final link = AppConfig.lostFoundShareUrl(post.id);
    return [
      '${context.t(post.type)} · ${context.t(post.petSpecies)}',
      post.description,
      '${context.t('last_seen_location')}: ${post.lastSeenLocation}',
      '${context.t('last_seen_date')}: ${post.lastSeenDate}',
      if (post.contactPhone.trim().isNotEmpty) '${context.t('contact_phone')}: ${post.contactPhone}',
      link,
    ].join('\n');
  }

  Future<void> _share(BuildContext context, LostFoundPost post) async {
    await SharePlus.instance.share(ShareParams(text: _shareText(context, post)));
  }

  Future<void> _shareWhatsApp(BuildContext context, LostFoundPost post) async {
    final text = Uri.encodeComponent(_shareText(context, post));
    final uri = Uri.parse('https://wa.me/?text=$text');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      await _share(context, post);
    }
  }

  String _digitsPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) return cleaned.substring(1);
    return cleaned.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _whatsAppChat(String phone) async {
    final digits = _digitsPhone(phone);
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contact(BuildContext context, LostFoundPost post) async {
    if (!context.requireLogin()) return;
    try {
      final id = await context.api.startConversation(
        otherUserId: post.userId,
        message: '${context.t('hello')} — ${context.t(post.type)} · ${post.lastSeenLocation}',
      );
      if (context.mounted) context.push('/chat/$id');
    } catch (e) {
      if (context.mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _resolve(BuildContext context, LostFoundPost post) async {
    final ok = await confirmAction(
      context,
      title: context.t('mark_resolved'),
      message: context.t('lf_resolve_confirm'),
      confirmLabel: context.t('mark_resolved'),
      color: PetsyColors.success,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.api.resolveLostFound(post.id);
      if (!context.mounted) return;
      context.snack(context.t('lost_found_resolved'));
      context.pop();
    } catch (e) {
      if (context.mounted) context.snack(context.errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthState>().user?.id;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('lost_found'))),
      body: AsyncView<LostFoundPost>(
        loader: () => context.api.lostFoundPost(widget.postId),
        builder: (context, post, reload) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDistance(post));
          final mine = userId != null && userId == post.userId;
          final active = post.status == 'active';
          final color = lostFoundColor(post.type);
          final phone = post.contactPhone.trim();
          final hasPhone = phone.isNotEmpty;
          final point = _distanceFor?.id == post.id ? _point : null;
          final posted = relativeTime(context, post.createdAt);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _DetailHero(
                      post: post,
                      onShare: () => _share(context, post),
                      onWhatsApp: () => _shareWhatsApp(context, post),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _petTitle(context, post),
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                                ),
                              ),
                              StatusChip(post.status),
                            ],
                          ),
                          if (posted.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              context.t('lf_posted').replaceAll('{time}', posted),
                              style: const TextStyle(color: PetsyColors.textLight, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(post.description, style: const TextStyle(fontSize: 15, height: 1.5)),
                          if (_distanceLabel != null && _distanceFor?.id == post.id) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.near_me_rounded, size: 15, color: color),
                                  const SizedBox(width: 5),
                                  Text(_distanceLabel!, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: context.t('lf_details'),
                      child: Column(
                        children: [
                          _Fact(Icons.pets_rounded, context.t('species'), context.t(post.petSpecies)),
                          if (post.breed != null && post.breed!.isNotEmpty)
                            _Fact(Icons.category_outlined, context.t('breed'), post.breed!),
                          if (post.color != null && post.color!.isNotEmpty)
                            _Fact(Icons.palette_outlined, context.t('color'), post.color!),
                          _Fact(Icons.event_outlined, context.t('last_seen_date'), _seenDate(context, post.lastSeenDate)),
                          if (hasPhone)
                            _Fact(Icons.phone_outlined, context.t('contact_phone'), phone, onTap: () => _call(phone)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: context.t('last_seen_location'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.place_rounded, size: 18, color: color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(post.lastSeenLocation, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (point != null)
                            _MiniMap(
                              key: ValueKey(point),
                              point: point,
                              color: color,
                              onTap: () => context.push('/lost-found/map?focus=${post.id}'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => context.push('/lost-found/map?focus=${post.id}'),
                              icon: const Icon(Icons.map_outlined),
                              label: Text(context.t('view_on_map')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                BottomActionBar(
                  child: Row(
                    children: mine
                        ? [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: PetsyColors.success),
                                onPressed: () => _resolve(context, post),
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(context.t('mark_resolved')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _RoundAction(
                              icon: Icons.share_outlined,
                              tooltip: context.t('share_report'),
                              onTap: () => _share(context, post),
                            ),
                          ]
                        : [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _contact(context, post),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: Text(context.t('contact_reporter')),
                              ),
                            ),
                            if (hasPhone) ...[
                              const SizedBox(width: 10),
                              _RoundAction(
                                icon: Icons.call_outlined,
                                tooltip: context.t('call_reporter'),
                                onTap: () => _call(phone),
                              ),
                              const SizedBox(width: 8),
                              _RoundAction(
                                icon: Icons.sms_outlined,
                                tooltip: context.t('whatsapp_reporter'),
                                onTap: () => _whatsAppChat(phone),
                              ),
                            ],
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

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.post, required this.onShare, required this.onWhatsApp});

  final LostFoundPost post;
  final VoidCallback onShare;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    Widget circle(IconData icon, String tooltip, VoidCallback onTap) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon, size: 20, color: PetsyColors.primaryDark),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(post.image, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Color(0x99000000)],
                ),
              ),
            ),
            PositionedDirectional(top: 12, start: 12, child: _TypeBadge(post.type, large: true)),
            PositionedDirectional(
              top: 10,
              end: 10,
              child: Row(
                children: [
                  circle(Icons.share_outlined, context.t('share_report'), onShare),
                  const SizedBox(width: 8),
                  circle(Icons.chat_outlined, context.t('share_via_whatsapp'), onWhatsApp),
                ],
              ),
            ),
            PositionedDirectional(
              bottom: 12,
              start: 14,
              end: 14,
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      post.lastSeenLocation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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

class _MiniMap extends StatelessWidget {
  const _MiniMap({super.key, required this.point, required this.color, required this.onTap});

  final LatLng point;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'company.petsy.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on_rounded,
                        color: color,
                        size: 42,
                        shadows: [Shadow(color: PetsyColors.ink.withValues(alpha: 0.38), blurRadius: 5, offset: const Offset(0, 2))],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            PositionedDirectional(
              bottom: 10,
              end: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.26), blurRadius: 6)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, size: 15, color: PetsyColors.primaryDark),
                    const SizedBox(width: 4),
                    Text(
                      context.t('view_on_map'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: PetsyColors.primarySoft,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          onTap: onTap,
          child: SizedBox(width: 50, height: 50, child: Icon(icon, color: PetsyColors.primaryDark)),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value, {this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PetsyColors.primarySoft,
              borderRadius: BorderRadius.circular(PetsyRadius.sm),
            ),
            child: Icon(icon, size: 19, color: PetsyColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: onTap == null ? PetsyColors.text : PetsyColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.call_rounded, size: 18, color: PetsyColors.primaryDark),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(borderRadius: BorderRadius.circular(PetsyRadius.sm), onTap: onTap, child: child);
  }
}

class ReportLostFoundScreen extends StatefulWidget {
  const ReportLostFoundScreen({super.key});

  @override
  State<ReportLostFoundScreen> createState() => _ReportLostFoundScreenState();
}

class _ReportLostFoundScreenState extends State<ReportLostFoundScreen> {
  final _form = GlobalKey<FormState>();
  final _phoneKey = GlobalKey<PetsyPhoneFieldState>();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _breed = TextEditingController();
  final _color = TextEditingController();
  final _phone = TextEditingController();
  String _type = 'lost';
  String _species = 'dog';
  DateTime _date = DateTime.now();
  String? _image;
  LatLng? _coords;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    if (user?.city != null && user!.city!.isNotEmpty) {
      _location.text = user.city!;
      _coords = GeoService.instance.fromKnownPlace(user.city!);
    }
    if (user?.phone != null && user!.phone!.isNotEmpty) {
      _phone.text = user.phone!.replaceFirst(RegExp(r'^\+\d+'), '');
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _location.dispose();
    _breed.dispose();
    _color.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final coords = _coords ?? await GeoService.instance.geocode(_location.text.trim());
      if (!mounted) return;
      await context.api.createLostFound({
        'type': _type,
        'pet_species': _species,
        'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        'color': _color.text.trim().isEmpty ? null : _color.text.trim(),
        'description': _desc.text.trim(),
        'last_seen_location': _location.text.trim(),
        'last_seen_date': _date.toIso8601String().split('T').first,
        'contact_phone': _phoneKey.currentState?.completeNumber ?? _phone.text.trim(),
        'image': _image,
        if (coords != null) 'lat': coords.latitude,
        if (coords != null) 'lng': coords.longitude,
      });
      if (!mounted) return;
      context.snack(context.t('lost_found_reported'));
      context.pop(true);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickOnMap() async {
    setState(() => _locating = true);
    try {
      final point = await showPickLocationMap(context, initial: _coords, hintLocation: _location.text);
      if (point != null && mounted) setState(() => _coords = point);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final color = lostFoundColor(_type);
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('report_lost_found'))),
      body: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(
                    context.t('lf_report_intro'),
                    style: const TextStyle(color: PetsyColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    icon: Icons.flag_outlined,
                    title: context.t('report_type'),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ReportTypeOption(
                            type: 'lost',
                            hint: context.t('lf_lost_hint'),
                            selected: _type == 'lost',
                            onTap: () => setState(() => _type = 'lost'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ReportTypeOption(
                            type: 'found',
                            hint: context.t('lf_found_hint'),
                            selected: _type == 'found',
                            onTap: () => setState(() => _type = 'found'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.photo_camera_outlined,
                    title: context.t('lf_section_photo'),
                    child: PetPhotoPicker(imageUrl: _image, onChanged: (url) => setState(() => _image = url)),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.pets_rounded,
                    title: context.t('lf_section_pet'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                icon: Icons.pets_outlined,
                              ),
                          ],
                          onChanged: (v) => setState(() => _species = v),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _breed,
                                decoration: InputDecoration(labelText: context.t('breed')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _color,
                                decoration: InputDecoration(labelText: context.t('color')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _desc,
                          maxLines: 4,
                          maxLength: 600,
                          decoration: InputDecoration(
                            labelText: context.t('description'),
                            hintText: context.t('lf_desc_hint'),
                            alignLabelWithHint: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.place_outlined,
                    title: context.t('lf_section_where'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PetsyCityField(
                          controller: _location,
                          label: context.t('last_seen_location'),
                          required: true,
                          autofillFromGps: _location.text.trim().isEmpty,
                          onChanged: (_) => setState(() {}),
                          onCitySelected: (city) => setState(() => _coords = city.center),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _locating ? null : _pickOnMap,
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: Text(context.t('pick_on_map')),
                        ),
                        const SizedBox(height: 10),
                        _PinStatus(coords: _coords),
                        const SizedBox(height: 12),
                        Material(
                          color: PetsyColors.backgroundAlt,
                          borderRadius: BorderRadius.circular(PetsyRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(PetsyRadius.md),
                            onTap: _pickDate,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(PetsyRadius.sm),
                                    ),
                                    child: Icon(Icons.event_outlined, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.t('last_seen_date'),
                                          style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary),
                                        ),
                                        Text(
                                          context.formatDate(_date),
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.edit_calendar_outlined, size: 20, color: PetsyColors.primaryDark),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.phone_outlined,
                    title: context.t('lf_section_contact'),
                    child: PetsyPhoneField(
                      key: _phoneKey,
                      controller: _phone,
                      required: true,
                      decoration: InputDecoration(labelText: context.t('contact_phone')),
                    ),
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: SubmitButton(label: context.t('submit_report'), busy: _busy, onPressed: _submit),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTypeOption extends StatelessWidget {
  const _ReportTypeOption({required this.type, required this.hint, required this.selected, required this.onTap});

  final String type;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = lostFoundColor(type);
    return Material(
      color: selected ? color.withValues(alpha: 0.1) : PetsyColors.backgroundAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        side: BorderSide(color: selected ? color : PetsyColors.border, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.lg)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? color : color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(lostFoundIcon(type), size: 19, color: selected ? Colors.white : color),
                  ),
                  const Spacer(),
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 20,
                    color: selected ? color : PetsyColors.textLight,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(context.t(type), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinStatus extends StatelessWidget {
  const _PinStatus({required this.coords});

  final LatLng? coords;

  @override
  Widget build(BuildContext context) {
    final pinned = coords != null;
    final color = pinned ? PetsyColors.success : PetsyColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PetsyRadius.md),
      ),
      child: Row(
        children: [
          Icon(pinned ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pinned
                  ? '${context.t('pinned_coords')}: ${coords!.latitude.toStringAsFixed(4)}, ${coords!.longitude.toStringAsFixed(4)}'
                  : context.t('lf_no_pin'),
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
