// lib/services/audio_processor.dart
//
// Implements the exact mel-spectrogram pipeline used in beeware2.py training:
//   librosa.feature.melspectrogram(y=y, sr=22050, n_mels=128)
//   librosa.power_to_db(S, ref=np.max)
//   Trimmed / padded to (128 mel bands, 128 time frames, 1 channel)
//
// Runs entirely on-device in a background isolate — no server needed.

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

class AudioProcessor {
  // ── Parameters must match the training script exactly ──────────────────
  static const int _sr          = 22050; // sample rate used by librosa.load
  static const int _nFft        = 2048;  // librosa default n_fft
  static const int _hopLength   = 512;   // librosa default hop_length
  static const int _nMels       = 128;   // n_mels
  static const int _targetFrames = 128;  // S_dB[:, :128]
  static const int _targetSamples = 110250; // sr * 5 seconds

  // ── Slaney mel-scale constants (librosa default htk=False) ─────────────
  static const double _fSp       = 200.0 / 3.0; // Hz per mel in linear region
  static const double _minLogHz  = 1000.0;       // linear→log boundary
  static const double _minLogMel = 15.0;         // = _minLogHz / _fSp
  // logStep = log(6.4) / 27.0  ≈ 0.068751...
  static const double _logStep   = 0.06875177742080365;

  // ───────────────────────────────────────────────────────────────────────
  /// Public entry point.
  /// Returns a [128][128][1] tensor ready to feed into the TFLite model.
  /// Executes in a background isolate so the UI stays responsive.
  static Future<List<List<List<double>>>> extractMelSpectrogram(
      String audioPath) async {
    return compute(_isolateEntry, audioPath);
  }

  // ── Isolate entry (must be a static / top-level function) ──────────────
  static List<List<List<double>>> _isolateEntry(String audioPath) {
    final bytes = File(audioPath).readAsBytesSync();
    return _computeMelSpectrogram(bytes);
  }

  // ── Core pipeline ───────────────────────────────────────────────────────
  static List<List<List<double>>> _computeMelSpectrogram(Uint8List bytes) {
    // 1. Decode WAV → float samples in [-1, 1]
    final samples = _decodeWav(bytes);

    // 2. Pre-compute Hann window (constant across frames)
    final window = _hannWindow(_nFft);

    // 3. Build mel filterbank [nMels][nBins]  (constant for fixed sr/n_fft)
    final melFb = _buildMelFilterbank();

    final nBins = _nFft ~/ 2 + 1;
    final melFrames = <List<double>>[];

    // 4. STFT → power spectrum → mel filterbank, frame by frame
    for (int start = 0;
        start + _nFft <= samples.length && melFrames.length < _targetFrames;
        start += _hopLength) {
      // 4a. Windowed frame
      final real = Float64List(_nFft);
      for (int i = 0; i < _nFft; i++) {
        real[i] = samples[start + i] * window[i];
      }
      final imag = Float64List(_nFft); // zeros

      // 4b. In-place FFT
      _fftInPlace(real, imag);

      // 4c. One-sided power spectrum  |X[k]|²
      final power = Float64List(nBins);
      for (int k = 0; k < nBins; k++) {
        power[k] = real[k] * real[k] + imag[k] * imag[k];
      }

      // 4d. Apply mel filterbank → one mel frame
      final melFrame = List<double>.generate(_nMels, (m) {
        double s = 0.0;
        final row = melFb[m];
        for (int k = 0; k < nBins; k++) {
          s += row[k] * power[k];
        }
        return s;
      });
      melFrames.add(melFrame);
    }

    // 5. power_to_db  →  10 * log10( max(S, 1e-10) / ref ),  ref = max(S)
    double refMax = 1e-10;
    for (final f in melFrames) {
      for (final v in f) {
        if (v > refMax) refMax = v;
      }
    }

    // 6. Build output tensor [nMels=128][targetFrames=128][1]
    //    librosa shape: (n_mels, n_frames) → we index [mel][frame]
    return List<List<List<double>>>.generate(_nMels, (mel) {
      return List<List<double>>.generate(_targetFrames, (frame) {
        if (frame >= melFrames.length) return [0.0]; // zero-pad if needed
        final db = 10.0 * log(max(melFrames[frame][mel], 1e-10) / refMax) / ln10;
        return [db];
      });
    });
  }

  // ── WAV decoder ─────────────────────────────────────────────────────────
  /// Parses a WAV file and returns float32 samples normalised to [-1.0, 1.0].
  /// Handles mono/stereo 16-bit PCM.  Extra metadata chunks are skipped.
  static List<double> _decodeWav(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);

    int numChannels  = 1;
    int bitsPerSample = 16;
    int dataStart    = -1;
    int dataSize     = 0;

    // Walk RIFF chunks starting after the 12-byte RIFF/WAVE header
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final id       = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSz  = bd.getUint32(offset + 4, Endian.little);

      if (id == 'fmt ') {
        numChannels   = bd.getUint16(offset + 10, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (id == 'data') {
        dataStart = offset + 8;
        dataSize  = chunkSz;
        break;
      }
      offset += 8 + chunkSz;
    }

    // Fallback to silence on corrupt / unsupported files
    if (dataStart < 0 || bitsPerSample != 16) {
      return List<double>.filled(_targetSamples, 0.0);
    }

    final bytesPerFrame = (bitsPerSample ~/ 8) * numChannels;
    final totalFrames   = dataSize ~/ bytesPerFrame;
    final readFrames    = min(totalFrames, _targetSamples);

    final result = List<double>.filled(_targetSamples, 0.0);
    for (int i = 0; i < readFrames; i++) {
      final off = dataStart + i * bytesPerFrame;
      result[i] = bd.getInt16(off, Endian.little) / 32768.0;
    }
    return result;
  }

  // ── Hann window ─────────────────────────────────────────────────────────
  /// 0.5 * (1 − cos(2π·n / (N−1)))  — matches scipy.signal.hann(N)
  static List<double> _hannWindow(int n) {
    return List<double>.generate(
        n, (i) => 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1))));
  }

  // ── Mel filterbank ──────────────────────────────────────────────────────
  /// Builds a [nMels × nBins] triangular mel filterbank.
  /// Matches: librosa.filters.mel(sr, n_fft, n_mels=128, fmin=0, fmax=sr/2,
  ///                               norm=None, htk=False)
  static List<Float64List> _buildMelFilterbank() {
    final nBins = _nFft ~/ 2 + 1;
    const double fmin = 0.0;
    const double fmax = _sr / 2.0; // Nyquist = 11025 Hz

    final melMin = _hzToMel(fmin);
    final melMax = _hzToMel(fmax);

    // n_mels + 2 linearly-spaced points in mel domain
    final nPts  = _nMels + 2;
    final step  = (melMax - melMin) / (_nMels + 1);
    final hzPts = List<double>.generate(nPts, (i) => _melToHz(melMin + i * step));

    // Convert Hz centres to FFT bin indices  (librosa: floor((n_fft+1)*f/sr))
    final bins = List<int>.generate(nPts, (i) => (hzPts[i] * (_nFft + 1) / _sr).floor());

    return List<Float64List>.generate(_nMels, (m) {
      final row   = Float64List(nBins);
      final bLow  = bins[m];
      final bMid  = bins[m + 1];
      final bHigh = bins[m + 2];

      // Rising slope:  (k − bLow) / (bMid − bLow)
      if (bMid > bLow) {
        for (int k = bLow; k < bMid && k < nBins; k++) {
          row[k] = (k - bLow) / (bMid - bLow);
        }
      }
      // Falling slope: (bHigh − k) / (bHigh − bMid)
      if (bHigh > bMid) {
        for (int k = bMid; k <= bHigh && k < nBins; k++) {
          row[k] = (bHigh - k) / (bHigh - bMid);
        }
      }
      return row;
    });
  }

  // ── Mel ↔ Hz conversions (Slaney scale) ────────────────────────────────
  static double _hzToMel(double hz) {
    if (hz >= _minLogHz) {
      return _minLogMel + log(hz / _minLogHz) / _logStep;
    }
    return hz / _fSp;
  }

  static double _melToHz(double mel) {
    if (mel >= _minLogMel) {
      return _minLogHz * exp(_logStep * (mel - _minLogMel));
    }
    return mel * _fSp;
  }

  // ── In-place radix-2 Cooley-Tukey FFT ──────────────────────────────────
  /// Requires [real] and [imag] to have power-of-2 length (2048 here).
  static void _fftInPlace(Float64List real, Float64List imag) {
    final n = real.length;

    // Bit-reversal permutation
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while (j >= bit) {
        j -= bit;
        bit >>= 1;
      }
      j += bit;
      if (i < j) {
        double t = real[i]; real[i] = real[j]; real[j] = t;
        t = imag[i]; imag[i] = imag[j]; imag[j] = t;
      }
    }

    // Butterfly stages
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2.0 * pi / len;
      final wRe = cos(ang);
      final wIm = sin(ang);
      final half = len >> 1;

      for (int i = 0; i < n; i += len) {
        double uRe = 1.0, uIm = 0.0;
        for (int k = 0; k < half; k++) {
          final eRe  = real[i + k];
          final eIm  = imag[i + k];
          final idx  = i + k + half;
          final oRe  = real[idx] * uRe - imag[idx] * uIm;
          final oIm  = real[idx] * uIm + imag[idx] * uRe;
          real[i + k] = eRe + oRe;
          imag[i + k] = eIm + oIm;
          real[idx]   = eRe - oRe;
          imag[idx]   = eIm - oIm;
          final nu = uRe * wRe - uIm * wIm;
          uIm = uRe * wIm + uIm * wRe;
          uRe = nu;
        }
      }
    }
  }
}
