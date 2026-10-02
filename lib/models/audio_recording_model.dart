// lib/models/audio_recording_model.dart

class AudioRecordingModel {
  final String id;
  final String deviceId;
  final int slot;
  final int frequency;
  final String condition;
  final double temperature;
  final double humidity;
  final String timestamp;
  final int createdAt;
  final String? trigger;
  final String? recordedTime;
  final String? recordedDate;
  final String? audioBase64;
  final String? audioUrl;
  final String? localFilePath;

  const AudioRecordingModel({
    required this.id,
    required this.deviceId,
    required this.slot,
    required this.frequency,
    required this.condition,
    required this.temperature,
    required this.humidity,
    required this.timestamp,
    required this.createdAt,
    this.trigger,
    this.recordedTime,
    this.recordedDate,
    this.audioBase64,
    this.audioUrl,
    this.localFilePath,
  });

  factory AudioRecordingModel.fromMap(String id, Map<String, dynamic> data) {
    final freq = (data['frequency'] ?? data['frequency_hz'] ?? data['frequencyHz'] ?? 0);
    int parsedFreq = 0;
    if (freq is num) {
      parsedFreq = freq.toInt();
    } else if (freq is String) {
      parsedFreq = int.tryParse(freq.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }

    double parseNumToDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    int parseNumToInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    final temp = parseNumToDouble(data['temperature'], 34.0);
    final hum = parseNumToDouble(data['humidity'], 60.0);
    final slot = parseNumToInt(data['slot'], 0);
    final createdAt = parseNumToInt(
      data['created_at'] ?? data['createdAt'],
      DateTime.now().millisecondsSinceEpoch,
    );

    final trigger = (data['trigger'] ??
            data['triggerType'] ??
            data['event'] ??
            (slot == 0 ? 'Device Restart' : 'Cooldown Cycle'))
        .toString();

    String? recTime = (data['recorded_time'] ?? data['recordedTime'] ?? data['time'])?.toString();
    String? recDate = (data['recorded_date'] ?? data['recordedDate'] ?? data['date'])?.toString();

    if ((recTime == null || recTime == 'Just now') && createdAt > 1700000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      final sec = dt.second.toString().padLeft(2, '0');
      recTime = '$hour:$min:$sec $period';

      if (recDate == null || recDate.isEmpty) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        recDate = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      }
    }

    return AudioRecordingModel(
      id: id,
      deviceId: (data['device_id'] ?? data['deviceId'] ?? 'BW-001').toString(),
      slot: slot,
      frequency: parsedFreq,
      condition: (data['condition'] ?? data['conditionLabel'] ?? (parsedFreq > 0 ? 'Queen Present' : 'No Buzz Detected')).toString(),
      temperature: temp,
      humidity: hum,
      timestamp: (data['timestamp'] ?? 'Just now').toString(),
      createdAt: createdAt,
      trigger: trigger,
      recordedTime: recTime,
      recordedDate: recDate,
      audioBase64: data['audioBase64'] ?? data['audio_base64'],
      audioUrl: data['audioUrl'] ?? data['audio_url'],
      localFilePath: data['localFilePath'],
    );
  }

  /// Returns user-friendly clock time of the recording, e.g. "12:05:32 AM" or "10:15 AM"
  String get formattedRecordedTime {
    if (recordedTime != null && recordedTime!.isNotEmpty && recordedTime != 'Just now') {
      return recordedTime!;
    }
    if (createdAt > 1700000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      final sec = dt.second.toString().padLeft(2, '0');
      return '$hour:$min:$sec $period';
    }
    return timestamp;
  }

  /// Returns formatted calendar date, e.g. "Oct 03, 2026"
  String get formattedRecordedDate {
    if (recordedDate != null && recordedDate!.isNotEmpty) {
      return recordedDate!;
    }
    if (createdAt > 1700000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    return '';
  }

  /// Label for the trigger source (e.g. "Device Restart" vs "Cooldown Cycle")
  String get triggerLabel {
    if (trigger != null && trigger!.isNotEmpty) {
      return trigger!;
    }
    return slot == 0 ? 'Device Restart' : 'Cooldown Cycle';
  }

  /// Whether this clip was captured on boot / restart
  bool get isRestartEvent =>
      triggerLabel.toLowerCase().contains('restart') ||
      triggerLabel.toLowerCase().contains('boot');

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'slot': slot,
      'frequency': frequency,
      'condition': condition,
      'temperature': temperature,
      'humidity': humidity,
      'timestamp': timestamp,
      'created_at': createdAt,
      if (trigger != null) 'trigger': trigger,
      if (recordedTime != null) 'recorded_time': recordedTime,
      if (recordedDate != null) 'recorded_date': recordedDate,
      if (audioBase64 != null) 'audioBase64': audioBase64,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (localFilePath != null) 'localFilePath': localFilePath,
    };
  }

  AudioRecordingModel copyWith({
    String? id,
    String? deviceId,
    int? slot,
    int? frequency,
    String? condition,
    double? temperature,
    double? humidity,
    String? timestamp,
    int? createdAt,
    String? trigger,
    String? recordedTime,
    String? recordedDate,
    String? audioBase64,
    String? audioUrl,
    String? localFilePath,
  }) {
    return AudioRecordingModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      slot: slot ?? this.slot,
      frequency: frequency ?? this.frequency,
      condition: condition ?? this.condition,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      trigger: trigger ?? this.trigger,
      recordedTime: recordedTime ?? this.recordedTime,
      recordedDate: recordedDate ?? this.recordedDate,
      audioBase64: audioBase64 ?? this.audioBase64,
      audioUrl: audioUrl ?? this.audioUrl,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }
}
