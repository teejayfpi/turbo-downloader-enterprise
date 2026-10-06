@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/media_extractor.dart';

/// End-to-end checks against the real YouTube endpoints. Opt in with:
///   TURBO_LIVE=1 flutter test test/live_media_test.dart
/// Skipped by default so the normal suite (and CI) never depends on a network
/// call to YouTube.
///
/// The goal is to reproduce what a user hits when they paste a link, and to
/// confirm the bytes actually land on disk. YouTube refuses to serve its pages
/// to datacenter IPs, so a block is reported as a skip rather than a failure:
/// it says nothing about the app.
void main() {
  const url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  final live = Platform.environment['TURBO_LIVE'] == '1';

  bool blocked(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('would not serve this page') ||
        message.contains('blocked in your region') ||
        message.contains('age-restricted') ||
        message.contains('sign in to confirm') ||
        message.contains('needs to be reloaded') ||
        message.contains('restrictions in place') ||
        message.contains('prevent watching');
  }

  test('describe returns formats for a real video', () async {
    final MediaInfo info;
    try {
      info = await const MediaExtractor().describe(url);
    } catch (error) {
      if (blocked(error)) {
        markTestSkipped('YouTube blocked this network: $error');
        return;
      }
      rethrow;
    }
    // ignore: avoid_print
    print('TITLE: ${info.title}');
    // ignore: avoid_print
    print('AUTHOR: ${info.author}');
    // ignore: avoid_print
    print(
        'FORMATS: ${info.formats.map((f) => '${f.kind}/${f.label}/${f.id}').join(', ')}');
    expect(info.title, isNotEmpty);
    expect(info.formats, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)), skip: !live);

  test('resolve yields a fetchable stream that downloads bytes', () async {
    const extractor = MediaExtractor();
    final MediaInfo info;
    try {
      info = await extractor.describe(url);
    } catch (error) {
      if (blocked(error)) {
        markTestSkipped('YouTube blocked this network: $error');
        return;
      }
      rethrow;
    }
    final first = info.formats.first;
    // ignore: avoid_print
    print(
        'PICKED: ${first.kind}/${first.label}/${first.id} needsMux=${first.requiresMux}');

    final media = await extractor.resolve(url, formatId: first.id);
    // ignore: avoid_print
    print('RESOLVED: ext=${media.extension} size=${media.size} '
        'audioUrl=${media.audioUrl != null}');

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(media.url));
    final res = await req.close();
    // ignore: avoid_print
    print('HTTP: ${res.statusCode} len=${res.contentLength}');
    expect(res.statusCode, anyOf(200, 206));
    final bytes = await res.fold<int>(0, (n, chunk) => n + chunk.length);
    // ignore: avoid_print
    print('DOWNLOADED: $bytes bytes');
    expect(bytes, greaterThan(0));
    client.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 3)), skip: !live);
}

