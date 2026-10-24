import 'package:flutter/material.dart';

import '../utils/format.dart';

class KpiCard extends StatefulWidget {
  const KpiCard({super.key, required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final double value;
  final IconData icon;
  final Color color;

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E7EF)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hover ? .10 : .04), blurRadius: _hover ? 18 : 8, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          CircleAvatar(radius: 24, backgroundColor: widget.color.withValues(alpha: .12), child: Icon(widget.icon, color: widget.color)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(Fmt.money(widget.value),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.value < 0 ? Colors.red.shade700 : null)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
