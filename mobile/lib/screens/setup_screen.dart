import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';

/// First-run screen. Turbo is a client for a server the user runs (or was
/// given), so the app must be told where that server lives before it can do
/// anything useful.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;
  bool _ok = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      _ok = false;
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.bolt_rounded, size: 64, color: accent),
                const SizedBox(height: 12),
                const Text(
                  'Turbo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TurboColors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect to your download server',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: TurboColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _connect(),
                  style: const TextStyle(color: TurboColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'https://your-server.onrender.com',
                    prefixIcon: Icon(Icons.dns_outlined,
                        color: TurboColors.textMuted, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _checking ? null : _connect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text(
                          'Connect',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: TurboColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: TurboColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_ok) ...[
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: TurboColors.success, size: 16),
                      SizedBox(width: 8),
                      Text('Connected',
                          style: TextStyle(
                              color: TurboColors.success, fontSize: 12)),
                    ],
                  ),
                ],
                const SizedBox(height: 26),
                const Text(
                  'Run your own server with the Turbo Docker image, or use one '
                  'you were given. You can change this address later in '
                  'Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: TurboColors.textMuted, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
