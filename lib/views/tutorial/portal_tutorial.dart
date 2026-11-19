import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/dashboard/hero.dart';

import 'tutorial_bus.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/haptics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the first-run tour can point at.
///
/// The keys live here, not in the dashboard: a widget attaches its own key, so the tour can
/// find it wherever the layout put it — one column on a phone, two on a wide window — without
/// the dashboard knowing that a tour exists.
enum TutorialTarget { modeSwitch, modeLabel, filters, chip, start, autoPing, autoPingColumn }

final tutorialKeys = {
  TutorialTarget.modeSwitch: GlobalKey(debugLabel: 'tutorial-mode-switch'),
  TutorialTarget.modeLabel: GlobalKey(debugLabel: 'tutorial-mode-label'),
  TutorialTarget.filters: GlobalKey(debugLabel: 'tutorial-filters'),
  TutorialTarget.chip: GlobalKey(debugLabel: 'tutorial-chip'),
  TutorialTarget.start: GlobalKey(debugLabel: 'tutorial-start'),
  TutorialTarget.autoPing: GlobalKey(debugLabel: 'tutorial-autoping'),
  TutorialTarget.autoPingColumn: GlobalKey(debugLabel: 'tutorial-autoping-column'),
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
    this.wait = Duration.zero,
    this.done,
  });

  final TutorialTarget? target;

  /// 1-based, and the name of the translation pair: `tutorialTitle$number`/`tutorialBody$number`.
  final int number;

  /// Screenshots that show this step where words are not enough.
  final List<String> pictures;

  /// A step that exists on the phone only: a desktop has no notification shade.
  final bool androidOnly;

  /// How long the screen waits before this page appears: the sentence about the numbers is
  /// about numbers that take a few seconds to arrive.
  final Duration wait;

  /// The action that closes this page. The owner performs it on the real control; the page
  /// then says what happened and moves on.
  final TutorialEvent? done;

  String title(AppLocalizations l) => switch (number) {
    1 => l.tutorialTitle1,
    2 => l.tutorialTitle2,
    3 => l.tutorialTitle3,
    4 => l.tutorialTitle4,
    5 => l.tutorialTitle5,
    6 => l.tutorialTitle6,
    7 => l.tutorialTitle7,
    _ => l.tutorialTitle8,
  };

  String body(AppLocalizations l) => switch (number) {
    1 => l.tutorialBody1,
    2 => l.tutorialBody2,
    3 => l.tutorialBody3,
    4 => l.tutorialBody4,
    5 => l.tutorialBody5,
    6 => l.tutorialBody6,
    7 => l.tutorialBody7,
    _ => l.tutorialBody8,
  };
}

/// The tour, in the order the owner walks it.
///
/// The same on every platform: one list, one set of words, one order. The one step that cannot
/// happen on a desktop — the quick-settings tile — is marked as such instead of being dropped
/// from the list, so the numbering stays honest.
/// The version of the tour below. Bump it with the steps: `AppSettingProps.tutorialVersion`
/// is compared against it when the app starts.
const tutorialVersion = 16;

const tutorialSteps = <TutorialStep>[
  // The switch, not the row: the tour asks for a tap on the control that moves, and closes when
  // it has actually moved.
  TutorialStep(
    target: TutorialTarget.modeSwitch,
    number: 1,
    done: TutorialEvent.modeChanged,
  ),
  TutorialStep(
    target: TutorialTarget.filters,
    number: 2,
    done: TutorialEvent.filtersOpened,
  ),
  TutorialStep(
    target: TutorialTarget.chip,
    number: 3,
    done: TutorialEvent.chipHeld,
  ),
  TutorialStep(
    target: TutorialTarget.chip,
    number: 4,
    done: TutorialEvent.chipDoubleTapped,
  ),
  // The word, not the row: the dashboard opens on the name and nothing else.
  TutorialStep(
    target: TutorialTarget.modeLabel,
    number: 5,
    done: TutorialEvent.labelTapped,
  ),
  TutorialStep(
    target: TutorialTarget.start,
    number: 6,
    done: TutorialEvent.started,
  ),
  // The whole column — the bolt and every row under it — because the sentence is about the
  // figures that appear in it the moment the portal opens. No wait: they are there at once.
  TutorialStep(target: TutorialTarget.autoPingColumn, number: 7),
  TutorialStep(target: null, number: 8, androidOnly: true),
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

  /// The page that asked for a gesture has seen it, and now says what happened.
  bool _confirmed = false;

  /// A page that wants the screen to settle first: the sentence about the numbers is about
  /// numbers the core has not produced yet when the previous page closes.
  bool _waiting = false;

  Timer? _waitTimer;

  List<TutorialStep> get _steps => [
    for (final step in tutorialSteps)
      if (!step.androidOnly || system.isAndroid) step,
  ];

  /// A frame clock while the tour is up: the hole is measured from a widget that can move
  /// under it — the list scrolls, and a mask that stayed where the row used to be points at
  /// nothing. Sixty rebuilds a second of one CustomPaint is cheaper than a wrong frame.
  Timer? _follow;

  @override
  void initState() {
    super.initState();
    _follow = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) setState(() {});
    });
    TutorialBus.last.addListener(_onAction);
    if (_steps[_index].wait == Duration.zero) {
      _waiting = false;
    } else {
      _waitFor(_steps[_index]);
    }
  }

  @override
  void dispose() {
    TutorialBus.last.removeListener(_onAction);
    _follow?.cancel();
    _waitTimer?.cancel();
    super.dispose();
  }

  /// Scrolls the working screen so the delay column is on it, when the list is longer than the
  /// screen. The mask is measured every frame, so it travels with the rows instead of staying
  /// where they were.
  void _revealNumbers(TutorialStep step) {
    if (step.number != 7) return;
    final scroll = heroScroll;
    if (!scroll.hasClients) return;
    final target = (scroll.offset + scroll.position.viewportDimension * 0.35)
        .clamp(0.0, scroll.position.maxScrollExtent);
    if (target <= scroll.offset + 8) return;
    unawaited(
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// The owner has just done the thing this page asks for: the page closes itself.
  void _onAction() {
    if (!mounted || _waiting) return;
    final step = _steps[_index];
    if (step.done == null || step.done != TutorialBus.last.value) return;
    TutorialBus.last.value = null;
    // The tile page shows the result before it closes: the owner should read what his own
    // gesture did, not be moved on with the question of whether it worked.
    if (step.number == 3 && !_confirmed) {
      setState(() => _confirmed = true);
      return;
    }
    _next();
  }

  void _waitFor(TutorialStep step) {
    _waitTimer?.cancel();
    if (step.wait == Duration.zero) {
      setState(() => _waiting = false);
      return;
    }
    setState(() => _waiting = true);
    _waitTimer = Timer(step.wait, () {
      if (!mounted) return;
      setState(() => _waiting = false);
      _revealNumbers(step);
    });
  }

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
    _waitFor(_steps[_index]);
  }

  void _finish() {
    // Whatever the stack looks like, no tour may outlive this call: a route left behind is a
    // barrier that shows nothing and swallows every tap, which is exactly what happened when
    // the working screen mounted twice and pushed two tours.
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    ref.read(appSettingProvider.notifier).update((state) => state.copyWith(
      tutorialSeen: true,
      tutorialStep: 0,
      tutorialVersion: tutorialVersion,
    ));
    widget.onDone();
  }

  /// The four bands that catch a tap outside the hole. Inside the hole nothing is caught, so
  /// the button underneath answers the owner's own finger.
  List<Widget> _frameAround(Rect? hole, Size screen) {
    Widget band(Rect rect) => Positioned.fromRect(
      rect: rect,
      // The bands swallow the tap so it cannot reach a control the page is not about, but they
      // do not advance: a tour that moves on when the owner misses the target teaches nothing.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: const SizedBox.expand(),
      ),
    );
    if (hole == null) {
      return [
        band(Offset.zero & screen),
      ];
    }
    final top = hole.top.clamp(0.0, screen.height);
    final bottom = hole.bottom.clamp(0.0, screen.height);
    final left = hole.left.clamp(0.0, screen.width);
    final right = hole.right.clamp(0.0, screen.width);
    return [
      band(Rect.fromLTWH(0, 0, screen.width, top)),
      band(Rect.fromLTWH(0, bottom, screen.width, screen.height - bottom)),
      band(Rect.fromLTWH(0, top, left, (bottom - top))),
      band(Rect.fromLTWH(right, top, screen.width - right, (bottom - top))),
    ];
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
    final size = MediaQuery.sizeOf(context);
    final screen = size;
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
          // The dim is painted but never touched, and the only things that catch a tap are the
          // four bands around the hole. The hole itself belongs to the real control underneath:
          // the tour asks the owner to press it, so it must be pressable.
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
          ..._frameAround(rect, size),
          if (!_waiting)
          Positioned(
            left: 16,
            right: 16,
            top: cardTop,
            // A phone with the largest text scale must still see the whole page: the card is
            // bounded by the screen and its own text scrolls inside it.
            bottom: null,
            child: _TutorialCard(
              maxHeight: size.height * 0.62,
              step: step,
              index: _index,
              total: _steps.length,
              bodyOverride: step.number == 3 && _confirmed
                  ? context.appLocalizations.tutorialChipOff
                  : null,
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
    this.bodyOverride,
    this.maxHeight,
  });

  final TutorialStep step;
  final String? bodyOverride;
  final double? maxHeight;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? double.infinity,
      ),
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
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
            bodyOverride ?? step.body(context.appLocalizations),
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
                ],
              ),
            ),
          ),
          // The buttons stay outside the scroll: a long page scrolls, the way out never does.
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
/// The tour is a layer of the working screen, not a route.
///
/// A route brings a modal barrier with it, and that barrier — not the tour's own bands — is what
/// a finger hits: the page could ask the owner to press a control and the press would never
/// arrive. This notifier is the whole lifecycle: set it to the first step to open, null to close.
final tutorialRequest = ValueNotifier<int?>(null);

/// True while a tour is on screen. The working screen can be mounted more than once for one
/// session — a page switch, a mode change rebuilds it — and each mount used to push another
/// tour. Two tours mean two barriers, and finishing one leaves the other over the screen where
/// it eats every tap while showing nothing.
bool tourIsShowing = false;

OverlayEntry? _tourEntry;

/// Shows the tour in the window's own overlay.
///
/// The overlay is the only surface whose coordinate space is the window's: the target's rectangle
/// is measured in global coordinates and drawn here, so a frame cannot land beside its control
/// because of a sidebar or a title bar, and the mask covers everything the owner can see.
Future<void> showPortalTutorial(BuildContext context, {int fromStep = 0}) async {
  if (tourIsShowing) return;
  tourIsShowing = true;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => PortalTutorial(
      fromStep: fromStep,
      onDone: () {
        if (_tourEntry != null && _tourEntry!.mounted) _tourEntry!.remove();
        if (identical(_tourEntry, entry)) _tourEntry = null;
        tourIsShowing = false;
      },
    ),
  );
  _tourEntry = entry;
  overlay.insert(entry);
}


