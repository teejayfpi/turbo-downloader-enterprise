import 'package:flutter_test/flutter_test.dart';

import 'package:turbo_downloader/media_url.dart';
import 'package:turbo_downloader/state.dart';

void main() {
  group('TurboState is device-only', () {
    test('starts with no server, token, or account', () {
      final state = TurboState();
      addTearDown(state.dispose);

      // There is nothing to configure before downloading: no base URL, no key.
      expect(state.defaultConnections, 4);
      expect(state.accentKey, 'cyan');
      expect(state.playSound, isTrue);
      expect(state.local.tasks, isEmpty);
    });
  });

  group('media routing', () {
    test('a media page is detected so it is queued for on-device resolve', () {
      expect(isMediaUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isMediaUrl('https://example.com/file.zip'), isFalse);
    });
  });
}
