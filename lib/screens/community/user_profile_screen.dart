import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'community_screens.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  int _reload = 0;
  bool _friendBusy = false;

  Future<(PublicUserProfile, List<CommunityPost>)> _load() async {
    final api = context.api;
    final profile = await api.publicUserProfile(widget.userId);
    final posts = await api.communityPosts(userId: widget.userId);
    return (profile, posts);
  }

  Future<void> _message(PublicUserProfile profile) async {
    if (!context.requireLogin()) return;
    final hello = context.t('hello');
    try {
      final id = await context.api.startConversation(
        otherUserId: profile.id,
        message: '$hello — ${profile.name}',
      );
      if (!mounted) return;
      context.push('/chat/$id');
    } catch (e) {
      if (!mounted) return;
      context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _toggleBlock(PublicUserProfile profile, bool currentlyBlocked) async {
    if (!context.requireLogin()) return;
    try {
      if (currentlyBlocked) {
        await context.api.unblockFriend(profile.id);
      } else {
        await context.api.blockFriend(profile.id);
      }
      if (!mounted) return;
      context.snack(context.t(currentlyBlocked ? 'user_unblocked' : 'user_blocked'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _unfriend(PublicUserProfile profile) async {
    if (!context.requireLogin() || _friendBusy) return;
    final ok = await confirmAction(
      context,
      title: context.t('unfriend'),
      message: context.t('unfriend_confirm').replaceAll('{name}', profile.name),
      confirmLabel: context.t('unfriend'),
    );
    if (!ok || !mounted) return;
    setState(() => _friendBusy = true);
    try {
      await context.api.unfriend(profile.id);
      if (!mounted) return;
      context.snack(context.t('friend_removed'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _sendFriendRequest(PublicUserProfile profile) async {
    if (!context.requireLogin() || _friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      final status = await context.api.sendFriendRequest(profile.id);
      if (!mounted) return;
      final key = switch (status) {
        'friends' || 'already_friends' => 'already_friends',
        'pending' => 'friend_request_sent',
        _ => 'friend_request_sent',
      };
      context.snack(context.t(key));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _acceptFriend(PublicUserProfile profile) async {
    final requestId = profile.incomingRequestId;
    if (requestId == null || requestId.isEmpty || !context.requireLogin() || _friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      await context.api.reviewFriendRequest(requestId, action: 'accept');
      if (!mounted) return;
      context.snack(context.t('friend_accepted'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _rejectFriend(PublicUserProfile profile) async {
    final requestId = profile.incomingRequestId;
    if (requestId == null || requestId.isEmpty || !context.requireLogin() || _friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      await context.api.reviewFriendRequest(requestId, action: 'reject');
      if (!mounted) return;
      context.snack(context.t('friend_rejected'));
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Widget _friendActions(PublicUserProfile profile) {
    final status = profile.friendshipStatus;
    if (status == 'friends' || status == 'already_friends') {
      return OutlinedButton.icon(
        onPressed: _friendBusy ? null : () => _unfriend(profile),
        icon: const Icon(Icons.person_remove_outlined),
        label: Text(context.t('unfriend')),
      );
    }
    if (status == 'outgoing_pending') {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top),
        label: Text(context.t('friend_request_sent')),
      );
    }
    if (status == 'incoming_pending') {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _friendBusy ? null : () => _acceptFriend(profile),
              icon: const Icon(Icons.check),
              label: Text(context.t('accept')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _friendBusy ? null : () => _rejectFriend(profile),
              icon: const Icon(Icons.close),
              label: Text(context.t('reject')),
            ),
          ),
        ],
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _friendBusy || profile.isBlocked ? null : () => _sendFriendRequest(profile),
      icon: _friendBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.person_add_alt_1),
      label: Text(context.t('add_friend')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AuthState>().user?.id;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('user_profile'))),
      body: AsyncView<(PublicUserProfile, List<CommunityPost>)>(
        key: ValueKey(_reload),
        loader: _load,
        builder: (context, data, reload) {
          final (profile, posts) = data;
          final mine = profile.isSelf || profile.id == myId;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(
                PetsySpacing.page,
                PetsySpacing.md,
                PetsySpacing.page,
                PetsySpacing.listBottom,
              ),
              children: [
                _UserHeaderCard(
                  profile: profile,
                  mine: mine,
                  onBlockToggle: mine ? null : () => _toggleBlock(profile, profile.isBlocked),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _UserStat(
                      icon: Icons.article_outlined,
                      value: '${profile.postsCount}',
                      label: context.t('posts'),
                    ),
                    const SizedBox(width: 8),
                    _UserStat(
                      icon: Icons.people_outline_rounded,
                      value: '${profile.friendsCount}',
                      label: context.t('friends'),
                    ),
                    if (!mine && profile.mutualCount > 0) ...[
                      const SizedBox(width: 8),
                      _UserStat(
                        icon: Icons.handshake_outlined,
                        value: '${profile.mutualCount}',
                        label: context.t('user_mutual'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (!mine) ...[
                  if (profile.isBlocked)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PetsyColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(PetsyRadius.md),
                        border: Border.all(color: PetsyColors.error.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.block_rounded, color: PetsyColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.t('user_blocked'),
                              style: const TextStyle(color: PetsyColors.error, fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _toggleBlock(profile, true),
                            child: Text(context.t('unblock_user')),
                          ),
                        ],
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _message(profile),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(context.t('send_message')),
                  ),
                  const SizedBox(height: 8),
                  _friendActions(profile),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileActionTile(
                          icon: Icons.people_outline_rounded,
                          label: context.t('friends'),
                          onTap: () => context.push('/friends'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ProfileActionTile(
                          icon: Icons.edit_outlined,
                          label: context.t('edit_profile'),
                          onTap: () => context.push('/edit-profile'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 19, color: PetsyColors.primaryDark),
                    const SizedBox(width: 8),
                    Text(context.t('posts'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: PetsyColors.primarySoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${posts.length}',
                        style: const TextStyle(color: PetsyColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (posts.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: PetsyColors.surface,
                      borderRadius: BorderRadius.circular(PetsyRadius.lg),
                      border: Border.all(color: PetsyColors.border),
                    ),
                    child: MessageView(icon: Icons.forum_outlined, text: context.t('no_posts_yet')),
                  )
                else
                  for (final post in posts) ...[
                    CommunityPostCard(
                      post: post,
                      onBlocked: () {
                        if (context.mounted) context.pop();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserHeaderCard extends StatelessWidget {
  const _UserHeaderCard({required this.profile, required this.mine, this.onBlockToggle});

  final PublicUserProfile profile;
  final bool mine;
  final VoidCallback? onBlockToggle;

  @override
  Widget build(BuildContext context) {
    final subtle = Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(PetsySpacing.lg, PetsySpacing.lg, PetsySpacing.sm, 18),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: UserAvatar(name: profile.name, url: profile.avatar, radius: 36),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (profile.isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified_rounded, color: Colors.white, size: 19),
                          ],
                        ],
                      ),
                      if (profile.username != null && profile.username!.isNotEmpty)
                        Text(
                          '@${profile.username}',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(color: subtle, fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _HeaderPill(icon: Icons.badge_outlined, label: context.t('role_${profile.role}')),
                          if (profile.city != null && profile.city!.isNotEmpty)
                            _HeaderPill(icon: Icons.place_outlined, label: profile.city!),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (onBlockToggle != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (_) => onBlockToggle!(),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(
                            profile.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                            color: profile.isBlocked ? PetsyColors.text : PetsyColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            ctx.t(profile.isBlocked ? 'unblock_user' : 'block_user'),
                            style: TextStyle(color: profile.isBlocked ? PetsyColors.text : PetsyColors.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(profile.bio!, style: const TextStyle(color: Colors.white, height: 1.45)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${context.t('member_since')} ${context.formatDate(profile.createdAt)}',
              style: TextStyle(color: subtle, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _UserStat extends StatelessWidget {
  const _UserStat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: PetsyColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: PetsyColors.primaryDark),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: PetsyColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: PetsyColors.primaryDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
