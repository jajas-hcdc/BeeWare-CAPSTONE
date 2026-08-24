# Flutter Integration Guide - Bee Queen Detection

## Overview

This guide explains how to integrate the trained TensorFlow Lite model into your Flutter app.

```
User records bee sound (5 seconds)
        ↓
AudioService → Records WAV at 22050 Hz
        ↓
ModelService → Extracts MFCC features (120×130)
        ↓
TFLite Inference → Loads beeware_model.tflite
        ↓
Predicts: Queen Present/Absent/Accepted/Rejected
        ↓
Shows confidence score & all class probabilities
        ↓
FirebaseService → Saves prediction + metadata
        ↓
Display results in UI
```

## Step 1: Copy Model Files

Copy the TFLite model to your Flutter project:

```bash
# From: C:\Users\PC\Beeware1\AI\models\
# Copy to: flutter_app/assets/

cp beeware_model.tflite flutter_app/assets/
cp labels.txt flutter_app/assets/
```

## Step 2: Update pubspec.yaml

Add these dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  tflite_flutter: ^0.10.1
  tflite_flutter_helper: ^0.3.1
  record: ^4.4.4
  flutter_sound: ^9.11.8
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0
  firebase_auth: ^4.10.0
  geolocator: ^9.0.2
  path_provider: ^2.1.1
  provider: ^6.0.0
  cupertino_icons: ^1.0.2

# Asset declarations
flutter:
  assets:
    - assets/beeware_model.tflite
    - assets/labels.txt
```

## Step 3: Set Permissions

### Android (android/app/AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS (ios/Runner/Info.plist)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to record bee sounds</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need location to track hive locations</string>
```

## Step 4: Copy Service Files

Copy to your Flutter project:

```
lib/services/
  ├── audio_service.dart
  ├── model_service.dart
  ├── firebase_service.dart

lib/screens/
  └── prediction_screen.dart
```

## Step 5: Update main.dart

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/screens/prediction_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bee Queen Detection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PredictionScreen(),
    );
  }
}
```

## Step 6: Model Information

**Model Details:**
- File: `beeware_model.tflite`
- Size: 0.31 MB (very small for mobile)
- Input Shape: (1, 120, 130, 1)
  - 1: Batch size
  - 120: MFCC features (40 MFCC + delta + delta-delta)
  - 130: Time steps (padded/truncated from ~4.4 seconds audio)
  - 1: Channel (mono audio)
- Output Shape: (1, 4)
  - 4 classes: Queen Present, Queen Absent, Queen Accepted, Queen Rejected

**Performance Metrics (from held-out test set):**
- Overall Accuracy: 67.39%
- Queen Rejected: 82.22% F1-score ⭐
- Queen Accepted: 59.13% F1-score
- Queen Present: 64.00% F1-score
- Queen Absent: 0% F1-score (needs improvement)

## Step 7: MFCC Feature Extraction

**Important Note:** The `ModelService.extractMFCC()` method currently uses a placeholder. For production, you need to implement actual MFCC extraction.

### Options:

**Option A: Use Native FFI (Recommended)**
- Call native C++ librosa binding
- Fastest for mobile
- Requires build setup

**Option B: Use Speech Feature Package**
```dart
// Add to pubspec.yaml
dependencies:
  speech_feature: ^0.1.0
  
// Then use in model_service.dart
final mfcc = computeMfcc(
  audio: audioSamples,
  sampleRate: 22050,
  numMfcc: 40,
  numFft: 512,
  numMels: 128,
);
```

**Option C: Send to Backend**
```dart
// Extract on Python backend, return MFCC
Future<List<List<List<double>>>> getMFCCFromBackend(String audioPath) async {
  var request = http.MultipartRequest('POST', 
    Uri.parse('https://your-backend.com/extract-mfcc'));
  request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
  var response = await request.send();
  // Parse and return MFCC
}
```

## Step 8: Firebase Setup

1. Create Firebase project
2. Enable Cloud Firestore
3. Add collection: `predictions`
4. Set security rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /predictions/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## Step 9: Run the App

```bash
flutter pub get
flutter run
```

## Expected Workflow

1. **Record Audio**: User taps "Record Audio (5s)"
2. **Extract Features**: App records 5 seconds of bee sound
3. **Run Inference**: Model processes MFCC features
4. **Display Results**:
   ```
   Prediction Result
   Queen Rejected
   Confidence: 82.45%
   
   Confidence Scores:
   Queen Present:  14.23%
   Queen Absent:    2.15%
   Queen Accepted:  1.17%
   Queen Rejected:  82.45%
   ```
5. **Save to Firebase**: Prediction stored with timestamp and location

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Model not loading | Ensure `beeware_model.tflite` is in `assets/` and declared in `pubspec.yaml` |
| Microphone permission denied | Check permissions in AndroidManifest.xml and Info.plist |
| MFCC extraction fails | Implement actual feature extraction (see Step 7) |
| TFLite crashes | Update to latest `tflite_flutter` version |
| Firebase connection fails | Check internet connectivity and Firebase config |

## Next Steps

1. ✅ Test on physical device
2. ✅ Optimize MFCC extraction for mobile
3. ✅ Add batch recording/analysis features
4. ✅ Create analytics dashboard with Firebase data
5. ✅ Fine-tune model on production data

## Performance Notes

- Model inference: ~100-200ms on mobile CPU
- MFCC extraction: ~500ms-1s (CPU-bound, implement native for faster)
- Firebase save: ~1-2s (network dependent)
- Total time per prediction: ~2-3 seconds

---

**Model Version:** 1.0
**Created:** 2026-07-27
**Accuracy:** 67.39% (held-out test set)
