// Imports the JSON produced by tool/export_access.ps1 into projects.db.
// Usage: dart run tool/import_access.dart <export.json> [target.db]
// Without a target it uses the app's real database path.
import 'dart:convert';
import 'dart:io';

import 'package:budget_management/core/formatters.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:shamsi_date/shamsi_date.dart';

const importer = 'Access import';

String _jalaliFromGregorianIso(String? iso) {
  final dt = iso == null ? DateTime.now() : DateTime.parse(iso);
  return formatJalali(Jalali.fromDateTime(dt));
}

/// Jalali date from the dyear/dmonth/dday text columns, or null if unusable.
String _norm(String s) =>
    s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('‌', ' ').trim();

String? _costDate(Map c) {
  final mName = _norm('${c['dmonth']}');
  var month = '$mName';
  final idx = jalaliMonthNames.indexWhere((n) => _norm(n) == mName);
  if (idx >= 0) month = '${idx + 1}';
  final raw = '${c['dyear']}/$month/${c['dday']}';
  final j = parseJalali(raw);
  return j == null ? null : formatJalali(j);
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/import_access.dart <export.json> [target.db]');
    exit(64);
  }
  final data = jsonDecode(await File(args[0]).readAsString()) as Map;
  final service = DatabaseService.instance;
  // ignore: invalid_use_of_visible_for_testing_member
  final positional = args.where((a) => !a.startsWith('--')).toList();
  // The importer works on this machine's local file only; the app pushes it to
  // the share on the next sync (if the share has no business data yet).
  // ignore: invalid_use_of_visible_for_testing_member
  service.remoteEnabled = false;
  // ignore: invalid_use_of_visible_for_testing_member
  if (positional.length > 1) service.localPathOverride = positional[1];
  final db = await service.db;

  // --reset wipes projects, expenses and incomes first (users are kept).
  final reset = args.contains('--reset');
  final already = reset ? <Map<String, Object?>>[{'c': 0}] : await db.rawQuery(
      "SELECT (SELECT COUNT(*) FROM expenses WHERE created_by = ?) + "
      "(SELECT COUNT(*) FROM incomes WHERE created_by = ?) AS c",
      [importer, importer]);
  if ((already.first['c'] as int) > 0) {
    stderr.writeln('This database already contains imported rows; refusing to import twice.');
    exit(1);
  }

  final now = DateTime.now().toIso8601String();
  final today = todayJalali();
  final names = <int, String>{};
  var fallbackDates = 0;

  await db.transaction((txn) async {
    if (reset) {
      await txn.delete('expenses');
      await txn.delete('incomes');
      await txn.delete('projects');
      await txn.delete('pending_ops');
      await txn.delete('sqlite_sequence',
          where: "name IN ('expenses','incomes','projects')");
    }
    for (final p in data['projects'] as List) {
      final name = (p['name'] as String).trim();
      names[p['id'] as int] = name;
      await txn.rawInsert(
        'INSERT OR IGNORE INTO projects (name, budget_percentage, total_income, created_at) '
        'VALUES (?, 100.0, 0, ?)',
        [name, now],
      );
    }
    for (final i in data['incomes'] as List) {
      final name = names[i['projectId']]!;
      final amount = (i['amount'] as num).toDouble();
      await txn.insert('incomes', {
        'uid': DatabaseService.newUid(),
        'project_name': name,
        'amount': amount,
        'date': today,
        'created_by': importer,
        'created_at': now,
      });
      await txn.rawUpdate(
          'UPDATE projects SET total_income = total_income + ? WHERE name = ?',
          [amount, name]);
    }
    for (final c in data['costs'] as List) {
      var date = _costDate(c);
      if (date == null) {
        date = _jalaliFromGregorianIso(c['insertDate'] as String?);
        fallbackDates++;
      }
      final payto = (c['payto'] as String).trim();
      final desc = (c['description'] as String).trim();
      final selected = c['selected'] == true;
      await txn.insert('expenses', {
        'uid': DatabaseService.newUid(),
        'project_name': names[c['projectId']]!,
        'date': date,
        'amount': (c['amount'] as num).toDouble(),
        'payee': payto,
        'description': desc,
        'is_approved': selected ? 1 : 0,
        'approved_by': selected ? importer : null,
        'approved_at': selected && c['okdate'] != null
            ? formatJalali(Jalali.fromDateTime(DateTime.parse(c['okdate'] as String)))
            : null,
        'created_by': importer,
        'created_at': (c['insertDate'] as String?) ?? now,
      });
    }
  });

  final s = await db.rawQuery('SELECT '
      '(SELECT COUNT(*) FROM projects) AS p, '
      '(SELECT COALESCE(SUM(total_income),0) FROM projects) AS inc, '
      '(SELECT COUNT(*) FROM expenses) AS e, '
      '(SELECT COALESCE(SUM(amount),0) FROM expenses) AS exp, '
      '(SELECT COUNT(*) FROM expenses WHERE is_approved = 1) AS appr');
  print('Imported. Dates taken from InsertDate for $fallbackDates costs.');
  print(s.first);
  await service.close();
}
