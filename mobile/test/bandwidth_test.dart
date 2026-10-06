import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/bandwidth.dart';

void main() {
  group('BandwidthGovernor', () {
    test('is unlimited by default and never delays', () {
      final g = BandwidthGovernor();
      expect(g.enabled, isFalse);
      expect(g.consume(1 << 20), Duration.zero);
      expect(g.consume(1 << 20), Duration.zero);
    });

    test('serves from the initial bucket before throttling', () {
      // 1 MB/s bucket starts full, so the first megabyte is free.
      final g = BandwidthGovernor(bytesPerSecond: 1024 * 1024);
      expect(g.consume(1024 * 1024), Duration.zero);
      // The bucket is now empty; the next bytes must wait.
      expect(g.consume(1024 * 1024), greaterThan(Duration.zero));
    });

    test('deficit is repaid at the configured rate', () {
      var now = DateTime(2026, 1, 1);
      final g = BandwidthGovernor(
        bytesPerSecond: 1000,
        clock: () => now,
      );
      // Drain the initial second of budget.
      expect(g.consume(1000), Duration.zero);
      // Asking for another 1000 bytes costs exactly one second at 1000 B/s.
      final wait = g.consume(1000);
      expect(wait.inMicroseconds, 1000000);

      // After a full second of refill the bucket is full again.
      now = now.add(const Duration(seconds: 1));
      expect(g.consume(1000), Duration.zero);
    });

    test('refill is capped at one second of budget', () {
      var now = DateTime(2026, 1, 1);
      final g = BandwidthGovernor(bytesPerSecond: 1000, clock: () => now);
      // Idle for an hour; the bucket must not grow beyond one second's worth.
      now = now.add(const Duration(hours: 1));
      expect(g.consume(1000), Duration.zero);
      expect(g.consume(1), greaterThan(Duration.zero));
    });

    test('changing the limit takes effect immediately', () {
      final g = BandwidthGovernor(bytesPerSecond: 0);
      expect(g.enabled, isFalse);
      g.bytesPerSecond = 512 * 1024;
      expect(g.enabled, isTrue);
    });
  });
}
