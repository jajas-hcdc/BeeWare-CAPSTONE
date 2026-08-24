import 'package:flutter/material.dart';

class BeehiveIcon extends StatelessWidget {
  final double size;
  final Color roofColor;
  final Color bodyColor;
  final Color legColor;
  final Color outlineColor;

  const BeehiveIcon({
    super.key,
    this.size = 48,
    this.roofColor = const Color(0xFFC7DEEB),
    this.bodyColor = const Color(0xFFFFE082),
    this.legColor = const Color(0xFF90A4AE),
    this.outlineColor = const Color(0xFF78909C),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: CustomPaint(
        painter: _BeehivePainter(
          roofColor: roofColor,
          bodyColor: bodyColor,
          legColor: legColor,
          outlineColor: outlineColor,
        ),
      ),
    );
  }
}

class _BeehivePainter extends CustomPainter {
  final Color roofColor;
  final Color bodyColor;
  final Color legColor;
  final Color outlineColor;

  _BeehivePainter({
    required this.roofColor,
    required this.bodyColor,
    required this.legColor,
    required this.outlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillRoofPaint = Paint()
      ..color = roofColor
      ..style = PaintingStyle.fill;

    final fillBodyPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;

    final fillLegPaint = Paint()
      ..color = legColor
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // 1. Draw Roof (triangle / trapezoid roof)
    final roofPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.95, h * 0.22)
      ..lineTo(w * 0.05, h * 0.22)
      ..close();
    canvas.drawPath(roofPath, fillRoofPaint);
    canvas.drawPath(roofPath, strokePaint);

    // 2. Draw Body Box (4 stacked layers)
    final bodyRect = Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.76, h * 0.65);
    canvas.drawRect(bodyRect, fillBodyPaint);
    canvas.drawRect(bodyRect, strokePaint);

    // Horizontal drawer seams & handles
    final layerHeight = (h * 0.65) / 4;
    for (int i = 1; i <= 3; i++) {
      final y = h * 0.22 + i * layerHeight;
      canvas.drawLine(Offset(w * 0.12, y), Offset(w * 0.88, y), strokePaint);

      // Handle curve for each layer
      final handleY = y - layerHeight * 0.45;
      final handlePath = Path()
        ..moveTo(w * 0.42, handleY)
        ..quadraticBezierTo(w * 0.5, handleY - 3, w * 0.58, handleY);
      canvas.drawPath(handlePath, strokePaint);
    }
    // Top layer handle
    final topHandleY = h * 0.22 + layerHeight * 0.55;
    final topHandlePath = Path()
      ..moveTo(w * 0.42, topHandleY)
      ..quadraticBezierTo(w * 0.5, topHandleY - 3, w * 0.58, topHandleY);
    canvas.drawPath(topHandlePath, strokePaint);

    // 3. Legs
    final leftLeg = Rect.fromLTWH(w * 0.18, h * 0.87, w * 0.12, h * 0.12);
    final rightLeg = Rect.fromLTWH(w * 0.70, h * 0.87, w * 0.12, h * 0.12);

    canvas.drawRect(leftLeg, fillLegPaint);
    canvas.drawRect(leftLeg, strokePaint);
    canvas.drawRect(rightLeg, fillLegPaint);
    canvas.drawRect(rightLeg, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
