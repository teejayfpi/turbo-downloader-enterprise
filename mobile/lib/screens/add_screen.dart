import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../contact.dart';
import '../credits.dart';
import '../format.dart';
import '../media_extractor.dart';
import '../media_url.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/access_widgets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/schedule_sheet.dart';
import '../link_inbox.dart' show extractUrl;

/// The only place a download starts. There is no mode switch: every job runs on
/// this device. Media pages are detected, inspected, and offered with a format
/// picker before the transfer is queued.
class AddScreen extends StatefulWidget {
  const AddScreen({super.key});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  bool _probing = false;
  int _connections = 4;

  /// Result of inspecting the pasted media page.
  ProbeResult? _probe;
  MediaFormat? _selectedFormat;

  /// Set when a URL looks like media but has not been inspected yet.
  bool _mediaReadyToInspect = false;

  /// True when a paste looked like a link buried in other text.
  bool _pastedExtracted = false;

  /// A link found on the clipboard when the app opened, offered as a shortcut.
  String? _clipboardUrl;

  /// When set, the queued download waits until this time. Null starts it now.
  DateTime? _startAt;

  @override
  void initState() {
    super.initState();
    _connections = context.read<TurboState>().defaultConnections;
    _controller.addListener(_onUrlChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  /// Looks at the clipboard once on open, when the user has opted in. If it
  /// holds a link, offer a one-tap way to use it — the fastest path when a URL
  /// was copied from a browser.
  Future<void> _checkClipboard() async {
    if (!context.read<TurboState>().clipboardMonitor) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = extractUrl(data?.text ?? '');
    if (!mounted || url == null) return;
    setState(() => _clipboardUrl = url);
  }

  Future<void> _useClipboard() async {
    final url = _clipboardUrl;
    if (url == null) return;
    setState(() {
      _clipboardUrl = null;
      _controller.text = url;
    });
    if (needsExtraction(url)) await _inspect();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumePending();
  }

  /// Pick up a link that arrived from outside the app (deep link, share sheet,
  /// drop, or a launch argument) and inspect it immediately.
  void _consumePending() {
    final state = context.read<TurboState>();
    if (state.pendingUrl == null) return;
    final url = state.takePendingLink();
    if (url == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.text = url;
      if (needsExtraction(url)) unawaited(_inspect());
    });
  }

  void _onUrlChanged() {
    final url = _controller.text.trim();
    final wasMedia = _mediaReadyToInspect;
    final isMedia = needsExtraction(url);
    if (isMedia != wasMedia) {
      // URL changed shape: drop stale metadata and re-evaluate.
      _probe = null;
      _selectedFormat = null;
      _mediaReadyToInspect = isMedia;
    } else if (wasMedia && _probe != null) {
      // Any edit invalidates a previous inspection.
      _probe = null;
      _selectedFormat = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUrlChanged);
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _isPage => needsExtraction(_controller.text);

  /// Default pick: the best rendition the engine can actually produce. HD
  /// (video-only) formats need a muxer, so fall back to the best muxed stream
  /// when FFmpeg is unavailable rather than preselecting something disabled.
  static MediaFormat? _defaultFormat(ProbeResult probe) {
    if (probe.formats.isEmpty) return null;
    for (final f in probe.formats) {
      if (!(f.requiresMux && !probe.canMux)) return f;
    }
    return probe.formats.first;
  }

  /// Reads whatever the clipboard holds and pulls a URL out of it, so a link
  /// copied alongside other text still lands cleanly in the field.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    final url = extractUrl(text);
    _controller.text = url ?? text;
    if (!mounted) return;
    setState(() => _pastedExtracted = url != null && url != text);
    if (url != null && needsExtraction(url)) {
      await _inspect();
    }
  }

  Future<void> _inspect() => _inspectWith(context.read<TurboState>());

  Future<void> _inspectWith(TurboState state) async {
    final url = _controller.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    setState(() => _probing = true);
    try {
      final result = await state.probeMedia(url);
      if (!mounted) return;
      setState(() {
        _probe = result;
        _selectedFormat = _defaultFormat(result);
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is MediaResolveException
          ? e.message
          : 'Could not read this page: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isPage && _probe == null) {
      final state = context.read<TurboState>();
      // Force an inspection first so the user gets a format choice.
      await _inspectWith(state);
      if (!mounted || _probe == null) return;
    }
    setState(() => _submitting = true);

    final state = context.read<TurboState>();
    final url = _controller.text.trim();
    final probe = _probe;
    final format = _selectedFormat;

    final isYtdlpFormat = probe?.usedYtdlp ?? false;
    final engine = isYtdlpFormat ? 'ytdlp' : null;
    final nameField = _nameController.text.trim();

    state.addLink(
      url,
      filename: nameField.isEmpty ? null : nameField,
      connections: _connections,
      engine: engine,
      mediaInfo: probe,
      formatSelector: isYtdlpFormat ? format?.id : null,
      formatId: isYtdlpFormat ? null : format?.id,
      extensionHint: format?.extension,
      startAt: _startAt,
    );

    if (!mounted) return;
    final wasPage = _isPage;
    final wasScheduled = _startAt != null;
    final scheduledAt = _startAt;
    setState(() => _submitting = false);
    _reset();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasScheduled
              ? 'Scheduled for ${formatStartAt(scheduledAt)}'
              : wasPage
                  ? 'Resolving and saving to this device\'s Downloads'
                  : 'Saving to this device\'s Downloads',
        ),
      ),
    );
  }

  void _reset() {
    _controller.clear();
    _nameController.clear();
    _probe = null;
    _selectedFormat = null;
    _mediaReadyToInspect = false;
    _startAt = null;
  }

  /// Opens the schedule sheet and applies the chosen start time.
  Future<void> _pickSchedule() async {
    final picked = await showScheduleSheet(context, initial: _startAt);
    // A null return means the sheet was dismissed; the sheet sends an explicit
    // epoch value to mean "start now".
    if (picked == null) return;
    setState(() => _startAt = picked == startNowSentinel ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final isPage = _isPage;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(),
            const SizedBox(height: 18),
            const Kicker('Link or file URL', letterSpacing: 2.0),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onFieldSubmitted: (_) {
                if (isPage && _probe == null) {
                  _inspect();
                } else if (!_submitting) {
                  _submit();
                }
              },
              style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: context.palette.textPrimary,
                  fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Paste a video, audio, or file link',
                prefixIcon: Icon(
                  isPage ? Icons.auto_awesome_rounded : Icons.link_rounded,
                  color: isPage ? context.palette.accent : context.palette.textMuted,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: Icon(Icons.content_paste_rounded,
                      color: context.palette.textMuted, size: 20),
                  onPressed: _paste,
                ),
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Enter a URL';
                final uri = Uri.tryParse(value);
                if (uri == null ||
                    !uri.hasScheme ||
                    !(uri.isScheme('http') || uri.isScheme('https'))) {
                  return 'Enter a valid http(s) URL';
                }
                return null;
              },
            ),
            if (_clipboardUrl != null && !_isPage) ...[
              const SizedBox(height: 10),
              Notice(
                icon: Icons.content_paste_go_rounded,
                color: context.palette.success,
                text: 'Link on your clipboard: ${_clipboardUrl!}',
                trailing: TextButton(
                  onPressed: _useClipboard,
                  child: const Text('USE'),
                ),
              ),
            ],
            // Auto-detect badge.
            if (isPage) ...[
              const SizedBox(height: 10),
              _DetectionBanner(
                url: _controller.text.trim(),
                probing: _probing,
                inspected: _probe != null,
                onInspect: _inspect,
              ),
            ],
            if (_pastedExtracted) ...[
              const SizedBox(height: 10),
              Notice(
                icon: Icons.content_paste_search_rounded,
                color: context.palette.speedUltra,
                text: 'Found a link in your clipboard and used it.',
              ),
            ],
            if (_probe != null) ...[
              const SizedBox(height: 14),
              MediaPreviewPanel(info: _probe!),
              const SizedBox(height: 14),
              FormatPickerPanel(
                formats: _probe!.formats,
                selected: _selectedFormat,
                canMux: _probe!.canMux,
                usedYtdlp: _probe!.usedYtdlp,
                onChanged: (f) => setState(() => _selectedFormat = f),
              ),
            ],
            const SizedBox(height: 18),
            const Kicker('Save as (optional)', letterSpacing: 2.0),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: context.palette.textPrimary,
                  fontSize: 13),
              decoration: InputDecoration(
                hintText: _probe?.title ?? 'filename.ext',
                prefixIcon: Icon(Icons.edit_outlined,
                    color: context.palette.textMuted, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            _SpeedRow(
              connections: _connections,
              mode: state.speedMode,
              onChanged: (v) => setState(() => _connections = v),
            ),
            const SizedBox(height: 14),
            _ScheduleRow(
              startAt: _startAt,
              locked: !state.canSchedule,
              onTap: _pickSchedule,
              onLockedTap: () => showLicenceDialog(context),
              onClear: () => setState(() => _startAt = null),
            ),
            const SizedBox(height: 22),
            TurboButton(
              busy: _submitting || _probing,
              onPressed: _submit,
              icon: isPage
                  ? Icons.auto_awesome_rounded
                  : Icons.download_rounded,
              label: _probing
                  ? 'Inspecting'
                  : (isPage && _probe == null
                      ? 'Inspect & download'
                      : 'Download to this device'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sd_storage_rounded,
                    size: 13, color: context.palette.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Runs here and saves to your Downloads folder',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: context.palette.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.3,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Center(
              child: Kicker('Eng. by ${Designer.name}',
                  size: 9, letterSpacing: 1.4),
            ),
            const SizedBox(height: 12),
            const WhatsAppTile(
              label: 'Need help? Chat with the designer',
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact headline that explains the app in one line.
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TurboPanel(
      padding: const EdgeInsets.all(16),
      accentColor: accent,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withOpacity(0.9), accent.withOpacity(0.35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.bolt_rounded,
                color: context.palette.bgPrimary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download anything, anywhere',
                  style: TextStyle(
                    fontFamily: TurboFonts.display,
                    color: context.palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paste a video, audio, image, archive, or file link. Turbo '
                  'detects what it is, picks the best quality, and saves it on '
                  'this device.',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textSecondary,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows that a page was auto-detected and offers to inspect it.
class _DetectionBanner extends StatelessWidget {
  final String url;
  final bool probing;
  final bool inspected;
  final VoidCallback onInspect;

  const _DetectionBanner({
    required this.url,
    required this.probing,
    required this.inspected,
    required this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final platform = isYouTubeUrl(url)
        ? 'YouTube'
        : (isMediaUrl(url) ? 'a media site' : 'a media page');
    final label = inspected
        ? 'Media detected — formats ready'
        : 'Media detected on $platform';

    return TurboPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      accentColor: accent,
      child: Row(
        children: [
          Icon(
            inspected
                ? Icons.check_circle_rounded
                : Icons.auto_awesome_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: context.palette.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!inspected)
            TextButton.icon(
              onPressed: probing ? null : onInspect,
              icon: probing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search_rounded, size: 16),
              label: Text(probing ? 'Reading' : 'Choose quality'),
            ),
        ],
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  final int connections;
  final SpeedMode mode;
  final ValueChanged<int> onChanged;

  const _SpeedRow({
    required this.connections,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TurboPanel(
      padding: const EdgeInsets.all(14),
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded,
                  color: context.palette.textMuted, size: 15),
              const SizedBox(width: 8),
              const Kicker('Parallel connections', letterSpacing: 1.6),
              const Spacer(),
              Text(
                '$connections',
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
            value: connections.toDouble().clamp(1, 16),
            min: 1,
            max: 16,
            divisions: 15,
            label: '$connections',
            onChanged: (v) => onChanged(v.round()),
          ),
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 12, color: context.palette.textMuted),
              const SizedBox(width: 5),
              Text(
                'Speed mode: ${mode.label}',
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: context.palette.textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'More connections can be faster, but some hosts limit them. Add '
            'blocks get up to 16 parallel segments, so multi-file downloads run '
            'wide at the same time.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: context.palette.textMuted,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable row that shows the pending start time and opens the scheduler.
/// When [locked] the row advertises the Pro tier and opens the licence dialog.
class _ScheduleRow extends StatelessWidget {
  final DateTime? startAt;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onLockedTap;
  final VoidCallback onClear;

  const _ScheduleRow({
    required this.startAt,
    required this.onTap,
    required this.onLockedTap,
    required this.onClear,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheduled = startAt != null;
    final tone = locked ? p.warning : p.accent;
    return TurboPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      accentColor: tone,
      child: Row(
        children: [
          Icon(
            locked
                ? Icons.lock_outline_rounded
                : scheduled
                    ? Icons.event_available_rounded
                    : Icons.schedule_rounded,
            color: locked || scheduled ? tone : p.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('Start time', letterSpacing: 1.6),
                const SizedBox(height: 2),
                Text(
                  locked
                      ? 'Scheduling is a Pro feature'
                      : scheduled
                          ? 'Queued — starts ${formatStartAt(startAt)}'
                          : 'Starts as soon as a slot is free',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: locked || scheduled ? tone : p.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (scheduled && !locked)
            IconButton(
              tooltip: 'Start now',
              icon: Icon(Icons.close_rounded, color: p.textMuted, size: 18),
              onPressed: onClear,
            ),
          TextButton(
            onPressed: locked ? onLockedTap : onTap,
            child: Text(
              locked
                  ? 'Unlock'
                  : scheduled
                      ? 'Change'
                      : 'Schedule',
            ),
          ),
        ],
      ),
    );
  }
}

