import 'dart:convert';
import 'dart:io';

import 'package:budget_management/core/app_config.dart';
import 'package:budget_management/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String appDir, updDir;

  Future<void> write(String path, String text) async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString(text);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_upd');
    appDir = p.join(tmp.path, 'app');
    updDir = p.join(tmp.path, 'update');
    await Directory(appDir).create();
    await Directory(updDir).create();
  });
  tearDown(() => tmp.delete(recursive: true));

  UpdateService svc({String? pointer, String? update}) => UpdateService(
        appDir: appDir,
        updateFolderOverride: update ?? updDir,
        pointerFile: pointer,
        tempRoot: tmp.path,
        resultFile: p.join(tmp.path, 'result.txt'),
      );

  test('parseVersion reads the leading number of the first line', () {
    expect(UpdateService.parseVersion('15'), 15);
    expect(UpdateService.parseVersion('\uFEFF  27 (2026-11-05)\n'), 27);
    expect(UpdateService.parseVersion('\n\n8\nignored'), 8);
    expect(UpdateService.parseVersion('v15'), isNull);
    expect(UpdateService.parseVersion(''), isNull);
  });

  group('check', () {
    test('newer version in the update folder is offered, with notes', () async {
      await write(p.join(appDir, 'version.txt'), '3');
      await write(p.join(updDir, 'version.txt'), '5');
      await write(p.join(updDir, 'notes.txt'), 'رفع خطا\nقابلیت جدید');
      final info = await svc().check();
      expect(info.installed, 3);
      expect(info.available, 5);
      expect(info.hasUpdate, isTrue);
      expect(info.notes, 'رفع خطا\nقابلیت جدید');
    });

    test('same or older version is not an update; missing notes is fine', () async {
      await write(p.join(appDir, 'version.txt'), '5');
      await write(p.join(updDir, 'version.txt'), '5');
      expect((await svc().check()).hasUpdate, isFalse);
      await write(p.join(updDir, 'version.txt'), '4');
      final info = await svc().check();
      expect(info.hasUpdate, isFalse);
      expect(info.notes, isNull);
    });

    test('an install without version.txt counts as version 0', () async {
      await write(p.join(updDir, 'version.txt'), '1');
      final info = await svc().check();
      expect(info.installed, 0);
      expect(info.hasUpdate, isTrue);
    });

    test('unreachable folder / missing or broken version.txt give a clear error', () async {
      await expectLater(svc(update: p.join(tmp.path, 'nope')).check(),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('در دسترس نیست'))));
      await expectLater(svc().check(),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('version.txt'))));
      await write(p.join(updDir, 'version.txt'), 'abc');
      await expectLater(svc().check(), throwsA(isA<UpdateException>()));
    });

    test('the update folder can come from a pointer file on the server', () async {
      final other = p.join(tmp.path, 'other');
      await write(p.join(other, 'version.txt'), '9');
      final pointer = p.join(tmp.path, 'update_path.txt');
      await File(pointer).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode('# comment\n\n  $other  \n')]);
      final s = UpdateService(
          appDir: appDir, pointerFile: pointer, tempRoot: tmp.path, resultFile: p.join(tmp.path, 'r.txt'));
      expect(await s.resolveUpdateFolder(), other);
      expect((await s.check()).available, 9);
      // pointer file missing -> the built-in default
      final d = UpdateService(appDir: appDir, pointerFile: p.join(tmp.path, 'none.txt'));
      expect(await d.resolveUpdateFolder(), AppConfig.defaultUpdateFolder);
    });
  });

  group('stage', () {
    Future<void> fullUpdateFolder() async {
      await write(p.join(updDir, AppConfig.exeName), 'EXE');
      await write(p.join(updDir, 'version.txt'), '7');
      await write(p.join(updDir, 'flutter_windows.dll'), 'DLL');
      await write(p.join(updDir, 'data', 'app.so'), 'SO');
      await write(p.join(updDir, 'data', 'flutter_assets', 'fonts', 'f.ttf'), 'FONT');
      await write(p.join(updDir, 'Thumbs.db'), 'junk');
    }

    test('copies the whole tree (nested folders) and reports progress; source untouched', () async {
      await fullUpdateFolder();
      final s = svc();
      final info = await s.check();
      final calls = <(int, int)>[];
      final staging = await s.stage(info, onProgress: (d, t) => calls.add((d, t)));
      expect(File(p.join(staging, AppConfig.exeName)).readAsStringSync(), 'EXE');
      expect(File(p.join(staging, 'data', 'flutter_assets', 'fonts', 'f.ttf')).readAsStringSync(), 'FONT');
      expect(File(p.join(staging, 'Thumbs.db')).existsSync(), isFalse);
      expect(calls.first, (0, 5));
      expect(calls.last, (5, 5));
      expect(File(p.join(updDir, AppConfig.exeName)).existsSync(), isTrue);
      expect(p.isWithin(tmp.path, staging), isTrue);
    });

    test('an incomplete update folder is rejected and leaves no staging folder behind', () async {
      await write(p.join(updDir, 'version.txt'), '7'); // exe missing
      await write(p.join(updDir, 'x.dll'), 'x');
      final s = svc();
      final info = await s.check();
      await expectLater(s.stage(info),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains(AppConfig.exeName))));
      expect(tmp.listSync().where((e) => p.basename(e.path).startsWith('bm_update_')), isEmpty);
    });
  });

  group('apply', () {
    test('the helper script is UTF-8 with BOM and does backup, copy, restore and restart', () async {
      final script = UpdateService.buildScript();
      for (final needle in ['Wait-Process', 'robocopy \$AppDir \$backup', 'robocopy \$Staging \$AppDir', 'restoring backup', 'Start-Process', 'Result "ok|']) {
        expect(script, contains(needle), reason: needle);
      }
    });

    test('starts powershell with the script and every argument', () async {
      if (Platform.isWindows) return; // uses a fake shell "powershell" below
      final out = p.join(tmp.path, 'args.txt');
      final fake = File(p.join(tmp.path, 'fake_ps.sh'))
        ..writeAsStringSync('#!/bin/sh\nfor a in "\$@"; do echo "\$a"; done > "$out"\n');
      await Process.run('chmod', ['+x', fake.path]);
      final s = svc();
      await write(p.join(updDir, 'version.txt'), '7');
      final info = UpdateInfo(installed: 3, available: 7, sourceDir: updDir);
      await s.apply(p.join(tmp.path, 'staging'), info, waitForPid: 4242, powershell: fake.path, retries: 3, waitSec: 1);
      for (var i = 0; i < 50 && !File(out).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final args = File(out).readAsLinesSync();
      String after(String flag) => args[args.indexOf(flag) + 1];
      expect(args, containsAllInOrder(['-NoProfile', '-ExecutionPolicy', 'Bypass']));
      expect(after('-File'), p.join(tmp.path, 'bm_apply_update.ps1'));
      expect(after('-ProcId'), '4242');
      expect(after('-AppDir'), appDir);
      expect(after('-Staging'), p.join(tmp.path, 'staging'));
      expect(after('-Exe'), AppConfig.exeName);
      expect(after('-Version'), '7');
      expect(after('-Retries'), '3');
      final bytes = File(after('-File')).readAsBytesSync();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), UpdateService.buildScript());
    });
  });

  test('takeLastResult reads the helper\'s verdict once', () async {
    final s = svc();
    expect(await s.takeLastResult(), isNull);
    await File(p.join(tmp.path, 'result.txt')).writeAsString('ok|12');
    expect(await s.takeLastResult(), (true, '12'));
    expect(await s.takeLastResult(), isNull); // consumed
    await File(p.join(tmp.path, 'result.txt')).writeAsString('failed|copy failed');
    expect(await s.takeLastResult(), (false, 'copy failed'));
  });
}
