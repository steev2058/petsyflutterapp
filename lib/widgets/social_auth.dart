import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/social_auth_service.dart';
import '../state/app_state.dart';
import 'common.dart';

export '../services/social_auth_service.dart' show SocialProvider, SocialProviderX;

/// Soft full-width social buttons that match the Petsy auth form.
class SocialAuthSection extends StatefulWidget {
  const SocialAuthSection({super.key, this.compact = false});

  final bool compact;

  @override
  State<SocialAuthSection> createState() => _SocialAuthSectionState();
}

class _SocialAuthSectionState extends State<SocialAuthSection> {
  SocialProvider? _busy;

  Future<void> _continue(SocialProvider provider) async {
    if (_busy != null) return;
    setState(() => _busy = provider);
    final auth = context.read<AuthState>();
    try {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => _SocialConfirmSheet(provider: provider),
      );
      if (confirmed != true || !mounted) return;

      if (provider == SocialProvider.instagram && mounted) {
        context.snack(context.t('instagram_via_meta'));
      }

      final social = await SocialAuthService.instance.signIn(provider);
      if (!mounted) return;
      if (social.providerUserId.isEmpty) {
        throw SocialAuthException('social_signin_failed');
      }

      await auth.loginSocial(
        provider: social.provider,
        providerUserId: social.providerUserId,
        email: social.email,
        name: social.name,
        avatar: social.avatar,
        accessToken: social.accessToken,
      );
      if (!mounted) return;
      if (social.demo) {
        context.snack(context.t('social_demo_mode'), success: true);
      }
      if (auth.needsOnboarding) {
        try {
          final pets = await context.api.myPets();
          if (pets.isNotEmpty) await auth.completeOnboarding();
        } catch (_) {}
      }
      if (!mounted) return;
      context.go(auth.needsOnboarding ? '/onboarding' : '/home');
    } catch (e) {
      if (!mounted) return;
      final text = e is SocialAuthException
          ? context.t(e.message)
          : context.errorText(e);
      context.snack(text, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: PetsyColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.t('or_continue_with'),
                style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
            const Expanded(child: Divider(color: PetsyColors.border)),
          ],
        ),
        SizedBox(height: widget.compact ? 12 : 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in SocialProvider.values) ...[
              if (p != SocialProvider.values.first) const SizedBox(width: 14),
              _SocialCircleButton(
                provider: p,
                busy: _busy == p,
                enabled: _busy == null,
                onTap: () => _continue(p),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SocialCircleButton extends StatelessWidget {
  const _SocialCircleButton({
    required this.provider,
    required this.onTap,
    required this.busy,
    required this.enabled,
  });

  final SocialProvider provider;
  final VoidCallback onTap;
  final bool busy;
  final bool enabled;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t(provider.labelKey),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled || busy ? 1 : 0.5,
        child: SizedBox.square(
          dimension: _size,
          child: Material(
            color: PetsyColors.mist,
            shape: CircleBorder(
              side: BorderSide(color: PetsyColors.primary.withValues(alpha: 0.22), width: 1.2),
            ),
            elevation: 0,
            shadowColor: PetsyColors.primary.withValues(alpha: 0.18),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: PetsyColors.primaryDark),
                      )
                    : SizedBox.square(
                        dimension: 22,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: _SocialMark(provider: provider, color: PetsyColors.primaryDark),
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

class _SocialConfirmSheet extends StatelessWidget {
  const _SocialConfirmSheet({required this.provider});

  final SocialProvider provider;

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
                decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
              ),
              const SizedBox(height: 18),
              SizedBox.square(
                dimension: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PetsyColors.mist,
                    border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.25), width: 1.4),
                  ),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: _SocialMark(provider: provider, color: PetsyColors.primaryDark),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.t(provider.labelKey),
                textAlign: TextAlign.center,
                style: PetsyType.section.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('social_link_hint'),
                textAlign: TextAlign.center,
                style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t('continue')),
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
                    backgroundColor: PetsyColors.surface,
                  ),
                  onPressed: () => Navigator.pop(context, false),
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

/// Crisp square marks — always drawn in a 24×24 logical box, then scaled with FittedBox.
class _SocialMark extends StatelessWidget {
  const _SocialMark({required this.provider, required this.color});

  final SocialProvider provider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const box = 24.0;
    return SizedBox.square(
      dimension: box,
      child: CustomPaint(
        painter: switch (provider) {
          SocialProvider.google => _GooglePainter(color),
          SocialProvider.facebook => _FacebookPainter(color),
          SocialProvider.instagram => _InstagramPainter(color),
        },
      ),
    );
  }
}

class _GooglePainter extends CustomPainter {
  _GooglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Perfect circle G inside a square canvas — no stretching.
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final r = s * 0.36;
    final stroke = s * 0.16;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -0.35, 4.5, false, paint);
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - stroke / 2, r + stroke * 0.35, stroke),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GooglePainter oldDelegate) => oldDelegate.color != color;
}

class _FacebookPainter extends CustomPainter {
  _FacebookPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // Balanced "f" glyph in a square viewBox.
    final path = Path()
      ..moveTo(s * 0.56, s * 1.0)
      ..lineTo(s * 0.56, s * 0.52)
      ..lineTo(s * 0.78, s * 0.52)
      ..lineTo(s * 0.78, s * 0.34)
      ..lineTo(s * 0.56, s * 0.34)
      ..lineTo(s * 0.56, s * 0.26)
      ..cubicTo(s * 0.56, s * 0.18, s * 0.60, s * 0.14, s * 0.74, s * 0.14)
      ..lineTo(s * 0.84, s * 0.14)
      ..lineTo(s * 0.84, s * 0.0)
      ..cubicTo(s * 0.78, 0, s * 0.70, 0, s * 0.56, 0)
      ..cubicTo(s * 0.34, 0, s * 0.24, s * 0.12, s * 0.24, s * 0.30)
      ..lineTo(s * 0.24, s * 0.34)
      ..lineTo(s * 0.12, s * 0.34)
      ..lineTo(s * 0.12, s * 0.52)
      ..lineTo(s * 0.24, s * 0.52)
      ..lineTo(s * 0.24, s * 1.0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FacebookPainter oldDelegate) => oldDelegate.color != color;
}

class _InstagramPainter extends CustomPainter {
  _InstagramPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Perfect rounded square + circle — both use equal width/height.
    final outer = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: s * 0.82, height: s * 0.82),
      Radius.circular(s * 0.22),
    );
    canvas.drawRRect(outer, stroke);
    canvas.drawCircle(c, s * 0.20, stroke);
    canvas.drawCircle(Offset(s * 0.70, s * 0.30), s * 0.055, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _InstagramPainter oldDelegate) => oldDelegate.color != color;
}
