import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app opens the way the product works: a dark void, a ring gathering, then a portal
/// that ignites and throws a handful of stars before it dissolves into the working screen.
class PortalLaunchGate extends StatefulWidget {
  const PortalLaunchGate({super.key, required this.child});

  final Widget child;

  @override
  State<PortalLaunchGate> createState() => _PortalLaunchGateState();
}

class _PortalLaunchGateState extends State<PortalLaunchGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final List<_Spark> _stars = _burst(math.Random());
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Spark> _burst(math.Random random) => [
        for (var i = 0; i < 36; i++)
          (
            angle: random.nextDouble() * math.pi * 2,
            speed: 0.45 + random.nextDouble() * 0.55,
            size: 0.8 + random.nextDouble() * 1.6,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  // 0.00–0.55 gather, 0.55–0.80 ignite, 0.80–1.00 dissolve.
                  final ignite = ((t - 0.55) / 0.25).clamp(0.0, 1.0);
                  final dissolve = ((t - 0.80) / 0.20).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1 - dissolve,
                    child: CustomPaint(
                      painter: _LaunchPainter(
                        turn: t,
                        ignite: ignite,
                        portal: scheme.primary,
                        accent: scheme.tertiary,
                        sparks: _stars,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

typedef _Spark = ({double angle, double speed, double size});

class _LaunchPainter extends CustomPainter {
  const _LaunchPainter({
    required this.turn,
    required this.ignite,
    required this.portal,
    required this.accent,
    required this.sparks,
  });

  final double turn;
  final double ignite;
  final Color portal;
  final Color accent;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final base = shortest * 0.16;
    final void0 = Paint()..color = const Color(0xFF05060A);
    canvas.drawRect(Offset.zero & size, void0);

    // A ring gathers: it starts wide and faint, then tightens onto the portal.
    final gather = (turn / 0.55).clamp(0.0, 1.0);
    final gatherRadius = base * (3.2 - 2.0 * gather);
    canvas.drawCircle(
      center,
      gatherRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = portal.withValues(alpha: 0.10 + 0.45 * gather),
    );

    final coreRadius = base * (0.22 + 0.78 * ignite);
    if (ignite > 0) {
      canvas.drawCircle(
        center,
        coreRadius * 1.9,
        Paint()
          ..shader = RadialGradient(
            colors: [
              portal.withValues(alpha: 0.34 * ignite),
              portal.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 1.9)),
      );
      canvas.drawCircle(
        center,
        coreRadius,
        Paint()..color = const Color(0xFF0A0C14),
      );
      canvas.drawCircle(
        center,
        coreRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = portal.withValues(alpha: 0.85 * ignite),
      );

      // Stars thrown by the ignition, travelling out and fading.
      final travel = ((turn - 0.55) / 0.45).clamp(0.0, 1.0);
      for (final spark in sparks) {
        final distance = base * (0.4 + travel * 3.4 * spark.speed);
        final offset = Offset(
          center.dx + math.cos(spark.angle) * distance,
          center.dy + math.sin(spark.angle) * distance,
        );
        canvas.drawCircle(
          offset,
          spark.size * (1 - travel * 0.6),
          Paint()
            ..color = (spark.size > 1.6 ? accent : Colors.white)
                .withValues(alpha: (1 - travel) * 0.9),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LaunchPainter oldDelegate) =>
      oldDelegate.turn != turn || oldDelegate.ignite != ignite;
}
