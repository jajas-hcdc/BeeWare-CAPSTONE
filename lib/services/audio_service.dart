import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_recording_model.dart';
import 'notification_service.dart';

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

  /// Fetches up to 5 stored recordings for a given deviceId from Firebase Cloud RTDB
  Future<List<AudioRecordingModel>> fetchRecordingsForDevice(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return [];

    try {
      final uri = Uri.parse('$_firebaseRtdbUrl/audio_history/$cleanId.json');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body != 'null') {
        final data = jsonDecode(resp.body);
        final List<AudioRecordingModel> list = [];

        if (data is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          final now = DateTime.now().millisecondsSinceEpoch;

          final entries = <Map<String, dynamic>>[];
          int maxUptimeMillis = 0;

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
              if (rawCreated < 1700000000000 && rawCreated > maxUptimeMillis) {
                maxUptimeMillis = rawCreated;
              }
              entries.add(map);
            }
          });

          for (final entry in entries) {
            final slotKey = entry['_slotKey'] as String;
            final rawCreated = entry['_rawCreatedAt'] as int;

            int realEpoch;
            if (rawCreated > 1700000000000) {
              realEpoch = rawCreated;
            } else if (rawCreated > 1700000000) {
              realEpoch = rawCreated * 1000;
            } else {
              // Persist arrival timestamp in app so it stays anchored to the clock
              final cacheKey = 'beeware_clip_arrival_${cleanId}_${slotKey}_$rawCreated';
              final savedEpoch = prefs.getInt(cacheKey);

              if (savedEpoch != null && savedEpoch > 1700000000000) {
                realEpoch = savedEpoch;
              } else {
                final deltaMs = maxUptimeMillis > rawCreated ? (maxUptimeMillis - rawCreated) : 0;
                realEpoch = now - deltaMs;
                await prefs.setInt(cacheKey, realEpoch);
              }
            }

            entry['createdAt'] = realEpoch;
            entry['created_at'] = realEpoch;

            final model = AudioRecordingModel.fromMap(slotKey, entry);
            list.add(model);
          }
        }

        // Sort descending: newest recording first
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final trimmed = list.take(5).toList();
        _recordingsCache[cleanId] = trimmed;

        try {
          final prefs = await SharedPreferences.getInstance();
          final encoded = jsonEncode(trimmed.map((m) => m.toMap()).toList());
          await prefs.setString('beeware_cached_audio_$cleanId', encoded);
        } catch (_) {}

        notifyListeners();
        return trimmed;
      }
    } catch (e) {
      debugPrint('Fetch audio recordings from Firebase RTDB error: $e');
    }

    return _recordingsCache[cleanId] ?? [];
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

    NotificationService().showAudioRecordedNotification(
      deviceId: cleanId,
      recordedTime: timeStr,
      trigger: trigger,
      frequency: frequency,
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
        debugPrint('No valid audio file available for playback');
        return;
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
