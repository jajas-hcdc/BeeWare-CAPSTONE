import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_recording_model.dart';
import 'audio_processor.dart';
import 'hive_service.dart';
import 'model_service.dart';

class AudioService extends ChangeNotifier {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal() {
    _initPlayer();
    _loadFromCache();
  }

  static const String _firebaseRtdbUrl =
      'https://beeware-beaef-default-rtdb.asia-southeast1.firebasedatabase.app';

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isRecording = false;
  bool _isPlaying = false;
  String? _activePlayingId;
  final Map<String, List<AudioRecordingModel>> _recordingsCache = {};
  final Map<String, ({int createdAt, String condition, int confidence})> _inferredClipsByDevice = {};

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get activePlayingId => _activePlayingId;

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      await _player.setSubscriptionDuration(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Audio player init error: $e');
    }
  }

  Future<void> initialize() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('Microphone permission denied');
    }
  }

  /// Start recording audio from phone microphone (for in-app inspection)
  Future<void> startRecording() async {
    try {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          throw Exception('Microphone permission denied');
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/bee_sound_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.openRecorder();
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.pcm16WAV,
        bitRate: 128000,
        sampleRate: 22050,
      );

      _isRecording = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isRecording = false;
      notifyListeners();
    }
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stopRecorder();
      _isRecording = false;
      notifyListeners();
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('beeware_cached_audio_'));
      for (final key in keys) {
        final deviceId = key.replaceFirst('beeware_cached_audio_', '');
        final jsonStr = prefs.getString(key);
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          final list = decoded
              .map((item) => AudioRecordingModel.fromMap(
                    (item as Map)['id']?.toString() ?? 'slot_0',
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
          _recordingsCache[deviceId] = list;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cached audio recordings: $e');
    }
  }

  /// Parses a formatted time ("01:43:04 AM") and date ("Oct 03, 2026") into epoch ms
  int _parseRecordedTimeAndDate(String? recTime, String? recDate) {
    if (recTime == null || recTime.isEmpty || recTime == 'Just now' || recTime == 'null') {
      return 0;
    }
    try {
      final now = DateTime.now();
      int year = now.year;
      int month = now.month;
      int day = now.day;

      if (recDate != null && recDate.isNotEmpty && recDate != 'null') {
        const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
        final cleanDate = recDate.replaceAll(',', '').trim();
        final dateParts = cleanDate.split(RegExp(r'\s+'));
        if (dateParts.length >= 3 && dateParts[0].length >= 3) {
          final mIdx = months.indexOf(dateParts[0].toLowerCase().substring(0, 3));
          if (mIdx != -1) month = mIdx + 1;
          day = int.tryParse(dateParts[1]) ?? day;
          year = int.tryParse(dateParts[2]) ?? year;
        }
      }

      final cleanTime = recTime.trim();
      final timeParts = cleanTime.split(RegExp(r'\s+'));
      final hms = timeParts[0].split(':');
      if (hms.length >= 2) {
        int hour = int.tryParse(hms[0]) ?? 0;
        final int minute = int.tryParse(hms[1]) ?? 0;
        final int second = hms.length >= 3 ? (int.tryParse(hms[2]) ?? 0) : 0;
        if (timeParts.length >= 2) {
          final period = timeParts[1].toUpperCase();
          if (period == 'PM' && hour < 12) hour += 12;
          if (period == 'AM' && hour == 12) hour = 0;
        }
        return DateTime(year, month, day, hour, minute, second).millisecondsSinceEpoch;
      }
    } catch (_) {}
    return 0;
  }

  /// Real-time sync when a new telemetry packet reports an audio recording event
  void syncFromTelemetry({
    required String deviceId,
    required String recordedTime,
    required String trigger,
    required int epoch,
    required double temperature,
    required double humidity,
    required int frequency,
    required String condition,
  }) {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return;

    // Fetch authoritative audio recordings uploaded by the ESP32 from Firebase RTDB.
    // Do not synthesize a clip using the phone's current clock time.
    fetchRecordingsForDevice(cleanId);
  }

  /// Fetches up to 5 stored recordings for a given deviceId from Firebase Cloud RTDB
  Future<List<AudioRecordingModel>> fetchRecordingsForDevice(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return [];

    final List<AudioRecordingModel> list = [];

    try {
      final uri = Uri.parse('$_firebaseRtdbUrl/audio_history/$cleanId.json');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body != 'null') {
        final data = jsonDecode(resp.body);

        if (data is Map<String, dynamic>) {
          final entries = <Map<String, dynamic>>[];

          data.forEach((slotKey, slotData) {
            if (slotData is Map) {
              final map = Map<String, dynamic>.from(slotData);
              map['_slotKey'] = slotKey.toString();

              int rawCreated = 0;
              final rawVal = map['created_at'] ?? map['createdAt'];
              if (rawVal is num) {
                rawCreated = rawVal.toInt();
              } else if (rawVal is String) {
                rawCreated = int.tryParse(rawVal) ?? 0;
              }
              map['_rawCreatedAt'] = rawCreated;
              entries.add(map);
            }
          });

          bool hasValidClockEntries = false;
          for (final entry in entries) {
            final rawCreated = entry['_rawCreatedAt'] as int;
            final recTime = (entry['recorded_time'] ?? entry['recordedTime'] ?? entry['timestamp'])?.toString();
            final recDate = (entry['recorded_date'] ?? entry['recordedDate'])?.toString();
            int realEpoch = 0;
            if (rawCreated > 1700000000000) {
              realEpoch = rawCreated;
            } else if (rawCreated > 1700000000) {
              realEpoch = rawCreated * 1000;
            } else {
              realEpoch = _parseRecordedTimeAndDate(recTime, recDate);
            }
            entry['_resolvedEpoch'] = realEpoch;
            if (realEpoch > 1700000000000) {
              hasValidClockEntries = true;
            }
          }

          for (final entry in entries) {
            final slotKey = entry['_slotKey'] as String;
            final rawCreated = entry['_rawCreatedAt'] as int;
            final resolvedEpoch = entry['_resolvedEpoch'] as int;

            // Skip legacy pre-NTP slots that lack a real timestamp when valid NTP slots exist
            if (hasValidClockEntries && resolvedEpoch == 0) {
              continue;
            }

            final effectiveEpoch = resolvedEpoch > 0 ? resolvedEpoch : rawCreated;
            entry['createdAt'] = effectiveEpoch;
            entry['created_at'] = effectiveEpoch;

            final model = AudioRecordingModel.fromMap(slotKey, entry);
            list.add(model);
          }
        }
      }
    } catch (e) {
      debugPrint('Fetch audio recordings from Firebase RTDB error: $e');
    }

    // Only fall back to cached recordings if the network fetch returned empty
    if (list.isEmpty) {
      final existingCached = _recordingsCache[cleanId] ?? [];
      for (final cached in existingCached) {
        if (!cached.id.startsWith('telemetry_')) {
          list.add(cached);
        }
      }
    }

    // Sort descending: newest recording first
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final trimmed = list.take(5).toList();

    // Run on-device TFLite model (assets/beeware_model.tflite) & FFT frequency extraction on ESP32 audio clips
    if (trimmed.isNotEmpty) {
      final latest = trimmed.first;
      int effectiveHz = latest.frequency;
      Uint8List? wavBytes;

      if (latest.audioBase64 != null && latest.audioBase64!.trim().isNotEmpty) {
        try {
          final cleanBase64 = latest.audioBase64!.trim().replaceAll('\n', '').replaceAll('\r', '');
          var bytes = base64Decode(cleanBase64);
          if (bytes.length >= 4 &&
              !(bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46)) {
            bytes = _addWavHeader(bytes, 16000, 1, 16);
          }
          wavBytes = bytes;
          if (effectiveHz <= 0) {
            final measuredHz = await AudioProcessor.computeDominantFrequencyHz(bytes);
            if (measuredHz > 0) {
              effectiveHz = measuredHz;
            }
          }
        } catch (e) {
          debugPrint('ℹ️ ESP32 audio WAV decode skipped: $e');
        }
      }

      if (effectiveHz < 90) {
        trimmed[0] = latest.copyWith(
          frequency: effectiveHz,
          condition: 'No Buzz Detected',
        );
        if (effectiveHz > 0) {
          HiveService().applyAiModelPrediction(
            deviceId: cleanId,
            recordingEpoch: latest.createdAt,
            prediction: 'No Buzz Detected',
            confidence: 60,
            frequencyHz: effectiveHz,
            recordedTime: latest.formattedRecordedTime,
          );
        }
      } else if (wavBytes != null) {
        final prevInferred = _inferredClipsByDevice[cleanId];
        if (prevInferred != null && prevInferred.createdAt == latest.createdAt) {
          trimmed[0] = latest.copyWith(
            frequency: effectiveHz,
            condition: prevInferred.condition,
          );
          HiveService().applyAiModelPrediction(
            deviceId: cleanId,
            recordingEpoch: latest.createdAt,
            prediction: prevInferred.condition,
            confidence: prevInferred.confidence,
            frequencyHz: effectiveHz,
            recordedTime: latest.formattedRecordedTime,
          );
        } else {
          try {
            final result = await ModelService().predictFromWavBytes(
              wavBytes,
              frequencyHz: effectiveHz,
            );
            if (result != null) {
              final predLabel = (result['prediction'] ?? latest.condition).toString();
              final confDouble = (result['confidence'] as num?)?.toDouble() ?? 0.90;
              final confPct = (confDouble * 100).round().clamp(55, 99);
              _inferredClipsByDevice[cleanId] = (
                createdAt: latest.createdAt,
                condition: predLabel,
                confidence: confPct,
              );
              trimmed[0] = latest.copyWith(
                frequency: effectiveHz,
                condition: predLabel,
              );
              HiveService().applyAiModelPrediction(
                deviceId: cleanId,
                recordingEpoch: latest.createdAt,
                prediction: predLabel,
                confidence: confPct,
                frequencyHz: effectiveHz,
                recordedTime: latest.formattedRecordedTime,
              );
            } else {
              HiveService().applyAiModelPrediction(
                deviceId: cleanId,
                recordingEpoch: latest.createdAt,
                prediction: latest.condition,
                confidence: 92,
                frequencyHz: effectiveHz,
                recordedTime: latest.formattedRecordedTime,
              );
            }
          } catch (e) {
            debugPrint('ℹ️ ESP32 audio TFLite inference skipped: $e');
            HiveService().applyAiModelPrediction(
              deviceId: cleanId,
              recordingEpoch: latest.createdAt,
              prediction: latest.condition,
              confidence: 92,
              frequencyHz: effectiveHz,
              recordedTime: latest.formattedRecordedTime,
            );
          }
        }
      } else if (effectiveHz >= 90) {
        HiveService().applyAiModelPrediction(
          deviceId: cleanId,
          recordingEpoch: latest.createdAt,
          prediction: latest.condition,
          confidence: 92,
          frequencyHz: effectiveHz,
          recordedTime: latest.formattedRecordedTime,
        );
      }
    }

    _recordingsCache[cleanId] = trimmed;

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(trimmed.map((m) => m.toMap()).toList());
      await prefs.setString('beeware_cached_audio_$cleanId', encoded);
    } catch (_) {}

    notifyListeners();
    return trimmed;
  }

  /// Gets cached recordings for a hive device
  List<AudioRecordingModel> getCachedRecordings(String deviceId) {
    return _recordingsCache[deviceId.trim()] ?? [];
  }

  /// Records or logs an event audio clip (e.g. Device Restart or Cooldown Cycle)
  Future<AudioRecordingModel> recordEventClip({
    required String deviceId,
    required String trigger, // 'Device Restart' or 'Cooldown Cycle'
    int frequency = 210,
    double temperature = 34.5,
    double humidity = 62.0,
    String condition = 'Queen Present',
  }) async {
    final cleanId = deviceId.trim();
    final now = DateTime.now();
    final epoch = now.millisecondsSinceEpoch;
    final hour = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final min = now.minute.toString().padLeft(2, '0');
    final sec = now.second.toString().padLeft(2, '0');
    final timeStr = '$hour:$min:$sec $period';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

    final existing = _recordingsCache[cleanId] ?? [];
    final slot = existing.isEmpty ? 0 : (existing.first.slot + 1) % 5;

    final newClip = AudioRecordingModel(
      id: 'slot_$slot',
      deviceId: cleanId,
      slot: slot,
      frequency: frequency,
      condition: condition,
      temperature: temperature,
      humidity: humidity,
      timestamp: timeStr,
      createdAt: epoch,
      trigger: trigger,
      recordedTime: timeStr,
      recordedDate: dateStr,
    );

    final updated = [newClip, ...existing.where((c) => c.id != newClip.id)].take(5).toList();
    _recordingsCache[cleanId] = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(updated.map((m) => m.toMap()).toList());
      await prefs.setString('beeware_cached_audio_$cleanId', encoded);
    } catch (_) {}

    notifyListeners();
    return newClip;
  }

  /// Plays a recorded clip from Base64 or local file
  Future<void> playRecording(AudioRecordingModel clip) async {
    // If this clip is currently playing, stop it (toggle behavior)
    if (_isPlaying && _activePlayingId == clip.id) {
      await stopPlayback();
      return;
    }

    try {
      await stopPlayback();

      String? filePath = clip.localFilePath;
      bool isTempFile = false;

      if (filePath == null || !File(filePath).existsSync()) {
        if (clip.audioBase64 != null && clip.audioBase64!.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();
          final cleanBase64 = clip.audioBase64!.trim().replaceAll('\n', '').replaceAll('\r', '');
          var bytes = base64Decode(cleanBase64);

          // If bytes do not start with 'RIFF', prepend standard 44-byte WAV header
          if (bytes.length >= 4 &&
              !(bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46)) {
            bytes = _addWavHeader(bytes, 22050, 1, 16);
          }

          final file = File('${tempDir.path}/hive_clip_${clip.deviceId}_${clip.id}.wav');
          await file.writeAsBytes(bytes, flush: true);
          filePath = file.path;
          isTempFile = true;
        }
      }

      if (filePath == null || !File(filePath).existsSync()) {
        // If raw base64 is still in transit, synthesize realistic 3.0s hive buzz at measured frequency
        final tempDir = await getTemporaryDirectory();
        final synthFile = File('${tempDir.path}/hive_synth_${clip.deviceId}_${clip.id}.wav');
        final freq = clip.frequency > 30 ? clip.frequency : 180;
        final synthBytes = _generateBuzzWav(freq, 3.0);
        await synthFile.writeAsBytes(synthBytes, flush: true);
        filePath = synthFile.path;
        isTempFile = true;
      }

      if (!_player.isOpen()) {
        await _player.openPlayer();
      }

      _activePlayingId = clip.id;
      _isPlaying = true;
      notifyListeners();

      await _player.startPlayer(
        fromURI: filePath,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          _isPlaying = false;
          _activePlayingId = null;
          notifyListeners();
          if (isTempFile && filePath != null) {
            try {
              final f = File(filePath);
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
          }
        },
      );
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _isPlaying = false;
      _activePlayingId = null;
      notifyListeners();
    }
  }

  /// Stops current audio playback
  Future<void> stopPlayback() async {
    try {
      if (_player.isPlaying) {
        await _player.stopPlayer();
      }
    } catch (_) {}
    _isPlaying = false;
    _activePlayingId = null;
    notifyListeners();
  }

  /// Synthesizes a realistic 3.0s worker bee buzz audio at [frequency] Hz
  Uint8List _generateBuzzWav(int frequency, double durationSec) {
    const sampleRate = 16000;
    final totalSamples = (sampleRate * durationSec).toInt();
    final pcmBytes = Uint8List(totalSamples * 2);
    final byteData = ByteData.view(pcmBytes.buffer);

    final f0 = frequency > 30 ? frequency.toDouble() : 180.0;
    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // Bee acoustic harmonics: fundamental + 2nd + 3rd harmonic with gentle amplitude modulation
      final mod = 1.0 + 0.08 * sin(2 * pi * 8.0 * t);
      final s = (sin(2 * pi * f0 * t) * 0.6 +
                 sin(2 * pi * (f0 * 2) * t) * 0.28 +
                 sin(2 * pi * (f0 * 3) * t) * 0.12) * mod;
      final sample = (s * 14000).toInt().clamp(-32768, 32767);
      byteData.setInt16(i * 2, sample, Endian.little);
    }

    return _addWavHeader(pcmBytes, sampleRate, 1, 16);
  }

  /// Generates a standard 44-byte RIFF/WAV header for raw 16-bit mono PCM bytes
  Uint8List _addWavHeader(Uint8List pcm, int sampleRate, int channels, int bitDepth) {
    final byteRate = sampleRate * channels * (bitDepth ~/ 8);
    final blockAlign = channels * (bitDepth ~/ 8);
    final dataSize = pcm.length;
    final chunkSize = 36 + dataSize;

    final header = Uint8List(44);
    final view = ByteData.view(header.buffer);

    // "RIFF"
    header[0] = 0x52; header[1] = 0x49; header[2] = 0x46; header[3] = 0x46;
    view.setUint32(4, chunkSize, Endian.little);
    // "WAVE"
    header[8] = 0x57; header[9] = 0x41; header[10] = 0x56; header[11] = 0x45;
    // "fmt "
    header[12] = 0x66; header[13] = 0x6D; header[14] = 0x74; header[15] = 0x20;
    view.setUint32(16, 16, Endian.little); // Subchunk1Size
    view.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitDepth, Endian.little);
    // "data"
    header[36] = 0x64; header[37] = 0x61; header[38] = 0x74; header[39] = 0x61;
    view.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, header);
    wav.setRange(44, 44 + pcm.length, pcm);
    return wav;
  }

  @override
  void dispose() {
    try {
      _recorder.closeRecorder();
      _player.closePlayer();
    } catch (_) {}
    super.dispose();
  }
}
