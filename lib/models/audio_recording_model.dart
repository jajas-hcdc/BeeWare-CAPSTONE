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

    final temp = (data['temperature'] as num?)?.toDouble() ?? 34.0;
    final hum = (data['humidity'] as num?)?.toDouble() ?? 60.0;
    final slot = (data['slot'] as num?)?.toInt() ?? 0;
    final createdAt = (data['created_at'] as num?)?.toInt() ??
        (data['createdAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

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
      audioBase64: data['audioBase64'] ?? data['audio_base64'],
      audioUrl: data['audioUrl'] ?? data['audio_url'],
      localFilePath: data['localFilePath'],
    );
  }

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
      audioBase64: audioBase64 ?? this.audioBase64,
      audioUrl: audioUrl ?? this.audioUrl,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }
}
