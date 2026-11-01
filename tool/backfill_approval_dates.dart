// Fills "تاریخ تایید" (approved_at) for already-imported expenses from the
// Access Okdate column, without touching anything else.
// Usage: dart run tool/backfill_approval_dates.dart <export.json> [local.db]
//
// Rows are matched on project + amount + the Access InsertDate that the import
// stored as created_at. Each update goes through the normal approval operation,
// so it is also queued and reaches the shared database on the next sync.
import 'dart:convert';
import 'dart:io';

import 'package:budget_management/core/formatters.dart';
import 'package:budget_management/models/models.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:shamsi_date/shamsi_date.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/backfill_approval_dates.dart <export.json> [local.db]');
    exit(64);
  }
  final data = jsonDecode(await File(args[0]).readAsString()) as Map;
  final service = DatabaseService.instance;
  // ignore: invalid_use_of_visible_for_testing_member
  service.remoteEnabled = false;
  // ignore: invalid_use_of_visible_for_testing_member
  if (args.length > 1) service.localPathOverride = args[1];

  final names = {
    for (final p in data['projects'] as List) p['id'] as int: (p['name'] as String).trim(),
  };

  String key(String project, double amount, String? createdAt) =>
      '$project|${amount.round()}|${createdAt ?? ''}';

  // Local rows by key, oldest first (the import inserted them in CostID order).
  final local = <String, List<Expense>>{};
  final all = await service.getAllExpenses();
  for (final e in all.reversed.toList()..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0))) {
    local.putIfAbsent(key(e.projectName, e.amount, e.createdAt), () => []).add(e);
  }

  var updated = 0, noDate = 0, unmatched = 0, alreadySet = 0;
  final costs = (data['costs'] as List).cast<Map>()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  for (final c in costs) {
    if (c['selected'] != true) continue;
    final ok = c['okdate'] as String?;
    if (ok == null) {
      noDate++;
      continue;
    }
    final k = key(names[c['projectId']]!, (c['amount'] as num).toDouble(),
        c['insertDate'] as String?);
    final bucket = local[k];
    if (bucket == null || bucket.isEmpty) {
      unmatched++;
      continue;
    }
    final e = bucket.removeAt(0);
    if (e.approvedAt != null && e.approvedAt!.isNotEmpty) {
      alreadySet++;
      continue;
    }
    await service.setExpenseApproval(
      e.uid!,
      true,
      e.approvedBy ?? 'Access import',
      at: formatJalali(Jalali.fromDateTime(DateTime.parse(ok))),
    );
    updated++;
  }

  stdout.writeln('updated=$updated  approved-without-date=$noDate  '
      'already-set=$alreadySet  unmatched=$unmatched  '
      'queued-for-share=${service.pendingCount}');
  await service.close();
}
