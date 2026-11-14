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
    this.intensity = 0,
    this.connections = 0,
    this.rateText,
  });

  final bool isStart;
  final bool suspended;
  final int? runTime;
  final double size;

  /// The connected server's mark, shown inside a lit portal.
  final Widget? center;

  /// Live traffic pressure 0..1: it decides how many packets cross the portal and how
  /// fast they move, so the picture follows the wire instead of a fixed loop.
  final double intensity;

  /// Open connections in the engine right now, and their measured rate.
  final int connections;
  final String? rateText;

  @override
  State<PortalGatewayCore> createState() => _PortalGatewayCoreState();
}

class _PortalGatewayCoreState extends State<PortalGatewayCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  )..repeat();

  /// One randomly generated sky. Regenerated every cycle so the picture is never the
  /// same twice, which is the point of a porthole.
  _SpaceField _space = _SpaceField.generate(math.Random());
  double _lastTurn = 0;

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
      core = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.center!,
          if (widget.rateText != null) ...[
            const SizedBox(height: 4),
            Text(
              '${widget.connections} · ${widget.rateText}',
              style: AppTextStyle.caption1.of(context).copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      );
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
          var t = reduced ? 0.0 : _controller.value;
          if (!reduced && t < _lastTurn) {
            _space = _SpaceField.generate(math.Random());
          }
          _lastTurn = t;
          final pulse = reduced ? 1.0 : 0.95 + 0.11 * _pulseWave(t);
          return Transform.scale(
            scale: pulse,
            child: CustomPaint(
              painter: _GatewayPainter(
                portal: portal,
                accent: accent,
                turn: t,
                active: widget.isStart,
                intensity: widget.intensity,
                space: _space,
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
    required this.intensity,
    required this.space,
  });

  final Color portal;
  final Color accent;
  final double turn;
  final bool active;
  final double intensity;
  final _SpaceField space;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

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

    // A porthole into space: flat Material shapes, never the same sky twice.
    final skyRect = Rect.fromCircle(center: center, radius: radius - 1);
    canvas.save();
    canvas.clipPath(Path()..addOval(skyRect));

    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF080B18), Color(0xFF0D0A1E), Color(0xFF02030A)],
      ).createShader(skyRect);
    canvas.drawRect(skyRect, sky);

    for (final nebula in space.nebulae) {
      final spot = Offset(
        center.dx + nebula.x * radius * 0.8,
        center.dy + nebula.y * radius * 0.8,
      );
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            nebula.color.withValues(alpha: 0.22),
            nebula.color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: spot, radius: nebula.radius * radius));
      canvas.drawCircle(spot, nebula.radius * radius, paint);
    }

    for (final star in space.stars) {
      final offset = Offset(
        center.dx + star.x * radius * 0.94,
        center.dy + star.y * radius * 0.94,
      );
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(turn * math.pi * 2 + star.phase));
      canvas.drawCircle(
        offset,
        star.radius,
        Paint()..color = Colors.white.withValues(alpha: twinkle * 0.9),
      );
    }

    for (final planet in space.planets) {
      final centerPlanet = Offset(
        center.dx + planet.x * radius * 0.62,
        center.dy + planet.y * radius * 0.62,
      );
      final planetRadius = planet.radius * radius;
      if (planet.ring) {
        canvas.save();
        canvas.translate(centerPlanet.dx, centerPlanet.dy);
        canvas.rotate(-0.42);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: planetRadius * 3.4,
            height: planetRadius * 1.1,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = planet.color.withValues(alpha: 0.55),
        );
        canvas.restore();
      }
      canvas.drawCircle(
        centerPlanet,
        planetRadius,
        Paint()..color = planet.color,
      );
      canvas.drawCircle(
        centerPlanet,
        planetRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18),
      );
    }

    for (final comet in space.comets) {
      final progress = (turn * 1.6 + comet.offset) % 1.0;
      final head = Offset(
        center.dx + comet.x * radius + comet.dx * radius * progress,
        center.dy + comet.y * radius + comet.dy * radius * progress,
      );
      final tail = Offset(
        head.dx - comet.dx * radius * 0.22,
        head.dy - comet.dy * radius * 0.22,
      );
      final fade = math.sin(progress * math.pi);
      canvas.drawPath(
        Path()
          ..moveTo(tail.dx, tail.dy)
          ..lineTo(head.dx, head.dy),
        Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              comet.color.withValues(alpha: 0.0),
              comet.color.withValues(alpha: 0.85 * fade),
            ],
          ).createShader(Rect.fromPoints(tail, head)),
      );
      canvas.drawCircle(
        head,
        2.4,
        Paint()..color = Colors.white.withValues(alpha: fade),
      );
    }

    canvas.restore();

    // The porthole frame stays, so the sky still reads as the portal.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = portal.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_GatewayPainter oldDelegate) =>
      oldDelegate.turn != turn ||
      oldDelegate.active != active ||
      oldDelegate.portal != portal ||
      oldDelegate.accent != accent ||
      oldDelegate.space != space;
}


typedef _Star = ({double x, double y, double radius, double phase});
typedef _Planet = ({double x, double y, double radius, Color color, bool ring});
typedef _Comet = ({double x, double y, double dx, double dy, double offset, Color color});
typedef _Nebula = ({double x, double y, double radius, Color color});

/// A randomly generated sky for the portal. Coordinates are in units of the portal
/// radius, so the same scene fits any size.
class _SpaceField {
  const _SpaceField({
    required this.stars,
    required this.planets,
    required this.comets,
    required this.nebulae,
  });

  final List<_Star> stars;
  final List<_Planet> planets;
  final List<_Comet> comets;
  final List<_Nebula> nebulae;

  static const _palette = [
    Color(0xFF7C6CF6),
    Color(0xFF54C7E8),
    Color(0xFFE8A25C),
    Color(0xFF9BE8C4),
    Color(0xFFE86C9B),
  ];

  static _SpaceField generate(math.Random random) {
    double unit() => random.nextDouble() * 2 - 1;

    final stars = <_Star>[
      for (var i = 0; i < 46; i++)
        (
          x: unit(),
          y: unit(),
          radius: 0.5 + random.nextDouble() * 1.1,
          phase: random.nextDouble() * math.pi * 2,
        ),
    ];

    final planets = <_Planet>[
      for (var i = 0; i < 1 + random.nextInt(2); i++)
        (
          x: unit() * 0.75,
          y: unit() * 0.75,
          radius: 0.13 + random.nextDouble() * 0.14,
          color: _palette[random.nextInt(_palette.length)],
          ring: random.nextDouble() < 0.45,
        ),
    ];

    final comets = <_Comet>[
      for (var i = 0; i < 2 + random.nextInt(2); i++)
        (
          x: unit() * 1.2,
          y: unit() * 1.2,
          dx: (random.nextDouble() * 1.4 + 0.6) * (random.nextBool() ? 1 : -1),
          dy: (random.nextDouble() * 1.2 + 0.5) * (random.nextBool() ? 1 : -1),
          offset: random.nextDouble(),
          color: _palette[random.nextInt(_palette.length)],
        ),
    ];

    final nebulae = <_Nebula>[
      for (var i = 0; i < 2; i++)
        (
          x: unit() * 0.7,
          y: unit() * 0.7,
          radius: 0.35 + random.nextDouble() * 0.35,
          color: _palette[random.nextInt(_palette.length)],
        ),
    ];

    return _SpaceField(
      stars: stars,
      planets: planets,
      comets: comets,
      nebulae: nebulae,
    );
  }
}
