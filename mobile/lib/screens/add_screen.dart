import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';

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
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

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
      state.addToDevice(
        _controller.text.trim(),
        filename: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        connections: _connections,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _reset();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading to this device')),
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
        const SnackBar(content: Text('Download added to the server')),
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
      await _probe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final deviceMode = state.mode == 'device';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeSwitch(
              mode: state.mode,
              onChanged: (m) => state.setMode(m),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onFieldSubmitted: (_) => deviceMode ? null : _probe(),
              style: const TextStyle(color: TurboColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: 'https://…',
                labelStyle: const TextStyle(color: TurboColors.textSecondary),
                prefixIcon: const Icon(Icons.link_rounded,
                    color: TurboColors.textMuted),
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
            if (deviceMode) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: TurboColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Save as (optional)',
                  hintText: 'filename.ext',
                  labelStyle: TextStyle(color: TurboColors.textSecondary),
                  prefixIcon: Icon(Icons.edit_outlined,
                      color: TurboColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              _ConnectionPicker(
                value: _connections,
                onChanged: (v) => setState(() => _connections = v),
              ),
            ] else ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _probing ? null : _probe,
                icon: _probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(_probing ? 'Checking…' : 'Check media'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TurboColors.textPrimary,
                  side: const BorderSide(color: TurboColors.borderSubtle),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_probeError != null) ...[
                const SizedBox(height: 12),
                _Notice(
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Icon(
                      deviceMode
                          ? Icons.download_rounded
                          : Icons.cloud_download_rounded,
                      size: 20),
              label: Text(_submitting
                  ? 'Adding…'
                  : deviceMode
                      ? 'Download to this device'
                      : 'Download on the server'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              deviceMode
                  ? 'The phone downloads directly and saves the file to its '
                      'own Downloads folder.'
                  : 'The server downloads the file; retrieve it to your phone '
                      'when it finishes.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: TurboColors.textMuted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control that decides where a download runs.
class _ModeSwitch extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget segment(String value, IconData icon, String label) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? accent : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? accent : TurboColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? TurboColors.textPrimary : TurboColors.textMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Row(
        children: [
          segment('device', Icons.phone_android_rounded, 'This device'),
          const SizedBox(width: 4),
          segment('server', Icons.dns_rounded, 'Server'),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded,
                  color: TurboColors.textMuted, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Parallel connections',
                style: TextStyle(
                    color: TurboColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '$value',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13,
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
            'Servers that do not support ranges fall back to one.',
            style: TextStyle(
                color: TurboColors.textMuted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.thumbnail != null && info.thumbnail!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    info.thumbnail!,
                    width: 84,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 84,
                      height: 52,
                      child: Icon(Icons.movie_rounded,
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
                        color: TurboColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (info.uploader != null) info.uploader!,
                        if (info.duration != null && info.duration! > 0)
                          formatDuration(info.duration),
                      ].join(' · '),
                      style: const TextStyle(
                        color: TurboColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Quality',
            style: TextStyle(
              color: TurboColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...info.formats.map((f) {
            final isSelected = selected?.formatId == f.formatId;
            final isAudioOnly = !f.isVideo;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => onSelect(f),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                        : TurboColors.bgTertiary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : TurboColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.display,
                          style: TextStyle(
                            color: isSelected
                                ? TurboColors.textPrimary
                                : TurboColors.textSecondary,
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isAudioOnly)
                        const Text(
                          'audio',
                          style: TextStyle(
                              color: TurboColors.textMuted, fontSize: 10),
                        ),
                      if (f.filesize > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatBytes(f.filesize),
                          style: const TextStyle(
                              color: TurboColors.textMuted, fontSize: 11),
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
