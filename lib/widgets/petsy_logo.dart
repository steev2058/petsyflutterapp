import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Vector paw: three toes + bean pad. Used by [PetsyMark].
class _PawPainter extends CustomPainter {
  const _PawPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.shortestSide;

    void oval(double dx, double dy, double w, double h) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dx * s, dy * s), width: w * s, height: h * s),
        paint,
      );
    }

    // Small breath between toes and pad — tighter than original, not touching.
    oval(0.22, 0.20, 0.24, 0.28);
    oval(0.50, 0.10, 0.26, 0.30);
    oval(0.78, 0.20, 0.24, 0.28);
    oval(0.50, 0.62, 0.66, 0.46);
  }

  @override
  bool shouldRepaint(covariant _PawPainter oldDelegate) => oldDelegate.color != color;
}

class _Paw extends StatelessWidget {
  const _Paw({required this.size, this.angle = 0});

  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: SizedBox(
        width: size,
        height: size * 1.15,
        child: const CustomPaint(painter: _PawPainter(color: Colors.white)),
      ),
    );
  }
}

/// Coral mark with two white paw prints — "pet + sy".
class PetsyMark extends StatefulWidget {
  const PetsyMark({super.key, this.size = 72, this.animated = false, this.radius});

  final double size;
  final bool animated;
  final double? radius;

  @override
  State<PetsyMark> createState() => _PetsyMarkState();
}

class _PetsyMarkState extends State<PetsyMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final disc = CurvedAnimation(parent: _c, curve: const Interval(0, 0.45, curve: Curves.easeOutCubic));
    final pawA = CurvedAnimation(parent: _c, curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic));
    final pawB = CurvedAnimation(parent: _c, curve: const Interval(0.4, 0.85, curve: Curves.easeOutCubic));

    return ScaleTransition(
      scale: Tween(begin: 0.88, end: 1.0).animate(disc),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius ?? s * 0.24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PetsyColors.secondary, PetsyColors.primary, PetsyColors.primaryDark],
            stops: [0, 0.45, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: PetsyColors.primary.withValues(alpha: 0.28),
              blurRadius: s * 0.18,
              offset: Offset(0, s * 0.08),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius ?? s * 0.24),
          child: Stack(
            children: [
              Positioned(
                left: -s * 0.2,
                top: -s * 0.35,
                child: Container(
                  width: s * 1.1,
                  height: s * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
              ),
              FadeTransition(
                opacity: pawA,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(pawA),
                  child: Align(
                    alignment: const Alignment(-0.42, -0.48),
                    child: _Paw(size: s * 0.28, angle: -20),
                  ),
                ),
              ),
              FadeTransition(
                opacity: pawB,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(pawB),
                  child: Align(
                    alignment: const Alignment(0.36, 0.42),
                    child: _Paw(size: s * 0.40, angle: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered Petsy wordmark in brand coral.
class PetsyWordmark extends StatefulWidget {
  const PetsyWordmark({
    super.key,
    this.fontSize = 40,
    this.animated = false,
    this.color = PetsyColors.primaryDark,
    this.showUnderline = false,
  });

  final double fontSize;
  final bool animated;
  final Color color;
  final bool showUnderline;

  @override
  State<PetsyWordmark> createState() => _PetsyWordmarkState();
}

class _PetsyWordmarkState extends State<PetsyWordmark> with SingleTickerProviderStateMixin {
  static const _letters = ['P', 'e', 't', 's', 'y'];
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.tajawal(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w800,
      color: widget.color,
      height: 1.05,
      letterSpacing: 0.6,
    );
    final underline = CurvedAnimation(parent: _c, curve: const Interval(0.55, 1, curve: Curves.easeOutCubic));

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _letters.length; i++)
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _c,
                    curve: Interval(0.15 + i * 0.1, 0.45 + i * 0.1, curve: Curves.easeOut),
                  ),
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.45), end: Offset.zero).animate(
                      CurvedAnimation(
                        parent: _c,
                        curve: Interval(0.15 + i * 0.1, 0.55 + i * 0.1, curve: Curves.easeOutCubic),
                      ),
                    ),
                    child: Text(_letters[i], style: style),
                  ),
                ),
            ],
          ),
          if (widget.showUnderline) ...[
            const SizedBox(height: 8),
            FadeTransition(
              opacity: underline,
              child: ScaleTransition(
                scale: underline,
                alignment: Alignment.center,
                child: Container(
                  width: widget.fontSize * 2.4,
                  height: 3.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      colors: [PetsyColors.secondary, PetsyColors.primary, PetsyColors.primaryDark],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full brand lockup: mark + wordmark + optional Arabic tagline.
class PetsyLogo extends StatelessWidget {
  const PetsyLogo({
    super.key,
    this.markSize = 88,
    this.showWordmark = true,
    this.showTagline = false,
    this.tagline,
    this.animated = false,
    this.horizontal = false,
    this.hero = false,
  });

  final double markSize;
  final bool showWordmark;
  final bool showTagline;
  final String? tagline;
  final bool animated;
  final bool horizontal;

  /// Larger lockup with halo plate + wordmark underline for auth/splash heroes.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final mark = PetsyMark(size: markSize, animated: animated);
    final framedMark = hero
        ? Container(
            padding: EdgeInsets.all(markSize * 0.12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(markSize * 0.34),
              color: Colors.white.withValues(alpha: 0.55),
              border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: PetsyColors.primary.withValues(alpha: 0.16),
                  blurRadius: markSize * 0.28,
                  offset: Offset(0, markSize * 0.08),
                ),
              ],
            ),
            child: mark,
          )
        : mark;

    final word = showWordmark
        ? PetsyWordmark(
            fontSize: hero ? (markSize * 0.48).clamp(28, 52) : (markSize * 0.42).clamp(22, 48),
            animated: animated,
            showUnderline: hero,
          )
        : null;

    final line = showTagline
        ? Padding(
            padding: EdgeInsets.only(top: hero ? 10 : 6),
            child: Text(
              tagline ?? 'حيوان أليف من سوريا',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontSize: hero ? (markSize * 0.155).clamp(13, 17) : (markSize * 0.16).clamp(12, 16),
                fontWeight: FontWeight.w600,
                color: PetsyColors.text.withValues(alpha: 0.72),
              ),
            ),
          )
        : null;

    final Widget lockup;
    if (horizontal) {
      lockup = Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            framedMark,
            if (word != null) ...[SizedBox(width: markSize * 0.18), word],
          ],
        ),
      );
    } else {
      lockup = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          framedMark,
          if (word != null) SizedBox(height: markSize * (hero ? 0.2 : 0.18)),
          ?word,
          ?line,
        ],
      );
    }

    if (!hero) return lockup;

    // FittedBox keeps the lockup inside the Hero flight rect so size morphs
    // between screens never trigger RenderFlex bottom overflows.
    final heroChild = Material(
      type: MaterialType.transparency,
      child: FittedBox(fit: BoxFit.contain, child: lockup),
    );

    return Hero(
      tag: 'petsy-auth-logo',
      createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
      flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
        final toLogo = toContext.widget as Hero;
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: toLogo.child,
        );
      },
      child: heroChild,
    );
  }
}
