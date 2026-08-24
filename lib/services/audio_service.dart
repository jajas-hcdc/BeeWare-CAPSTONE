// lib/services/audio_service.dart
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> initialize() async {
    // Request microphone permission upfront.
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('Microphone permission denied');
    }
  }

  /// Start recording audio
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
    } catch (e) {
      print('Error starting recording: $e');
      _isRecording = false;
    }
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stopRecorder();
      _isRecording = false;
      return path;
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  /// Cleanup
  Future<void> dispose() async {
    try {
      await _recorder.closeRecorder();
    } catch (_) {}
  }
}
