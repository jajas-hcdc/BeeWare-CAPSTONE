git add .import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/interactive_history_charts.dart';
import '../widgets/sensor_visualizers.dart';

class HiveDetailScreen extends StatefulWidget {
  static const routeName = '/hive-detail';
  final HiveData? hive;
  final int initialTab;

  const HiveDetailScreen({super.key, this.hive, this.initialTab = 0});

  @override
  State<HiveDetailScreen> createState() => _HiveDetailScreenState();
}

class _HiveDetailScreenState extends State<HiveDetailScreen> {
  late int _selectedTab;
  late HiveData _hive;
  late final PageController _pageController;

  final List<String> _tabs = ['Overview', 'Sensors', 'AI analysis', 'History'];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _pageController = PageController(initialPage: _selectedTab);
    _hive = widget.hive ??
        (HiveService().hives.isNotEmpty
            ? HiveService().hives.first
            : HiveData(
                id: 'hive_live',
                name: 'Live Hive',
                conditionLabel: 'Queen Present',
                confidence: 90,
                healthScore: 90,
                temperature: '--',
                humidity: '--',
                acoustic: 'Normal Activity',
                updated: 'Just now',
                isAlert: false,
                alertLabel: 'Queen Present',
                alertMessage: 'Waiting for live telemetry stream...',
              ));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_selectedTab != index) {
      setState(() => _selectedTab = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  String _getHeaderTitle() {
    switch (_selectedTab) {
      case 1:
        return '${_hive.name} - Sensors';
      case 2:
        return '${_hive.name} - Analysis';
      case 3:
        return '${_hive.name} - History';
      default:
        return _hive.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, child) {
        final live = HiveService().getHiveById(_hive.id);
        if (live != null) {
          _hive = live;
        }

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
          appBar: CustomHeaderBar(
            title: _getHeaderTitle(),
            showBack: true,
          ),
          body: Column(
            children: [
              // Sub-tab Navigation Bar
              Container(
                color: AppColors.screenYellow,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(_tabs.length, (index) {
                    final isSelected = index == _selectedTab;
                    return GestureDetector(
                      onTap: () => _onTabTapped(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: isSelected
                              ? const Border(
                                  bottom: BorderSide(color: Colors.black, width: 2.5),
                                )
                              : null,
                        ),
                        child: Text(
                          _tabs[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Sub-tab PageView with swipe and slide navigation
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _selectedTab = index);
                  },
                  children: [
                    _buildTabWrapper(_buildOverviewTab()),
                    _buildTabWrapper(_buildSensorsTab()),
                    _buildTabWrapper(_buildAiAnalysisTab()),
                    _buildTabWrapper(_buildHistoryTab()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabWrapper(Widget content) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hive.isSensorOffline)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB74D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, size: 18, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Sensor Node Offline (${_hive.lastSeenText})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          content,
        ],
      ),
    );
  }

  // ---------------- TAB 1: OVERVIEW ----------------
  Widget _buildOverviewTab() {
    final tempVal = double.tryParse(_hive.temperature.replaceAll('°C', '').trim()) ?? 34.2;
    final humVal = double.tryParse(_hive.humidity.replaceAll('%', '').trim()) ?? 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: AI Colony Health Assessment
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Colony Health Assessment',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircularGauge(
                    percentage: _hive.healthScore.toDouble(),
                    size: 78,
                    strokeWidth: 9,
                    progressColor: _hive.labelColor,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hive.conditionLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: _hive.labelColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'The colony is healthy and is showing normal behavior.',
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Confidence: ${_hive.confidence}%',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 2: Current Colony Condition with Mascot
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Colony Condition',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hive.labelBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _hive.conditionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _hive.labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No Intervention Required.\nContinue Monitoring.',
                      style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                    ),
                  ],
                ),
              ),
              Image.asset(
                'assets/images/bee_mascot_large.png',
                height: 80,
                width: 80,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.emoji_nature, size: 60, color: Colors.black),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 3: Current Sensor Data with modern visualizers
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Current Sensor Data',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                  ),
                  Text(_hive.updated.toLowerCase().contains('just now') ? 'Just Now' : _hive.updated, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
              const Divider(color: Colors.black26, height: 20),

              // Temperature row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.thermostat, size: 20, color: Color(0xFFE65100)),
                            SizedBox(width: 4),
                            Text('Temperature', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_hive.temperature}°C',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ],
                    ),
                    TemperatureVisualizer(
                      currentTemp: tempVal,
                      history: _hive.temperatureHistory,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12, height: 18),

              // Humidity row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.water_drop_outlined, size: 20, color: Color(0xFF0288D1)),
                            SizedBox(width: 4),
                            Text('Humidity', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_hive.humidity}%',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ],
                    ),
                    HumidityVisualizer(
                      currentHumidity: humVal,
                      history: _hive.humidityHistory,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12, height: 18),

              // Acoustic Signal row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.graphic_eq, size: 20, color: Color(0xFFFFB300)),
                              SizedBox(width: 4),
                              Text('Acoustic Signal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _hive.acoustic,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AcousticSignalVisualizer(
                      conditionLabel: _hive.conditionLabel,
                      acousticStatus: _hive.acousticStatus,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- TAB 2: SENSORS ----------------
  Widget _buildSensorsTab() {
    final tempVal = double.tryParse(_hive.temperature.replaceAll('°C', '').trim()) ?? 34.2;
    final humVal = double.tryParse(_hive.humidity.replaceAll('%', '').trim()) ?? 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Temperature Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Temperature', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.thermostat, size: 34, color: Color(0xFFE65100)),
                            const SizedBox(width: 8),
                            Text(
                              '${_hive.temperature}°C',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Normal Range: 30°C - 40°C',
                          style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  TemperatureVisualizer(
                    currentTemp: tempVal,
                    history: _hive.temperatureHistory,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Humidity Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Humidity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.water_drop_outlined, size: 34, color: Color(0xFF0288D1)),
                            const SizedBox(width: 8),
                            Text(
                              '${_hive.humidity}%',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Normal Range: 50% - 70%',
                          style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  HumidityVisualizer(
                    currentHumidity: humVal,
                    history: _hive.humidityHistory,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Acoustic Signal Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Acoustic Signal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.graphic_eq, size: 32, color: Color(0xFFFFB300)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _hive.acoustic,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Status: ${_hive.acousticStatus}',
                          style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AcousticSignalVisualizer(
                    conditionLabel: _hive.conditionLabel,
                    acousticStatus: _hive.acousticStatus,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Wi-Fi Signal & Battery Row
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14.0),
                decoration: AppStyles.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wi-Fi Signal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.wifi, size: 28, color: Colors.black),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _hive.wifiStatus,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14.0),
                decoration: AppStyles.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Device Battery', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.battery_5_bar, size: 28, color: Colors.black),
                        const SizedBox(width: 6),
                        Text(
                          _hive.batteryLevel,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------- TAB 3: AI ANALYSIS ----------------
  Widget _buildAiAnalysisTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AI Classification Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Colony Condition Classification',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hive.labelBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _hive.conditionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _hive.labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Confidence: ${_hive.confidence}%',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Image.asset(
                'assets/images/bee_mascot_large.png',
                height: 75,
                width: 75,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.emoji_nature, size: 55, color: Colors.black),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Explanation Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(color: AppColors.healthyGreenBg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Explanation',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 6),
              Text(
                _hive.explanation,
                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Detected Colony Conditions Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detected Colony Conditions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
              ),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow('Queen Present', _hive.queenPresentDetected),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow('Queen Absent', _hive.queenAbsentDetected),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow('Queen Accepted', _hive.queenAcceptedDetected),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow('Queen Rejected', _hive.queenRejectedDetected),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // AI Recommendation Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(color: AppColors.infoBlueBg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.black87, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Recommendation',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hive.recommendation,
                      style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conditionDetectRow(String conditionName, bool isDetected) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDetected ? Colors.red : AppColors.healthyGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              conditionName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
            ),
          ],
        ),
        Text(
          isDetected ? 'Detected' : 'Not\nDetected',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            color: isDetected ? Colors.red : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ---------------- TAB 4: HISTORY ----------------
  Widget _buildHistoryTab() {
    return InteractiveHistoryView(hive: _hive);
  }
}
