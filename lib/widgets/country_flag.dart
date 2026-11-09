import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Renders a country flag. Syria uses the independence-era tricolor
/// (green / white / black with three red stars) because the `🇸🇾` emoji
/// still resolves to the old Baʽathist flag on most devices.
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.iso,
    required this.emoji,
    this.size = 22,
  });

  final String iso;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (iso.toUpperCase() == 'SY') {
      return SizedBox(
        width: size * 1.35,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.12),
            child: CustomPaint(
              painter: const _SyriaIndependenceFlagPainter(),
              size: Size(size * 1.35, size),
            ),
          ),
        ),
      );
    }

    return Text(emoji, style: TextStyle(fontSize: size, height: 1));
  }
}

/// Syrian independence flag (current): green–white–black with 3 red stars.
class _SyriaIndependenceFlagPainter extends CustomPainter {
  const _SyriaIndependenceFlagPainter();

  static const _green = Color(0xFF007A3D);
  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);
  static const _red = Color(0xFFCE1126);

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.height / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), Paint()..color = _green);
    canvas.drawRect(Rect.fromLTWH(0, band, size.width, band), Paint()..color = _white);
    canvas.drawRect(Rect.fromLTWH(0, band * 2, size.width, band), Paint()..color = _black);

    final starR = math.min(size.width, size.height) * 0.11;
    final cy = band + band / 2;
    final gap = size.width * 0.22;
    final startX = size.width / 2 - gap;
    for (var i = 0; i < 3; i++) {
      _drawStar(canvas, Offset(startX + gap * i, cy), starR, Paint()..color = _red);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outer = -math.pi / 2 + i * 2 * math.pi / 5;
      final inner = outer + math.pi / 5;
      final ox = center.dx + radius * math.cos(outer);
      final oy = center.dy + radius * math.sin(outer);
      final ix = center.dx + radius * 0.4 * math.cos(inner);
      final iy = center.dy + radius * 0.4 * math.sin(inner);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
