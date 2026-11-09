import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/geo_service.dart';
import '../../widgets/common.dart';

const _radiusOptions = <double?>[5, 10, 25, 50, null];

Color lostFoundColor(String type) => type == 'lost' ? PetsyColors.error : PetsyColors.accent;

IconData lostFoundIcon(String type) => type == 'lost' ? Icons.travel_explore_rounded : Icons.volunteer_activism_rounded;

String radiusLabel(BuildContext context, double? km) =>
    km == null ? context.t('any_distance') : context.t('within_km').replaceAll('{km}', '${km.toInt()}');

/// Segmented all / lost / found switch shared by the list and the map.
class LostFoundTypeSwitch extends StatelessWidget {
  const LostFoundTypeSwitch({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String? type, String label, IconData icon) {
      final selected = value == type;
      final color = type == null ? PetsyColors.primary : lostFoundColor(type);
      return Expanded(
        child: Material(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(PetsyRadius.md),
            onTap: () => onChanged(type),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: selected ? Colors.white : color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: selected ? Colors.white : PetsyColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          segment(null, context.t('all'), Icons.apps_rounded),
          segment('lost', context.t('lost'), lostFoundIcon('lost')),
          segment('found', context.t('found'), lostFoundIcon('found')),
        ],
      ),
    );
  }
}

class LostFoundMapScreen extends StatefulWidget {
  const LostFoundMapScreen({super.key, this.initialType, this.focusPostId});

  final String? initialType;
  final String? focusPostId;

  @override
  State<LostFoundMapScreen> createState() => _LostFoundMapScreenState();
}

class _LostFoundMapScreenState extends State<LostFoundMapScreen> {
  late String? _type = widget.initialType;
  double? _radiusKm = 10;
  final _controller = MapController();
  LatLng _origin = petsyMapCenter;
  bool _originFromDevice = false;
  bool _locating = false;
  List<_MappedPost> _all = const [];
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(requestPermission: true));
  }

  Future<void> _locate({bool requestPermission = false}) async {
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
      } else if (result.fromDevice) {
        _controller.move(_origin, GeoService.instance.zoomForRadiusKm(_radiusKm ?? 25));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<List<_MappedPost>> _load(BuildContext context) async {
    final posts = await context.api.lostFound(type: _type);
    final mapped = <_MappedPost>[];
    final geo = GeoService.instance;
    for (final p in posts) {
      LatLng? point;
      if (p.hasCoords) {
        point = LatLng(p.lat!, p.lng!);
      } else {
        point = await geo.geocode(p.lastSeenLocation);
      }
      if (point == null) continue;
      final km = geo.kmBetween(_origin, point);
      mapped.add(_MappedPost(post: p, point: point, km: km));
    }
    mapped.sort((a, b) => a.km.compareTo(b.km));
    _all = mapped;
    return _applyFilter(mapped);
  }

  List<_MappedPost> _applyFilter(List<_MappedPost> source) {
    final radius = _radiusKm;
    if (radius == null) return source;
    return source.where((e) => e.km <= radius).toList();
  }

  void _fit(List<_MappedPost> items) {
    if (widget.focusPostId != null) {
      final focus = items.where((e) => e.post.id == widget.focusPostId).toList();
      if (focus.isNotEmpty) {
        _controller.move(focus.first.point, 14);
        return;
      }
    }
    if (_radiusKm != null) {
      _controller.move(_origin, GeoService.instance.zoomForRadiusKm(_radiusKm!));
      return;
    }
    if (items.isEmpty) {
      _controller.move(_origin, 11);
      return;
    }
    if (items.length == 1) {
      _controller.move(items.first.point, 13);
      return;
    }
    final points = [_origin, ...items.map((e) => e.point)];
    final lats = points.map((e) => e.latitude);
    final lngs = points.map((e) => e.longitude);
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 200, 48, 96)));
  }

  void _onRadiusChanged(double? radius) {
    setState(() => _radiusKm = radius);
    final filtered = _applyFilter(_all);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit(filtered);
    });
  }

  @override
  Widget build(BuildContext context) {
    final geo = GeoService.instance;
    final visible = _applyFilter(_all);
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('lost_found_map')),
        actions: [
          IconButton(
            tooltip: context.t('lost_found'),
            onPressed: () => context.pushReplacement('/lost-found'),
            icon: const Icon(Icons.view_list_rounded),
          ),
        ],
      ),
      floatingActionButton: PetsyFab(
        heroTag: 'lost-found-map-fab',
        icon: Icons.add_location_alt_rounded,
        label: context.t('report_lost_found'),
        onPressed: () {
          if (!context.requireLogin()) return;
          context.push('/lost-found/report');
        },
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AsyncView<_MapBundle>(
              key: ValueKey('$_type-$_reloadToken'),
              loader: () async {
                final items = await _load(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {});
                    _fit(items);
                  }
                });
                return _MapBundle(all: _all, filtered: items);
              },
              isEmpty: (data) => data.all.isEmpty,
              emptyIcon: Icons.map_outlined,
              emptyText: context.t('lost_found_map_empty'),
              builder: (context, data, reload) {
                final items = _applyFilter(data.all);
                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _controller,
                      options: MapOptions(
                        initialCenter: _origin,
                        initialZoom: geo.zoomForRadiusKm(_radiusKm ?? 25),
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'company.petsy.app',
                          maxNativeZoom: 19,
                        ),
                        if (_radiusKm != null)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: geo.circlePoints(_origin, _radiusKm!),
                                color: PetsyColors.primary.withValues(alpha: 0.08),
                                borderColor: PetsyColors.primary.withValues(alpha: 0.45),
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(point: _origin, width: 44, height: 44, child: const _OriginMarker()),
                            for (final m in items)
                              Marker(
                                point: m.point,
                                width: 46,
                                height: 46,
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  onTap: () => _showPostSheet(context, m),
                                  child: _MapPin(type: m.post.type, focused: m.post.id == widget.focusPostId),
                                ),
                              ),
                          ],
                        ),
                        const RichAttributionWidget(
                          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                        ),
                      ],
                    ),
                    if (items.isEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 88,
                        child: _MapNotice(
                          icon: Icons.social_distance_outlined,
                          text: context.t('lost_found_map_empty_radius'),
                          action: _radiusKm == null
                              ? null
                              : TextButton(
                                  onPressed: () => _onRadiusChanged(null),
                                  child: Text(context.t('any_distance')),
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: _MapFilterCard(
              type: _type,
              radiusKm: _radiusKm,
              count: visible.length,
              fromDevice: _originFromDevice,
              locating: _locating,
              onType: (v) => setState(() {
                _type = v;
                _reloadToken++;
              }),
              onRadius: _onRadiusChanged,
              onLocate: () => _locate(requestPermission: true),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPostSheet(BuildContext context, _MappedPost m) async {
    final post = m.post;
    final color = lostFoundColor(post.type);
    final title = [context.t(post.petSpecies), if (post.breed != null && post.breed!.isNotEmpty) post.breed!].join(' · ');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PetsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(PetsyRadius.md),
                    child: SizedBox(width: 76, height: 76, child: NetImage(post.image)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
                              child: Text(
                                context.t(post.type),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.near_me_rounded, size: 14, color: PetsyColors.primaryDark),
                            const SizedBox(width: 3),
                            Text(
                              GeoService.instance.formatKm(m.km, Localizations.localeOf(context).languageCode),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 14, color: PetsyColors.textSecondary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                post.lastSeenLocation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.4, color: PetsyColors.text),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/lost-found/${post.id}');
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(context.t('view_details')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapFilterCard extends StatelessWidget {
  const _MapFilterCard({
    required this.type,
    required this.radiusKm,
    required this.count,
    required this.fromDevice,
    required this.locating,
    required this.onType,
    required this.onRadius,
    required this.onLocate,
  });

  final String? type;
  final double? radiusKm;
  final int count;
  final bool fromDevice;
  final bool locating;
  final ValueChanged<String?> onType;
  final ValueChanged<double?> onRadius;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: PetsyColors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        boxShadow: [BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LostFoundTypeSwitch(value: type, onChanged: onType),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in _radiusOptions)
                  PetsyPill(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    label: radiusLabel(context, r),
                    selected: radiusKm == r,
                    onTap: () => onRadius(r),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const _LegendDot(color: PetsyColors.error),
              const SizedBox(width: 4),
              Text(context.t('lost'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              const _LegendDot(color: PetsyColors.accent),
              const SizedBox(width: 4),
              Text(context.t('found'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t('nearby_count').replaceAll('{count}', '$count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
                ),
              ),
              Tooltip(
                message: fromDevice ? context.t('use_my_location') : context.t('using_default_location'),
                child: Material(
                  color: fromDevice ? PetsyColors.primarySoft : PetsyColors.accentSoft,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: locating ? null : onLocate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (locating)
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            Icon(
                              fromDevice ? Icons.my_location_rounded : Icons.location_searching_rounded,
                              size: 14,
                              color: PetsyColors.primaryDark,
                            ),
                          const SizedBox(width: 5),
                          Text(
                            context.t(fromDevice ? 'lf_near_you' : 'lf_default_city'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        boxShadow: [BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(icon, color: PetsyColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.35)),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _OriginMarker extends StatelessWidget {
  const _OriginMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PetsyColors.primary.withValues(alpha: 0.22),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: PetsyColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.26), blurRadius: 6)],
        ),
      ),
    );
  }
}

class _MapBundle {
  const _MapBundle({required this.all, required this.filtered});
  final List<_MappedPost> all;
  final List<_MappedPost> filtered;
}

class _MappedPost {
  const _MappedPost({required this.post, required this.point, required this.km});
  final LostFoundPost post;
  final LatLng point;
  final double km;
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.type, this.focused = false});

  final String type;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final color = lostFoundColor(type);
    final size = focused ? 46.0 : 42.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(
          Icons.location_on_rounded,
          color: color,
          size: size,
          shadows: [Shadow(color: PetsyColors.ink.withValues(alpha: 0.38), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        Positioned(
          top: size * 0.17,
          child: Container(
            width: size * 0.42,
            height: size * 0.42,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.pets_rounded, size: size * 0.26, color: color),
          ),
        ),
      ],
    );
  }
}

/// Full-screen map picker used by the report form.
Future<LatLng?> showPickLocationMap(
  BuildContext context, {
  LatLng? initial,
  String? hintLocation,
}) async {
  var center = initial ?? GeoService.instance.fromKnownPlace(hintLocation ?? '') ?? petsyMapCenter;
  if (initial == null && hintLocation != null && hintLocation.trim().isNotEmpty) {
    center = await GeoService.instance.geocode(hintLocation) ?? center;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<LatLng>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PetsyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
    ),
    builder: (context) => _PickLocationSheet(initial: center),
  );
}

class _PickLocationSheet extends StatefulWidget {
  const _PickLocationSheet({required this.initial});
  final LatLng initial;

  @override
  State<_PickLocationSheet> createState() => _PickLocationSheetState();
}

class _PickLocationSheetState extends State<_PickLocationSheet> {
  late LatLng _point = widget.initial;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.t('pick_on_map'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('cancel'))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, size: 18, color: PetsyColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.t('pick_on_map_hint'),
                    style: const TextStyle(color: PetsyColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PetsyRadius.lg),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _point,
                    initialZoom: 13,
                    onTap: (_, latLng) => setState(() => _point = latLng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'company.petsy.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _point,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.place_rounded,
                            color: PetsyColors.primary,
                            size: 46,
                            shadows: [Shadow(color: PetsyColors.ink.withValues(alpha: 0.38), blurRadius: 5, offset: const Offset(0, 2))],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _point),
                icon: const Icon(Icons.check_rounded),
                label: Text(context.t('use_this_location')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
