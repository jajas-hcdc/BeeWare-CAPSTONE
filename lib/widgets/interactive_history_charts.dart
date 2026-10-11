import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/audio_recording_model.dart';
import '../models/hive_data.dart';
import '../services/audio_service.dart';
import '../services/export_service.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';

class InteractiveHistoryView extends StatefulWidget {
  final HiveData hive;

  const InteractiveHistoryView({super.key, required this.hive});

  @override
  State<InteractiveHistoryView> createState() => _InteractiveHistoryViewState();
}

class _InteractiveHistoryViewState extends State<InteractiveHistoryView> {
  int _selectedTimeframe = 0; // 0: 24H, 1: 7D, 2: 30D
  final List<String> _timeframeLabels = ['24 Hours', '7 Days', '30 Days'];
  Timer? _clockTimer;

  /// Returns the live version of the hive from HiveService, falling back to widget.hive
  HiveData get _liveHive {
    final live = HiveService().getHiveById(widget.hive.id);
    return live ?? widget.hive;
  }

  @override
  void initState() {
    super.initState();
    AudioService().fetchRecordingsForDevice(widget.hive.deviceId);
    // Listen to HiveService for real-time telemetry updates
    HiveService().addListener(_onHiveServiceUpdate);
    // Periodically tick with the clock so elapsed minutes & hours update live
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    HiveService().removeListener(_onHiveServiceUpdate);
    super.dispose();
  }

  String? _lastKnownAudioTime;

  void _onHiveServiceUpdate() {
    if (!mounted) return;
    final currentAudioTime = _liveHive.lastAudioRecordedTime;
    if (currentAudioTime != null && currentAudioTime != _lastKnownAudioTime) {
      _lastKnownAudioTime = currentAudioTime;
      AudioService().fetchRecordingsForDevice(_liveHive.deviceId);
    }
    setState(() {});
  }

  static const List<String> _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDateTimeForTimeframe(DateTime dt, int timeframe) {
    final mon = _shortMonths[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    if (timeframe == 0) {
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final hrStr = hour12.toString().padLeft(2, '0');
      final minStr = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      // 24 Hours: emphasize 12-hour time with AM/PM on top, date below
      return '$hrStr:$minStr $ampm\n$mon $day';
    } else {
      // 7 Days & 30 Days: 1 bar per day labeled with the date
      return '$mon $day';
    }
  }

  /// Synchronized historical dataset combining full-day telemetry history and
  /// Recent Hive Buzz Recordings in chronological order.
  ({
    List<double> temps,
    List<double> hums,
    List<double> acoustics,
    List<String> dates,
  }) get _syncedHistoryData {
    final recordings = AudioService().getCachedRecordings(_liveHive.deviceId);
    final curTemp = double.tryParse(_liveHive.temperature.replaceAll('°C', '').trim());
    final curHum = double.tryParse(_liveHive.humidity.replaceAll('%', '').trim());
    final rawAc = double.tryParse(_liveHive.acoustic.replaceAll('Hz', '').trim());
    final curAc = (rawAc != null && rawAc > 0) ? rawAc : null;

    final hasTemps = _liveHive.temperatureHistory.isNotEmpty || curTemp != null || recordings.isNotEmpty;
    final hasHums = _liveHive.humidityHistory.isNotEmpty || curHum != null || recordings.isNotEmpty;
    final hasAcoustic = _liveHive.acousticHistory.isNotEmpty || curAc != null || recordings.isNotEmpty;

    if (!hasTemps && !hasHums && !hasAcoustic) {
      return (temps: <double>[], hums: <double>[], acoustics: <double>[], dates: <String>[]);
    }

    var rawTemps = List<double>.from(_liveHive.temperatureHistory);
    var rawHums = List<double>.from(_liveHive.humidityHistory);
    var rawAcoustics = List<double>.from(_liveHive.acousticHistory);
    var rawDates = List<String>.from(_liveHive.historyDates);

    final fallbackEpoch = _liveHive.lastAudioCreatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final curDateLabel = HiveService.formatEpochToHistoryLabel(
      fallbackEpoch,
      fallbackTs: _liveHive.lastAudioRecordedTime,
    );

    if (recordings.isEmpty) {
      if (rawTemps.isEmpty && curTemp != null) rawTemps = [curTemp];
      if (rawHums.isEmpty && curHum != null) rawHums = [curHum];
      if (rawAcoustics.isEmpty && curAc != null) rawAcoustics = [curAc];
      if (rawDates.isEmpty) rawDates = [curDateLabel];
    }

    int maxLen = [rawTemps.length, rawHums.length, rawAcoustics.length, rawDates.length].reduce(max);

    if (maxLen > 0) {
      while (rawTemps.length < maxLen) {
        rawTemps.insert(0, rawTemps.isNotEmpty ? rawTemps.first : (curTemp ?? 34.0));
      }
      while (rawHums.length < maxLen) {
        rawHums.insert(0, rawHums.isNotEmpty ? rawHums.first : (curHum ?? 60.0));
      }
      while (rawAcoustics.length < maxLen) {
        rawAcoustics.insert(0, rawAcoustics.isNotEmpty ? rawAcoustics.first : (curAc ?? 110.0));
      }
      while (rawDates.length < maxLen) {
        rawDates.insert(0, curDateLabel);
      }
    }

    // Build chronological, deduplicated points with resolved GMT+8 DateTime
    final Map<String, ({DateTime dt, double t, double h, double a})> dedupedMap = {};
    final latestKnownDt = (_liveHive.lastAudioCreatedAt != null && _liveHive.lastAudioCreatedAt! > 1700000000000)
        ? HiveService.epochToHiveDateTime(_liveHive.lastAudioCreatedAt!)
        : HiveService.epochToHiveDateTime(DateTime.now().millisecondsSinceEpoch);

    for (int i = 0; i < maxLen; i++) {
      final rawLabel = rawDates[i].trim();
      if (maxLen > 1 && (rawLabel == 'Now' || rawLabel.startsWith('-') || rawLabel.isEmpty)) {
        continue;
      }
      DateTime? dt = HiveService.parseHistoryLabelToDateTime(rawLabel);
      dt ??= latestKnownDt.subtract(Duration(minutes: (maxLen - 1 - i) * 5));
      if (HiveService.isBeforeIotStartDate(dt)) {
        continue;
      }

      double aVal = rawAcoustics[i];
      if (aVal > 0 && aVal <= 55.0 && (curAc == null || curAc >= 75.0)) {
        aVal = aVal * 5.0;
      }

      final key = '${dt.year}-${dt.month}-${dt.day}-${dt.hour}-${dt.minute}';
      dedupedMap[key] = (
        dt: dt,
        t: rawTemps[i],
        h: rawHums[i],
        a: aVal,
      );
    }

    // Merge Recent Hive Buzz Recordings so every clip shown in the list is reflected in the charts
    if (recordings.isNotEmpty) {
      final chronologicalClips = recordings.reversed.toList();
      for (int i = 0; i < chronologicalClips.length; i++) {
        final clip = chronologicalClips[i];
        DateTime? dt;
        int epoch = clip.createdAt;
        if (epoch > 0 && epoch < 1700000000000 && epoch >= 1700000000) {
          epoch *= 1000;
        }
        if (epoch > 1700000000000) {
          dt = HiveService.epochToHiveDateTime(epoch);
        } else {
          final combined = clip.formattedRecordedDate.isNotEmpty
              ? '${clip.formattedRecordedDate}, ${clip.formattedRecordedTime}'
              : clip.formattedRecordedTime;
          dt = HiveService.parseHistoryLabelToDateTime(combined);
        }
        dt ??= HiveService.epochToHiveDateTime(DateTime.now().millisecondsSinceEpoch)
            .subtract(Duration(minutes: (chronologicalClips.length - 1 - i) * 5));
        if (HiveService.isBeforeIotStartDate(dt)) {
          continue;
        }

        final key = '${dt.year}-${dt.month}-${dt.day}-${dt.hour}-${dt.minute}';
        dedupedMap[key] = (
          dt: dt,
          t: clip.temperature,
          h: clip.humidity,
          a: clip.frequency.toDouble(),
        );
      }
    }

    var sortedPoints = dedupedMap.values.toList()
      ..sort((a, b) => a.dt.compareTo(b.dt));

    if (sortedPoints.isEmpty) {
      return (temps: <double>[], hums: <double>[], acoustics: <double>[], dates: <String>[]);
    }

    final refEnd = sortedPoints.last.dt;
    final Duration maxAge = _selectedTimeframe == 0
        ? const Duration(hours: 24)
        : (_selectedTimeframe == 1 ? const Duration(days: 7) : const Duration(days: 30));

    final filteredPoints = sortedPoints.where((p) => refEnd.difference(p.dt) <= maxAge).toList();
    if (filteredPoints.isNotEmpty) {
      sortedPoints = filteredPoints;
    }

    final finalTemps = <double>[];
    final finalHums = <double>[];
    final finalAcoustics = <double>[];
    final finalDates = <String>[];

    if (_selectedTimeframe == 0) {
      // 24 Hours: individual readings across the day (AM to PM)
      if (sortedPoints.length > 35) {
        sortedPoints = sortedPoints.sublist(sortedPoints.length - 35);
      }
      for (final p in sortedPoints) {
        finalTemps.add(p.t);
        finalHums.add(p.h);
        finalAcoustics.add(p.a);
        finalDates.add(_formatDateTimeForTimeframe(p.dt, 0));
      }
    } else {
      // 7 Days & 30 Days: group by calendar day into 1 daily average bar per day
      final Map<String, List<({DateTime dt, double t, double h, double a})>> byDay = {};
      for (final p in sortedPoints) {
        final dayKey =
            '${p.dt.year}-${p.dt.month.toString().padLeft(2, '0')}-${p.dt.day.toString().padLeft(2, '0')}';
        byDay.putIfAbsent(dayKey, () => []).add(p);
      }

      var dayKeys = byDay.keys.toList()..sort();
      final int maxDays = _selectedTimeframe == 1 ? 7 : 30;
      if (dayKeys.length > maxDays) {
        dayKeys = dayKeys.sublist(dayKeys.length - maxDays);
      }

      for (final dayKey in dayKeys) {
        final dayPoints = byDay[dayKey]!;
        final validT = dayPoints.where((p) => p.t > 0.0).map((p) => p.t).toList();
        final validH = dayPoints.where((p) => p.h > 0.0).map((p) => p.h).toList();
        final validA = dayPoints.where((p) => p.a > 0.0).map((p) => p.a).toList();

        final avgT = validT.isNotEmpty
            ? double.parse((validT.reduce((a, b) => a + b) / validT.length).toStringAsFixed(1))
            : dayPoints.last.t;
        final avgH = validH.isNotEmpty
            ? double.parse((validH.reduce((a, b) => a + b) / validH.length).toStringAsFixed(1))
            : dayPoints.last.h;
        final avgA = validA.isNotEmpty
            ? (validA.reduce((a, b) => a + b) / validA.length).roundToDouble()
            : dayPoints.last.a;

        finalTemps.add(avgT);
        finalHums.add(avgH);
        finalAcoustics.add(avgA);
        finalDates.add(_formatDateTimeForTimeframe(dayPoints.last.dt, _selectedTimeframe));
      }
    }

    return (
      temps: hasTemps ? finalTemps : <double>[],
      hums: hasHums ? finalHums : <double>[],
      acoustics: hasAcoustic ? finalAcoustics : <double>[],
      dates: finalDates,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Timeframe Selector (Swipeable) & Export Bar
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -150) {
                    // Swipe left -> advance timeframe
                    if (_selectedTimeframe < _timeframeLabels.length - 1) {
                      setState(() => _selectedTimeframe++);
                    }
                  } else if (velocity > 150) {
                    // Swipe right -> previous timeframe
                    if (_selectedTimeframe > 0) {
                      setState(() => _selectedTimeframe--);
                    }
                  }
                },
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
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
                  ExportService.exportCsvReport(context, _liveHive);
                } else if (value == 'audit') {
                  ExportService.exportAuditReport(context, _liveHive);
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
        const SizedBox(height: 16),

        // 5. Recent Hive Audio Recordings (Last 5)
        _buildAudioRecordingsCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ================= SCROLLABLE CHART CONTAINER =================
  Widget _buildScrollableChart({
    required Widget chart,
    required int dataLength,
    double height = 160,
  }) {
    final bool needsScroll = dataLength >= 2;

    if (!needsScroll) {
      // Single data point — just show it centered, no scroll
      return SizedBox(
        height: height,
        child: ClipRect(
          child: RepaintBoundary(child: chart),
        ),
      );
    }

    // Always make the chart wider than the viewport so it's swipable
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 64; // minus card + screen padding
    final perBarWidth = max(76.0, availableWidth / dataLength);
    final chartWidth = max(dataLength * perBarWidth, availableWidth + 120);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            key: ValueKey('history_scroll_${_selectedTimeframe}_$dataLength'),
            scrollDirection: Axis.horizontal,
            reverse: true, // Start anchored at the newest (rightmost) readings
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: chartWidth,
              child: ClipRect(
                child: RepaintBoundary(child: chart),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.swipe, size: 13, color: Colors.black38),
            SizedBox(width: 4),
            Text(
              'Showing latest readings • Swipe right for earlier history',
              style: TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  // ================= TEMPERATURE CARD =================
  Widget _buildTemperatureCard() {
    final synced = _syncedHistoryData;
    final temps = synced.temps;
    final chartDates = synced.dates;

    if (temps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20.0),
        decoration: AppStyles.cardDecoration(),
        child: Column(
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
            const SizedBox(height: 20),
            const Icon(Icons.sensors_outlined, size: 36, color: Colors.black26),
            const SizedBox(height: 8),
            Text(
              'Awaiting live temperature data from ${_liveHive.deviceId}...',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    final validTemps = temps.where((t) => t > 0.0).toList();
    final avgTemp = validTemps.isNotEmpty
        ? (validTemps.reduce((a, b) => a + b) / validTemps.length).toStringAsFixed(1)
        : (temps.isNotEmpty ? temps.last.toStringAsFixed(1) : '34.0');

    final maxVal = temps.isNotEmpty ? temps.reduce(max) : 36.0;
    final double maxY = max(45.0, ((maxVal / 5).ceil() * 5).toDouble());

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
                decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Optimal Brood Nest Zone (32.0°C - 36.0°C • Alert ≤ 25.0°C / ≥ 85.0°C)',
                  style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: temps.length,
            height: 162,
            chart: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: temps.length <= 4 ? BarChartAlignment.spaceEvenly : BarChartAlignment.spaceAround,
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
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}°',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.round();
                        if ((val - idx).abs() > 0.05) return const SizedBox.shrink();
                        if (idx < 0 || idx >= chartDates.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            chartDates[idx],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(temps.length, (i) {
                  final t = temps[i];
                  final isOptimal = t >= 32.0 && t <= 36.0;
                  final isTempAlert = (t > 0.0 && t <= 25.0) || t >= 85.0;
                  final isHot = t > 36.0 && t < 85.0;
                  final barColor = isOptimal
                      ? AppColors.healthyGreen
                      : (isTempAlert
                          ? const Color(0xFFD32F2F)
                          : (isHot ? const Color(0xFFE65100) : const Color(0xFFFFB300)));
                  final safeToY = t.clamp(0.0, maxY * 0.92);

                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: safeToY,
                        color: t <= 0.0 ? Colors.grey.shade400 : barColor,
                        width: temps.length == 1 ? 24 : 14,
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

  // ================= HUMIDITY CARD =================
  Widget _buildHumidityCard() {
    final synced = _syncedHistoryData;
    final hums = synced.hums;
    final chartDates = synced.dates;

    if (hums.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20.0),
        decoration: AppStyles.cardDecoration(),
        child: Column(
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
            const SizedBox(height: 20),
            const Icon(Icons.water_outlined, size: 36, color: Colors.black26),
            const SizedBox(height: 8),
            Text(
              'Awaiting live humidity data from ${_liveHive.deviceId}...',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    final validHums = hums.where((h) => h > 0.0).toList();
    final avgHum = validHums.isNotEmpty
        ? (validHums.reduce((a, b) => a + b) / validHums.length).toStringAsFixed(0)
        : (hums.isNotEmpty ? hums.last.toStringAsFixed(0) : '60');

    const double maxY = 100.0;

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
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Color(0xFF0288D1), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Optimal Hive Humidity Zone (50% - 75% • Alert ≥ 85%)',
                  style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: hums.length,
            height: 162,
            chart: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: hums.length <= 4 ? BarChartAlignment.spaceEvenly : BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.black.withAlpha(20), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      reservedSize: 32,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}%',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.round();
                        if ((val - idx).abs() > 0.05) return const SizedBox.shrink();
                        if (idx < 0 || idx >= chartDates.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            chartDates[idx],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(hums.length, (i) {
                  final h = hums[i];
                  final isHumAlert = h >= 85.0;
                  final isOptimal = h >= 50.0 && h <= 75.0;
                  final barColor = isHumAlert
                      ? const Color(0xFFD32F2F)
                      : (isOptimal
                          ? const Color(0xFF0288D1)
                          : (h > 75.0 ? const Color(0xFF01579B) : const Color(0xFFFFB300)));
                  final safeToY = h.clamp(0.0, 94.0);

                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: safeToY,
                        color: h <= 0.0 ? Colors.grey.shade400 : barColor,
                        width: hums.length == 1 ? 24 : 14,
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

  // ================= ACOUSTIC CARD =================
  Widget _buildAcousticCard() {
    final synced = _syncedHistoryData;
    final acoustics = synced.acoustics;
    final chartDates = synced.dates;

    if (acoustics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20.0),
        decoration: AppStyles.cardDecoration(),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.graphic_eq, size: 20, color: AppColors.healthyGreen),
                SizedBox(width: 6),
                Text(
                  'Acoustic Frequency History (Hz)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Icon(Icons.mic_none_outlined, size: 36, color: Colors.black26),
            const SizedBox(height: 8),
            Text(
              'Awaiting audio stream packets from ${_liveHive.deviceId}...',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    final validAcoustics = acoustics.where((a) => a > 0.0).toList();
    final avgHz = validAcoustics.isNotEmpty
        ? (validAcoustics.reduce((a, b) => a + b) / validAcoustics.length).toStringAsFixed(0)
        : (acoustics.isNotEmpty ? acoustics.last.toStringAsFixed(0) : '0');

    final maxVal = acoustics.isNotEmpty ? acoustics.reduce(max) : 260.0;
    final double maxY = max(300.0, ((maxVal / 50).ceil() * 50).toDouble() + 50.0);
    final double yInterval = maxY > 400 ? 100 : 50;

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
                  Icon(Icons.graphic_eq, size: 20, color: AppColors.healthyGreen),
                  SizedBox(width: 6),
                  Text(
                    'Acoustic Frequency History (Hz)',
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
                  'Avg: $avgHz Hz',
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
                decoration: const BoxDecoration(color: AppColors.healthyGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Normal Queenright Hum Zone (90 - 260 Hz • < 90 Hz No Buzz)',
                  style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildScrollableChart(
            dataLength: acoustics.length,
            height: 162,
            chart: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: acoustics.length <= 4 ? BarChartAlignment.spaceEvenly : BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.black.withAlpha(20), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      reservedSize: 34,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.round();
                        if ((val - idx).abs() > 0.05) return const SizedBox.shrink();
                        if (idx < 0 || idx >= chartDates.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            chartDates[idx],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(acoustics.length, (i) {
                  final hz = acoustics[i];
                  final safeToY = hz.clamp(0.0, maxY * 0.92);
                  final isNoBuzz = hz > 0.0 && hz < 90.0;
                  final isHigh = hz >= 320.0;
                  final isElevated = hz > 260.0 && hz < 320.0;
                  final barColor = hz <= 0.0
                      ? Colors.grey.shade400
                      : (isNoBuzz
                          ? const Color(0xFFD32F2F)
                          : (isHigh
                              ? const Color(0xFFE65100)
                              : (isElevated ? const Color(0xFFFFB300) : AppColors.healthyGreen)));
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: safeToY,
                        color: barColor,
                        width: acoustics.length == 1 ? 24 : 14,
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
    final timeline = _liveHive.conditionTimeline.isNotEmpty
        ? _liveHive.conditionTimeline
        : [
            {
              'date': _liveHive.updated,
              'status': _liveHive.conditionLabel,
            }
          ];

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
            children: timeline.map((item) {
              final status = item['status'] ?? _liveHive.conditionLabel;
              final date = item['date'] ?? _liveHive.updated;
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

  // ================= 5. RECENT HIVE AUDIO RECORDINGS (LAST 5) =================
  Widget _buildAudioRecordingsCard() {
    return AnimatedBuilder(
      animation: AudioService(),
      builder: (context, _) {
        final audioService = AudioService();
        final recordings = audioService.getCachedRecordings(_liveHive.deviceId);
        final isPlaying = audioService.isPlaying;
        final activeId = audioService.activePlayingId;

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
                      Icon(Icons.headphones_outlined, size: 20, color: Colors.black87),
                      SizedBox(width: 8),
                      Text(
                        'Recent Hive Buzz Recordings',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      audioService.fetchRecordingsForDevice(_liveHive.deviceId);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, size: 12, color: Colors.black54),
                          SizedBox(width: 4),
                          Text(
                            'Refresh',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Up to 5 recent 3.0-second acoustic audio clips captured on boot and cycle cooldown.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 14),

              if (recordings.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mic_none_outlined, size: 36, color: Colors.black38),
                      const SizedBox(height: 8),
                      Text(
                        'Awaiting buzz recordings from ${_liveHive.name}...',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Recordings are captured in 3-second clips whenever the ESP32 node boots up or completes a cooldown cycle.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recordings.length,
                  separatorBuilder: (context, index) => const Divider(height: 16, color: Colors.black12),
                  itemBuilder: (context, index) {
                    final clip = recordings[index];
                    final isThisPlaying = isPlaying && activeId == clip.id;

                    Color badgeColor = AppColors.healthyGreen;
                    Color badgeBg = AppColors.queenPresentGreenBg;
                    if (clip.frequency == 0 || clip.condition.toLowerCase().contains('no buzz')) {
                      badgeColor = AppColors.queenAbsentRed;
                      badgeBg = AppColors.queenAbsentRedBg;
                    } else if (clip.frequency >= 320 || clip.condition.toLowerCase().contains('rejected')) {
                      badgeColor = AppColors.queenRejectedOrange;
                      badgeBg = AppColors.queenRejectedOrangeBg;
                    } else if (clip.condition.toLowerCase().contains('accepted')) {
                      badgeColor = AppColors.queenAcceptedBlue;
                      badgeBg = AppColors.queenAcceptedBlueBg;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // Play/Pause button
                          GestureDetector(
                            onTap: () {
                              audioService.playRecording(clip);
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isThisPlaying ? Colors.black : const Color(0xFFFFCC00),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isThisPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                color: isThisPlaying ? Colors.white : Colors.black,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Metadata column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            'Clip #${index + 1}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: clip.isRestartEvent
                                                  ? const Color(0xFFFFF3E0)
                                                  : const Color(0xFFE3F2FD),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: clip.isRestartEvent
                                                    ? const Color(0xFFFFB74D)
                                                    : const Color(0xFF90CAF9),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  clip.isRestartEvent ? Icons.restart_alt : Icons.hourglass_bottom_rounded,
                                                  size: 10,
                                                  color: clip.isRestartEvent ? const Color(0xFFE65100) : const Color(0xFF1976D2),
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  clip.triggerLabel,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: clip.isRestartEvent ? const Color(0xFFE65100) : const Color(0xFF1976D2),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        clip.frequency > 0 ? '${clip.frequency} Hz' : '0 Hz',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_filled, size: 12, color: Colors.black45),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Recorded at ${clip.formattedRecordedTime}${clip.formattedRecordedDate.isNotEmpty ? " • ${clip.formattedRecordedDate}" : ""} (${_getClipDisplayTimestamp(index, clip)})',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      clip.condition,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor,
                                      ),
                                    ),
                                    const Text(' • ', style: TextStyle(fontSize: 11, color: Colors.black38)),
                                    Text(
                                      '${clip.temperature.toStringAsFixed(1)}°C / ${clip.humidity.toStringAsFixed(0)}%',
                                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                                    ),
                                    const Spacer(),
                                    Text(
                                      isThisPlaying ? 'Playing...' : '3.0s',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isThisPlaying ? const Color(0xFFE65100) : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _getClipDisplayTimestamp(int index, AudioRecordingModel clip) {
    int epoch = clip.createdAt;
    if (epoch > 0 && epoch < 1700000000000 && epoch > 1700000000) {
      epoch = epoch * 1000;
    }

    if (epoch > 1700000000000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final diffMs = now - epoch;
      if (diffMs >= 0) {
        final diffMin = diffMs ~/ 60000;
        if (diffMin < 1) {
          return 'Just now';
        } else if (diffMin < 60) {
          return '$diffMin min${diffMin > 1 ? "s" : ""} ago';
        } else {
          final hours = diffMin ~/ 60;
          if (hours < 24) {
            return '$hours hr${hours > 1 ? "s" : ""} ago';
          } else {
            final days = hours ~/ 24;
            return '$days day${days > 1 ? "s" : ""} ago';
          }
        }
      }
    }
    return 'Recorded earlier';
  }
}
