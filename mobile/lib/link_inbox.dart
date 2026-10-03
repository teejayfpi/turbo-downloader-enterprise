import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Pulls the first `http(s)` URL out of arbitrary shared text.
///
/// A browser share, a copied message, or an "Open with" payload can all contain
/// extra words around the link, so this scans for the URL rather than assuming
/// the whole string is one.
String? extractUrl(String text) {
  final match = RegExp(r'https?://[^\s<>"' r"'" r'\]\)]+').firstMatch(text);
  if (match == null) return null;
  // Trim trailing punctuation that commonly wraps a pasted link.
  var url = match.group(0)!;
  while (url.isNotEmpty && '.,;:!?'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}

/// Watches the operating system for links that were aimed at Turbo and hands
/// each one to [onLink].
///
/// Sources are covered on every platform:
/// - **deep links / "Open with"** via `app_links` (Android, iOS, macOS, Windows,
///   Linux) — clicking a link registered to Turbo, or choosing Turbo in a share
///   menu;
/// - **the Android/iOS share sheet** via `receive_sharing_intent`, so a link
///   shared straight from a browser's Share button arrives here;
/// - **desktop drag-and-drop** is handled by the widget layer (`desktop_drop`),
///   which also funnels into [onLink].
///
/// Everything is best-effort and platform-guarded: a platform without a source
/// simply receives nothing.
class LinkInbox {
  LinkInbox({required this.onLink});

  /// Called once per incoming link, already reduced to a bare URL.
  final void Function(String url) onLink;

  StreamSubscription<Uri>? _uriSub;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _listenDeepLinks();
    _listenShares();
  }

  void _listenDeepLinks() {
    if (kIsWeb) return;
    try {
      final links = AppLinks();
      // A cold start hands the link over exactly once.
      links.getInitialLink().then((uri) => _emit(uri)).catchError((_) {});
      _uriSub = links.uriLinkStream.listen(
        _emit,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // The platform has no deep-link support; ignore.
    }
  }

  void _listenShares() {
    if (kIsWeb) return;
    // The share sheet exists on mobile only; registering elsewhere can throw.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      final sharing = ReceiveSharingIntent.instance;
      sharing.getInitialMedia().then((files) {
        for (final f in files) {
          _emitText(f.path);
        }
        sharing.reset();
      }).catchError((_) {});
      _shareSub = sharing.getMediaStream().listen((files) {
        for (final f in files) {
          _emitText(f.path);
        }
      }, onError: (_) {});
    } catch (_) {
      // Sharing is unavailable; the other sources still work.
    }
  }

  void _emit(Uri? uri) {
    if (uri == null) return;
    final url = extractUrl(uri.toString());
    if (url != null) onLink(url);
  }

  void _emitText(String? text) {
    if (text == null || text.isEmpty) return;
    final url = extractUrl(text);
    if (url != null) onLink(url);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _uriSub?.cancel();
    await _shareSub?.cancel();
  }
}
