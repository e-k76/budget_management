// TEMPORARY: which way of starting PowerShell from Dart actually runs a script on Windows?
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('launch variants', () async {
    final tmp = await Directory.systemTemp.createTemp('bm_probe');
    final ps1 = File(p.join(tmp.path, 'probe.ps1'))
      ..writeAsStringSync('param([string]\$Out)\nSet-Content -Path \$Out -Value "ran"\n');
    final base = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps1.path];
    final out = {for (final v in 'ABCDEF'.split('')) v: p.join(tmp.path, 'out$v.txt')};

    Future<void> go(String v, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        File(out[v]!).writeAsStringSync('START ERROR: $e');
      }
    }

    await go('A', () => Process.start('powershell.exe', ['-WindowStyle', 'Hidden', ...base, '-Out', out['A']!], mode: ProcessStartMode.detached));
    await go('B', () => Process.start('powershell.exe', [...base, '-Out', out['B']!], mode: ProcessStartMode.detached));
    await go('C', () => Process.start('powershell.exe', ['-WindowStyle', 'Hidden', ...base, '-Out', out['C']!], mode: ProcessStartMode.detachedWithStdio));
    await go('D', () => Process.start('cmd.exe', ['/c', 'start', '', '/min', 'powershell.exe', '-WindowStyle', 'Hidden', ...base, '-Out', out['D']!], mode: ProcessStartMode.detached));
    await go('E', () => Process.start('powershell.exe', ['-WindowStyle', 'Hidden', ...base, '-Out', out['E']!]));
    await go('F', () => Process.start('cmd.exe', ['/c', 'start', '', '/b', 'powershell.exe', ...base, '-Out', out['F']!], mode: ProcessStartMode.detached));

    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) && out.values.any((f) => !File(f).existsSync())) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final summary = out.entries
        .map((e) => '${e.key}: ${File(e.value).existsSync() ? File(e.value).readAsStringSync().trim() : "NOT RUN"}')
        .join(' | ');
    // ignore: avoid_print
    print('PROBE $summary');
    fail('PROBE RESULT  $summary');
  }, skip: Platform.isWindows ? false : 'Windows only');
}
