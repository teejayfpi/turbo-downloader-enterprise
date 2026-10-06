import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../state.dart';
import '../theme.dart';

/// Opens the licence-key dialog. Returns true when a key was accepted.
Future<bool> showLicenceDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _LicenceDialog(),
  );
  return result ?? false;
}

class _LicenceDialog extends StatefulWidget {
  const _LicenceDialog();

  @override
  State<_LicenceDialog> createState() => _LicenceDialogState();
}

class _LicenceDialogState extends State<_LicenceDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<TurboState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await state.activateLicence(_controller.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.bgSecondary,
      title: Text(
        'Activate Pro',
        style: TextStyle(
          fontFamily: TurboFonts.display,
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste the licence key you were given. It is checked on this '
            'device — nothing is sent anywhere.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(
              fontFamily: TurboFonts.mono,
              color: p.textPrimary,
              fontSize: 12,
            ),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(
              hintText: 'eyJ2Ijox…',
              errorText: _error,
              prefixIcon:
                  Icon(Icons.key_rounded, color: p.textMuted, size: 20),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Checking…' : 'Activate'),
        ),
      ],
    );
  }
}

/// A slim strip under the app bar that shows the access countdown while the
/// install is on trial, and a call to action once it has ended.
class AccessBanner extends StatelessWidget {
  const AccessBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final status = state.accessStatus;
    if (status == null || status.isPro) return const SizedBox.shrink();

    final p = context.palette;
    final trial = status.isTrial;
    final tone = trial ? p.accent : p.error;
    final remaining = state.timeRemaining();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        border: Border(bottom: BorderSide(color: tone.withOpacity(0.25))),
      ),
      child: Row(
        children: [
          Icon(
            trial ? Icons.timer_outlined : Icons.lock_outline_rounded,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trial
                      ? 'Trial · ${formatRemaining(remaining)}'
                      : 'Trial ended · downloads run one at a time',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: tone,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trial) ...[
                  const SizedBox(height: 6),
                  TurboProgressBar(
                    value: state.accessUsedFraction(),
                    color: tone,
                    height: 4,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (state.licensingEnabled)
            TextButton(
              onPressed: () => showLicenceDialog(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                'Unlock Pro',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: tone,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact chip for the app bar: "PRO · 364 days left", or "TRIAL · 6 d".
class AccessChip extends StatelessWidget {
  const AccessChip({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final status = state.accessStatus;
    if (status == null || status.isFree) return const SizedBox.shrink();

    final p = context.palette;
    final pro = status.isPro;
    final tone = pro ? p.success : p.accent;
    final remaining = state.timeRemaining();
    final label = pro
        ? (status.expiresAt == null
            ? 'PRO'
            : 'PRO · ${formatRemaining(remaining)}')
        : 'TRIAL · ${formatRemaining(remaining)}';

    return Tooltip(
      message: pro ? 'Pro licence active' : 'Trial in progress',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: tone.withOpacity(0.14),
          borderRadius: TurboRadius.all(TurboRadius.pill),
          border: Border.all(color: tone.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: TurboFonts.mono,
            color: tone,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
