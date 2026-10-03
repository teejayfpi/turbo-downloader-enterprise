import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

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
            const SizedBox(height: 14),
            const Kicker('Speed mode', letterSpacing: 1.6),
            const SizedBox(height: 8),
            ModeSegment(
              value: state.speedMode == SpeedMode.turbo ? 'turbo' : 'balanced',
              onChanged: (v) => state.setSpeedMode(
                  v == 'turbo' ? SpeedMode.turbo : SpeedMode.balanced),
              options: const [
                ModeSegmentOption('balanced', Icons.shield_moon_rounded,
                    'Balanced'),
                ModeSegmentOption('turbo', Icons.bolt_rounded, 'Turbo'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              state.speedMode == SpeedMode.turbo
                  ? 'Turbo splits range-capable downloads across up to 16 '
                      'segments for maximum speed.'
                  : 'Balanced uses fewer segments to stay gentle on hosts.',
              style: const TextStyle(
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
        _EngineSection(state: state, accent: accent),
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

/// Shows whether yt-dlp (and ffmpeg) are installed, with install help.
class _EngineSection extends StatelessWidget {
  final TurboState state;
  final Color accent;
  const _EngineSection({required this.state, required this.accent});

  @override
  Widget build(BuildContext context) {
    final available = state.ytdlpAvailable;
    return _Section(
      title: 'Download engine',
      accent: accent,
      children: [
        _InfoRow(
          label: 'yt-dlp',
          value: available ? 'Installed' : 'Not found',
        ),
        if (available)
          _InfoRow(
            label: 'ffmpeg (HD merge)',
            value: state.ytdlpHasFfmpeg ? 'Available' : 'Not installed',
          ),
        const SizedBox(height: 10),
        Notice(
          icon: available
              ? Icons.verified_rounded
              : Icons.info_outline_rounded,
          color: available ? TurboColors.success : TurboColors.warning,
          text: available
              ? 'The built-in engine handles direct files and YouTube. yt-dlp '
                  'unlocks other platforms and high-resolution merged downloads, '
                  'all on this device.'
              : 'The built-in engine handles direct files and YouTube, so the '
                  'app already works. Install yt-dlp to download from more '
                  'platforms and in higher resolution.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.preferEngine,
          onChanged: (v) => state.setPreferEngine(v),
          title: const Text(
            'Prefer yt-dlp when installed',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: TurboColors.textPrimary,
              fontSize: 13,
            ),
          ),
          subtitle: const Text(
            'Otherwise YouTube uses the built-in extractor.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: TurboColors.textMuted,
              fontSize: 10.5,
            ),
          ),
        ),
        if (!available) ...[
          const Divider(height: 20),
          const Kicker('Install', letterSpacing: 1.6),
          const SizedBox(height: 8),
          Text(
            _installHint,
            style: const TextStyle(
              fontFamily: TurboFonts.mono,
              color: TurboColors.textSecondary,
              fontSize: 10.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          TurboButton(
            label: 'Re-check',
            icon: Icons.refresh_rounded,
            outline: true,
            onPressed: state.refreshEngine,
          ),
        ],
      ],
    );
  }

  String get _installHint {
    if (Platform.isWindows) {
      return 'winget install yt-dlp.yt-dlp\n'
          '(ffmpeg optional, for HD merge: winget install Gyan.FFmpeg)';
    }
    if (Platform.isMacOS) {
      return 'brew install yt-dlp\n(ffmpeg optional: brew install ffmpeg)';
    }
    if (Platform.isLinux) {
      return 'sudo apt install yt-dlp\n'
          '(ffmpeg optional: sudo apt install ffmpeg)';
    }
    return 'Install yt-dlp, then tap Re-check.';
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
