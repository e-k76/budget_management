import 'package:flutter/material.dart';

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'حذف',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
    this.expand = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Fill the parent's height and give the child all remaining space.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            if (expand) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable table that stretches to the available width.
class ScrollableTable extends StatelessWidget {
  const ScrollableTable({super.key, required this.table});
  final Widget table;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: table,
        ),
      ),
    );
  }
}

class PinnedColumn {
  const PinnedColumn(this.label, {this.flex = 1, this.minWidth = 100});
  final String label;
  final int flex;
  final double minWidth;
}

/// Table whose header (and optional footer) stay put while the rows scroll.
/// It fills the height it is given, so place it inside an [Expanded].
class PinnedTable extends StatelessWidget {
  const PinnedTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.onRowTap,
    this.rowHeight = 52,
  });

  final List<PinnedColumn> columns;
  final List<List<Widget>> rows;
  final List<Widget>? footer;
  final void Function(int index)? onRowTap;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5));

    Widget line(List<Widget> cells,
        {Color? color, TextStyle? style, VoidCallback? onTap}) {
      return Material(
        color: color ?? Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: divider)),
            child: DefaultTextStyle.merge(
              style: style,
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    Expanded(
                      flex: columns[i].flex,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: cells[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final minW = columns.fold<double>(0, (a, b) => a + b.minWidth);
      final width = c.maxWidth < minW ? minW : c.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: c.maxHeight,
          child: Column(
            children: [
              line(
                [for (final col in columns) Text(col.label)],
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemExtent: rowHeight,
                  itemBuilder: (_, i) => line(
                    rows[i],
                    onTap: onRowTap == null ? null : () => onRowTap!(i),
                  ),
                ),
              ),
              if (footer != null)
                line(
                  footer!,
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
      );
    });
  }
}
