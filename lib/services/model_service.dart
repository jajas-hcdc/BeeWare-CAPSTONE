// lib/services/model_service.dart
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();

  factory ModelService() {
    return _instance;
  }

  ModelService._internal();

  late Interpreter _interpreter;
  final List<String> _labels = [
    'Queen Present',
    'Queen Absent',
    'Queen Accepted',
    'Queen Rejected'
  ];

  bool _isInitialized = false;

  /// Initialize TFLite model
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('beeware_model.tflite');
      _isInitialized = true;
      print('✅ Model loaded successfully');
    } catch (e) {
      print('❌ Error loading model: $e');
      rethrow;
    }
  }

  bool get isInitialized => _isInitialized;

  /// Extract MFCC features from audio file
  /// Mimics Python pipeline: 40 MFCC + delta + delta-delta = 120 dimensions
  /// Padded/truncated to 130 time steps
  Future<List<List<List<double>>>> extractMFCC(String audioPath) async {
    try {
      // This is still a placeholder until native MFCC extraction is implemented.
      return _generatePlaceholderMFCC();
    } catch (e) {
      print('Error extracting MFCC: $e');
      rethrow;
    }
  }

  /// Generate placeholder MFCC (120x130) - replace with actual extraction
  List<List<List<double>>> _generatePlaceholderMFCC() {
    List<List<List<double>>> mfcc = [];
    for (int i = 0; i < 120; i++) {
      List<List<double>> timeSteps = [];
      for (int j = 0; j < 130; j++) {
        timeSteps.add([Random().nextDouble()]);
      }
      mfcc.add(timeSteps);
    }
    return mfcc;
  }

  /// Run inference on MFCC features
  Future<Map<String, dynamic>> predict(
      List<List<List<double>>> mfccFeatures) async {
    try {
      if (!_isInitialized) {
        throw Exception('Model not initialized');
      }

      final input = List.generate(
        1,
        (_) => List.generate(
          120,
          (i) => List.generate(
            130,
            (j) => [mfccFeatures[i][j][0]],
          ),
        ),
      );

      final output = List.generate(1, (_) => List.filled(4, 0.0));
      _interpreter.run(input, output);

      final scores = List<double>.from(output[0]);
      final softmaxOutput = _softmax(scores);
      final predictedClass = softmaxOutput.indexWhere(
        (score) => score == softmaxOutput.reduce(max),
      );

      return {
        'prediction': _labels[predictedClass],
        'confidence': softmaxOutput[predictedClass],
        'scores': {
          for (var i = 0; i < _labels.length; i++) _labels[i]: softmaxOutput[i],
        },
        'allPredictions': [
          for (var i = 0; i < _labels.length; i++)
            {'label': _labels[i], 'confidence': softmaxOutput[i]},
        ],
      };
    } catch (e) {
      print('Error running inference: $e');
      rethrow;
    }
  }

  /// Softmax activation
  List<double> _softmax(List<double> logits) {
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
