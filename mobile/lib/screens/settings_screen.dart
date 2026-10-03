import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
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
              'Segments used for new downloads. Range-capable hosts split the '
              'transfer across these; others fall back to one.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 10,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.playSound,
              onChanged: (v) => state.setPlaySound(v),
              title: const Text(
                'Completion sound',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textPrimary,
                  fontSize: 13,
                ),
              ),
              subtitle: const Text(
                'Play a chime when a download finishes.',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ),
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
              'Turbo downloads entirely on this device. It opens the '
              'connections itself, saves into your Downloads folder, and needs '
              'no server, account, or key.',
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
            _ContactRow(icon: Icons.person_rounded, value: Designer.name),
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
