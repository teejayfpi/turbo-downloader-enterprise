import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/link_inbox.dart';
import 'package:turbo_downloader/state.dart';

void main() {
  group('extractUrl', () {
    test('pulls a bare link out of arbitrary shared text', () {
      expect(
        extractUrl('Watch this https://youtu.be/dQw4w9WgXcQ now'),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('keeps the whole link when it is the only content', () {
      expect(
        extractUrl('https://example.com/file.zip'),
        'https://example.com/file.zip',
      );
    });

    test('trims trailing punctuation that wraps a pasted link', () {
      expect(
        extractUrl('(https://example.com/a.mp3).'),
        'https://example.com/a.mp3',
      );
    });

    test('handles scheme-only and empty input', () {
      expect(extractUrl('no links here'), isNull);
      expect(extractUrl(''), isNull);
    });
  });

  group('TurboState pending link', () {
    test('receiveLink stores and takePendingLink returns once', () {
      final state = TurboState();
      expect(state.pendingUrl, isNull);

      state.receiveLink('  https://example.com/v  ');
      expect(state.pendingUrl, 'https://example.com/v');

      expect(state.takePendingLink(), 'https://example.com/v');
      expect(state.pendingUrl, isNull);
      expect(state.takePendingLink(), isNull);

      state.dispose();
    });

    test('ignores blank links', () {
      final state = TurboState();
      state.receiveLink('   ');
      expect(state.pendingUrl, isNull);
      state.dispose();
    });
  });
}
