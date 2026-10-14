import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/download_error.dart';

/// The user-facing message must describe the real failure, not the opaque
/// "The download stopped unexpectedly." These check the classifier that turns a
/// thrown object into an actionable [DownloadError].
void main() {
  test('a timeout is reported as a timeout, not a generic stop', () {
    final error = DownloadError.from(
      TimeoutException('connection timed out'),
    );
    expect(error.kind, DownloadErrorKind.timeout);
    expect(error.retryable, isTrue);
    expect(error.message, isNot(contains('stopped unexpectedly')));
  });

  test('a generic "timed out" text is a timeout', () {
    final error = DownloadError.from(Exception('the request timed out'));
    expect(error.kind, DownloadErrorKind.timeout);
  });

  test('a failed host lookup is a network error', () {
    final error = DownloadError.from(
      const SocketException('Failed host lookup: example.com'),
    );
    expect(error.kind, DownloadErrorKind.network);
    expect(error.retryable, isTrue);
  });

  test('a full disk is reported as disk full', () {
    final error = DownloadError.from(
      const FileSystemException('write failed', '/tmp/x', OSError('no space', 28)),
    );
    expect(error.kind, DownloadErrorKind.diskFull);
  });

  test('a permission failure is reported as permission', () {
    final error = DownloadError.from(
      const FileSystemException('write failed', '/tmp/x', OSError('denied', 13)),
    );
    expect(error.kind, DownloadErrorKind.permission);
  });

  test('a null-check crash is surfaced as storage, not generic', () {
    final error = DownloadError.from(
      Exception('Null check operator used on a null value'),
    );
    expect(error.kind, DownloadErrorKind.storage);
    expect(error.message, isNot(contains('stopped unexpectedly')));
  });

  test('an unclassifiable error keeps the generic message and is retryable',
      () {
    final error = DownloadError.from(StateError('something odd'));
    expect(error.kind, DownloadErrorKind.unknown);
    expect(error.message, contains('stopped unexpectedly'));
    expect(error.retryable, isTrue);
  });

  test('an already-classified error passes through unchanged', () {
    final error = DownloadError.from(DownloadErrors.storageUnavailable);
    expect(identical(error, DownloadErrors.storageUnavailable), isTrue);
  });
}
