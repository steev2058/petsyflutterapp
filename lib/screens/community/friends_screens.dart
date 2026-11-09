import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_realtime_service.dart';
import '../../state/app_state.dart';
import '../../state/badge_counts.dart';
import '../../widgets/common.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  int _reload = 0;
  final _onlineIds = <String>{};
  StreamSubscription<ChatRealtimeEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = ChatRealtimeService.instance.events.listen((event) {
      if (!mounted || event.type != 'presence_update') return;
      final uid = event.payload['user_id']?.toString();
      if (uid == null || uid.isEmpty) return;
      final online = event.payload['is_online'] == true;
      setState(() {
        if (online) {
          _onlineIds.add(uid);
        } else {
          _onlineIds.remove(uid);
        }
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  bool _isOnline(FriendUser f) => _onlineIds.contains(f.id) || f.isOnline;

  Future<(List<FriendUser>, FriendRequestsBundle, List<FriendUser>, List<FriendUser>)> _load() async {
    final api = context.api;
    final results = await Future.wait([
      api.friends(),
      api.friendRequests(),
      api.blockedFriends(),
      api.friendSuggestions(),
    ]);
    return (
      results[0] as List<FriendUser>,
      results[1] as FriendRequestsBundle,
      results[2] as List<FriendUser>,
      results[3] as List<FriendUser>,
    );
  }

  Future<void> _addSuggested(FriendUser user) async {
    try {
      final status = await context.api.sendFriendRequest(user.id);
      if (!mounted) return;
      final key = switch (status) {
        'friends' || 'already_friends' => 'already_friends',
        _ => 'friend_request_sent',
      };
      context.snack(context.t(key));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _review(String requestId, String action) async {
    try {
      await context.api.reviewFriendRequest(requestId, action: action);
      if (!mounted) return;
      context.snack(context.t(action == 'accept' ? 'friend_accepted' : 'friend_rejected'));
      context.read<BadgeCountsState>().refresh();
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _cancelOutgoing(FriendRequestItem request) async {
    try {
      await context.api.cancelFriendRequest(request.id);
      if (!mounted) return;
      context.snack(context.t('friend_request_cancelled'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _unblock(FriendUser user) async {
    try {
      await context.api.unblockFriend(user.id);
      if (!mounted) return;
      context.snack(context.t('user_unblocked'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _unfriend(FriendUser friend) async {
    final ok = await confirmAction(
      context,
      title: context.t('unfriend'),
      message: context.t('unfriend_confirm').replaceAll('{name}', friend.name),
      confirmLabel: context.t('unfriend'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.unfriend(friend.id);
      if (!mounted) return;
      context.snack(context.t('friend_removed'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _block(FriendUser friend) async {
    final ok = await confirmAction(
      context,
      title: context.t('block_user'),
      message: context.t('block_friend_confirm').replaceAll('{name}', friend.name),
      confirmLabel: context.t('block_user'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.blockFriend(friend.id);
      if (!mounted) return;
      context.snack(context.t('user_blocked'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  String _mutualLabel(FriendUser f) {
    if (f.mutualCount <= 0) return f.username == null || f.username!.isEmpty ? '' : '@${f.username}';
    final mutual = context.t('mutual_friends_count').replaceAll('{n}', '${f.mutualCount}');
    if (f.username == null || f.username!.isEmpty) return mutual;
    return '@${f.username} · $mutual';
  }

  Future<void> _openAndReload(String route, {bool refreshBadges = false}) async {
    await context.push(route);
    if (!mounted) return;
    if (refreshBadges) context.read<BadgeCountsState>().refresh();
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('friends')),
        actions: [
          IconButton(
            tooltip: context.t('friends_activity'),
            onPressed: () => context.push('/friends/activity'),
            icon: const Icon(Icons.dynamic_feed_outlined),
          ),
          IconButton(
            tooltip: context.t('invite_friend'),
            onPressed: () => _openAndReload('/friends/invite', refreshBadges: true),
            icon: const Icon(Icons.qr_code_2_outlined),
          ),
        ],
      ),
      body: AsyncView<(List<FriendUser>, FriendRequestsBundle, List<FriendUser>, List<FriendUser>)>(
        key: ValueKey(_reload),
        loader: _load,
        builder: (context, data, reload) {
          final (friends, requests, blocked, suggestions) = data;
          final tabs = <(String, IconData, int, bool)>[
            (context.t('friends'), Icons.people_outline_rounded, friends.length, false),
            (context.t('friend_incoming'), Icons.mark_email_unread_outlined, requests.incoming.length, true),
            (context.t('friend_outgoing'), Icons.outgoing_mail, requests.outgoing.length, false),
            (context.t('blocked_users'), Icons.block_rounded, blocked.length, false),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  PetsySpacing.page,
                  PetsySpacing.md,
                  PetsySpacing.page,
                  0,
                ),
                child: _FriendSearchLauncher(onTap: () => _openAndReload('/friends/search')),
              ),
              const SizedBox(height: PetsySpacing.md),
              AnimatedBuilder(
                animation: _tabs,
                builder: (context, _) => PetsyFilterRow(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      PetsyPill(
                        label: tabs[i].$1,
                        icon: tabs[i].$2,
                        count: tabs[i].$3 > 0 ? tabs[i].$3 : null,
                        highlightCount: tabs[i].$4,
                        selected: _tabs.index == i,
                        onTap: () => _tabs.animateTo(i),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _friendsTab(friends, suggestions, reload),
                    _listOrEmpty(
                      reload: reload,
                      isEmpty: requests.incoming.isEmpty,
                      emptyIcon: Icons.mark_email_unread_outlined,
                      emptyText: context.t('no_friend_requests'),
                      children: [
                        for (final r in requests.incoming)
                          _PersonCard(
                            name: r.user.name,
                            avatar: r.user.avatar,
                            subtitle: r.message?.trim().isNotEmpty == true
                                ? r.message!
                                : context.formatDate(r.createdAt),
                            onTap: () => context.push('/users/${r.user.id}'),
                            bottom: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                    onPressed: () => _review(r.id, 'accept'),
                                    icon: const Icon(Icons.check_rounded, size: 18),
                                    label: Text(context.t('accept')),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                    onPressed: () => _review(r.id, 'reject'),
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    label: Text(context.t('reject')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    _listOrEmpty(
                      reload: reload,
                      isEmpty: requests.outgoing.isEmpty,
                      emptyIcon: Icons.outgoing_mail,
                      emptyText: context.t('no_outgoing_requests'),
                      children: [
                        for (final r in requests.outgoing)
                          _PersonCard(
                            name: r.user.name,
                            avatar: r.user.avatar,
                            subtitle: context.t('friend_request_sent'),
                            subtitleIcon: Icons.hourglass_top_rounded,
                            onTap: () => context.push('/users/${r.user.id}'),
                            trailing: TextButton(
                              onPressed: () => _cancelOutgoing(r),
                              child: Text(context.t('cancel_request')),
                            ),
                          ),
                      ],
                    ),
                    _listOrEmpty(
                      reload: reload,
                      isEmpty: blocked.isEmpty,
                      emptyIcon: Icons.block_outlined,
                      emptyText: context.t('no_blocked_users'),
                      children: [
                        for (final u in blocked)
                          _PersonCard(
                            name: u.name,
                            avatar: u.avatar,
                            subtitle: u.username == null || u.username!.isEmpty ? null : '@${u.username}',
                            onTap: () => context.push('/users/${u.id}'),
                            trailing: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: () => _unblock(u),
                              child: Text(context.t('unblock_user')),
                            ),
                          ),
                      ],
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

  Widget _listOrEmpty({
    required Future<void> Function() reload,
    required bool isEmpty,
    required IconData emptyIcon,
    required String emptyText,
    required List<Widget> children,
  }) {
    return RefreshIndicator(
      onRefresh: reload,
      child: isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 64),
              children: [MessageView(icon: emptyIcon, text: emptyText)],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => children[i],
            ),
    );
  }

  Widget _friendsTab(List<FriendUser> friends, List<FriendUser> suggestions, Future<void> Function() reload) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (suggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 18, color: PetsyColors.primaryDark),
                  const SizedBox(width: 6),
                  Text(context.t('suggested_friends'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                ],
              ),
            ),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final s = suggestions[i];
                  final reason = s.suggestionReason == 'city'
                      ? context.t('suggestion_same_city').replaceAll('{city}', s.city ?? '')
                      : context.t('mutual_friends_count').replaceAll('{n}', '${s.mutualCount}');
                  return _SuggestionCard(
                    user: s,
                    reason: reason,
                    pending: s.friendshipStatus == 'outgoing_pending',
                    onAdd: () => _addSuggested(s),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: MessageView(
                icon: Icons.people_outline_rounded,
                text: context.t('no_friends_yet'),
                action: FilledButton.icon(
                  onPressed: () => _openAndReload('/friends/invite', refreshBadges: true),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(context.t('invite_friend')),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final f in friends) ...[
                    _PersonCard(
                      name: f.name,
                      avatar: f.avatar,
                      online: _isOnline(f),
                      subtitle: _mutualLabel(f).isEmpty ? null : _mutualLabel(f),
                      onTap: () => context.push('/users/${f.id}'),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: PetsyColors.textSecondary),
                        onSelected: (v) {
                          if (v == 'unfriend') _unfriend(f);
                          if (v == 'block') _block(f);
                          if (v == 'profile') context.push('/users/${f.id}');
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(value: 'profile', child: Text(ctx.t('view_profile'))),
                          PopupMenuItem(value: 'unfriend', child: Text(ctx.t('unfriend'))),
                          PopupMenuItem(
                            value: 'block',
                            child: Text(ctx.t('block_user'), style: const TextStyle(color: PetsyColors.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FriendSearchLauncher extends StatelessWidget {
  const _FriendSearchLauncher({required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_search_outlined, color: PetsyColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t('search_friends_hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.name,
    required this.onTap,
    this.avatar,
    this.subtitle,
    this.subtitleIcon,
    this.online = false,
    this.trailing,
    this.bottom,
  });

  final String name;
  final String? avatar;
  final String? subtitle;
  final IconData? subtitleIcon;
  final bool online;
  final Widget? trailing;
  final Widget? bottom;
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
          padding: EdgeInsetsDirectional.fromSTEB(12, 10, trailing == null ? 12 : 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(name: name, url: avatar, radius: 23),
                      if (online)
                        PositionedDirectional(
                          end: 0,
                          bottom: 0,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: PetsyColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (subtitleIcon != null) ...[
                                Icon(subtitleIcon, size: 13, color: PetsyColors.textLight),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PetsyColors.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 10),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.user,
    required this.reason,
    required this.pending,
    required this.onAdd,
  });

  final FriendUser user;
  final String reason;
  final bool pending;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: InkWell(
          onTap: () => context.push('/users/${user.id}'),
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.lg),
              border: Border.all(color: PetsyColors.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [PetsyColors.secondary, PetsyColors.primary]),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: UserAvatar(name: user.name, url: user.avatar, radius: 26),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: PetsyColors.textSecondary),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: pending
                      ? OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                          onPressed: null,
                          child: Text(context.t('friend_request_sent'), style: const TextStyle(fontSize: 11.5)),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                          onPressed: onAdd,
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                          label: Text(context.t('add_friend'), style: const TextStyle(fontSize: 12)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FriendSearchScreen extends StatefulWidget {
  const FriendSearchScreen({super.key});

  @override
  State<FriendSearchScreen> createState() => _FriendSearchScreenState();
}

class _FriendSearchScreenState extends State<FriendSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _busy = false;
  String? _error;
  List<FriendUser> _results = const [];
  final Set<String> _pendingIds = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await context.api.searchFriends(q);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.errorText(e);
        _results = const [];
      });
    }
  }

  Future<void> _sendRequest(FriendUser user) async {
    if (_pendingIds.contains(user.id)) return;
    setState(() => _pendingIds.add(user.id));
    try {
      final status = await context.api.sendFriendRequest(user.id);
      if (!mounted) return;
      final key = switch (status) {
        'friends' || 'already_friends' => 'already_friends',
        _ => 'friend_request_sent',
      };
      context.snack(context.t(key));
      await _search(_query.text);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _pendingIds.remove(user.id));
    }
  }

  Widget? _trailing(FriendUser user) {
    final status = user.friendshipStatus;
    Widget statusPill(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: PetsyColors.backgroundAlt, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: PetsyColors.textSecondary),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: PetsyColors.textSecondary)),
            ],
          ),
        );
    if (status == 'friends') return statusPill(Icons.check_rounded, context.t('already_friends'));
    if (status == 'outgoing_pending') return statusPill(Icons.hourglass_top_rounded, context.t('friend_request_sent'));
    if (status == 'incoming_pending') {
      return TextButton(
        onPressed: () => context.push('/friends'),
        child: Text(context.t('friend_incoming')),
      );
    }
    final pending = _pendingIds.contains(user.id);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: pending ? null : () => _sendRequest(user),
      icon: pending
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.person_add_alt_1_rounded, size: 17),
      label: Text(context.t('add_friend'), style: const TextStyle(fontSize: 12.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('search_friends'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() {});
                _onQueryChanged(v);
              },
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: context.t('search_friends_hint'),
                prefixIcon: const Icon(Icons.search_rounded, color: PetsyColors.primary),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.t('clear'),
                        onPressed: () {
                          _query.clear();
                          _onQueryChanged('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? MessageView(icon: Icons.error_outline, text: _error!)
                : _query.text.trim().length < 2
                    ? MessageView(icon: Icons.person_search_outlined, text: context.t('search_friends_hint'))
                    : _results.isEmpty && !_busy
                        ? MessageView(icon: Icons.search_off, text: context.t('no_search_results'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _results.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final u = _results[i];
                              final mutual = u.mutualCount > 0
                                  ? context.t('mutual_friends_count').replaceAll('{n}', '${u.mutualCount}')
                                  : null;
                              final subtitle = [
                                if (u.username != null && u.username!.isNotEmpty) '@${u.username}',
                                ?mutual,
                              ].join(' · ');
                              return _PersonCard(
                                name: u.name,
                                avatar: u.avatar,
                                subtitle: subtitle.isEmpty ? null : subtitle,
                                trailing: Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 6),
                                  child: _trailing(u),
                                ),
                                onTap: () => context.push('/users/${u.id}'),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class InviteFriendsScreen extends StatefulWidget {
  const InviteFriendsScreen({super.key, this.initialCode, this.autoScan = false});

  final String? initialCode;
  final bool autoScan;

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  late final TextEditingController _code = TextEditingController(text: widget.initialCode ?? '');
  final _qrKey = GlobalKey();
  FriendUser? _found;
  bool _busy = false;
  bool _sending = false;
  bool _sharingQr = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode?.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.autoScan) {
        await _scanQr();
        return;
      }
      if (initial != null && initial.isNotEmpty) {
        await _lookup();
      }
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _myCode => context.read<AuthState>().user?.userCode?.trim() ?? '';

  Future<File?> _captureQrPng() async {
    final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/petsy_invite_${_myCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  Future<void> _shareMine() async {
    final code = _myCode;
    if (code.isEmpty) {
      context.snack(context.t('invite_code_missing'), error: true);
      return;
    }
    final text = context.t('invite_share_text').replaceAll('{code}', code);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _shareQrImage() async {
    if (_myCode.isEmpty || _sharingQr) return;
    setState(() => _sharingQr = true);
    try {
      final file = await _captureQrPng();
      if (file == null) throw Exception('qr_capture_failed');
      if (!mounted) return;
      final text = context.t('invite_share_text').replaceAll('{code}', _myCode);
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile(file.path, mimeType: 'image/png', name: 'petsy-invite.png')],
        ),
      );
      if (mounted) context.snack(context.t('invite_qr_shared'));
    } catch (e) {
      if (mounted) context.snack(context.t('invite_qr_share_failed'), error: true);
    } finally {
      if (mounted) setState(() => _sharingQr = false);
    }
  }

  Future<void> _copyMine() async {
    final code = _myCode;
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    context.snack(context.t('invite_code_copied'));
  }

  Future<void> _lookup() async {
    final code = _code.text.trim();
    if (code.length < 3) {
      context.snack(context.t('invite_code_short'), error: true);
      return;
    }
    setState(() {
      _busy = true;
      _found = null;
    });
    try {
      final user = await context.api.lookupFriendByCode(code);
      if (!mounted) return;
      setState(() => _found = user);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final user = _found;
    if (user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final status = await context.api.sendFriendRequest(user.id);
      if (!mounted) return;
      final key = switch (status) {
        'friends' || 'already_friends' => 'already_friends',
        _ => 'friend_request_sent',
      };
      context.snack(context.t(key));
      context.read<BadgeCountsState>().refresh();
      setState(() {
        _found = FriendUser(
          id: user.id,
          name: user.name,
          avatar: user.avatar,
          username: user.username,
          userCode: user.userCode,
          city: user.city,
          mutualCount: user.mutualCount,
          friendshipStatus: status == 'friends' || status == 'already_friends' ? 'friends' : 'outgoing_pending',
        );
      });
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _normalizeScanned(String raw) {
    var value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final codeParam = uri.queryParameters['code'];
      if (codeParam != null && codeParam.trim().isNotEmpty) return codeParam.trim();
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'invite') {
        return uri.pathSegments.length > 1 ? uri.pathSegments[1] : value;
      }
    }
    final marker = '/invite/';
    final idx = value.indexOf(marker);
    if (idx >= 0) return value.substring(idx + marker.length).split(RegExp(r'[/?#]')).first;
    return value;
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      CupertinoPageRoute(builder: (_) => const _InviteQrScannerScreen()),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() => _code.text = _normalizeScanned(code));
    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final myCode = _myCode;
    final found = _found;
    final invitePayload = myCode.isEmpty ? '' : 'petsy://invite/$myCode';
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('invite_friend'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PetsyColors.secondary, PetsyColors.primary],
              ),
              boxShadow: [
                BoxShadow(
                  color: PetsyColors.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  context.t('your_invite_code'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 14),
                if (myCode.isNotEmpty)
                  RepaintBoundary(
                    key: _qrKey,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(PetsyRadius.lg),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrImageView(
                            data: invitePayload,
                            version: QrVersions.auto,
                            size: 188,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: PetsyColors.primaryDark),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: PetsyColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            myCode,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: PetsyColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text('Petsy', style: TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                else
                  const Text(
                    '—',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                const SizedBox(height: 12),
                Text(
                  context.t('invite_qr_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _InviteAction(
                      icon: Icons.copy_rounded,
                      label: context.t('copy_code'),
                      onTap: myCode.isEmpty ? null : _copyMine,
                    ),
                    const SizedBox(width: 8),
                    _InviteAction(
                      icon: Icons.ios_share_rounded,
                      label: context.t('share_invite'),
                      onTap: myCode.isEmpty ? null : _shareMine,
                    ),
                    const SizedBox(width: 8),
                    _InviteAction(
                      icon: Icons.image_outlined,
                      label: context.t('share_qr_image'),
                      busy: _sharingQr,
                      onTap: myCode.isEmpty || _sharingQr ? null : _shareQrImage,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PetsyColors.surface,
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              border: Border.all(color: PetsyColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.t('enter_invite_code'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.search,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _lookup(),
                  decoration: InputDecoration(
                    hintText: 'PET-XXXXXX',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: IconButton(
                      tooltip: context.t('search'),
                      onPressed: _busy ? null : _lookup,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(context.t('scan_invite_qr')),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (found != null) ...[
                  const SizedBox(height: 12),
                  _PersonCard(
                    name: found.name,
                    avatar: found.avatar,
                    subtitle: [
                      if (found.userCode != null && found.userCode!.isNotEmpty) found.userCode!,
                      if (found.mutualCount > 0)
                        context.t('mutual_friends_count').replaceAll('{n}', '${found.mutualCount}'),
                    ].join(' · '),
                    onTap: () => context.push('/users/${found.id}'),
                    trailing: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: found.friendshipStatus == 'friends'
                          ? Text(context.t('already_friends'),
                              style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w700))
                          : found.friendshipStatus == 'outgoing_pending'
                              ? Text(context.t('friend_request_sent'),
                                  style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w700))
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  onPressed: _sending ? null : _send,
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                                  label: Text(context.t('add_friend')),
                                ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteAction extends StatelessWidget {
  const _InviteAction({required this.icon, required this.label, this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: onTap == null && !busy ? 0.12 : 0.2),
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              children: [
                busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(icon, color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteQrScannerScreen extends StatefulWidget {
  const _InviteQrScannerScreen();

  @override
  State<_InviteQrScannerScreen> createState() => _InviteQrScannerScreenState();
}

class _InviteQrScannerScreenState extends State<_InviteQrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('scan_invite_qr'))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue?.trim();
            if (raw == null || raw.isEmpty) continue;
            _handled = true;
            Navigator.of(context).pop(raw);
            return;
          }
        },
      ),
    );
  }
}
