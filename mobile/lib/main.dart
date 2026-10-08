import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'link_inbox.dart';
import 'l10n/strings.dart';
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

class _TurboAppState extends State<TurboApp> with WidgetsBindingObserver {
  late final TurboState _state;
  LinkInbox? _inbox;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = TurboState()..init();
    if (widget.initialUrl != null) {
      _state.receiveLink(widget.initialUrl!);
    }
    _inbox = LinkInbox(onLink: _state.receiveLink);
    _inbox!.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A hard kill gives no shutdown callback, so persist the per-host speed
    // memory as soon as the app leaves the foreground.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_state.local.flushHostMemory());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_state.local.flushHostMemory());
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
          final accent = TurboAccents.of(state.accentKey);
          return MaterialApp(
            title: 'Turbo',
            debugShowCheckedModeBanner: false,
            theme: buildTurboTheme(
              accent,
              brightness: Brightness.light,
              highContrast: state.highContrast,
            ),
            darkTheme: buildTurboTheme(
              accent,
              brightness: Brightness.dark,
              highContrast: state.highContrast,
            ),
            themeMode: state.themeMode,
            locale: state.localeCode == null
                ? null
                : Locale(state.localeCode!),
            supportedLocales: TurboStrings.supportedLocales,
            localizationsDelegates: const [
              TurboStringsDelegate(),
            ],
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(
                    media.textScaler.scale(1) * state.textScale,
                  ),
                  disableAnimations: state.reducedMotion,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
