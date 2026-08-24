import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// =========================================================================
// 1. TEMPERATURE VISUALIZER
// =========================================================================
class TemperatureVisualizer extends StatelessWidget {
  final double currentTemp;
  final List<double> history;
  final double minRange;
  final double maxRange;
  final double safeMin;
  final double safeMax;

  const TemperatureVisualizer({
    super.key,
    required this.currentTemp,
    this.history = const [33.2, 33.6, 34.0, 34.4, 34.2, 34.5, 34.2],
    this.minRange = 28.0,
    this.maxRange = 40.0,
    this.safeMin = 32.0,
    this.safeMax = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    final isSafe = currentTemp >= safeMin && currentTemp <= safeMax;
    final primaryColor = isSafe ? const Color(0xFFE65100) : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Mini Curved Sparkline with Gradient Area
        SizedBox(
          width: 120,
          height: 36,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ThermalSparklinePainter(
                data: history.isNotEmpty ? history : [currentTemp, currentTemp],
                minVal: minRange,
                maxVal: maxRange,
                lineColor: primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Linear Range Bar
        SizedBox(
          width: 120,
          child: Column(
            children: [
              // Range Track
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(25),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Stack(
                  children: [
                    // Safe Zone Green Band
                    Positioned(
                      left: ((safeMin - minRange) / (maxRange - minRange) * 120).clamp(0.0, 120.0),
                      width: ((safeMax - safeMin) / (maxRange - minRange) * 120).clamp(0.0, 120.0),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.healthyGreen.withAlpha(140),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Current Temp Indicator Dot
                    Positioned(
                      left: (((currentTemp - minRange) / (maxRange - minRange) * 120) - 3)
                          .clamp(0.0, 114.0),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('30°', style: TextStyle(fontSize: 8, color: Colors.black45, fontWeight: FontWeight.bold)),
                  Text('Optimal', style: TextStyle(fontSize: 8, color: AppColors.healthyGreen, fontWeight: FontWeight.bold)),
                  Text('40°', style: TextStyle(fontSize: 8, color: Colors.black45, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThermalSparklinePainter extends CustomPainter {
  final List<double> data;
  final double minVal;
  final double maxVal;
  final Color lineColor;

  _ThermalSparklinePainter({
    required this.data,
    required this.minVal,
    required this.maxVal,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (data.length - 1);
    final range = (maxVal - minVal) <= 0 ? 1.0 : (maxVal - minVal);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final norm = ((data[i] - minVal) / range).clamp(0.0, 1.0);
      final y = size.height - (norm * (size.height - 4)) - 2;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        // Smooth Bezier segment
        final prevX = (i - 1) * stepX;
        final prevNorm = ((data[i - 1] - minVal) / range).clamp(0.0, 1.0);
        final prevY = size.height - (prevNorm * (size.height - 4)) - 2;
        final cx = (prevX + x) / 2;

        path.cubicTo(cx, prevY, cx, y, x, y);
        fillPath.cubicTo(cx, prevY, cx, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withAlpha(80),
          lineColor.withAlpha(0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw last point dot
    final lastNorm = ((data.last - minVal) / range).clamp(0.0, 1.0);
    final lastY = size.height - (lastNorm * (size.height - 4)) - 2;
    canvas.drawCircle(
      Offset(size.width, lastY),
      3.0,
      Paint()..color = lineColor,
    );
    canvas.drawCircle(
      Offset(size.width, lastY),
      1.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ThermalSparklinePainter oldDelegate) => true;
}

// =========================================================================
// 2. HUMIDITY VISUALIZER
// =========================================================================
class HumidityVisualizer extends StatelessWidget {
  final double currentHumidity;
  final List<double> history;
  final double minRange;
  final double maxRange;
  final double safeMin;
  final double safeMax;

  const HumidityVisualizer({
    super.key,
    required this.currentHumidity,
    this.history = const [66.0, 65.5, 65.0, 64.5, 64.2, 64.0, 64.0],
    this.minRange = 30.0,
    this.maxRange = 90.0,
    this.safeMin = 50.0,
    this.safeMax = 70.0,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0288D1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Mini Moisture Wave Sparkline
        SizedBox(
          width: 120,
          height: 36,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _MoistureWavePainter(
                data: history.isNotEmpty ? history : [currentHumidity, currentHumidity],
                minVal: minRange,
                maxVal: maxRange,
                lineColor: primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Linear Humidity Range Bar
        SizedBox(
          width: 120,
          child: Column(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(25),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Stack(
                  children: [
                    // Safe Zone Blue Band
                    Positioned(
                      left: ((safeMin - minRange) / (maxRange - minRange) * 120).clamp(0.0, 120.0),
                      width: ((safeMax - safeMin) / (maxRange - minRange) * 120).clamp(0.0, 120.0),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0288D1).withAlpha(130),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Current Humidity Indicator Dot
                    Positioned(
                      left: (((currentHumidity - minRange) / (maxRange - minRange) * 120) - 3)
                          .clamp(0.0, 114.0),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('30%', style: TextStyle(fontSize: 8, color: Colors.black45, fontWeight: FontWeight.bold)),
                  Text('50%-70%', style: TextStyle(fontSize: 8, color: Color(0xFF0288D1), fontWeight: FontWeight.bold)),
                  Text('90%', style: TextStyle(fontSize: 8, color: Colors.black45, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoistureWavePainter extends CustomPainter {
  final List<double> data;
  final double minVal;
  final double maxVal;
  final Color lineColor;

  _MoistureWavePainter({
    required this.data,
    required this.minVal,
    required this.maxVal,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (data.length - 1);
    final range = (maxVal - minVal) <= 0 ? 1.0 : (maxVal - minVal);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final norm = ((data[i] - minVal) / range).clamp(0.0, 1.0);
      final y = size.height - (norm * (size.height - 4)) - 2;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevNorm = ((data[i - 1] - minVal) / range).clamp(0.0, 1.0);
        final prevY = size.height - (prevNorm * (size.height - 4)) - 2;
        final cx = (prevX + x) / 2;

        path.cubicTo(cx, prevY, cx, y, x, y);
        fillPath.cubicTo(cx, prevY, cx, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withAlpha(90),
          lineColor.withAlpha(0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final lastNorm = ((data.last - minVal) / range).clamp(0.0, 1.0);
    final lastY = size.height - (lastNorm * (size.height - 4)) - 2;
    canvas.drawCircle(
      Offset(size.width, lastY),
      3.0,
      Paint()..color = lineColor,
    );
    canvas.drawCircle(
      Offset(size.width, lastY),
      1.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _MoistureWavePainter oldDelegate) => true;
}

// =========================================================================
// 3. ACOUSTIC SIGNAL VISUALIZER
// =========================================================================
class AcousticSignalVisualizer extends StatelessWidget {
  final String conditionLabel;
  final String acousticStatus;

  const AcousticSignalVisualizer({
    super.key,
    required this.conditionLabel,
    this.acousticStatus = 'Normal',
  });

  @override
  Widget build(BuildContext context) {
    Color barColor;
    List<double> heights;

    final condition = conditionLabel.toLowerCase();
    if (condition.contains('absent')) {
      barColor = Colors.red;
      // High agitation queenless roar pattern
      heights = [0.3, 0.7, 0.9, 0.4, 0.85, 1.0, 0.6, 0.9, 0.75, 0.4, 0.8, 0.95, 0.5, 0.85, 0.3];
    } else if (condition.contains('rejected')) {
      barColor = const Color(0xFFE65100);
      // Erratic worker aggression buzzing
      heights = [0.4, 0.8, 0.6, 0.9, 0.7, 0.95, 0.85, 0.6, 0.8, 0.7, 0.9, 0.5, 0.8, 0.6, 0.4];
    } else if (condition.contains('accepted')) {
      barColor = const Color(0xFF1976D2);
      // Piping rhythm pattern
      heights = [0.2, 0.4, 0.8, 0.9, 0.8, 0.3, 0.2, 0.75, 0.85, 0.7, 0.2, 0.3, 0.6, 0.4, 0.2];
    } else {
      barColor = AppColors.healthyGreen;
      // Steady harmonic worker hum (180-220 Hz)
      heights = [0.3, 0.45, 0.6, 0.7, 0.8, 0.75, 0.65, 0.55, 0.65, 0.75, 0.8, 0.7, 0.6, 0.45, 0.3];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Multi-frequency Animated Equalizer Bars
        SizedBox(
          width: 120,
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(heights.length, (index) {
              final h = heights[index] * 30.0;
              return Container(
                width: 4.5,
                height: max(4.0, h),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: [
                      barColor,
                      barColor.withAlpha(180),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),

        // Frequency & Decibel readout label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: barColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              condition.contains('absent')
                  ? '380 Hz • 72 dB'
                  : (condition.contains('rejected')
                      ? '420 Hz • 76 dB'
                      : (condition.contains('accepted') ? '240 Hz • 60 dB' : '205 Hz • 56 dB')),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
