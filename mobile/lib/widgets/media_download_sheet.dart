import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media_extractor.dart';
import '../state.dart';
import '../theme.dart';
import 'media_widgets.dart';

/// Inspects [url] in a bottom sheet and lets the user pick a quality before
/// saving it to this device.
///
/// Returns true when a download was queued. Used by the Browse tab so a
/// tapped video can be previewed and confirmed without leaving the page.
Future<bool> showMediaDownloadSheet(
  BuildContext context,
  String url, {
  String? suggestedName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MediaDownloadSheet(url: url, suggestedName: suggestedName),
  );
  return result ?? false;
}

class _MediaDownloadSheet extends StatefulWidget {
  final String url;
  final String? suggestedName;
  const _MediaDownloadSheet({required this.url, this.suggestedName});

  @override
  State<_MediaDownloadSheet> createState() => _MediaDownloadSheetState();
}

class _MediaDownloadSheetState extends State<_MediaDownloadSheet> {
  ProbeResult? _probe;
  MediaFormat? _selectedFormat;
  bool _probing = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspect());
  }

  /// Best rendition the engine can actually produce. HD (video-only) formats
  /// need a muxer, so fall back to the best muxed stream when FFmpeg is
  /// unavailable rather than preselecting something disabled.
  static MediaFormat? _defaultFormat(ProbeResult probe) {
    if (probe.formats.isEmpty) return null;
    for (final f in probe.formats) {
      if (!(f.requiresMux && !probe.canMux)) return f;
    }
    return probe.formats.first;
  }

  Future<void> _inspect() async {
    final state = context.read<TurboState>();
    try {
      final result = await state.probeMedia(widget.url);
      if (!mounted) return;
      setState(() {
        _probe = result;
        _selectedFormat = _defaultFormat(result);
        _probing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MediaResolveException
            ? e.message
            : 'Could not read this page: $e';
        _probing = false;
      });
    }
  }

  void _download() {
    final probe = _probe;
    if (probe == null) return;
    setState(() => _submitting = true);
    final state = context.read<TurboState>();
    final format = _selectedFormat;
    final isYtdlp = probe.usedYtdlp;

    state.addLink(
      widget.url,
      filename: widget.suggestedName,
      engine: isYtdlp ? 'ytdlp' : null,
      mediaInfo: probe,
      formatSelector: isYtdlp ? format?.id : null,
      formatId: isYtdlp ? null : format?.id,
      extensionHint: format?.extension,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final probe = _probe;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: p.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.download_rounded, color: p.accent, size: 18),
                  const SizedBox(width: 8),
                  const Kicker('Save to this device', letterSpacing: 1.6),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        color: p.textMuted, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _probing
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: p.accent),
                          const SizedBox(height: 14),
                          Text(
                            'Inspecting this video…',
                            style: TextStyle(
                              fontFamily: TurboFonts.mono,
                              color: p.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? _ErrorBody(message: _error!)
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            MediaPreviewPanel(info: probe!),
                            const SizedBox(height: 14),
                            FormatPickerPanel(
                              formats: probe.formats,
                              selected: _selectedFormat,
                              canMux: probe.canMux,
                              usedYtdlp: probe.usedYtdlp,
                              onChanged: (f) =>
                                  setState(() => _selectedFormat = f),
                            ),
                            const SizedBox(height: 22),
                            TurboButton(
                              busy: _submitting,
                              onPressed:
                                  probe.formats.isEmpty ? null : _download,
                              icon: Icons.download_rounded,
                              label: 'Download to this device',
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: p.warning, size: 34),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
