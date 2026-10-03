import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../credits.dart';
import '../format.dart';
import '../media_url.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class AddScreen extends StatefulWidget {
  const AddScreen({super.key});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  MediaInfo? _info;
  MediaFormat? _selectedFormat;
  bool _probing = false;
  bool _submitting = false;
  String? _probeError;
  int _connections = 4;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUrlChanged);
    _connections = context.read<TurboState>().defaultConnections;
  }

  void _onUrlChanged() {
    // Rebuild so the media hint appears/disappears while typing.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUrlChanged);
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _mediaHint => isMediaUrl(_controller.text);

  Future<void> _probe() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _probing = true;
      _probeError = null;
      _info = null;
      _selectedFormat = null;
    });

    try {
      final state = context.read<TurboState>();
      final info = await state.api.getMediaInfo(url);
      setState(() {
        _info = info;
        // Default to the highest-quality progressive stream. A "video only"
        // entry cannot be played on its own, and the server withholds separate
        // HD streams from datacenter IPs, so it is not a safe default.
        final progressive = info.formats.where((f) => f.isProgressive).toList();
        if (progressive.isNotEmpty) {
          progressive.sort((a, b) => b.height.compareTo(a.height));
          _selectedFormat = progressive.first;
        } else if (info.formats.isNotEmpty) {
          _selectedFormat = info.formats.first;
        }
      });
    } on ApiException catch (e) {
      setState(() => _probeError = e.message);
    } finally {
      setState(() => _probing = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final state = context.read<TurboState>();

    // Device mode stores the file on the phone; server mode queues it remotely.
    if (state.mode == 'device') {
      final url = _controller.text.trim();
      final isMedia = isMediaUrl(url);
      state.addToDevice(
        url,
        filename: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        connections: _connections,
        kind: isMedia ? 'media' : 'http',
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _reset();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMedia
                ? 'Resolving and downloading on this device · saved to Downloads'
                : 'Downloading to this device · saved to Downloads',
          ),
        ),
      );
      return;
    }

    final error = await state.add(
      _controller.text.trim(),
      formatId: _selectedFormat?.formatId,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      _reset();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download queued on the server')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  void _reset() {
    setState(() {
      _info = null;
      _selectedFormat = null;
      _probeError = null;
    });
    _controller.clear();
    _nameController.clear();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      if (isMediaUrl(text)) {
        await _probe();
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final deviceMode = state.mode == 'device';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ModeSegment(
              value: state.mode,
              onChanged: (m) => state.setMode(m),
              options: const [
                ModeSegmentOption(
                    'device', Icons.phone_android_rounded, 'This device'),
                ModeSegmentOption('server', Icons.dns_rounded, 'Server'),
              ],
            ),
            const SizedBox(height: 18),
            const Kicker('Target URL', letterSpacing: 2.0),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) {
                if (!deviceMode && _mediaHint) _probe();
              },
              style: const TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textPrimary,
                  fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://example.com/file.zip',
                prefixIcon: const Icon(Icons.link_rounded,
                    color: TurboColors.textMuted, size: 20),
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
            if (deviceMode && isMediaUrl(_controller.text)) const _MediaHint(),
            if (deviceMode) ...[
              const SizedBox(height: 18),
              const Kicker('Save as (optional)', letterSpacing: 2.0),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: TurboColors.textPrimary,
                    fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'filename.ext',
                  prefixIcon: Icon(Icons.edit_outlined,
                      color: TurboColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              _ConnectionPicker(
                value: _connections,
                onChanged: (v) => setState(() => _connections = v),
              ),
            ] else ...[
              const SizedBox(height: 16),
              if (isYouTubeUrl(_controller.text)) ...[
                const Notice(
                  icon: Icons.warning_amber_rounded,
                  color: TurboColors.warning,
                  text: 'YouTube may refuse to serve the video from a hosted '
                      'server unless cookies are configured. If the download '
                      'fails with "403" or "Sign in to confirm", the server '
                      'needs YT_DLP_COOKIES_DATA set.',
                ),
                const SizedBox(height: 12),
              ] else if (_mediaHint)
                const Notice(
                  icon: Icons.movie_rounded,
                  color: TurboColors.accent,
                  text: 'Media page detected. Use Check media to list the '
                      'available video and audio streams before downloading.',
                ),
              const SizedBox(height: 12),
              TurboButton(
                outline: true,
                busy: _probing,
                onPressed: _probe,
                icon: Icons.travel_explore_rounded,
                label: _probing ? 'Probing' : 'Check media',
              ),
              if (_probeError != null) ...[
                const SizedBox(height: 12),
                Notice(
                  icon: Icons.info_outline_rounded,
                  color: TurboColors.warning,
                  text: '$_probeError\n\n'
                      'This is normal for direct file links. You can still '
                      'download it as a regular file.',
                ),
              ],
              if (_info != null) ...[
                const SizedBox(height: 16),
                _MediaCard(
                  info: _info!,
                  selected: _selectedFormat,
                  onSelect: (f) => setState(() => _selectedFormat = f),
                ),
              ],
            ],
            const SizedBox(height: 22),
            TurboButton(
              busy: _submitting,
              onPressed: _submit,
              icon: deviceMode
                  ? Icons.download_rounded
                  : Icons.cloud_download_rounded,
              label: _submitting
                  ? 'Adding'
                  : deviceMode
                      ? 'Download to this device'
                      : 'Download on the server',
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  deviceMode ? Icons.sd_storage_rounded : Icons.cloud_rounded,
                  size: 13,
                  color: TurboColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    deviceMode
                        ? 'Runs on this phone, stored in your Downloads folder'
                        : 'Fetched by the server, retrieve it to your phone later',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
              child: Kicker('Eng. by ${Designer.name}', size: 9, letterSpacing: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a media page is pasted in device mode, which now resolves the
/// page on the phone and stores the file locally. It sets the expectation that
/// a combined stream is used because a phone cannot mux separate HD tracks.
class _MediaHint extends StatelessWidget {
  const _MediaHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurboColors.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: TurboColors.accent.withOpacity(0.4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.movie_rounded, color: TurboColors.accent, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Downloading on this device',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: TurboColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'The video is resolved and saved on your phone using its own '
                  'storage and connection — nothing is stored on the server. A '
                  'combined audio+video stream is used, so quality tops out '
                  'around 360p/720p.',
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: TurboColors.textSecondary,
                      fontSize: 11.5,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the user trade speed for server politeness in device mode.
class _ConnectionPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ConnectionPicker({required this.value, required this.onChanged});

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
                '$value',
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
            value: value.toDouble(),
            min: 1,
            max: 16,
            divisions: 15,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
          const Text(
            'More connections can be faster but some servers limit them. '
            'Hosts that do not support ranges fall back to one.',
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

class _MediaCard extends StatelessWidget {
  final MediaInfo info;
  final MediaFormat? selected;
  final ValueChanged<MediaFormat> onSelect;

  const _MediaCard({
    required this.info,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return TurboPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.thumbnail != null && info.thumbnail!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    info.thumbnail!,
                    width: 92,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 92,
                      height: 56,
                      color: TurboColors.bgTertiary,
                      child: const Icon(Icons.movie_rounded,
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: TurboFonts.body,
                        color: TurboColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Kicker(
                      [
                        if (info.uploader != null) info.uploader!,
                        if (info.duration != null && info.duration! > 0)
                          formatDuration(info.duration),
                      ].join(' · '),
                      size: 9,
                      letterSpacing: 0.8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Kicker('Quality', letterSpacing: 1.8),
          const SizedBox(height: 8),
          ...info.formats.map((f) {
            final isSelected = selected?.formatId == f.formatId;
            final isAudioOnly = !f.isVideo;
            final accent = Theme.of(context).colorScheme.primary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => onSelect(f),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withOpacity(0.12)
                        : TurboColors.bgTertiary,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? accent : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 17,
                        color: isSelected ? accent : TurboColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.display,
                          style: TextStyle(
                            fontFamily: TurboFonts.body,
                            color: isSelected
                                ? TurboColors.textPrimary
                                : TurboColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isAudioOnly)
                        const Text(
                          'audio',
                          style: TextStyle(
                            fontFamily: TurboFonts.mono,
                            color: TurboColors.textMuted,
                            fontSize: 9.5,
                          ),
                        ),
                      if (f.filesize > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatBytes(f.filesize),
                          style: const TextStyle(
                            fontFamily: TurboFonts.mono,
                            color: TurboColors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
