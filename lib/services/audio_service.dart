// lib/services/audio_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/audio_recording_model.dart';

class AudioService extends ChangeNotifier {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal() {
    _initPlayer();
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
        sampleRate: 16000,
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
          data.forEach((slotKey, slotData) {
            if (slotData is Map) {
              final model = AudioRecordingModel.fromMap(
                slotKey,
                Map<String, dynamic>.from(slotData),
              );
              list.add(model);
            }
          });
        }

        // Sort descending: newest recording first (by epoch timestamp or slot index)
        list.sort((a, b) {
          if (b.createdAt > 1700000000000 && a.createdAt > 1700000000000) {
            return b.createdAt.compareTo(a.createdAt);
          }
          final cmp = b.createdAt.compareTo(a.createdAt);
          if (cmp != 0) return cmp;
          return b.slot.compareTo(a.slot);
        });

        final trimmed = list.take(5).toList();
        _recordingsCache[cleanId] = trimmed;
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

      // If we only have Base64, write to a temporary WAV file in documents dir
      if (filePath == null || !File(filePath).existsSync()) {
        if (clip.audioBase64 != null && clip.audioBase64!.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();
          final cleanBase64 = clip.audioBase64!.trim().replaceAll('\n', '').replaceAll('\r', '');
          var bytes = base64Decode(cleanBase64);

          // If bytes do not start with 'RIFF', prepend standard 44-byte WAV header
          if (bytes.length >= 4 &&
              !(bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46)) {
            bytes = _addWavHeader(bytes, 16000, 1, 16);
          }

          final file = File('${tempDir.path}/hive_clip_${clip.deviceId}_${clip.id}.wav');
          await file.writeAsBytes(bytes, flush: true);
          filePath = file.path;
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
