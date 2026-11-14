import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The portal itself, drawn the way the legacy PortalVPN gateway drew it: a
/// breathing core with two rings turning in opposite directions.
///
/// It is only the visual layer and keeps no state of its own: the caller owns
/// the toggle, the run time and the suspended flag, so the button behaves the
/// same as the plain one it replaces.
class PortalGatewayCore extends StatefulWidget {
  const PortalGatewayCore({
    super.key,
    required this.isStart,
    required this.suspended,
    required this.runTime,
    this.size = 168,
    this.center,
  });

  final bool isStart;
  final bool suspended;
  final int? runTime;
  final double size;

  /// The connected server's mark, shown inside a lit portal.
  final Widget? center;

  @override
  State<PortalGatewayCore> createState() => _PortalGatewayCoreState();
}

class _PortalGatewayCoreState extends State<PortalGatewayCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final portal = colorScheme.primary;
    final accent = colorScheme.tertiary;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget core;
    if (!widget.isStart) {
      // The portal is off: nothing is drawn inside the hole.
      core = const SizedBox.shrink();
    } else if (widget.center != null) {
      core = widget.center!;
    } else if (widget.suspended) {
      core = const GlyphIcon(AppGlyphs.wifiOff, size: 34, fill: 1);
    } else {
      core = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlyphIcon(AppGlyphs.stop, size: 26, fill: 1),
          const SizedBox(height: 6),
          Text(
            getTimeText(widget.runTime),
            style: AppTextStyle.title3.of(context),
          ),
        ],
      );
    }
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = reduced ? 0.0 : _controller.value;
          final pulse = reduced ? 1.0 : 0.95 + 0.11 * _pulseWave(t);
          return Transform.scale(
            scale: pulse,
            child: CustomPaint(
              painter: _GatewayPainter(
                portal: portal,
                accent: accent,
                turn: t,
                active: widget.isStart,
              ),
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(color: portal),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: portal),
                    child: child!,
                  ),
                ),
              ),
            ),
          );
        },
        child: core,
      ),
    );
  }

  /// 0 → 1 → 0 across the loop, so the breathing is symmetric.
  double _pulseWave(double t) => math.sin(t * math.pi * 2).abs();
}

class _GatewayPainter extends CustomPainter {
  const _GatewayPainter({
    required this.portal,
    required this.accent,
    required this.turn,
    required this.active,
  });

  final Color portal;
  final Color accent;
  final double turn;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final dim = active ? 1.0 : 1.0;

    if (!active) {
      // A black hole: the portal is there, but nothing comes out of it.
      final hole = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF000000),
            const Color(0xFF06070B),
            portal.withValues(alpha: 0.10),
          ],
          stops: const [0.0, 0.72, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, hole);
      final horizon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = portal.withValues(alpha: 0.22);
      canvas.drawCircle(center, radius - 2, horizon);
      return;
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          portal.withValues(alpha: 0.32 * dim),
          portal.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = portal.withValues(alpha: 0.9 * dim);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      turn * math.pi * 2,
      math.pi * 1.25,
      false,
      outer,
    );

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.75 * dim);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 18),
      -turn * math.pi * 2 * 1.5,
      math.pi * 0.9,
      false,
      inner,
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = portal.withValues(alpha: 0.18 * dim);
    canvas.drawCircle(center, radius - 30, rim);
  }

  @override
  bool shouldRepaint(_GatewayPainter oldDelegate) =>
      oldDelegate.turn != turn ||
      oldDelegate.active != active ||
      oldDelegate.portal != portal ||
      oldDelegate.accent != accent;
}
