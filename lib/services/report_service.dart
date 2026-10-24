import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/project.dart';
import '../utils/format.dart';

class ReportService {
  static const companyName = 'نام شرکت'; // TODO: set your company name
  static final format = PdfPageFormat.a4.landscape;

  static Future<Uint8List> buildDashboardReport(List<Project> projects, String printedBy) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    const rtl = pw.TextDirection.rtl;
    const headers = ['ردیف', 'نام پروژه', 'درآمد کلی', 'هزینه کرد کلی', 'مانده هزینه', 'درصد بودجه', 'تراز کلی'];
    const flex = [1, 4, 3, 3, 3, 2, 3];

    pw.Widget cell(int i, String t, {bool head = false, PdfColor? color, PdfColor? bg}) => pw.Expanded(
          flex: flex[i],
          child: pw.Container(
            color: bg,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: .5)),
            child: pw.Text(t,
                textDirection: i == 1 ? rtl : pw.TextDirection.ltr,
                textAlign: i == 1 ? pw.TextAlign.right : pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10, fontWeight: head ? pw.FontWeight.bold : null, color: color)),
          ),
        );

    pw.Widget row(List<String> v, {bool head = false, PdfColor? bg, PdfColor? balanceColor}) => pw.Row(
          textDirection: rtl,
          children: [for (var i = 0; i < v.length; i++) cell(i, v[i], head: head, bg: bg, color: i == 6 ? balanceColor : null)],
        );

    final totalIncome = projects.fold(0.0, (a, p) => a + p.totalIncome);
    final totalExp = projects.fold(0.0, (a, p) => a + p.totalExpenses);
    final totalBal = projects.fold(0.0, (a, p) => a + p.balance);

    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      textDirection: rtl,
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(textDirection: rtl, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(companyName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('تاریخ: ${Fmt.today()}'),
        ]),
        pw.SizedBox(height: 4),
        pw.Text('گزارش مالی کلیه پروژه‌ها', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
      ]),
      footer: (c) => pw.Row(textDirection: rtl, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('چاپ‌کننده: $printedBy', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('صفحه ${c.pageNumber} از ${c.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
      ]),
      build: (_) => [
        row(headers, head: true, bg: PdfColors.grey200),
        for (var i = 0; i < projects.length; i++)
          row([
            '${i + 1}',
            projects[i].name,
            Fmt.number(projects[i].totalIncome),
            Fmt.number(projects[i].totalExpenses),
            Fmt.number(projects[i].remaining),
            Fmt.percent(projects[i].budgetPercentage),
            Fmt.number(projects[i].balance),
          ], balanceColor: projects[i].balance < 0 ? PdfColors.red800 : PdfColors.green800),
        row(['', 'جمع کل', Fmt.number(totalIncome), Fmt.number(totalExp), Fmt.number(totalIncome - totalExp), '', Fmt.number(totalBal)],
            head: true, bg: PdfColors.grey100, balanceColor: totalBal < 0 ? PdfColors.red800 : PdfColors.green800),
        pw.SizedBox(height: 8),
        pw.Text('کلیه مبالغ به ریال می‌باشد.', style: const pw.TextStyle(fontSize: 9)),
      ],
    ));
    return doc.save();
  }
}
