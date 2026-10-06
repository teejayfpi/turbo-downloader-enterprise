import 'dart:async';

/// A shared token-bucket that caps the aggregate download rate.
///
/// All concurrent transfers (the built-in engine and yt-dlp) draw from one
/// bucket, so a limit means the whole app, not each connection. A limit of 0
/// means unlimited and the governor never delays anything.
///
/// The bucket refills continuously at [bytesPerSecond]. Each [consume] call
/// takes the tokens it can and reports how long the caller should wait before
/// writing, so the write loop never busy-waits and stays smooth.
class BandwidthGovernor {
  BandwidthGovernor({this.bytesPerSecond = 0, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _lastRefill = (clock ?? DateTime.now)(),
        _available = bytesPerSecond.toDouble();

  /// The cap in bytes per second. 0 (or negative) disables limiting.
  int bytesPerSecond;

  final DateTime Function() _clock;
  double _available;
  DateTime _lastRefill;

  bool get enabled => bytesPerSecond > 0;

  void _refill() {
    if (!enabled) return;
    final now = _clock();
    final elapsed = now.difference(_lastRefill).inMicroseconds;
    if (elapsed <= 0) return;
    _lastRefill = now;
    _available = (_available + bytesPerSecond * elapsed / 1e6)
        .clamp(0.0, bytesPerSecond.toDouble());
  }

  /// Records that [n] bytes are about to be written and returns how long the
  /// caller should wait first. Returns [Duration.zero] when unlimited or when
  /// tokens are available. Never blocks.
  Duration consume(int n) {
    if (!enabled || n <= 0) return Duration.zero;
    _refill();
    _available -= n;
    if (_available >= 0) return Duration.zero;
    // The deficit is repaid at the refill rate; the caller sleeps exactly that
    // long so the average rate converges on the cap.
    final deficit = -_available;
    _available = 0;
    final micros = (deficit / bytesPerSecond * 1e6).round();
    return Duration(microseconds: micros);
  }

  /// Waits for [n] bytes' worth of budget, then returns. Await this before a
  /// write to throttle a stream to the configured rate.
  Future<void> waitFor(int n) async {
    final delay = consume(n);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }
}
