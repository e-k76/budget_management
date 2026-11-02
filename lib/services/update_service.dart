import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_config.dart';

/// Thrown with a message that is safe to show to the user (Persian).
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateInfo {
  const UpdateInfo({
    required this.installed,
    required this.available,
    required this.sourceDir,
    this.notes,
  });

  final int installed;
  final int available;
  final String sourceDir;
  final String? notes;

  bool get hasUpdate => available > installed;
}

/// Update flow (a running program cannot overwrite its own files):
///  1. [check]  – compare `version.txt` in the update folder with the one next to the exe.
///  2. [stage]  – copy the update folder to a local temp folder while the app still runs
///                (a network hiccup here changes nothing).
///  3. [apply]  – start a small PowerShell helper and let the app exit. The helper waits for
///                the app to close, backs up the program folder, copies the staged files over
///                it (restoring the backup if that fails), and starts the app again.
class UpdateService {
  UpdateService({
    String? appDir,
    this.updateFolderOverride,
    this.pointerFile,
    String? tempRoot,
    String? resultFile,
  })  : appDir = _trimSep(appDir ?? File(Platform.resolvedExecutable).parent.path),
        tempRoot = tempRoot ?? Directory.systemTemp.path,
        resultFile = resultFile ?? defaultResultFile();

  /// Folder the running program lives in (where files get replaced).
  final String appDir;

  /// Tests / per-PC override of the update folder.
  final String? updateFolderOverride;

  /// File naming the update folder; defaults to [AppConfig.updatePointerFilePath].
  final String? pointerFile;

  final String tempRoot;

  /// Where the helper leaves `ok|<version>` or `failed|<reason>` for the next start.
  final String resultFile;

  static const _probe = Duration(seconds: 5);

  static String _trimSep(String path) =>
      path.length > 3 && (path.endsWith('\\') || path.endsWith('/'))
          ? path.substring(0, path.length - 1)
          : path;

  static String defaultResultFile() => p.join(
      Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
      'budget_management',
      'update_result.txt');

  /// Only a Windows build running as budget_management.exe can replace itself.
  bool get canSelfUpdate =>
      Platform.isWindows &&
      p.basename(Platform.resolvedExecutable).toLowerCase() ==
          AppConfig.exeName.toLowerCase();

  // ----------------------------------------------------------------- version

  /// Leading number of the first non-empty line (`15`, `15 (2026-11-05)` -> 15).
  static int? parseVersion(String text) {
    var t = text;
    if (t.startsWith('﻿')) t = t.substring(1);
    for (final line in LineSplitter.split(t)) {
      final m = RegExp(r'^\s*(\d+)').firstMatch(line);
      if (m != null) return int.parse(m.group(1)!);
      if (line.trim().isNotEmpty) return null;
    }
    return null;
  }

  static Future<String> _readText(File f) async =>
      utf8.decode(await f.readAsBytes().timeout(_probe), allowMalformed: true);

  /// The build number of this installation (0 for builds made before updates existed).
  Future<int> installedVersion() async {
    try {
      final f = File(p.join(appDir, 'version.txt'));
      if (await f.exists()) return parseVersion(await _readText(f)) ?? 0;
    } catch (_) {}
    return 0;
  }

  Future<String> resolveUpdateFolder() async {
    if (updateFolderOverride != null) return updateFolderOverride!;
    try {
      final text = await _readText(File(pointerFile ?? AppConfig.updatePointerFilePath));
      var t = text.startsWith('﻿') ? text.substring(1) : text;
      for (final line in LineSplitter.split(t)) {
        final l = line.trim();
        if (l.isNotEmpty && !l.startsWith('#')) return l;
      }
    } catch (_) {}
    return AppConfig.defaultUpdateFolder;
  }

  // ------------------------------------------------------------------- check

  Future<UpdateInfo> check() async {
    final dir = await resolveUpdateFolder();
    try {
      if (!await Directory(dir).exists().timeout(_probe)) {
        throw UpdateException('پوشه به‌روزرسانی در دسترس نیست:\n$dir');
      }
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw UpdateException('پوشه به‌روزرسانی در دسترس نیست:\n$dir');
    }
    final vf = File(p.join(dir, 'version.txt'));
    int? available;
    try {
      if (await vf.exists().timeout(_probe)) available = parseVersion(await _readText(vf));
    } catch (_) {}
    if (available == null) {
      throw UpdateException('فایل version.txt در پوشه به‌روزرسانی پیدا نشد یا معتبر نیست:\n$dir');
    }
    String? notes;
    try {
      final nf = File(p.join(dir, 'notes.txt'));
      if (await nf.exists().timeout(_probe)) {
        final t = (await _readText(nf)).trim();
        notes = t.length > 3000 ? t.substring(0, 3000) : t;
        if (notes.isEmpty) notes = null;
      }
    } catch (_) {}
    return UpdateInfo(
        installed: await installedVersion(), available: available, sourceDir: dir, notes: notes);
  }

  // ------------------------------------------------------------------- stage

  /// Copies the update folder to a fresh local temp folder and verifies it.
  /// Returns that folder. Nothing in the program folder is touched.
  Future<String> stage(UpdateInfo info, {void Function(int done, int total)? onProgress}) async {
    final staging = Directory(p.join(
        tempRoot, 'bm_update_${DateTime.now().millisecondsSinceEpoch}'));
    try {
      await staging.create(recursive: true);
      final files = <File>[];
      await for (final e in Directory(info.sourceDir).list(recursive: true, followLinks: false)) {
        if (e is File) {
          final name = p.basename(e.path).toLowerCase();
          if (name == 'desktop.ini' || name == 'thumbs.db') continue;
          files.add(e);
        }
      }
      var done = 0;
      onProgress?.call(0, files.length);
      for (final f in files) {
        final dest = File(p.join(staging.path, p.relative(f.path, from: info.sourceDir)));
        await dest.parent.create(recursive: true);
        await f.copy(dest.path);
        onProgress?.call(++done, files.length);
      }
      if (!await File(p.join(staging.path, AppConfig.exeName)).exists()) {
        throw UpdateException('پوشه به‌روزرسانی ناقص است: ${AppConfig.exeName} پیدا نشد.');
      }
      if (!await File(p.join(staging.path, 'version.txt')).exists()) {
        throw UpdateException('پوشه به‌روزرسانی ناقص است: version.txt پیدا نشد.');
      }
      return staging.path;
    } catch (e) {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {}
      if (e is UpdateException) rethrow;
      throw UpdateException('کپی فایل‌های به‌روزرسانی ناموفق بود:\n$e');
    }
  }

  // ------------------------------------------------------------------- apply

  /// The helper script. UTF-8 with BOM so PowerShell reads Persian text correctly.
  static String buildScript() => r'''
param(
  [int]$ProcId = 0,
  [string]$AppDir,
  [string]$Staging,
  [string]$Exe,
  [string]$ResultFile,
  [string]$Version,
  [int]$Retries = 15,
  [int]$WaitSec = 2,
  [switch]$NoRestart
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'budget_management_update.log'
function Log([string]$m) { try { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $m) -Encoding UTF8 } catch {} }
function Result([string]$m) {
  try {
    $dir = Split-Path -Parent $ResultFile
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $ResultFile -Value $m -Encoding UTF8
  } catch { Log "result: $_" }
}
$backup = Join-Path $env:TEMP ('bm_backup_' + [guid]::NewGuid().ToString('N'))
try {
  Log "start pid=$ProcId app=$AppDir staging=$Staging version=$Version"
  if ($ProcId -gt 0) {
    try { Wait-Process -Id $ProcId -Timeout 90 -ErrorAction Stop } catch { Log "wait: $_" }
  }
  Start-Sleep -Seconds 1

  # 1. back up the current program folder so a failed copy can be undone
  robocopy $AppDir $backup /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "backup failed (robocopy $LASTEXITCODE)" }

  # 2. copy the new files over it (robocopy codes 0-7 mean success)
  robocopy $Staging $AppDir /E /R:$Retries /W:$WaitSec /NFL /NDL /NJH /NJS /NP | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    Log "copy failed ($code): restoring backup"
    robocopy $backup $AppDir /E /IS /IT /R:5 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    Result "failed|copy failed (robocopy $code); the previous version was restored"
  } else {
    Log "copy ok ($code)"
    Result "ok|$Version"
  }
} catch {
  Log "error: $_"
  Result "failed|$_"
} finally {
  if (-not $NoRestart) {
    try { Start-Process -FilePath (Join-Path $AppDir $Exe) -WorkingDirectory $AppDir } catch { Log "restart: $_" }
  }
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Staging
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $backup
  Log "done"
}
''';

  /// Writes the helper next to the temp folder and starts it detached. The CALLER must then
  /// close the database and exit the app so the files are free to be replaced.
  Future<void> apply(String staging, UpdateInfo info,
      {int? waitForPid,
      int retries = 15,
      int waitSec = 2,
      bool restart = true,
      String powershell = 'powershell.exe'}) async {
    final script = File(p.join(tempRoot, 'bm_apply_update.ps1'));
    await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(buildScript())], flush: true);
    await Process.start(
      powershell,
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-ProcId',
        '${waitForPid ?? pid}',
        '-AppDir',
        appDir,
        '-Staging',
        staging,
        '-Exe',
        AppConfig.exeName,
        '-ResultFile',
        resultFile,
        '-Version',
        '${info.available}',
        '-Retries',
        '$retries',
        '-WaitSec',
        '$waitSec',
        if (!restart) '-NoRestart',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  // ------------------------------------------------------------ last result

  /// What the previous update run reported (consumed once): `(true, '15')` or `(false, reason)`.
  Future<(bool, String)?> takeLastResult() async {
    try {
      final f = File(resultFile);
      if (!await f.exists()) return null;
      final text = (await _readText(f)).trim();
      await f.delete();
      final i = text.indexOf('|');
      if (i < 0) return null;
      return (text.substring(0, i) == 'ok', text.substring(i + 1));
    } catch (_) {
      return null;
    }
  }
}
