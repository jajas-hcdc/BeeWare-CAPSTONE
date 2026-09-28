import 'package:flutter/material.dart';
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
                acoustic: '0 Hz',
                acousticStatus: 'Not Detected (0 Hz)',
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
    final parsedTemp = double.tryParse(_hive.temperature.replaceAll('°C', '').trim());
    final parsedHum = double.tryParse(_hive.humidity.replaceAll('%', '').trim());
    final tempVal = parsedTemp ?? 34.2;
    final humVal = parsedHum ?? 64.0;
    final hasRealTemp = _hive.temperature != '--';
    final hasRealHum = _hive.humidity != '--';
    final isConnecting = _hive.conditionLabel.toLowerCase().contains('connect') || !hasRealTemp || !hasRealHum;

    final isTempNotDetected = (parsedTemp != null && parsedTemp <= 0.0) || _hive.temperature == '0.0' || _hive.temperature == '0';
    final isHumNotDetected = (parsedHum != null && parsedHum <= 0.0) || _hive.humidity == '0.0' || _hive.humidity == '0';
    final acousticClean = _hive.acoustic.trim().toLowerCase();
    final isAcousticNotDetected = acousticClean == '0' ||
        acousticClean == '0 hz' ||
        acousticClean.startsWith('0 ') ||
        _hive.acousticStatus.toLowerCase().contains('not detected');
    final hasSensorNotDetected = isTempNotDetected || isHumNotDetected || isAcousticNotDetected;

    String overviewDesc;
    String conditionActionDesc;

    if (isConnecting) {
      overviewDesc = 'ESP32 IoT node paired. Live sensor telemetry streaming to backend.';
      conditionActionDesc = 'Awaiting Telemetry Stream.\nSensor calibration in progress.';
    } else if (isAcousticNotDetected) {
      overviewDesc = 'No buzz detected (0 Hz / Silent). Acoustic activity is absent or microphone is disconnected.';
      conditionActionDesc = 'No Buzz Detected (0 Hz).\nInspect microphone or check hive activity.';
    } else if (_hive.conditionLabel.toLowerCase().contains('absent')) {
      overviewDesc = 'Acoustic frequency indicates Queenless Roar. Urgent frame inspection needed.';
      conditionActionDesc = 'Urgent Intervention Required.\nInspect brood frames for queen cells.';
    } else if (_hive.conditionLabel.toLowerCase().contains('rejected')) {
      overviewDesc = 'High agitation buzzing detected. Workers rejecting introduced queen.';
      conditionActionDesc = 'Worker Agitation Detected.\nInspect slow-release cage.';
    } else if (_hive.conditionLabel.toLowerCase().contains('accepted')) {
      overviewDesc = 'Colony piping harmony confirmed. Queen accepted into hive.';
      conditionActionDesc = 'Colony Harmonious.\nAvoid disturbing brood nest for 5 days.';
    } else {
      overviewDesc = 'The colony is queenright and showing normal healthy behavior.';
      conditionActionDesc = 'Colony Stable.\nContinue regular routine monitoring.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sensor Not Detected Alert Banner
        if (hasSensorNotDetected)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF5350), width: 1.2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sensor Not Detected Alert',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (isTempNotDetected) '• Temperature sensor not detected (0.0°C)',
                          if (isHumNotDetected) '• Humidity sensor not detected (0%)',
                          if (isAcousticNotDetected) '• Acoustic microphone not detected (0 Hz)',
                        ].join('\n'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C), height: 1.3),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Inspect physical sensor wiring and power on the ESP32 node.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

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
                    percentage: isAcousticNotDetected ? 0.0 : _hive.healthScore.toDouble(),
                    size: 78,
                    strokeWidth: 9,
                    progressColor: isAcousticNotDetected ? const Color(0xFFD32F2F) : _hive.labelColor,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAcousticNotDetected
                              ? 'No Buzz Detected'
                              : _hive.conditionLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isAcousticNotDetected ? const Color(0xFFD32F2F) : _hive.labelColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          overviewDesc,
                          style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAcousticNotDetected
                              ? 'Confidence: 0%'
                              : (_hive.confidence > 0 ? 'Confidence: ${_hive.confidence}%' : 'Confidence: Analysis In Progress'),
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        if (isAcousticNotDetected) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF5350)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_off, size: 13, color: Color(0xFFD32F2F)),
                                SizedBox(width: 4),
                                Text(
                                  'No Buzz Detected (0 Hz)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFD32F2F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                        color: isAcousticNotDetected ? const Color(0xFFFFEBEE) : _hive.labelBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAcousticNotDetected ? 'No Buzz Detected' : _hive.conditionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isAcousticNotDetected ? const Color(0xFFC62828) : _hive.labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      conditionActionDesc,
                      style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
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
                          isTempNotDetected
                              ? '0.0°C (Not Detected)'
                              : (_hive.temperature.contains('-') ? '--' : '${_hive.temperature}°C'),
                          style: TextStyle(
                            fontSize: isTempNotDetected ? 13 : 15,
                            fontWeight: FontWeight.w900,
                            color: isTempNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                          ),
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
                          isHumNotDetected
                              ? '0% (Not Detected)'
                              : (_hive.humidity.contains('-') ? '--' : '${_hive.humidity}%'),
                          style: TextStyle(
                            fontSize: isHumNotDetected ? 13 : 15,
                            fontWeight: FontWeight.w900,
                            color: isHumNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                          ),
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
                            isAcousticNotDetected ? '0 Hz (Not Detected)' : _hive.acoustic,
                            style: TextStyle(
                              fontSize: isAcousticNotDetected ? 13 : 13,
                              fontWeight: FontWeight.w900,
                              color: isAcousticNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AcousticSignalVisualizer(
                      conditionLabel: _hive.conditionLabel,
                      acousticStatus: _hive.acousticStatus,
                      acoustic: _hive.acoustic,
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
    final parsedTemp = double.tryParse(_hive.temperature.replaceAll('°C', '').trim());
    final parsedHum = double.tryParse(_hive.humidity.replaceAll('%', '').trim());
    final tempVal = parsedTemp ?? 34.2;
    final humVal = parsedHum ?? 64.0;

    final isTempNotDetected = (parsedTemp != null && parsedTemp <= 0.0) || _hive.temperature == '0.0' || _hive.temperature == '0';
    final isHumNotDetected = (parsedHum != null && parsedHum <= 0.0) || _hive.humidity == '0.0' || _hive.humidity == '0';
    final acousticClean = _hive.acoustic.trim().toLowerCase();
    final isAcousticNotDetected = acousticClean == '0' ||
        acousticClean == '0 hz' ||
        acousticClean.startsWith('0 ') ||
        _hive.acousticStatus.toLowerCase().contains('not detected');
    final hasSensorNotDetected = isTempNotDetected || isHumNotDetected || isAcousticNotDetected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sensor Not Detected Alert Banner
        if (hasSensorNotDetected)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF5350), width: 1.2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sensor Not Detected Alert',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (isTempNotDetected) '• Temperature sensor not detected (0.0°C)',
                          if (isHumNotDetected) '• Humidity sensor not detected (0%)',
                          if (isAcousticNotDetected) '• Acoustic microphone not detected (0 Hz)',
                        ].join('\n'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C), height: 1.3),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Inspect physical sensor wiring and power on the ESP32 node.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

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
                              isTempNotDetected
                                  ? '0.0°C (Not Detected)'
                                  : (_hive.temperature.contains('-') ? '--' : '${_hive.temperature}°C'),
                              style: TextStyle(
                                fontSize: isTempNotDetected ? 18 : 22,
                                fontWeight: FontWeight.w900,
                                color: isTempNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isTempNotDetected ? '⚠️ Check DHT22 Data Wire (GPIO 4)' : 'Normal Range: 30°C - 40°C',
                          style: TextStyle(
                            fontSize: 11,
                            color: isTempNotDetected ? const Color(0xFFD32F2F) : Colors.black54,
                            fontWeight: isTempNotDetected ? FontWeight.w700 : FontWeight.w500,
                          ),
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
                              isHumNotDetected
                                  ? '0% (Not Detected)'
                                  : (_hive.humidity.contains('-') ? '--' : '${_hive.humidity}%'),
                              style: TextStyle(
                                fontSize: isHumNotDetected ? 18 : 22,
                                fontWeight: FontWeight.w900,
                                color: isHumNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isHumNotDetected ? '⚠️ Check DHT22 Data Wire (GPIO 4)' : 'Normal Range: 50% - 70%',
                          style: TextStyle(
                            fontSize: 11,
                            color: isHumNotDetected ? const Color(0xFFD32F2F) : Colors.black54,
                            fontWeight: isHumNotDetected ? FontWeight.w700 : FontWeight.w500,
                          ),
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
                                isAcousticNotDetected ? '0 Hz (Not Detected)' : _hive.acoustic,
                                style: TextStyle(
                                  fontSize: isAcousticNotDetected ? 14 : 15,
                                  fontWeight: FontWeight.w900,
                                  color: isAcousticNotDetected ? const Color(0xFFD32F2F) : Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isAcousticNotDetected ? 'Status: Not Detected (0 Hz)' : 'Status: ${_hive.acousticStatus}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isAcousticNotDetected ? const Color(0xFFD32F2F) : Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AcousticSignalVisualizer(
                    conditionLabel: _hive.conditionLabel,
                    acousticStatus: _hive.acousticStatus,
                    acoustic: _hive.acoustic,
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
    final parsedTemp = double.tryParse(_hive.temperature.replaceAll('°C', '').trim());
    final parsedHum = double.tryParse(_hive.humidity.replaceAll('%', '').trim());
    final isTempNotDetected = (parsedTemp != null && parsedTemp <= 0.0) || _hive.temperature == '0.0' || _hive.temperature == '0';
    final isHumNotDetected = (parsedHum != null && parsedHum <= 0.0) || _hive.humidity == '0.0' || _hive.humidity == '0';
    final acousticClean = _hive.acoustic.trim().toLowerCase();
    final isAcousticNotDetected = acousticClean == '0' ||
        acousticClean == '0 hz' ||
        acousticClean.startsWith('0 ') ||
        _hive.acousticStatus.toLowerCase().contains('not detected');
    final hasSensorNotDetected = isTempNotDetected || isHumNotDetected || isAcousticNotDetected;

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
                        color: isAcousticNotDetected ? const Color(0xFFFFEBEE) : _hive.labelBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAcousticNotDetected ? 'No Buzz Detected' : _hive.conditionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isAcousticNotDetected ? const Color(0xFFC62828) : _hive.labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAcousticNotDetected ? 'Confidence: 0%' : 'Confidence: ${_hive.confidence}%',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    if (isAcousticNotDetected) ...[
                      const SizedBox(height: 5),
                      const Text(
                        '⚠️ No buzz detected (0 Hz / Silent)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ],
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
          decoration: AppStyles.cardDecoration(color: _hive.labelBgColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Explanation',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 6),
              Text(
                isAcousticNotDetected
                    ? '⚠️ No Buzz Detected: The acoustic microphone recorded 0 Hz (silence). The AI cannot detect active worker humming, queen piping, or colony vibration until acoustic buzz signals are present.\n\n${_hive.explanation}'
                    : _hive.explanation,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Detected Colony Conditions',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                  ),
                  if (isAcousticNotDetected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Offline / Inactive',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow(
                'Queen Present',
                isAcousticNotDetected ? false : _hive.queenPresentDetected,
                isDimmed: isAcousticNotDetected,
              ),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow(
                'Queen Absent',
                isAcousticNotDetected ? false : _hive.queenAbsentDetected,
                isDimmed: isAcousticNotDetected,
              ),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow(
                'Queen Accepted',
                isAcousticNotDetected ? false : _hive.queenAcceptedDetected,
                isDimmed: isAcousticNotDetected,
              ),
              const Divider(color: Colors.black12, height: 18),
              _conditionDetectRow(
                'Queen Rejected',
                isAcousticNotDetected ? false : _hive.queenRejectedDetected,
                isDimmed: isAcousticNotDetected,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Separate Colony Acoustic Buzz Card (Below Detected Colony Conditions)
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _conditionDetectRow(
                'Colony Acoustic Buzz',
                !isAcousticNotDetected,
                overrideStatusText: isAcousticNotDetected ? 'No Buzz\nDetected' : 'Buzzing\nDetected',
                overrideColor: isAcousticNotDetected ? const Color(0xFFD32F2F) : AppColors.healthyGreen,
              ),
              if (isAcousticNotDetected) ...[
                const SizedBox(height: 8),
                const Text(
                  'Colony acoustics are currently silent (0 Hz). Ensure the microphone is connected to enable audio-based condition detection.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFD32F2F),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // AI Recommendation Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(
            color: hasSensorNotDetected ? const Color(0xFFFFF8E1) : AppColors.infoBlueBg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasSensorNotDetected ? Icons.lightbulb_outline : Icons.info_outline,
                color: hasSensorNotDetected ? const Color(0xFFF57F17) : Colors.black87,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Recommendation',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: hasSensorNotDetected ? const Color(0xFFE65100) : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAcousticNotDetected
                          ? '⚠️ No buzz detected: Colony acoustics are currently silent (0 Hz). Ensure the microphone is connected and verify if bees are active in the hive box.\n\n${_hive.recommendation}'
                          : (hasSensorNotDetected
                              ? '⚠️ Sensor Data Missing: Connect offline sensors for accurate colony diagnosis.\n\n${_hive.recommendation}'
                              : _hive.recommendation),
                      style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Below the AI Recommendation: Sensor Connection & Diagnostic Advisory Card
        if (hasSensorNotDetected) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEF5350), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 24),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Sensor Disconnected Alert',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC62828),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCDD2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ACTION REQUIRED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFB71C1C),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'The AI detected that the following hardware sensor(s) are offline or not connected to the ESP32 node:',
                  style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C), height: 1.3),
                ),
                const SizedBox(height: 10),
                if (isTempNotDetected)
                  _sensorActionRow(
                    icon: Icons.thermostat,
                    title: 'Temperature Sensor Not Detected (0.0°C)',
                    action: 'Check DHT22 DATA wire on GPIO 4 & verify 3.3V power and GND connections.',
                  ),
                if (isHumNotDetected)
                  _sensorActionRow(
                    icon: Icons.water_drop,
                    title: 'Humidity Sensor Not Detected (0%)',
                    action: 'Check DHT22 DATA wire on GPIO 4 & verify sensor contacts are clean and dry.',
                  ),
                if (isAcousticNotDetected)
                  _sensorActionRow(
                    icon: Icons.mic_off,
                    title: 'Acoustic Microphone Not Detected (0 Hz / Silent)',
                    action: 'Check INMP441 pins: D33 (SD), D32 (SCK), D25 (WS), 3.3V (VDD), GND, & L/R to GND.',
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.build_circle_outlined, size: 18, color: Color(0xFFD32F2F)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'After reconnecting wires, press the EN (Reset) button on the ESP32 node to refresh live AI diagnostics.',
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Color _getConditionActiveColor(String conditionName) {
    final lower = conditionName.toLowerCase();
    if (lower.contains('present')) return AppColors.queenPresentGreen;
    if (lower.contains('absent')) return AppColors.queenAbsentRed;
    if (lower.contains('accepted')) return AppColors.queenAcceptedBlue;
    if (lower.contains('rejected')) return AppColors.queenRejectedOrange;
    return AppColors.healthyGreen;
  }

  Widget _conditionDetectRow(
    String conditionName,
    bool isDetected, {
    String? overrideStatusText,
    Color? overrideColor,
    bool isDimmed = false,
  }) {
    final activeColor = overrideColor ?? _getConditionActiveColor(conditionName);
    final dotColor = isDimmed
        ? Colors.grey.shade400
        : (isDetected ? activeColor : (overrideColor ?? Colors.grey.shade400));
    final titleColor = isDimmed
        ? Colors.grey.shade500
        : (isDetected ? Colors.black : Colors.grey.shade600);
    final statusColor = isDimmed
        ? Colors.grey.shade400
        : (isDetected ? activeColor : (overrideColor ?? Colors.grey.shade500));

    return Opacity(
      opacity: isDimmed ? 0.55 : 1.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                conditionName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: (isDetected && !isDimmed) ? FontWeight.w800 : FontWeight.w600,
                  color: titleColor,
                ),
              ),
            ],
          ),
          Text(
            isDimmed
                ? 'Not\nDetected'
                : (overrideStatusText ?? (isDetected ? 'Detected' : 'Not\nDetected')),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorActionRow({
    required IconData icon,
    required String title,
    required String action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCDD2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFC62828)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- TAB 4: HISTORY ----------------
  Widget _buildHistoryTab() {
    return InteractiveHistoryView(hive: _hive);
  }
}
