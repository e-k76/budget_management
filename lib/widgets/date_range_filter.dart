import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/date_range.dart';
import '../core/formatters.dart';
import 'form_fields.dart';

/// «از تاریخ / تا تاریخ» filter with calendar pickers and quick presets.
/// The parent owns the [range]; typing a valid date (or picking one) updates it.
class DateRangeFilter extends StatefulWidget {
  const DateRangeFilter({super.key, required this.range, required this.onChanged});

  final DateRange range;
  final ValueChanged<DateRange> onChanged;

  @override
  State<DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends State<DateRangeFilter> {
  late final _from = TextEditingController(text: widget.range.from ?? '');
  late final _to = TextEditingController(text: widget.range.to ?? '');

  @override
  void didUpdateWidget(DateRangeFilter old) {
    super.didUpdateWidget(old);
    // The parent changed the range (preset / clear): reflect it in the boxes.
    if (_parse(_from.text) != widget.range.from) _from.text = widget.range.from ?? '';
    if (_parse(_to.text) != widget.range.to) _to.text = widget.range.to ?? '';
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  static String? _parse(String text) {
    final j = parseJalali(text);
    return j == null ? null : formatJalali(j);
  }

  void _emit() => widget.onChanged(DateRange(from: _parse(_from.text), to: _parse(_to.text)));

  Future<void> _pick(TextEditingController c) async {
    final picked = await pickJalaliDate(context, parseJalali(c.text) ?? Jalali.now());
    if (picked != null) {
      c.text = formatJalali(picked);
      _emit();
    }
  }

  void _preset(DateRange r) {
    _from.text = r.from ?? '';
    _to.text = r.to ?? '';
    _emit();
  }

  Widget _box(TextEditingController c, String label, {String? error}) => SizedBox(
        width: 165,
        child: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.datetime,
          onChanged: (_) {
            _emit();
            setState(() {});
          },
          decoration: InputDecoration(
            labelText: label,
            hintText: '1403/01/01',
            isDense: true,
            errorText: error,
            suffixIcon: IconButton(
              tooltip: 'انتخاب تاریخ',
              icon: const Icon(Icons.calendar_month_outlined, size: 20),
              onPressed: () => _pick(c),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final today = Jalali.now();
    String? err(TextEditingController c) =>
        c.text.trim().isNotEmpty && _parse(c.text) == null ? 'تاریخ نامعتبر' : null;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        _box(_from, 'از تاریخ', error: err(_from)),
        _box(_to, 'تا تاریخ',
            error: err(_to) ?? (widget.range.isInverted ? 'قبل از تاریخ شروع' : null)),
        PopupMenuButton<DateRange>(
          tooltip: 'بازه‌های آماده',
          icon: const Icon(Icons.date_range_outlined),
          onSelected: _preset,
          itemBuilder: (_) => [
            PopupMenuItem(value: DateRange.thisMonth(today), child: const Text('این ماه')),
            PopupMenuItem(value: DateRange.lastMonth(today), child: const Text('ماه گذشته')),
            PopupMenuItem(value: DateRange.last30Days(today), child: const Text('۳۰ روز اخیر')),
            PopupMenuItem(value: DateRange.thisYear(today), child: const Text('امسال')),
          ],
        ),
        if (widget.range.isActive || _from.text.isNotEmpty || _to.text.isNotEmpty)
          IconButton(
            tooltip: 'حذف بازه تاریخ',
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => _preset(const DateRange()),
          ),
      ],
    );
  }
}
