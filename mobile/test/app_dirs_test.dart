import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/app_dirs.dart';

/// Where the app writes its state files. A regression here is not cosmetic:
/// resolving to a working-directory-relative `./.turbo` fails on a read-only
/// working directory and surfaces as "Could not read the session", which blocks
/// sign-in.
void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('appdirs');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('prefers ~/.turbo so existing desktop data is kept', () async {
    final home = Directory('${sandbox.path}/home')..createSync();
    final dir = await AppDirs.resolve(home: home.path, temp: sandbox);
    expect(dir.path, '${home.path}${Platform.pathSeparator}.turbo');
    expect(dir.existsSync(), isTrue);
  });

  test('falls back to the platform directory when HOME is unset', () async {
    final support = Directory('${sandbox.path}/support')..createSync();
    final dir = await AppDirs.resolve(
      home: null,
      platform: () async => support,
      temp: sandbox,
    );
    expect(dir.path, support.path);
  });

  test('never returns a working-directory-relative path', () async {
    // The exact shape of the reported bug: HOME and USERPROFILE both empty, so
    // the old code produced `./.turbo` and a read-only cwd rejected it.
    final dir = await AppDirs.resolve(home: '', temp: sandbox);
    expect(dir.isAbsolute, isTrue);
    expect(dir.path, isNot(startsWith('.')));
    expect(dir.path, sandbox.path);
  });

  test('skips a home directory it cannot create', () async {
    // Stand in for a read-only location: a path whose parent is a *file*, so
    // create() must fail and the resolver has to move on.
    final blocker = File('${sandbox.path}/blocker')..writeAsStringSync('x');
    final home = Directory('${blocker.path}/nested');
    final dir = await AppDirs.resolve(home: home.path, temp: sandbox);
    expect(dir.path, sandbox.path,
        reason: 'an unusable home must fall through to the writable fallback');
  });

  test('an explicit override wins when it is writable', () async {
    final override = Directory('${sandbox.path}/override')..createSync();
    final dir = await AppDirs.resolve(
      override: override,
      home: '${sandbox.path}/home',
      temp: sandbox,
    );
    expect(dir.path, override.path);
  });

  test('falls back to temp when every platform probe fails', () async {
    final dir = await AppDirs.resolve(
      home: null,
      platform: () async => null,
      temp: sandbox,
    );
    expect(dir.path, sandbox.path);
  });
}
