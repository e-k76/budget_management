import 'package:flutter/material.dart';

/// Document icon with a round check (approved) or cross (unapproved) badge.
class DocStatusIcon extends StatelessWidget {
  const DocStatusIcon({super.key, required this.approved, this.size = 28});

  final bool approved;
  final double size;

  static const Color approvedColor = Color(0xFF22A559);
  static const Color unapprovedColor = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.6;
    final color = approved ? approvedColor : unapprovedColor;
    return SizedBox(
      width: size + 6,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(Icons.description_outlined,
                size: size, color: const Color(0xFF1F2937)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(approved ? Icons.check_rounded : Icons.close_rounded,
                  size: badge * 0.75, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded square with a dollar sign and an arrow leaving it (money out).
/// Takes its colour and size from the surrounding [IconTheme], so it works as
/// a navigation icon.
class CashOutIcon extends StatelessWidget {
  const CashOutIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    final color = theme.color ?? Colors.black87;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _CashOutPainter(color)),
          Padding(
            padding: EdgeInsets.only(right: size * 0.2),
            child: Icon(Icons.attach_money_rounded, size: size * 0.6, color: color),
          ),
        ],
      ),
    );
  }
}

class _CashOutPainter extends CustomPainter {
  _CashOutPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final box = RRect.fromLTRBR(
        s * 0.08, s * 0.12, s * 0.72, s * 0.88, Radius.circular(s * 0.22));

    // Square with a gap on its right side where the arrow leaves.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRRect(box, paint);
    canvas.drawRect(
      Rect.fromLTRB(s * 0.6, s * 0.38, s * 0.8, s * 0.62),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    // Arrow.
    final y = s * 0.5;
    canvas.drawLine(Offset(s * 0.66, y), Offset(s * 0.94, y), paint);
    canvas.drawLine(Offset(s * 0.80, y - s * 0.14), Offset(s * 0.94, y), paint);
    canvas.drawLine(Offset(s * 0.80, y + s * 0.14), Offset(s * 0.94, y), paint);
  }

  @override
  bool shouldRepaint(_CashOutPainter old) => old.color != color;
}
