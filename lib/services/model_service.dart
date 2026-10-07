// lib/services/model_service.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'audio_processor.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();

  factory ModelService() {
    return _instance;
  }

  ModelService._internal();

  late Interpreter _interpreter;
  
  final List<String> _presenceLabels = [
    'Queen Present',
    'Queen Absent'
  ];

  final List<String> _statusLabels = [
    'Queen Absent',
    'Queen Accepted',
    'Queen Present',
    'Queen Rejected'
  ];

  // Training dataset distribution (1,275 total samples) used for inverse-prior calibration
  // to correct the 53.3% Queen Rejected class imbalance documented in AI/DEPLOYMENT_SUMMARY.md:
  //   Queen Absent:   158 / 1275 = 0.1239
  //   Queen Accepted: 259 / 1275 = 0.2031
  //   Queen Present:  179 / 1275 = 0.1404
  //   Queen Rejected: 679 / 1275 = 0.5325
  static const List<double> _trainingClassPriors = [
    158.0 / 1275.0,
    259.0 / 1275.0,
    179.0 / 1275.0,
    679.0 / 1275.0,
  ];

  bool _isInitialized = false;

  /// Initialize TFLite model
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/beeware_model.tflite');
      _isInitialized = true;
      debugPrint('✅ Model loaded successfully from assets/beeware_model.tflite');
    } catch (e) {
      try {
        _interpreter = await Interpreter.fromAsset('beeware_model.tflite');
        _isInitialized = true;
        debugPrint('✅ Model loaded successfully from beeware_model.tflite');
      } catch (e2) {
        debugPrint('❌ Error loading model: $e2');
        rethrow;
      }
    }
  }

  bool get isInitialized => _isInitialized;

  /// Extract mel-spectrogram features from a recorded WAV file.
  ///
  /// Matches the Python training pipeline exactly:
  ///   librosa.feature.melspectrogram(y, sr=22050, n_mels=128)
  ///   librosa.power_to_db(S, ref=np.max)
  ///   → shape [128 mel bands][128 time frames][1 channel]
  ///
  /// Runs in a background isolate via [AudioProcessor].
  Future<List<List<List<double>>>> extractMFCC(String audioPath) async {
    try {
      return await AudioProcessor.extractMelSpectrogram(audioPath);
    } catch (e) {
      debugPrint('Error extracting mel-spectrogram: $e');
      rethrow;
    }
  }

  /// Run TFLite inference directly on in-memory WAV bytes (e.g. from ESP32 INMP441 Base64 audio),
  /// fusing the prior-calibrated CNN probabilities with the measured dominant frequency [frequencyHz].
  Future<Map<String, dynamic>?> predictFromWavBytes(
    Uint8List wavBytes, {
    int frequencyHz = 0,
  }) async {
    if (frequencyHz < 90) {
      return {
        'prediction': 'No Buzz Detected',
        'confidence': 0.60,
      };
    }
    if (wavBytes.length <= 44) {
      return null;
    }
    try {
      if (!_isInitialized) {
        await initialize();
      }
      final features = await AudioProcessor.extractMelSpectrogramFromBytes(wavBytes);
      return await predict(features, frequencyHz: frequencyHz);
    } catch (e) {
      debugPrint('ℹ️ TFLite inference skipped/fallback to acoustic harmonics: $e');
      return null;
    }
  }

  /// Run inference on MFCC features using the dual output heads,
  /// applying inverse-prior calibration and optional acoustic frequency fusion.
  Future<Map<String, dynamic>> predict(
    List<List<List<double>>> mfccFeatures, {
    int? frequencyHz,
  }) async {
    try {
      if (frequencyHz != null && frequencyHz < 90) {
        return {
          'prediction': 'No Buzz Detected',
          'confidence': 0.60,
          'scores': {
            for (var i = 0; i < _statusLabels.length; i++) _statusLabels[i]: 0.0,
          },
          'allPredictions': [
            {'label': 'No Buzz Detected', 'confidence': 0.60},
          ],
          'presencePrediction': 'No Buzz Detected',
          'presenceConfidence': 0.60,
          'presenceScores': {
            for (var i = 0; i < _presenceLabels.length; i++) _presenceLabels[i]: 0.0,
          },
        };
      }

      if (!_isInitialized) {
        throw Exception('Model not initialized');
      }

      // Input shape expected by the model: [1, 128, 128, 1]
      final input = List.generate(
        1,
        (_) => List.generate(
          128,
          (i) => List.generate(
            128,
            (j) => [mfccFeatures[i][j][0]],
          ),
        ),
      );

      // Detect output tensor indices dynamically based on shapes
      int presenceIndex = 0;
      int statusIndex = 1;
      final outputTensors = _interpreter.getOutputTensors();
      for (int i = 0; i < outputTensors.length; i++) {
        final shape = outputTensors[i].shape;
        if (shape.contains(2)) {
          presenceIndex = i;
        } else if (shape.contains(4)) {
          statusIndex = i;
        }
      }

      // Prepare outputs matching target shape
      final outputPresence = List.generate(1, (_) => List.filled(2, 0.0));
      final outputStatus = List.generate(1, (_) => List.filled(4, 0.0));

      final outputs = {
        presenceIndex: outputPresence,
        statusIndex: outputStatus,
      };

      // Run multiple outputs inference
      _interpreter.runForMultipleInputs([input], outputs);

      // Parse presence output (2 classes: ['Queen Present', 'Queen Absent'])
      final presenceScores = List<double>.from(outputPresence[0]);
      final presenceSoftmax = _softmax(presenceScores);
      final predictedPresenceClass = presenceSoftmax.indexWhere(
        (score) => score == presenceSoftmax.reduce(max),
      );

      // Parse status output (4 classes: ['Queen Absent', 'Queen Accepted', 'Queen Present', 'Queen Rejected'])
      // Apply inverse-prior calibration to remove the 53.3% Queen Rejected training dataset bias
      final statusScores = List<double>.from(outputStatus[0]);
      final rawStatusSoftmax = _softmax(statusScores);
      final calibratedWeights = List<double>.generate(
        _statusLabels.length,
        (i) => rawStatusSoftmax[i] / _trainingClassPriors[i],
      );

      // Compute average dB energy across the dataset's Mel-spectrogram bands:
      // Bands 0-3 (0-90 Hz), Bands 4-12 (90-280 Hz), Bands 13-27 (300-600 Hz),
      // Bands 28-45 (600-1000 Hz), Bands 46-75 (1000-2500 Hz)
      double bandMeanDb(int startMel, int endMel) {
        double sum = 0.0;
        int count = 0;
        for (int m = startMel; m <= endMel && m < mfccFeatures.length; m++) {
          for (int t = 0; t < mfccFeatures[m].length; t++) {
            final v = mfccFeatures[m][t][0];
            if (v != 0.0) {
              sum += v;
              count++;
            }
          }
        }
        return count > 0 ? sum / count : -80.0;
      }

      final double dbBands0to3 = bandMeanDb(0, 3);     // 0 - 90 Hz (Low rumble / background floor)
      final double dbBands4to12 = bandMeanDb(4, 12);   // 90 - 280 Hz (Queen Present / Accepted fundamental)
      final double dbBands13to27 = bandMeanDb(13, 27); // 300 - 600 Hz (Queen Absent / Rejected distress)
      final double dbBands28to45 = bandMeanDb(28, 45); // 600 - 1000 Hz (Queen Accepted piping harmonics)
      final double dbBands46to75 = bandMeanDb(46, 75); // 1000 - 2500 Hz (Queen Rejected wing-click agitation)

      // If no explicit Hz was passed and Mel Bands 0-3 (0-90 Hz) dominate all bee bands by > 8 dB, classify as No Buzz Detected
      if (frequencyHz == null &&
          dbBands0to3 > dbBands4to12 + 8.0 &&
          dbBands0to3 > dbBands13to27 + 8.0) {
        return {
          'prediction': 'No Buzz Detected',
          'confidence': 0.60,
          'scores': {
            for (var i = 0; i < _statusLabels.length; i++) _statusLabels[i]: 0.0,
          },
          'allPredictions': [
            {'label': 'No Buzz Detected', 'confidence': 0.60},
          ],
          'presencePrediction': 'No Buzz Detected',
          'presenceConfidence': 0.60,
          'presenceScores': {
            for (var i = 0; i < _presenceLabels.length; i++) _presenceLabels[i]: 0.0,
          },
        };
      }

      // Fuse TFLite dual-head probabilities with Mel-band harmonic signatures and INMP441 Hz
      if (frequencyHz != null && frequencyHz >= 90) {
        if (frequencyHz >= 90 && frequencyHz <= 260) {
          // Mel Bands 4-12 (90-260 Hz): Queen Present vs Queen Accepted
          // If Mel Bands 28-45 (600-1000 Hz piping harmonics) are strong or frequency is 200-260 Hz with strong Accepted score:
          final bool hasPipingHarmonics = (dbBands28to45 - dbBands4to12) > -14.0;
          calibratedWeights[2] *= 2.4 * (0.5 + presenceSoftmax[0]); // Queen Present
          calibratedWeights[1] *= (hasPipingHarmonics ? 2.5 : 1.5) * (0.5 + presenceSoftmax[0]); // Queen Accepted
          calibratedWeights[0] *= 0.25; // Queen Absent
          calibratedWeights[3] *= 0.25; // Queen Rejected
        } else if (frequencyHz > 320) {
          // Mel Bands 13-27 (> 320 Hz): Queen Absent vs Queen Rejected
          // High-frequency wing-click friction in Bands 46-75 (1000-2500 Hz) distinguishes Queen Rejected balling from Queen Absent roar
          final bool hasBallingAgitation = (dbBands46to75 - dbBands13to27) > -15.0;
          calibratedWeights[0] *= 2.5 * (0.5 + presenceSoftmax[1]); // Queen Absent
          calibratedWeights[3] *= (hasBallingAgitation ? 2.6 : 1.6) * (0.5 + presenceSoftmax[1]); // Queen Rejected
          calibratedWeights[2] *= 0.25; // Queen Present
        } else {
          // Transitional band (261-320 Hz, Mel Bands 11-14): Queen Accepted piping vs Queen Rejected agitation
          calibratedWeights[1] *= 1.6 * (0.5 + presenceSoftmax[0]); // Queen Accepted
          calibratedWeights[2] *= 1.2 * (0.5 + presenceSoftmax[0]); // Queen Present
          calibratedWeights[3] *= 1.6 * (0.5 + presenceSoftmax[1]); // Queen Rejected
          calibratedWeights[0] *= 1.2 * (0.5 + presenceSoftmax[1]); // Queen Absent
        }
      }

      final double sumCalibrated = calibratedWeights.reduce((a, b) => a + b);
      final List<double> statusSoftmax = sumCalibrated > 0
          ? calibratedWeights.map((w) => w / sumCalibrated).toList()
          : rawStatusSoftmax;

      final predictedStatusClass = statusSoftmax.indexWhere(
        (score) => score == statusSoftmax.reduce(max),
      );

      return {
        // Backwards compatibility for prediction_screen.dart (status)
        'prediction': _statusLabels[predictedStatusClass],
        'confidence': statusSoftmax[predictedStatusClass],
        'scores': {
          for (var i = 0; i < _statusLabels.length; i++) _statusLabels[i]: statusSoftmax[i],
        },
        'allPredictions': [
          for (var i = 0; i < _statusLabels.length; i++)
            {'label': _statusLabels[i], 'confidence': statusSoftmax[i]},
        ],
        // New presence head predictions
        'presencePrediction': _presenceLabels[predictedPresenceClass],
        'presenceConfidence': presenceSoftmax[predictedPresenceClass],
        'presenceScores': {
          for (var i = 0; i < _presenceLabels.length; i++) _presenceLabels[i]: presenceSoftmax[i],
        },
      };
    } catch (e) {
      debugPrint('Error running inference: $e');
      rethrow;
    }
  }

  /// Softmax activation (handles both raw logits and already-normalized probabilities)
  List<double> _softmax(List<double> logits) {
    final sum = logits.fold<double>(0.0, (a, b) => a + b);
    final allNonNegative = logits.every((v) => v >= 0.0 && v <= 1.0);
    if (allNonNegative && (sum - 1.0).abs() < 1e-3) {
      return List<double>.from(logits);
    }
    final maxLogit = logits.reduce(max);
    final expValues = logits.map((logit) => exp(logit - maxLogit)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((value) => value / sumExp).toList();
  }

  /// Cleanup
  Future<void> dispose() async {
    if (_isInitialized) {
      _interpreter.close();
      _isInitialized = false;
    }
  }
}

