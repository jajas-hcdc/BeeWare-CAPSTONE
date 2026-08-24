import os
import numpy as np
from tensorflow import keras

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(BASE_DIR, "ai_models", "hive_classifier.keras")

# Base hive samples from the app data.
base_samples = [
    {"temperature": 34.2, "humidity": 64.0, "health_score": 90.0, "confidence": 95.0, "label": "healthy"},
    {"temperature": 62.1, "humidity": 58.0, "health_score": 74.0, "confidence": 74.0, "label": "stress"},
    {"temperature": 36.6, "humidity": 60.0, "health_score": 58.0, "confidence": 58.0, "label": "swarming"},
    {"temperature": 33.0, "humidity": 51.0, "health_score": 41.0, "confidence": 41.0, "label": "queenless"},
    {"temperature": 32.8, "humidity": 65.0, "health_score": 93.0, "confidence": 93.0, "label": "healthy"},
]

label_map = {"healthy": 0, "stress": 1, "swarming": 2, "queenless": 3}


def build_training_data(samples, per_sample=12):
    features = []
    labels = []
    rng = np.random.default_rng(42)

    for sample in samples:
        for _ in range(per_sample):
            noise = rng.normal(0.0, 1.2, size=4)
            feature_row = np.array([
                sample["temperature"] + noise[0],
                sample["humidity"] + noise[1],
                sample["health_score"] + noise[2],
                sample["confidence"] + noise[3],
            ], dtype=np.float32)
            features.append(feature_row)
            labels.append(label_map[sample["label"]])

    return np.array(features, dtype=np.float32), np.array(labels, dtype=np.int32)


def train_model():
    X, y = build_training_data(base_samples)

    model = keras.Sequential([
        keras.layers.Input(shape=(4,)),
        keras.layers.Dense(24, activation="relu"),
        keras.layers.Dense(12, activation="relu"),
        keras.layers.Dense(len(label_map), activation="softmax"),
    ])

    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    model.fit(X, y, epochs=220, batch_size=8, verbose=0)

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    model.save(OUTPUT_PATH)

    return model


if __name__ == "__main__":
    model = train_model()
    sample = np.array([[35.5, 63.0, 88.0, 90.0]], dtype=np.float32)
    prediction = model.predict(sample, verbose=0)
    predicted_index = int(np.argmax(prediction[0]))
    predicted_label = list(label_map.keys())[predicted_index]
    print(f"Model trained and saved to: {OUTPUT_PATH}")
    print(f"Sample prediction: {predicted_label} ({prediction[0][predicted_index]:.2%} confidence)")
