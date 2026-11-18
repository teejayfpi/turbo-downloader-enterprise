import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/app_dirs.dart';
import 'package:turbo_downloader/services/update_checker.dart';
import 'package:turbo_downloader/services/ytdlp_provisioner.dart';

/// Picks the right standalone yt-dlp asset, and installs it only after the
/// release's published checksum verifies the bytes.
void main() {
  YtdlpProvisioner provisioner({
    Abi? abi,
    bool? windows,
    bool? macos,
    bool? linux,
    Directory? dir,
    UpdateInstaller? installer,
  }) =>
      YtdlpProvisioner(
        abiOverride: abi,
        isWindows: windows ?? false,
        isMacOS: macos ?? false,
        isLinux: linux ?? false,
        dirOverride: dir,
        installer: installer,
        latestTagOverride: 'v2026.10.26',
      );

  group('asset selection', () {
    test('Windows x64 uses the plain executable', () {
      expect(
        provisioner(windows: true, abi: Abi.windowsX64).assetName,
        'yt-dlp.exe',
      );
    });

    test('Windows on ARM uses the arm64 build', () {
      expect(
        provisioner(windows: true, abi: Abi.windowsArm64).assetName,
        'yt-dlp_arm64.exe',
      );
    });

    test('macOS uses the universal build', () {
      expect(provisioner(macos: true, abi: Abi.macosArm64).assetName,
          'yt-dlp_macos');
      expect(provisioner(macos: true, abi: Abi.macosX64).assetName,
          'yt-dlp_macos');
    });

    test('Linux x64 and arm64 use their own builds', () {
      expect(provisioner(linux: true, abi: Abi.linuxX64).assetName,
          'yt-dlp_linux');
      expect(provisioner(linux: true, abi: Abi.linuxArm64).assetName,
          'yt-dlp_linux_aarch64');
    });

    test('a platform with no published build reports unsupported', () {
      final p = provisioner(linux: true, abi: Abi.linuxArm);
      expect(p.assetName, isNull);
      expect(p.isSupported, isFalse);
    });
  });

  group('install', () {
    test('downloads to the published asset and marks it executable', () async {
      final dir = await Directory.systemTemp.createTemp('turbo_prov');
      addTearDown(() => dir.delete(recursive: true));

      final installer = _RecordingInstaller();
      final p = provisioner(linux: true, abi: Abi.linuxX64, dir: dir,
          installer: installer);

      final path = await p.install();

      expect(installer.requestedUrl,
          contains('/releases/download/v2026.10.26/yt-dlp_linux'));
      // The manifest for the same tag is handed to the fail-closed verifier.
      expect(installer.checksumUrls.single,
          contains('/releases/download/v2026.10.26/SHA2-256SUMS'));
      expect(File(path).existsSync(), isTrue);
      expect(await File(path).readAsString(), 'FAKE-BINARY');
      // A POSIX install must be executable. Windows has no mode bits: a
      // `.exe` is runnable by its extension, so there is nothing to assert.
      if (!Platform.isWindows) {
        final mode = await File(path).stat();
        expect(mode.mode & 0x49, isNot(0), reason: 'owner/group/other x bits');
      }
    });

    test('a platform with no build fails with install advice', () async {
      final p = provisioner(linux: true, abi: Abi.linuxArm);
      await expectLater(
        p.install(),
        throwsA(isA<YtdlpInstallException>().having(
          (e) => e.message,
          'message',
          contains('package manager'),
        )),
      );
    });

    test('a checksum failure is reported, not installed', () async {
      final dir = await Directory.systemTemp.createTemp('turbo_prov');
      addTearDown(() => dir.delete(recursive: true));

      final p = provisioner(
        linux: true,
        abi: Abi.linuxX64,
        dir: dir,
        installer: _ThrowingInstaller(
          const HttpException('Update failed verification: checksum mismatch'),
        ),
      );

      await expectLater(
        p.install(),
        throwsA(isA<YtdlpInstallException>().having(
          (e) => e.message,
          'message',
          contains('did not match its published checksum'),
        )),
      );
      expect(await p.installedBinary(), isNull);
    });

    test('installedBinary reports the file once it exists', () async {
      final dir = await Directory.systemTemp.createTemp('turbo_prov');
      addTearDown(() => dir.delete(recursive: true));
      final p = provisioner(
        linux: true,
        abi: Abi.linuxX64,
        dir: dir,
        installer: _RecordingInstaller(),
      );

      expect(await p.installedBinary(), isNull);
      final path = await p.install();
      expect(await p.installedBinary(), path);
    });

    test('installs under the app data dir the engine searches', () async {
      final root = await Directory.systemTemp.createTemp('turbo_prov_app');
      addTearDown(() {
        AppDirs.testOverride = null;
        return root.delete(recursive: true);
      });
      AppDirs.testOverride = root;

      // No dirOverride, so the real AppDirs path is used.
      final p = YtdlpProvisioner(
        abiOverride: Abi.linuxX64,
        isLinux: true,
        installer: _RecordingInstaller(),
        latestTagOverride: 'v2026.10.26',
      );

      final path = await p.install();
      expect(path, '${root.path}${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}yt-dlp');
      expect(await p.installedBinary(), path);
    });
  });
}

/// An installer that writes a fixed payload and records what it was asked for,
/// standing in for the real GitHub download.
class _RecordingInstaller implements UpdateInstaller {
  String? requestedUrl;
  List<String> checksumUrls = const [];

  @override
  Future<File> download(
    String url, {
    void Function(double? progress)? onProgress,
    bool Function()? isCancelled,
    String? expectedSha256,
    List<String> checksumUrls = const [],
    bool allowUnverified = false,
  }) async {
    requestedUrl = url;
    this.checksumUrls = checksumUrls;
    onProgress?.call(0.5);
    onProgress?.call(1);
    final file = File(
        '${Directory.systemTemp.path}/turbo_prov_asset_${DateTime.now().microsecondsSinceEpoch}');
    await file.writeAsString('FAKE-BINARY');
    return file;
  }

  @override
  Future<InstallResult> install(File file) async => const InstallResult();
}

/// An installer that always fails, to prove the error text is user-safe.
class _ThrowingInstaller implements UpdateInstaller {
  final Object error;
  _ThrowingInstaller(this.error);

  @override
  Future<File> download(
    String url, {
    void Function(double? progress)? onProgress,
    bool Function()? isCancelled,
    String? expectedSha256,
    List<String> checksumUrls = const [],
    bool allowUnverified = false,
  }) async =>
      throw error;

  @override
  Future<InstallResult> install(File file) async => const InstallResult();
}
