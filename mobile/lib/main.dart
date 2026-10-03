import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TurboApp());
}

/// The app downloads entirely on the device it runs on. It never asks for a
/// server, an account, or a key: open it and download.
class TurboApp extends StatelessWidget {
  const TurboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TurboState()..init(),
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
