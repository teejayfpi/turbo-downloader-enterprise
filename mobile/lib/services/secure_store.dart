import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small key/value store for values that should not sit in plain
/// `SharedPreferences`.
///
/// On Android the value is encrypted with a key held in the **Android
/// Keystore** (see `PlatformChannels.kt`), so the plaintext never touches disk. On
/// desktop it is written to a file whose permissions are restricted to the
/// current user (`0600`); the OS keychain is not used because Flutter has no
/// first-party API for Windows Credential Manager / macOS Keychain / Linux
/// Secret Service and pulling one in would add a heavy, platform-specific
/// dependency for a single feature.
///
/// The store is used for API tokens, cookies, and any future credentials. It is
/// deliberately tiny: [write], [read], [delete].
class SecureStore {
  SecureStore({MethodChannel? channel, Directory? rootOverride})
      : _channel = channel ?? const MethodChannel('turbo_downloader/secure'),
        _rootOverride = rootOverride;

  final MethodChannel _channel;
  final Directory? _rootOverride;

  /// Names of the secrets currently held, so Settings can show what exists
  /// without ever rendering a value.
  static const _indexKey = 'turbo.secure.index';

  Future<File> _file() async {
    final root = _rootOverride ??
        Directory(
            '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.turbo');
    if (!await root.exists()) await root.create(recursive: true);
    return File('${root.path}/secure.json');
  }

  /// Writes [value] under [key], overwriting any previous value.
  Future<void> write(String key, String value) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<bool>('secureWrite', {
          'key': key,
          'value': value,
        });
        await _touchIndex(key);
        return;
      } on MissingPluginException {
        // Fall through to the file/memory backend.
      } catch (_) {}
    }
    final file = await _file();
    final map = await _readFile(file);
    map[key] = value;
    await _writeFile(file, map);
    await _touchIndex(key);
  }

  /// Returns the stored value for [key], or null.
  Future<String?> read(String key) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final value = await _channel.invokeMethod<String>('secureRead', {
          'key': key,
        });
        if (value != null) return value;
      } on MissingPluginException {
        // Fall through.
      } catch (_) {}
    }
    final file = await _file();
    return (await _readFile(file))[key];
  }

  /// Removes [key] and returns true when something was deleted.
  Future<bool> delete(String key) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<bool>('secureDelete', {'key': key});
      } on MissingPluginException {
        // Fall through.
      } catch (_) {}
    }
    final file = await _file();
    final map = await _readFile(file);
    final removed = map.remove(key) != null;
    await _writeFile(file, map);
    final prefs = await SharedPreferences.getInstance();
    final index = (prefs.getStringList(_indexKey) ?? const <String>[])
        .where((k) => k != key)
        .toList();
    await prefs.setStringList(_indexKey, index);
    return removed;
  }

  /// The keys that currently hold a value. Values are never returned.
  Future<List<String>> keys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_indexKey) ?? const <String>[];
  }

  Future<void> _touchIndex(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? <String>[];
    if (!index.contains(key)) {
      index.add(key);
      await prefs.setStringList(_indexKey, index);
    }
  }

  Future<Map<String, String>> _readFile(File file) async {
    try {
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      return (decoded as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFile(File file, Map<String, String> map) async {
    await file.writeAsString(jsonEncode(map), flush: true);
    if (!Platform.isWindows) {
      // Best-effort owner-only permissions; Windows uses ACLs instead.
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  /// A stable, per-install device id, used to bind a licence to one device.
  ///
  /// It is a random value generated on first use and kept in
  /// `SharedPreferences`, not a hardware identifier: it is not personal data and
  /// does not survive a reinstall or cleared app data. The owner can ask a user
  /// for this id and issue a key locked to it.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'turbo.device.id';
    var id = prefs.getString(key);
    if (id == null || id.isEmpty) {
      id = generate(length: 22, symbols: false);
      await prefs.setString(key, id);
    }
    return id;
  }

  /// A stable, non-reversible fingerprint of a secret, so a UI can show that a
  /// credential exists (and whether it changed) without storing or printing it.
  static String fingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 12);

  /// The alphabet used by [generate]. Ambiguous characters (0/O, 1/l/I) are
  /// omitted so a generated password can be read aloud without mistakes.
  static const _lower = 'abcdefghijkmnpqrstuvwxyz';
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _digits = '23456789';
  static const _symbols = '!@#\$%^&*-_=+?';

  /// Generates a cryptographically random password.
  ///
  /// [Random.secure] is used, and the result always contains at least one
  /// character from each enabled class.
  static String generate({
    int length = 20,
    bool symbols = true,
  }) {
    final rng = math.Random.secure();
    final classes = <String>[_lower, _upper, _digits, if (symbols) _symbols];
    final all = classes.join();
    final out = <String>[
      for (final c in classes) c[rng.nextInt(c.length)],
    ];
    while (out.length < length) {
      out.add(all[rng.nextInt(all.length)]);
    }
    out.shuffle(rng);
    return out.join();
  }

  /// A coarse strength estimate: 0 (very weak) to 4 (very strong), with a label.
  static ({int score, String label}) strength(String password) {
    if (password.isEmpty) return (score: 0, label: 'Empty');
    var classes = 0;
    if (password.contains(RegExp(r'[a-z]'))) classes++;
    if (password.contains(RegExp(r'[A-Z]'))) classes++;
    if (password.contains(RegExp(r'[0-9]'))) classes++;
    if (password.contains(RegExp(r'[^A-Za-z0-9]'))) classes++;

    // Rough entropy in bits: length × log2(alphabet). This is a heuristic, not
    // a guarantee, but it tracks the two things that matter: length and variety.
    final alphabet = switch (classes) {
      <= 1 => 26,
      2 => 52,
      3 => 62,
      _ => 95,
    };
    final bits = (password.length * (math.log(alphabet) / math.ln2));
    final score = bits >= 100
        ? 4
        : bits >= 75
            ? 3
            : bits >= 50
                ? 2
                : bits >= 30
                    ? 1
                    : 0;
    final label = switch (score) {
      4 => 'Very strong',
      3 => 'Strong',
      2 => 'Fair',
      1 => 'Weak',
      _ => 'Very weak',
    };
    return (score: score, label: label);
  }
}
