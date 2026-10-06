import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../contact.dart';
import '../credits.dart';
import '../format.dart';
import '../l10n/strings.dart';
import '../services/notifications.dart';
import '../services/session_store.dart';
import '../services/update_checker.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'credentials_screen.dart';
import 'diagnostics_screen.dart';
import 'storage_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Maps the stored byte-per-second cap back to its preset label so the
  /// segmented control shows the right selection.
  static String _bandwidthPresetKey(int limit) {
    for (final entry in TurboState.bandwidthPresets.entries) {
      if (entry.value == limit) return entry.key;
    }
    return 'Unlimited';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = context.palette.accent;
    final strings = TurboStrings.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Section(
          title: 'Device engine',
          accent: accent,
          children: [
            Row(
              children: [
                Icon(Icons.speed_rounded,
                    color: context.palette.textMuted, size: 15),
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
            const _Hint(
              'Segments used for new downloads. Range-capable hosts split the '
              'transfer across these; others fall back to one.',
            ),
            const SizedBox(height: 14),
            const Kicker('Speed mode', letterSpacing: 1.6),
            const SizedBox(height: 8),
            ModeSegment(
              value: state.speedMode == SpeedMode.turbo ? 'turbo' : 'balanced',
              onChanged: (v) => state.setSpeedMode(
                  v == 'turbo' ? SpeedMode.turbo : SpeedMode.balanced),
              options: const [
                ModeSegmentOption(
                    'balanced', Icons.shield_moon_rounded, 'Balanced'),
                ModeSegmentOption('turbo', Icons.bolt_rounded, 'Turbo'),
              ],
            ),
            const SizedBox(height: 6),
            _Hint(state.speedMode == SpeedMode.turbo
                ? 'Turbo splits range-capable downloads across up to 16 '
                    'segments for maximum speed.'
                : 'Balanced uses fewer segments to stay gentle on hosts.'),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.layers_rounded,
                    color: context.palette.textMuted, size: 15),
                const SizedBox(width: 8),
                const Kicker('Simultaneous downloads', letterSpacing: 1.6),
                const Spacer(),
                Text(
                  '${state.maxConcurrent}',
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
              value: state.maxConcurrent.toDouble(),
              min: 1,
              max: 6,
              divisions: 5,
              label: '${state.maxConcurrent}',
              onChanged: (v) => state.setMaxConcurrent(v.round()),
            ),
            const _Hint('How many downloads run at the same time. Extra jobs wait in '
                'the queue.'),
            const SizedBox(height: 16),
            const Kicker('Bandwidth limit', letterSpacing: 1.6),
            const SizedBox(height: 8),
            ModeSegment(
              value: _bandwidthPresetKey(state.bandwidthLimit),
              onChanged: (v) => state.setBandwidthLimit(
                  TurboState.bandwidthPresets[v] ?? 0),
              options: const [
                ModeSegmentOption('Unlimited', Icons.all_inclusive_rounded,
                    'Unlimited'),
                ModeSegmentOption('5 MB/s', Icons.speed_rounded, '5 MB/s'),
                ModeSegmentOption('1 MB/s', Icons.speed_rounded, '1 MB/s'),
                ModeSegmentOption('500 KB/s', Icons.speed_rounded, '500 KB/s'),
              ],
            ),
            const SizedBox(height: 6),
            _Hint(state.bandwidthLimit == 0
                ? 'No cap. Downloads use all the bandwidth the host will give.'
                : 'Caps the total download rate across every transfer, so the '
                    'rest of the device stays responsive.'),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Reliability',
          accent: accent,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.autoRetry,
              onChanged: state.setAutoRetry,
              title: Text('Automatic retry',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: context.palette.textPrimary,
                      fontSize: 13)),
              subtitle: Text(
                'Retry transient failures with exponential backoff.',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textMuted,
                    fontSize: 10.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.wifiOnly,
              onChanged: state.setWifiOnly,
              title: Text('Wi-Fi only',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: context.palette.textPrimary,
                      fontSize: 13)),
              subtitle: Text(
                'Pause transfers when the device is on mobile data.',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textMuted,
                    fontSize: 10.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.batteryAware,
              onChanged: state.setBatteryAware,
              title: Text('Battery aware',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: context.palette.textPrimary,
                      fontSize: 13)),
              subtitle: Text(
                'Pause transfers on a low, unplugged battery.',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textMuted,
                    fontSize: 10.5),
              ),
            ),
            const SizedBox(height: 8),
            if (!state.deviceState.charging || state.deviceState.batteryLevel >= 0)
              _InfoRow(
                label: 'Device',
                value: state.deviceState.batteryLevel >= 0
                    ? '${state.deviceState.onWifi ? 'Wi-Fi' : 'Mobile'} · '
                        '${state.deviceState.batteryLevel}%'
                        '${state.deviceState.charging ? ' · charging' : ''}'
                    : state.deviceState.onWifi
                        ? 'Wi-Fi'
                        : 'Mobile',
              ),
          ],
        ),
        const SizedBox(height: 16),
        _NotificationsSection(state: state),
        const SizedBox(height: 16),
        _Section(
          title: 'Appearance',
          accent: accent,
          children: [
            const Kicker('Theme', letterSpacing: 1.6),
            const SizedBox(height: 8),
            ModeSegment(
              value: state.themeMode.name,
              onChanged: (v) => state.setThemeMode(switch (v) {
                'light' => ThemeMode.light,
                'system' => ThemeMode.system,
                _ => ThemeMode.dark,
              }),
              options: const [
                ModeSegmentOption('system', Icons.brightness_auto_rounded, 'System'),
                ModeSegmentOption('light', Icons.light_mode_rounded, 'Light'),
                ModeSegmentOption('dark', Icons.dark_mode_rounded, 'Dark'),
              ],
            ),
            const SizedBox(height: 14),
            const Kicker('Language', letterSpacing: 1.6),
            const SizedBox(height: 8),
            ModeSegment(
              value: state.localeCode ?? 'system',
              onChanged: (v) => state.setLocale(v == 'system' ? null : v),
              options: [
                const ModeSegmentOption('system', Icons.translate_rounded, 'Auto'),
                for (final entry in TurboStrings.localeNames.entries)
                  ModeSegmentOption(entry.key, Icons.language_rounded,
                      entry.value),
              ],
            ),
            const SizedBox(height: 14),
            const Kicker('Accent colour', letterSpacing: 1.6),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: TurboAccents.all.entries.map((entry) {
                final selected = state.accentKey == entry.key;
                return GestureDetector(
                  onTap: () => state.setAccent(entry.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: entry.value,
                      borderRadius: TurboRadius.all(TurboRadius.sm),
                      border: Border.all(
                        color: selected
                            ? context.palette.textPrimary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded,
                            color: context.palette.isDark
                                ? context.palette.bgPrimary
                                : Colors.white,
                            size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Kicker('Accessibility', letterSpacing: 1.6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.highContrast,
              onChanged: state.setHighContrast,
              title: Text('High contrast',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: context.palette.textPrimary,
                      fontSize: 13)),
              subtitle: Text(
                'Stronger text and border contrast.',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textMuted,
                    fontSize: 10.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.reducedMotion,
              onChanged: state.setReducedMotion,
              title: Text('Reduce motion',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: context.palette.textPrimary,
                      fontSize: 13)),
              subtitle: Text(
                'Limit non-essential animation.',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textMuted,
                    fontSize: 10.5),
              ),
            ),
            Row(
              children: [
                Text('Text size',
                    style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: context.palette.textPrimary,
                        fontSize: 13)),
                const Spacer(),
                Text('${(state.textScale * 100).round()}%',
                    style: TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: accent,
                        fontSize: 12)),
              ],
            ),
            Slider(
              value: state.textScale,
              min: 0.8,
              max: 1.6,
              divisions: 8,
              label: '${(state.textScale * 100).round()}%',
              onChanged: state.setTextScale,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _EngineSection(state: state, accent: accent),
        const SizedBox(height: 16),
        _SessionSection(state: state, accent: accent),
        const SizedBox(height: 16),
        _PrivacySection(state: state, accent: accent),
        const SizedBox(height: 16),
        _StorageSection(state: state, accent: accent),
        const SizedBox(height: 16),
        _UpdatesSection(state: state, accent: accent),
        const SizedBox(height: 16),
        _Section(
          title: strings.diagnosticsTitle,
          accent: accent,
          children: [
            TurboButton(
              label: 'Open diagnostics',
              icon: Icons.bug_report_outlined,
              outline: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AboutSection(strings: strings, accent: accent),
      ],
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  final TurboState state;
  const _NotificationsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Section(
      title: 'Notifications',
      accent: p.accent,
      children: [
        const Kicker('When to notify', letterSpacing: 1.6),
        const SizedBox(height: 8),
        ModeSegment(
          value: state.notifyStyle.name,
          onChanged: (v) => state.setNotifyStyle(switch (v) {
            'off' => NotificationStyle.off,
            'everyDownload' => NotificationStyle.everyDownload,
            _ => NotificationStyle.onQueueComplete,
          }),
          options: const [
            ModeSegmentOption('off', Icons.notifications_off_rounded, 'Off'),
            ModeSegmentOption(
                'onQueueComplete', Icons.done_all_rounded, 'When done'),
            ModeSegmentOption(
                'everyDownload', Icons.notifications_active_rounded, 'Each'),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.notifyProgress,
          onChanged: state.setNotifyProgress,
          title: Text('Show progress',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13)),
          subtitle: Text(
            'Keep a progress notification while downloads run.',
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 10.5),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.playSound,
          onChanged: state.setPlaySound,
          title: Text('Completion sound',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13)),
          subtitle: Text(
            'Play a chime when a download finishes.',
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}

class _StorageSection extends StatelessWidget {
  final TurboState state;
  final Color accent;
  const _StorageSection({required this.state, required this.accent});

  @override
  Widget build(BuildContext context) {
    final stats = state.storageStats;
    return _Section(
      title: 'Storage',
      accent: accent,
      children: [
        _StorageRow(
          icon: Icons.sd_storage_rounded,
          label: 'Available',
          value: stats.freeBytes < 0
              ? 'Unknown'
              : formatBytes(stats.freeBytes),
          warn: stats.isLow || stats.isCritical,
        ),
        _StorageRow(
          icon: Icons.download_done_rounded,
          label: 'Downloaded',
          value: formatBytes(stats.downloadedBytes),
        ),
        _StorageRow(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Temporary',
          value: formatBytes(stats.temporaryBytes),
          detail: stats.partialFileCount > 0
              ? '${stats.partialFileCount} partial file(s)'
              : null,
        ),
        if (stats.isCritical)
          Notice(
            icon: Icons.warning_amber_rounded,
            color: context.palette.error,
            text: TurboStrings.of(context).storageCriticalWarning,
          )
        else if (stats.isLow)
          Notice(
            icon: Icons.warning_amber_rounded,
            color: context.palette.warning,
            text: TurboStrings.of(context).storageLowWarning,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TurboButton(
                label: 'Manage',
                icon: Icons.folder_open_rounded,
                outline: true,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StorageScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TurboButton(
                label: 'Clean up',
                icon: Icons.cleaning_services_rounded,
                onPressed: state.cleanUpPartials,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StorageRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final bool warn;
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: warn ? p.warning : p.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textSecondary,
                        fontSize: 13)),
                if (detail != null)
                  Text(detail!,
                      style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: p.textMuted,
                          fontSize: 9.5)),
              ],
            ),
          ),
          Text(value,
              style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: warn ? p.warning : p.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _UpdatesSection extends StatefulWidget {
  final TurboState state;
  final Color accent;
  const _UpdatesSection({required this.state, required this.accent});

  @override
  State<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends State<_UpdatesSection> {
  Future<void> _install() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await widget.state.installUpdate();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = widget.accent;
    final p = context.palette;
    final update = state.updateAvailable;
    final channel = state.updateChannel;
    return _Section(
      title: 'Updates',
      accent: accent,
      children: [
        _InfoRow(label: 'Channel', value: channel.label),
        const SizedBox(height: 8),
        ModeSegment(
          value: channel.name,
          onChanged: (v) => state.setUpdateChannel(switch (v) {
            'beta' => UpdateChannel.beta,
            'nightly' => UpdateChannel.nightly,
            _ => UpdateChannel.stable,
          }),
          options: const [
            ModeSegmentOption('stable', Icons.verified_rounded, 'Stable'),
            ModeSegmentOption('beta', Icons.science_rounded, 'Beta'),
            ModeSegmentOption('nightly', Icons.nightlight_round, 'Nightly'),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.checkUpdates,
          onChanged: state.setCheckUpdates,
          title: Text('Check on launch',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13)),
          subtitle: Text(
            'Look for a newer release at startup.',
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 10.5),
          ),
        ),
        if (update != null) ...[
          Notice(
            icon: Icons.system_update_alt_rounded,
            color: p.accent,
            text: 'Version ${update.version} is available.',
          ),
          const SizedBox(height: 8),
          if (state.updateInstalling) ...[
            ClipRRect(
              borderRadius: TurboRadius.all(TurboRadius.pill),
              child: LinearProgressIndicator(
                value: state.updateProgress,
                minHeight: 5,
                backgroundColor: p.bgTertiary,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TurboButton(
            label: state.updateInstalling ? 'Downloading…' : 'Download & install',
            icon: Icons.download_rounded,
            onPressed: state.updateInstalling ? null : _install,
          ),
        ] else
          const _InfoRow(label: 'Status', value: 'Up to date (v$appVersion)'),
        const SizedBox(height: 12),
        TurboButton(
          label: 'Check now',
          icon: Icons.refresh_rounded,
          outline: true,
          onPressed: state.checkForUpdates,
        ),
      ],
    );
  }
}

/// Privacy and local-security controls: clipboard watching, metadata
/// stripping, and the credential vault.
class _PrivacySection extends StatelessWidget {
  final TurboState state;
  final Color accent;
  const _PrivacySection({required this.state, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Section(
      title: 'Privacy & security',
      accent: accent,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.clipboardMonitor,
          onChanged: state.setClipboardMonitor,
          title: Text('Watch clipboard for links',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13)),
          subtitle: Text(
            'Offer a copied link in the Add tab. Read only when the app is '
            'open; never uploaded.',
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 10.5),
          ),
        ),
        const SizedBox(height: 8),
        TurboButton(
          label: 'Manage credentials',
          icon: Icons.key_rounded,
          outline: true,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CredentialsScreen()),
          ),
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
    final p = context.palette;
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
          icon: available ? Icons.verified_rounded : Icons.info_outline_rounded,
          color: available ? p.success : p.warning,
          text: available
              ? 'The built-in engine handles direct files and YouTube. yt-dlp '
                  'unlocks other platforms and high-resolution merged '
                  'downloads, all on this device.'
              : 'The built-in engine handles direct files and YouTube, so the '
                  'app already works. Install yt-dlp to download from more '
                  'platforms and in higher resolution.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.preferEngine,
          onChanged: state.setPreferEngine,
          title: Text('Prefer yt-dlp when installed',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13)),
          subtitle: Text(
            'Otherwise YouTube uses the built-in extractor.',
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 10.5),
          ),
        ),
        if (!available) ...[
          const Divider(height: 20),
          const Kicker('Install', letterSpacing: 1.6),
          const SizedBox(height: 8),
          Text(
            _installHint,
            style: TextStyle(
              fontFamily: TurboFonts.mono,
              color: p.textSecondary,
              fontSize: 10.5,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 10),
        TurboButton(
          label: 'Re-check',
          icon: Icons.refresh_rounded,
          outline: true,
          onPressed: state.refreshEngine,
        ),
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

/// The optional signed-in session. Some sites (notably YouTube's bot check)
/// refuse to serve a video unless the request carries a logged-in session.
/// This lets the user supply one — either a cookie file or a local browser
/// profile — and keeps it in the encrypted vault.
class _SessionSection extends StatelessWidget {
  final TurboState state;
  final Color accent;
  const _SessionSection({required this.state, required this.accent});

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _CookieImportDialog(),
    );
    if (text == null) return;
    await state.setSessionCookies(text);
    messenger.showSnackBar(SnackBar(
      content: Text('Session saved (${state.sessionCookieCount} cookies).'),
    ));
  }

  Future<void> _chooseBrowser(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in SessionStore.browsers.entries)
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: Text(entry.value),
                selected: state.sessionBrowser == entry.key,
                onTap: () => Navigator.of(context).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await state.setSessionBrowser(choice);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final configured = state.sessionConfigured;
    final browserName = state.sessionBrowser == null
        ? null
        : SessionStore.browsers[state.sessionBrowser];
    return _Section(
      title: 'Sign-in & cookies',
      accent: accent,
      children: [
        _InfoRow(
          label: 'Session',
          value: configured
              ? (browserName != null
                  ? 'From $browserName'
                  : '${state.sessionCookieCount} cookies')
              : 'Not set',
        ),
        const SizedBox(height: 10),
        Notice(
          icon: configured ? Icons.lock_rounded : Icons.info_outline_rounded,
          color: configured ? p.success : p.textMuted,
          text: configured
              ? 'Downloads carry this session, so bot-checked, age-restricted, '
                  'private, and members-only videos work. It is stored encrypted '
                  'on this device and sent only to the site you download from.'
              : 'Most videos work without this. Add a session only if a site '
                  'asks you to sign in or confirm you are not a bot.',
        ),
        const SizedBox(height: 12),
        TurboButton(
          label: 'Import cookies.txt',
          icon: Icons.file_upload_outlined,
          onPressed: () => _import(context),
        ),
        const SizedBox(height: 8),
        TurboButton(
          label: browserName == null
              ? 'Use a browser profile'
              : 'Browser: $browserName',
          icon: Icons.public_rounded,
          outline: true,
          onPressed: () => _chooseBrowser(context),
        ),
        if (configured) ...[
          const SizedBox(height: 8),
          TurboButton(
            label: 'Clear session',
            icon: Icons.lock_open_rounded,
            outline: true,
            onPressed: state.clearSession,
          ),
        ],
      ],
    );
  }
}

/// Paste-or-drop a cookie jar. Accepts the Netscape `cookies.txt` format that
/// browser extensions export.
class _CookieImportDialog extends StatefulWidget {
  const _CookieImportDialog();

  @override
  State<_CookieImportDialog> createState() => _CookieImportDialogState();
}

class _CookieImportDialogState extends State<_CookieImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = _controller.text;
    final count = SessionStore.countCookies(text);
    return AlertDialog(
      title: const Text('Import cookies'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export cookies for the site from your browser (a '
            '"Get cookies.txt" style extension) and paste the contents here.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            minLines: 4,
            maxLines: 8,
            style: TextStyle(
              fontFamily: TurboFonts.mono,
              fontSize: 11,
              color: p.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t…',
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 8),
            Text('$count cookies detected',
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: p.success,
                  fontSize: 10.5,
                )),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count > 0
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}


class _AboutSection extends StatelessWidget {
  final TurboStrings strings;
  final Color accent;
  const _AboutSection({required this.strings, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Section(
      title: 'About',
      accent: accent,
      children: [
        const _InfoRow(label: 'App', value: 'Turbo Downloader'),
        const _InfoRow(label: 'Version', value: appVersion),
        const _InfoRow(label: 'Designer', value: Designer.name),
        const SizedBox(height: 10),
        Text(
          'Turbo downloads entirely on this device. It opens the connections '
          'itself, saves into your Downloads folder, and needs no server, '
          'account, or key.',
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: p.textMuted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        Divider(color: p.borderSubtle, height: 1),
        const SizedBox(height: 14),
        const Kicker('Designed & engineered by', letterSpacing: 1.6),
        const SizedBox(height: 8),
        const _ContactRow(icon: Icons.person_rounded, value: Designer.name),
        const _ContactRow(
          icon: Icons.email_outlined,
          value: Designer.email,
          copyValue: Designer.email,
        ),
        const SizedBox(height: 12),
        const WhatsAppTile(),
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

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: TurboFonts.body,
          color: context.palette.textMuted,
          fontSize: 10,
          height: 1.45,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textSecondary,
                fontSize: 13,
              )),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: p.textPrimary,
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
    final p = context.palette;
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
      borderRadius: TurboRadius.all(TurboRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: p.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
            if (copyValue != null)
              Icon(Icons.copy_rounded, size: 14, color: p.accent.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}
