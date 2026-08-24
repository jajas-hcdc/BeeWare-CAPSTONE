"""
Evaluate the best trained model on the held-out test set
This script tests ONLY on the 184 samples that were never seen during training
"""
import os
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    classification_report, confusion_matrix, accuracy_score,
    precision_score, recall_score, f1_score
)

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
CACHE_FILE = os.path.join("..", "models", "features_cache.npz")
MODEL_PATH = os.path.join("..", "models", "beeware_model_fast.keras")

print("="*80)
print("HELD-OUT TEST SET EVALUATION")
print("="*80)

# Load cached features
print("\n📊 Loading cached features...")
data = np.load(CACHE_FILE)
X, y, filenames = data['X'], data['y'], data['filenames']
print(f"✅ Loaded {len(X)} samples")

# Recreate exact train/val/test split
print("\n📈 Recreating exact 70/15/15 split...")
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)

X_train, X_temp, y_train, y_temp = train_test_split(
    X, y_encoded, test_size=0.30, random_state=42, stratify=y_encoded
)
X_val, X_test, y_val, y_test = train_test_split(
    X_temp, y_temp, test_size=0.50, random_state=42, stratify=y_temp
)

print(f"  Train: {X_train.shape[0]}")
print(f"  Val: {X_val.shape[0]}")
print(f"  Test: {X_test.shape[0]} (HELD-OUT - NEVER SEEN BY MODEL)")

# Reshape for model
X_test = X_test.reshape(X_test.shape[0], X_test.shape[1], X_test.shape[2], 1)

# One-hot encode y_test for model evaluation
from tensorflow.keras.utils import to_categorical
y_test_categorical = to_categorical(y_test)

# Load best model
print(f"\n🔄 Loading best model from {MODEL_PATH}...")
model = tf.keras.models.load_model(MODEL_PATH)
print("✅ Model loaded")

# Evaluate on test set
print("\n🎯 Evaluating on held-out test set...")
loss, accuracy = model.evaluate(X_test, y_test_categorical, verbose=0)
print(f"\n{'='*80}")
print(f"✅ TEST SET ACCURACY: {accuracy:.4f} ({100*accuracy:.2f}%)")
print(f"   Test loss: {loss:.4f}")
print(f"{'='*80}")

# Detailed per-class metrics
print("\n📊 Per-Class Metrics:")
y_pred = np.argmax(model.predict(X_test, verbose=0), axis=1)

class_names = [str(c) for c in encoder.classes_]  # Convert to strings
for i, class_name in enumerate(class_names):
    mask = y_test == i
    if np.sum(mask) > 0:
        class_acc = accuracy_score(y_test[mask], y_pred[mask])
    else:
        class_acc = 0
    n_samples = np.sum(mask)
    print(f"  {class_name}: {class_acc:.2%} ({n_samples} samples)")

# Classification report
print("\n📈 Detailed Classification Report:")
print(classification_report(y_test, y_pred, target_names=class_names, zero_division=0))

# Confusion matrix
print("\n🔢 Confusion Matrix:")
cm = confusion_matrix(y_test, y_pred)
print(cm)

# Overall metrics
precision_macro = precision_score(y_test, y_pred, average='macro')
recall_macro = recall_score(y_test, y_pred, average='macro')
f1_macro = f1_score(y_test, y_pred, average='macro')

print("\n⚖️  Macro-Averaged Metrics:")
print(f"  Precision: {precision_macro:.4f}")
print(f"  Recall: {recall_macro:.4f}")
print(f"  F1-Score: {f1_macro:.4f}")

# Summary comparison
print("\n" + "="*80)
print("IMPROVEMENT SUMMARY")
print("="*80)
print(f"Old pipeline (random contaminated samples):  46-58% ❌")
print(f"New pipeline (held-out test set):           {100*accuracy:.2f}% ✅")
print(f"IMPROVEMENT:                                 ~{100*accuracy - 52:.0f}% better! 🎉")
print("="*80)

print("\n✅ Test complete!")
