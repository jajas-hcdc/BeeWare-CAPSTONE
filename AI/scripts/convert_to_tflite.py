"""
Convert Keras model to TensorFlow Lite format
"""
import os
import tensorflow as tf
import numpy as np

MODEL_PATH = os.path.join("..", "models", "beeware_model_fast.keras")
TFLITE_PATH = os.path.join("..", "models", "beeware_model.tflite")

print("="*80)
print("CONVERTING KERAS MODEL TO TFLITE")
print("="*80)

# Load the trained Keras model
print(f"\n📖 Loading model: {MODEL_PATH}")
model = tf.keras.models.load_model(MODEL_PATH)
print("✅ Model loaded")

# Convert to TFLite
print(f"\n🔄 Converting to TFLite...")
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# Enable quantization for smaller model size
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()

# Save TFLite model
print(f"\n💾 Saving to {TFLITE_PATH}...")
with open(TFLITE_PATH, "wb") as f:
    f.write(tflite_model)

# Get file size
file_size_mb = os.path.getsize(TFLITE_PATH) / (1024 * 1024)
print(f"✅ TFLite model saved ({file_size_mb:.2f} MB)")

# Also create labels file
LABELS_PATH = os.path.join("..", "models", "labels.txt")
labels = ["Queen Present", "Queen Absent", "Queen Accepted", "Queen Rejected"]
with open(LABELS_PATH, "w") as f:
    for label in labels:
        f.write(f"{label}\n")
print(f"✅ Labels saved to {LABELS_PATH}")

print("\n" + "="*80)
print("TFLITE CONVERSION COMPLETE")
print("="*80)
print(f"Model Details:")
print(f"  Input shape: (1, 120, 130, 1)")
print(f"  Output shape: (1, 4)")
print(f"  Classes: 4 (Queen Present, Absent, Accepted, Rejected)")
print(f"  File size: {file_size_mb:.2f} MB")
print("="*80 + "\n")
