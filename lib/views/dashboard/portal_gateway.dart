import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

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
  // An endless clock, not a cycle: nothing rewinds, so the sky never cuts back to a
  // beginning. Depth is a function of elapsed seconds.
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) {
    _clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  })..start();

  final _SpaceField _space = _SpaceField.generate(math.Random());

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
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
        animation: _clock,
        builder: (context, child) {
          final t = reduced ? 0.0 : _clock.value;
          final pulse = reduced ? 1.0 : 0.97 + 0.05 * _pulseWave(t);
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

  /// Breathing on the endless clock: one breath per 2.5 seconds.
  double _pulseWave(double seconds) => math.sin(seconds * 0.8).abs();
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

    // Everything drifts outward from the centre: depth maps to radius, so the sky
    // flies at the viewer instead of cutting to another frame.
    final flow = turn * 0.22;

    for (final star in space.stars) {
      final z = (star.z + flow * star.speed) % 1.0;
      final distance = radius * 0.98 * z * z;
      final offset = Offset(
        center.dx + math.cos(star.angle) * distance,
        center.dy + math.sin(star.angle) * distance,
      );
      final edge = math.min(1.0, (1.0 - z) / 0.08);
      final twinkle = 0.55 + 0.45 * math.sin(turn * 2.4 + star.angle * 9);
      final alpha = (0.15 + 0.85 * z) * edge * twinkle;
      canvas.drawCircle(
        offset,
        star.size * (0.35 + z * 1.7),
        Paint()..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }

    for (final planet in space.planets) {
      final z = (planet.z + flow * 0.15 * planet.speed) % 1.0;
      final distance = radius * 0.9 * z * z;
      final planetCenter = Offset(
        center.dx + math.cos(planet.angle) * distance,
        center.dy + math.sin(planet.angle) * distance,
      );
      final planetRadius = radius * planet.radius * (0.35 + z * 2.1);
      // Grow in and out of the frame instead of appearing at full size.
      final fadeIn = (z / 0.12).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - z) / 0.12).clamp(0.0, 1.0);
      final alpha = fadeIn * fadeOut;
      if (alpha <= 0.01) continue;

      if (planet.ring) {
        canvas.save();
        canvas.translate(planetCenter.dx, planetCenter.dy);
        canvas.rotate(-0.42 + planet.angle);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: planetRadius * 3.4,
            height: planetRadius * 1.1,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = planet.color.withValues(alpha: 0.5 * alpha),
        );
        canvas.restore();
      }
      canvas.drawCircle(
        planetCenter,
        planetRadius,
        Paint()..color = planet.color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        planetCenter,
        planetRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.16 * alpha),
      );
    }

    for (final comet in space.comets) {
      final progress = (turn * 0.06 + comet.offset) % 1.0;
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


typedef _Star = ({double angle, double z, double speed, double size});
typedef _Planet = ({
  double angle,
  double z,
  double speed,
  double radius,
  Color color,
  bool ring,
});
typedef _Comet = ({double x, double y, double dx, double dy, double offset, Color color});
typedef _Nebula = ({double x, double y, double radius, Color color});

/// A randomly generated sky for the portal. Stars and planets carry their own depth and
/// speed and travel toward the viewer, so the picture flows instead of cutting to a new
/// frame. Coordinates are in units of the portal radius.
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
    double angle() => random.nextDouble() * math.pi * 2;

    final stars = <_Star>[
      for (var i = 0; i < 70; i++)
        (
          angle: angle(),
          z: random.nextDouble(),
          speed: 0.25 + random.nextDouble() * 0.85,
          size: 0.4 + random.nextDouble() * 1.2,
        ),
    ];

    final planets = <_Planet>[
      for (var i = 0; i < 3; i++)
        (
          angle: angle(),
          // Staggered so one is always on its way in while another passes by.
          z: i / 3 + random.nextDouble() * 0.12,
          speed: 0.5 + random.nextDouble() * 0.5,
          radius: 0.05 + random.nextDouble() * 0.06,
          color: _palette[random.nextInt(_palette.length)],
          ring: random.nextDouble() < 0.5,
        ),
    ];

    final comets = <_Comet>[
      for (var i = 0; i < 2; i++)
        (
          x: unit() * 0.9,
          y: unit() * 0.9,
          dx: (random.nextDouble() * 1.2 + 0.5) * (random.nextBool() ? 1 : -1),
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
