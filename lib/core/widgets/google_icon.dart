import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Official multi-color Google "G" icon rendered crisply with CustomPaint.
class GoogleIcon extends StatelessWidget {
  final double size;

  const GoogleIcon({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(size: Size(size, size), painter: _GoogleIconPainter()),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final center = Offset(cx, cy);
    final double radius = size.width / 2;
    final double stroke = size.width * 0.22;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final blueArcPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Draw Google arcs:
    // Red: Top arc (~220 deg to 360 deg)
    canvas.drawArc(rect, -2.4, 1.8, false, redPaint);
    // Yellow: Left arc (~140 deg to 220 deg)
    canvas.drawArc(rect, math.pi * 0.65, 0.9, false, yellowPaint);
    // Green: Bottom arc (~40 deg to 140 deg)
    canvas.drawArc(rect, 0.0, math.pi * 0.65, false, greenPaint);
    // Blue: Lower-right small arc
    canvas.drawArc(rect, -0.6, 0.6, false, blueArcPaint);

    // Blue horizontal crossbar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 2, cy - stroke / 2, radius + 2 - stroke / 4, stroke),
      Radius.circular(stroke * 0.2),
    );
    canvas.drawRRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
