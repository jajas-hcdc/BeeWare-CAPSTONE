import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SparklineChart extends StatelessWidget {
  final List<double> data;
  final Color lineColor;
  final double lineWidth;
  final double height;
  final double width;

  const SparklineChart({
    super.key,
    required this.data,
    this.lineColor = AppColors.healthyGreen,
    this.lineWidth = 2.5,
    this.height = 30,
    this.width = 100,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          lineColor: lineColor,
          lineWidth: lineWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final double lineWidth;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.lineWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final path = Path();
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      // Invert Y so higher values are higher up
      final normalized = (data[i] - minVal) / range;
      final y = size.height - (normalized * (size.height - 8)) - 4;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}

class EqualizerWaveform extends StatelessWidget {
  final int barCount;
  final Color color;
  final double height;
  final double width;

  const EqualizerWaveform({
    super.key,
    this.barCount = 18,
    this.color = AppColors.healthyGreen,
    this.height = 24,
    this.width = 90,
  });

  @override
  Widget build(BuildContext context) {
    // Pattern heights mimicking sound waves
    const heights = [
      0.3, 0.6, 0.4, 0.8, 0.5, 0.9, 0.7, 0.4, 1.0,
      0.6, 0.8, 0.5, 0.9, 0.4, 0.7, 0.3, 0.6, 0.4
    ];

    return SizedBox(
      height: height,
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          final hRatio = heights[index % heights.length];
          return Container(
            width: 2.5,
            height: height * hRatio,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class HistoryLineChart extends StatelessWidget {
  final List<String> dates;
  final List<double> values;
  final Color lineColor;
  final double minGrid;
  final double maxGrid;
  final double height;

  const HistoryLineChart({
    super.key,
    required this.dates,
    required this.values,
    this.lineColor = const Color(0xFF0088FF),
    this.minGrid = 50,
    this.maxGrid = 70,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HistoryLineChartPainter(
          dates: dates,
          values: values,
          lineColor: lineColor,
          minGrid: minGrid,
          maxGrid: maxGrid,
        ),
      ),
    );
  }
}

class _HistoryLineChartPainter extends CustomPainter {
  final List<String> dates;
  final List<double> values;
  final Color lineColor;
  final double minGrid;
  final double maxGrid;

  _HistoryLineChartPainter({
    required this.dates,
    required this.values,
    required this.lineColor,
    required this.minGrid,
    required this.maxGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final leftPadding = 30.0;
    final bottomPadding = 24.0;
    final topPadding = 20.0;
    final rightPadding = 12.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - bottomPadding - topPadding;

    final gridPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final textStyle = const TextStyle(color: Color(0xFF888888), fontSize: 10);
    final valueStyle = const TextStyle(
      color: Colors.black,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    // Draw horizontal grid lines
    final gridLevels = [minGrid, (minGrid + maxGrid) / 2, maxGrid];
    for (var level in gridLevels) {
      final normalized = (level - minGrid) / (maxGrid - minGrid);
      final y = topPadding + chartHeight * (1 - normalized);

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(text: level.toInt().toString(), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    final path = Path();
    final points = <Offset>[];
    final stepX = chartWidth / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final x = leftPadding + i * stepX;
      final normalized = (values[i] - minGrid) / (maxGrid - minGrid);
      final clampedNorm = normalized.clamp(0.0, 1.0);
      final y = topPadding + chartHeight * (1 - clampedNorm);
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    // Draw point values and date labels
    for (int i = 0; i < values.length; i++) {
      final pt = points[i];

      // Draw value on top of point
      final valTp = TextPainter(
        text: TextSpan(text: values[i].toInt().toString(), style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(pt.dx - valTp.width / 2, pt.dy - valTp.height - 4));

      // Draw date on bottom
      if (i < dates.length) {
        final dateTp = TextPainter(
          text: TextSpan(text: dates[i], style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        dateTp.paint(
          canvas,
          Offset(pt.dx - dateTp.width / 2, size.height - bottomPadding + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryLineChartPainter oldDelegate) => true;
}

class HistoryBarChart extends StatelessWidget {
  final List<String> dates;
  final List<double> values;
  final Color barColor;
  final double maxVal;
  final double height;

  const HistoryBarChart({
    super.key,
    required this.dates,
    required this.values,
    this.barColor = const Color(0xFF33D98E),
    this.maxVal = 80,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HistoryBarChartPainter(
          dates: dates,
          values: values,
          barColor: barColor,
          maxVal: maxVal,
        ),
      ),
    );
  }
}

class _HistoryBarChartPainter extends CustomPainter {
  final List<String> dates;
  final List<double> values;
  final Color barColor;
  final double maxVal;

  _HistoryBarChartPainter({
    required this.dates,
    required this.values,
    required this.barColor,
    required this.maxVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final leftPadding = 30.0;
    final bottomPadding = 24.0;
    final topPadding = 20.0;
    final rightPadding = 12.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - bottomPadding - topPadding;

    final gridPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1;

    final barPaint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    final textStyle = const TextStyle(color: Color(0xFF888888), fontSize: 10);
    final valueStyle = const TextStyle(
      color: Colors.black,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    // Draw horizontal grid lines (0, 20, 40, 60, 80)
    for (int lvl = 0; lvl <= maxVal.toInt(); lvl += 20) {
      final normalized = lvl / maxVal;
      final y = topPadding + chartHeight * (1 - normalized);

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(text: lvl.toString(), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    final barWidth = chartWidth / (values.length * 1.6);
    final stepX = chartWidth / values.length;

    for (int i = 0; i < values.length; i++) {
      final centerX = leftPadding + (i + 0.5) * stepX;
      final normalized = (values[i] / maxVal).clamp(0.0, 1.0);
      final barH = chartHeight * normalized;
      final y = topPadding + chartHeight - barH;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(centerX - barWidth / 2, y, barWidth, barH),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );

      canvas.drawRRect(rect, barPaint);

      // Draw value on top of bar
      final valTp = TextPainter(
        text: TextSpan(text: values[i].toInt().toString(), style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(
        canvas,
        Offset(centerX - valTp.width / 2, y - valTp.height - 2),
      );

      // Draw date on bottom
      if (i < dates.length) {
        final dateTp = TextPainter(
          text: TextSpan(text: dates[i], style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        dateTp.paint(
          canvas,
          Offset(centerX - dateTp.width / 2, size.height - bottomPadding + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryBarChartPainter oldDelegate) => true;
}
