import os
import numpy as np
import pandas as pd
import librosa
import tensorflow as tf
from sklearn.metrics import confusion_matrix, classification_report, accuracy_score
import random

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
DATA_PATH = os.path.join("..", "dataset", "all_data")
MODEL_PATH = os.path.join("..", "models", "beeware_model.keras")
LABELS_PATH = os.path.join("..", "models", "labels.txt")

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

# Build file map
available_files = {}
for file in os.listdir(DATA_PATH):
    if file.endswith(('.wav', '.raw', '.mp3')):
        base = file.split('__segment')[0] if '__segment' in file else os.path.splitext(file)[0]
        if base not in available_files:
            available_files[base] = []
        available_files[base].append(os.path.join(DATA_PATH, file))

print(f"Found {len(available_files)} unique audio files\n")

# Test on random samples
num_tests = min(100, len(df))
test_indices = random.sample(range(len(df)), num_tests)

y_true = []
y_pred = []
correct = 0
errors = []

print(f"Testing on {num_tests} random samples...\n")

for idx in test_indices:
    row = df.iloc[idx]
    filename = str(row["file name"]).strip()
    queen_status = int(row["queen status"])
    
    if queen_status not in CLASS_NAME_MAP:
        continue
    
    actual_label = CLASS_NAME_MAP[queen_status]
    base = filename.split('__segment')[0] if '__segment' in filename else os.path.splitext(filename)[0]
    
    if base not in available_files:
        continue
    
    file_path = available_files[base][0]
    
    try:
        # Load audio
        signal, sr = librosa.load(file_path, sr=22050)
        mfcc = librosa.feature.mfcc(y=signal, sr=sr, n_mfcc=40)
        mfcc = mfcc[:, :130]
        if mfcc.shape[1] < 130:
            pad_width = 130 - mfcc.shape[1]
            mfcc = np.pad(mfcc, ((0, 0), (0, pad_width)))
        
        # Prepare input
        X = np.array([mfcc])
        X = X.reshape(X.shape[0], X.shape[1], X.shape[2], 1)
        
        # Predict
        prediction = model.predict(X, verbose=0)
        predicted_class = np.argmax(prediction[0])
        predicted_label = labels[predicted_class]
        confidence = prediction[0][predicted_class]
        
        # Store for metrics
        y_true.append(queen_status)
        y_pred.append(predicted_class)
        
        # Check if correct
        is_correct = predicted_class == queen_status
        if is_correct:
            correct += 1
        else:
            errors.append({
                'file': os.path.basename(file_path),
                'actual': actual_label,
                'predicted': predicted_label,
                'confidence': f"{confidence:.2%}"
            })
        
        print(f"{'✓' if is_correct else '✗'} {os.path.basename(file_path)[:40]:40} | Actual: {actual_label:20} | Predicted: {predicted_label:20} ({confidence:.2%})")
        
    except Exception as e:
        continue

print(f"\n{'='*100}")
print(f"RESULTS: {correct}/{num_tests} correct ({100*correct/num_tests:.1f}%)")
print(f"{'='*100}\n")

# Classification report
print("Classification Report:")
print("-" * 80)
if len(y_true) > 0:
    print(classification_report(y_true, y_pred, target_names=labels))

# Confusion matrix
print("\nConfusion Matrix:")
print("-" * 80)
if len(y_true) > 0:
    cm = confusion_matrix(y_true, y_pred)
    print("Predicted (columns) vs Actual (rows):")
    print("     " + "  ".join([f"{l[:10]:>12}" for l in labels]))
    for i, label in enumerate(labels):
        print(f"{label[:5]:5}", end="")
        for j in range(len(labels)):
            print(f" {cm[i][j]:>12}", end="")
        print()

# Show errors
if errors:
    print(f"\n\nMisclassified ({len(errors)} errors):")
    print("-" * 80)
    for error in errors[:10]:  # Show first 10 errors
        print(f"  {error['file'][:40]:40} | {error['actual']:20} → {error['predicted']:20} ({error['confidence']})")
    if len(errors) > 10:
        print(f"  ... and {len(errors) - 10} more errors")
