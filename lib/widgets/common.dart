import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/petsy_api.dart';
import '../state/app_state.dart';

extension AppContext on BuildContext {
  PetsyApi get api => read<PetsyApi>();

  String errorText(Object error) {
    if (error is ApiException) {
      if (error.code == 'NETWORK') return t('error_network');
      if (error.code == 'DM_FRIENDS_ONLY') return t('dm_friends_only');
      if (error.code == 'INVITE_NOT_FOUND') return t('invite_not_found');
      if (error.code == 'INVITE_SELF') return t('invite_self');
      if (error.code == 'SLOT_TAKEN') return t('slot_taken');
      if (error.code == 'PAST_DATE') return t('past_date');
      if (error.code == 'OWN_PET') return t('own_pet_error');
      if (error.code == 'PET_NOT_AVAILABLE') return t('pet_not_available');
      if (error.code == 'MESSAGE_TOO_SHORT') return t('message_too_short');
      if (error.code == 'ALREADY_REQUESTED') return t('already_requested');
      if (error.code == 'INVALID_IMAGE') return t('invalid_image');
      if (error.code == 'FILE_TOO_LARGE') return t('file_too_large');
      if (error.code == 'MESSAGE_TOO_LONG') return t('message_too_long');
      if (error.message == 'upload_failed') return t('upload_failed');
      return error.message;
    }
    return t('error_generic');
  }

  void snack(
    String message, {
    bool error = false,
    bool success = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(this);
    final tone = error
        ? PetsyToastTone.error
        : success
            ? PetsyToastTone.success
            : PetsyToastTone.neutral;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, PetsySpacing.md),
          duration: duration,
          dismissDirection: DismissDirection.horizontal,
          content: PetsyToast(
            message: message,
            tone: tone,
            icon: icon,
          ),
        ),
      );
  }

  /// Returns true when logged in; otherwise sends the user to the login screen.
  bool requireLogin() {
    if (read<AuthState>().isLoggedIn) return true;
    snack(t('login_required'));
    push('/login');
    return false;
  }

  String formatDate(DateTime? date, {bool withTime = false}) {
    if (date == null) return '';
    final locale = Localizations.localeOf(this).languageCode;
    return (withTime ? DateFormat.yMMMd(locale).add_Hm() : DateFormat.yMMMd(locale)).format(date);
  }
}

/// All amounts are USD, matching the backend's payment currency. Wrapped in an LTR isolate
/// so "$5" doesn't flip to "5$" when embedded in Arabic text.
/// Picks `<keyPrefix>_one/_two/_few/_many` (Arabic) or `_one/_many` (English) and fills `{n}`.
String countPhrase(BuildContext context, String keyPrefix, int n) {
  final arabic = Localizations.localeOf(context).languageCode == 'ar';
  final form = switch (n) {
    1 => 'one',
    2 when arabic => 'two',
    >= 3 && <= 10 when arabic => 'few',
    _ => 'many',
  };
  return context.t('${keyPrefix}_$form').replaceAll('{n}', '$n');
}

/// Localized label for a stored pet age; unrecognized free text is shown as typed.
String petAgeLabel(BuildContext context, String? raw) {
  final age = PetAge.parse(raw);
  if (age == null) return raw?.trim() ?? '';
  final unit = age.months ? 'age_months' : 'age_years';
  if (age.value != age.value.roundToDouble()) {
    return context.t('${unit}_many').replaceAll('{n}', age.number);
  }
  return countPhrase(context, unit, age.value.toInt());
}

/// Joins text segments so each keeps its own direction (e.g. "2 years" inside Arabic text).
String joinIsolated(Iterable<String> parts, [String separator = ' · ']) =>
    parts.map((p) => '\u2068$p\u2069').join(separator);

String formatPrice(double value, {String? currency}) {
  final code = (currency ?? '').trim().toUpperCase();
  if (code.isEmpty || code == 'USD') {
    final amount = NumberFormat.currency(
      locale: 'en_US',
      symbol: '\$',
      decimalDigits: value.truncateToDouble() == value ? 0 : 2,
    ).format(value);
    return '\u2066$amount\u2069';
  }
  final digits = value.truncateToDouble() == value ? 0 : 2;
  final amount = NumberFormat.decimalPattern('en_US').format(value);
  final pretty = digits == 0 ? amount.split('.').first : amount;
  return '\u2066$pretty $code\u2069';
}

/// Loads data with [loader], showing loading / error+retry / empty states, with pull-to-refresh.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.loader,
    required this.builder,
    this.isEmpty,
    this.emptyIcon = Icons.pets,
    this.emptyText,
  });

  final Future<T> Function() loader;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final IconData emptyIcon;
  final String? emptyText;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.loader();

  Future<void> reload() async {
    final next = widget.loader();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _scrollable(MessageView(
            icon: Icons.cloud_off,
            text: context.errorText(snapshot.error!),
            action: TextButton(onPressed: reload, child: Text(context.t('retry'))),
          ));
        }
        final data = snapshot.data as T;
        if (widget.isEmpty?.call(data) ?? false) {
          return _scrollable(MessageView(icon: widget.emptyIcon, text: widget.emptyText ?? context.t('empty')));
        }
        return RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, reload));
      },
    );
  }

  Widget _scrollable(Widget child) => RefreshIndicator(
        onRefresh: reload,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: constraints.maxHeight, child: child),
          ),
        ),
      );
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: PetsyColors.primarySoft,
              child: Icon(icon, size: 36, color: PetsyColors.primary),
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: PetsyColors.textSecondary)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.icon = Icons.pets});

  final String? url;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: PetsyColors.primarySoft,
      alignment: Alignment.center,
      child: Icon(icon, color: PetsyColors.primary.withValues(alpha: 0.5), size: 40),
    );
    final resolved = AppConfig.resolveMediaUrl(url);
    if (resolved.isEmpty ||
        !(resolved.startsWith('http://') || resolved.startsWith('https://'))) {
      return placeholder;
    }
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: fit,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.radius = 22});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: PetsyColors.primarySoft,
      child: ClipOval(
        child: SizedBox.expand(
          child: url != null && url!.startsWith('http')
              ? NetImage(url, icon: Icons.person)
              : Center(
                  child: Text(initial,
                      style: TextStyle(color: PetsyColors.primary, fontWeight: FontWeight.w800, fontSize: radius * 0.8)),
                ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onSeeAll, this.padding});

  final String title;
  final VoidCallback? onSeeAll;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            PetsySpacing.page,
            PetsySpacing.section,
            PetsySpacing.page,
            PetsySpacing.sm,
          ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: PetsyType.section)),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: Text(context.t('see_all'))),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'confirmed' || 'completed' || 'delivered' || 'for_adoption' || 'resolved' || 'active' || 'accepted' =>
        PetsyColors.success,
      'adopted' => PetsyColors.accent,
      'cancelled' || 'lost' || 'declined' || 'rejected' => PetsyColors.error,
      'withdrawn' => PetsyColors.textSecondary,
      'shipped' || 'for_sale' || 'found' => PetsyColors.primary,
      'pending_verification' => PetsyColors.warning,
      _ => PetsyColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(context.t(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Asks the user to confirm an action; [color] tints the confirm button (red by default for destructive actions).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  Color color = PetsyColors.error,
  IconData? icon,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: PetsyColors.ink.withValues(alpha: 0.48),
    builder: (ctx) => PetsyConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel ?? ctx.t('cancel'),
      color: color,
      icon: icon ??
          (color == PetsyColors.error ? Icons.delete_outline_rounded : Icons.help_outline_rounded),
    ),
  );
  return ok == true;
}

enum PetsyToastTone { neutral, success, error }

/// In-app floating toast used by [AppContext.snack].
class PetsyToast extends StatelessWidget {
  const PetsyToast({
    super.key,
    required this.message,
    this.tone = PetsyToastTone.neutral,
    this.icon,
  });

  final String message;
  final PetsyToastTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, soft, resolvedIcon) = switch (tone) {
      PetsyToastTone.error => (
          PetsyColors.surface,
          PetsyColors.error.withValues(alpha: 0.28),
          PetsyColors.text,
          const Color(0xFFFFE8E6),
          icon ?? Icons.error_outline_rounded,
        ),
      PetsyToastTone.success => (
          PetsyColors.surface,
          PetsyColors.success.withValues(alpha: 0.28),
          PetsyColors.text,
          const Color(0xFFE6F6EE),
          icon ?? Icons.check_circle_outline_rounded,
        ),
      PetsyToastTone.neutral => (
          PetsyColors.surface,
          PetsyColors.border,
          PetsyColors.text,
          PetsyColors.primarySoft,
          icon ?? Icons.notifications_none_rounded,
        ),
    };
    final iconColor = switch (tone) {
      PetsyToastTone.error => PetsyColors.error,
      PetsyToastTone.success => PetsyColors.success,
      PetsyToastTone.neutral => PetsyColors.primaryDark,
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: PetsyColors.ink.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(resolvedIcon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: PetsyType.body.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Polished confirmation dialog used across the app (clear cart, logout, delete…).
class PetsyConfirmDialog extends StatelessWidget {
  const PetsyConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.color = PetsyColors.error,
    this.icon = Icons.delete_outline_rounded,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final soft = Color.alphaBlend(color.withValues(alpha: 0.12), PetsyColors.surface);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.float,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: soft,
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18, height: 1.25),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(
                fontSize: 14,
                height: 1.45,
                color: PetsyColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
                  textStyle: PetsyType.button,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: PetsyColors.text,
                  side: const BorderSide(color: PetsyColors.border),
                  backgroundColor: PetsyColors.backgroundAlt,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
                  textStyle: PetsyType.button.copyWith(color: PetsyColors.text),
                ),
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PetsySheetAction<T> {
  const PetsySheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final String? subtitle;
}

/// Shared bottom-sheet chrome (handle + optional title) for popups.
Future<T?> showPetsyActionSheet<T>({
  required BuildContext context,
  required List<PetsySheetAction<T>> actions,
  String? title,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => PetsyActionSheet(
      title: title,
      subtitle: subtitle,
      actions: actions,
    ),
  );
}

class PetsyActionSheet<T> extends StatelessWidget {
  const PetsyActionSheet({
    super.key,
    required this.actions,
    this.title,
    this.subtitle,
  });

  final List<PetsySheetAction<T>> actions;
  final String? title;
  final String? subtitle;

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
              if (title != null) ...[
                const SizedBox(height: PetsySpacing.lg),
                Text(title!, style: PetsyType.section, textAlign: TextAlign.center),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: PetsyType.meta.copyWith(height: 1.35),
                  ),
                ],
              ],
              const SizedBox(height: PetsySpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: PetsyColors.surface,
                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                  border: Border.all(color: PetsyColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: PetsyColors.border),
                      _PetsySheetActionTile(action: actions[i]),
                    ],
                  ],
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t('cancel')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetsySheetActionTile<T> extends StatelessWidget {
  const _PetsySheetActionTile({required this.action});

  final PetsySheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? PetsyColors.error : PetsyColors.text;
    final soft = action.destructive ? const Color(0xFFFFE8E6) : PetsyColors.primarySoft;
    final iconColor = action.destructive ? PetsyColors.error : PetsyColors.primaryDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, action.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
                    ),
                    if (action.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle!,
                        style: PetsyType.meta.copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              PetsyChevron.forward(
                color: action.destructive ? PetsyColors.error.withValues(alpha: 0.5) : PetsyColors.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum PetsyPillStyle {
  /// Solid primary when selected; for list filters.
  filter,

  /// Soft tint when selected; for form choices.
  choice,
}

class PetsyPill extends StatelessWidget {
  const PetsyPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.highlightCount = false,
    this.style = PetsyPillStyle.filter,
    this.margin,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  /// Draws the count badge in solid primary even when unselected (e.g. unread or pending).
  final bool highlightCount;
  final PetsyPillStyle style;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final solid = style == PetsyPillStyle.filter;
    final bg = selected
        ? (solid ? PetsyColors.primary : PetsyColors.primarySoft)
        : (solid ? PetsyColors.surface : PetsyColors.backgroundAlt);
    final fg = selected ? (solid ? Colors.white : PetsyColors.primaryDark) : PetsyColors.text;
    final iconColor = selected
        ? (solid ? Colors.white : PetsyColors.primaryDark)
        : (solid ? PetsyColors.primaryDark : PetsyColors.textSecondary);
    final borderColor = selected ? PetsyColors.primary : PetsyColors.border;
    final shape = StadiumBorder(side: BorderSide(color: borderColor, width: selected && !solid ? 1.5 : 1));

    final (badgeBg, badgeFg) = selected
        ? (solid ? Colors.white : PetsyColors.primary, solid ? PetsyColors.primary : Colors.white)
        : highlightCount
            ? (PetsyColors.primary, Colors.white)
            : (PetsyColors.primarySoft, PetsyColors.primaryDark);

    final pill = Material(
      color: bg,
      shape: shape,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.symmetric(horizontal: solid ? 12 : 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '$count',
                    style: TextStyle(color: badgeFg, fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return margin == null ? pill : Padding(padding: margin!, child: pill);
  }
}

/// White rounded card with an optional icon + title header, used for form and detail sections.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.icon, this.trailing});

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: PetsyColors.primaryDark),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title!, style: PetsyType.cardTitle),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: PetsySpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// Sticky bottom area for a screen's primary action(s), above the system inset.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            PetsySpacing.page,
            PetsySpacing.md,
            PetsySpacing.page,
            PetsySpacing.md,
          ),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: PetsyColors.border))),
          child: child,
        ),
      ),
    );
  }
}

class CartButton extends StatelessWidget {
  const CartButton({super.key, this.style});

  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CartState>().count;
    return IconButton(
      style: style,
      onPressed: () => context.push('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

/// iPhone-style chevron for list rows / drill-in navigation (flips in RTL).
class PetsyChevron extends StatelessWidget {
  const PetsyChevron.forward({
    super.key,
    this.color = PetsyColors.textLight,
    this.size = 14,
  }) : _back = false;

  const PetsyChevron.back({
    super.key,
    this.color = PetsyColors.text,
    this.size = 18,
  }) : _back = true;

  final Color color;
  final double size;
  final bool _back;

  @override
  Widget build(BuildContext context) {
    return Icon(
      _back ? Icons.arrow_back_ios_new_rounded : Icons.arrow_forward_ios_rounded,
      size: size,
      color: color,
    );
  }
}

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSend,
    this.onChanged,
    this.onAttach,
  });

  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: PetsyColors.surface,
            border: const Border(top: BorderSide(color: PetsyColors.border)),
            boxShadow: [
              BoxShadow(
                color: PetsyColors.ink.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = !busy && value.text.trim().isNotEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onAttach != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: PetsyColors.primarySoft,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: busy ? null : onAttach,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: busy ? PetsyColors.textLight : PetsyColors.primaryDark,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onAttach != null) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: PetsyColors.backgroundAlt,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: PetsyColors.border),
                      ),
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (canSend) onSend();
                        },
                        onChanged: onChanged,
                        decoration: InputDecoration(
                          hintText: hint,
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canSend || busy
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFD44318), PetsyColors.primary, PetsyColors.secondary],
                            )
                          : null,
                      color: canSend || busy ? null : PetsyColors.shellWash,
                      boxShadow: canSend
                          ? [
                              BoxShadow(
                                color: PetsyColors.primary.withValues(alpha: 0.28),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: IconButton(
                      onPressed: canSend ? onSend : null,
                      tooltip: context.t('send'),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: canSend ? Colors.white : PetsyColors.textLight,
                              size: 22,
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shared extended floating action — coral gradient pill with icon badge.
class PetsyFab extends StatelessWidget {
  const PetsyFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.heroTag,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Object? heroTag;
  final String? tooltip;

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      PetsyColors.primaryDark,
      PetsyColors.primary,
      PetsyColors.secondary,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    Widget body = PetsyPressScale(
      onTap: onPressed,
      scale: 0.97,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.55,
        duration: const Duration(milliseconds: 160),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: PetsyShadows.fab,
          ),
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: _gradient,
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.1,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.trim().isNotEmpty) {
      body = Tooltip(message: tooltip!, child: body);
    }
    if (heroTag != null) {
      body = Hero(
        tag: heroTag!,
        flightShuttleBuilder: (flightContext, animation, direction, from, to) => to.widget,
        child: Material(color: Colors.transparent, elevation: 0, shadowColor: Colors.transparent, child: body),
      );
    }
    // Keep shadow clear of scaffold FAB slot clipping.
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2, bottom: 2),
      child: body,
    );
  }
}

/// Page shell: tab screens stay transparent over the shell gradient;
/// pushed routes get a soft background → backgroundAlt wash.
class PetsyPage extends StatelessWidget {
  const PetsyPage({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.tabCanvas = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool tabCanvas;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tabCanvas ? Colors.transparent : PetsyColors.backgroundAlt,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: tabCanvas
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(gradient: petsyPageGradient),
              child: child,
            ),
    );
  }
}

/// Standard search field used above filter pill rows.
class PetsySearchField extends StatelessWidget {
  const PetsySearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onClear,
    this.margin,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ??
          const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, PetsySpacing.sm),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, color: PetsyColors.textSecondary),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.t('clear'),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                      onChanged?.call('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal filter row of [PetsyPill]s with consistent padding.
class PetsyFilterRow extends StatelessWidget {
  const PetsyFilterRow({
    super.key,
    required this.children,
    this.padding,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ??
          const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, PetsySpacing.md),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: PetsySpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Rating badge with amber token colors.
class PetsyRating extends StatelessWidget {
  const PetsyRating(this.value, {super.key, this.compact = false});

  final double value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: PetsyColors.ratingSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: compact ? 13 : 15, color: PetsyColors.rating),
          SizedBox(width: compact ? 1 : 2),
          Text(
            value.toStringAsFixed(1),
            style: PetsyType.meta.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 11.5 : 12.5,
              color: PetsyColors.ratingInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft meta / count badge (replaces ad-hoc pink/amber chips).
class PetsyMetaBadge extends StatelessWidget {
  const PetsyMetaBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = PetsyMetaTone.neutral,
  });

  final String label;
  final IconData? icon;
  final PetsyMetaTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PetsyMetaTone.primary => (PetsyColors.primarySoft, PetsyColors.primaryDark),
      PetsyMetaTone.accent => (PetsyColors.accentSoft, PetsyColors.accent),
      PetsyMetaTone.warning => (PetsyColors.ratingSoft, PetsyColors.ratingInk),
      PetsyMetaTone.neutral => (PetsyColors.mist, PetsyColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Text(label, style: PetsyType.meta.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

enum PetsyMetaTone { neutral, primary, accent, warning }

/// Raised card treatment (xl + one soft primary-tinted shadow).
class PetsyRaisedCard extends StatelessWidget {
  const PetsyRaisedCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(PetsyRadius.xl);
    final body = Material(
      color: PetsyColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: padding ?? const EdgeInsets.all(PetsySpacing.lg),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: PetsyColors.border),
            boxShadow: PetsyShadows.raised,
          ),
          child: child,
        ),
      ),
    );
    return margin == null ? body : Padding(padding: margin!, child: body);
  }
}

/// Primary CTA press scale — one of the three allowed motions.
class PetsyPressScale extends StatefulWidget {
  const PetsyPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PetsyPressScale> createState() => _PetsyPressScaleState();
}

class _PetsyPressScaleState extends State<PetsyPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
