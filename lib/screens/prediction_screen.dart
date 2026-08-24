// lib/screens/prediction_screen.dart
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/backend_service.dart';
import '../services/model_service.dart';
import '../services/firebase_service.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  late AudioService _audioService;
  late ModelService _modelService;
  late FirebaseService _firebaseService;
  
  String? _currentPrediction;
  double? _confidence;
  Map<String, double>? _scores;
  bool _isProcessing = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }
  
  Future<void> _initializeServices() async {
    _audioService = AudioService();
    _modelService = ModelService();
    _firebaseService = FirebaseService();
    
    await _audioService.initialize();
    
    try {
      await _modelService.initialize();
      print('✅ Services initialized');
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load model: $e';
      });
    }
  }
  
  Future<void> _recordAndPredict() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _currentPrediction = null;
      _confidence = null;
    });
    
    try {
      // Start recording
      await _audioService.startRecording();
      
      // Record for 5 seconds
      await Future.delayed(const Duration(seconds: 5));
      
      // Stop recording
      final audioPath = await _audioService.stopRecording();
      
      if (audioPath == null) {
        throw Exception('Failed to record audio');
      }
      
      // Extract MFCC features
      final features = await _modelService.extractMFCC(audioPath);
      
      // Run inference
      final result = await _modelService.predict(features);
      
      setState(() {
        _currentPrediction = result['prediction'];
        _confidence = result['confidence'];
        _scores = Map<String, double>.from(result['scores']);
        _isProcessing = false;
      });
      
      // Save to Firebase
      final saved = await _firebaseService.savePrediction(
        prediction: result['prediction'],
        confidence: result['confidence'],
        scores: result['scores'],
        audioPath: audioPath,
      );

      if (saved && result['prediction'] != 'Queen Present') {
        await BackendService().sendAlert(
          hiveId: 'mobile_prediction',
          queenStatus: result['prediction'],
          title: 'Hive Alert: ${result['prediction']}',
          message:
              'Predicted ${result['prediction']} with ${(result['confidence'] * 100).toStringAsFixed(1)}% confidence.',
          additionalData: {
            'source': 'mobile_app',
            'confidence': (result['confidence'] as double).toStringAsFixed(3),
          },
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isProcessing = false;
      });
      print('Error during prediction: $e');
    }
  }
  
  @override
  void dispose() {
    _audioService.dispose();
    _modelService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bee Queen Detection'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recording Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _recordAndPredict,
              icon: Icon(
                _audioService.isRecording ? Icons.stop : Icons.mic,
                size: 32,
              ),
              label: Text(
                _isProcessing
                    ? 'Processing...'
                    : _audioService.isRecording
                        ? 'Stop Recording'
                        : 'Record Audio (5s)',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _audioService.isRecording
                    ? Colors.red
                    : Colors.green,
              ),
            ),
            const SizedBox(height: 32),
            
            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            
            if (_errorMessage != null) const SizedBox(height: 16),
            
            // Prediction Result
            if (_currentPrediction != null)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'Prediction Result',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentPrediction!,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Confidence: ${(_confidence! * 100).toStringAsFixed(2)}%',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 32),
            
            // Confidence Scores Chart
            if (_scores != null)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confidence Scores',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._scores!.entries.map((entry) {
                        double score = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry.key),
                                  Text(
                                    '${(score * 100).toStringAsFixed(2)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: score,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 32),
            
            // Model Info
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('• Accuracy: 67.39%'),
                    const Text('• Input: MFCC Features (120×130)'),
                    const Text('• Classes: 4 Queen States'),
                    const Text('• Model Size: 0.31 MB'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
