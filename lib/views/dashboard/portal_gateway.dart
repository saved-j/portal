import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
    this.closedAtMs,
    this.openedAtMs,
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

  /// Wall-clock moment the portal was switched off. The closing animation is computed
  /// from it, so it survives the widget being rebuilt (or recreated) mid-animation.
  final int? closedAtMs;

  /// Wall-clock moment of the press that opens the portal. The sky starts moving on the
  /// press; the engine catches up afterwards.
  final int? openedAtMs;

  @override
  State<PortalGatewayCore> createState() => _PortalGatewayCoreState();
}

class _PortalGatewayCoreState extends State<PortalGatewayCore>
    with SingleTickerProviderStateMixin {
  // An endless clock, not a cycle: nothing rewinds, so the sky never cuts back to a
  // beginning. Depth is a function of elapsed seconds.
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    // A late field would only be created on first read — that is, in dispose.
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    })..start();
  }

  final _SpaceField _space = _SpaceField.generate(math.Random());



  @override
  void didUpdateWidget(PortalGatewayCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStart && !oldWidget.isStart) {
      // The successful opening has its own tactile confirmation.  It is kept
      // here (at the actual state transition), rather than only on the tap,
      // so a delayed engine start still feels alive.
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final portal = colorScheme.primary;
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
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ],
      );
    } else if (widget.suspended) {
      core = const GlyphIcon(AppGlyphs.wifiOff, size: 34, fill: 1);
    } else {
      core = Text(
        getTimeText(widget.runTime),
        // The timer sits on the dark sky, not on the page: on a light theme the
        // theme's own text colour would be black on black.
        style: AppTextStyle.title3
            .of(context)
            .copyWith(color: Colors.white.withValues(alpha: 0.92)),
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
                turn: t,
                active: widget.isStart || _igniting(),
                intensity: widget.intensity,
                space: _space,
                ignite: _ignite(),
                collapse: _collapse(),
              ),
              child: Center(
                child: IconTheme.merge(
                  // Same reason as the timer: the core sits on the dark sky.
                  data: IconThemeData(color: Colors.white.withValues(alpha: 0.9)),
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



  double _sinceOpenedMs() {
    final openedAt = widget.openedAtMs;
    if (openedAt == null) return double.infinity;
    return (DateTime.now().millisecondsSinceEpoch - openedAt).toDouble();
  }

  bool _igniting() => _sinceOpenedMs() < 900;

  double _ignite() => (_sinceOpenedMs() / 900).clamp(0.0, 1.0);

  /// 0 → 1 over 1.3 s after the switch-off moment. Wall clock, not widget state: the
  /// button subtree can be rebuilt while this runs and the animation must not jump.
  double _collapse() {
    final closedAt = widget.closedAtMs;
    if (closedAt == null) return 1;
    final elapsed = DateTime.now().millisecondsSinceEpoch - closedAt;
    return (elapsed / 1300).clamp(0.0, 1.0);
  }

  /// Breathing on the endless clock: one breath per 2.5 seconds.
  double _pulseWave(double seconds) => math.sin(seconds * 0.8).abs();
}

class _GatewayPainter extends CustomPainter {
  const _GatewayPainter({
    required this.portal,
    required this.turn,
    required this.active,
    required this.intensity,
    required this.space,
    required this.ignite,
    required this.collapse,
  });

  final Color portal;
  final double turn;
  final bool active;
  final double intensity;
  final _SpaceField space;

  /// 0 → 1 over the first 0.9 s of an open portal; 1 means "fully open".
  final double ignite;

  /// 0 → 1 over the 0.7 s after the portal closes; 1 means fully closed.
  final double collapse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    if (!active) {
      // The idle hole is drawn first and always, so the last frame of the closing iris
      // lands on exactly this picture. Earlier the hole was only painted after the
      // animation ended, and the two looked different: a visible pop.
      _paintHole(canvas, center, radius);
      if (collapse >= 1) return;
    }

    // A porthole into space: flat Material shapes, never the same sky twice.
    // While closing, the same sky is drawn inside an iris that shrinks to nothing, so
    // stopping is an animation rather than a picture swap.
    final closing = !active && collapse < 1;
    final skyR = closing ? math.max(1.0, (radius - 1) * (1 - collapse)) : radius - 1;
    final skyRect = Rect.fromCircle(center: center, radius: skyR);
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
        center.dx + nebula.x * skyR * 0.8,
        center.dy + nebula.y * skyR * 0.8,
      );
      final paint = Paint()
        ..shader =
            RadialGradient(
              colors: [
                nebula.color.withValues(alpha: 0.22),
                nebula.color.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: spot, radius: nebula.radius * skyR),
            );
      canvas.drawCircle(spot, nebula.radius * skyR, paint);
    }

    // Everything drifts outward from the centre: depth maps to radius, so the sky
    // flies at the viewer instead of cutting to another frame.  `epoch` gives a
    // traveller a fresh heading on every pass through the porthole.  That makes
    // this an endlessly generated field, not a short movie played in a loop.
    final flow = turn * 0.5;


    // Depth layering: some of the sky passes in front of a planet, some behind it.
    void paintStars(bool front) {
      for (final star in space.stars.where((s) => s.front == front)) {
      final phase = star.z + flow * star.speed;
      final epoch = phase.floorToDouble();
      final z = phase - epoch;
      final angle =
          star.angle + (_noise(star.seed + epoch * 17.31) - 0.5) * 0.9;
      final distance = skyR * 0.98 * z * z;
      final offset = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final edge = math.min(1.0, (1.0 - z) / 0.08);
      final twinkle = 0.55 + 0.45 * math.sin(turn * 4.5 + angle * 9);
      final alpha = ((0.15 + 0.85 * z) * edge * twinkle).clamp(0.0, 1.0);

      // Motion blur: the trail is the distance the star covered in the last instant,
      // so fast near stars streak and slow far ones stay points.
      final beforePhase = star.z + (flow - 0.075) * star.speed;
      final zBefore = beforePhase - beforePhase.floorToDouble();
      if (beforePhase.floorToDouble() == epoch) {
        final trail = skyR * 0.98 * (z * z - zBefore * zBefore);
        if (trail > 0.6) {
          final tail = Offset(
            center.dx + math.cos(angle) * (distance - trail),
            center.dy + math.sin(angle) * (distance - trail),
          );
          // Two feathered strokes make the near, fast stars read as motion
          // blur on a phone display instead of as a single hard line.
          canvas.drawLine(
            tail,
            offset,
            Paint()
              ..strokeWidth = star.size * (1.4 + z * 2.4)
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: alpha * 0.11),
          );
          canvas.drawLine(
            tail,
            offset,
            Paint()
              ..strokeWidth = star.size * (0.3 + z * 1.3)
              ..strokeCap = StrokeCap.round
              ..shader = LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: alpha * 0.75),
                ],
              ).createShader(Rect.fromPoints(tail, offset)),
          );
        }
      }

      canvas.drawCircle(
        offset,
        star.size * (0.35 + z * 1.7),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );

      }
    }

    void paintComets(bool front) {
      for (final comet in space.comets.where((c) => c.front == front)) {
      final cometPhase = turn * 0.14 + comet.offset;
      final cometEpoch = cometPhase.floorToDouble();
      final progress = cometPhase - cometEpoch;
      final heading = (_noise(comet.seed + cometEpoch * 11.17) - 0.5) * 0.55;
      final dx = comet.dx * math.cos(heading) - comet.dy * math.sin(heading);
      final dy = comet.dx * math.sin(heading) + comet.dy * math.cos(heading);
      final head = Offset(
        center.dx + comet.x * radius + dx * radius * progress,
        center.dy + comet.y * radius + dy * radius * progress,
      );
      final tail = Offset(
        head.dx - dx * radius * 0.22,
        head.dy - dy * radius * 0.22,
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
    }

    paintStars(false);
    paintComets(false);

    for (final planet in space.planets) {
      final phase = planet.z + flow * 0.27 * planet.speed;
      final epoch = phase.floorToDouble();
      final z = phase - epoch;
      final angle =
          planet.angle + (_noise(planet.seed + epoch * 5.73) - 0.5) * 1.25;
      final distance = skyR * 0.9 * z * z;
      final planetCenter = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final planetRadius = skyR * planet.radius * (0.35 + z * 2.1);
      // Grow in and out of the frame instead of appearing at full size.
      final fadeIn = (z / 0.12).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - z) / 0.12).clamp(0.0, 1.0);
      final alpha = fadeIn * fadeOut;
      if (alpha <= 0.01) continue;

      if (planet.ring) {
        canvas.save();
        canvas.translate(planetCenter.dx, planetCenter.dy);
        canvas.rotate(-0.42 + angle + turn * planet.speed * 0.23);
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
      // Flat Material disc: colour only, no shading.
      canvas.drawCircle(
        planetCenter,
        planetRadius,
        Paint()..color = planet.color.withValues(alpha: alpha),
      );
    }


    if (ignite < 1) {
      // Opening: a shock ring runs out from the core and the sky brightens, so the
      // moment of connection is visible instead of merely being "on".
      final e = ignite;
      canvas.drawCircle(
        center,
        radius * (0.15 + 0.85 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - e) + 0.6
          ..color = portal.withValues(alpha: 0.75 * (1 - e)),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = portal.withValues(alpha: 0.22 * (1 - e)),
      );
    }

    canvas.restore();

    if (closing) {
      // The iris edge: a bright contracting ring where the sky is being cut off.
      canvas.drawCircle(
        center,
        skyR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - collapse) + 0.8
          ..color = portal.withValues(alpha: 0.55 + 0.35 * (1 - collapse)),
      );
      canvas.drawCircle(
        center,
        skyR + 6 * collapse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = portal.withValues(alpha: 0.25 * (1 - collapse)),
      );
    }

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


  void _paintHole(Canvas canvas, Offset center, double radius) {
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
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = portal.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_GatewayPainter oldDelegate) =>
      oldDelegate.turn != turn ||
      oldDelegate.active != active ||
      oldDelegate.portal != portal ||
      oldDelegate.space != space ||
      oldDelegate.ignite != ignite ||
      oldDelegate.collapse != collapse;
}

typedef _Planet = ({
  double angle,
  double z,
  double speed,
  double radius,
  Color color,
  bool ring,
  double seed,
});
typedef _Star = ({
  double angle,
  double z,
  double speed,
  double size,
  double seed,
  bool front,
});
typedef _Comet = ({
  double x,
  double y,
  double dx,
  double dy,
  double offset,
  Color color,
  double seed,
  bool front,
});
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
      for (var i = 0; i < 112; i++)
        (
          angle: angle(),
          z: random.nextDouble(),
          speed: 0.22 + random.nextDouble() * 1.25,
          size: 0.4 + random.nextDouble() * 1.2,
          seed: random.nextDouble() * 10000,
          front: random.nextDouble() < 0.28,
        ),
    ];

    // One planet, sometimes two — half a cycle apart. Never a parade.
    final planetCount = 1 + (random.nextDouble() < 0.5 ? 1 : 0);
    final planets = <_Planet>[
      for (var i = 0; i < planetCount; i++)
        (
          angle: angle(),
          // Staggered so one is always on its way in while another passes by.
          z: i / planetCount + random.nextDouble() * 0.08,
          speed: 0.5 + random.nextDouble() * 0.5,
          radius: 0.05 + random.nextDouble() * 0.06,
          color: _palette[random.nextInt(_palette.length)],
          ring: random.nextDouble() < 0.5,
          seed: random.nextDouble() * 10000,
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
          seed: random.nextDouble() * 10000,
          front: random.nextBool(),
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

/// Stable, allocation-free noise for the next generated fly-by.
double _noise(double value) {
  final n = math.sin(value * 127.1 + 311.7) * 43758.5453123;
  return n - n.floorToDouble();
}
