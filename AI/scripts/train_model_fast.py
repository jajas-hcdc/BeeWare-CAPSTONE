"""
Fast training script with pre-cached MFCC features
Extracts features once, saves to NPZ, then trains quickly
"""
import os
import numpy as np
import pandas as pd
import librosa
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.utils.class_weight import compute_class_weight
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense, Dropout, BatchNormalization, GlobalAveragePooling2D
from tensorflow.keras.utils import to_categorical
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau, ModelCheckpoint

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATASET_CSV = os.path.join(BASE_DIR, "dataset", "all_data_updated.csv")
DATA_PATH = os.path.join(BASE_DIR, "dataset", "all_data")
CACHE_FILE = os.path.join(BASE_DIR, "models", "features_cache.npz")
MODEL_PATH = os.path.join(BASE_DIR, "models", "beeware_model_fast.keras")
TFLITE_PATH = os.path.join(BASE_DIR, "models", "beeware_model_fast.tflite")
LABELS_PATH = os.path.join(BASE_DIR, "models", "labels_fast.txt")

os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)

def extract_and_cache_features():
    """Extract MFCC features from all audio and cache to disk"""
    print("🔍 Checking for cached features...")
    if os.path.exists(CACHE_FILE):
        print(f"✅ Loading from cache: {CACHE_FILE}")
        data = np.load(CACHE_FILE)
        return data['X'], data['y'], data['filenames']
    
    print("\n🎵 Extracting MFCC features (one-time)...")
    print("This will take 5-10 minutes on first run, then saved to cache.")
    
    df = pd.read_csv(DATASET_CSV)
    
    # Build file map
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
    
    X = []
    y = []
    filenames = []
    loaded = 0
    skipped = 0

    for idx, row in df.iterrows():
        filename = str(row["file name"]).strip()
        queen_status = int(row["queen status"])
        
        if queen_status not in [0, 1, 2, 3]:
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
            skipped += 1
            continue
        
        try:
            # Load audio and extract MFCC
            signal, sr = librosa.load(file_path, sr=22050)
            mfcc = librosa.feature.mfcc(y=signal, sr=sr, n_mfcc=40)
            mfcc_delta = librosa.feature.delta(mfcc)
            mfcc_delta2 = librosa.feature.delta(mfcc, order=2)
            
            features = np.vstack([mfcc, mfcc_delta, mfcc_delta2])
            features = features[:, :130]
            if features.shape[1] < 130:
                pad_width = 130 - features.shape[1]
                features = np.pad(features, ((0, 0), (0, pad_width)))
            
            X.append(features)
            y.append(queen_status)
            filenames.append(os.path.basename(file_path))
            loaded += 1
            
            # Progress
            if loaded % 100 == 0:
                print(f"  ✅ Loaded {loaded} samples...")
            
        except Exception as e:
            skipped += 1
            continue
    
    print(f"\n✅ Loaded {loaded} samples, skipped {skipped}")
    
    X = np.array(X)
    y = np.array(y)
    filenames = np.array(filenames)
    
    # Save to cache
    print(f"\n💾 Caching {len(X)} samples to {CACHE_FILE}...")
    np.savez_compressed(CACHE_FILE, X=X, y=y, filenames=filenames)
    
    return X, y, filenames

if __name__ == "__main__":
    print("="*80)
    print("FAST TRAINING PIPELINE (with feature caching)")
    print("="*80)
    
    # Load/extract features
    X, y, filenames = extract_and_cache_features()
    
    print(f"\n📊 Dataset statistics:")
    unique, counts = np.unique(y, return_counts=True)
    for u, c in zip(unique, counts):
        pct = 100 * c / len(y)
        class_name = {0: "Queen Present", 1: "Queen Absent", 2: "Queen Accepted", 3: "Queen Rejected"}[u]
        print(f"  {class_name}: {c} ({pct:.1f}%)")

    print("\n📊 Encoding labels...")
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    y_categorical = to_categorical(y_encoded)

    print("📈 Splitting data (80/10/10 stratified)...")
    X_train, X_temp, y_train, y_temp = train_test_split(
        X,
        y_categorical,
        test_size=0.20,
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

    # Calculate class weights
    class_weights = compute_class_weight(
        'balanced',
        classes=np.unique(y_encoded),
        y=y_encoded
    )
    class_weight_dict = {i: weight for i, weight in enumerate(class_weights)}
    print(f"\n⚖️  Class weights: {class_weight_dict}")

    # Prepare input
    X_train = X_train.reshape(X_train.shape[0], X_train.shape[1], X_train.shape[2], 1)
    X_val = X_val.reshape(X_val.shape[0], X_val.shape[1], X_val.shape[2], 1)
    X_test = X_test.reshape(X_test.shape[0], X_test.shape[1], X_test.shape[2], 1)

    print("\n🏗️  Building model...")
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
        Dense(y_categorical.shape[1], activation="softmax"),
    ])
    
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss="categorical_crossentropy",
        metrics=["accuracy"]
    )
    
    print("\n🚀 Training...")
    callbacks = [
        EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=False,
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
        epochs=100,
        batch_size=32,
        verbose=1,
        class_weight=class_weight_dict,
        callbacks=callbacks,
    )
    
    # Reload best model from checkpoint
    model = tf.keras.models.load_model(MODEL_PATH)
    print(f"\n✅ Reloaded best model from checkpoint")

    print("\n📊 Evaluating on test set...")
    loss, accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"✅ Test accuracy: {accuracy:.4f} ({100*accuracy:.1f}%)")
    print(f"   Test loss: {loss:.4f}")

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

    print(f"\n✅ Done!")
    print(f"   Model: {MODEL_PATH}")
    print(f"   TFLite: {TFLITE_PATH}")
    print(f"   Cache: {CACHE_FILE}")
