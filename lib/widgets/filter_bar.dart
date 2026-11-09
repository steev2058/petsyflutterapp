import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import 'common.dart';

/// One removable active-filter chip shown under [PetsyFilterBar].
class PetsyActiveFilter {
  const PetsyActiveFilter({
    required this.label,
    required this.onClear,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onClear;
}

/// Quiet listing chrome: one filter trigger (+ optional trailing control),
/// and a slim active-chip row only when filters are applied.
class PetsyFilterBar extends StatelessWidget {
  const PetsyFilterBar({
    super.key,
    required this.onOpen,
    this.activeCount = 0,
    this.chips = const [],
    this.onClearAll,
    this.trailing,
    this.label,
    this.margin = const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 0),
  });

  final VoidCallback onOpen;
  final int activeCount;
  final List<PetsyActiveFilter> chips;
  final VoidCallback? onClearAll;
  final Widget? trailing;
  final String? label;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final hasChips = chips.isNotEmpty;
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterTrigger(
                  label: label ?? context.t('filters'),
                  activeCount: activeCount,
                  onTap: onOpen,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
          if (hasChips) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _ActiveChip(filter: chips[i]),
                  ],
                  if (onClearAll != null) ...[
                    const SizedBox(width: 8),
                    PetsyPressScale(
                      onTap: onClearAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: PetsyColors.shellWash,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: PetsyColors.border),
                        ),
                        child: Text(
                          context.t('clear_all'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: PetsyColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterTrigger extends StatelessWidget {
  const _FilterTrigger({
    required this.label,
    required this.activeCount,
    required this.onTap,
  });

  final String label;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Material(
      color: active ? PetsyColors.primarySoft : PetsyColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        side: BorderSide(
          color: active ? PetsyColors.primary.withValues(alpha: 0.45) : PetsyColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: active ? PetsyColors.primaryDark : PetsyColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: active ? PetsyColors.primaryDark : PetsyColors.text,
                  ),
                ),
              ),
              if (active)
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: PetsyColors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$activeCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded, color: PetsyColors.textLight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.filter});

  final PetsyActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      shape: StadiumBorder(side: BorderSide(color: PetsyColors.border.withValues(alpha: 0.9))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: filter.onClear,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (filter.icon != null) ...[
                Icon(filter.icon, size: 14, color: PetsyColors.primaryDark),
                const SizedBox(width: 5),
              ],
              Text(
                filter.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: PetsyColors.text,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.close_rounded, size: 15, color: PetsyColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared bottom sheet shell for listing filters.
Future<bool?> showPetsyFiltersSheet({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext ctx, void Function(VoidCallback fn) setModal) body,
  VoidCallback? onReset,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: PetsyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
    ),
    builder: (ctx) {
      final viewInsets = MediaQuery.viewInsetsOf(ctx);
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.78;
      return StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PetsySpacing.page,
                    0,
                    PetsySpacing.page,
                    PetsySpacing.page,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: PetsyType.section),
                      const SizedBox(height: PetsySpacing.md),
                      Flexible(
                        child: SingleChildScrollView(
                          child: body(ctx, setModal),
                        ),
                      ),
                      const SizedBox(height: PetsySpacing.md),
                      Row(
                        children: [
                          if (onReset != null)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  onReset();
                                  setModal(() {});
                                },
                                child: Text(context.t('clear')),
                              ),
                            ),
                          if (onReset != null) const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(context.t('guard_filters_apply')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
