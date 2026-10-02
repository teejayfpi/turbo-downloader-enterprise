// Exercises the real TurboApi client against a running server.
// Usage: dart run tool/integration_check.dart http://localhost:12001
import 'dart:io';

import 'package:turbo_downloader/api.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://localhost:12001';
  final api = TurboApi(base);

  print('1. ping');
  if (!await api.ping()) {
    stderr.writeln('   FAIL: server not reachable at $base');
    exit(1);
  }
  print('   ok');

  print('2. create download');
  final created = await api.addDownload(
    url: 'https://raw.githubusercontent.com/flutter/flutter/master/README.md',
    connections: 4,
  );
  if (created.isEmpty) {
    stderr.writeln('   FAIL: no task returned');
    exit(1);
  }
  final id = created.first.id;
  print('   ok -> $id (${created.first.filename})');

  print('3. poll to completion');
  var status = '';
  for (var i = 0; i < 40; i++) {
    await Future.delayed(const Duration(milliseconds: 500));
    final task = await api.getDownload(id);
    status = task.status;
    if (task.isCompleted || task.isFailed) {
      print('   $status  ${task.downloaded}/${task.total} bytes');
      if (task.isFailed) {
        stderr.writeln('   FAIL: ${task.error}');
        exit(1);
      }
      break;
    }
  }
  if (status != 'completed') {
    stderr.writeln('   FAIL: still $status after 20s');
    exit(1);
  }

  print('4. list contains the task');
  final list = await api.getDownloads();
  if (!list.downloads.any((d) => d.id == id)) {
    stderr.writeln('   FAIL: task missing from list');
    exit(1);
  }
  print('   ok (${list.downloads.length} task(s), total ${list.stats.totalCount})');

  print('5. retrieve the file');
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(api.fileUrl(id)));
  final res = await req.close();
  if (res.statusCode != 200) {
    stderr.writeln('   FAIL: file endpoint returned ${res.statusCode}');
    exit(1);
  }
  final bytes = await res.fold<int>(0, (n, chunk) => n + chunk.length);
  print('   ok ($bytes bytes)');
  if (bytes <= 0) {
    stderr.writeln('   FAIL: empty file');
    exit(1);
  }

  print('6. cleanup');
  await api.remove(id, deleteFile: true);
  print('   ok');

  print('\nALL CHECKS PASSED');
}
