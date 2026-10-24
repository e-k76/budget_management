import 'package:flutter/material.dart';

import '../core/formatters.dart';

enum ApprovalFilter { all, approved, unapproved }

extension ApprovalFilterX on ApprovalFilter {
  /// Whether an expense with this approval state passes the filter.
  bool allows(bool isApproved) => switch (this) {
        ApprovalFilter.all => true,
        ApprovalFilter.approved => isApproved,
        ApprovalFilter.unapproved => !isApproved,
      };
}

/// Dropdown: همه / تایید شده / تایید نشده.
class ApprovalFilterField extends StatelessWidget {
  const ApprovalFilterField({super.key, required this.value, required this.onChanged});

  final ApprovalFilter value;
  final ValueChanged<ApprovalFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<ApprovalFilter>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'وضعیت تایید', isDense: true),
        items: const [
          DropdownMenuItem(value: ApprovalFilter.all, child: Text('همه')),
          DropdownMenuItem(value: ApprovalFilter.approved, child: Text('تایید شده')),
          DropdownMenuItem(value: ApprovalFilter.unapproved, child: Text('تایید نشده')),
        ],
        onChanged: (v) => onChanged(v ?? value),
      ),
    );
  }
}

/// An amount that can be clicked to add it to / remove it from the temporary
/// sum. Picked amounts are highlighted.
class PickableAmount extends StatelessWidget {
  const PickableAmount({
    super.key,
    required this.amount,
    required this.picked,
    required this.onTap,
  });

  final double amount;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: picked ? 'حذف از جمع موقت' : 'افزودن به جمع موقت',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: picked ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: picked ? scheme.primary : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picked) ...[
                Icon(Icons.check_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
              ],
              Text(
                formatNumber(amount),
                style: TextStyle(
                  fontWeight: picked ? FontWeight.w800 : FontWeight.normal,
                  color: picked ? scheme.onPrimaryContainer : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "جمع موقت" bar: total of the amounts clicked in the table, with a button to
/// clear them all.
class TempSumBar extends StatelessWidget {
  const TempSumBar({
    super.key,
    required this.count,
    required this.total,
    required this.onClear,
  });

  final int count;
  final double total;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = count > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('جمع موقت',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  active
                      ? formatMoney(total)
                      : 'برای جمع زدن، روی مبلغ هر هزینه کلیک کنید',
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w800 : FontWeight.normal,
                    fontSize: active ? 16 : 13,
                    color: active ? scheme.primary : Theme.of(context).hintColor,
                  ),
                ),
                if (active)
                  Text('($count مورد)',
                      style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: active ? onClear : null,
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('پاک کردن'),
          ),
        ],
      ),
    );
  }
}
