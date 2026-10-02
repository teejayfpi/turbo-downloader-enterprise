import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _testing = false;
  bool? _reachable;
  String? _serverInfo;

  @override
  void initState() {
    super.initState();
    _urlController =
        TextEditingController(text: context.read<TurboState>().baseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _reachable = null;
      _serverInfo = null;
    });

    final probe = TurboApi(TurboState.normalizeUrl(_urlController.text));
    final ok = await probe.ping();
    String? info;
    if (ok) {
      try {
        final system = await probe.getSystem();
        final media = system['media'] as Map?;
        info = 'Server ${system['version'] ?? ''}'
            '${media != null && media['available'] == true ? ' · media engine ready' : ''}';
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _reachable = ok;
      _serverInfo = info;
    });
  }

  Future<void> _save() async {
    final state = context.read<TurboState>();
    await state.setBaseUrl(_urlController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.serverConfigured
            ? 'Server updated'
            : 'Server address cleared'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Download location',
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    selected: state.mode == 'device',
                    icon: Icons.phone_android_rounded,
                    title: 'This device',
                    subtitle: 'Uses the phone\'s storage and connection',
                    onTap: () => state.setMode('device'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeButton(
                    selected: state.mode == 'server',
                    icon: Icons.dns_rounded,
                    title: 'Server',
                    subtitle: 'Downloads on your Turbo server',
                    onTap: () => state.setMode('server'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Device downloads keep the file on your phone and never leave '
              'it. Use the server when you want big jobs to survive the app '
              'closing or the phone sleeping.',
              style: TextStyle(
                  color: TurboColors.textMuted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Server',
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              style: const TextStyle(
                  color: TurboColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://your-server.onrender.com',
                prefixIcon: Icon(Icons.cloud_outlined,
                    color: TurboColors.textMuted, size: 20),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Optional. Only needed to browse and start downloads on a Turbo '
              'server. Leave blank to use this device only.',
              style: TextStyle(
                  color: TurboColors.textMuted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('Test'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TurboColors.textPrimary,
                      side: const BorderSide(color: TurboColors.borderSubtle),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (_reachable != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    _reachable! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 16,
                    color: _reachable! ? TurboColors.success : TurboColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _reachable!
                          ? (_serverInfo ?? 'Server reachable')
                          : 'Could not reach that server',
                      style: TextStyle(
                        color: _reachable!
                            ? TurboColors.success
                            : TurboColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Accent colour',
          children: [
            Wrap(
              spacing: 12,
              children: TurboColors.accents.entries.map((entry) {
                final selected = state.accentKey == entry.key;
                return GestureDetector(
                  onTap: () => state.setAccent(entry.key),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? TurboColors.textPrimary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.black, size: 22)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Section(
          title: 'About',
          children: [
            _InfoRow(label: 'App', value: 'Turbo Downloader'),
            _InfoRow(label: 'Version', value: '1.1.0'),
            SizedBox(height: 8),
            Text(
              'Turbo downloads either here on the device or on your Turbo '
              'server. Device downloads use the phone\'s own storage and '
              'connection; server downloads are fetched and merged remotely, '
              'then saved to your phone when you retrieve them.',
              style: TextStyle(
                  color: TurboColors.textMuted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ],
    );
  }
}

/// Selectable card describing one download location.
class _ModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : TurboColors.bgTertiary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? accent : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20, color: selected ? accent : TurboColors.textMuted),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: selected
                    ? TurboColors.textPrimary
                    : TurboColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                  color: TurboColors.textMuted, fontSize: 10, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: TurboColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TurboColors.bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TurboColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: TurboColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: TurboColors.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }
}
