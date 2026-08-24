# BeeWare AI Capstone

This folder contains a from-scratch TensorFlow training workflow for an audio-based bee colony classifier.

## Files
- train_beeware.py: training script for MFCC-based CNN
- model/: output folder for the trained model and labels

## Expected dataset layout
- all_data_updated.csv
- all_data/*.wav

## Required packages
```bash
pip install librosa tensorflow pandas scikit-learn matplotlib
```

## Run training
```bash
python train_beeware.py
```
