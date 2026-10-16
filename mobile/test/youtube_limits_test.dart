import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/youtube_browser.dart';
import 'package:turbo_downloader/services/youtube_limits.dart';

void main() {
  group('isYouTubeRateLimit', () {
    test('matches the library wording', () {
      const raw =
          'Failed to perform an HTTP request to YouTube because of rate '
          'limiting. This error indicates that YouTube thinks there were too '
          'many request made from this IP and considers it suspicious.';
      expect(isYouTubeRateLimit(raw), isTrue);
    });

    test('matches each phrase on its own', () {
      expect(isYouTubeRateLimit('...because of rate limiting.'), isTrue);
      expect(isYouTubeRateLimit('HTTP 429 rate-limit reached'), isTrue);
      expect(isYouTubeRateLimit('too many requests'), isTrue);
      expect(isYouTubeRateLimit('TOO MANY REQUESTS'), isTrue);
    });

    test('does not match a bot check, a private video, or a network error', () {
      expect(
        isYouTubeRateLimit(
          'Sign in to confirm you are not a bot. Use --cookies.',
        ),
        isFalse,
      );
      expect(isYouTubeRateLimit('Video unavailable'), isFalse);
      expect(isYouTubeRateLimit('Connection reset by peer'), isFalse);
      expect(isYouTubeRateLimit(''), isFalse);
    });

    test('the user-facing wording avoids the raw library advice', () {
      expect(youTubeRateLimitMessage.toLowerCase(),
          isNot(contains('httpclient')));
      expect(youTubeRateLimitMessage.toLowerCase(),
          isNot(contains('response')));
      expect(youTubeRateLimitMessage, contains('rate-limiting'));
    });
  });

  group('BrowseException.from', () {
    test('replaces a rate-limit error with the app wording', () {
      final e = BrowseException.from(
        Exception('...because of rate limiting. too many request...'),
        'Could not search YouTube',
      );
      expect(e.message, youTubeRateLimitMessage);
    });

    test('keeps the context prefix for any other error', () {
      final e = BrowseException.from(
        Exception('socket closed'),
        'Could not search YouTube',
      );
      expect(e.message, startsWith('Could not search YouTube:'));
      expect(e.message, contains('socket closed'));
    });
  });
}
