import os
import numpy as np
import pandas as pd
import librosa
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense, Dropout
from tensorflow.keras.utils import to_categorical

DATASET_CSV = os.path.join("..", "dataset", "all_data_updated.csv")
DATA_PATH = os.path.join("..", "dataset", "all_data")
MODEL_PATH = os.path.join("..", "models", "beeware_model.keras")
TFLITE_PATH = os.path.join("..", "models", "beeware_model.tflite")
LABELS_PATH = os.path.join("..", "models", "labels.txt")

os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)


def load_dataset(csv_path, data_path):
    df = pd.read_csv(csv_path)
    if "file name" not in df.columns or "queen status" not in df.columns:
        raise ValueError("CSV must contain 'file name' and 'queen status' columns")

    # Build a map of base filenames to actual files
    available_files = {}
    for file in os.listdir(data_path):
        if file.endswith(('.wav', '.raw', '.mp3')):
            # Extract base name (timestamp and device, without segment)
            base = file.split('__segment')[0] if '__segment' in file else os.path.splitext(file)[0]
            if base not in available_files:
                available_files[base] = []
            available_files[base].append(os.path.join(data_path, file))

    CLASS_NAME_MAP = {0: "Queen Present", 1: "Queen Absent", 2: "Queen Accepted", 3: "Queen Rejected"}
    
    X = []
    y = []
    skipped = 0

    for _, row in df.iterrows():
        filename = str(row["file name"]).strip()
        queen_status = int(row["queen status"])
        
        if queen_status not in CLASS_NAME_MAP:
            continue
        
        # Extract base name from CSV filename
        base = filename.split('__segment')[0] if '__segment' in filename else os.path.splitext(filename)[0]
        
        # Find matching file(s)
        if base not in available_files:
            skipped += 1
            continue
        
        # Use first segment available for this timestamp
        file_path = available_files[base][0]
        
        try:
            signal, sr = librosa.load(file_path, sr=22050)
            mfcc = librosa.feature.mfcc(y=signal, sr=sr, n_mfcc=40)
            mfcc = mfcc[:, :130]
            if mfcc.shape[1] < 130:
                pad_width = 130 - mfcc.shape[1]
                mfcc = np.pad(mfcc, ((0, 0), (0, pad_width)))
            X.append(mfcc)
            y.append(CLASS_NAME_MAP[queen_status])
        except Exception as e:
            skipped += 1
            continue
    
    if skipped > 0:
        print(f"Skipped {skipped} files due to missing or error loading")
    if len(X) == 0:
        raise ValueError("No valid audio files found!")

    X = np.array(X)
    X = X.reshape(X.shape[0], X.shape[1], X.shape[2], 1)
    return X, y


def build_model(num_classes):
    model = Sequential([
        Conv2D(32, (3, 3), activation="relu", input_shape=(40, 130, 1)),
        MaxPooling2D(),
        Conv2D(64, (3, 3), activation="relu"),
        MaxPooling2D(),
        Flatten(),
        Dense(128, activation="relu"),
        Dropout(0.5),
        Dense(num_classes, activation="softmax"),
    ])
    model.compile(optimizer="adam", loss="categorical_crossentropy", metrics=["accuracy"])
    return model


if __name__ == "__main__":
    X, y = load_dataset(DATASET_CSV, DATA_PATH)

    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    y_categorical = to_categorical(y_encoded)

    X_train, X_temp, y_train, y_temp = train_test_split(
        X,
        y_categorical,
        test_size=0.30,
        random_state=42,
        stratify=y_categorical,
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp,
        y_temp,
        test_size=0.50,
        random_state=42,
        stratify=y_temp,
    )

    # Calculate class weights to balance classes
    from sklearn.utils.class_weight import compute_class_weight
    class_weights = compute_class_weight(
        'balanced',
        classes=np.unique(y_encoded),
        y=y_encoded
    )
    class_weight_dict = {i: weight for i, weight in enumerate(class_weights)}
    print(f"Class weights: {class_weight_dict}\n")

    model = build_model(y_categorical.shape[1])
    history = model.fit(
        X_train,
        y_train,
        validation_data=(X_val, y_val),
        epochs=20,
        batch_size=32,
        verbose=1,
        class_weight=class_weight_dict,
    )

    loss, accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test accuracy: {accuracy:.4f}")

    model.save(MODEL_PATH)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    with open(TFLITE_PATH, "wb") as f:
        f.write(tflite_model)

    with open(LABELS_PATH, "w", encoding="utf-8") as f:
        for label in encoder.classes_:
            f.write(f"{label}\n")

    print(f"Saved model: {MODEL_PATH}")
    print(f"Saved TFLite model: {TFLITE_PATH}")
    print(f"Saved labels: {LABELS_PATH}")
