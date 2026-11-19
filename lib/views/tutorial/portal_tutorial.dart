import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/haptics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the first-run tour can point at.
///
/// The keys live here, not in the dashboard: a widget attaches its own key, so the tour can
/// find it wherever the layout put it — one column on a phone, two on a wide window — without
/// the dashboard knowing that a tour exists.
enum TutorialTarget { modeSwitch, modeLabel, filters, chip, start }

final tutorialKeys = {
  TutorialTarget.modeSwitch: GlobalKey(debugLabel: 'tutorial-mode-switch'),
  TutorialTarget.modeLabel: GlobalKey(debugLabel: 'tutorial-mode-label'),
  TutorialTarget.filters: GlobalKey(debugLabel: 'tutorial-filters'),
  TutorialTarget.chip: GlobalKey(debugLabel: 'tutorial-chip'),
  TutorialTarget.start: GlobalKey(debugLabel: 'tutorial-start'),
};

/// One page of the tour.
///
/// The words are not here: a step is a number, and the number is looked up in the app's own
/// translations. A tour written in one language on a phone set to another is a bug the owner
/// has to notice; there is nothing to notice when the strings live where every other string
/// lives.
class TutorialStep {
  const TutorialStep({
    required this.target,
    required this.number,
    this.pictures = const [],
    this.androidOnly = false,
  });

  final TutorialTarget? target;

  /// 1-based, and the name of the translation pair: `tutorialTitle$number`/`tutorialBody$number`.
  final int number;

  /// Screenshots that show this step where words are not enough.
  final List<String> pictures;

  /// A step that exists on the phone only: a desktop has no notification shade.
  final bool androidOnly;

  String title(AppLocalizations l) => switch (number) {
    1 => l.tutorialTitle1,
    2 => l.tutorialTitle2,
    3 => l.tutorialTitle3,
    4 => l.tutorialTitle4,
    5 => l.tutorialTitle5,
    6 => l.tutorialTitle6,
    _ => l.tutorialTitle7,
  };

  String body(AppLocalizations l) => switch (number) {
    1 => l.tutorialBody1,
    2 => l.tutorialBody2,
    3 => l.tutorialBody3,
    4 => l.tutorialBody4,
    5 => l.tutorialBody5,
    6 => l.tutorialBody6,
    _ => l.tutorialBody7,
  };
}

/// The tour, in the order the owner walks it.
///
/// The same on every platform: one list, one set of words, one order. The one step that cannot
/// happen on a desktop — the quick-settings tile — is marked as such instead of being dropped
/// from the list, so the numbering stays honest.
/// The version of the tour below. Bump it with the steps: `AppSettingProps.tutorialVersion`
/// is compared against it when the app starts.
const tutorialVersion = 4;

const tutorialSteps = <TutorialStep>[
  // The switch, not the row: the tour asks for a tap on the control that moves.
  TutorialStep(target: TutorialTarget.modeSwitch, number: 1),
  TutorialStep(target: TutorialTarget.filters, number: 2),
  TutorialStep(target: TutorialTarget.chip, number: 3),
  TutorialStep(target: TutorialTarget.chip, number: 4),
  // The word, not the row: the dashboard opens on the name and nothing else.
  TutorialStep(target: TutorialTarget.modeLabel, number: 5),
  TutorialStep(target: null, number: 6, androidOnly: true),
  TutorialStep(target: TutorialTarget.start, number: 7),
];


/// The tour itself: a dimmed screen, a hole over the thing it is talking about, and a card.
///
/// It is drawn over the dashboard rather than inside it, so the layout underneath is the real
/// one — a hole that does not match the button would be worse than no tour.
class PortalTutorial extends ConsumerStatefulWidget {
  const PortalTutorial({super.key, required this.onDone, this.fromStep = 0});

  final VoidCallback onDone;
  final int fromStep;

  @override
  ConsumerState<PortalTutorial> createState() => _PortalTutorialState();
}

class _PortalTutorialState extends ConsumerState<PortalTutorial> {
  late int _index = widget.fromStep.clamp(0, tutorialSteps.length - 1);

  List<TutorialStep> get _steps => [
    for (final step in tutorialSteps)
      if (!step.androidOnly || system.isAndroid) step,
  ];

  void _next() {
    AppHaptics.tap();
    // The step is written down as it is reached: a tour cut off by a restart resumes here.
    ref.read(appSettingProvider.notifier).update((state) => state.copyWith(
      tutorialStep: _index + 1,
    ));
    if (_index + 1 >= _steps.length) {
      _finish();
      return;
    }
    setState(() => _index += 1);
  }

  void _finish() {
    ref.read(appSettingProvider.notifier).update((state) => state.copyWith(
      tutorialSeen: true,
      tutorialStep: 0,
      tutorialVersion: tutorialVersion,
    ));
    widget.onDone();
  }

  Rect? _targetRect(TutorialTarget? target) {
    if (target == null) return null;
    final box = tutorialKeys[target]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_index];
    final screen = MediaQuery.sizeOf(context);
    final rect = _targetRect(step.target);
    // The card sits under the thing it points at when there is room, and above it otherwise.
    final cardTop = rect == null
        ? screen.height / 2 - 140
        : (rect.bottom + 24 + 220 > screen.height
              ? (rect.top - 24 - 220).clamp(24.0, screen.height - 260)
              : rect.bottom + 24);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // One barrier, one hole: the rest of the screen is dimmed, the target is not.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HolePainter(
                  hole: rect?.inflate(8),
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          Positioned.fill(
            bottom: null,
            child: GestureDetector(
              // Taps outside the card advance the tour: nobody wants to hunt for a button.
              behavior: HitTestBehavior.translucent,
              onTap: _next,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: cardTop,
            child: _TutorialCard(
              step: step,
              index: _index,
              total: _steps.length,
              onNext: _next,
              onSkip: _finish,
            ),
          ),
          if (step.target == null)
            const SizedBox.shrink()
          else
            // The next button is always reachable, even when the target covers the card's spot.
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: TextButton(
                  onPressed: _next,
                  child: Text(
                    context.appLocalizations.tutorialNext,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final TutorialStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.appLocalizations.tutorialStepOf(index + 1, total),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.title(context.appLocalizations),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            step.body(context.appLocalizations),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          if (step.pictures.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: step.pictures.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    step.pictures[index],
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: onSkip,
                child: Text(
                  context.appLocalizations.tutorialSkip,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: onNext,
                child: Text(context.appLocalizations.tutorialNext),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dimmed screen with a rounded hole in it.
class _HolePainter extends CustomPainter {
  const _HolePainter({required this.hole, required this.color});

  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(outer, Paint()..color = color);
      return;
    }
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(18)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF00F5A0),
    );
  }

  @override
  bool shouldRepaint(_HolePainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color;
}

/// Opens the tour over whatever is on screen and remembers where it stopped.
Future<void> showPortalTutorial(BuildContext context, {int fromStep = 0}) async {
  final done = Completer<void>();
  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => PortalTutorial(
        fromStep: fromStep,
        onDone: () {
          if (!done.isCompleted) done.complete();
          navigator.maybePop();
        },
      ),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  await done.future;
}
