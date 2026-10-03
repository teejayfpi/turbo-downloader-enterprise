import 'dart:io';

/// Makes the app the handler for the `turbo://` handoff scheme on desktop,
/// so a browser extension (or any helper) can open a link straight in Turbo.
///
/// This is best-effort and per-user; on Windows it writes under `HKCU` (no
/// admin prompt), on Linux it drops a desktop entry under the user's data dir.
/// macOS is declared in `Info.plist` instead, so nothing is done there.
Future<void> registerProtocolHandler() async {
  try {
    if (Platform.isWindows) {
      await _registerWindows();
    } else if (Platform.isLinux) {
      await _registerLinux();
    }
  } catch (_) {
    // Registration is a convenience; never let it block startup.
  }
}

Future<void> _registerWindows() async {
  final exe = Platform.resolvedExecutable;
  const base = r'HKCU\Software\Classes\turbo';
  Future<void> add(List<String> args) =>
      Process.run('reg', ['add', ...args, '/f']).catchError((_) => ProcessResult(0, 0, '', ''));
  await add([base, '/ve', '/d', 'URL:Turbo Downloader']);
  await add([base, '/v', 'URL Protocol', '/d', '']);
  await add(['$base\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"']);
}

Future<void> _registerLinux() async {
  final exe = Platform.resolvedExecutable;
  final appsDir = Directory(
    '${Platform.environment['HOME'] ?? '/tmp'}/.local/share/applications',
  );
  if (!await appsDir.exists()) {
    await appsDir.create(recursive: true);
  }
  final entry = File('${appsDir.path}/turbo-downloader.desktop');
  await entry.writeAsString('''[Desktop Entry]
Type=Application
Name=Turbo Downloader
Exec=$exe %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/turbo;
Categories=Network;
''');
  await Process.run(
    'update-desktop-database',
    [appsDir.path],
  ).catchError((_) => ProcessResult(0, 0, '', ''));
}
