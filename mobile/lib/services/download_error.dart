import 'dart:io';

/// The category of a download failure. The UI uses it to choose an icon, a
/// colour, and whether a retry makes sense.
enum DownloadErrorKind {
  network,
  timeout,
  server,
  notFound,
  forbidden,
  rangeUnsupported,
  diskFull,
  permission,
  fileChanged,
  corrupt,
  engine,
  media,
  mux,
  cancelled,
  unknown,
}

/// A failure the user can act on.
///
/// Every user-facing string lives in [message]; [detail] holds the raw,
/// copyable technical text for a support ticket. Nothing here is a stack trace
/// or a raw `toString()` — those are appended to the diagnostics log instead.
class DownloadError implements Exception {
  final DownloadErrorKind kind;

  /// One sentence, plain language, telling the user what happened.
  final String message;

  /// What to do about it, when there is a concrete next step.
  final String? advice;

  /// Raw technical text (HTTP status, OS errno, engine stderr). Copyable.
  final String? detail;

  /// True when retrying is likely to succeed (transient conditions).
  final bool retryable;

  const DownloadError(
    this.kind,
    this.message, {
    this.advice,
    this.detail,
    this.retryable = false,
  });

  /// Classifies a thrown object into an actionable [DownloadError].
  factory DownloadError.from(Object error, {String? context}) {
    if (error is DownloadError) return error;
    final text = error.toString();
    final lower = text.toLowerCase();

    if (error is SocketException) {
      if (lower.contains('failed host lookup') ||
          lower.contains('nodename nor servname') ||
          lower.contains('name or service not known')) {
        return DownloadError(
          DownloadErrorKind.network,
          'Could not reach the server. Check your connection and the address.',
          advice: 'Confirm the link opens in a browser, then retry.',
          detail: text,
          retryable: true,
        );
      }
      return DownloadError(
        DownloadErrorKind.network,
        'The network connection dropped before the download finished.',
        advice: 'Reconnect and retry; the transfer resumes where it stopped.',
        detail: text,
        retryable: true,
      );
    }

    if (error is HandshakeException) {
      return DownloadError(
        DownloadErrorKind.network,
        'The secure connection could not be established.',
        advice: 'The server\'s certificate may be invalid or expired.',
        detail: text,
        retryable: false,
      );
    }

    if (error is HttpException) {
      return _fromHttpText(text);
    }

    if (error is FileSystemException) {
      final os = error.osError;
      if (os != null && (os.errorCode == 28 || os.errorCode == 112)) {
        return DownloadError(
          DownloadErrorKind.diskFull,
          'The destination disk is full.',
          advice: 'Free up space, then retry. Your partial file is kept.',
          detail: text,
          retryable: true,
        );
      }
      if (os != null && (os.errorCode == 13 || os.errorCode == 5)) {
        return DownloadError(
          DownloadErrorKind.permission,
          'Turbo was not allowed to write the file.',
          advice: 'Grant storage permission, or pick another folder.',
          detail: text,
          retryable: false,
        );
      }
      return DownloadError(
        DownloadErrorKind.unknown,
        'The file could not be written to disk.',
        detail: text,
        retryable: true,
      );
    }

    if (lower.contains('insufficient') || lower.contains('no space left')) {
      return DownloadError(
        DownloadErrorKind.diskFull,
        'The destination disk is full.',
        advice: 'Free up space, then retry.',
        detail: text,
        retryable: true,
      );
    }

    return DownloadError(
      DownloadErrorKind.unknown,
      context == null
          ? 'The download stopped unexpectedly.'
          : 'The download stopped unexpectedly ($context).',
      detail: text,
      retryable: true,
    );
  }

  static DownloadError _fromHttpText(String text) {
    final status = int.tryParse(
      RegExp(r'(\d{3})').firstMatch(text)?.group(1) ?? '',
    );
    switch (status) {
      case 401:
      case 403:
        return DownloadError(
          DownloadErrorKind.forbidden,
          'The server refused access to this file.',
          advice: 'It may need a login or may be region-restricted.',
          detail: text,
          retryable: false,
        );
      case 404:
      case 410:
        return DownloadError(
          DownloadErrorKind.notFound,
          'The file was not found on the server.',
          advice: 'The link may have expired or been removed.',
          detail: text,
          retryable: false,
        );
      case 416:
        return DownloadError(
          DownloadErrorKind.fileChanged,
          'The remote file changed while downloading.',
          advice: 'Retry to start fresh; the old partial data is discarded.',
          detail: text,
          retryable: true,
        );
      case 429:
        return DownloadError(
          DownloadErrorKind.server,
          'The server is rate-limiting requests.',
          advice: 'Wait a moment and retry.',
          detail: text,
          retryable: true,
        );
    }
    if (status != null && status >= 500) {
      return DownloadError(
        DownloadErrorKind.server,
        'The server had a problem handling the request.',
        advice: 'This is usually temporary; retry shortly.',
        detail: text,
        retryable: true,
      );
    }
    return DownloadError(
      DownloadErrorKind.server,
      'The server rejected the download request.',
      detail: text,
      retryable: status == null,
    );
  }

  /// A short, copyable block for a support ticket.
  String get technicalDetails {
    final buffer = StringBuffer()
      ..writeln('kind: ${kind.name}')
      ..writeln('message: $message');
    if (advice != null) buffer.writeln('advice: $advice');
    if (detail != null) buffer.writeln('detail: $detail');
    return buffer.toString().trimRight();
  }

  @override
  String toString() => message;
}

/// Canonical, reusable failure constructors for the engine.
class DownloadErrors {
  const DownloadErrors._();

  static const noResume = DownloadError(
    DownloadErrorKind.rangeUnsupported,
    'The server does not support resumable downloads.',
    advice: 'This transfer restarts from the beginning if interrupted.',
    retryable: false,
  );

  static const timeout = DownloadError(
    DownloadErrorKind.timeout,
    'The connection timed out.',
    advice: 'Retry; Turbo will back off between attempts.',
    retryable: true,
  );

  static const permission = DownloadError(
    DownloadErrorKind.permission,
    'Storage permission is required.',
    advice: 'Grant permission in Settings, then retry.',
    retryable: false,
  );

  static const diskFull = DownloadError(
    DownloadErrorKind.diskFull,
    'The destination disk has insufficient space.',
    advice: 'Free up space, then retry.',
    retryable: true,
  );

  static const fileChanged = DownloadError(
    DownloadErrorKind.fileChanged,
    'The remote file changed during resume.',
    advice: 'Retry to download the current version from the start.',
    retryable: true,
  );

  static const corruptPart = DownloadError(
    DownloadErrorKind.corrupt,
    'A partial file was damaged and has been discarded.',
    advice: 'Retry to download it again cleanly.',
    retryable: true,
  );

  static DownloadError rangeIgnored(int segment) => DownloadError(
        DownloadErrorKind.rangeUnsupported,
        'The server ignored range requests.',
        advice: 'Turbo fell back to a single connection.',
        detail: 'segment ${segment + 1}',
        retryable: true,
      );

  static DownloadError endedEarly(int expected, int got) => DownloadError(
        DownloadErrorKind.network,
        'The connection ended before the file was complete.',
        advice: 'Retry; the transfer resumes from the last byte.',
        detail: 'expected $expected bytes, received $got',
        retryable: true,
      );

  static DownloadError httpStatus(int status) =>
      DownloadError.from(HttpException('Server responded $status'));
}
