import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android intent filters that decide where Turbo appears in the
/// system's "Open with" chooser. Android only offers an app for an intent that
/// carries a MIME type when a filter lists that type, so a video/audio link
/// needs the `video/*`/`audio/*` filter to make Turbo a candidate downloader.
/// These checks read the real manifest so a future edit cannot silently drop it.
void main() {
  late final String manifest;

  setUpAll(() {
    manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  });

  test('Turbo is offered for video and audio media intents', () {
    expect(manifest, contains('android:mimeType="video/*"'));
    expect(manifest, contains('android:mimeType="audio/*"'));
  });

  test('the media filter is browsable over http(s) for VIEW', () {
    // The media filter must be part of a VIEW/BROWSABLE filter with the http
    // and https schemes, or a browser will never offer Turbo.
    final mediaFilter = RegExp(
      r'<intent-filter[^>]*>(?:(?!</intent-filter>).)*?'
      r'android:mimeType="video/\*"(?:(?!</intent-filter>).)*?</intent-filter>',
      dotAll: true,
    ).firstMatch(manifest)?.group(0);
    expect(mediaFilter, isNotNull, reason: 'no media intent filter found');
    expect(mediaFilter, contains('android.intent.action.VIEW'));
    expect(mediaFilter, contains('android.intent.category.BROWSABLE'));
    expect(mediaFilter, contains('android:scheme="http"'));
    expect(mediaFilter, contains('android:scheme="https"'));
  });

  test('plain http(s) links can still be opened with Turbo', () {
    expect(manifest, contains('android:scheme="https"'));
    expect(manifest, contains('android:scheme="http"'));
  });
}
