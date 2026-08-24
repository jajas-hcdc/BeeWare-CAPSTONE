# Flutter dependencies for Bee Queen Detection

# Add these to your pubspec.yaml

dependencies:
  flutter:
    sdk: flutter
  
  # TensorFlow Lite for model inference
  tflite_flutter: ^0.10.1
  tflite_flutter_helper: ^0.3.1
  
  # Audio recording
  record: ^4.4.4
  
  # Audio playback (for feature extraction)
  flutter_sound: ^9.11.8
  
  # Firebase
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0
  firebase_auth: ^4.10.0
  
  # Location services
  geolocator: ^9.0.2
  
  # Path provider
  path_provider: ^2.1.1
  
  # State management (recommended)
  provider: ^6.0.0
  
  # UI
  cupertino_icons: ^1.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

# iOS specific
# In ios/Podfile, add:
# post_install do |installer|
#   installer.pods_project.targets.each do |target|
#     target.build_configurations.each do |config|
#       config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
#         '$(inherited)',
#         'PERMISSION_MICROPHONE=1',
#       ]
#     end
#   end
# end

# Android specific
# In android/app/build.gradle:
# android {
#   compileSdkVersion 34
#   defaultConfig {
#     minSdkVersion 24
#     targetSdkVersion 34
#   }
#   
#   packagingOptions {
#     pickFirst 'lib/x86/libc++_shared.so'
#     pickFirst 'lib/x86_64/libc++_shared.so'
#     pickFirst 'lib/armeabi-v7a/libc++_shared.so'
#     pickFirst 'lib/arm64-v8a/libc++_shared.so'
#   }
# }
