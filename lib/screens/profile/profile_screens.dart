import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_prefs.dart';
import '../../services/fcm_service.dart';
import '../../services/lost_found_proximity_service.dart';
import '../../services/push_notification_service.dart';
import '../../state/app_state.dart';
import '../../state/badge_counts.dart';
import '../../data/phone_countries.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_field.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _view = GlobalKey<AsyncViewState<List<AppNotification>>>();
  String _filter = 'all'; // all | friend_request | chat | community | appointment

  static const _filters = <(String, String, IconData)>[
    ('all', 'notif_filter_all', Icons.notifications_none_rounded),
    ('friend_request', 'notif_filter_friends', Icons.person_add_alt_1_rounded),
    ('chat', 'notif_filter_chat', Icons.chat_bubble_outline_rounded),
    ('community', 'notif_filter_community', Icons.forum_outlined),
    ('appointment', 'notif_filter_appointments', Icons.calendar_month_outlined),
  ];

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _view.currentState?.reload();
      if (mounted) context.read<BadgeCountsState>().refresh();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  bool _matchesFilter(AppNotification n) {
    if (_filter == 'all') return true;
    if (_filter == 'appointment') {
      return n.type == 'appointment' || n.type == 'appointment_reminder';
    }
    return n.type == _filter;
  }

  String _friendTitle(AppNotification n) {
    final status = n.status;
    if (status == 'accepted') return context.t('notif_friend_accepted_title');
    if (status == 'rejected') return context.t('notif_friend_rejected_title');
    return context.t('notif_friend_incoming_title');
  }

  String _friendBody(AppNotification n) {
    final name = n.fromUserName?.trim().isNotEmpty == true ? n.fromUserName! : context.t('someone');
    final status = n.status;
    if (status == 'accepted') {
      return context.t('notif_friend_accepted_body').replaceAll('{name}', name);
    }
    if (status == 'rejected') {
      return context.t('notif_friend_rejected_body').replaceAll('{name}', name);
    }
    return context.t('notif_friend_incoming_body').replaceAll('{name}', name);
  }

  static const _appointmentStatuses = {'requested', 'confirmed', 'cancelled', 'completed'};

  /// Appointment notifications are stored in English; rebuild them in the user's language.
  (String, String)? _appointmentText(AppNotification n) {
    final status = n.status;
    final date = n.data['date']?.toString();
    final time = n.data['time']?.toString();
    if (!_appointmentStatuses.contains(status) || date == null || time == null) return null;
    final when = appointmentWhen(date, time, Localizations.localeOf(context).languageCode);
    final name = n.fromUserName?.trim().isNotEmpty == true ? n.fromUserName! : context.t('someone');
    return (
      context.t('notif_appt_${status}_title'),
      context.t('notif_appt_${status}_body').replaceAll('{when}', when).replaceAll('{name}', name),
    );
  }

  static const _adoptionStatuses = {'requested', 'accepted', 'declined', 'closed'};

  (String, String)? _adoptionText(AppNotification n) {
    final status = n.status;
    if (!_adoptionStatuses.contains(status)) return null;
    final pet = n.data['pet_name']?.toString() ?? context.t('pet');
    final name = n.fromUserName?.trim().isNotEmpty == true ? n.fromUserName! : context.t('someone');
    String fill(String key) => context.t(key).replaceAll('{pet}', pet).replaceAll('{name}', name);
    return (fill('notif_adoption_${status}_title'), fill('notif_adoption_${status}_body'));
  }

  Future<void> _reviewFriend(AppNotification n, String action) async {
    final requestId = n.requestId;
    if (requestId == null || requestId.isEmpty) {
      context.push(n.route ?? '/friends');
      return;
    }
    final api = context.api;
    try {
      await api.reviewFriendRequest(requestId, action: action);
      if (!n.isRead) await api.markNotificationRead(n.id);
      if (!mounted) return;
      context.snack(context.t(action == 'accept' ? 'friend_accepted' : 'friend_rejected'));
      context.read<BadgeCountsState>().refresh();
      await _view.currentState?.reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _confirmClear() async {
    final ok = await confirmAction(
      context,
      title: context.t('clear_all'),
      message: context.t('notif_clear_confirm'),
      confirmLabel: context.t('clear_all'),
      icon: Icons.notifications_off_outlined,
    );
    if (ok && mounted) {
      await _run(context.api.clearNotifications);
    }
  }

  Future<void> _openNotification(AppNotification n) async {
    final api = context.api;
    final isAppointment = n.type == 'appointment' || n.type == 'appointment_reminder';
    final isChat = n.type == 'chat';
    final isCommunity = n.type == 'community';
    final isFriend = n.type == 'friend_request';
    final chatRoute = n.route ?? (n.conversationId == null ? null : '/chat/${n.conversationId}');
    final communityRoute = n.route ?? (n.postId == null ? null : '/community/${n.postId}');
    final friendRoute = n.route ?? '/friends';

    if (!n.isRead) await _run(() => api.markNotificationRead(n.id));
    if (!mounted) return;
    if (isAppointment) {
      context.push(n.route == '/vet/appointments' ? '/vet/appointments' : '/appointments');
    } else if (isChat && chatRoute != null) {
      context.push(chatRoute);
    } else if (isCommunity && communityRoute != null) {
      context.push(communityRoute);
    } else if (isFriend) {
      context.push(friendRoute);
    } else if (n.route != null && n.route!.isNotEmpty) {
      context.push(n.route!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('notifications')),
        actions: [
          IconButton(
            tooltip: context.t('mark_all_read'),
            onPressed: () => _run(api.markAllNotificationsRead),
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: context.t('clear_all'),
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.page,
              PetsySpacing.xs,
              PetsySpacing.page,
              0,
            ),
            child: Text(
              context.t('notif_subtitle'),
              style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: PetsySpacing.md),
          PetsyFilterRow(
            children: [
              for (final (value, label, icon) in _filters)
                PetsyPill(
                  label: context.t(label),
                  icon: icon,
                  selected: _filter == value,
                  onTap: () => setState(() => _filter = value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncView<List<AppNotification>>(
              key: _view,
              loader: api.notifications,
              builder: (context, items, reload) {
                final visible = items.where(_matchesFilter).toList();
                final unread = items.where((n) => !n.isRead).length;
                final unreadLabel = unread == 0
                    ? context.t('notif_all_read')
                    : unread == 1
                        ? context.t('notif_unread_one')
                        : context.t('notif_unread').replaceAll('{count}', '$unread');

                if (visible.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 72),
                        MessageView(
                          icon: Icons.notifications_none_rounded,
                          text: items.isEmpty
                              ? '${context.t('notif_empty_title')}\n${context.t('notif_empty_body')}'
                              : context.t('notif_empty_filter'),
                          action: items.isNotEmpty && _filter != 'all'
                              ? TextButton(
                                  onPressed: () => setState(() => _filter = 'all'),
                                  child: Text(context.t('notif_filter_all')),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.xs,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    itemCount: visible.length + 1,
                    separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 10) : const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Text(
                          unreadLabel,
                          style: const TextStyle(
                            color: PetsyColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        );
                      }
                      final n = visible[i - 1];
                      final isAppointment = n.type == 'appointment' || n.type == 'appointment_reminder';
                      final isChat = n.type == 'chat';
                      final isCommunity = n.type == 'community';
                      final isFriend = n.type == 'friend_request';
                      final pendingFriend = isFriend &&
                          (n.status == null || n.status == 'pending' || n.action == 'incoming') &&
                          n.status != 'accepted' &&
                          n.status != 'rejected';
                      final localized = isAppointment
                          ? _appointmentText(n)
                          : n.type == 'adoption'
                              ? _adoptionText(n)
                              : n.type == 'push_test'
                                  ? ('Petsy', context.t('push_test_sent'))
                                  : null;
                      final title = isFriend ? _friendTitle(n) : localized?.$1 ?? n.title;
                      final body = isFriend ? _friendBody(n) : localized?.$2 ?? n.body;
                      return _NotificationCard(
                        notification: n,
                        title: title,
                        body: body,
                        isAppointment: isAppointment,
                        isChat: isChat,
                        isCommunity: isCommunity,
                        isFriend: isFriend,
                        pendingFriend: pendingFriend,
                        onTap: () => _openNotification(n),
                        onAccept: () => _reviewFriend(n, 'accept'),
                        onReject: () => _reviewFriend(n, 'reject'),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.title,
    required this.body,
    required this.isAppointment,
    required this.isChat,
    required this.isCommunity,
    required this.isFriend,
    required this.pendingFriend,
    required this.onTap,
    required this.onAccept,
    required this.onReject,
  });

  final AppNotification notification;
  final String title;
  final String body;
  final bool isAppointment;
  final bool isChat;
  final bool isCommunity;
  final bool isFriend;
  final bool pendingFriend;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final soft = isFriend
        ? PetsyColors.accentSoft
        : isAppointment
            ? PetsyColors.mist
            : isChat
                ? PetsyColors.primarySoft
                : isCommunity
                    ? const Color(0xFFF3EEE8)
                    : PetsyColors.primarySoft;
    final ink = isFriend
        ? PetsyColors.accent
        : isAppointment
            ? PetsyColors.primaryDark
            : isChat
                ? PetsyColors.primary
                : isCommunity
                    ? PetsyColors.primaryDark
                    : PetsyColors.primary;
    final icon = isAppointment
        ? Icons.calendar_month_rounded
        : isChat
            ? Icons.chat_bubble_rounded
            : isCommunity
                ? Icons.forum_rounded
                : isFriend
                    ? Icons.person_add_alt_1_rounded
                    : notification.type == 'adoption'
                        ? Icons.volunteer_activism_rounded
                        : Icons.notifications_rounded;

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(
              color: notification.isRead ? PetsyColors.border : PetsyColors.primary.withValues(alpha: 0.28),
            ),
            color: notification.isRead ? PetsyColors.surface : soft,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: notification.isRead ? soft : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: ink, size: 22),
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
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w800,
                                    fontSize: 15,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              if (!notification.isRead) ...[
                                const SizedBox(width: PetsySpacing.sm),
                                PetsyMetaBadge(
                                  label: context.t('notif_new'),
                                  tone: PetsyMetaTone.primary,
                                ),
                              ],
                            ],
                          ),
                          if (body.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PetsyColors.textSecondary,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            context.formatDate(notification.createdAt, withTime: true),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: PetsyColors.textLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: PetsyChevron.forward(),
                    ),
                  ],
                ),
                if (pendingFriend && notification.requestId != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: onAccept,
                          child: Text(context.t('accept')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onReject,
                          child: Text(context.t('reject')),
                        ),
                      ),
                    ],
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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final badges = context.watch<BadgeCountsState>();

    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('profile')),
        actions: [
          if (user != null)
            IconButton(
              tooltip: context.t('edit_profile'),
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: context.t('notifications'),
            onPressed: () async {
              await context.push('/notifications');
              if (context.mounted) context.read<BadgeCountsState>().refresh();
            },
            icon: Badge(
              isLabelVisible: badges.notifications > 0,
              label: Text(badges.notifications > 99 ? '99+' : '${badges.notifications}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _ProfileHeroBanner()),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.page,
              PetsySpacing.md,
              PetsySpacing.page,
              PetsySpacing.listBottom,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (user == null)
                  const _ProfileGuestCard()
                else ...[
                  _ProfileHeader(user: user),
                  const SizedBox(height: PetsySpacing.md),
                  _ProfileSectionLabel(context.t('profile_section_services')),
                  const SizedBox(height: PetsySpacing.sm),
                  _ProfileQuickActions(notificationBadge: badges.notifications),
                  const SizedBox(height: PetsySpacing.xl),
                  _ProfileSectionLabel(context.t('profile_section_account')),
                  const SizedBox(height: PetsySpacing.sm),
                  _ProfileMenuGroup(
                    children: [
                      if (user.role == 'vet')
                        _ProfileMenuTile(
                          icon: Icons.medical_services_outlined,
                          label: context.t('vet_clinic_title'),
                          color: PetsyColors.accent,
                          iconSoft: PetsyColors.accentSoft,
                          onTap: () => context.push('/vet/appointments'),
                        ),
                      if (user.isAdmin || user.role == 'admin')
                        _ProfileMenuTile(
                          icon: Icons.school_outlined,
                          label: context.t('trainer_review_title'),
                          color: PetsyColors.accent,
                          iconSoft: PetsyColors.accentSoft,
                          onTap: () => context.push('/admin/trainer-applications'),
                        ),
                      _ProfileMenuTile(
                        icon: Icons.favorite_border_rounded,
                        label: context.t('favorites_title'),
                        onTap: () => context.push('/favorites'),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.volunteer_activism_outlined,
                        label: context.t('adoption_requests_title'),
                        onTap: () => context.push('/adoption-requests'),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.people_outline_rounded,
                        label: context.t('friends'),
                        badge: badges.friendRequests,
                        onTap: () async {
                          await context.push('/friends');
                          if (context.mounted) context.read<BadgeCountsState>().refresh();
                        },
                      ),
                      _ProfileMenuTile(
                        icon: Icons.dynamic_feed_outlined,
                        label: context.t('friends_activity'),
                        onTap: () => context.push('/friends/activity'),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.edit_outlined,
                        label: context.t('edit_profile'),
                        onTap: () => context.push('/edit-profile'),
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: PetsySpacing.xl),
                  _ProfileSectionLabel(context.t('profile_section_settings')),
                  const SizedBox(height: PetsySpacing.sm),
                  const _PushSettingsCard(),
                  const SizedBox(height: PetsySpacing.md),
                  const _ChatSettingsCard(),
                  const SizedBox(height: PetsySpacing.md),
                  const _FriendPrivacyCard(),
                ],
                const SizedBox(height: PetsySpacing.xl),
                _ProfileSectionLabel(context.t('profile_section_explore')),
                const SizedBox(height: PetsySpacing.sm),
                const _ProfileExploreGrid(),
                const SizedBox(height: PetsySpacing.md),
                _ProfileMenuGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: PetsyColors.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.language_rounded, color: PetsyColors.primaryDark, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.t('language'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          _ProfileLanguageToggle(isArabic: isArabic),
                        ],
                      ),
                    ),
                  ],
                ),
                if (user != null) ...[
                  const SizedBox(height: PetsySpacing.lg),
                  _ProfileMenuGroup(
                    children: [
                      _ProfileMenuTile(
                        icon: Icons.logout_rounded,
                        label: context.t('logout'),
                        color: PetsyColors.error,
                        iconSoft: const Color(0xFFFFE8E6),
                        onTap: () async {
                          final ok = await confirmAction(
                            context,
                            title: context.t('logout_confirm_title'),
                            message: context.t('logout_confirm_message'),
                            confirmLabel: context.t('logout'),
                            icon: Icons.logout_rounded,
                          );
                          if (ok) await auth.logout();
                        },
                        showDivider: false,
                        showChevron: false,
                      ),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeroBanner extends StatefulWidget {
  const _ProfileHeroBanner();

  @override
  State<_ProfileHeroBanner> createState() => _ProfileHeroBannerState();
}

class _ProfileHeroBannerState extends State<_ProfileHeroBanner> with SingleTickerProviderStateMixin {
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
                    Color(0xFFFF5C2E),
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
                top: -10,
                child: Icon(Icons.person_rounded, size: 120, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -20,
                bottom: -26,
                child: Icon(Icons.pets_rounded, size: 92, color: Colors.white.withValues(alpha: 0.08)),
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
                        context.t('profile_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('profile_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('profile_subtitle'),
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

class _ProfileSectionLabel extends StatelessWidget {
  const _ProfileSectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: PetsyType.meta.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: PetsyColors.text,
      ),
    );
  }
}

class _ProfileGuestCard extends StatelessWidget {
  const _ProfileGuestCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: PetsyColors.border),
        boxShadow: PetsyShadows.soft,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: PetsyColors.primarySoft, width: 3),
            ),
            child: const UserAvatar(name: '?', radius: 40),
          ),
          const SizedBox(height: 14),
          Text(context.t('guest'), style: PetsyType.title.copyWith(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            context.t('guest_hint'),
            textAlign: TextAlign.center,
            style: PetsyType.meta.copyWith(height: 1.4, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/login'),
              icon: const Icon(Icons.login_rounded),
              label: Text(context.t('profile_login_cta')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (user.city != null && user.city!.trim().isNotEmpty) user.city!.trim(),
      if (user.userCode != null && user.userCode!.trim().isNotEmpty)
        '${context.t('profile_member_code')}: ${user.userCode}',
    ];

    return PetsyPressScale(
      onTap: () => context.push('/edit-profile'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.soft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: PetsyColors.primarySoft, width: 3),
              ),
              child: UserAvatar(name: user.name, url: user.avatar, radius: 36),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('profile_welcome_back'),
                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PetsyColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PetsyColors.textLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (user.bio != null && user.bio!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      user.bio!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PetsyColors.primaryDark,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PetsyMetaBadge(
                        label: context.t('role_${user.role}'),
                        icon: Icons.badge_outlined,
                        tone: PetsyMetaTone.primary,
                      ),
                      if (user.isVerified)
                        PetsyMetaBadge(
                          label: context.t('profile_verified'),
                          icon: Icons.verified_rounded,
                          tone: PetsyMetaTone.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t('profile_tap_edit'),
                    style: PetsyType.meta.copyWith(fontSize: 11.5, color: PetsyColors.primaryDark),
                  ),
                ],
              ),
            ),
            const PetsyChevron.forward(color: PetsyColors.textLight),
          ],
        ),
      ),
    );
  }
}

class _ProfileQuickActions extends StatelessWidget {
  const _ProfileQuickActions({required this.notificationBadge});

  final int notificationBadge;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Color, Color, VoidCallback, int)>[
      (
        Icons.pets_rounded,
        context.t('my_pets'),
        PetsyColors.primarySoft,
        PetsyColors.primaryDark,
        () => context.push('/my-pets'),
        0,
      ),
      (
        Icons.calendar_month_rounded,
        context.t('appointments'),
        PetsyColors.mist,
        PetsyColors.primaryDark,
        () => context.push('/appointments'),
        0,
      ),
      (
        Icons.receipt_long_rounded,
        context.t('orders'),
        PetsyColors.accentSoft,
        PetsyColors.accent,
        () => context.push('/orders'),
        0,
      ),
      (
        Icons.favorite_border_rounded,
        context.t('favorites_title'),
        const Color(0xFFFFF0F2),
        const Color(0xFFC23A55),
        () => context.push('/favorites'),
        0,
      ),
      (
        Icons.shopping_bag_outlined,
        context.t('cart'),
        PetsyColors.shellWash,
        PetsyColors.primaryDark,
        () => context.push('/cart'),
        0,
      ),
      (
        Icons.notifications_outlined,
        context.t('notifications'),
        PetsyColors.primarySoft,
        PetsyColors.primaryDark,
        () async {
          await context.push('/notifications');
          if (context.mounted) context.read<BadgeCountsState>().refresh();
        },
        notificationBadge,
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ProfileQuickTile(
                    icon: items[row * 3 + col].$1,
                    label: items[row * 3 + col].$2,
                    soft: items[row * 3 + col].$3,
                    ink: items[row * 3 + col].$4,
                    onTap: items[row * 3 + col].$5,
                    badge: items[row * 3 + col].$6,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ProfileQuickTile extends StatelessWidget {
  const _ProfileQuickTile({
    required this.icon,
    required this.label,
    required this.soft,
    required this.ink,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final Color soft;
  final Color ink;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: ink.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : '$badge'),
              child: Icon(icon, color: ink, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileExploreGrid extends StatelessWidget {
  const _ProfileExploreGrid();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Color, Color, VoidCallback)>[
      (Icons.medical_services_outlined, context.t('vets'), PetsyColors.accentSoft, PetsyColors.accent, () => context.push('/vets')),
      (Icons.forum_outlined, context.t('community'), PetsyColors.primarySoft, PetsyColors.primaryDark, () => context.push('/community')),
      (Icons.travel_explore_rounded, context.t('lost_found'), PetsyColors.mist, PetsyColors.primaryDark, () => context.push('/lost-found')),
      (Icons.shield_outlined, context.t('guard_dogs'), const Color(0xFFE8EEF8), const Color(0xFF3B82B0), () => context.push('/guard-dogs')),
      (Icons.school_outlined, context.t('training'), PetsyColors.shellWash, PetsyColors.primaryDark, () => context.push('/training')),
      (Icons.storefront_outlined, context.t('shop'), PetsyColors.primarySoft, PetsyColors.primaryDark, () => context.go('/shop')),
    ];

    return Column(
      children: [
        for (var row = 0; row < items.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _exploreTile(items[row])),
              const SizedBox(width: 8),
              Expanded(
                child: row + 1 < items.length ? _exploreTile(items[row + 1]) : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _exploreTile((IconData, String, Color, Color, VoidCallback) item) {
    return PetsyPressScale(
      onTap: item.$5,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: PetsyColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: item.$3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.$1, color: item.$4, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: item.$4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileLanguageToggle extends StatelessWidget {
  const _ProfileLanguageToggle({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PetsyColors.backgroundAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangChip(
            label: context.t('arabic'),
            selected: isArabic,
            onTap: () => context.read<LocaleState>().setLanguage('ar'),
          ),
          _LangChip(
            label: context.t('english'),
            selected: !isArabic,
            onTap: () => context.read<LocaleState>().setLanguage('en'),
          ),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: selected ? Colors.white : PetsyColors.text,
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuGroup extends StatelessWidget {
  const _ProfileMenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      elevation: 0,
      shadowColor: PetsyColors.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        side: const BorderSide(color: PetsyColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.color,
    this.iconSoft,
    this.showDivider = true,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final Color? color;
  final Color? iconSoft;
  final bool showDivider;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? PetsyColors.text;
    final soft = iconSoft ?? (color != null ? color!.withValues(alpha: 0.12) : PetsyColors.primarySoft);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text(badge > 99 ? '99+' : '$badge'),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color ?? PetsyColors.primaryDark, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ink),
                    ),
                  ),
                  if (showChevron) PetsyChevron.forward(color: color ?? PetsyColors.textLight),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 66, endIndent: 14, color: PetsyColors.border),
      ],
    );
  }
}

class _PushSettingsCard extends StatefulWidget {
  const _PushSettingsCard();

  @override
  State<_PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends State<_PushSettingsCard> {
  bool? _enabled;
  bool? _lfAlerts;
  double _lfKm = 10;
  bool _busy = false;

  static const _lfRadiusOptions = <double>[5, 10, 25, 50];

  @override
  void initState() {
    super.initState();
    final prefs = context.read<SharedPreferences>();
    PushNotificationService.instance.areEnabled(prefs).then((v) {
      if (mounted) setState(() => _enabled = v);
    });
    LostFoundProximityService.instance.areEnabled(prefs).then((v) {
      if (mounted) {
        setState(() {
          _lfAlerts = v;
          _lfKm = LostFoundProximityService.instance.alertKm(prefs);
        });
      }
    });
  }

  Future<void> _setEnabled(bool value) async {
    final prefs = context.read<SharedPreferences>();
    final api = context.api;
    final reminderTitle = context.t('appointment_reminder');
    final lang = Localizations.localeOf(context).languageCode;
    final denied = context.t('push_permission_denied');
    final push = PushNotificationService.instance;
    setState(() {
      _enabled = value;
      _busy = true;
    });
    try {
      if (value) {
        final ok = await push.requestPermission();
        if (!ok) {
          if (!mounted) return;
          context.snack(denied, error: true);
          setState(() => _enabled = false);
          return;
        }
        await push.setEnabled(prefs, true);
        await push.registerWithBackend(api, prefs);
        final appointments = await api.appointments();
        await push.syncAppointments(
          appointments: appointments,
          title: reminderTitle,
          bodyFor: (a) => '${a.reason} · ${a.when(lang)}',
        );
      } else {
        await push.setEnabled(prefs, false);
      }
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final api = context.api;
    final denied = context.t('push_permission_denied');
    final testTitle = context.t('push_test');
    final testSent = context.t('push_test_sent');
    setState(() => _busy = true);
    try {
      final ok = await PushNotificationService.instance.requestPermission();
      if (!ok) {
        if (mounted) context.snack(denied, error: true);
        return;
      }
      await api.pushTest();
      await PushNotificationService.instance.showNow(
        title: testTitle,
        body: testSent,
        id: 900002,
      );
      if (mounted) context.snack(testSent);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? true;
    return _ProfileMenuGroup(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          secondary: const _SettingsIcon(Icons.notifications_active_outlined),
          title: Text(context.t('push_enabled'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('push_enabled_hint'), style: PetsyType.meta),
          value: enabled,
          onChanged: _busy || _enabled == null ? null : _setEnabled,
        ),
        ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          leading: const _SettingsIcon(Icons.notification_add_outlined),
          title: Text(context.t('push_test'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          trailing: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const PetsyChevron.forward(),
          onTap: enabled && !_busy ? _test : null,
        ),
        ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          leading: _SettingsIcon(
            FcmService.instance.isReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          ),
          title: Text(
            context.t(FcmService.instance.isReady ? 'fcm_ready' : 'fcm_pending'),
            style: PetsyType.meta,
          ),
        ),
        const Divider(height: PetsySpacing.sm),
        SwitchListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          secondary: const _SettingsIcon(Icons.pets_outlined),
          title: Text(context.t('lf_alerts_enabled'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('lf_alerts_hint'), style: PetsyType.meta),
          value: enabled && (_lfAlerts ?? true),
          onChanged: !enabled || _busy || _lfAlerts == null
              ? null
              : (v) async {
                  final prefs = context.read<SharedPreferences>();
                  setState(() => _lfAlerts = v);
                  await LostFoundProximityService.instance.setEnabled(prefs, v);
                },
        ),
        if (enabled && (_lfAlerts ?? true))
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              PetsySpacing.lg,
              0,
              PetsySpacing.lg,
              PetsySpacing.sm + 2,
            ),
            child: Row(
              children: [
                Expanded(child: Text(context.t('lf_alert_radius'))),
                DropdownButton<double>(
                  value: _lfRadiusOptions.contains(_lfKm) ? _lfKm : 10,
                  items: [
                    for (final km in _lfRadiusOptions)
                      DropdownMenuItem(
                        value: km,
                        child: Text(context.t('within_km').replaceAll('{km}', '${km.round()}')),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) async {
                          if (v == null) return;
                          final prefs = context.read<SharedPreferences>();
                          setState(() => _lfKm = v);
                          await LostFoundProximityService.instance.setAlertKm(prefs, v);
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChatSettingsCard extends StatefulWidget {
  const _ChatSettingsCard();

  @override
  State<_ChatSettingsCard> createState() => _ChatSettingsCardState();
}

class _ChatSettingsCardState extends State<_ChatSettingsCard> {
  bool? _sound;
  bool? _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<SharedPreferences>();
    _sound = ChatPrefs.soundEnabled(prefs);
    _preview = ChatPrefs.previewEnabled(prefs);
    _refreshFromApi();
  }

  Future<void> _refreshFromApi() async {
    final api = context.api;
    final prefs = context.read<SharedPreferences>();
    try {
      final settings = await api.userSettings();
      await ChatPrefs.applyFromSettings(prefs, settings);
      if (!mounted) return;
      setState(() {
        _sound = settings.chatSound;
        _preview = settings.chatPreview;
      });
    } catch (_) {}
  }

  Future<void> _setSound(bool value) async {
    final prefs = context.read<SharedPreferences>();
    final api = context.api;
    setState(() {
      _sound = value;
      _busy = true;
    });
    try {
      await ChatPrefs.setSound(prefs, value);
      await api.updateUserSettings({'chat_sound': value});
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPreview(bool value) async {
    final prefs = context.read<SharedPreferences>();
    final api = context.api;
    setState(() {
      _preview = value;
      _busy = true;
    });
    try {
      await ChatPrefs.setPreview(prefs, value);
      await api.updateUserSettings({'chat_preview': value});
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileMenuGroup(
      children: [
        _SettingsHeader(context.t('chat_settings')),
        SwitchListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          secondary: const _SettingsIcon(Icons.volume_up_outlined),
          title: Text(context.t('chat_sound'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('chat_sound_hint'), style: PetsyType.meta),
          value: _sound ?? true,
          onChanged: _busy || _sound == null ? null : _setSound,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          secondary: const _SettingsIcon(Icons.visibility_outlined),
          title: Text(context.t('chat_preview'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('chat_preview_hint'), style: PetsyType.meta),
          value: _preview ?? true,
          onChanged: _busy || _preview == null ? null : _setPreview,
        ),
      ],
    );
  }
}

class _FriendPrivacyCard extends StatefulWidget {
  const _FriendPrivacyCard();

  @override
  State<_FriendPrivacyCard> createState() => _FriendPrivacyCardState();
}

class _FriendPrivacyCardState extends State<_FriendPrivacyCard> {
  String? _allowRequests;
  String? _allowMessages;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final settings = await context.api.userSettings();
      if (!mounted) return;
      setState(() {
        _allowRequests = settings.allowFriendRequests == 'nobody' ? 'nobody' : 'everyone';
        _allowMessages = settings.allowDirectMessages == 'friends_only' ? 'friends_only' : 'everyone';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _allowRequests ??= 'everyone';
          _allowMessages ??= 'everyone';
        });
      }
    }
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      await context.api.updateUserSettings(patch);
      if (!mounted) return;
      context.snack(context.t('privacy_saved'));
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAllowRequests(String value) async {
    setState(() => _allowRequests = value);
    await _patch({'allow_friend_requests': value});
  }

  Future<void> _setAllowMessages(String value) async {
    setState(() => _allowMessages = value);
    await _patch({'allow_direct_messages': value});
  }

  Widget _choices(String current, List<String> values, bool ready, ValueChanged<String> onPick) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(68, 0, 16, 12),
      child: Row(
        children: [
          for (final (i, value) in values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: PetsyPill(
                label: context.t('privacy_$value'),
                selected: current == value,
                style: PetsyPillStyle.choice,
                onTap: () {
                  if (ready && !_busy && current != value) onPick(value);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileMenuGroup(
      children: [
        _SettingsHeader(context.t('friend_privacy')),
        ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          leading: const _SettingsIcon(Icons.person_add_alt_1_outlined),
          title: Text(context.t('allow_friend_requests'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('allow_friend_requests_hint'), style: PetsyType.meta),
        ),
        _choices(_allowRequests ?? 'everyone', const ['everyone', 'nobody'], _allowRequests != null, _setAllowRequests),
        ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: PetsySpacing.lg, vertical: PetsySpacing.xs),
          leading: const _SettingsIcon(Icons.chat_bubble_outline),
          title: Text(context.t('allow_direct_messages'), style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('allow_direct_messages_hint'), style: PetsyType.meta),
        ),
        _choices(
          _allowMessages ?? 'everyone',
          const ['everyone', 'friends_only'],
          _allowMessages != null,
          _setAllowMessages,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Title inside a settings card; start-aligned to match the rows below it.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          PetsySpacing.lg,
          14,
          PetsySpacing.lg,
          PetsySpacing.xs / 2,
        ),
        child: Text(text, style: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Same soft icon box as [_ProfileMenuTile], for settings rows.
class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: PetsyColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: PetsyColors.primaryDark, size: 20),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final User _user = context.read<AuthState>().user!;
  late final ParsedPhone _parsedPhone = parseStoredPhone(_user.phone);
  final _phoneKey = GlobalKey<PetsyPhoneFieldState>();
  final _picker = ImagePicker();
  late final _name = TextEditingController(text: _user.name);
  late final _phone = TextEditingController(text: _parsedPhone.national);
  late final _city = TextEditingController(text: _user.city);
  late final _bio = TextEditingController(text: _user.bio);
  late String _avatarUrl = (_user.avatar ?? '').trim();
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_uploading || _busy) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      final url = await context.api.uploadImage(file.path);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      context.snack(context.t('photo_uploaded'), success: true, icon: Icons.check_circle_outline_rounded);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showPhotoSheet() async {
    if (_uploading || _busy) return;
    final action = await showPetsyActionSheet<String>(
      context: context,
      title: context.t('edit_profile_photo'),
      subtitle: context.t('edit_profile_change_photo'),
      actions: [
        PetsySheetAction(
          value: 'gallery',
          label: context.t('choose_gallery'),
          icon: Icons.photo_library_outlined,
        ),
        PetsySheetAction(
          value: 'camera',
          label: context.t('take_photo'),
          icon: Icons.photo_camera_outlined,
        ),
        if (_avatarUrl.isNotEmpty)
          PetsySheetAction(
            value: 'remove',
            label: context.t('remove_photo'),
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'remove') {
      setState(() => _avatarUrl = '');
      return;
    }
    await _pickPhoto(action == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      context.snack(context.t('required'), error: true);
      return;
    }
    if (_uploading) {
      context.snack(context.t('edit_profile_uploading'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().updateProfile({
        'name': _name.text.trim(),
        'phone': _phoneKey.currentState?.completeNumber ?? _phone.text.trim(),
        'city': _city.text.trim(),
        'bio': _bio.text.trim(),
        'avatar': _avatarUrl.trim(),
      });
      if (!mounted) return;
      context.snack(context.t('profile_updated'), success: true, icon: Icons.check_circle_outline_rounded);
      context.pop();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _name.text.trim().isEmpty ? _user.name : _name.text.trim();

    return PetsyPage(
      appBar: AppBar(title: Text(context.t('edit_profile'))),
      bottomNavigationBar: _EditProfileSaveBar(busy: _busy || _uploading, onPressed: _save),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 28),
        children: [
          const _EditProfileHero(),
          const SizedBox(height: 16),
          _EditProfileAvatarCard(
            name: displayName,
            avatarUrl: _avatarUrl,
            uploading: _uploading,
            verified: _user.isVerified,
            onTap: _showPhotoSheet,
          ),
          const SizedBox(height: 14),
          _EditProfileSection(
            title: context.t('edit_profile_section_personal'),
            icon: Icons.badge_outlined,
            children: [
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.t('name'),
                  hintText: context.t('edit_profile_name_hint'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: context.t('bio'),
                  hintText: context.t('edit_profile_bio_hint'),
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 54),
                    child: Icon(Icons.notes_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EditProfileSection(
            title: context.t('edit_profile_section_contact'),
            icon: Icons.contact_mail_outlined,
            children: [
              PetsyPhoneField(
                key: _phoneKey,
                controller: _phone,
                initialCountryIso: _parsedPhone.country.iso,
                decoration: InputDecoration(
                  labelText: context.t('phone'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              PetsyCityField(
                controller: _city,
                label: context.t('city'),
                hint: context.t('edit_profile_city_hint'),
                autofillFromGps: (_user.city ?? '').trim().isEmpty,
              ),
              const SizedBox(height: 12),
              _EditProfileEmailLock(email: _user.email),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EditProfileHero extends StatelessWidget {
  const _EditProfileHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1F6B5A), Color(0xFF2E8B74), Color(0xFF3FA48A)],
        ),
        boxShadow: [
          BoxShadow(
            color: PetsyColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              context.t('edit_profile_hero_tag'),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.t('edit_profile_hero_title'),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('edit_profile_hero_body'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _EditProfileAvatarCard extends StatelessWidget {
  const _EditProfileAvatarCard({
    required this.name,
    required this.avatarUrl,
    required this.uploading,
    required this.verified,
    required this.onTap,
  });

  final String name;
  final String avatarUrl;
  final bool uploading;
  final bool verified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        side: const BorderSide(color: PetsyColors.border),
      ),
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          PetsyColors.primary.withValues(alpha: 0.18),
                          PetsyColors.accent.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                  UserAvatar(name: name, url: avatarUrl.isEmpty ? null : avatarUrl, radius: 46),
                  if (uploading)
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.38),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 2,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: PetsyColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: PetsyColors.primary.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                uploading ? context.t('edit_profile_uploading') : context.t('edit_profile_change_photo'),
                style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (verified) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: PetsyColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 15, color: PetsyColors.primary),
                      const SizedBox(width: 5),
                      Text(
                        context.t('profile_verified'),
                        style: const TextStyle(color: PetsyColors.primaryDark, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSection extends StatelessWidget {
  const _EditProfileSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        side: const BorderSide(color: PetsyColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EditProfileEmailLock extends StatelessWidget {
  const _EditProfileEmailLock({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: PetsyColors.backgroundAlt,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 20, color: PetsyColors.textLight),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('email'), style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(email, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  context.t('edit_profile_email_locked'),
                  style: const TextStyle(fontSize: 11.5, color: PetsyColors.textLight, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileSaveBar extends StatelessWidget {
  const _EditProfileSaveBar({required this.busy, required this.onPressed});

  final bool busy;
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
          child: SizedBox(
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
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(context.t('edit_profile_save')),
            ),
          ),
        ),
      ),
    );
  }
}
