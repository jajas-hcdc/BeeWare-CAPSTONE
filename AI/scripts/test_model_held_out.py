"""
Test script that evaluates ONLY on the held-out test set
(same data split as training)
"""
import os
import numpy as np
import pandas as pd
import librosa
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.metrics import confusion_matrix, classification_report
from sklearn.preprocessing import LabelEncoder

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
DATA_PATH = os.path.join("..", "dataset", "all_data")
MODEL_PATH = os.path.join("..", "models", "beeware_model_fixed.keras")
LABELS_PATH = os.path.join("..", "models", "labels_fixed.txt")

CLASS_NAME_MAP = {0: "Queen Present", 1: "Queen Absent", 2: "Queen Accepted", 3: "Queen Rejected"}

# Load labels
with open(LABELS_PATH, "r") as f:
    labels = [line.strip() for line in f.readlines()]

print(f"Loaded labels: {labels}\n")

# Load model
model = tf.keras.models.load_model(MODEL_PATH)
print(f"Loaded model from {MODEL_PATH}\n")

# Load CSV
df = pd.read_csv(DATASET_CSV)

# Build file map (including segments)
available_files = {}
for file in os.listdir(DATA_PATH):
    if file.endswith(('.wav', '.raw', '.mp3')):
        if '__segment' in file:
            base = file.split('__segment')[0]
            segment_num = int(file.split('__segment')[1].split('.')[0])
        else:
            base = os.path.splitext(file)[0]
            segment_num = 0
        
        if base not in available_files:
            available_files[base] = {}
        
        available_files[base][segment_num] = os.path.join(DATA_PATH, file)

print(f"Found {len(available_files)} unique recordings\n")

# ====== REPLICATE EXACT TRAIN/VAL/TEST SPLIT ======
print("📈 Recreating exact train/val/test split (70/15/15)...\n")

X_dummy = []
y_all = []
file_indices_map = []

# Load all data with same logic as training
for idx, row in df.iterrows():
    filename = str(row["file name"]).strip()
    queen_status = int(row["queen status"])
    
    if queen_status not in CLASS_NAME_MAP:
        continue
    
    # Extract base name
    if '__segment' in filename:
        base = filename.split('__segment')[0]
        segment_num = int(filename.split('__segment')[1].split('.')[0])
    else:
        base = os.path.splitext(filename)[0]
        segment_num = 0
    
    # Find matching file
    file_path = None
    if base in available_files:
        if segment_num in available_files[base]:
            file_path = available_files[base][segment_num]
        elif 0 in available_files[base]:
            file_path = available_files[base][0]
    
    if file_path is None:
        continue
    
    try:
        # Load audio
        signal, sr = librosa.load(file_path, sr=22050)
        
        # Extract features
        mfcc = librosa.feature.mfcc(y=signal, sr=sr, n_mfcc=40)
        mfcc_delta = librosa.feature.delta(mfcc)
        mfcc_delta2 = librosa.feature.delta(mfcc, order=2)
        
        features = np.vstack([mfcc, mfcc_delta, mfcc_delta2])
        features = features[:, :130]
        if features.shape[1] < 130:
            pad_width = 130 - features.shape[1]
            features = np.pad(features, ((0, 0), (0, pad_width)))
        
        X_dummy.append(features)
        y_all.append(queen_status)
        file_indices_map.append(idx)  # Track original df index
        
    except Exception as e:
        continue

print(f"Loaded {len(X_dummy)} valid samples from CSV\n")

# Encode labels
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y_all)
y_categorical = tf.keras.utils.to_categorical(y_encoded)

# EXACT SAME SPLIT AS TRAINING (random_state=42)
X_train, X_temp, y_train, y_temp, idx_train, idx_temp = train_test_split(
    np.array(X_dummy),
    y_categorical,
    np.arange(len(X_dummy)),
    test_size=0.30,
    random_state=42,
    stratify=y_encoded,
)

X_val, X_test, y_val, y_test, idx_val, idx_test = train_test_split(
    X_temp,
    y_temp,
    idx_temp,
    test_size=0.50,
    random_state=42,
    stratify=np.argmax(y_temp, axis=1),
)

print(f"Split verification:")
print(f"  Train: {X_train.shape[0]}")
print(f"  Val: {X_val.shape[0]}")
print(f"  Test: {X_test.shape[0]}\n")

# Prepare test data with channel dimension
X_test_input = X_test.reshape(X_test.shape[0], X_test.shape[1], X_test.shape[2], 1)

# ====== EVALUATE ON HELD-OUT TEST SET ======
print("🧪 EVALUATING ON HELD-OUT TEST SET (184 samples)")
print("=" * 100)

y_true = []
y_pred = []
y_pred_probs = []
correct = 0
errors = []

predictions = model.predict(X_test_input, verbose=0)

for i in range(len(X_test)):
    predicted_class = np.argmax(predictions[i])
    predicted_label = labels[predicted_class]
    confidence = predictions[i][predicted_class]
    
    # Get actual label
    actual_class = np.argmax(y_test[i])
    actual_label = labels[actual_class]
    
    # Store for metrics
    y_true.append(actual_class)
    y_pred.append(predicted_class)
    y_pred_probs.append(predictions[i])
    
    # Check if correct
    is_correct = predicted_class == actual_class
    if is_correct:
        correct += 1
    else:
        errors.append({
            'idx': idx_test[i],
            'actual': actual_label,
            'predicted': predicted_label,
            'confidence': f"{confidence:.2%}"
        })
    
    symbol = "✓" if is_correct else "✗"
    print(f"{symbol} {actual_label:20} → {predicted_label:20} ({confidence:.2%})")

print(f"\n{'='*100}")
print(f"✅ TEST ACCURACY: {correct}/{len(X_test)} correct ({100*correct/len(X_test):.1f}%)")
print(f"{'='*100}\n")

# Classification report
print("📊 Classification Report:")
print("-" * 80)
print(classification_report(y_true, y_pred, target_names=labels))

# Confusion matrix
print("\n📈 Confusion Matrix (Predicted → Actual):")
print("-" * 80)
cm = confusion_matrix(y_true, y_pred)
print("     " + "  ".join([f"{l[:10]:>12}" for l in labels]))
for i, label in enumerate(labels):
    print(f"{label[:5]:5}", end="")
    for j in range(len(labels)):
        print(f" {cm[i][j]:>12}", end="")
    print()

# Show errors
if errors:
    print(f"\n\n❌ Misclassified ({len(errors)} errors):")
    print("-" * 80)
    for error in errors[:15]:
        print(f"  {error['actual']:20} → {error['predicted']:20} ({error['confidence']})")
    if len(errors) > 15:
        print(f"  ... and {len(errors) - 15} more errors")

# Per-class metrics
print(f"\n\n📋 Per-Class Metrics:")
print("-" * 80)
for i, label in enumerate(labels):
    mask = np.array(y_true) == i
    if mask.sum() == 0:
        continue
    class_acc = (np.array(y_pred)[mask] == i).sum() / mask.sum()
    print(f"{label:20}: {class_acc:.1%} accuracy ({mask.sum()} samples)")
