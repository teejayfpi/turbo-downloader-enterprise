import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../media_url.dart';
import '../state.dart';
import '../theme.dart';

/// The only place a download starts. There is no mode switch any more: every
/// job runs on this device, whether it is a direct file or a media page.
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

  bool get _isMedia => isMediaUrl(_controller.text);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final state = context.read<TurboState>();
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
              ? 'Resolving and saving to this device\'s Downloads'
              : 'Saving to this device\'s Downloads',
        ),
      ),
    );
  }

  void _reset() {
    _controller.clear();
    _nameController.clear();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Kicker('Target URL', letterSpacing: 2.0),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) {
                if (!_submitting) _submit();
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
            if (_isMedia) const _MediaHint(),
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
            const SizedBox(height: 22),
            TurboButton(
              busy: _submitting,
              onPressed: _submit,
              icon: Icons.download_rounded,
              label: _submitting ? 'Adding' : 'Download to this device',
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

/// Shown when a media page is pasted. It sets the expectation that a combined
/// stream is used, because a device cannot mux separate HD tracks.
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
                  'The video is resolved and saved on this device using its own '
                  'storage and connection. A combined audio+video stream is '
                  'used, so quality tops out around 360p/720p.',
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

/// Lets the user trade speed for server politeness.
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
