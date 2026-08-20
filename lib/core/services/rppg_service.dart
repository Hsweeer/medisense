import 'dart:math';

/// One video frame's worth of signal: the average R/G/B pixel value inside
/// the detected face box, plus when it was captured.
class RppgSample {
  RppgSample({required this.timestampMs, required this.r, required this.g, required this.b});
  final int timestampMs;
  final double r;
  final double g;
  final double b;
}

/// Estimates heart rate (BPM) from a short window of face-region RGB
/// samples using **CHROM** (Haan & Jeanne, 2013) — the same chrominance-
/// based unsupervised method rPPG-Toolbox benchmarks. It's plain signal
/// processing (no trained model, no GPU, no dataset), which is what makes
/// it realistic to run natively on-device instead of via their Python
/// pipeline.
///
/// How it works, in order:
/// 1. Normalize each color channel by its own mean over the window (so
///    brightness differences between people/lighting don't dominate).
/// 2. Project normalized RGB onto two chrominance signals (Xs, Ys) that the
///    CHROM paper derived to cancel out motion/lighting artifacts while
///    keeping the pulse-driven color variation.
/// 3. Combine them into a single pulse signal S = Xs − alpha·Ys.
/// 4. Scan candidate heart rates (42–180 BPM) with a Goertzel filter — this
///    is a lightweight way to ask "how much energy in S is at exactly this
///    frequency?" without needing a full FFT library. The BPM with the
///    most energy wins.
class AutocorrResult {
  AutocorrResult({required this.bpm, required this.score});
  final double? bpm;
  final double score;
}

class RppgResult {
  RppgResult({required this.bpm, required this.confidence, required this.resampled, required this.powers, required this.fs, this.autocorrBpm, this.autocorrScore});
  final double? bpm;
  final double confidence;
  final List<double> resampled;
  final List<double> powers;
  final double fs;
  final double? autocorrBpm;
  final double? autocorrScore;
}

class RppgService {
  RppgService._();

  /// Minimum samples/duration needed for a reading to be trustworthy.
  static const int minSamples = 90; // ~6s at 15fps
  static const double minDurationSeconds = 8;

  static const double _minBpm = 42;
  static const double _maxBpm = 180;
  static const double _bpmStep = 0.5;

  /// Returns detailed estimation including confidence and internal signals
  /// which are useful for debugging or UI display. Does not print by default
  /// but will return arrays (may be large).
  static RppgResult estimateWithDebug(List<RppgSample> samples) {
    final n = samples.length;
    if (n < minSamples) return RppgResult(bpm: null, confidence: 0.0, resampled: [], powers: [], fs: 0.0);

    final durationSeconds =
        (samples.last.timestampMs - samples.first.timestampMs) / 1000.0;
    if (durationSeconds < minDurationSeconds) return RppgResult(bpm: null, confidence: 0.0, resampled: [], powers: [], fs: 0.0);

    // Original irregular sampling timestamps (ms -> seconds)
    final times = samples
        .map((s) => (s.timestampMs - samples.first.timestampMs) / 1000.0)
        .toList();

    // Compute normalized chrominance pulse using CHROM (per-sample)
    final rMean = _mean(samples.map((s) => s.r));
    final gMean = _mean(samples.map((s) => s.g));
    final bMean = _mean(samples.map((s) => s.b));
    if (rMean == 0 || gMean == 0 || bMean == 0) return RppgResult(bpm: null, confidence: 0.0, resampled: [], powers: [], fs: 0.0);

    final rn = samples.map((s) => s.r / rMean).toList();
    final gn = samples.map((s) => s.g / gMean).toList();
    final bn = samples.map((s) => s.b / bMean).toList();

    final xs = List<double>.generate(n, (i) => 3 * rn[i] - 2 * gn[i]);
    final ys = List<double>.generate(
        n, (i) => 1.5 * rn[i] + gn[i] - 1.5 * bn[i]);

    final stdXs = _std(xs);
    final stdYs = _std(ys);
    final alpha = stdYs == 0 ? 0.0 : stdXs / stdYs;

    final pulse = List<double>.generate(n, (i) => xs[i] - alpha * ys[i]);

    // Resample to a uniform sampling rate for spectral methods
    const double targetFs = 20.0; // 20 Hz is a good on-device compromise
    final int m = (durationSeconds * targetFs).round();
    if (m < 4) return RppgResult(bpm: null, confidence: 0.0, resampled: [], powers: [], fs: targetFs);
    final resampled = List<double>.filled(m, 0.0);
    final resampledTimes = List<double>.generate(m, (i) => i / targetFs);

    // Linear interpolation of the detrended pulse
    final pulseMean = _mean(pulse);
    final detrended = pulse.map((v) => v - pulseMean).toList();

    for (int i = 0; i < m; i++) {
      final t = resampledTimes[i];
      // find interval in original times
      if (t <= times.first) {
        resampled[i] = detrended.first;
        continue;
      }
      if (t >= times.last) {
        resampled[i] = detrended.last;
        continue;
      }
      // binary search for index (linear scan is fine for small n)
      int idx = 0;
      while (idx < times.length - 1 && times[idx + 1] < t) {
        idx++;
      }
      final t0 = times[idx];
      final t1 = times[idx + 1];
      final v0 = detrended[idx];
      final v1 = detrended[idx + 1];
      final w = (t - t0) / (t1 - t0);
      resampled[i] = v0 * (1 - w) + v1 * w;
    }

    // Apply Hann window to reduce spectral leakage
    final windowed = List<double>.generate(m, (i) {
      final w = 0.5 * (1 - cos(2 * pi * i / (m - 1)));
      return resampled[i] * w;
    });

    // Bandpass filter (2nd-order biquad) centered on band (0.75 - 3.0 Hz)
    final filtered = _bandpassBiquad(windowed, targetFs, 0.75, 3.0);

    // Compute Goertzel powers across candidate BPMs using uniform fs
    double bestBpm = 0;
    double bestPower = -1;
    final List<double> powers = [];
    for (double bpm = _minBpm; bpm <= _maxBpm; bpm += _bpmStep) {
      final freqHz = bpm / 60.0;
      final power = _goertzelPower(filtered, targetFs, freqHz);
      powers.add(power);
      if (power > bestPower) {
        bestPower = power;
        bestBpm = bpm;
      }
    }

    if (bestBpm == 0) return RppgResult(bpm: null, confidence: 0.0, resampled: resampled, powers: powers, fs: targetFs);

    // Confidence metric: ratio of best peak to median power
    final sorted = List<double>.from(powers)..sort();
    final median = sorted[sorted.length ~/ 2];
    final confidence = median <= 0 ? double.infinity : bestPower / (median + 1e-12);

    // --- Autocorrelation-based check (time-domain) ---
    final autocorr = _autocorrEstimate(filtered, targetFs);

    // Decision logic combining both methods
    double? finalBpm;
    double finalConfidence = confidence;

    // Accept if Goertzel is very confident
    if (confidence >= 6.0) {
      finalBpm = bestBpm;
    } else if (autocorr.bpm != null) {
      // If autocorr agrees within +/- 3 BPM, accept average
      if ((autocorr.bpm! - bestBpm).abs() <= 3.0) {
        finalBpm = (autocorr.bpm! + bestBpm) / 2.0;
        finalConfidence = (confidence + autocorr.score) / 2.0;
      } else if (confidence >= 4.0 && autocorr.score >= 4.0) {
        // fallback: both somewhat confident but different — prefer Goertzel
        finalBpm = bestBpm;
        finalConfidence = (confidence + autocorr.score) / 2.0;
      } else {
        finalBpm = null;
      }
    } else {
      // no autocorr result and confidence low
      finalBpm = null;
    }

    return RppgResult(bpm: finalBpm, confidence: finalConfidence, resampled: resampled, powers: powers, fs: targetFs, autocorrBpm: autocorr.bpm, autocorrScore: autocorr.score);
  }

  static double? estimateBpm(List<RppgSample> samples) {
    return estimateWithDebug(samples).bpm;
  }

  /// Bandpass the signal [x] using a single 2nd-order biquad (RBJ cookbook)
  /// centered on the band [lowHz..highHz]. Returns the filtered signal.
  static List<double> _bandpassBiquad(
      List<double> x, double fs, double lowHz, double highHz) {
    final n = x.length;
    if (n == 0) return <double>[];

    final f0 = (lowHz + highHz) / 2.0;
    final bw = (highHz - lowHz).abs();
    final Q = bw <= 0 ? 1.0 : (f0 / bw);

    final omega = 2 * pi * f0 / fs;
    final sinw = sin(omega);
    final cosw = cos(omega);
    final alpha = sinw / (2 * Q);

    double b0 = alpha;
    double b1 = 0.0;
    double b2 = -alpha;
    double a0 = 1 + alpha;
    double a1 = -2 * cosw;
    double a2 = 1 - alpha;

    b0 /= a0;
    b1 /= a0;
    b2 /= a0;
    a1 /= a0;
    a2 /= a0;

    final y = List<double>.filled(n, 0.0);
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < n; i++) {
      final xi = x[i];
      final yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      y[i] = yi;
      x2 = x1;
      x1 = xi;
      y2 = y1;
      y1 = yi;
    }
    return y;
  }

  /// Power of signal [x] at [targetFreqHz], sampled at [fps] — a cheap
  /// single-frequency alternative to a full FFT, exact for any sample count.
  static double _goertzelPower(
      List<double> x, double fps, double targetFreqHz) {
    final n = x.length;
    final k = 0.5 + (n * targetFreqHz / fps);
    final w = 2 * pi * k / n;
    final cosine = cos(w);
    final coeff = 2 * cosine;

    double q0 = 0, q1 = 0, q2 = 0;
    for (final v in x) {
      q0 = coeff * q1 - q2 + v;
      q2 = q1;
      q1 = q0;
    }
    final real = q1 - q2 * cosine;
    final imag = q2 * sin(w);
    return real * real + imag * imag;
  }

  /// Autocorrelation-based BPM estimate. Returns null BPM if signal too
  /// weak. Score is a crude SNR-like ratio (peak / median).
  static AutocorrResult _autocorrEstimate(List<double> x, double fs) {
    final n = x.length;
    if (n < 8) return AutocorrResult(bpm: null, score: 0.0);

    // zero-mean
    final mean = _mean(x);
    final xx = x.map((v) => v - mean).toList();

    // lags corresponding to 42..180 BPM
    final minLag = (fs * 60.0 / _maxBpm).floor();
    final maxLag = (fs * 60.0 / _minBpm).ceil();
    if (maxLag >= n) return AutocorrResult(bpm: null, score: 0.0);

    List<double> ac = List<double>.filled(maxLag + 1, 0.0);
    for (int lag = minLag; lag <= maxLag; lag++) {
      double s = 0.0;
      for (int i = 0; i < n - lag; i++) {
        s += xx[i] * xx[i + lag];
      }
      ac[lag] = s;
    }

    // normalize by lag 0 energy
    double energy0 = 0.0;
    for (final v in xx) energy0 += v * v;
    if (energy0 <= 1e-9) return AutocorrResult(bpm: null, score: 0.0);

    for (int i = 0; i < ac.length; i++) ac[i] = ac[i] / energy0;

    // find peak lag
    int bestLag = minLag;
    double bestVal = ac[bestLag];
    for (int lag = minLag + 1; lag <= maxLag; lag++) {
      if (ac[lag] > bestVal) {
        bestVal = ac[lag];
        bestLag = lag;
      }
    }

    // crude score: peak / median of ac in range
    final region = ac.sublist(minLag, maxLag + 1);
    final sorted = List<double>.from(region)..sort();
    final median = sorted[sorted.length ~/ 2];
    final score = median <= 0 ? (bestVal > 0 ? bestVal * 100.0 : 0.0) : bestVal / (median + 1e-12);

    final bpm = bestVal <= 0 ? null : (fs / bestLag) * 60.0;
    return AutocorrResult(bpm: bpm, score: score);
  }

  static double _mean(Iterable<double> v) {
    if (v.isEmpty) return 0;
    return v.reduce((a, b) => a + b) / v.length;
  }

  static double _std(List<double> v) {
    if (v.isEmpty) return 0;
    final m = _mean(v);
    final variance = v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
        v.length;
    return sqrt(variance);
  }
}
