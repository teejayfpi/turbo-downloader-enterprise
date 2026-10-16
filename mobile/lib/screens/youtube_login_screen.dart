import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../services/cookie_jar.dart';
import '../state.dart';
import 'home_shell.dart';

/// The widget-test harness has no web-view plugin, so the embedded browser
/// cannot be built there. Tests exercise the surrounding first-run flow against
/// a placeholder instead of failing to load the plugin.
bool get _hasWebView => !Platform.environment.containsKey('FLUTTER_TEST');

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
///
/// On first run the caller pushes this as [required]: the back button is
/// intercepted so the user cannot slip past it, but "Not now" is still offered
/// (with a confirmation) so a locked-out network never traps them. A normal
/// sign-in from Settings leaves [required] false and can be dismissed freely.
class YouTubeLoginScreen extends StatefulWidget {
  const YouTubeLoginScreen({super.key, this.required = false});

  /// True on the first-run gate: the screen cannot be dismissed by going back.
  final bool required;

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
      await _save(jar);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      _snack('Could not read the session: $e');
    }
  }

  /// Saves the captured jar and leaves the screen.
  ///
  /// On the first-run gate this screen is the root route, so there is nothing
  /// to pop to: it persists the session and replaces itself with the shell. A
  /// sign-in from Settings pops the jar back to the caller as before.
  Future<void> _save(String jar) async {
    final state = context.read<TurboState>();
    await state.setSessionCookies(jar);
    await state.completeSignInPrompt();
    if (!mounted) return;
    if (widget.required) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeShell()),
      );
    } else {
      Navigator.of(context).pop(jar);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// First-run gate only: confirm before letting the user continue without a
  /// session. They can still proceed, so a network YouTube will not talk to
  /// never traps them on this screen.
  Future<void> _notNow() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue without signing in?'),
        content: const Text(
          'Turbo works without a YouTube session, but bot-checked, '
          'age-restricted, private, and members-only videos need one. You can '
          'sign in any time from Settings → Sign-in & cookies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep signing in'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await context.read<TurboState>().completeSignInPrompt();
      if (!mounted) return;
      // On the gate this screen is the root route; replace it with the shell.
      // If it was pushed from Settings, just pop back.
      if (widget.required) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeShell()),
        );
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.required,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _notNow();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.required,
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
            else ...[
              TextButton(
                onPressed: _signedIn ? _capture : null,
                child: const Text('Save'),
              ),
              if (widget.required)
                TextButton(
                  onPressed: _notNow,
                  child: const Text('Not now'),
                ),
            ],
          ],
        ),
        body: Column(
          children: [
            if (!_signedIn)
              Container(
                width: double.infinity,
                color: Colors.amber.shade100,
                padding: const EdgeInsets.all(10),
                child: Text(
                  widget.required
                      ? 'Sign in to YouTube to finish setup. Turbo keeps you '
                          'signed in and uses the session wherever a video '
                          'needs it.'
                      : 'Sign in below. Once you are back on YouTube, tap Save.',
                ),
              ),
            Expanded(
              child: _hasWebView
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
                      initialSettings: InAppWebViewSettings(
                        thirdPartyCookiesEnabled: true,
                        // A desktop-ish agent avoids the mobile-web login funnel,
                        // which is fussier and more likely to interpose extra
                        // steps.
                        userAgent:
                            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                            '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
                      ),
                      onLoadStop: (_, __) => _checkSignedIn(),
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'The sign-in page is not available in this build.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
