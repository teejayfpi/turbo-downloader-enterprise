import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../credits.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _testing = false;
  bool? _reachable;
  String? _serverInfo;

  @override
  void initState() {
    super.initState();
    final state = context.read<TurboState>();
    _urlController = TextEditingController(text: state.baseUrl);
    _tokenController = TextEditingController(text: state.apiToken);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _reachable = null;
      _serverInfo = null;
    });

    final probe = TurboApi(
      TurboState.normalizeUrl(_urlController.text),
      apiToken: _tokenController.text.trim(),
    );
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
    await state.setApiToken(_tokenController.text);
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
    final accent = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Section(
          title: 'Download location',
          accent: accent,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    selected: state.mode == 'device',
                    icon: Icons.phone_android_rounded,
                    title: 'This device',
                    subtitle: 'Uses the phone\'s storage and bandwidth',
                    accent: accent,
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
                    accent: accent,
                    onTap: () => state.setMode('server'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Device downloads keep the file on your phone and never leave it. '
              'Use the server when you want large jobs to survive the app being '
              'closed or the phone sleeping.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Device engine',
          accent: accent,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded,
                    color: TurboColors.textMuted, size: 15),
                const SizedBox(width: 8),
                const Kicker('Default connections', letterSpacing: 1.6),
                const Spacer(),
                Text(
                  '${state.defaultConnections}',
                  style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              value: state.defaultConnections.toDouble(),
              min: 1,
              max: 16,
              divisions: 15,
              label: '${state.defaultConnections}',
              onChanged: (v) => state.setDefaultConnections(v.round()),
            ),
            const Text(
              'Segments used for new device downloads. Range-capable hosts '
              'split the transfer across these; others fall back to one.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Server',
          accent: accent,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://your-server.onrender.com',
                prefixIcon: Icon(Icons.cloud_outlined,
                    color: TurboColors.textMuted, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Optional. Only needed to browse and start downloads on a Turbo '
              'server. Leave blank to use this device only.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: true,
              style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Access token (if the server requires one)',
                prefixIcon: Icon(Icons.key_rounded,
                    color: TurboColors.textMuted, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only needed when the server was started with a TURBO_API_TOKEN. '
              'Leave blank for open servers.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TurboButton(
                    outline: true,
                    busy: _testing,
                    onPressed: _test,
                    icon: Icons.wifi_tethering_rounded,
                    label: 'Test',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TurboButton(
                    onPressed: _save,
                    icon: Icons.save_rounded,
                    label: 'Save',
                  ),
                ),
              ],
            ),
            if (_reachable != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _reachable!
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 16,
                    color: _reachable!
                        ? TurboColors.success
                        : TurboColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _reachable!
                          ? (_serverInfo ?? 'Server reachable')
                          : 'Could not reach that server',
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
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
          accent: accent,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: TurboColors.accents.entries.map((entry) {
                final selected = state.accentKey == entry.key;
                return GestureDetector(
                  onTap: () => state.setAccent(entry.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: entry.value,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? TurboColors.textPrimary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: TurboColors.bgPrimary, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'About',
          accent: accent,
          children: const [
            _InfoRow(label: 'App', value: 'Turbo Downloader'),
            _InfoRow(label: 'Version', value: appVersion),
            _InfoRow(label: 'Designer', value: Designer.name),
            SizedBox(height: 10),
            Text(
              'Turbo downloads either on the device or on your Turbo server. '
              'Device downloads run entirely on your phone and save straight to '
              'your Downloads folder; server downloads are fetched and merged '
              'remotely, then saved to your phone when you retrieve them.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            SizedBox(height: 14),
            Divider(color: TurboColors.borderSubtle, height: 1),
            SizedBox(height: 14),
            Kicker('Designed & engineered by', letterSpacing: 1.6),
            SizedBox(height: 8),
            _ContactRow(
              icon: Icons.person_rounded,
              value: Designer.name,
            ),
            _ContactRow(
              icon: Icons.email_outlined,
              value: Designer.email,
              copyValue: Designer.email,
            ),
            _ContactRow(
              icon: Icons.phone_outlined,
              value: Designer.phone,
              copyValue: Designer.phoneHref,
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
  final Color accent;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : TurboColors.bgTertiary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: selected ? accent.withOpacity(0.7) : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 19, color: selected ? accent : TurboColors.textMuted),
            const SizedBox(height: 9),
            Text(
              title,
              style: TextStyle(
                fontFamily: TurboFonts.body,
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
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 10,
                height: 1.35,
              ),
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
  final Color accent;
  const _Section({
    required this.title,
    required this.children,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Kicker(title, letterSpacing: 2.0),
        ),
        TurboPanel(
          padding: const EdgeInsets.all(14),
          accentColor: accent,
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textSecondary,
                fontSize: 13,
              )),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: TurboFonts.mono,
                color: TurboColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A read-only contact line that copies its value to the clipboard on tap.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? copyValue;

  const _ContactRow({
    required this.icon,
    required this.value,
    this.copyValue,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: copyValue == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: copyValue!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied $value')),
                );
              }
            },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: TurboColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
            if (copyValue != null)
              Icon(Icons.copy_rounded, size: 14, color: accent.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}
