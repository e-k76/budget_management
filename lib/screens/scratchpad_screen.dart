import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/calc.dart';
import '../utils/format.dart';

/// In-memory only: nothing here ever touches the database.
class ScratchpadScreen extends StatefulWidget {
  const ScratchpadScreen({super.key});
  @override
  State<ScratchpadScreen> createState() => _ScratchpadScreenState();
}

class _Row {
  final label = TextEditingController();
  final value = TextEditingController();
  double? get number => Fmt.parseMoney(value.text);
}

class _ScratchpadScreenState extends State<ScratchpadScreen> {
  final _expr = TextEditingController();
  final _history = <String>[];
  final _rows = <_Row>[_Row(), _Row(), _Row()];
  final _pct = TextEditingController(text: '10');
  String? _error;
  double? _result;

  void _evaluate() {
    try {
      final r = Calc.eval(_expr.text);
      setState(() {
        _result = r;
        _error = null;
        _history.insert(0, '${_expr.text} = ${_fmt(r)}');
        _expr.text = _plain(r);
        _expr.selection = TextSelection.collapsed(offset: _expr.text.length);
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  String _fmt(double v) => v == v.roundToDouble() ? Fmt.number(v) : _plain(v);

  void _key(String k) {
    setState(() {
      _error = null;
      if (k == 'C') {
        _expr.clear();
        _result = null;
      } else if (k == '⌫') {
        if (_expr.text.isNotEmpty) _expr.text = _expr.text.substring(0, _expr.text.length - 1);
      } else {
        _expr.text += k;
      }
      _expr.selection = TextSelection.collapsed(offset: _expr.text.length);
    });
  }

  double get _sum => _rows.fold(0, (a, r) => a + (r.number ?? 0));
  int get _count => _rows.where((r) => r.number != null).length;

  @override
  Widget build(BuildContext context) {
    final keys = ['C', '(', ')', '÷', '7', '8', '9', '×', '4', '5', '6', '-', '1', '2', '3', '+', '0', '.', '%', '⌫'];
    final pct = double.tryParse(_pct.text) ?? 0;
    final calc = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('ماشین‌حساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _expr,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 22),
            onSubmitted: (_) => _evaluate(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹.+\-*/×÷()%,\s]'))],
            decoration: InputDecoration(hintText: 'مثال: 1,200,000 × 3 ÷ 4', errorText: _error),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4, shrinkWrap: true, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.7,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final k in keys) OutlinedButton(onPressed: () => _key(k), child: Text(k, style: const TextStyle(fontSize: 18)))],
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _evaluate, child: const Text('=')),
          if (_history.isNotEmpty) ...[
            const Divider(height: 28),
            Row(children: [const Text('تاریخچه'), const Spacer(), TextButton(onPressed: () => setState(_history.clear), child: const Text('پاک کردن'))]),
            for (final h in _history.take(8)) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(h, textDirection: TextDirection.ltr)),
          ],
        ]),
      ),
    );

    final sheet = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('جدول محاسبات موقت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            if (_result != null) TextButton.icon(onPressed: () => setState(() => _rows.add(_Row()..value.text = Fmt.number(_result!))), icon: const Icon(Icons.add), label: const Text('افزودن نتیجه به جدول')),
            TextButton.icon(onPressed: () => setState(() => _rows.add(_Row())), icon: const Icon(Icons.add), label: const Text('ردیف جدید')),
          ]),
          const SizedBox(height: 8),
          for (final r in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: r.label, decoration: const InputDecoration(labelText: 'عنوان', isDense: true))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: r.value,
                    textDirection: TextDirection.ltr,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹,.\-]'))],
                    decoration: const InputDecoration(labelText: 'مقدار', isDense: true),
                  ),
                ),
                IconButton(onPressed: () => setState(() => _rows.remove(r)), icon: const Icon(Icons.close, size: 18)),
              ]),
            ),
          const Divider(height: 28),
          _stat('جمع', _sum),
          _stat('میانگین', _count == 0 ? 0 : _sum / _count),
          const SizedBox(height: 12),
          Row(children: [
            const Text('سناریوی چه‌می‌شود‌اگر: جمع'),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: _pct, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true, suffixText: '٪'))),
          ]),
          const SizedBox(height: 6),
          _stat('افزایش', _sum * (1 + pct / 100)),
          _stat('کاهش', _sum * (1 - pct / 100)),
          _stat('سهم ٪', _sum * pct / 100),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => setState(() { for (final r in _rows) { r.label.clear(); r.value.clear(); } }), child: const Text('پاک کردن جدول'))),
        ]),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('محیط موقت محاسبات')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Colors.amber.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: const Text('این محیط فقط موقت است؛ هیچ داده‌ای در پایگاه داده ذخیره نمی‌شود و با خروج از صفحه پاک می‌شود.'),
        ),
        Expanded(
          child: LayoutBuilder(builder: (c, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: box.maxWidth > 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: calc), const SizedBox(width: 16), Expanded(child: sheet)])
                : Column(children: [calc, const SizedBox(height: 16), sheet]),
          )),
        ),
      ]),
    );
  }

  Widget _stat(String t, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Text(t), const Spacer(), Text(_fmt(v), style: const TextStyle(fontWeight: FontWeight.bold))]),
      );
}
