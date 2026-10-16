import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/cookie_jar.dart';

/// An embedded browser the user signs into YouTube with, so the app can copy
/// the resulting session cookies into the vault.
///
/// Mobile sandboxes stop us reading the real Chrome/Safari cookie store, so a
/// WebView is the only way to obtain a logged-in session on a phone. The
/// cookies are read back from the *platform* cookie store
/// ([CookieManager]), not from JavaScript — the session cookies are HttpOnly,
/// so scripts cannot see them and an in-page `document.cookie` read would
/// always come back empty.
///
/// Pops the captured Netscape `cookies.txt` text, or null if cancelled.
class YouTubeLoginScreen extends StatefulWidget {
  const YouTubeLoginScreen({super.key});

  @override
  State<YouTubeLoginScreen> createState() => _YouTubeLoginScreenState();
}

class _YouTubeLoginScreenState extends State<YouTubeLoginScreen> {
  bool _signedIn = false;
  bool _capturing = false;

  static const _loginUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube';

  /// Cookies YouTube sets for a signed-in user. A logged-out visit still sets
  /// visitor cookies, so presence of an anonymous cookie is not enough.
  static const _sessionCookies = {
    'SAPISID',
    'SID',
    '__Secure-1PSID',
    '__Secure-3PSID',
  };

  Future<void> _checkSignedIn() async {
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri('https://www.youtube.com'));
    final signedIn =
        cookies.any((c) => _sessionCookies.contains(c.name) && c.value.isNotEmpty);
    if (signedIn != _signedIn && mounted) {
      setState(() => _signedIn = signedIn);
    }
  }

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final manager = CookieManager.instance();
      final cookies = <JarCookie>[];
      for (final origin in const [
        'https://www.youtube.com',
        'https://accounts.google.com',
      ]) {
        for (final c in await manager.getCookies(url: WebUri(origin))) {
          cookies.add(JarCookie(
            name: c.name,
            value: c.value,
            domain: c.domain ?? '',
            path: c.path ?? '/',
            secure: c.isSecure ?? false,
            httpOnly: c.isHttpOnly ?? false,
            expiresMs: c.expiresDate,
          ));
        }
      }
      final jar = CookieJar.toNetscape(CookieJar.onlyYouTube(cookies));
      if (!mounted) return;
      if (CookieJar.onlyYouTube(cookies).isEmpty) {
        setState(() => _capturing = false);
        _snack('No YouTube cookies were captured. Make sure you are signed in.');
        return;
      }
      Navigator.of(context).pop(jar);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      _snack('Could not read the session: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to YouTube'),
        actions: [
          if (_capturing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _signedIn ? _capture : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_signedIn)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Sign in below. Once you are back on YouTube, tap Save.',
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
              initialSettings: InAppWebViewSettings(
                thirdPartyCookiesEnabled: true,
                // A desktop-ish agent avoids the mobile-web login funnel, which
                // is fussier and more likely to interpose extra steps.
                userAgent:
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
              ),
              onLoadStop: (_, __) => _checkSignedIn(),
            ),
          ),
        ],
      ),
    );
  }
}
