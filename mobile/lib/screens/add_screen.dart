import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../format.dart';
import '../media_extractor.dart';
import '../media_url.dart';
import '../state.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    _connections = context.read<TurboState>().defaultConnections;
    _controller.addListener(_onUrlChanged);
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

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      if (mounted) setState(() {});
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
        _selectedFormat =
            result.formats.isNotEmpty ? result.formats.first : null;
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
    );

    if (!mounted) return;
    final wasPage = _isPage;
    setState(() => _submitting = false);
    _reset();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasPage
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
              style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Paste a video, audio, or file link',
                prefixIcon: Icon(
                  isPage ? Icons.auto_awesome_rounded : Icons.link_rounded,
                  color: isPage ? TurboColors.accent : TurboColors.textMuted,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded,
                      color: TurboColors.textMuted, size: 20),
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
            if (_probe != null) ...[
              const SizedBox(height: 14),
              _MediaPreview(info: _probe!),
              const SizedBox(height: 14),
              _FormatPicker(
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
              style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 13),
              decoration: InputDecoration(
                hintText: _probe?.title ?? 'filename.ext',
                prefixIcon: const Icon(Icons.edit_outlined,
                    color: TurboColors.textMuted, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            _SpeedRow(
              connections: _connections,
              mode: state.speedMode,
              onChanged: (v) => setState(() => _connections = v),
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
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sd_storage_rounded,
                    size: 13, color: TurboColors.textMuted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Runs here and saves to your Downloads folder',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: TurboColors.textMuted,
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
            child: const Icon(Icons.bolt_rounded,
                color: TurboColors.bgPrimary, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download anything, anywhere',
                  style: TextStyle(
                    fontFamily: TurboFonts.display,
                    color: TurboColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Paste a video, audio, image, archive, or file link. Turbo '
                  'detects what it is, picks the best quality, and saves it on '
                  'this device.',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: TurboColors.textSecondary,
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
              style: const TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textPrimary,
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

/// Title, author, duration, and thumbnail of an inspected page.
class _MediaPreview extends StatelessWidget {
  final ProbeResult info;
  const _MediaPreview({required this.info});

  @override
  Widget build(BuildContext context) {
    final thumb = info.thumbnailUrl;
    return TurboPanel(
      padding: const EdgeInsets.all(12),
      accentColor: Theme.of(context).colorScheme.primary,
      clip: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 96,
              height: 56,
              color: TurboColors.bgTertiary,
              child: thumb == null
                  ? const Icon(Icons.movie_rounded,
                      color: TurboColors.textMuted)
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.movie_rounded,
                          color: TurboColors.textMuted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: TurboFonts.body,
                    color: TurboColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (info.author != null && info.author!.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          info.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: TurboFonts.body,
                            color: TurboColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (info.durationSeconds != null) ...[
                      const Icon(Icons.schedule_rounded,
                          size: 12, color: TurboColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        formatDuration(info.durationSeconds),
                        style: const TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: TurboColors.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (info.usedYtdlp
                                ? TurboColors.accent
                                : TurboColors.speedUltra)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        info.usedYtdlp ? 'ENGINE · YT-DLP' : 'ENGINE · BUILT-IN',
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: info.usedYtdlp
                              ? TurboColors.accent
                              : TurboColors.speedUltra,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${info.formats.length} formats',
                      style: const TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: TurboColors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of selectable renditions.
class _FormatPicker extends StatelessWidget {
  final List<MediaFormat> formats;
  final MediaFormat? selected;
  final bool canMux;
  final bool usedYtdlp;
  final ValueChanged<MediaFormat> onChanged;

  const _FormatPicker({
    required this.formats,
    required this.selected,
    required this.canMux,
    required this.usedYtdlp,
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
              const Icon(Icons.tune_rounded,
                  color: TurboColors.textMuted, size: 15),
              const SizedBox(width: 8),
              const Kicker('Quality', letterSpacing: 1.6),
              const Spacer(),
              if (!canMux && formats.any((f) => f.requiresMux))
                const Kicker('HD needs ffmpeg', size: 8.5, letterSpacing: 0.8),
            ],
          ),
          const SizedBox(height: 10),
          if (formats.isEmpty)
            const Text(
              'No downloadable formats were listed for this page.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: TurboColors.textMuted,
                fontSize: 11,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: formats.map((f) {
                final isSelected = selected?.id == f.id;
                final disabled = f.requiresMux && !canMux;
                return _FormatChip(
                  format: f,
                  selected: isSelected,
                  disabled: disabled,
                  accent: accent,
                  onTap: disabled ? null : () => onChanged(f),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Text(
            usedYtdlp
                ? 'Powered by the yt-dlp engine on this device. HD options '
                    'merge separate video and audio tracks when ffmpeg is '
                    'available.'
                : 'Resolved on this device. The built-in engine saves a '
                    'combined stream, so quality tops out around 360p/720p.',
            style: const TextStyle(
              fontFamily: TurboFonts.body,
              color: TurboColors.textMuted,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final MediaFormat format;
  final bool selected;
  final bool disabled;
  final Color accent;
  final VoidCallback? onTap;

  const _FormatChip({
    required this.format,
    required this.selected,
    required this.disabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled ? TurboColors.textMuted : accent;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.16) : TurboColors.bgTertiary,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? color : TurboColors.borderSubtle,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    format.isAudio
                        ? Icons.music_note_rounded
                        : Icons.high_quality_rounded,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    format.label,
                    style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: selected
                          ? TurboColors.textPrimary
                          : TurboColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  format.extension.toUpperCase(),
                  if (format.size > 0) formatBytes(format.size),
                  if (format.requiresMux) 'merge',
                ].join(' · '),
                style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speed/connection picker that reflects the current global speed profile.
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
              const Icon(Icons.speed_rounded,
                  color: TurboColors.textMuted, size: 15),
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
              const Icon(Icons.bolt_rounded, size: 12, color: TurboColors.textMuted),
              const SizedBox(width: 5),
              Text(
                'Speed mode: ${mode.label}',
                style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'More connections can be faster, but some hosts limit them. Add '
            'blocks get up to 16 parallel segments, so multi-file downloads run '
            'wide at the same time.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: TurboColors.textMuted,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
