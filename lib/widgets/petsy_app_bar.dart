import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../state/badge_counts.dart';
import 'petsy_logo.dart';

/// Soft circular action used in Petsy app bars.
class PetsyAppBarAction extends StatelessWidget {
  const PetsyAppBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
    this.child,
    this.emphasized = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int badgeCount;
  final Widget? child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final content = child ??
        Icon(
          icon,
          size: 20,
          color: emphasized ? PetsyColors.primaryDark : PetsyColors.text,
        );

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: emphasized ? PetsyColors.primarySoft : PetsyColors.mist,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Badge(
                  isLabelVisible: badgeCount > 0,
                  backgroundColor: PetsyColors.primary,
                  label: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Branded home AppBar: frosted plate, lockup, soft action chips, avatar.
class PetsyHomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PetsyHomeAppBar({super.key});

  static const _toolbar = 64.0;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbar);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    final locale = context.watch<LocaleState>().locale.languageCode.toUpperCase();
    final badges = context.watch<BadgeCountsState>();
    final cartCount = context.watch<CartState>().count;

    return AppBar(
      toolbarHeight: _toolbar,
      centerTitle: false,
      titleSpacing: 12,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  PetsyColors.background.withValues(alpha: 0.96),
                  PetsyColors.background.withValues(alpha: 0.86),
                ],
              ),
              border: const Border(
                bottom: BorderSide(color: PetsyColors.border, width: 0.85),
              ),
              boxShadow: [
                BoxShadow(
                  color: PetsyColors.primary.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
          ),
        ),
      ),
      title: const _HomeBrandLockup(),
      actions: [
        PetsyAppBarAction(
          icon: Icons.translate_rounded,
          tooltip: context.t('language'),
          onPressed: context.read<LocaleState>().toggle,
          child: Text(
            locale == 'AR' ? 'ع' : 'EN',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: PetsyColors.primaryDark,
            ),
          ),
        ),
        if (user != null)
          PetsyAppBarAction(
            icon: Icons.notifications_none_rounded,
            tooltip: context.t('notifications'),
            badgeCount: badges.notifications,
            onPressed: () async {
              await context.push('/notifications');
              if (context.mounted) context.read<BadgeCountsState>().refresh();
            },
          ),
        PetsyAppBarAction(
          icon: Icons.shopping_bag_outlined,
          tooltip: context.t('cart'),
          badgeCount: cartCount,
          emphasized: cartCount > 0,
          onPressed: () => context.push('/cart'),
        ),
        if (user != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10, start: 2),
            child: _HomeAvatarButton(user: user),
          )
        else
          const SizedBox(width: 6),
      ],
    );
  }
}

class _HomeBrandLockup extends StatelessWidget {
  const _HomeBrandLockup();

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    const mark = PetsyMark(size: 34, animated: true);
    const word = PetsyWordmark(fontSize: 22, animated: true);

    // Keep Latin "Petsy" LTR, but in Arabic put the wordmark to the LEFT of the mark.
    final brand = Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isRtl
            ? const [word, SizedBox(width: 8), mark]
            : const [mark, SizedBox(width: 8), word],
      ),
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          brand,
          Container(
            margin: const EdgeInsetsDirectional.only(start: 10, end: 8),
            width: 1,
            height: 22,
            color: PetsyColors.border,
          ),
          Text(
            context.t('home_appbar_tag'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: PetsyColors.textSecondary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAvatarButton extends StatelessWidget {
  const _HomeAvatarButton({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final avatar = user.avatar?.trim();
    final initial = (user.name.trim().isNotEmpty ? user.name.trim()[0] : 'P').toUpperCase();
    final profileBadge = context.watch<BadgeCountsState>().profileBadge;

    return Tooltip(
      message: context.t('profile'),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.go('/profile'),
        child: Badge(
          isLabelVisible: profileBadge > 0,
          backgroundColor: PetsyColors.primary,
          label: Text(
            profileBadge > 99 ? '99+' : '$profileBadge',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PetsyColors.secondary, PetsyColors.primary],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: PetsyColors.primary.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              image: (avatar != null && avatar.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                  : null,
            ),
            child: (avatar == null || avatar.isEmpty)
                ? Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
