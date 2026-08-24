# Flutter Integration Guide - TFLite Model

## Model Ready for Deployment ✅

**File:** `beeware_model.tflite` (7.83 MB)
**Format:** TensorFlow Lite (mobile-optimized)
**Input:** MFCC audio features (40, 130, 1)
**Output:** 4 class probabilities

### Class Labels
```
0: Queen Absent
1: Queen Accepted  
2: Queen Present
3: Queen Rejected
```

---

## Integration Steps

### 1. Copy Model to Flutter Assets
```bash
# Copy the TFLite model to your Flutter project
cp c:\Users\PC\Beeware1\AI\models\beeware_model.tflite <flutter_project>/assets/
```

### 2. Update pubspec.yaml
```yaml
flutter:
  assets:
    - assets/beeware_model.tflite
    - assets/labels.txt  # Optional: for reference
    
dependencies:
  tflite_flutter: ^0.9.0  # Or latest version
  audio_session: ^0.1.0   # For microphone access
  flutter_sound: ^9.0.0   # For audio recording
```

### 3. Flutter Code Example

```dart
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class BeeClassifier {
  late Interpreter interpreter;
  List<String> labels = ['Queen Absent', 'Queen Accepted', 'Queen Present', 'Queen Rejected'];

  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset('beeware_model.tflite');
    print('Model loaded successfully');
  }

  Future<Map<String, dynamic>> classifyAudio(List<List<List<double>>> mfccFeatures) async {
    // Input shape: [1, 40, 130, 1]
    List<List<List<List<double>>>> input = [mfccFeatures];
    List<List<double>> output = [List(4).cast<double>()];
    
    interpreter.run(input, output);
    
    List<double> predictions = output[0];
    int classIndex = predictions.indexWhere((p) => p == predictions.reduce((a, b) => a > b ? a : b));
    double confidence = predictions[classIndex];
    
    return {
      'label': labels[classIndex],
      'confidence': confidence,
      'scores': {
        'Queen Absent': predictions[0],
        'Queen Accepted': predictions[1],
        'Queen Present': predictions[2],
        'Queen Rejected': predictions[3],
      }
    };
  }

  void dispose() {
    interpreter.close();
  }
}
```

### 4. Audio Processing (MFCC Extraction)

Use the `librosa` equivalent in Flutter:
- **Package:** `audio_features_extractor` or similar
- **Settings:** n_mfcc=40, n_fft=2048, hop_length=512 (match training)
- **Padding:** Ensure features are padded/truncated to (40, 130)

### 5. Real-World Testing Workflow

1. **Record audio** from bee hive with Flutter app
2. **Extract MFCC features** on device or send to backend
3. **Run inference** using the TFLite model
4. **Log results** with metadata (location, timestamp, hive_id, temperature, humidity)
5. **Collect feedback** to improve data quality for future retraining

---

## Model Performance (Current)

| Metric | Value |
|--------|-------|
| Overall Accuracy (Random Test) | 46-58% |
| Best Class (Queen Rejected) | 88-100% recall |
| Worst Classes (Queen Absent/Accepted) | ~0-10% recall |
| Test Set Size | 1,275 recordings |
| Training Epochs | 20 |

**Note:** Severe class imbalance (Queen Rejected 53.3% vs Queen Absent 12.4%) causes bias. Real-world validation essential before production deployment.

---

## Known Issues & Next Steps

### Current Limitations
- ⚠️ **Class imbalance bias**: Model predicts "Queen Rejected" too often
- ⚠️ **Low minority class accuracy**: Queen Absent/Accepted/Present need improvement
- ⚠️ **Training data might have labeling errors**: Needs real-world validation

### Improvement Plan (Post-Deployment)
1. Collect real bee hive audio recordings from Flutter app
2. Manually verify labels on subset of new data
3. Identify data quality issues in original training set
4. Retrain with balanced data and/or Focal Loss if needed
5. Deploy improved model v2

---

## Quick Reference

**Model Input:**
- Shape: (1, 40, 130, 1) — batch, MFCC coefficients, time steps, channels
- Type: Float32
- Normalization: Standardized (mean=0, std=1) during training

**Model Output:**
- Shape: (1, 4) — batch, 4 classes
- Type: Float32 (softmax probabilities)
- Interpretation: Argmax for predicted class, value for confidence

**Inference Speed:** ~50-100ms on modern mobile device (CPU)

---

## Flutter Screens to Update

### In `hive_detail_screen.dart` or similar:
- Add "Predict Queen Status" button
- Record 5-10 second audio clip from hive
- Extract MFCC features
- Run model inference
- Display results: predicted class, confidence, all 4 class scores
- Save prediction with timestamp to local DB

### In `alerts_screen.dart`:
- Show predictions if confidence < 70% (uncertain)
- Flag for manual review if Queen Absent/Accepted (rare/important)
- Alert if multiple consecutive Queen Rejected predictions (unhealthy hive)

---

## Resources

- [TFLite Flutter Plugin](https://pub.dev/packages/tflite_flutter)
- [MFCC Feature Extraction](https://librosa.org/doc/main/generated/librosa.feature.mfcc.html)
- [TensorFlow Lite Guide](https://www.tensorflow.org/lite/guide)
