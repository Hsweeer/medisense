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
class RppgService {
  RppgService._();

  /// Minimum samples/duration needed for a reading to be trustworthy.
  static const int minSamples = 90; // ~6s at 15fps
  static const double minDurationSeconds = 8;

  static const double _minBpm = 42;
  static const double _maxBpm = 180;
  static const double _bpmStep = 0.5;

  /// Returns the estimated BPM, or null if there isn't enough/clean-enough
  /// data yet (caller should keep collecting samples).
  static double? estimateBpm(List<RppgSample> samples) {
    final n = samples.length;
    if (n < minSamples) return null;

    final durationSeconds =
        (samples.last.timestampMs - samples.first.timestampMs) / 1000.0;
    if (durationSeconds < minDurationSeconds) return null;

    final fps = n / durationSeconds;

    final rMean = _mean(samples.map((s) => s.r));
    final gMean = _mean(samples.map((s) => s.g));
    final bMean = _mean(samples.map((s) => s.b));
    if (rMean == 0 || gMean == 0 || bMean == 0) return null;

    final rn = samples.map((s) => s.r / rMean).toList();
    final gn = samples.map((s) => s.g / gMean).toList();
    final bn = samples.map((s) => s.b / bMean).toList();

    // CHROM projection.
    final xs = List<double>.generate(n, (i) => 3 * rn[i] - 2 * gn[i]);
    final ys = List<double>.generate(
        n, (i) => 1.5 * rn[i] + gn[i] - 1.5 * bn[i]);

    final stdXs = _std(xs);
    final stdYs = _std(ys);
    final alpha = stdYs == 0 ? 0.0 : stdXs / stdYs;

    final pulse = List<double>.generate(n, (i) => xs[i] - alpha * ys[i]);
    final pulseMean = _mean(pulse);
    final detrended = pulse.map((v) => v - pulseMean).toList();

    double bestBpm = 0;
    double bestPower = -1;
    for (double bpm = _minBpm; bpm <= _maxBpm; bpm += _bpmStep) {
      final power = _goertzelPower(detrended, fps, bpm / 60.0);
      if (power > bestPower) {
        bestPower = power;
        bestBpm = bpm;
      }
    }

    return bestBpm == 0 ? null : bestBpm;
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
