import 'dart:math';

/// Exponential-backoff policy for automatic retries.
///
/// Transient failures (network drops, timeouts, 5xx, rate limits) are retried
/// up to [maxAttempts] times with a growing delay and a little jitter, so a
/// fleet of downloads does not hammer a host in lockstep.
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double multiplier;

  /// Fraction of the delay added as random jitter (0–1).
  final double jitter;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
    this.multiplier = 2.0,
    this.jitter = 0.2,
  });

  /// No automatic retries; the user retries by hand.
  static const none = RetryPolicy(maxAttempts: 1);

  /// The delay before [attempt] (1-based). Attempt 1 is the first try, so its
  /// delay is zero; subsequent attempts back off.
  Duration delayFor(int attempt, {Random? random}) {
    if (attempt <= 1) return Duration.zero;
    final rng = random ?? Random();
    final raw = baseDelay.inMilliseconds * pow(multiplier, attempt - 2);
    final capped = min(raw.toDouble(), maxDelay.inMilliseconds.toDouble());
    final jitterMs = capped * jitter * rng.nextDouble();
    return Duration(milliseconds: (capped + jitterMs).round());
  }

  /// True when another automatic attempt is allowed after [attempts] tries.
  bool shouldRetry(int attempts) => attempts < maxAttempts;

  RetryPolicy copyWith({int? maxAttempts}) => RetryPolicy(
        maxAttempts: maxAttempts ?? this.maxAttempts,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        multiplier: multiplier,
        jitter: jitter,
      );
}
