import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_prefs.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/chat_session.dart';
import '../../state/app_state.dart';
import '../../state/badge_counts.dart';
import '../../widgets/common.dart';

enum _ChatListFilter { all, unread, muted, online }

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  static const _pollInterval = Duration(seconds: 8);

  final _view = GlobalKey<AsyncViewState<List<Conversation>>>();
  final _search = TextEditingController();
  Timer? _poll;
  StreamSubscription<ChatRealtimeEvent>? _wsSub;
  final _onlineIds = <String>{};
  String _query = '';
  _ChatListFilter _filterMode = _ChatListFilter.all;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      if (!context.read<AuthState>().isLoggedIn) return;
      _view.currentState?.reload();
    });
    _wsSub = ChatRealtimeService.instance.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'presence_update') {
        final uid = event.payload['user_id']?.toString();
        final online = event.payload['is_online'] == true;
        if (uid == null) return;
        setState(() {
          if (online) {
            _onlineIds.add(uid);
          } else {
            _onlineIds.remove(uid);
          }
        });
      } else if (event.type == 'conversations_updated' ||
          event.type == 'new_message' ||
          event.type == 'conversation_deleted') {
        _view.currentState?.reload();
        context.read<BadgeCountsState>().refresh();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _wsSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _isOnline(Conversation c) {
    final otherId = c.otherUser.id;
    return c.otherUser.isOnline || (otherId != null && _onlineIds.contains(otherId));
  }

  bool _isMuted(Conversation c) =>
      ChatPrefs.isMuted(context.read<SharedPreferences>(), c.id);

  List<Conversation> _filter(List<Conversation> items) {
    final q = _query.trim().toLowerCase();
    final prefs = context.read<SharedPreferences>();
    return items.where((c) {
      switch (_filterMode) {
        case _ChatListFilter.unread:
          if (c.unreadCount == 0) return false;
        case _ChatListFilter.muted:
          if (!ChatPrefs.isMuted(prefs, c.id)) return false;
        case _ChatListFilter.online:
          if (!_isOnline(c)) return false;
        case _ChatListFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final name = c.otherUser.name.toLowerCase();
      final last = (c.lastMessage ?? '').toLowerCase();
      return name.contains(q) || last.contains(q);
    }).toList();
  }

  Future<void> _deleteConversation(Conversation c, Future<void> Function() reload) async {
    final ok = await confirmAction(
      context,
      title: context.t('delete_conversation'),
      message: context.t('delete_conversation_confirm'),
      confirmLabel: context.t('delete'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.deleteConversation(c.id);
      if (!mounted) return;
      context.snack(context.t('conversation_deleted'));
      reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _openChatSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MessagesSettingsSheet(),
    );
    if (mounted) setState(() {});
  }

  String _emptyFilterText() {
    if (_query.trim().isNotEmpty) return context.t('no_search_results');
    return context.t(switch (_filterMode) {
      _ChatListFilter.unread => 'chat_no_unread',
      _ChatListFilter.muted => 'chat_no_muted',
      _ChatListFilter.online => 'chat_no_online',
      _ChatListFilter.all => 'no_search_results',
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthState>().isLoggedIn;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('messages')),
        actions: [
          if (loggedIn)
            IconButton(
              tooltip: context.t('chat_settings'),
              onPressed: _openChatSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: !loggedIn
          ? MessageView(
              icon: Icons.lock_outline,
              text: context.t('guest_hint'),
              action: TextButton(onPressed: () => context.push('/login'), child: Text(context.t('login'))),
            )
          : AsyncView<List<Conversation>>(
              key: _view,
              loader: context.api.conversations,
              builder: (context, items, reload) {
                final filtered = _filter(items);
                final unreadTotal = items.where((c) => c.unreadCount > 0).length;
                final onlineTotal = items.where(_isOnline).length;
                return RefreshIndicator(
                  onRefresh: reload,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(child: _MessagesHero()),
                      SliverToBoxAdapter(
                        child: PetsySearchField(
                          controller: _search,
                          hint: context.t('search_conversations'),
                          margin: const EdgeInsetsDirectional.fromSTEB(
                            PetsySpacing.page,
                            PetsySpacing.md,
                            PetsySpacing.page,
                            0,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                          onClear: () => setState(() => _query = ''),
                        ),
                      ),
                      if (items.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _MessagesStatsRow(
                            total: items.length,
                            unread: unreadTotal,
                            online: onlineTotal,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: _MessagesFilterBar(
                          selected: _filterMode,
                          unreadCount: unreadTotal,
                          onSelected: (f) => setState(() => _filterMode = f),
                        ),
                      ),
                      if (items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: MessageView(
                            icon: Icons.chat_bubble_outline_rounded,
                            text: '${context.t('no_conversations')}\n${context.t('chat_empty_body')}',
                            action: FilledButton.icon(
                              onPressed: () => context.go('/adoption'),
                              icon: const Icon(Icons.pets_rounded),
                              label: Text(context.t('chat_browse_pets')),
                            ),
                          ),
                        )
                      else if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: MessageView(
                            icon: switch (_filterMode) {
                              _ChatListFilter.unread => Icons.mark_chat_read_outlined,
                              _ChatListFilter.muted => Icons.notifications_off_outlined,
                              _ChatListFilter.online => Icons.wifi_off_rounded,
                              _ChatListFilter.all => Icons.search_off_rounded,
                            },
                            text: _emptyFilterText(),
                            action: _filterMode != _ChatListFilter.all || _query.isNotEmpty
                                ? TextButton(
                                    onPressed: () => setState(() {
                                      _filterMode = _ChatListFilter.all;
                                      _query = '';
                                      _search.clear();
                                    }),
                                    child: Text(context.t('clear')),
                                  )
                                : null,
                          ),
                        )
                      else ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              PetsySpacing.page,
                              PetsySpacing.xs,
                              PetsySpacing.page,
                              PetsySpacing.sm,
                            ),
                            child: Text(
                              context.t('chat_delete_hint'),
                              style: PetsyType.meta.copyWith(fontSize: 12),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            PetsySpacing.page,
                            0,
                            PetsySpacing.page,
                            PetsySpacing.listBottom,
                          ),
                          sliver: SliverList.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final c = filtered[i];
                              return _ConversationTile(
                                conversation: c,
                                online: _isOnline(c),
                                muted: _isMuted(c),
                                onLongPress: () => _deleteConversation(c, reload),
                                onTap: () async {
                                  await context.push('/chat/${c.id}');
                                  if (!mounted) return;
                                  this.context.read<BadgeCountsState>().refresh();
                                  reload();
                                },
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

class _MessagesHero extends StatefulWidget {
  const _MessagesHero();

  @override
  State<_MessagesHero> createState() => _MessagesHeroState();
}

class _MessagesHeroState extends State<_MessagesHero> with SingleTickerProviderStateMixin {
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
                    Color(0xFF1F6F68),
                    Color(0xFF2F9E8F),
                    Color(0xFF5BB8A8),
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
                top: -14,
                child: Icon(Icons.forum_rounded, size: 118, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -18,
                bottom: -24,
                child: Icon(Icons.chat_bubble_rounded, size: 90, color: Colors.white.withValues(alpha: 0.08)),
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
                        context.t('messages_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('messages_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('messages_subtitle'),
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

class _MessagesStatsRow extends StatelessWidget {
  const _MessagesStatsRow({
    required this.total,
    required this.unread,
    required this.online,
  });

  final int total;
  final int unread;
  final int online;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: Row(
        children: [
          Expanded(
            child: _MessagesStatCard(
              icon: Icons.forum_outlined,
              label: context.t('messages_total_stat').replaceAll('{count}', '$total'),
              color: PetsyColors.primary,
              soft: PetsyColors.primarySoft,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MessagesStatCard(
              icon: Icons.mark_chat_unread_outlined,
              label: context.t('messages_unread_stat').replaceAll('{count}', '$unread'),
              color: unread > 0 ? PetsyColors.primaryDark : PetsyColors.textSecondary,
              soft: unread > 0 ? PetsyColors.mist : PetsyColors.shellWash,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MessagesStatCard(
              icon: Icons.circle,
              label: context.t('messages_online_stat').replaceAll('{count}', '$online'),
              color: online > 0 ? PetsyColors.success : PetsyColors.textSecondary,
              soft: online > 0 ? PetsyColors.accentSoft : PetsyColors.shellWash,
              iconSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesStatCard extends StatelessWidget {
  const _MessagesStatCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.soft,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color soft;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.2,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesFilterBar extends StatelessWidget {
  const _MessagesFilterBar({
    required this.selected,
    required this.unreadCount,
    required this.onSelected,
  });

  final _ChatListFilter selected;
  final int unreadCount;
  final ValueChanged<_ChatListFilter> onSelected;

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
            _MessagesFilterChip(
              icon: Icons.forum_outlined,
              label: context.t('all'),
              selected: selected == _ChatListFilter.all,
              onTap: () => onSelected(_ChatListFilter.all),
            ),
            const SizedBox(width: 8),
            _MessagesFilterChip(
              icon: Icons.mark_chat_unread_outlined,
              label: context.t('chat_filter_unread'),
              selected: selected == _ChatListFilter.unread,
              count: unreadCount > 0 ? unreadCount : null,
              onTap: () => onSelected(_ChatListFilter.unread),
            ),
            const SizedBox(width: 8),
            _MessagesFilterChip(
              icon: Icons.circle,
              label: context.t('chat_filter_online'),
              selected: selected == _ChatListFilter.online,
              iconSize: 10,
              onTap: () => onSelected(_ChatListFilter.online),
            ),
            const SizedBox(width: 8),
            _MessagesFilterChip(
              icon: Icons.notifications_off_outlined,
              label: context.t('chat_filter_muted'),
              selected: selected == _ChatListFilter.muted,
              onTap: () => onSelected(_ChatListFilter.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesFilterChip extends StatelessWidget {
  const _MessagesFilterChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final accent = PetsyColors.accent;
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : PetsyColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? accent : PetsyColors.border),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: selected ? Colors.white : PetsyColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : PetsyColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : PetsyColors.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? accent : PetsyColors.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessagesSettingsSheet extends StatefulWidget {
  const _MessagesSettingsSheet();

  @override
  State<_MessagesSettingsSheet> createState() => _MessagesSettingsSheetState();
}

class _MessagesSettingsSheetState extends State<_MessagesSettingsSheet> {
  late bool _sound;
  late bool _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<SharedPreferences>();
    _sound = ChatPrefs.soundEnabled(prefs);
    _preview = ChatPrefs.previewEnabled(prefs);
  }

  Future<void> _setSound(bool value) async {
    setState(() {
      _busy = true;
      _sound = value;
    });
    try {
      await ChatPrefs.setSound(context.read<SharedPreferences>(), value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPreview(bool value) async {
    setState(() {
      _busy = true;
      _preview = value;
    });
    try {
      await ChatPrefs.setPreview(context.read<SharedPreferences>(), value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.backgroundAlt,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, PetsySpacing.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: PetsyColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: PetsySpacing.lg),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: PetsyColors.accentSoft,
                      borderRadius: BorderRadius.circular(PetsyRadius.md),
                    ),
                    child: const Icon(Icons.tune_rounded, color: PetsyColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.t('chat_settings'), style: PetsyType.section)),
                ],
              ),
              const SizedBox(height: PetsySpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: PetsyColors.surface,
                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                  border: Border.all(color: PetsyColors.border),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: _sound,
                      onChanged: _busy ? null : _setSound,
                      activeThumbColor: PetsyColors.accent,
                      title: Text(context.t('chat_sound'), style: PetsyType.body.copyWith(fontWeight: FontWeight.w800)),
                      subtitle: Text(context.t('chat_sound_hint'), style: PetsyType.meta),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      value: _preview,
                      onChanged: _busy ? null : _setPreview,
                      activeThumbColor: PetsyColors.accent,
                      title: Text(context.t('chat_preview'), style: PetsyType.body.copyWith(fontWeight: FontWeight.w800)),
                      subtitle: Text(context.t('chat_preview_hint'), style: PetsyType.meta),
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

String _chatTimeLabel(BuildContext context, DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  final locale = Localizations.localeOf(context).languageCode;
  if (diff == 0) return DateFormat.Hm(locale).format(local);
  if (diff == 1) return context.t('chat_yesterday');
  if (diff < 7) return DateFormat.EEEE(locale).format(local);
  return DateFormat.yMd(locale).format(local);
}

String _chatDayLabel(BuildContext context, DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return context.t('chat_today');
  if (diff == 1) return context.t('chat_yesterday');
  return DateFormat.yMMMMd(Localizations.localeOf(context).languageCode).format(day);
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.online,
    required this.muted,
    required this.onTap,
    required this.onLongPress,
  });

  final Conversation conversation;
  final bool online;
  final bool muted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unreadCount > 0;
    final last = (c.lastMessage ?? '').trim();
    final photoLabel = last == '📷';
    final mine = c.lastMessageSenderId != null && c.lastMessageSenderId == context.read<AuthState>().user?.id;
    final bodyText = photoLabel ? context.t('photo_message') : last;
    final subtitle = '${mine ? context.t('you_prefix') : ''}$bodyText';

    return Material(
      color: unread ? PetsyColors.accentSoft.withValues(alpha: 0.55) : PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(
              color: unread ? PetsyColors.accent.withValues(alpha: 0.35) : PetsyColors.border,
            ),
            boxShadow: unread ? PetsyShadows.soft : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: online ? PetsyColors.success : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: UserAvatar(name: c.otherUser.name, url: c.otherUser.avatar, radius: 25),
                  ),
                  if (online)
                    PositionedDirectional(
                      end: 2,
                      bottom: 2,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.otherUser.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.w900 : FontWeight.w800,
                              fontSize: 15.5,
                              color: PetsyColors.text,
                            ),
                          ),
                        ),
                        if (muted)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 4, end: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: PetsyColors.shellWash,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Icon(Icons.notifications_off_outlined, size: 13, color: PetsyColors.textLight),
                          ),
                        Text(
                          _chatTimeLabel(context, c.lastMessageTime),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                            color: unread ? PetsyColors.accent : PetsyColors.textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (mine) ...[
                          Icon(
                            c.lastMessageRead ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 16,
                            color: c.lastMessageRead ? PetsyColors.accent : PetsyColors.textLight,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (photoLabel) ...[
                          const Icon(Icons.photo_outlined, size: 15, color: PetsyColors.textSecondary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            subtitle.isEmpty ? '—' : subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread ? PetsyColors.text : PetsyColors.textSecondary,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: PetsyColors.accent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                            ),
                          ),
                        ],
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

void showChatImagePreview(BuildContext context, String? imageUrl) {
  final url = imageUrl?.trim() ?? '';
  if (url.isEmpty) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: PetsyColors.ink.withValues(alpha: 0.87),
      pageBuilder: (_, _, _) => _ChatImagePreviewPage(imageUrl: url),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ChatImagePreviewPage extends StatelessWidget {
  const _ChatImagePreviewPage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.ink,
      appBar: AppBar(
        backgroundColor: PetsyColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: NetImage(imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _pollInterval = Duration(seconds: 4);

  final _input = TextEditingController();
  final _search = TextEditingController();
  List<ChatMessage> _messages = [];
  ChatUser? _otherUser;
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  bool _otherTyping = false;
  bool _muted = false;
  bool _searching = false;
  String _searchQuery = '';
  ChatMessage? _replyTo;
  Timer? _poll;
  Timer? _typingIdle;
  Timer? _typingClear;
  StreamSubscription<ChatRealtimeEvent>? _wsSub;
  bool _iAmTyping = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    ChatSession.instance.enter(widget.conversationId);
    final prefs = context.read<SharedPreferences>();
    _muted = ChatPrefs.isMuted(prefs, widget.conversationId);
    _load();
    _poll = Timer.periodic(_pollInterval, (_) => _load(silent: true));
    ChatRealtimeService.instance.markRead(widget.conversationId);
    _wsSub = ChatRealtimeService.instance.events.listen(_onRealtime);
  }

  @override
  void dispose() {
    _setTyping(false);
    ChatSession.instance.leave(widget.conversationId);
    _poll?.cancel();
    _typingIdle?.cancel();
    _typingClear?.cancel();
    _wsSub?.cancel();
    _input.dispose();
    _search.dispose();
    super.dispose();
  }

  static DateTime? _dayOf(DateTime? t) {
    if (t == null) return null;
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static bool _sameGroup(ChatMessage a, ChatMessage b) {
    if (a.senderId != b.senderId) return false;
    final ta = a.createdAt, tb = b.createdAt;
    if (ta == null || tb == null) return true;
    return tb.difference(ta).inMinutes.abs() < 5;
  }

  List<ChatMessage> get _visibleMessages {
    final q = _searchQuery.trim().toLowerCase();
    if (!_searching || q.isEmpty) return _messages;
    const photoKeys = {'photo', 'صورة', 'image', 'pic', '📷'};
    return _messages.where((m) {
      if (m.content.toLowerCase().contains(q)) return true;
      if (m.hasImage && photoKeys.contains(q)) return true;
      return false;
    }).toList();
  }

  void _onRealtime(ChatRealtimeEvent event) {
    if (!mounted) return;
    final myId = context.read<AuthState>().user?.id;

    if (event.type == 'typing' && event.conversationId == widget.conversationId) {
      final uid = event.payload['user_id']?.toString();
      if (uid == null || uid == myId) return;
      final typing = event.payload['is_typing'] == true;
      _typingClear?.cancel();
      setState(() => _otherTyping = typing);
      if (typing) {
        _typingClear = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _otherTyping = false);
        });
      }
      return;
    }

    if (event.type == 'presence_update') {
      final uid = event.payload['user_id']?.toString();
      final other = _otherUser;
      if (other == null || uid == null || uid != other.id) return;
      setState(() => _otherUser = other.copyWith(isOnline: event.payload['is_online'] == true));
      return;
    }

    if (event.type == 'messages_read' && event.conversationId == widget.conversationId) {
      final reader = event.payload['reader_id']?.toString();
      if (reader == null || reader == myId) return;
      setState(() {
        _messages = [
          for (final m in _messages)
            if (m.senderId == myId && !m.isRead)
              ChatMessage(
                id: m.id,
                senderId: m.senderId,
                content: m.content,
                imageUrl: m.imageUrl,
                replyToMessageId: m.replyToMessageId,
                replyToContent: m.replyToContent,
                replyToSenderId: m.replyToSenderId,
                createdAt: m.createdAt,
                isRead: true,
              )
            else
              m,
        ];
      });
      return;
    }

    if (event.type == 'message_deleted' && event.conversationId == widget.conversationId) {
      final id = event.payload['message_id']?.toString();
      if (id == null) return;
      setState(() => _messages = _messages.where((m) => m.id != id).toList());
      return;
    }

    if (event.type == 'conversation_deleted' &&
        (event.conversationId == widget.conversationId ||
            event.payload['conversation_id']?.toString() == widget.conversationId)) {
      if (mounted) {
        context.snack(context.t('conversation_deleted'));
        context.pop();
      }
      return;
    }

    if (event.type == 'new_message' && event.conversationId == widget.conversationId) {
      final raw = event.payload['message'];
      if (raw is Map) {
        final msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
        if (!_messages.any((m) => m.id == msg.id)) {
          setState(() {
            _messages = [..._messages, msg];
            _otherTyping = false;
          });
          if (msg.senderId != myId) {
            ChatRealtimeService.instance.markRead(widget.conversationId);
            final prefs = context.read<SharedPreferences>();
            ChatPrefs.playIncomingSound(prefs);
          }
        }
      } else {
        _load(silent: true);
      }
    }
  }

  void _onInputChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText) {
      _setTyping(true);
      _typingIdle?.cancel();
      _typingIdle = Timer(const Duration(seconds: 2), () => _setTyping(false));
    } else {
      _setTyping(false);
    }
  }

  void _setTyping(bool typing) {
    if (_iAmTyping == typing) return;
    _iAmTyping = typing;
    ChatRealtimeService.instance.setTyping(
      conversationId: widget.conversationId,
      isTyping: typing,
    );
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final (other, messages) = await context.api.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _otherUser = other ?? _otherUser;
        _messages = messages;
        _error = null;
        _loading = false;
      });
      ChatRealtimeService.instance.markRead(widget.conversationId);
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _send({String? imageUrl}) async {
    final text = _input.text.trim();
    if (text.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;
    final reply = _replyTo;
    _setTyping(false);
    setState(() => _sending = true);
    try {
      final message = await context.api.sendMessage(
        widget.conversationId,
        content: text,
        imageUrl: imageUrl,
        replyToMessageId: reply?.id,
      );
      _input.clear();
      if (mounted) {
        setState(() {
          _replyTo = null;
          if (!_messages.any((m) => m.id == message.id)) {
            _messages = [..._messages, message];
          }
        });
      }
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachPhoto() async {
    if (_sending) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _sending = true);
      final url = await context.api.uploadImage(file.path);
      if (!mounted) return;
      await _send(imageUrl: url);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        context.snack(context.errorText(e), error: true);
      }
    }
  }

  Future<void> _toggleMute() async {
    final prefs = context.read<SharedPreferences>();
    final api = context.api;
    final next = !_muted;
    final ids = ChatPrefs.mutedIds(prefs);
    if (next) {
      ids.add(widget.conversationId);
    } else {
      ids.remove(widget.conversationId);
    }
    setState(() => _muted = next);
    try {
      await ChatPrefs.setMutedIds(prefs, ids);
      await api.updateUserSettings({'muted_conversation_ids': ids.toList()});
      if (mounted) {
        context.snack(
          context.t(next ? 'chat_muted' : 'chat_unmuted'),
          success: !next,
          icon: next ? Icons.notifications_off_rounded : Icons.notifications_active_outlined,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _muted = !next);
      context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _messageActions(ChatMessage message, {required bool mine}) async {
    final action = await showPetsyActionSheet<String>(
      context: context,
      title: context.t('messages'),
      actions: [
        PetsySheetAction(
          value: 'reply',
          label: context.t('reply_message'),
          icon: Icons.reply_outlined,
        ),
        if (message.content.trim().isNotEmpty)
          PetsySheetAction(
            value: 'copy',
            label: context.t('copy_message'),
            icon: Icons.copy_rounded,
          ),
        PetsySheetAction(
          value: 'forward',
          label: context.t('forward_message'),
          icon: Icons.reply_all_outlined,
        ),
        if (mine)
          PetsySheetAction(
            value: 'delete',
            label: context.t('delete_message'),
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'reply') {
      setState(() => _replyTo = message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.content));
      if (mounted) context.snack(context.t('message_copied'));
    } else if (action == 'forward') {
      await _forwardMessage(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final ok = await confirmAction(
      context,
      title: context.t('delete_message'),
      message: context.t('delete_message_confirm'),
      confirmLabel: context.t('delete'),
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await context.api.deleteMessage(widget.conversationId, message.id);
      if (!mounted) return;
      setState(() => _messages = _messages.where((m) => m.id != message.id).toList());
      context.snack(context.t('message_deleted'));
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    List<Conversation> conversations;
    try {
      conversations = await context.api.conversations();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
      return;
    }
    if (!mounted) return;
    final targets = conversations.where((c) => c.id != widget.conversationId).toList();
    if (targets.isEmpty) {
      context.snack(context.t('no_conversations'), error: true);
      return;
    }

    final targetId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Material(
        color: PetsyColors.backgroundAlt,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, PetsySpacing.page),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PetsyColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: PetsySpacing.lg),
                  Text(ctx.t('forward_to'), style: PetsyType.section),
                  const SizedBox(height: PetsySpacing.md),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: PetsyColors.surface,
                        borderRadius: BorderRadius.circular(PetsyRadius.lg),
                        border: Border.all(color: PetsyColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: targets.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: PetsyColors.border),
                        itemBuilder: (ctx, i) {
                          final c = targets[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: UserAvatar(name: c.otherUser.name, url: c.otherUser.avatar, radius: 22),
                            title: Text(c.otherUser.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            trailing: const PetsyChevron.forward(),
                            onTap: () => Navigator.pop(ctx, c.id),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: PetsySpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PetsyColors.text,
                        side: const BorderSide(color: PetsyColors.border),
                        backgroundColor: PetsyColors.surface,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(ctx.t('cancel')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (targetId == null || !mounted) return;

    final prefix = context.t('forwarded_prefix');
    final original = message.content.trim();
    final body = original.isEmpty
        ? prefix
        : original.startsWith(prefix)
            ? original
            : '$prefix $original';
    try {
      setState(() => _sending = true);
      await context.api.sendMessage(
        targetId,
        content: body,
        imageUrl: message.imageUrl,
      );
      if (mounted) context.snack(context.t('message_forwarded'));
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteConversation() async {
    final ok = await confirmAction(
      context,
      title: context.t('delete_conversation'),
      message: context.t('delete_conversation_confirm'),
      confirmLabel: context.t('delete'),
      icon: Icons.forum_outlined,
    );
    if (!ok || !mounted) return;
    try {
      await context.api.deleteConversation(widget.conversationId);
      if (!mounted) return;
      context.snack(context.t('conversation_deleted'));
      context.pop();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _sendQuick(String text) async {
    if (_sending) return;
    _input.text = text;
    await _send();
  }

  void _openOtherProfile() {
    final id = _otherUser?.id;
    if (id == null || id.isEmpty) return;
    context.push('/users/$id');
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AuthState>().user?.id;
    final other = _otherUser;
    final visible = _visibleMessages;
    final q = _searchQuery.trim();
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: context.t('search_messages'),
                  border: InputBorder.none,
                  hintStyle: const TextStyle(color: PetsyColors.textSecondary),
                ),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              )
            : other == null
                ? null
                : InkWell(
                    onTap: other.id == null || other.id!.isEmpty ? null : _openOtherProfile,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: other.isOnline ? PetsyColors.success : PetsyColors.border,
                                width: 1.6,
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                UserAvatar(name: other.name, url: other.avatar, radius: 18),
                                if (other.isOnline)
                                  PositionedDirectional(
                                    end: -1,
                                    bottom: -1,
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: BoxDecoration(
                                        color: PetsyColors.success,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  other.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: Text(
                                    _otherTyping
                                        ? context.t('typing')
                                        : other.isOnline
                                            ? context.t('online')
                                            : context.t('offline'),
                                    key: ValueKey(_otherTyping ? 'typing' : other.isOnline ? 'on' : 'off'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _otherTyping || other.isOnline
                                          ? PetsyColors.success
                                          : PetsyColors.textSecondary,
                                      fontStyle: _otherTyping ? FontStyle.italic : FontStyle.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
        actions: [
          IconButton(
            tooltip: context.t('search_messages'),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _searchQuery = '';
                }
              });
            },
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (!_searching) ...[
            IconButton(
              tooltip: context.t(_muted ? 'unmute_chat' : 'mute_chat'),
              onPressed: _toggleMute,
              icon: Icon(_muted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'profile') _openOtherProfile();
                if (v == 'delete') _deleteConversation();
              },
              itemBuilder: (ctx) => [
                if (other?.id != null && other!.id!.isNotEmpty)
                  PopupMenuItem(
                    value: 'profile',
                    child: Text(ctx.t('chat_open_profile')),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(ctx.t('delete_conversation'), style: const TextStyle(color: PetsyColors.error)),
                ),
              ],
            ),
          ],
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF8F4),
              PetsyColors.backgroundAlt,
              Color(0xFFF3F7F4),
            ],
          ),
        ),
        child: Column(
          children: [
            if (_muted && !_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.sm, PetsySpacing.page, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: PetsyColors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(PetsyRadius.md),
                    border: Border.all(color: PetsyColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: PetsyColors.shellWash,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.notifications_off_outlined, size: 16, color: PetsyColors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.t('muted'),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: PetsyColors.textSecondary),
                        ),
                      ),
                      PetsyPressScale(
                        onTap: _toggleMute,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: PetsyColors.accentSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            context.t('unmute_chat'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PetsyColors.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? MessageView(
                          icon: Icons.cloud_off,
                          text: context.errorText(_error!),
                          action: TextButton(onPressed: _load, child: Text(context.t('retry'))),
                        )
                      : visible.isEmpty
                          ? _ChatEmptyPane(
                              searching: _searching && q.isNotEmpty,
                              onQuick: _searching ? null : _sendQuick,
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                              itemCount: visible.length + (_otherTyping && !_searching ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (_otherTyping && !_searching && i == 0) {
                                  return const _TypingBubble();
                                }
                                final index = (_otherTyping && !_searching) ? i - 1 : i;
                                final k = visible.length - 1 - index;
                                final m = visible[k];
                                final prev = k > 0 ? visible[k - 1] : null;
                                final next = k < visible.length - 1 ? visible[k + 1] : null;
                                final day = _dayOf(m.createdAt);
                                final newDay = prev == null || day != _dayOf(prev.createdAt);
                                final groupedWithPrev = prev != null && !newDay && _sameGroup(prev, m);
                                final groupedWithNext =
                                    next != null && _dayOf(next.createdAt) == day && _sameGroup(m, next);
                                final mine = m.senderId == myId;
                                final highlighted =
                                    q.isNotEmpty && m.content.toLowerCase().contains(q.toLowerCase());
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (newDay && day != null) _DaySeparator(label: _chatDayLabel(context, day)),
                                    Padding(
                                      padding: EdgeInsets.only(top: groupedWithPrev ? 2 : 8),
                                      child: _Bubble(
                                        message: m,
                                        mine: mine,
                                        tail: !groupedWithNext,
                                        highlighted: highlighted,
                                        highlightQuery: highlighted ? q : null,
                                        onImageTap:
                                            m.hasImage ? () => showChatImagePreview(context, m.imageUrl) : null,
                                        onLongPress: () => _messageActions(m, mine: mine),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),
            if (!_searching) ...[
              if (_replyTo != null)
                Material(
                  color: PetsyColors.surface,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                    child: Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 0, 8),
                      decoration: BoxDecoration(
                        color: PetsyColors.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                        border: const BorderDirectional(start: BorderSide(color: PetsyColors.primary, width: 3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.reply_rounded, color: PetsyColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${context.t('replying_to')} ${_replyTo!.senderId == myId ? context.t('you') : (other?.name ?? '')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    color: PetsyColors.primaryDark,
                                  ),
                                ),
                                Text(
                                  _replyTo!.content.trim().isEmpty
                                      ? context.t('photo_message')
                                      : _replyTo!.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: PetsyColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => setState(() => _replyTo = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              MessageComposer(
                controller: _input,
                hint: context.t('type_message'),
                busy: _sending,
                onSend: () => _send(),
                onChanged: _onInputChanged,
                onAttach: _attachPhoto,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatEmptyPane extends StatelessWidget {
  const _ChatEmptyPane({required this.searching, this.onQuick});

  final bool searching;
  final Future<void> Function(String text)? onQuick;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return MessageView(
        icon: Icons.search_off_rounded,
        text: context.t('no_search_results'),
      );
    }
    final quick = [
      ('chat_quick_hi', Icons.waving_hand_outlined),
      ('chat_quick_available', Icons.help_outline_rounded),
      ('chat_quick_info', Icons.info_outline_rounded),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 24, PetsySpacing.page, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          decoration: BoxDecoration(
            color: PetsyColors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(color: PetsyColors.border),
            boxShadow: PetsyShadows.soft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PetsyColors.primarySoft, PetsyColors.mist],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.16)),
                ),
                child: const Icon(Icons.forum_outlined, size: 34, color: PetsyColors.primaryDark),
              ),
              const SizedBox(height: 14),
              Text(context.t('chat_say_hi'), textAlign: TextAlign.center, style: PetsyType.section.copyWith(fontSize: 17)),
              const SizedBox(height: 8),
              Text(
                context.t('chat_empty_hint'),
                textAlign: TextAlign.center,
                style: PetsyType.meta.copyWith(height: 1.4, fontSize: 13.5),
              ),
              if (onQuick != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final item in quick)
                      PetsyPressScale(
                        onTap: () => onQuick!(context.t(item.$1)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: PetsyColors.backgroundAlt,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: PetsyColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.$2, size: 15, color: PetsyColors.primaryDark),
                              const SizedBox(width: 6),
                              Text(
                                context.t(item.$1),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: PetsyColors.border, height: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: PetsyColors.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: PetsyColors.border),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: PetsyColors.textSecondary),
            ),
          ),
          const Expanded(child: Divider(color: PetsyColors.border, height: 1)),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: const BorderRadiusDirectional.only(
            topStart: Radius.circular(18),
            topEnd: Radius.circular(18),
            bottomEnd: Radius.circular(18),
            bottomStart: Radius.circular(6),
          ),
          border: Border.all(color: PetsyColors.border),
          boxShadow: [
            BoxShadow(color: PetsyColors.ink.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Semantics(
          label: context.t('typing'),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Transform.translate(
                    offset: Offset(0, -2.5 * (1 - ((_controller.value * 3 - i).abs() % 3).clamp(0.0, 1.0))),
                    child: Opacity(
                      opacity: 0.35 + 0.65 * (1 - ((_controller.value * 3 - i) % 3).clamp(0.0, 1.0)),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: PetsyColors.primary, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    this.onImageTap,
    this.onLongPress,
    this.highlighted = false,
    this.highlightQuery,
    this.tail = true,
  });

  final ChatMessage message;
  final bool mine;
  final bool tail;
  final VoidCallback? onImageTap;
  final VoidCallback? onLongPress;
  final bool highlighted;
  final String? highlightQuery;

  TextSpan _span(String text, Color color) {
    final q = highlightQuery?.trim() ?? '';
    if (q.isEmpty) {
      return TextSpan(text: text, style: TextStyle(color: color, height: 1.35, fontSize: 15, fontWeight: FontWeight.w600));
    }
    final lower = text.toLowerCase();
    final needle = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(needle, start);
      if (idx < 0) {
        spans.add(TextSpan(
          text: text.substring(start),
          style: TextStyle(color: color, height: 1.35, fontSize: 15, fontWeight: FontWeight.w600),
        ));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: TextStyle(color: color, height: 1.35, fontSize: 15, fontWeight: FontWeight.w600),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + needle.length),
        style: TextStyle(
          color: color,
          backgroundColor: const Color(0x66FFEB3B),
          fontWeight: FontWeight.w900,
          height: 1.35,
          fontSize: 15,
        ),
      ));
      start = idx + needle.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt;
    final metaColor = mine ? Colors.white.withValues(alpha: 0.78) : PetsyColors.textSecondary;
    final hasText = message.content.trim().isNotEmpty;
    final textColor = mine ? Colors.white : PetsyColors.text;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.fromLTRB(
            message.hasImage ? 5 : 14,
            message.hasImage ? 5 : 10,
            message.hasImage ? 5 : 14,
            8,
          ),
          decoration: BoxDecoration(
            color: mine ? PetsyColors.primary : PetsyColors.surface,
            gradient: mine
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD44318), PetsyColors.primary, PetsyColors.secondary],
                  )
                : null,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(20),
              topEnd: const Radius.circular(20),
              bottomStart: Radius.circular(!mine && tail ? 6 : 20),
              bottomEnd: Radius.circular(mine && tail ? 6 : 20),
            ),
            border: highlighted
                ? Border.all(color: PetsyColors.accent, width: 2)
                : (mine ? null : Border.all(color: PetsyColors.border)),
            boxShadow: [
              BoxShadow(
                color: (mine ? PetsyColors.primary : PetsyColors.ink).withValues(alpha: mine ? 0.2 : 0.05),
                blurRadius: mine ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isReply)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.fromLTRB(message.hasImage ? 2 : 0, 0, message.hasImage ? 2 : 0, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: (mine ? Colors.white : PetsyColors.primary).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: BorderDirectional(
                      start: BorderSide(color: mine ? Colors.white70 : PetsyColors.primary, width: 3),
                    ),
                  ),
                  child: Text(
                    message.replyToContent?.trim().isNotEmpty == true
                        ? message.replyToContent!
                        : context.t('photo_message'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: mine ? Colors.white.withValues(alpha: 0.82) : PetsyColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (message.hasImage)
                GestureDetector(
                  onTap: onImageTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: NetImage(message.imageUrl, fit: BoxFit.cover),
                    ),
                  ),
                ),
              if (hasText)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    message.hasImage ? 8 : 0,
                    message.hasImage ? 8 : 0,
                    message.hasImage ? 8 : 0,
                    0,
                  ),
                  child: Text.rich(_span(message.content, textColor)),
                ),
              const SizedBox(height: 3),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: message.hasImage ? 8 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (time != null)
                      Text(
                        DateFormat.Hm().format(time.toLocal()),
                        style: TextStyle(fontSize: 10.5, color: metaColor, fontWeight: FontWeight.w700),
                      ),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: context.t(message.isRead ? 'message_seen' : 'message_sent'),
                        child: Icon(
                          message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 15,
                          color: message.isRead ? Colors.white : metaColor,
                        ),
                      ),
                    ],
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
