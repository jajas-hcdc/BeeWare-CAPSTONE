import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CircularGauge extends StatelessWidget {
  final double percentage; // 0.0 to 100.0
  final Color progressColor;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final String? centerText;

  const CircularGauge({
    super.key,
    required this.percentage,
    this.progressColor = AppColors.healthyGreen,
    this.trackColor = const Color(0xFFE5E7EB),
    this.size = 80,
    this.strokeWidth = 10,
    this.centerText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _CircularGaugePainter(
              percentage: percentage,
              progressColor: progressColor,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
          ),
          Text(
            centerText ?? '${percentage.toInt()}%',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularGaugePainter extends CustomPainter {
  final double percentage;
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;

  _CircularGaugePainter({
    required this.percentage,
    required this.progressColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw full track circle
    canvas.drawCircle(center, radius, trackPaint);

    // Draw progress arc starting from top (-pi / 2)
    final sweepAngle = (percentage / 100) * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.progressColor != progressColor;
  }
}
