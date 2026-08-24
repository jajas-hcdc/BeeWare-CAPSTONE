import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

class InteractiveHistoryView extends StatefulWidget {
  final HiveData hive;

  const InteractiveHistoryView({super.key, required this.hive});

  @override
  State<InteractiveHistoryView> createState() => _InteractiveHistoryViewState();
}

class _InteractiveHistoryViewState extends State<InteractiveHistoryView> {
  int _selectedTimeframe = 1; // 0: 24H, 1: 7D, 2: 30D
  final List<String> _timeframeLabels = ['24 Hours', '7 Days', '30 Days'];

  List<String> get _currentDates {
    if (_selectedTimeframe == 0) {
      return [
        '00:00', '02:00', '04:00', '06:00', '08:00', '10:00',
        '12:00', '14:00', '16:00', '18:00', '20:00', '22:00', '23:59'
      ];
    } else if (_selectedTimeframe == 1) {
      return [
        'May 10', 'May 11', 'May 12', 'May 13', 'May 14', 'May 15', 'May 16',
        'May 17', 'May 18', 'May 19', 'May 20', 'May 21', 'May 22', 'May 23'
      ];
    } else {
      return [
        'May 01', 'May 03', 'May 05', 'May 07', 'May 09', 'May 11',
        'May 13', 'May 15', 'May 17', 'May 19', 'May 21', 'May 23',
        'May 25', 'May 27', 'May 29', 'May 31'
      ];
    }
  }

  List<double> get _currentTemperature {
    if (_selectedTimeframe == 0) {
      return [33.5, 33.7, 34.0, 34.2, 34.6, 35.1, 35.4, 35.2, 34.9, 34.4, 34.1, 33.8, 33.6];
    } else if (_selectedTimeframe == 1) {
      return [34.0, 34.5, 35.0, 34.2, 34.8, 35.1, 34.6, 34.4, 34.7, 35.0, 34.8, 34.3, 34.5, 34.2];
    } else {
      return [
        33.8, 34.1, 34.4, 34.6, 34.9, 35.2, 35.0, 34.7,
        34.3, 34.5, 34.8, 35.1, 34.9, 34.6, 34.4, 34.2
      ];
    }
  }

  List<double> get _currentHumidity {
    if (_selectedTimeframe == 0) {
      return [67, 68, 65, 63, 60, 58, 56, 57, 60, 62, 65, 66, 67];
    } else if (_selectedTimeframe == 1) {
      return [60, 62, 65, 64, 63, 65, 66, 64, 63, 61, 62, 64, 65, 64];
    } else {
      return [
        62, 63, 65, 66, 64, 62, 60, 63,
        65, 64, 62, 63, 65, 64, 63, 64
      ];
    }
  }

  List<double> get _currentAcoustic {
    if (_selectedTimeframe == 0) {
      return [40, 42, 45, 50, 56, 62, 65, 60, 55, 52, 48, 44, 42];
    } else if (_selectedTimeframe == 1) {
      return [50, 45, 66, 70, 60, 50, 55, 52, 48, 62, 68, 56, 50, 54];
    } else {
      return [
        52, 48, 62, 68, 56, 50, 54, 52,
        49, 53, 58, 64, 57, 52, 50, 53
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Timeframe Selector & Export Bar
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: List.generate(_timeframeLabels.length, (index) {
                    final isSelected = index == _selectedTimeframe;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTimeframe = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFFCC00) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _timeframeLabels[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Icon(Icons.share_outlined, size: 20, color: Colors.black87),
              ),
              tooltip: 'Export Report',
              onSelected: (value) {
                if (value == 'csv') {
                  ExportService.exportCsvReport(context, widget.hive);
                } else if (value == 'audit') {
                  ExportService.exportAuditReport(context, widget.hive);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'csv',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart_outlined, size: 18, color: Colors.black87),
                      SizedBox(width: 8),
                      Text('Export CSV Data', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'audit',
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 18, color: Colors.black87),
                      SizedBox(width: 8),
                      Text('Export Health Audit (PDF/Txt)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 1. Temperature History Chart (Swipable)
        _buildTemperatureCard(),
        const SizedBox(height: 16),

        // 2. Humidity History Chart (Swipable)
        _buildHumidityCard(),
        const SizedBox(height: 16),

        // 3. Acoustic Frequency & Activity Chart (Swipable)
        _buildAcousticCard(),
        const SizedBox(height: 16),

        // 4. AI Colony Condition Timeline
        _buildTimelineCard(),
      ],
    );
  }

  // ================= SCROLLABLE CHART CONTAINER =================
  Widget _buildScrollableChart({
    required Widget chart,
    required int dataLength,
    double height = 160,
  }) {
    // Allocate 50px per date to allow smooth horizontal panning
    final chartWidth = max(320.0, dataLength * 52.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: chartWidth,
              child: RepaintBoundary(child: chart),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.swipe_left, size: 13, color: Colors.black38),
            SizedBox(width: 4),
            Text(
              'Swipe horizontally for more dates',
              style: TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  // ================= TEMPERATURE CARD =================
  Widget _buildTemperatureCard() {
    final temps = _currentTemperature;
    final dates = _currentDates;
    final avgTemp = (temps.reduce((a, b) => a + b) / temps.length).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: AppStyles.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.thermostat_outlined, size: 20, color: Color(0xFFE65100)),
                  SizedBox(width: 6),
                  Text(
                    'Temperature History (°C)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.healthyGreenBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Avg: $avgTemp°C',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.healthyGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Color(0x334CAF50), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Text(
                'Optimal Brood Nest Zone (32.0°C - 35.5°C)',
                style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: dates.length,
            height: 160,
            chart: LineChart(
              LineChartData(
                minY: 28,
                maxY: 38,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (value) {
                    if (value == 32 || value == 36) {
                      return FlLine(color: const Color(0x334CAF50), strokeWidth: 1.5, dashArray: [4, 4]);
                    }
                    return FlLine(color: Colors.black.withAlpha(20), strokeWidth: 1);
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      reservedSize: 30,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}°',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < dates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dates[idx],
                              style: const TextStyle(fontSize: 9, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(temps.length, (i) => FlSpot(i.toDouble(), temps[i])),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFFE65100),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isAlert = spot.y < 31.0 || spot.y > 36.5;
                        return FlDotCirclePainter(
                          radius: 4,
                          color: isAlert ? Colors.red : const Color(0xFFE65100),
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFE65100).withAlpha(80),
                          const Color(0xFFE65100).withAlpha(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= HUMIDITY CARD =================
  Widget _buildHumidityCard() {
    final hums = _currentHumidity;
    final dates = _currentDates;
    final avgHum = (hums.reduce((a, b) => a + b) / hums.length).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: AppStyles.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.water_drop_outlined, size: 20, color: Color(0xFF0288D1)),
                  SizedBox(width: 6),
                  Text(
                    'Relative Humidity (%)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Avg: $avgHum%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0288D1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: dates.length,
            height: 150,
            chart: LineChart(
              LineChartData(
                minY: 40,
                maxY: 80,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.black.withAlpha(20), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      reservedSize: 30,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}%',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < dates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dates[idx],
                              style: const TextStyle(fontSize: 9, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(hums.length, (i) => FlSpot(i.toDouble(), hums[i])),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF0288D1),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0288D1).withAlpha(100),
                          const Color(0xFF0288D1).withAlpha(10),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= ACOUSTIC CARD =================
  Widget _buildAcousticCard() {
    final acoustics = _currentAcoustic;
    final dates = _currentDates;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: AppStyles.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.graphic_eq, size: 20, color: AppColors.healthyGreen),
                  SizedBox(width: 6),
                  Text(
                    'Acoustic Energy & Frequency (dB)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: dates.length,
            height: 150,
            chart: BarChart(
              BarChartData(
                maxY: 80,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.black.withAlpha(20), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 20,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < dates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dates[idx],
                              style: const TextStyle(fontSize: 9, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(acoustics.length, (i) {
                  final isHigh = acoustics[i] > 65;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: acoustics[i],
                        color: isHigh ? const Color(0xFFE65100) : AppColors.healthyGreen,
                        width: 14,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TIMELINE CARD =================
  Widget _buildTimelineCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: AppStyles.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Queen Condition Timeline',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.hive.conditionTimeline.map((item) {
              final status = item['status'] ?? 'Queen Present';
              final date = item['date'] ?? '';
              Color pillBg;
              Color pillText;

              final st = status.toLowerCase();
              if (st.contains('present')) {
                pillBg = AppColors.queenPresentGreenBg;
                pillText = AppColors.queenPresentGreen;
              } else if (st.contains('absent')) {
                pillBg = AppColors.queenAbsentRedBg;
                pillText = AppColors.queenAbsentRed;
              } else if (st.contains('accepted')) {
                pillBg = AppColors.queenAcceptedBlueBg;
                pillText = AppColors.queenAcceptedBlue;
              } else if (st.contains('rejected')) {
                pillBg = AppColors.queenRejectedOrangeBg;
                pillText = AppColors.queenRejectedOrange;
              } else {
                pillBg = const Color(0xFFF0F0F0);
                pillText = Colors.black87;
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(date, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: pillText),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
