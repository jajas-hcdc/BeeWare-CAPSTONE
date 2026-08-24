"""
Fixed training script with correct file loading and improved architecture
"""
import os
import numpy as np
import pandas as pd
import librosa
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense, Dropout, BatchNormalization, GlobalAveragePooling2D
from tensorflow.keras.utils import to_categorical
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau, ModelCheckpoint

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
DATA_PATH = os.path.join("..", "dataset", "all_data")
MODEL_PATH = os.path.join("..", "models", "beeware_model_fixed.keras")
TFLITE_PATH = os.path.join("..", "models", "beeware_model_fixed.tflite")
LABELS_PATH = os.path.join("..", "models", "labels_fixed.txt")

os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)

def load_dataset(csv_path, data_path):
    """Load dataset with CORRECT file matching"""
    df = pd.read_csv(csv_path)
    
    if "file name" not in df.columns or "queen status" not in df.columns:
        raise ValueError("CSV must contain 'file name' and 'queen status' columns")

    # Build map of ALL available files (including segments)
    available_files = {}
    for file in os.listdir(data_path):
        if file.endswith(('.wav', '.raw', '.mp3')):
            # Extract base name
            if '__segment' in file:
                base = file.split('__segment')[0]
                segment_num = int(file.split('__segment')[1].split('.')[0])
            else:
                base = os.path.splitext(file)[0]
                segment_num = 0
            
            if base not in available_files:
                available_files[base] = {}
            
            available_files[base][segment_num] = os.path.join(data_path, file)

    CLASS_NAME_MAP = {0: "Queen Present", 1: "Queen Absent", 2: "Queen Accepted", 3: "Queen Rejected"}
    
    X = []
    y = []
    loaded = 0
    skipped = 0

    for idx, row in df.iterrows():
        filename = str(row["file name"]).strip()
        queen_status = int(row["queen status"])
        
        if queen_status not in CLASS_NAME_MAP:
            continue
        
        # Extract base name from CSV
        if '__segment' in filename:
            base = filename.split('__segment')[0]
            segment_num = int(filename.split('__segment')[1].split('.')[0])
        else:
            # Remove .raw/.wav extension
            base = os.path.splitext(filename)[0]
            # Try to match with segment0 or no segment
            segment_num = 0
        
        # Try to find matching file
        file_path = None
        if base in available_files:
            if segment_num in available_files[base]:
                # Exact match (e.g., segment 1 in CSV, segment 1 exists)
                file_path = available_files[base][segment_num]
            elif 0 in available_files[base]:
                # Fallback to segment 0 if exact segment not found
                file_path = available_files[base][0]
        
        if file_path is None:
            skipped += 1
            if skipped <= 5:
                print(f"  ⚠️  Skipped: {filename} (base={base}, seg={segment_num})")
            continue
        
        try:
            # Load audio
            signal, sr = librosa.load(file_path, sr=22050)
            
            # Extract MFCC features
            mfcc = librosa.feature.mfcc(y=signal, sr=sr, n_mfcc=40)
            
            # Extract delta and delta-delta (important for temporal dynamics)
            mfcc_delta = librosa.feature.delta(mfcc)
            mfcc_delta2 = librosa.feature.delta(mfcc, order=2)
            
            # Combine all features (3 × 40 = 120 features)
            features = np.vstack([mfcc, mfcc_delta, mfcc_delta2])  # (120, time_steps)
            
            # Truncate/pad to fixed length
            features = features[:, :130]
            if features.shape[1] < 130:
                pad_width = 130 - features.shape[1]
                features = np.pad(features, ((0, 0), (0, pad_width)))
            
            X.append(features)
            y.append(queen_status)
            loaded += 1
            
        except Exception as e:
            skipped += 1
            if skipped <= 5:
                print(f"  ❌ Error loading {file_path}: {str(e)[:50]}")
            continue
    
    print(f"\n✅ Loaded {loaded} samples, skipped {skipped}")
    if len(X) == 0:
        raise ValueError("No valid audio files found!")

    X = np.array(X)
    print(f"Feature shape: {X.shape}")
    X = X.reshape(X.shape[0], X.shape[1], X.shape[2], 1)
    print(f"Input shape: {X.shape}")
    
    return np.array(X), np.array(y)

def build_model(num_classes):
    """Improved CNN architecture with batch norm and better depth"""
    model = Sequential([
        Conv2D(32, (3, 3), activation="relu", input_shape=(120, 130, 1)),
        BatchNormalization(),
        Conv2D(64, (3, 3), activation="relu"),
        BatchNormalization(),
        MaxPooling2D((2, 2)),
        
        Conv2D(128, (3, 3), activation="relu"),
        BatchNormalization(),
        MaxPooling2D((2, 2)),
        Dropout(0.3),
        
        Conv2D(128, (3, 3), activation="relu"),
        BatchNormalization(),
        Dropout(0.3),
        
        GlobalAveragePooling2D(),
        
        Dense(256, activation="relu"),
        BatchNormalization(),
        Dropout(0.5),
        Dense(128, activation="relu"),
        Dropout(0.3),
        Dense(num_classes, activation="softmax"),
    ])
    
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss="categorical_crossentropy",
        metrics=["accuracy"]
    )
    
    return model

if __name__ == "__main__":
    print("="*80)
    print("FIXED TRAINING PIPELINE")
    print("="*80)
    
    print("\n📂 Loading dataset...")
    X, y = load_dataset(DATASET_CSV, DATA_PATH)

    print(f"\nDataset statistics:")
    unique, counts = np.unique(y, return_counts=True)
    for u, c in zip(unique, counts):
        pct = 100 * c / len(y)
        class_name = {0: "Queen Present", 1: "Queen Absent", 2: "Queen Accepted", 3: "Queen Rejected"}[u]
        print(f"  {class_name}: {c} ({pct:.1f}%)")

    print("\n📊 Encoding labels...")
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    y_categorical = to_categorical(y_encoded)

    print("📈 Splitting data (70/15/15 stratified)...")
    X_train, X_temp, y_train, y_temp = train_test_split(
        X,
        y_categorical,
        test_size=0.30,
        random_state=42,
        stratify=y_encoded,
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp,
        y_temp,
        test_size=0.50,
        random_state=42,
        stratify=np.argmax(y_temp, axis=1),
    )

    print(f"  Train: {X_train.shape[0]}")
    print(f"  Val: {X_val.shape[0]}")
    print(f"  Test: {X_test.shape[0]}")

    # Save test set indices for reproducible evaluation
    import json
    train_indices_file = os.path.join(os.path.dirname(MODEL_PATH), "train_indices.json")
    val_indices_file = os.path.join(os.path.dirname(MODEL_PATH), "val_indices.json")
    test_indices_file = os.path.join(os.path.dirname(MODEL_PATH), "test_indices.json")
    
    # We'll save which rows from df made it to train/val/test
    # To do this, we need to track indices before shuffling
    # For now, just save the split sizes and random state so we can recreate it
    split_info = {
        "total_samples": len(X),
        "train_size": X_train.shape[0],
        "val_size": X_val.shape[0],
        "test_size": X_test.shape[0],
        "random_state": 42
    }
    with open(os.path.join(os.path.dirname(MODEL_PATH), "split_info.json"), "w") as f:
        json.dump(split_info, f, indent=2)

    # Calculate class weights
    from sklearn.utils.class_weight import compute_class_weight
    class_weights = compute_class_weight(
        'balanced',
        classes=np.unique(y_encoded),
        y=y_encoded
    )
    class_weight_dict = {i: weight for i, weight in enumerate(class_weights)}
    print(f"\n⚖️  Class weights: {class_weight_dict}")

    print("\n🏗️  Building model...")
    model = build_model(y_categorical.shape[1])
    model.summary()

    print("\n🚀 Training...")
    callbacks = [
        EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=False,  # Don't revert; let checkpoint handle best model
            verbose=1
        ),
        ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-6,
            verbose=1
        ),
        ModelCheckpoint(
            MODEL_PATH,
            monitor='val_accuracy',
            save_best_only=True,
            verbose=1
        )
    ]

    history = model.fit(
        X_train,
        y_train,
        validation_data=(X_val, y_val),
        epochs=100,  # Increased with early stopping
        batch_size=32,
        verbose=1,
        class_weight=class_weight_dict,
        callbacks=callbacks,
    )
    
    # Reload the best model from checkpoint (not the final epoch)
    model = tf.keras.models.load_model(MODEL_PATH)
    print(f"\n✅ Reloaded best model from checkpoint")

    print("\n📊 Evaluating on test set...")
    loss, accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test accuracy: {accuracy:.4f}")
    print(f"Test loss: {loss:.4f}")

    print(f"\n💾 Saving model...")
    model.save(MODEL_PATH)

    print(f"🔄 Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    with open(TFLITE_PATH, "wb") as f:
        f.write(tflite_model)

    print(f"🏷️  Saving labels...")
    with open(LABELS_PATH, "w", encoding="utf-8") as f:
        for label in encoder.classes_:
            f.write(f"{label}\n")

    print(f"\n✅ Saved model: {MODEL_PATH}")
    print(f"✅ Saved TFLite model: {TFLITE_PATH}")
    print(f"✅ Saved labels: {LABELS_PATH}")
