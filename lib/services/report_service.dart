import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../models/models.dart';

class ReportService {
  ReportService._();

  /// Dana from assets if bundled, otherwise a Persian-capable system font.
  static Future<pw.Font?> _loadFont(String asset, String systemFallback) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } catch (_) {}
    try {
      final f = File(systemFallback);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        return pw.Font.ttf(ByteData.view(Uint8List.fromList(bytes).buffer));
      }
    } catch (_) {}
    return null;
  }

  static Future<Uint8List> buildDashboardPdf(
    List<ProjectSummary> rows, {
    required double budgetPercentage,
    required String printedBy,
  }) async {
    final regular = await _loadFont(
        'assets/fonts/DanaFaNum-Regular.ttf', r'C:\Windows\Fonts\tahoma.ttf');
    final bold = await _loadFont(
            'assets/fonts/DanaFaNum-Bold.ttf', r'C:\Windows\Fonts\tahomabd.ttf') ??
        regular;

    final theme = (regular == null)
        ? pw.ThemeData()
        : pw.ThemeData.withFont(base: regular, bold: bold);

    final totalIncome = rows.fold<double>(0, (a, s) => a + s.income);
    final totalBudget = rows.fold<double>(0, (a, s) => a + s.budgetedIncome);
    final totalExp = rows.fold<double>(0, (a, s) => a + s.totalExpenses);
    final totalRem = rows.fold<double>(0, (a, s) => a + s.unapprovedExpenses);
    final totalBal = rows.fold<double>(0, (a, s) => a + s.balance);

    const headers = [
      'ردیف',
      'نام پروژه',
      'درآمد کلی',
      'بودجه',
      'هزینه کرد کلی',
      'مانده هزینه',
      'تراز کلی',
    ];
    const widths = <double>[30, 140, 95, 95, 95, 95, 100];

    // pw.Table lays columns out left-to-right, so reverse the logical (RTL)
    // order to get the first column on the right edge.
    pw.Widget cell(String text,
        {bool head = false, bool bold = false, PdfColor? color}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          text,
          textDirection: RegExp(r'^-?[0-9,]+$').hasMatch(text)
              ? pw.TextDirection.ltr
              : pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: (head || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );
    }

    pw.TableRow row(List<String> cells,
        {bool head = false, bool footer = false, PdfColor? fill}) {
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: fill),
        children: [
          for (final c in cells.reversed)
            cell(c, head: head, bold: footer),
        ],
      );
    }

    final body = <pw.TableRow>[
      row(headers, head: true, fill: PdfColors.indigo50),
      for (var i = 0; i < rows.length; i++)
        row([
          '${i + 1}',
          rows[i].name,
          formatNumberPlain(rows[i].income),
          formatNumberPlain(rows[i].budgetedIncome),
          formatNumberPlain(rows[i].totalExpenses),
          formatNumberPlain(rows[i].unapprovedExpenses),
          formatNumberPlain(rows[i].balance),
        ]),
      row([
        '',
        'جمع کل',
        formatNumberPlain(totalIncome),
        formatNumberPlain(totalBudget),
        formatNumberPlain(totalExp),
        formatNumberPlain(totalRem),
        formatNumberPlain(totalBal),
      ], footer: true, fill: PdfColors.grey200),
    ];

    final doc = pw.Document(theme: theme, title: 'گزارش مالی پروژه‌ها');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Row follows the page's RTL direction: first child sits right.
                pw.Text(AppConfig.companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('تاریخ: ${todayJalali()}',
                    textDirection: pw.TextDirection.rtl,
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
                'گزارش مالی کلیه پروژه‌ها — درصد بودجه: ${formatPercent(budgetPercentage)} — چاپ‌کننده: $printedBy',
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
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
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
            columnWidths: {
              for (var i = 0; i < widths.length; i++)
                i: pw.FlexColumnWidth(widths[widths.length - 1 - i]),
            },
            children: body,
          ),
          pw.SizedBox(height: 8),
          pw.Text('مبالغ به ریال. بودجه = درآمد × درصد بودجه. مانده هزینه = هزینه‌های تاییدنشده. تراز کلی = بودجه − هزینه‌های تاییدشده.',
              textDirection: pw.TextDirection.rtl,
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> printDashboard(
    List<ProjectSummary> rows, {
    required double budgetPercentage,
    required String printedBy,
  }) async {
    await Printing.layoutPdf(
      name: 'project-report-${todayJalali().replaceAll('/', '-')}',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => buildDashboardPdf(rows,
          budgetPercentage: budgetPercentage, printedBy: printedBy),
    );
  }
}
