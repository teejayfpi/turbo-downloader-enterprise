import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// First-run screen. Turbo can download entirely on the device, so a server is
/// optional; it is only needed to run or retrieve remote jobs.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Skip server setup and start downloading straight to this device.
  void _useDevice() {
    context.read<TurboState>().setMode('device');
  }

  Future<void> _connect() async {
    final url = TurboState.normalizeUrl(_controller.text);
    if (url.isEmpty) {
      setState(() => _error = 'Enter your server address');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final reachable = await TurboApi(url).ping();
    if (!mounted) return;

    if (!reachable) {
      setState(() {
        _checking = false;
        _error = 'No Turbo server responded at that address';
      });
      return;
    }

    await context.read<TurboState>().setBaseUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.7, -0.9),
            radius: 1.4,
            colors: [accent.withOpacity(0.10), TurboColors.bgPrimary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accent, scheme.secondary],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.bolt_rounded,
                          color: TurboColors.bgPrimary, size: 36),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'TURBO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.display,
                      color: TurboColors.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Kicker(
                    'High-performance download engine',
                    align: TextAlign.center,
                    letterSpacing: 2.2,
                    size: 10,
                  ),
                  const SizedBox(height: 30),
                  TurboButton(
                    onPressed: _useDevice,
                    icon: Icons.phone_android_rounded,
                    label: 'Start on this device',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No account or server needed. Files download to your own '
                    'Downloads folder using this phone\'s connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: TurboColors.textMuted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Row(
                    children: [
                      Expanded(
                          child: Divider(color: TurboColors.borderSubtle)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Kicker('or connect a server', letterSpacing: 1.8),
                      ),
                      Expanded(
                          child: Divider(color: TurboColors.borderSubtle)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _connect(),
                    style: const TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: TurboColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'https://your-server.onrender.com',
                      prefixIcon: Icon(Icons.dns_outlined,
                          color: TurboColors.textMuted, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TurboButton(
                    outline: true,
                    busy: _checking,
                    onPressed: _connect,
                    icon: Icons.link_rounded,
                    label: _checking ? 'Connecting' : 'Connect',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Notice(
                      icon: Icons.error_outline_rounded,
                      color: TurboColors.error,
                      text: _error!,
                    ),
                  ],
                  const SizedBox(height: 30),
                  const Divider(color: TurboColors.borderSubtle, height: 1),
                  const SizedBox(height: 16),
                  const Kicker(
                    'Designed & engineered by ${Designer.name}',
                    align: TextAlign.center,
                    size: 9,
                    letterSpacing: 1.4,
                  ),
                  const SizedBox(height: 6),
                  const Kicker(
                    '${Designer.email}  ·  ${Designer.phone}',
                    align: TextAlign.center,
                    size: 9,
                    letterSpacing: 0.6,
                  ),
                  const SizedBox(height: 10),
                  const Kicker(
                    'v$appVersion',
                    align: TextAlign.center,
                    size: 9,
                    letterSpacing: 1.2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
