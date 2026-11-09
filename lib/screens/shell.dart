import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../state/badge_counts.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _barHeight = 72.0;
  static const _barGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final badges = context.watch<BadgeCountsState>();
    final media = MediaQuery.of(context);
    final bottomInset = math.max(media.padding.bottom, _barGap);
    final tabs = [
      _TabItem(Icons.home_outlined, Icons.home_rounded, 'home', 0),
      _TabItem(Icons.favorite_outline_rounded, Icons.favorite_rounded, 'adoption', 0),
      _TabItem(Icons.storefront_outlined, Icons.storefront_rounded, 'shop', 0),
      _TabItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'messages', badges.messages),
      _TabItem(Icons.person_outline_rounded, Icons.person_rounded, 'profile', badges.profileBadge),
    ];

    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: petsyShellGradient),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset + _barHeight + _barGap),
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: shell,
                ),
              ),
            ),
          ),
          Positioned(
            left: PetsySpacing.page,
            right: PetsySpacing.page,
            bottom: bottomInset,
            child: _PetsyBottomMenu(
              index: shell.currentIndex,
              tabs: tabs,
              onSelect: (i) {
                HapticFeedback.selectionClick();
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  const _TabItem(this.icon, this.selectedIcon, this.labelKey, this.badge);
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final int badge;
}

/// Floating frosted capsule bottom menu.
class _PetsyBottomMenu extends StatelessWidget {
  const _PetsyBottomMenu({
    required this.index,
    required this.tabs,
    required this.onSelect,
  });

  final int index;
  final List<_TabItem> tabs;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          boxShadow: PetsyShadows.float,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PetsyRadius.xl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    PetsyColors.surface.withValues(alpha: 0.94),
                    PetsyColors.mist.withValues(alpha: 0.90),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.75),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, PetsySpacing.sm, 6, PetsySpacing.sm),
                child: SizedBox(
                  height: MainShell._barHeight - 16,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: _BottomTabButton(
                            item: tabs[i],
                            selected: i == index,
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _TabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PetsyColors.primary : PetsyColors.textSecondary;
    final label = context.t(item.labelKey);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: PetsyColors.primary.withValues(alpha: 0.08),
        highlightColor: PetsyColors.primary.withValues(alpha: 0.04),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? PetsyColors.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Badge(
                isLabelVisible: item.badge > 0,
                backgroundColor: PetsyColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                label: Text(
                  item.badge > 99 ? '99+' : '${item.badge}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                ),
                child: AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: PetsyType.meta.copyWith(
                fontSize: 10.5,
                height: 1.05,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? PetsyColors.primaryDark : PetsyColors.textSecondary,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
