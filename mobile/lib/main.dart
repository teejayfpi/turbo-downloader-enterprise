import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'link_inbox.dart';
import 'platform_links.dart';
import 'state.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final initial = _urlFromArgs(args);
  runApp(TurboApp(initialUrl: initial));
  // Let a browser extension hand links over through turbo:// on desktop.
  registerProtocolHandler();
}

/// On desktop, the OS may launch the app with a URL as a command-line argument
/// (or via a custom `x-scheme-handler`). Picking it up here means a link opened
/// from any browser reaches the app even before the UI is up.
String? _urlFromArgs(List<String> args) {
  for (final arg in args) {
    final url = extractUrl(arg);
    if (url != null) return url;
  }
  return null;
}

/// The app downloads entirely on the device it runs on. It never asks for a
/// server, an account, or a key: open it and download.
class TurboApp extends StatefulWidget {
  const TurboApp({super.key, this.initialUrl});

  /// A URL the app was launched with, if any.
  final String? initialUrl;

  @override
  State<TurboApp> createState() => _TurboAppState();
}

class _TurboAppState extends State<TurboApp> {
  late final TurboState _state;
  LinkInbox? _inbox;

  @override
  void initState() {
    super.initState();
    _state = TurboState()..init();
    if (widget.initialUrl != null) {
      _state.receiveLink(widget.initialUrl!);
    }
    _inbox = LinkInbox(onLink: _state.receiveLink);
    _inbox!.start();
  }

  @override
  void dispose() {
    _inbox?.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TurboState>.value(
      value: _state,
      child: Consumer<TurboState>(
        builder: (context, state, _) {
          final accent =
              TurboColors.accents[state.accentKey] ?? TurboColors.accent;
          return MaterialApp(
            title: 'Turbo',
            debugShowCheckedModeBanner: false,
            theme: buildTurboTheme(accent),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
