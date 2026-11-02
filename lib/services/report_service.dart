import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../models/models.dart';

class ReportService {
  ReportService._();

  /// Dana from assets if bundled, otherwise a Persian-capable system font (raw bytes, so
  /// they can be handed to the background isolate that builds the PDF).
  static Future<Uint8List?> _fontBytes(String asset, String systemFallback) async {
    try {
      final d = await rootBundle.load(asset);
      return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    } catch (_) {}
    try {
      final f = File(systemFallback);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  // ------------------------------------------------------------ shared builder

  static pw.ThemeData _theme(Uint8List? regular, Uint8List? bold) {
    if (regular == null) return pw.ThemeData();
    pw.Font font(Uint8List b) => pw.Font.ttf(ByteData.view(b.buffer, b.offsetInBytes, b.lengthInBytes));
    return pw.ThemeData.withFont(base: font(regular), bold: font(bold ?? regular));
  }

  /// Numbers, amounts and dates read left-to-right even in an RTL table.
  static final _ltr = RegExp(r'^[-0-9,./٪%]+$');

  static pw.Widget _cell(String text,
      {bool head = false, bool bold = false, pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textDirection:
            _ltr.hasMatch(text) ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: (head || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// One printed table. [widths] are relative column widths in logical (RTL)
  /// order: the first column is printed on the right edge.
  static List<pw.Widget> _table(ReportTable t) {
    // pw.Table lays columns out left-to-right, so reverse the logical order.
    pw.TableRow row(List<String> cells,
        {bool head = false, bool footer = false, PdfColor? fill}) {
      return pw.TableRow(
        repeat: head, // column headings reappear at the top of every page
        decoration: pw.BoxDecoration(color: fill),
        children: [for (final c in cells.reversed) _cell(c, head: head, bold: footer)],
      );
    }

    // NOT wrapped in a Column: a Column cannot be split, so a table taller than one page
    // made MultiPage give up ("created more than 20 pages") and the app froze.
    // A bare pw.Table is spannable and continues on the next page.
    return [
      if (t.heading != null) ...[
        pw.Text(t.heading!,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
      ],
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: {
          for (var i = 0; i < t.widths.length; i++)
            i: pw.FlexColumnWidth(t.widths[t.widths.length - 1 - i]),
        },
        children: [
          row(t.headers, head: true, fill: PdfColors.indigo50),
          for (final r in t.rows) row(r),
          for (final f in t.footers) row(f, footer: true, fill: PdfColors.grey200),
        ],
      ),
      pw.SizedBox(height: 14),
    ];
  }

  static Future<Uint8List> _build({
    required String title,
    required String subtitle,
    required List<ReportTable> tables,
    String? note,
  }) async {
    final regular = await _fontBytes('assets/fonts/DanaFaNum-Regular.ttf', r'C:\Windows\Fonts\tahoma.ttf');
    final bold = await _fontBytes('assets/fonts/DanaFaNum-Bold.ttf', r'C:\Windows\Fonts\tahomabd.ttf') ?? regular;
    final today = todayJalali();
    // Laying out hundreds of rows takes seconds: do it off the UI thread so the window
    // keeps responding ("Not Responding") while the report is prepared.
    return Isolate.run(() => _render(title, subtitle, tables, note, regular, bold, today));
  }

  static Future<Uint8List> _render(String title, String subtitle, List<ReportTable> tables,
      String? note, Uint8List? regular, Uint8List? bold, String today) async {
    final doc = pw.Document(theme: _theme(regular, bold), title: title);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        maxPages: 2000, // long expense lists really can be hundreds of pages
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Row follows the page's RTL direction: first child sits right.
                pw.Text(AppConfig.companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('تاریخ: $today',
                    textDirection: pw.TextDirection.rtl,
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(title,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(subtitle,
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Divider(thickness: 0.8),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
        build: (ctx) => [
          for (final t in tables) ..._table(t),
          if (note != null)
            pw.Text(note,
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> _show(String name, Future<Uint8List> Function() build) {
    return Printing.layoutPdf(
      name: '$name-${todayJalali().replaceAll('/', '-')}',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => build(),
    );
  }

  static String _n(num v) => formatNumberPlain(v.toDouble());
  static String _status(bool approved) => approved ? 'تاییدشده' : 'تاییدنشده';

  // --------------------------------------------------------------- dashboard

  /// The dashboard table. «هزینه کرد کلی» counts ONLY approved (checked)
  /// expenses; «مانده هزینه» is what is still unapproved.
  @visibleForTesting
  static ReportTable dashboardTable(List<ProjectSummary> rows) {
    double sum(double Function(ProjectSummary s) f) =>
        rows.fold<double>(0, (a, s) => a + f(s));
    return ReportTable(
      headers: const [
        'ردیف',
        'نام پروژه',
        'درآمد کلی',
        'بودجه',
        'هزینه کرد کلی',
        'مانده هزینه',
        'تراز کلی',
      ],
      widths: const [30, 140, 95, 95, 95, 95, 100],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].name,
            _n(rows[i].income),
            _n(rows[i].budgetedIncome),
            _n(rows[i].approvedExpenses),
            _n(rows[i].unapprovedExpenses),
            _n(rows[i].balance),
          ],
      ],
      footers: [
        [
          '',
          'جمع کل',
          _n(sum((s) => s.income)),
          _n(sum((s) => s.budgetedIncome)),
          _n(sum((s) => s.approvedExpenses)),
          _n(sum((s) => s.unapprovedExpenses)),
          _n(sum((s) => s.balance)),
        ],
      ],
    );
  }

  static Future<Uint8List> buildDashboardPdf(
    List<ProjectSummary> rows, {
    required double budgetPercentage,
    required String printedBy,
  }) =>
      _build(
        title: 'گزارش مالی کلیه پروژه‌ها',
        subtitle: 'درصد بودجه: ${formatPercent(budgetPercentage)} | چاپ‌کننده: $printedBy',
        tables: [dashboardTable(rows)],
        note: 'مبالغ به ریال. بودجه = درآمد × درصد بودجه. '
            'هزینه کرد کلی = فقط هزینه‌های تاییدشده (تیک‌خورده). '
            'مانده هزینه = هزینه‌های تاییدنشده. تراز کلی = بودجه - هزینه‌های تاییدشده.',
      );

  static Future<void> printDashboard(
    List<ProjectSummary> rows, {
    required double budgetPercentage,
    required String printedBy,
  }) =>
      _show(
          'project-report',
          () => buildDashboardPdf(rows,
              budgetPercentage: budgetPercentage, printedBy: printedBy));

  // ----------------------------------------------------------------- project

  @visibleForTesting
  static ReportTable expensesTable(List<Expense> list, {bool withProject = false}) {
    final total = list.fold<double>(0, (a, e) => a + e.amount);
    final approved =
        list.where((e) => e.isApproved).fold<double>(0, (a, e) => a + e.amount);
    final p = withProject ? 1 : 0; // extra «پروژه» column
    List<String> foot(String label, double v) => [
          for (var i = 0; i < 8 + p; i++)
            i == 3 + p ? label : (i == 4 + p ? _n(v) : ''),
        ];
    return ReportTable(
      headers: [
        'ردیف',
        if (withProject) 'پروژه',
        'تاریخ',
        'در وجه',
        'شرح',
        'مبلغ',
        'وضعیت تایید',
        'تاییدکننده',
        'تاریخ تایید',
      ],
      widths: [28, if (withProject) 100, 62, 105, 190, 88, 62, 90, 62],
      rows: [
        for (var i = 0; i < list.length; i++)
          [
            '${i + 1}',
            if (withProject) list[i].projectName,
            list[i].date,
            list[i].payee,
            list[i].description,
            _n(list[i].amount),
            _status(list[i].isApproved),
            list[i].isApproved ? displayUser(list[i].approvedBy) : '',
            list[i].approvedAt ?? '',
          ],
      ],
      footers: [
        foot('جمع کل', total),
        foot('جمع تاییدشده', approved),
        foot('جمع تاییدنشده', total - approved),
      ],
    );
  }

  @visibleForTesting
  static ReportTable incomesTable(List<Income> list, {bool withProject = false}) {
    final total = list.fold<double>(0, (a, i) => a + i.amount);
    final p = withProject ? 1 : 0;
    return ReportTable(
      headers: [
        'ردیف',
        if (withProject) 'پروژه',
        'تاریخ',
        'مبلغ',
        'ثبت‌کننده',
      ],
      widths: [30, if (withProject) 140, 80, 110, 120],
      rows: [
        for (var i = 0; i < list.length; i++)
          [
            '${i + 1}',
            if (withProject) list[i].projectName,
            list[i].date,
            _n(list[i].amount),
            displayUser(list[i].createdBy),
          ],
      ],
      footers: [
        [
          for (var i = 0; i < 4 + p; i++)
            i == 1 + p ? 'جمع کل' : (i == 2 + p ? _n(total) : ''),
        ],
      ],
    );
  }

  static Future<Uint8List> buildProjectPdf(
    ProjectSummary s, {
    required List<Expense> expenses,
    required List<Income> incomes,
    required String filterNote,
    required String printedBy,
  }) =>
      _build(
        title: 'گزارش پروژه: ${s.name}',
        subtitle: 'درصد بودجه: ${formatPercent(s.budgetPercentage)} | چاپ‌کننده: $printedBy'
            '${filterNote.isEmpty ? '' : ' | $filterNote'}',
        tables: [
          ReportTable(
            heading: 'خلاصه مالی',
            headers: const [
              'درآمد کلی',
              'بودجه',
              'هزینه کرد کلی',
              'مانده هزینه',
              'تراز کلی',
            ],
            widths: const [100, 100, 100, 100, 100],
            rows: [
              [
                _n(s.income),
                _n(s.budgetedIncome),
                _n(s.approvedExpenses),
                _n(s.unapprovedExpenses),
                _n(s.balance),
              ],
            ],
          ),
          ReportTable.titled('هزینه‌ها / درخواست‌های وجه', expensesTable(expenses)),
          ReportTable.titled('درآمدها', incomesTable(incomes)),
        ],
        note: 'مبالغ به ریال. هزینه کرد کلی = فقط هزینه‌های تاییدشده (تیک‌خورده). '
            'مانده هزینه = هزینه‌های تاییدنشده. تراز کلی = بودجه - هزینه‌های تاییدشده.',
      );

  static Future<void> printProject(
    ProjectSummary s, {
    required List<Expense> expenses,
    required List<Income> incomes,
    required String filterNote,
    required String printedBy,
  }) =>
      _show(
          'project-${s.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}',
          () => buildProjectPdf(s,
              expenses: expenses,
              incomes: incomes,
              filterNote: filterNote,
              printedBy: printedBy));

  // ------------------------------------------------------------------- lists

  static Future<Uint8List> buildExpensesPdf(
    List<Expense> list, {
    required String filterNote,
    required String printedBy,
  }) =>
      _build(
        title: 'فهرست هزینه‌ها (کلیه پروژه‌ها)',
        subtitle: 'چاپ‌کننده: $printedBy${filterNote.isEmpty ? '' : ' | $filterNote'}',
        tables: [expensesTable(list, withProject: true)],
        note: 'مبالغ به ریال. فقط ردیف‌های نمایش‌داده‌شده با فیلتر فعلی چاپ شده‌اند.',
      );

  static Future<void> printExpenses(
    List<Expense> list, {
    required String filterNote,
    required String printedBy,
  }) =>
      _show('expenses',
          () => buildExpensesPdf(list, filterNote: filterNote, printedBy: printedBy));

  static Future<Uint8List> buildIncomesPdf(
    List<Income> list, {
    required String filterNote,
    required String printedBy,
  }) =>
      _build(
        title: 'فهرست درآمدها (کلیه پروژه‌ها)',
        subtitle: 'چاپ‌کننده: $printedBy${filterNote.isEmpty ? '' : ' | $filterNote'}',
        tables: [incomesTable(list, withProject: true)],
        note: 'مبالغ به ریال. فقط ردیف‌های نمایش‌داده‌شده با فیلتر فعلی چاپ شده‌اند.',
      );

  static Future<void> printIncomes(
    List<Income> list, {
    required String filterNote,
    required String printedBy,
  }) =>
      _show('incomes',
          () => buildIncomesPdf(list, filterNote: filterNote, printedBy: printedBy));
}

/// A printable table. Column order is logical (RTL): first column prints on the right.
class ReportTable {
  const ReportTable({
    this.heading,
    required this.headers,
    required this.widths,
    required this.rows,
    this.footers = const [],
  });

  factory ReportTable.titled(String heading, ReportTable t) => ReportTable(
      heading: heading,
      headers: t.headers,
      widths: t.widths,
      rows: t.rows,
      footers: t.footers);

  final String? heading;
  final List<String> headers;
  final List<double> widths;
  final List<List<String>> rows;
  final List<List<String>> footers;
}
