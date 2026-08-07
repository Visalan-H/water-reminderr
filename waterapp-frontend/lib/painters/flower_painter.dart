import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../animation/flower_wilt_animation.dart';

class FlowerPainter extends CustomPainter {
  final FlowerWiltFrame frame;
  final List<FallingPetal> particles;
  final DateTime frameTime;

  FlowerPainter({
    required this.frame,
    required this.particles,
    required this.frameTime,
  });

  // Quadratic bezier helpers
  static Offset _qBez(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  static Offset _qBezTan(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      2 * u * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx),
      2 * u * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stemH = frame.stemH.clamp(0.0, 1.0);
    final leafH = frame.leafH.clamp(0.0, 1.0);
    final colorH = frame.colorH.clamp(0.0, 1.0);
    final w = size.width;
    final ht = size.height;
    final cx = w / 2;

    // ── Layout proportions ──
    final potW = w * 0.34;
    final potH = ht * 0.11;
    final potRimH = ht * 0.024;
    final potTopY = ht * 0.83;
    final potBotY = potTopY + potH;

    // Stem endpoints
    final stemBaseX = cx;
    final stemBaseY = potTopY - 2;
    final stemTopBaseY = ht * 0.30;

    // Droop increases as stemH drops
    final droopX = (1.0 - stemH) * w * 0.18;
    final droopY = (1.0 - stemH) * ht * 0.10;
    final stemTopX = cx + droopX;
    final stemTopY = stemTopBaseY + droopY;

    // Control point for the stem curve
    final stemCtrlX = cx + droopX * 0.55;
    final stemCtrlY = (stemBaseY + stemTopY) / 2 + droopY * 0.2;

    final stemP0 = Offset(stemBaseX, stemBaseY);
    final stemP1 = Offset(stemCtrlX, stemCtrlY);
    final stemP2 = Offset(stemTopX, stemTopY);

    // ── Colors ──
    final potColor =
        Color.lerp(const Color(0xFF6A4535), const Color(0xFFB5694E), colorH)!;
    final potRimColor =
        Color.lerp(const Color(0xFF503028), const Color(0xFF8B5040), colorH)!;
    final soilColor =
        Color.lerp(const Color(0xFF3E2E20), const Color(0xFF2E2018), colorH)!;
    final stemColor =
        Color.lerp(const Color(0xFF6B5B3A), const Color(0xFF3D8B50), colorH)!;
    final leafColor =
        Color.lerp(const Color(0xFF7A6B3A), const Color(0xFF4CAF50), colorH)!;
    final petalColor =
        Color.lerp(const Color(0xFF8B6B5A), const Color(0xFFFF6B9D), colorH)!;
    final petalInner =
        Color.lerp(const Color(0xFF9B7B6A), const Color(0xFFFF8DB5), colorH)!;
    final centerColor =
        Color.lerp(const Color(0xFF6B4A2A), const Color(0xFFFFD54F), colorH)!;

    // ── Apply sway rotation around stem base ──
    canvas.save();
    canvas.translate(cx, stemBaseY);
    canvas.rotate(frame.sway);
    canvas.translate(-cx, -stemBaseY);

    // ── Draw pot ──
    final potPath = Path()
      ..moveTo(cx - potW / 2, potTopY + potRimH)
      ..lineTo(cx - potW * 0.37, potBotY)
      ..quadraticBezierTo(cx, potBotY + 4, cx + potW * 0.37, potBotY)
      ..lineTo(cx + potW / 2, potTopY + potRimH)
      ..close();
    canvas.drawPath(potPath, Paint()..color = potColor);

    // Pot rim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - potW / 2 - 3, potTopY, potW + 6, potRimH + 2),
        Radius.circular(potRimH / 2),
      ),
      Paint()..color = potRimColor,
    );

    // Soil fill
    canvas.drawRect(
      Rect.fromLTWH(cx - potW / 2 + 4, potTopY + potRimH - 1, potW - 8, 5),
      Paint()..color = soilColor,
    );

    // Decorative stripe on pot
    final stripeY = (potTopY + potRimH + potBotY) / 2;
    canvas.drawLine(
      Offset(cx - potW * 0.26, stripeY),
      Offset(cx + potW * 0.26, stripeY),
      Paint()
        ..color = potRimColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // ── Draw stem ──
    final stemPath = Path()
      ..moveTo(stemP0.dx, stemP0.dy)
      ..quadraticBezierTo(stemP1.dx, stemP1.dy, stemP2.dx, stemP2.dy);
    canvas.drawPath(
        stemPath,
        Paint()
          ..color = stemColor
          ..strokeWidth = w * 0.02
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    // ── Draw leaves ──
    _drawLeaf(canvas, stemP0, stemP1, stemP2, 0.45, leafColor, w * 0.10, true, leafH);
    _drawLeaf(canvas, stemP0, stemP1, stemP2, 0.60, leafColor, w * 0.085, false, leafH);

    // ── Draw petals ──
    final petalCount = FlowerWiltFrame.petalCount;
    final petalLen = w * 0.115 * (0.50 + colorH * 0.50);
    final petalWid = w * 0.058 * (0.35 + colorH * 0.65);
    final petalBaseAngles = List<double>.generate(
        petalCount, (i) => (i * 2 * math.pi / petalCount) - math.pi / 2);

    for (int i = 0; i < petalCount; i++) {
      final baseAngle = petalBaseAngles[i];
      final ph = frame.petalH[i].clamp(0.0, 1.0);
      final droopFactor = (1.0 - ph) * 0.70;
      // Each petal droops toward pointing downward, independently timed.
      final angle = baseAngle + (math.pi / 2 - baseAngle) * droopFactor;

      _drawPetal(
        canvas,
        Offset(stemTopX, stemTopY),
        angle,
        petalLen,
        petalWid,
        petalColor,
        petalInner,
      );
    }

    // ── Draw center ──
    final centerR = w * 0.038 * (0.65 + colorH * 0.35);
    canvas.drawCircle(
        Offset(stemTopX, stemTopY), centerR, Paint()..color = centerColor);
    // Highlight
    canvas.drawCircle(
      Offset(stemTopX - centerR * 0.25, stemTopY - centerR * 0.25),
      centerR * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.10 + colorH * 0.15),
    );

    canvas.restore();

    // ── Falling petals ── drawn in world space, outside the sway transform
    // so a detached petal doesn't sway with the plant it left.
    if (particles.isNotEmpty) {
      final fallLen = petalLen * 0.55;
      final fallWid = petalWid * 0.6;
      for (final particle in particles) {
        final progress = particle.progressAt(frameTime);
        if (progress >= 1.0) continue;
        final baseAngle =
            petalBaseAngles[particle.petalIndex % petalBaseAngles.length];
        final originX = stemTopX + petalLen * 0.6 * math.sin(baseAngle);
        final originY = stemTopY - petalLen * 0.6 * math.cos(baseAngle);
        _drawFallingPetal(
          canvas,
          Offset(originX, originY),
          progress,
          particle,
          fallLen,
          fallWid,
          petalColor,
        );
      }
    }
  }

  void _drawFallingPetal(
    Canvas canvas,
    Offset origin,
    double progress,
    FallingPetal particle,
    double length,
    double width,
    Color color,
  ) {
    final fallY = progress * length * 6;
    final drift = particle.xDriftSeed * progress * length * 2;
    final rotation = particle.rotationSeed * progress * math.pi * 1.5;
    final alpha = (1.0 - progress).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(origin.dx + drift, origin.dy + fallY);
    canvas.rotate(rotation);

    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(width, -length * 0.25, width * 0.55, -length * 0.85, 0, -length)
      ..cubicTo(-width * 0.55, -length * 0.85, -width, -length * 0.25, 0, 0);

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    canvas.restore();
  }

  void _drawPetal(Canvas canvas, Offset center, double angle, double length,
      double width, Color color, Color innerColor) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        width, -length * 0.25,
        width * 0.55, -length * 0.85,
        0, -length,
      )
      ..cubicTo(
        -width * 0.55, -length * 0.85,
        -width, -length * 0.25,
        0, 0,
      );

    canvas.drawPath(path, Paint()..color = color);

    // Inner lighter layer for depth
    canvas.save();
    canvas.scale(0.60, 0.60);
    canvas.drawPath(path, Paint()..color = innerColor.withValues(alpha: 0.35));
    canvas.restore();

    canvas.restore();
  }

  void _drawLeaf(
      Canvas canvas,
      Offset p0,
      Offset p1,
      Offset p2,
      double t,
      Color color,
      double leafSize,
      bool leftSide,
      double leafHydration) {
    final pos = _qBez(p0, p1, p2, t);
    final tan = _qBezTan(p0, p1, p2, t);
    final stemAngle = math.atan2(tan.dy, tan.dx);

    final leafBaseAngle =
        leftSide ? stemAngle - math.pi / 2 : stemAngle + math.pi / 2;
    final droopAmt = (1.0 - leafHydration) * math.pi * 0.35;
    final leafAngle =
        leftSide ? leafBaseAngle - droopAmt : leafBaseAngle + droopAmt;
    final curLeafSize = leafSize * (0.6 + leafHydration * 0.4);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(leafAngle);

    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        curLeafSize * 0.45, -curLeafSize * 0.15,
        curLeafSize * 0.30, -curLeafSize * 0.55,
        0, -curLeafSize,
      )
      ..cubicTo(
        -curLeafSize * 0.30, -curLeafSize * 0.55,
        -curLeafSize * 0.45, -curLeafSize * 0.15,
        0, 0,
      );

    canvas.drawPath(leafPath, Paint()..color = color);

    // Vein
    canvas.drawLine(
      Offset.zero,
      Offset(0, -curLeafSize * 0.65),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 0.8,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlowerPainter oldDelegate) => true;
}
