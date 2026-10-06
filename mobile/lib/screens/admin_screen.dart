import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../services/subscription.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The owner's console for handing out access.
///
/// This screen only exists on the owner's build. It can mint signed keys for
/// daily / weekly / monthly / quarterly / yearly (or a custom window), keep a
/// ledger of who holds what, and copy a key for sending to a user. It is gated
/// behind a passphrase so a user of the same build cannot issue themselves a
/// key, and it never ships in a user-facing release.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin · Access'),
        actions: [
          if (state.adminUnlocked)
            IconButton(
              tooltip: 'Lock',
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: state.lockAdmin,
            ),
        ],
      ),
      body: !state.adminAvailable
          ? const _Unavailable()
          : !state.adminConfigured
              ? _SetupPanel(state: state)
              : !state.adminUnlocked
                  ? _UnlockPanel(state: state)
                  : _Console(state: state),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Notice(
            icon: Icons.info_outline_rounded,
            color: Color(0xFFF5A524),
            text: 'This build was compiled without a licence public key, so it '
                'cannot verify or issue keys. Build with '
                '--dart-define=TURBO_LICENCE_PUBLIC_KEY=... to enable access '
                'control.',
          ),
        ],
      );
}

/// First-run: set the passphrase and paste the signing seed.
class _SetupPanel extends StatefulWidget {
  final TurboState state;
  const _SetupPanel({required this.state});

  @override
  State<_SetupPanel> createState() => _SetupPanelState();
}

class _SetupPanelState extends State<_SetupPanel> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _seed = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    _seed.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass = _pass.text;
    if (pass.length < 6) {
      setState(() => _error = 'Use at least 6 characters.');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = 'The passphrases do not match.');
      return;
    }
    if (_seed.text.trim().isEmpty) {
      setState(() => _error = 'Paste the signing seed from keygen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final seedError = await widget.state.setAdminSeed(_seed.text);
    if (seedError != null) {
      setState(() {
        _busy = false;
        _error = seedError;
      });
      return;
    }
    await widget.state.setAdminPassphrase(pass);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        TurboPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kicker('Set up the owner console', letterSpacing: 2.0),
              const SizedBox(height: 10),
              Text(
                'Run `dart run tools/license_tool.dart keygen` once. Keep the '
                'private seed here so this device can issue keys; bake the '
                'public key into the app you ship to users. The seed never '
                'leaves this device.',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Owner passphrase'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm passphrase'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _seed,
          obscureText: true,
          maxLines: 1,
          decoration: const InputDecoration(
            labelText: 'Signing seed (base64)',
            hintText: 'from keygen',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(
                  fontFamily: TurboFonts.body, color: p.error, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        TurboButton(
          label: 'Save and unlock',
          icon: Icons.lock_open_rounded,
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

/// Returning owner: enter the passphrase to unlock.
class _UnlockPanel extends StatefulWidget {
  final TurboState state;
  const _UnlockPanel({required this.state});

  @override
  State<_UnlockPanel> createState() => _UnlockPanelState();
}

class _UnlockPanelState extends State<_UnlockPanel> {
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.state.unlockAdmin(_pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Wrong passphrase.';
    });
  }

  Future<void> _forgot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset owner console?'),
        content: const Text(
          'This clears the stored passphrase and signing seed. You will need '
          'the seed again to issue new keys. Keys already given out keep '
          'working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.state.resetAdmin();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Notice(
          icon: Icons.shield_outlined,
          color: Color(0xFF7C5CFF),
          text: 'The owner console is locked. Enter the passphrase to issue or '
              'review subscriptions.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _pass,
          obscureText: true,
          onSubmitted: (_) => _unlock(),
          decoration: const InputDecoration(labelText: 'Owner passphrase'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(
                  fontFamily: TurboFonts.body, color: p.error, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        TurboButton(
          label: 'Unlock',
          icon: Icons.lock_open_rounded,
          busy: _busy,
          onPressed: _busy ? null : _unlock,
        ),
        const SizedBox(height: 8),
        TurboButton(
          label: 'Forgot passphrase',
          icon: Icons.restart_alt_rounded,
          outline: true,
          onPressed: _forgot,
        ),
      ],
    );
  }
}

/// The unlocked console: issue keys and review the ledger.
class _Console extends StatelessWidget {
  final TurboState state;
  const _Console({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stats = state.subscriptionStats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Active',
                value: '${stats.active}',
                color: p.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Expired',
                value: '${stats.expired}',
                color: p.error,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Issued',
                value: '${stats.total}',
                color: p.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TurboButton(
          label: 'Issue a subscription',
          icon: Icons.add_card_rounded,
          onPressed: () => _issue(context),
        ),
        const SizedBox(height: 20),
        const Kicker('Ledger', letterSpacing: 2.0),
        const SizedBox(height: 8),
        if (state.subscriptions.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No subscriptions yet',
            message: 'Issue a key to see it here.',
          )
        else
          for (final sub in state.subscriptions)
            _SubscriptionRow(
              sub: sub,
              now: state.accessNow,
              onCopy: () => _copy(context, sub.key, 'Key copied'),
              onRevoke: () => _revoke(context, sub),
            ),
      ],
    );
  }

  Future<void> _issue(BuildContext context) async {
    final result = await showDialog<Subscription>(
      context: context,
      builder: (_) => _IssueDialog(state: state),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Issued ${result.id} for ${result.holder}.')),
      );
    }
  }

  Future<void> _revoke(BuildContext context, Subscription sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${sub.id}?'),
        content: Text(
          'This forgets ${sub.holder}\'s key on this device. The key the user '
          'holds keeps working until it expires, because verification is '
          'offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await state.revokeSubscription(sub.id);
  }

  static Future<void> _copy(
      BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SubscriptionRow extends StatelessWidget {
  final Subscription sub;
  final DateTime now;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;
  const _SubscriptionRow({
    required this.sub,
    required this.now,
    required this.onCopy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = sub.isActiveAt(now);
    final tone = active ? p.success : p.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.timer_off_rounded,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.holder,
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sub.plan.label} · ${sub.id}',
                  style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: p.textMuted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub.isPerpetual
                      ? 'Never expires'
                      : '${formatRemaining(sub.remainingAt(now))} · '
                          '${_date(sub.expiresAt!)}',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: tone,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy key',
            icon: Icon(Icons.copy_rounded, size: 18, color: p.accent),
            onPressed: onCopy,
          ),
          IconButton(
            tooltip: 'Remove from ledger',
            icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: p.textSecondary),
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

/// The issue form: holder, plan, optional custom end date, optional device bind.
class _IssueDialog extends StatefulWidget {
  final TurboState state;
  const _IssueDialog({required this.state});

  @override
  State<_IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<_IssueDialog> {
  final _holder = TextEditingController();
  final _device = TextEditingController();
  BillingPlan _plan = BillingPlan.monthly;
  DateTime? _customEnd;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _holder.dispose();
    _device.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = widget.state.accessNow;
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _customEnd = picked);
  }

  Future<void> _issue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.state.issueSubscription(
      holder: _holder.text,
      plan: _plan,
      expiresAt: _plan == BillingPlan.custom ? _customEnd : null,
      deviceId: _device.text.trim().isEmpty ? null : _device.text.trim(),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context, result.subscription);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: const Text('Issue a subscription'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _holder,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Holder',
                hintText: 'name or email',
              ),
            ),
            const SizedBox(height: 14),
            const Kicker('Plan', letterSpacing: 1.6),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final plan in BillingPlan.values)
                  ChoiceChip(
                    label: Text(plan == BillingPlan.custom
                        ? 'Custom'
                        : '${plan.label} · ${plan.days}d'),
                    selected: _plan == plan,
                    onSelected: (_) => setState(() => _plan = plan),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_plan == BillingPlan.custom)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _customEnd == null
                          ? 'No end date chosen'
                          : 'Ends ${_date(_customEnd!)}',
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickDate,
                    child: const Text('Pick date'),
                  ),
                ],
              )
            else
              Text(
                'Expires ${_date(widget.state.accessNow.add(Duration(days: _plan.days)))}',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textSecondary,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _device,
              decoration: const InputDecoration(
                labelText: 'Bind to device id (optional)',
                hintText: 'leave blank to allow any device',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: p.error,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy || _holder.text.trim().isEmpty ? null : _issue,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Issue'),
        ),
      ],
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
