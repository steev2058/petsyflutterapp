import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/geo_service.dart';
import '../../widgets/common.dart';
import '../pets/lost_found_map_screen.dart' show lostFoundColor, lostFoundIcon;
import 'community_screens.dart' show postTypeColors, postTypeIcon, relativeTime;

enum _ActivityFilter { all, posts, reports, nearby }

class FriendsActivityScreen extends StatefulWidget {
  const FriendsActivityScreen({super.key});

  @override
  State<FriendsActivityScreen> createState() => _FriendsActivityScreenState();
}

class _FriendsActivityScreenState extends State<FriendsActivityScreen> {
  _ActivityFilter _filter = _ActivityFilter.all;

  Future<List<FriendActivityItem>> _load() async {
    final api = context.api;
    double? lat;
    double? lng;
    try {
      final loc = await GeoService.instance.currentLocation();
      if (loc.fromDevice) {
        lat = loc.point.latitude;
        lng = loc.point.longitude;
      }
    } catch (_) {}
    final items = await api.friendsActivity(lat: lat, lng: lng);
    return items
        .where((e) => (e.isCommunity && e.community != null) || (e.isLostFound && e.lostFound != null))
        .toList();
  }

  bool _matches(FriendActivityItem item, _ActivityFilter filter) => switch (filter) {
        _ActivityFilter.all => true,
        _ActivityFilter.posts => item.isCommunity,
        _ActivityFilter.reports => item.isLostFound,
        _ActivityFilter.nearby => item.isNearby,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('friends_activity'))),
      body: AsyncView<List<FriendActivityItem>>(
        loader: _load,
        isEmpty: (items) => false,
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 48),
                  MessageView(
                    icon: Icons.dynamic_feed_outlined,
                    text: '${context.t('no_friends_activity')}\n${context.t('activity_empty_body')}',
                    action: FilledButton.icon(
                      onPressed: () => context.push('/friends'),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(context.t('activity_find_friends')),
                    ),
                  ),
                ],
              ),
            );
          }
          final visible = items.where((e) => _matches(e, _filter)).toList();
          final filters = [
            (_ActivityFilter.all, context.t('all'), Icons.apps_rounded),
            (_ActivityFilter.posts, context.t('activity_filter_posts'), Icons.forum_outlined),
            (_ActivityFilter.reports, context.t('activity_filter_reports'), Icons.travel_explore_rounded),
            (_ActivityFilter.nearby, context.t('activity_filter_nearby'), Icons.near_me_outlined),
          ];
          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.xs,
                      PetsySpacing.page,
                      PetsySpacing.sm + 2,
                    ),
                    child: Text(
                      context.t('activity_subtitle'),
                      style: PetsyType.meta.copyWith(height: 1.4),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsyFilterRow(
                    children: [
                      for (final f in filters)
                        PetsyPill(
                          label: f.$2,
                          icon: f.$3,
                          count: items.where((e) => _matches(e, f.$1)).length,
                          selected: _filter == f.$1,
                          onTap: () => setState(() => _filter = f.$1),
                        ),
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageView(
                      icon: Icons.filter_alt_off_outlined,
                      text: context.t('activity_filter_empty'),
                      action: TextButton(
                        onPressed: () => setState(() => _filter = _ActivityFilter.all),
                        child: Text(context.t('all')),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      14,
                      PetsySpacing.page,
                      PetsySpacing.xl,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = visible[i];
                        return item.isCommunity
                            ? _CommunityActivityCard(key: ValueKey('c-${item.community!.id}'), item: item, post: item.community!)
                            : _LostFoundActivityCard(item: item, post: item.lostFound!);
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

class _ActivityShell extends StatelessWidget {
  const _ActivityShell({
    required this.item,
    required this.action,
    required this.actionIcon,
    required this.actionColor,
    required this.onTap,
    required this.child,
    this.highlight,
  });

  final FriendActivityItem item;
  final String action;
  final IconData actionIcon;
  final Color actionColor;
  final VoidCallback onTap;
  final Widget child;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PetsyRadius.xl);
    final time = relativeTime(context, item.createdAt);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: PetsyColors.primary.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: PetsyColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: highlight ?? PetsyColors.border, width: highlight == null ? 1 : 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => context.push('/users/${item.user.id}'),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(name: item.user.name, url: item.user.avatar, radius: 21),
                          PositionedDirectional(
                            bottom: -2,
                            end: -2,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: actionColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: PetsyColors.surface, width: 2),
                              ),
                              child: Icon(actionIcon, size: 11, color: Colors.white),
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
                          Text(
                            item.user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            [action, if (time.isNotEmpty) time].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityActivityCard extends StatefulWidget {
  const _CommunityActivityCard({super.key, required this.item, required this.post});

  final FriendActivityItem item;
  final CommunityPost post;

  @override
  State<_CommunityActivityCard> createState() => _CommunityActivityCardState();
}

class _CommunityActivityCardState extends State<_CommunityActivityCard> {
  late int _likes = widget.post.likes;
  bool _liked = false;
  bool _liking = false;

  Future<void> _like() async {
    if (_liked || _liking || !context.requireLogin()) return;
    setState(() {
      _liked = true;
      _liking = true;
      _likes++;
    });
    try {
      await context.api.likePost(widget.post.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = false;
        _likes = (_likes - 1).clamp(0, 1 << 30);
      });
      context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final (typeFg, typeBg) = postTypeColors(post.type);
    final hasImage = post.image != null && post.image!.trim().isNotEmpty;
    return _ActivityShell(
      item: widget.item,
      action: context.t('activity_posted_community'),
      actionIcon: Icons.forum_rounded,
      actionColor: PetsyColors.primary,
      onTap: () => context.push('/community/${post.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(99)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(postTypeIcon(post.type), size: 13, color: typeFg),
                const SizedBox(width: 4),
                Text(context.t(post.type), style: TextStyle(color: typeFg, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(post.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.3)),
          const SizedBox(height: 4),
          Text(
            post.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PetsyColors.textSecondary, height: 1.45),
          ),
          if (hasImage) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(PetsyRadius.lg),
              child: AspectRatio(aspectRatio: 16 / 9, child: NetImage(post.image, fit: BoxFit.cover)),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: PetsyColors.border),
          const SizedBox(height: 6),
          Row(
            children: [
              _ActivityAction(
                icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: '$_likes',
                color: _liked ? PetsyColors.error : PetsyColors.textSecondary,
                onTap: _liked || _liking ? null : _like,
              ),
              const SizedBox(width: 6),
              _ActivityAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${post.commentsCount}',
                color: PetsyColors.textSecondary,
                onTap: () => context.push('/community/${post.id}'),
              ),
              const Spacer(),
              _ActivityAction(
                icon: Icons.arrow_forward_rounded,
                label: context.t('activity_open'),
                color: PetsyColors.primaryDark,
                trailingIcon: true,
                onTap: () => context.push('/community/${post.id}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityAction extends StatelessWidget {
  const _ActivityAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailingIcon = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool trailingIcon;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18, color: color);
    final text = Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13));
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: trailingIcon
              ? [text, const SizedBox(width: 4), iconWidget]
              : [iconWidget, const SizedBox(width: 5), text],
        ),
      ),
    );
  }
}

class _LostFoundActivityCard extends StatelessWidget {
  const _LostFoundActivityCard({required this.item, required this.post});

  final FriendActivityItem item;
  final LostFoundPost post;

  @override
  Widget build(BuildContext context) {
    final color = lostFoundColor(post.type);
    final nearby = item.nearbyKm;
    final title = [
      context.t(post.petSpecies),
      if (post.breed != null && post.breed!.trim().isNotEmpty) post.breed!.trim(),
    ].join(' · ');
    return _ActivityShell(
      item: item,
      action: context.t(post.isLost ? 'activity_reported_lost' : 'activity_reported_found'),
      actionIcon: lostFoundIcon(post.type),
      actionColor: color,
      highlight: item.isNearby ? color.withValues(alpha: 0.55) : null,
      onTap: () => context.push('/lost-found/${post.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(PetsyRadius.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PetsyRadius.md),
                  child: SizedBox(width: 84, height: 84, child: NetImage(post.image, fit: BoxFit.cover)),
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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                          const Spacer(),
                          if (nearby != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.near_me_rounded, size: 13, color: PetsyColors.primaryDark),
                                const SizedBox(width: 3),
                                Text(
                                  context
                                      .t('activity_nearby_km')
                                      .replaceAll('{km}', nearby.toStringAsFixed(nearby < 10 ? 1 : 0)),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: PetsyColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 14, color: PetsyColors.textLight),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              post.lastSeenLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: PetsyColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        post.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: PetsyColors.textSecondary, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (item.isNearby) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.t('activity_nearby_hint'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
