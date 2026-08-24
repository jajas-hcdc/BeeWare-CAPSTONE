"""
Comprehensive Model Evaluation Report
For Thesis Documentation
"""
import os
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    classification_report, confusion_matrix, accuracy_score,
    precision_score, recall_score, f1_score,
    roc_curve, auc, roc_auc_score
)

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
CACHE_FILE = os.path.join("..", "models", "features_cache.npz")
MODEL_PATH = os.path.join("..", "models", "beeware_model_fast.keras")

print("\n" + "="*80)
print("COMPREHENSIVE MODEL EVALUATION - THESIS REPORT")
print("="*80)

# Load cached features
print("\n📊 Loading dataset and model...")
data = np.load(CACHE_FILE)
X, y, filenames = data['X'], data['y'], data['filenames']

# Recreate exact train/val/test split
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)

X_train, X_temp, y_train, y_temp = train_test_split(
    X, y_encoded, test_size=0.30, random_state=42, stratify=y_encoded
)
X_val, X_test, y_val, y_test = train_test_split(
    X_temp, y_temp, test_size=0.50, random_state=42, stratify=y_temp
)

# Reshape for model
X_test = X_test.reshape(X_test.shape[0], X_test.shape[1], X_test.shape[2], 1)

# One-hot encode for model
from tensorflow.keras.utils import to_categorical
y_test_categorical = to_categorical(y_test)

# Load model
model = tf.keras.models.load_model(MODEL_PATH)
print(f"✅ Model loaded: {MODEL_PATH}")

# Get predictions
print("\n🔮 Generating predictions...")
y_pred_prob = model.predict(X_test, verbose=0)
y_pred = np.argmax(y_pred_prob, axis=1)

# Class names
class_names = [str(c) for c in encoder.classes_]
class_labels = {
    '0': 'Queen Present',
    '1': 'Queen Absent', 
    '2': 'Queen Accepted',
    '3': 'Queen Rejected'
}

print("\n" + "="*80)
print("1. OVERALL ACCURACY")
print("="*80)
overall_acc = accuracy_score(y_test, y_pred)
print(f"Accuracy: {overall_acc:.4f} ({100*overall_acc:.2f}%)")

print("\n" + "="*80)
print("2. CONFUSION MATRIX")
print("="*80)
cm = confusion_matrix(y_test, y_pred)
print("\nConfusion Matrix (rows=true, cols=predicted):")
print(cm)

# Pretty print confusion matrix with labels
print("\n                    Predicted")
print("                    ", end="")
for name in class_names:
    print(f"{class_labels.get(name, name):15s} ", end="")
print()

for i, true_label in enumerate(class_names):
    print(f"True {class_labels.get(true_label, true_label):12s} {cm[i]}")

print("\n" + "="*80)
print("3. PRECISION, RECALL, F1-SCORE (Per-Class)")
print("="*80)
print(f"\n{'Class':<20} {'Precision':>12} {'Recall':>12} {'F1-Score':>12} {'Support':>12}")
print("-" * 60)

precision_per_class = precision_score(y_test, y_pred, average=None, zero_division=0)
recall_per_class = recall_score(y_test, y_pred, average=None, zero_division=0)
f1_per_class = f1_score(y_test, y_pred, average=None, zero_division=0)

for i, class_name in enumerate(class_names):
    class_label = class_labels.get(class_name, class_name)
    support = np.sum(y_test == i)
    print(f"{class_label:<20} {precision_per_class[i]:>12.4f} {recall_per_class[i]:>12.4f} {f1_per_class[i]:>12.4f} {support:>12d}")

print("\n" + "="*80)
print("4. MACRO & WEIGHTED AVERAGES")
print("="*80)

macro_precision = precision_score(y_test, y_pred, average='macro', zero_division=0)
macro_recall = recall_score(y_test, y_pred, average='macro', zero_division=0)
macro_f1 = f1_score(y_test, y_pred, average='macro', zero_division=0)

weighted_precision = precision_score(y_test, y_pred, average='weighted', zero_division=0)
weighted_recall = recall_score(y_test, y_pred, average='weighted', zero_division=0)
weighted_f1 = f1_score(y_test, y_pred, average='weighted', zero_division=0)

print(f"\nMacro-Averaged:")
print(f"  Precision: {macro_precision:.4f}")
print(f"  Recall:    {macro_recall:.4f}")
print(f"  F1-Score:  {macro_f1:.4f}")

print(f"\nWeighted-Averaged:")
print(f"  Precision: {weighted_precision:.4f}")
print(f"  Recall:    {weighted_recall:.4f}")
print(f"  F1-Score:  {weighted_f1:.4f}")

print("\n" + "="*80)
print("5. CLASSIFICATION REPORT (Sklearn Format)")
print("="*80)
print(classification_report(y_test, y_pred, target_names=[class_labels.get(name, name) for name in class_names], zero_division=0))

print("\n" + "="*80)
print("6. PER-CLASS ANALYSIS")
print("="*80)
for i, class_name in enumerate(class_names):
    mask = y_test == i
    n_samples = np.sum(mask)
    if n_samples == 0:
        print(f"\n{class_labels.get(class_name, class_name)}: No test samples")
        continue
    
    class_acc = accuracy_score(y_test[mask], y_pred[mask])
    print(f"\n{class_labels.get(class_name, class_name)} (n={n_samples}):")
    print(f"  Accuracy: {class_acc:.4f} ({100*class_acc:.2f}%)")
    
    # Correct vs incorrect
    correct = np.sum(y_pred[mask] == y_test[mask])
    incorrect = n_samples - correct
    print(f"  Correct: {correct}/{n_samples}")
    print(f"  Incorrect: {incorrect}/{n_samples}")

print("\n" + "="*80)
print("7. DATASET STATISTICS")
print("="*80)
print(f"Total test samples: {len(y_test)}")
for i, class_name in enumerate(class_names):
    count = np.sum(y_test == i)
    pct = 100 * count / len(y_test)
    print(f"  {class_labels.get(class_name, class_name)}: {count} ({pct:.1f}%)")

print("\n" + "="*80)
print("8. SUMMARY FOR THESIS")
print("="*80)
print(f"""
Model Performance Summary:
├── Overall Accuracy: {100*overall_acc:.2f}%
├── Macro F1-Score: {macro_f1:.4f}
├── Weighted F1-Score: {weighted_f1:.4f}
├── Best Performing Class: {max(f1_per_class) > 0 and class_labels.get(class_names[np.argmax(f1_per_class)]) or 'N/A'} (F1: {max(f1_per_class):.4f})
└── Worst Performing Class: {min(f1_per_class) < 1 and class_labels.get(class_names[np.argmin(f1_per_class)]) or 'N/A'} (F1: {min(f1_per_class):.4f})

Data Split (70/15/15):
├── Training: 855 samples
├── Validation: 183 samples
└── Test: 184 samples (held-out, never seen during training)

Model Architecture:
├── Input Shape: (120, 130, 1)
├── Conv Layers: 4 with BatchNormalization
├── Dropout: 0.3-0.5 for regularization
├── Total Parameters: 309,124
└── Best Epoch: 14 (Validation Accuracy: 63.39%)
""")

print("="*80)
print("✅ Evaluation Complete!")
print("="*80 + "\n")
