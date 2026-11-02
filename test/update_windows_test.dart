// Runs the REAL PowerShell helper against temp folders. Windows only (skipped
// elsewhere); executed in CI on a Windows runner.
import 'dart:io';

import 'package:budget_management/core/app_config.dart';
import 'package:budget_management/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final skip = Platform.isWindows ? false : 'Windows only';
  late Directory tmp;
  late String appDir, updDir, resultFile;
  late UpdateService svc;

  Future<void> write(String path, String text) async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString(text);
  }

  /// When the helper leaves no result, find out why: its log, and its own error output.
  Future<String> diagnose(UpdateInfo info, String staging) async {
    final log = File('${Platform.environment['TEMP']}\\budget_management_update.log');
    final b = StringBuffer('LOG: ${log.existsSync() ? log.readAsStringSync() : '(none)'}\n');
    try {
      final args = await svc.prepareHelper(staging, info, waitForPid: 0, retries: 1, waitSec: 1, restart: false);
      final r = await Process.run('powershell.exe', args).timeout(const Duration(seconds: 60));
      b.writeln('SYNC EXIT ${r.exitCode}\nSTDOUT: ${r.stdout}\nSTDERR: ${r.stderr}');
      b.writeln('RESULT FILE: ${File(resultFile).existsSync() ? File(resultFile).readAsStringSync() : '(none)'}');
    } catch (e) {
      b.writeln('diagnose failed: $e');
    }
    return b.toString();
  }

  Future<String> readResult() async {
    for (var i = 0; i < 300; i++) {
      final f = File(resultFile);
      if (f.existsSync()) {
        try {
          final t = f.readAsStringSync().replaceAll('\uFEFF', '').trim();
          if (t.isNotEmpty) return t;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return 'TIMEOUT: no result file after 60 s';
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_win');
    appDir = p.join(tmp.path, 'app');
    updDir = p.join(tmp.path, 'update');
    resultFile = p.join(tmp.path, 'result.txt');
    svc = UpdateService(
        appDir: appDir, updateFolderOverride: updDir, tempRoot: tmp.path, resultFile: resultFile);
    final exe = r'C:\Windows\System32\whoami.exe'; // any harmless exe that exits at once
    await Directory(appDir).create(recursive: true);
    await File(exe).copy(p.join(appDir, AppConfig.exeName));
    await write(p.join(appDir, 'version.txt'), '1');
    await write(p.join(appDir, 'a_first.txt'), 'OLD-A');
    await write(p.join(appDir, 'keep_me.txt'), 'USER FILE');
    await write(p.join(appDir, 'data', 'x.bin'), 'OLD-X');
    await Directory(updDir).create(recursive: true);
    await File(exe).copy(p.join(updDir, AppConfig.exeName));
    await write(p.join(updDir, 'version.txt'), '2');
    await write(p.join(updDir, 'a_first.txt'), 'NEW-A');
    await write(p.join(updDir, 'data', 'x.bin'), 'NEW-X');
    await write(p.join(updDir, 'data', 'brand_new.txt'), 'NEW-FILE');
    await write(p.join(updDir, 'z_last.txt'), 'NEW-Z');
  });

  tearDown(() async {
    try {
      await Process.run('attrib', ['-R', '${tmp.path}\\*', '/S']);
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<Process> shortLivedApp() => Process.start('cmd', ['/c', 'ping -n 3 127.0.0.1 > nul']);

  test('helper waits for the app, replaces files, keeps others, reports ok', () async {
    final info = await svc.check();
    expect(info.hasUpdate, isTrue);
    final staging = await svc.stage(info);
    final app = await shortLivedApp();
    await svc.apply(staging, info, waitForPid: app.pid, retries: 2, waitSec: 1);
    final r1 = await readResult();
    if (r1.startsWith('TIMEOUT')) fail(await diagnose(info, staging));
    expect(r1, 'ok|2');
    File(p.join(appDir, 'a_first.txt')).readAsStringSync();
    expect(File(p.join(appDir, 'a_first.txt')).readAsStringSync(), 'NEW-A');
    expect(File(p.join(appDir, 'data', 'x.bin')).readAsStringSync(), 'NEW-X');
    expect(File(p.join(appDir, 'data', 'brand_new.txt')).readAsStringSync(), 'NEW-FILE');
    expect(File(p.join(appDir, 'z_last.txt')).readAsStringSync(), 'NEW-Z');
    expect(File(p.join(appDir, 'keep_me.txt')).readAsStringSync(), 'USER FILE'); // untouched
    expect(File(p.join(appDir, 'version.txt')).readAsStringSync().trim(), '2');
    expect((await svc.check()).hasUpdate, isFalse); // now up to date
    for (var i = 0; i < 50 && Directory(staging).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(Directory(staging).existsSync(), isFalse); // staging cleaned up
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('a failed copy restores the previous version', () async {
    // a read-only file in the app folder that the new version wants to change
    await write(p.join(appDir, 'locked.txt'), 'OLD-LOCKED');
    await write(p.join(updDir, 'locked.txt'), 'NEW-LOCKED');
    await Process.run('attrib', ['+R', p.join(appDir, 'locked.txt')]);
    final info = await svc.check();
    final staging = await svc.stage(info);
    await svc.apply(staging, info, waitForPid: 0, retries: 1, waitSec: 1, restart: false);
    final result = await readResult();
    if (result.startsWith('TIMEOUT')) fail(await diagnose(info, staging));
    expect(result, startsWith('failed|'), reason: result);
    // files robocopy had already replaced are put back
    expect(File(p.join(appDir, 'a_first.txt')).readAsStringSync(), 'OLD-A');
    expect(File(p.join(appDir, 'data', 'x.bin')).readAsStringSync(), 'OLD-X');
    expect(File(p.join(appDir, 'locked.txt')).readAsStringSync(), 'OLD-LOCKED');
    expect(File(p.join(appDir, 'version.txt')).readAsStringSync().trim(), '1');
    expect(File(p.join(appDir, 'keep_me.txt')).readAsStringSync(), 'USER FILE');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
