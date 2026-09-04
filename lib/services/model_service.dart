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

  bool _isInitialized = false;

  /// Initialize TFLite model
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/beeware_model.tflite');
      _isInitialized = true;
      print('✅ Model loaded successfully from assets/beeware_model.tflite');
    } catch (e) {
      try {
        _interpreter = await Interpreter.fromAsset('beeware_model.tflite');
        _isInitialized = true;
        print('✅ Model loaded successfully from beeware_model.tflite');
      } catch (e2) {
        print('❌ Error loading model: $e2');
        rethrow;
      }
    }
  }

  bool get isInitialized => _isInitialized;

  /// Extract MFCC features from audio file
  /// Mimics Python pipeline: updated to 128x128 dimensions for the new model
  Future<List<List<List<double>>>> extractMFCC(String audioPath) async {
    try {
      // This is still a placeholder until native MFCC extraction is implemented.
      return _generatePlaceholderMFCC();
    } catch (e) {
      print('Error extracting MFCC: $e');
      rethrow;
    }
  }

  /// Generate placeholder MFCC (128x128) - replace with actual extraction
  List<List<List<double>>> _generatePlaceholderMFCC() {
    List<List<List<double>>> mfcc = [];
    for (int i = 0; i < 128; i++) {
      List<List<double>> timeSteps = [];
      for (int j = 0; j < 128; j++) {
        timeSteps.add([Random().nextDouble()]);
      }
      mfcc.add(timeSteps);
    }
    return mfcc;
  }

  /// Run inference on MFCC features using the dual output heads
  Future<Map<String, dynamic>> predict(
      List<List<List<double>>> mfccFeatures) async {
    try {
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

      // Parse presence output (2 classes)
      final presenceScores = List<double>.from(outputPresence[0]);
      final presenceSoftmax = _softmax(presenceScores);
      final predictedPresenceClass = presenceSoftmax.indexWhere(
        (score) => score == presenceSoftmax.reduce(max),
      );

      // Parse status output (4 classes)
      final statusScores = List<double>.from(outputStatus[0]);
      final statusSoftmax = _softmax(statusScores);
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

