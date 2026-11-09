import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_photo_picker.dart';
import '../auth/auth_screens.dart';

const postTypes = ['question', 'story', 'tip'];

IconData postTypeIcon(String? type) => switch (type) {
      'question' => Icons.help_outline_rounded,
      'story' => Icons.auto_stories_outlined,
      'tip' => Icons.lightbulb_outline_rounded,
      _ => Icons.forum_outlined,
    };

(Color, Color) postTypeColors(String type) => switch (type) {
      'question' => (const Color(0xFF3B82C4), const Color(0xFFE7F1FB)),
      'story' => (PetsyColors.primaryDark, PetsyColors.primarySoft),
      'tip' => (PetsyColors.accent, PetsyColors.accentSoft),
      _ => (PetsyColors.textSecondary, const Color(0xFFF1ECE8)),
    };

/// Arabic counts take different noun forms for 1, 2, 3–10 and 11+; English only splits 1 vs. many.
String relativeTime(BuildContext context, DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return context.t('time_now');
  if (diff.inHours < 1) return countPhrase(context, 'time_minutes', diff.inMinutes);
  if (diff.inDays < 1) return countPhrase(context, 'time_hours', diff.inHours);
  if (diff.inDays == 1) return context.t('chat_yesterday');
  if (diff.inDays < 7) return countPhrase(context, 'time_days', diff.inDays);
  return context.formatDate(time);
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String? _type;
  int _version = 0;

  Future<void> _compose() async {
    if (!context.requireLogin()) return;
    final created = await context.push<bool>('/create-post');
    if (created == true) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('community'))),
      floatingActionButton: PetsyFab(
        heroTag: 'community-fab',
        icon: Icons.edit_rounded,
        label: context.t('new_post'),
        onPressed: _compose,
      ),
      body: AsyncView<List<CommunityPost>>(
        key: ValueKey('$_type-$_version'),
        loader: () => context.api.communityPosts(type: _type),
        builder: (context, posts, reload) {
          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('community_subtitle'),
                          style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        const SizedBox(height: PetsySpacing.md),
                        _ComposePrompt(name: user?.name, avatar: user?.avatar, onTap: _compose),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PetsyFilterRow(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      0,
                    ),
                    children: [
                      for (var i = 0; i < postTypes.length + 1; i++)
                        PetsyPill(
                          label: context.t(i == 0 ? 'all' : postTypes[i - 1]),
                          icon: postTypeIcon(i == 0 ? null : postTypes[i - 1]),
                          selected: (i == 0 ? null : postTypes[i - 1]) == _type,
                          onTap: () => setState(() => _type = i == 0 ? null : postTypes[i - 1]),
                        ),
                    ],
                  ),
                ),
                if (posts.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: MessageView(
                        icon: postTypeIcon(_type),
                        text: '${context.t('community_empty_title')}\n${context.t('community_empty_body')}',
                        action: FilledButton.icon(
                          onPressed: _compose,
                          icon: const Icon(Icons.edit_rounded),
                          label: Text(context.t('new_post')),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      14,
                      PetsySpacing.page,
                      96,
                    ),
                    sliver: SliverList.separated(
                      itemCount: posts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CommunityPostCard(post: posts[i], onBlocked: reload),
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

class _ComposePrompt extends StatelessWidget {
  const _ComposePrompt({required this.onTap, this.name, this.avatar});

  final String? name;
  final String? avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyRaisedCard(
      onTap: onTap,
      padding: const EdgeInsets.all(PetsySpacing.sm + 2),
      child: Row(
        children: [
          if (name != null)
            UserAvatar(name: name!, url: avatar, radius: 20)
          else
            const CircleAvatar(
              radius: 20,
              backgroundColor: PetsyColors.primarySoft,
              child: Icon(Icons.person_outline_rounded, color: PetsyColors.primaryDark),
            ),
          const SizedBox(width: PetsySpacing.sm + 2),
          Expanded(
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: PetsyColors.backgroundAlt,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                context.t('community_compose_prompt'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: PetsySpacing.sm),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: PetsyColors.primarySoft,
              borderRadius: BorderRadius.circular(PetsyRadius.md),
            ),
            child: const Icon(Icons.add_photo_alternate_outlined, color: PetsyColors.primaryDark, size: 21),
          ),
        ],
      ),
    );
  }
}

class CommunityPostCard extends StatefulWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    this.expanded = false,
    this.onBlocked,
    this.following,
    this.onToggleFollow,
  });

  final CommunityPost post;
  final bool expanded;
  final VoidCallback? onBlocked;
  final bool? following;
  final VoidCallback? onToggleFollow;

  @override
  State<CommunityPostCard> createState() => _CommunityPostCardState();
}

class _CommunityPostCardState extends State<CommunityPostCard> {
  late int _likes = widget.post.likes;
  bool _liked = false;

  Future<void> _like() async {
    if (_liked || !context.requireLogin()) return;
    setState(() {
      _liked = true;
      _likes++;
    });
    try {
      await context.api.likePost(widget.post.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = false;
        _likes--;
      });
      context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _report() async {
    if (!context.requireLogin()) return;
    try {
      await context.api.reportPost(widget.post.id);
      if (mounted) context.snack(context.t('reported'));
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _block() async {
    if (!context.requireLogin()) return;
    try {
      await context.api.blockCommunityUser(widget.post.userId);
      if (!mounted) return;
      context.snack(context.t('user_blocked'));
      widget.onBlocked?.call();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _share() async {
    final post = widget.post;
    final link = AppConfig.communityShareUrl(post.id);
    await SharePlus.instance.share(
      ShareParams(text: '${post.title}\n${post.content}\n$link'),
    );
  }

  void _openDetail() => context.push('/community/${widget.post.id}');

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final image = post.image?.trim() ?? '';
    final hasImage = image.isNotEmpty;
    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: InkWell(
        onTap: widget.expanded ? null : _openDetail,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(color: PetsyColors.border),
            boxShadow: PetsyShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(PetsySpacing.md, 10, 2, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: post.userId.isEmpty ? null : () => context.push('/users/${post.userId}'),
                        borderRadius: BorderRadius.circular(PetsyRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              UserAvatar(name: post.userName, url: post.userAvatar, radius: 21),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                    ),
                                    Text(
                                      relativeTime(context, post.createdAt),
                                      style: const TextStyle(
                                        color: PetsyColors.textLight,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    PetsyMetaBadge(
                      label: context.t(post.type),
                      icon: postTypeIcon(post.type),
                      tone: switch (post.type) {
                        'tip' => PetsyMetaTone.accent,
                        'story' => PetsyMetaTone.primary,
                        _ => PetsyMetaTone.neutral,
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: PetsyColors.textSecondary),
                      onSelected: (v) {
                        if (v == 'report') _report();
                        if (v == 'block') _block();
                        if (v == 'share') _share();
                      },
                      itemBuilder: (_) => [
                        _menuItem('share', Icons.ios_share_rounded, context.t('share_post')),
                        _menuItem('report', Icons.flag_outlined, context.t('report')),
                        _menuItem('block', Icons.block_rounded, context.t('block_user'), danger: true),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: TextStyle(fontSize: widget.expanded ? 19 : 16, fontWeight: FontWeight.w800, height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post.content,
                      maxLines: widget.expanded ? null : 3,
                      overflow: widget.expanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1.55,
                        fontSize: widget.expanded ? 15 : 14,
                        color: widget.expanded ? PetsyColors.text : PetsyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasImage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(PetsyRadius.lg),
                    child: AspectRatio(aspectRatio: 16 / 10, child: NetImage(image)),
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(height: 1, indent: 12, endIndent: 12, color: PetsyColors.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: _PostAction(
                        icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _liked ? PetsyColors.primary : PetsyColors.textSecondary,
                        label: _likes > 0 ? '$_likes' : context.t('community_like'),
                        onTap: _like,
                      ),
                    ),
                    Expanded(
                      child: _PostAction(
                        icon: Icons.mode_comment_outlined,
                        color: PetsyColors.textSecondary,
                        label: post.commentsCount > 0 ? '${post.commentsCount}' : context.t('comments'),
                        onTap: widget.expanded ? null : _openDetail,
                      ),
                    ),
                    if (widget.expanded && widget.onToggleFollow != null)
                      Expanded(
                        child: _PostAction(
                          icon: widget.following == true
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: widget.following == true ? PetsyColors.primary : PetsyColors.textSecondary,
                          label: context.t(widget.following == true ? 'unfollow_thread' : 'follow_thread'),
                          onTap: widget.onToggleFollow,
                        ),
                      )
                    else
                      Expanded(
                        child: _PostAction(
                          icon: Icons.ios_share_rounded,
                          color: PetsyColors.textSecondary,
                          label: context.t('share'),
                          onTap: _share,
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

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {bool danger = false}) {
    final color = danger ? PetsyColors.error : PetsyColors.text;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: danger ? PetsyColors.error : PetsyColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({required this.icon, required this.color, required this.label, this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _comment = TextEditingController();
  final _view = GlobalKey<AsyncViewState<(CommunityPost, List<Comment>)>>();
  bool _sending = false;
  bool _following = false;
  Comment? _replyTo;
  final _likedComments = <String>{};
  final _commentLikes = <String, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFollow());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadFollow() async {
    try {
      final ids = await context.api.communityNotifySubscriptions();
      if (mounted) setState(() => _following = ids.contains(widget.postId));
    } catch (_) {}
  }

  Future<(CommunityPost, List<Comment>)> _load() async {
    final api = context.api;
    final results = await Future.wait([api.communityPost(widget.postId), api.comments(widget.postId)]);
    final comments = results[1] as List<Comment>;
    for (final c in comments) {
      _commentLikes.putIfAbsent(c.id, () => c.likes);
    }
    return (results[0] as CommunityPost, comments);
  }

  Future<void> _toggleFollow() async {
    if (!context.requireLogin()) return;
    final next = !_following;
    setState(() => _following = next);
    try {
      if (next) {
        await context.api.enablePostNotify(widget.postId);
        if (mounted) context.snack(context.t('thread_followed'));
      } else {
        await context.api.disablePostNotify(widget.postId);
        if (mounted) context.snack(context.t('thread_unfollowed'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !next);
      context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _likeComment(Comment c) async {
    if (_likedComments.contains(c.id) || !context.requireLogin()) return;
    setState(() {
      _likedComments.add(c.id);
      _commentLikes[c.id] = (_commentLikes[c.id] ?? c.likes) + 1;
    });
    try {
      await context.api.likeComment(c.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _likedComments.remove(c.id);
        _commentLikes[c.id] = (_commentLikes[c.id] ?? c.likes) - 1;
      });
      context.snack(context.errorText(e), error: true);
    }
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || !context.requireLogin()) return;
    setState(() => _sending = true);
    try {
      await context.api.addComment(
        widget.postId,
        text,
        parentCommentId: _replyTo?.id,
      );
      _comment.clear();
      setState(() => _replyTo = null);
      await _view.currentState?.reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Groups replies under their top-level ancestor so threads render one level deep.
  List<(Comment, List<Comment>)> _threads(List<Comment> comments) {
    final byId = {for (final c in comments) c.id: c};
    String rootOf(Comment c) {
      var cur = c;
      final seen = <String>{};
      while (cur.parentCommentId != null && byId.containsKey(cur.parentCommentId) && seen.add(cur.id)) {
        cur = byId[cur.parentCommentId]!;
      }
      return cur.id;
    }

    final roots = <Comment>[];
    final replies = <String, List<Comment>>{};
    for (final c in comments) {
      final root = rootOf(c);
      if (root == c.id) {
        roots.add(c);
      } else {
        replies.putIfAbsent(root, () => []).add(c);
      }
    }
    return [for (final r in roots) (r, replies[r.id] ?? const <Comment>[])];
  }

  Widget _commentTile(Comment c, {bool reply = false}) {
    return _CommentTile(
      comment: c,
      isReply: reply,
      liked: _likedComments.contains(c.id),
      likes: _commentLikes[c.id] ?? c.likes,
      onLike: () => _likeComment(c),
      onReply: () {
        if (!context.requireLogin()) return;
        setState(() => _replyTo = c);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('community')),
        actions: [
          IconButton(
            tooltip: context.t(_following ? 'unfollow_thread' : 'follow_thread'),
            onPressed: _toggleFollow,
            icon: Icon(_following ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<(CommunityPost, List<Comment>)>(
              key: _view,
              loader: _load,
              builder: (context, data, reload) {
                final (post, comments) = data;
                final threads = _threads(comments);
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      CommunityPostCard(
                        post: post,
                        expanded: true,
                        following: _following,
                        onToggleFollow: _toggleFollow,
                        onBlocked: () {
                          if (context.mounted) context.pop();
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(Icons.forum_outlined, size: 19, color: PetsyColors.primaryDark),
                          const SizedBox(width: 8),
                          Text(
                            context.t('comments'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(
                              color: PetsyColors.primarySoft,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${comments.length}',
                              style: const TextStyle(
                                color: PetsyColors.primaryDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (comments.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: PetsyColors.surface,
                            borderRadius: BorderRadius.circular(PetsyRadius.lg),
                            border: Border.all(color: PetsyColors.border),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, color: PetsyColors.textLight, size: 30),
                              const SizedBox(height: 8),
                              Text(
                                context.t('community_no_comments'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final (root, children) in threads) ...[
                          _commentTile(root),
                          for (final r in children) _commentTile(r, reply: true),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
          if (_replyTo != null)
            Material(
              color: PetsyColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 0, 6),
                  decoration: BoxDecoration(
                    color: PetsyColors.primarySoft,
                    borderRadius: BorderRadius.circular(PetsyRadius.sm),
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
                              '${context.t('replying_to')} ${_replyTo!.userName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: PetsyColors.primaryDark,
                              ),
                            ),
                            Text(
                              _replyTo!.content,
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
            controller: _comment,
            hint: context.t('write_comment'),
            busy: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.liked,
    required this.likes,
    required this.onLike,
    required this.onReply,
  });

  final Comment comment;
  final bool isReply;
  final bool liked;
  final int likes;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final canOpenProfile = c.userId != null && c.userId!.isNotEmpty;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: isReply ? 44 : 0, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: canOpenProfile ? () => context.push('/users/${c.userId}') : null,
            child: UserAvatar(name: c.userName, url: c.userAvatar, radius: isReply ? 15 : 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: BoxDecoration(
                    color: PetsyColors.surface,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(5),
                      topEnd: Radius.circular(18),
                      bottomStart: Radius.circular(18),
                      bottomEnd: Radius.circular(18),
                    ),
                    border: Border.all(color: PetsyColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: canOpenProfile ? () => context.push('/users/${c.userId}') : null,
                        child: Text(
                          c.userName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(c.content, style: const TextStyle(height: 1.45, fontSize: 14)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6, top: 2),
                  child: Row(
                    children: [
                      Text(
                        relativeTime(context, c.createdAt),
                        style: const TextStyle(fontSize: 11.5, color: PetsyColors.textLight, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      _CommentAction(
                        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: liked ? PetsyColors.primary : PetsyColors.textSecondary,
                        label: likes > 0 ? '$likes' : context.t('community_like'),
                        onTap: onLike,
                      ),
                      _CommentAction(
                        icon: Icons.reply_rounded,
                        color: PetsyColors.textSecondary,
                        label: context.t('reply_comment'),
                        onTap: onReply,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const _titleMax = 120;

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  String? _imageUrl;
  String _type = postTypes.first;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.api.createPost(
        type: _type,
        title: _title.text.trim(),
        content: _content.text.trim(),
        image: _imageUrl,
      );
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? context.t('required') : null;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('new_post'))),
      body: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SectionCard(
                    title: context.t('community_post_type'),
                    child: Column(
                      children: [
                        for (final t in postTypes) ...[
                          _PostTypeOption(
                            type: t,
                            hint: context.t('community_${t}_hint'),
                            selected: _type == t,
                            onTap: () => setState(() => _type = t),
                          ),
                          if (t != postTypes.last) const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _title,
                          maxLength: _titleMax,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          decoration: InputDecoration(
                            labelText: context.t('title'),
                            hintText: context.t('community_title_hint'),
                          ),
                          validator: required,
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _content,
                          minLines: 6,
                          maxLines: 12,
                          decoration: InputDecoration(
                            labelText: context.t('content'),
                            hintText: context.t('community_content_hint'),
                            alignLabelWithHint: true,
                          ),
                          validator: required,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('community_photo_optional'),
                    child: PetPhotoPicker(
                      imageUrl: _imageUrl,
                      onChanged: (url) => setState(() => _imageUrl = url),
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: SubmitButton(label: context.t('publish'), busy: _busy, onPressed: _submit),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTypeOption extends StatelessWidget {
  const _PostTypeOption({
    required this.type,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String type;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = postTypeColors(type);
    return Material(
      color: selected ? bg : PetsyColors.backgroundAlt,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.md),
            border: Border.all(color: selected ? fg : PetsyColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(postTypeIcon(type), color: fg, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t(type),
                      style: TextStyle(fontWeight: FontWeight.w800, color: selected ? fg : PetsyColors.text),
                    ),
                    Text(hint, style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? fg : PetsyColors.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
