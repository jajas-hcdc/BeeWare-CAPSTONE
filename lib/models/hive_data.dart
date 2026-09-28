import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HiveData {
  final String id;
  final String name;
  final String deviceId;
  final String notes;
  final String conditionLabel;
  final int confidence;
  final int healthScore;
  final String temperature;
  final String humidity;
  final String acoustic;
  final String acousticStatus;
  final String wifiStatus;
  final String batteryLevel;
  final String updated;
  final int signalBars;

  final String explanation;
  final bool queenPresentDetected;
  final bool queenAbsentDetected;
  final bool queenAcceptedDetected;
  final bool queenRejectedDetected;
  final String recommendation;

  final List<String> historyDates;
  final List<double> temperatureHistory;
  final List<double> humidityHistory;
  final List<double> acousticHistory;
  final List<Map<String, String>> conditionTimeline;

  final bool isAlert;
  final String alertSeverity; // Critical, Warning, Info
  final String alertLabel;
  final String alertMessage;
  final String alertTime;
  final String detectedBy;
  final String alertRecommendation;
  final String? audioFilePath;

  HiveData({
    required this.id,
    required this.name,
    this.deviceId = 'BW-001-A',
    this.notes = 'Main Apiary hive',
    required this.conditionLabel,
    required this.confidence,
    required this.healthScore,
    required this.temperature,
    required this.humidity,
    required this.acoustic,
    this.acousticStatus = 'Normal',
    this.wifiStatus = 'Connected',
    this.batteryLevel = '90%',
    required this.updated,
    this.signalBars = 4,
    this.explanation =
        'The AI analyzed the hive\'s acoustic, temperature, and humidity data and classified the colony state.',
    this.queenPresentDetected = true,
    this.queenAbsentDetected = false,
    this.queenAcceptedDetected = false,
    this.queenRejectedDetected = false,
    this.recommendation =
        'Continue routine monitoring. No intervention required.',
    this.historyDates = const [],
    this.temperatureHistory = const [],
    this.humidityHistory = const [],
    this.acousticHistory = const [],
    this.conditionTimeline = const [],
    required this.isAlert,
    this.alertSeverity = 'Info',
    this.alertLabel = 'Normal',
    required this.alertMessage,
    this.alertTime = 'Just now',
    this.detectedBy = 'AI Acoustic Analysis',
    this.alertRecommendation = 'Continue regular inspection routine.',
    this.audioFilePath,
  });

  Color get labelColor {
    final label = conditionLabel.toLowerCase();
    if (healthScore < 50 || label.contains('absent')) return AppColors.queenAbsentRed;
    if (healthScore < 75 || label.contains('rejected')) return AppColors.queenRejectedOrange;
    if (label.contains('accepted')) return AppColors.queenAcceptedBlue;
    if (label.contains('present') || label.contains('healthy')) return AppColors.healthyGreen;
    return AppColors.healthyGreen;
  }

  Color get labelBgColor {
    final label = conditionLabel.toLowerCase();
    if (label.contains('present')) return AppColors.queenPresentGreenBg;
    if (label.contains('absent')) return AppColors.queenAbsentRedBg;
    if (label.contains('accepted')) return AppColors.queenAcceptedBlueBg;
    if (label.contains('rejected')) return AppColors.queenRejectedOrangeBg;
    if (label.contains('healthy')) return AppColors.healthyGreenBg;
    return const Color(0xFFF0F0F0);
  }

  bool get isSensorOffline {
    final wifi = wifiStatus.toLowerCase();
    if (wifi.contains('disconnect') || wifi.contains('offline')) return true;
    final up = updated.toLowerCase();
    if (up.contains('hr') || up.contains('hour') || up.contains('day') || up.contains('offline')) {
      return true;
    }
    return false;
  }

  String get lastSeenText {
    if (updated.toLowerCase().contains('just now')) return 'Live';
    return 'Last seen: $updated';
  }

  HiveData copyWith({
    String? id,
    String? name,
    String? deviceId,
    String? notes,
    String? conditionLabel,
    int? confidence,
    int? healthScore,
    String? temperature,
    String? humidity,
    String? acoustic,
    String? acousticStatus,
    String? wifiStatus,
    String? batteryLevel,
    String? updated,
    int? signalBars,
    String? explanation,
    bool? queenPresentDetected,
    bool? queenAbsentDetected,
    bool? queenAcceptedDetected,
    bool? queenRejectedDetected,
    String? recommendation,
    List<String>? historyDates,
    List<double>? temperatureHistory,
    List<double>? humidityHistory,
    List<double>? acousticHistory,
    List<Map<String, String>>? conditionTimeline,
    bool? isAlert,
    String? alertSeverity,
    String? alertLabel,
    String? alertMessage,
    String? alertTime,
    String? detectedBy,
    String? alertRecommendation,
    String? audioFilePath,
  }) {
    return HiveData(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      notes: notes ?? this.notes,
      conditionLabel: conditionLabel ?? this.conditionLabel,
      confidence: confidence ?? this.confidence,
      healthScore: healthScore ?? this.healthScore,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      acoustic: acoustic ?? this.acoustic,
      acousticStatus: acousticStatus ?? this.acousticStatus,
      wifiStatus: wifiStatus ?? this.wifiStatus,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      updated: updated ?? this.updated,
      signalBars: signalBars ?? this.signalBars,
      explanation: explanation ?? this.explanation,
      queenPresentDetected: queenPresentDetected ?? this.queenPresentDetected,
      queenAbsentDetected: queenAbsentDetected ?? this.queenAbsentDetected,
      queenAcceptedDetected: queenAcceptedDetected ?? this.queenAcceptedDetected,
      queenRejectedDetected: queenRejectedDetected ?? this.queenRejectedDetected,
      recommendation: recommendation ?? this.recommendation,
      historyDates: historyDates ?? this.historyDates,
      temperatureHistory: temperatureHistory ?? this.temperatureHistory,
      humidityHistory: humidityHistory ?? this.humidityHistory,
      acousticHistory: acousticHistory ?? this.acousticHistory,
      conditionTimeline: conditionTimeline ?? this.conditionTimeline,
      isAlert: isAlert ?? this.isAlert,
      alertSeverity: alertSeverity ?? this.alertSeverity,
      alertLabel: alertLabel ?? this.alertLabel,
      alertMessage: alertMessage ?? this.alertMessage,
      alertTime: alertTime ?? this.alertTime,
      detectedBy: detectedBy ?? this.detectedBy,
      alertRecommendation: alertRecommendation ?? this.alertRecommendation,
      audioFilePath: audioFilePath ?? this.audioFilePath,
    );
  }

  factory HiveData.fromFirestore(String id, Map<String, dynamic> data) {
    var condition = (data['conditionLabel'] ?? 'Queen Present').toString();
    final acousticRaw = (data['acoustic'] ?? 'Normal Activity').toString();
    final acousticStatusRaw = (data['acousticStatus'] ?? 'Normal').toString();
    final freqVal = data['frequency'] ?? data['frequency_hz'];

    final bool isAcousticZero = acousticRaw.trim() == '0 Hz' ||
        acousticRaw.trim() == '0' ||
        acousticRaw.trim().startsWith('0 ') ||
        acousticStatusRaw.toLowerCase().contains('not detected') ||
        freqVal == 0;

    if (isAcousticZero && (condition == 'Queen Present' || condition.isEmpty)) {
      condition = 'No Buzz Detected';
    }

    final isAbsent = condition.toLowerCase().contains('absent');
    final isRejected = condition.toLowerCase().contains('rejected');
    final isAccepted = condition.toLowerCase().contains('accepted');
    final isPresent = !isAbsent && !isRejected && !isAccepted && !isAcousticZero;

    int parsedHealth = (data['healthScore'] as num?)?.toInt() ?? 90;
    if (isAcousticZero) {
      parsedHealth = (parsedHealth > 30) ? 30 : parsedHealth;
    } else if (isAbsent) {
      parsedHealth = (parsedHealth > 45) ? 45 : parsedHealth;
    } else if (isRejected) {
      parsedHealth = (parsedHealth > 50) ? 50 : parsedHealth;
    }

    final bool isAlertVal = data['isAlert'] == true || isAbsent || isRejected || isAcousticZero;
    final String severityVal = isAcousticZero
        ? 'Critical'
        : (data['alertSeverity'] ?? (isAbsent ? 'Critical' : (isRejected ? 'Warning' : 'Info')));
    final String alertLabelVal = isAcousticZero
        ? '⚠️ Acoustic Signal Not Detected (0 Hz)'
        : (data['alertLabel'] ?? condition);
    final String alertMessageVal = isAcousticZero
        ? 'Acoustic microphone on ${data['name'] ?? id} is detecting 0 Hz (silent or disconnected).'
        : (data['alertMessage'] ?? (isAbsent ? 'Colony is Queenless.' : (isRejected ? 'Colony rejecting queen.' : 'Colony is stable.')));

    List<double> parseDoubleList(dynamic list, List<double> fallback) {
      if (list is List) {
        return list.map((e) => (e as num).toDouble()).toList();
      }
      return fallback;
    }

    return HiveData(
      id: id,
      name: data['name'] ?? 'Hive',
      deviceId: data['deviceId'] ?? 'BW-001',
      notes: data['notes'] ?? '',
      conditionLabel: condition,
      confidence: (data['confidence'] as num?)?.toInt() ?? (isAcousticZero ? 50 : 90),
      healthScore: parsedHealth,
      temperature: data['temperature']?.toString() ?? '34.0',
      humidity: data['humidity']?.toString() ?? '60',
      acoustic: isAcousticZero ? '0 Hz' : acousticRaw,
      acousticStatus: isAcousticZero ? 'Not Detected (0 Hz)' : acousticStatusRaw,
      wifiStatus: data['wifiStatus'] ?? 'Connected',
      batteryLevel: data['batteryLevel'] ?? '90%',
      updated: data['updated'] ?? 'Just now',
      signalBars: (data['signalBars'] as num?)?.toInt() ?? 4,
      explanation: data['explanation'] ??
          'The AI analyzed the hive\'s acoustic, temperature, and humidity data and classified the colony state.',
      queenPresentDetected: data['queenPresentDetected'] ?? isPresent,
      queenAbsentDetected: data['queenAbsentDetected'] ?? isAbsent,
      queenAcceptedDetected: data['queenAcceptedDetected'] ?? isAccepted,
      queenRejectedDetected: data['queenRejectedDetected'] ?? isRejected,
      recommendation: data['recommendation'] ??
          (isAcousticZero
              ? 'Check INMP441 I2S microphone wiring and examine hive for activity.'
              : (isAbsent
                  ? 'Inspect frames for emergency queen cells.'
                  : (isRejected
                      ? 'Check release cage and examine worker agitation.'
                      : 'Colony is queenright and stable. Continue regular monitoring.'))),
      historyDates: data['historyDates'] != null
          ? List<String>.from(data['historyDates'])
          : const [],
      temperatureHistory: parseDoubleList(data['temperatureHistory'], const []),
      humidityHistory: parseDoubleList(data['humidityHistory'], const []),
      acousticHistory: parseDoubleList(data['acousticHistory'], const []),
      isAlert: isAlertVal,
      alertSeverity: severityVal,
      alertLabel: alertLabelVal,
      alertMessage: alertMessageVal,
      alertTime: data['alertTime'] ?? 'Just now',
      detectedBy: data['detectedBy'] ?? 'ESP32 & AI Acoustic Model',
      alertRecommendation: data['alertRecommendation'] ??
          (isAcousticZero
              ? 'Verify INMP441 I2S wiring (GPIO 14, 15, 32) and microphone power.'
              : (isAbsent
                  ? 'Inspect frames for emergency queen cells.'
                  : (isRejected
                      ? 'Check release cage and examine worker agitation.'
                      : 'Continue regular inspection routine.'))),
      audioFilePath: data['audioFilePath'] ?? data['audio_file_path'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'deviceId': deviceId,
      'notes': notes,
      'conditionLabel': conditionLabel,
      'confidence': confidence,
      'healthScore': healthScore,
      'temperature': temperature,
      'humidity': humidity,
      'acoustic': acoustic,
      'acousticStatus': acousticStatus,
      'wifiStatus': wifiStatus,
      'batteryLevel': batteryLevel,
      'updated': updated,
      'signalBars': signalBars,
      'explanation': explanation,
      'queenPresentDetected': queenPresentDetected,
      'queenAbsentDetected': queenAbsentDetected,
      'queenAcceptedDetected': queenAcceptedDetected,
      'queenRejectedDetected': queenRejectedDetected,
      'recommendation': recommendation,
      'temperatureHistory': temperatureHistory,
      'humidityHistory': humidityHistory,
      'acousticHistory': acousticHistory,
      'isAlert': isAlert,
      'alertSeverity': alertSeverity,
      'alertLabel': alertLabel,
      'alertMessage': alertMessage,
      'alertTime': alertTime,
      'detectedBy': detectedBy,
      'alertRecommendation': alertRecommendation,
      'audioFilePath': audioFilePath,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toMap(),
      };

  factory HiveData.fromJson(Map<String, dynamic> json) {
    return HiveData.fromFirestore(json['id'] ?? '', json);
  }

  static List<HiveData> samples = [
    HiveData(
      id: 'hive_1',
      name: 'Hive 1',
      deviceId: 'BW-001-ALPHA',
      notes: 'South garden station',
      conditionLabel: 'Queen Present',
      confidence: 95,
      healthScore: 95,
      temperature: '34.2',
      humidity: '64',
      acoustic: '205 Hz',
      acousticStatus: 'Stable',
      wifiStatus: 'Connected',
      batteryLevel: '95%',
      updated: 'Just Now',
      signalBars: 4,
      explanation:
          'The AI acoustic model detected stable queen piping frequencies (205 Hz) and normal hive hum, confirming Queen Presence.',
      queenPresentDetected: true,
      queenAbsentDetected: false,
      queenAcceptedDetected: false,
      queenRejectedDetected: false,
      recommendation:
          'Colony is queenright and healthy. Continue routine monitoring.',
      isAlert: false,
      alertSeverity: 'Info',
      alertLabel: 'Queen Present',
      alertMessage: 'Queen is active and laying normally.',
      alertTime: '1 hour ago',
      detectedBy: 'AI Multi-Sensor Acoustic Model',
      alertRecommendation: 'Continue standard weekly inspections.',
    ),
    HiveData(
      id: 'hive_2',
      name: 'Hive 2',
      deviceId: 'BW-002-BETA',
      notes: 'East apiary corner',
      conditionLabel: 'Queen Accepted',
      confidence: 88,
      healthScore: 88,
      temperature: '34.8',
      humidity: '62',
      acoustic: '240 Hz',
      acousticStatus: 'Normal',
      wifiStatus: 'Connected',
      batteryLevel: '85%',
      updated: '2 mins ago',
      signalBars: 4,
      explanation:
          'Acoustic frequencies (240 Hz) and worker hum indicate that the newly introduced queen was successfully accepted.',
      queenPresentDetected: false,
      queenAbsentDetected: false,
      queenAcceptedDetected: true,
      queenRejectedDetected: false,
      recommendation:
          'Queen accepted. Avoid disturbing brood box for 5 days while egg laying stabilizes.',
      isAlert: false,
      alertSeverity: 'Info',
      alertLabel: 'Queen Accepted',
      alertMessage: 'Colony has successfully accepted the introduced queen.',
      alertTime: '12 mins ago',
      detectedBy: 'AI Acoustic Classifier',
      alertRecommendation:
          'Check for newly laid eggs in 5 days.',
    ),
    HiveData(
      id: 'hive_3',
      name: 'Hive 3',
      deviceId: 'BW-003-GAMMA',
      notes: 'Main breeding colony',
      conditionLabel: 'Queen Absent',
      confidence: 58,
      healthScore: 45,
      temperature: '32.1',
      humidity: '55',
      acoustic: '380 Hz',
      acousticStatus: 'Abnormal',
      wifiStatus: 'Connected',
      batteryLevel: '78%',
      updated: '1 min ago',
      signalBars: 3,
      explanation:
          'Acoustic signature shows characteristic queenless roar (380 Hz) and absence of queen piping signals.',
      queenPresentDetected: false,
      queenAbsentDetected: true,
      queenAcceptedDetected: false,
      queenRejectedDetected: false,
      recommendation:
          'Inspect frames for emergency queen cells or introduce a new mated queen promptly.',
      isAlert: true,
      alertSeverity: 'Critical',
      alertLabel: 'Queen Absent',
      alertMessage: 'Acoustic signals indicate that the hive is Queenless.',
      alertTime: '2 mins ago',
      detectedBy: 'AI Acoustic Model',
      alertRecommendation:
          'Inspect frames for emergency queen cells or introduce a new queen.',
    ),
    HiveData(
      id: 'hive_4',
      name: 'Hive 4',
      deviceId: 'BW-004-DELTA',
      notes: 'New split colony',
      conditionLabel: 'Queen Rejected',
      confidence: 41,
      healthScore: 35,
      temperature: '37.5',
      humidity: '58',
      acoustic: '420 Hz',
      acousticStatus: 'High Distress',
      wifiStatus: 'Connected',
      batteryLevel: '92%',
      updated: '30 mins ago',
      signalBars: 4,
      explanation:
          'High agitation buzzing and localized thermal spikes suggest workers are rejecting or balling the queen.',
      queenPresentDetected: false,
      queenAbsentDetected: false,
      queenAcceptedDetected: false,
      queenRejectedDetected: true,
      recommendation:
          'Inspect the release cage immediately, check for worker aggression, and consider slow-release method.',
      isAlert: true,
      alertSeverity: 'Warning',
      alertLabel: 'Queen Rejected',
      alertMessage: 'Colony is rejecting the introduced queen.',
      alertTime: '30 mins ago',
      detectedBy: 'AI Acoustic & Thermal Analysis',
      alertRecommendation:
          'Check release cage and release method to prevent queen injury.',
    ),
  ];
}
