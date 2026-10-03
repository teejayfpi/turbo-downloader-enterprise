import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/secure_store.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The credential vault. Values are held in the platform's protected store —
/// the Android Keystore on mobile, an owner-only file on desktop — and are
/// never displayed once saved. Only the key names and a one-way fingerprint are
/// shown, which is enough to confirm a credential exists without exposing it.
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  List<String> _keys = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await context.read<TurboState>().secure.keys();
    if (!mounted) return;
    setState(() {
      _keys = keys..sort();
      _loading = false;
    });
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<TurboState>();
    final result = await showDialog<_NewSecret>(
      context: context,
      builder: (_) => const _NewSecretDialog(),
    );
    if (result == null) return;
    await state.secure.write(result.key, result.value);
    await _load();
    messenger.showSnackBar(
      SnackBar(content: Text('Saved "${result.key}" to the vault.')),
    );
  }

  Future<void> _delete(String key) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<TurboState>();
    await state.secure.delete(key);
    await _load();
    messenger.showSnackBar(SnackBar(content: Text('Removed "$key".')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credential vault'),
        actions: [
          IconButton(
            tooltip: 'Add credential',
            icon: const Icon(Icons.add_rounded),
            onPressed: _add,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TurboPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('How it is stored', letterSpacing: 2.0),
                const SizedBox(height: 10),
                Text(
                  'Secrets are encrypted by the operating system — the Android '
                  'Keystore on mobile, an owner-only file on desktop. Turbo '
                  'never writes a credential to plain preferences, never logs '
                  'it, and never sends it anywhere. The vault is optional; the '
                  'app works without it.',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: p.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                TurboButton(
                  label: 'Add credential',
                  icon: Icons.key_rounded,
                  onPressed: _add,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Kicker('Stored keys', letterSpacing: 2.0),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_keys.isEmpty)
            const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Vault empty',
              message: 'No credentials stored yet.',
            )
          else
            for (final key in _keys)
              _SecretRow(storageKey: key, onDelete: () => _delete(key)),
        ],
      ),
    );
  }
}

class _SecretRow extends StatelessWidget {
  final String storageKey;
  final VoidCallback onDelete;
  const _SecretRow({required this.storageKey, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_key_rounded, size: 16, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              storageKey,
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: p.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
          Text('••••••',
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: p.textMuted,
                fontSize: 12,
              )),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline_rounded,
                color: p.textSecondary, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _NewSecret {
  final String key;
  final String value;
  _NewSecret(this.key, this.value);
}

class _NewSecretDialog extends StatefulWidget {
  const _NewSecretDialog();

  @override
  State<_NewSecretDialog> createState() => _NewSecretDialogState();
}

class _NewSecretDialogState extends State<_NewSecretDialog> {
  final _key = TextEditingController();
  final _value = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _generate() {
    setState(() {
      _value.text = SecureStore.generate();
      _hide = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final valid = _key.text.trim().isNotEmpty && _value.text.isNotEmpty;
    final strength = SecureStore.strength(_value.text);
    final strengthColor = switch (strength.score) {
      >= 4 => p.success,
      3 => p.speedFast,
      2 => p.warning,
      _ => p.error,
    };
    return AlertDialog(
      title: const Text('Add credential'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _key,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Key',
              hintText: 'e.g. premium-host-token',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            onChanged: (_) => setState(() {}),
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'Value',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Generate',
                    icon: Icon(Icons.casino_rounded,
                        size: 18, color: p.accent),
                    onPressed: _generate,
                  ),
                  IconButton(
                    icon: Icon(
                      _hide
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: p.textMuted,
                    ),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ],
              ),
            ),
          ),
          if (_value.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: TurboRadius.all(TurboRadius.pill),
                    child: LinearProgressIndicator(
                      value: (strength.score + 1) / 5,
                      minHeight: 5,
                      backgroundColor: p.bgTertiary,
                      valueColor: AlwaysStoppedAnimation(strengthColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(strength.label,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: strengthColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context)
                  .pop(_NewSecret(_key.text.trim(), _value.text))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
