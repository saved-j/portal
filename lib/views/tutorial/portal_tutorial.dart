import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/dashboard/hero.dart';
import 'package:fl_clash/views/dashboard/portal_controls.dart'
    show portalAvailabilityProvider;

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
    this.opensScreen = false,
    this.needsMode = true,
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

  /// This page opens a screen of its own. The tour steps aside for it instead of drawing a card
  /// the owner cannot act on, and comes back when that screen is closed.
  final bool opensScreen;

  /// This page only makes sense when the engine can run the subscription: the mode switch, the
  /// filter strip and the tile layout are the engine's. A portal-only subscription keeps the
  /// first and the last pages and nothing in between.
  final bool needsMode;

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
const tutorialVersion = 37;

const tutorialSteps = <TutorialStep>[
  // The switch, not the row: the tour asks for a tap on the control that moves, and closes when
  // it has actually moved.
  TutorialStep(
    target: TutorialTarget.modeSwitch,
    number: 1,
    done: TutorialEvent.modeChanged,
  ),
  // Opening a list is a screen, not a card: the tour hides, the real page comes up, and the next
  // page is about what the owner does there.
  TutorialStep(
    target: TutorialTarget.filters,
    number: 2,
    opensScreen: true,
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
    opensScreen: true,
  ),
  // The page asks for the measurement the button performs, and the list it leaves behind is the
  // lesson: numbers appearing where dashes were.
  // Start, then measure: two different controls, two different lessons. They were one page in an
  // earlier pass and the words stopped matching the screen.
  TutorialStep(
    target: TutorialTarget.start,
    number: 6,
    done: TutorialEvent.started,
  ),
  TutorialStep(
    target: TutorialTarget.autoPing,
    number: 7,
    done: TutorialEvent.pingAllStarted,
  ),
  // The whole column — the bolt and every row under it — because the sentence is about the
  // figures that appear in it the moment the portal opens. No wait: they are there at once.

  TutorialStep(
    target: null,
    number: 8,
    androidOnly: true,
    needsMode: false,
  ),
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

  /// How many times the owner has switched the tile look on the page that asks for it.
  int _chipTaps = 0;

  /// The page that asked for a screen has been served: it is not drawn again, not even for the
  /// moment the closing sheet takes to slide away.
  bool _served = false;

  Timer? _waitTimer;

  /// Closes the screen this page opened, so the page that follows is drawn over the page it is
  /// about.
  Timer? _autoClose;
  NavigatorState? _nav;

  /// The pages this subscription can teach.
  ///
  /// A subscription that the engine cannot run has no mode switch to teach, no filter strip, no
  /// tile layout — the whole first part of the tour would point at controls that answer with
  /// "unavailable". What is left is what is true either way: where the portal is started, and how
  /// to put its tile in the shade.
  List<TutorialStep> get _steps {
    final mode = ref.watch(
      portalAvailabilityProvider.select((state) => state.engine.available),
    );
    return [
      for (final step in tutorialSteps)
        if (!step.androidOnly || system.isAndroid)
          if (mode || !step.needsMode) step,
    ];
  }

  /// A frame clock while the tour is up: the hole is measured from a widget that can move
  /// under it — the list scrolls, and a mask that stayed where the row used to be points at
  /// nothing. Sixty rebuilds a second of one CustomPaint is cheaper than a wrong frame.
  Timer? _follow;

  @override
  void initState() {
    super.initState();
    tourScrollLocked.value = true;
    _follow = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) setState(() {});
    });
    TutorialBus.last.addListener(_onAction);
    // A page that opened a screen hides the tour while that screen is up, and brings it back on
    // the way out: a card over a list the owner must read is in the way of the thing it teaches.
    tutorialScreenOpened.addListener(_onScreenChanged);
    tutorialScreenClosed.addListener(_onScreenChanged);
    if (_steps[_index].wait == Duration.zero) {
      _waiting = false;
    } else {
      _waitFor(_steps[_index]);
    }
  }

  /// How many screens the tour's own pages have pushed. While it is above zero the tour is not
  /// drawn: the owner is reading the screen the tour told him to open.
  int _screens = 0;

  /// A page that opened a screen has served its purpose the moment that screen appears: the
  /// owner does not need to be told to press what he has just pressed. The tour moves on while the
  /// screen is up, so the page that follows is about the open screen — and that page's own text
  /// says to close it.
  void _onScreenChanged() {
    if (!mounted) return;
    final screens = (tutorialScreenOpened.value - tutorialScreenClosed.value).clamp(0, 9);
    if (screens > _screens) {
      _screens = screens;
      if (_steps[_index].opensScreen) {
        // The page has done its job the moment its screen appears: it must not come back when
        // that screen closes.
        _served = true;
        // The page asked for a screen, the screen is up, the owner sees it — and then the tour
        // closes it itself. The next page is about the working screen, and a sheet left open
        // would put its card over the sheet instead of over the control it points at.
        _autoClose?.cancel();
        // The next page is chosen while the screen is still up — so page two is never drawn
        // again for the moment the sheet takes to slide away — and the screen is closed after.
        _autoClose = Timer(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          _next();
          _nav?.maybePop();
        });
      }
      setState(() {});
      return;
    }
    setState(() => _screens = screens);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nav = Navigator.maybeOf(context);
  }

  @override
  void dispose() {
    tourSwitchOff.value = false;
    tourScrollLocked.value = false;
    _autoClose?.cancel();
    TutorialBus.last.removeListener(_onAction);
    tutorialScreenOpened.removeListener(_onScreenChanged);
    tutorialScreenClosed.removeListener(_onScreenChanged);
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
    // Switching the mode is followed by the list arriving: the owner has to see that before the
    // next page asks him for anything.
    if (step.number == 1) {
      if (_waiting) return;
      _waiting = true;
      setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        _waiting = false;
        setState(() {});
        _next();
      });
      return;
    }
    if (step.number == 3 && !_confirmed) {
      setState(() => _confirmed = true);
      return;
    }
    // The look of the tiles changes under the finger, so one double tap is not enough to see it:
    // the page stays until ten taps have happened or the owner presses Next himself.
    if (step.number == 4) {
      _chipTaps += 1;
      setState(() => _confirmed = true);
      if (_chipTaps < 10) return;
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
    _served = false;
    _chipTaps = 0;
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
    final full = origin & box.size;
    // A Material switch answers in a 48 dp box and draws a 34×14 track inside it: the frame
    // goes on what the owner can see, not on the invisible margin that takes the touch.
    if (target == TutorialTarget.modeSwitch) {
      return Rect.fromCenter(
        center: full.center,
        width: full.width * 34 / 48,
        height: full.height * 14 / 48,
      );
    }
    return full;
  }

  @override
  Widget build(BuildContext context) {
    // The first page asks for the switch: it is drawn off while that page is up, and the list
    // under it is what the owner's own press fills.
    final forceOff = _index == 0 && _steps[_index].target == TutorialTarget.modeSwitch;
    if (tourSwitchOff.value != forceOff) tourSwitchOff.value = forceOff;
    // While a screen the tour opened is up, the tour is not drawn at all: the owner reads the
    // screen first, and the page that follows is the one that says how to use it.
    if (_screens > 0) return const SizedBox.shrink();
    if (_served && _steps[_index].opensScreen) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final step = _steps[_index];
    final size = MediaQuery.sizeOf(context);
    final screen = size;
    final rect = _targetRect(step.target);
    // The card fills the larger free gap beside the thing it points at, and never leaves the
    // screen: the gap is the card's height limit, and the page scrolls inside it when the text is
    // larger than the gap.
    const margin = 16.0;
    const gap = 24.0;
    // Four gaps around the control, measured, not guessed: below, above, right, left. The card
    // takes the roomiest one that can hold a readable page, so the same tour works on a phone, on
    // a wide window, with the largest text and with a control that sits at the top or the bottom.
    final gaps = <({String side, Rect room})>[
      if (rect == null)
        (side: 'free', room: Rect.fromLTWH(margin, margin, screen.width - 2 * margin, screen.height - 2 * margin))
      else ...[
        (
          side: 'below',
          room: Rect.fromLTRB(
            margin,
            rect.bottom + gap,
            screen.width - margin,
            screen.height - margin,
          ),
        ),
        (
          side: 'above',
          room: Rect.fromLTRB(
            margin,
            margin,
            screen.width - margin,
            rect.top - gap,
          ),
        ),
        (
          side: 'right',
          room: Rect.fromLTRB(
            rect.right + gap,
            margin,
            screen.width - margin,
            screen.height - margin,
          ),
        ),
        (
          side: 'left',
          room: Rect.fromLTRB(
            margin,
            margin,
            rect.left - gap,
            screen.height - margin,
          ),
        ),
      ],
    ];
    // A gap is usable when a page fits in it: two lines of text and the two buttons. The first
    // gap that clears the bar wins — below, then above, then right, then left — because "below"
    // is where a reader looks after the control, and the roomiest gap is not always the one
    // furthest from the eye.
    const minRoom = Size(200, 132);
    // Below the control is where a reader looks next, so it wins whenever a page fits there; the
    // others are only for a control near the bottom edge. A gap on the side of a control that
    // spans the screen is zero wide and never wins.
    ({String side, Rect room}) usable = gaps.first;
    bool fits(Rect r) => r.width >= minRoom.width && r.height >= minRoom.height;
    for (final gapRoom in gaps) {
      if (fits(gapRoom.room)) {
        usable = gapRoom;
        break;
      }
    }
    // ignore: avoid_print
    assert(() {
      if (rect != null) {
        // ignore: avoid_print
        print(
          'TOUR page ${step.number}: gaps '
          '${gaps.map((g) => "${g.side}=${g.room.width.round()}x${g.room.height.round()}").join(" ")} '
          '-> ${usable.side}',
        );
      }
      return true;
    }());
    // Nothing clears the bar — a control wider than the screen with no room above or below:
    // the roomiest gap is used and its page scrolls; the bands still keep the control's own
    // rectangle clear.
    if (!fits(usable.room)) {
      var roomiest = gaps.first;
      for (final gapRoom in gaps) {
        if (gapRoom.room.width * gapRoom.room.height >
            roomiest.room.width * roomiest.room.height) {
          roomiest = gapRoom;
        }
      }
      usable = roomiest;
    }
    final room = usable.room;
    // The card never takes more than its own gap, and never more than two fifths of the screen:
    // the page behind it is the lesson.
    // Never taller than its gap, and never taller than two fifths of the screen: the page behind
    // it is the lesson, and the card's own text scrolls inside whatever height is left.
    final cardSpace = room.height.clamp(0.0, screen.height * 0.42);
    // ignore: avoid_print
    assert(() {
      if (rect != null) print('TGT ${step.number}: ${rect.top.round()}..${rect.bottom.round()} gaps ${gaps.map((g) => "${g.side}:${g.room.top.round()}..${g.room.bottom.round()}").join(" ")}');
      return true;
    }());
    assert(() {
      print(
        'SLOT ${usable.side} room=${room.top.round()}..${room.bottom.round()} '
        'space=${cardSpace.round()}',
      );
      return true;
    }());
    // ignore: avoid_print
    assert(() {
      if (rect != null) {
        print(
          'TOUR ${step.number}: side=${usable.side} '
          'room=${room.left.round()},${room.top.round()} '
          '${room.width.round()}x${room.height.round()} cap=${cardSpace.round()} '
          'screenH=${screen.height.round()}',
        );
      }
      return true;
    }());
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
                  hole: rect?.inflate(6),
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          ..._frameAround(rect, size),
          if (!_waiting)
          IgnorePointer(
            ignoring: false,
            child: _CardSlot(
            left: room.left,
            width: room.width,
            // A slot that starts from the bottom is first limited in height: with only a
            // `bottom` set, a child taller than the room grows up over the control instead of
            // being cut off inside its own gap.
            // Anchored to the edge the room was measured from: an "above" page ends where the
            // gap ends, a "below" page starts where the gap starts, and in both cases the card is
            // exactly `cardSpace` tall — never stretched by a row that has no other child.
            cardSpace: cardSpace,
            upper: usable.side == 'above' || usable.side == 'left',
            // The room's real bottom: the page inside the card scrolls, so a card that has to be
            // shorter than a readable page is the correct trade — it never covers the control.
            roomTop: room.top,
            roomBottom: room.bottom,
            child: _TutorialCard(
              maxHeight: cardSpace,
              step: step,
              index: _index,
              total: _steps.length,
              bodyOverride: step.number == 3 && _confirmed
                  ? context.appLocalizations.tutorialChipOff
                  : null,
              isLast: _index == _steps.length - 1,
              holdsMore: step.number == 4 && _confirmed,
              onNext: _next,
              onSkip: _finish,
            ),
            ),
          ),
          // One way forward: the card's own button. A second Next floating at the bottom made
          // the tour read as two different screens fighting for the same tap.
        ],
      ),
    );
  }
  /// The yellow arrow: beside the target when there is room, above or below otherwise.
}

/// The card, findable by tests: the stand checks that it never overlaps the control it explains.
/// A key, not the painted box: a card's decoration may spill a shadow outside its layout box, and
/// a test that measured the painted edge would report a collision the layout never had.
const tutorialCardKey = Key('tutorial-card-layout');

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
    this.bodyOverride,
    this.maxHeight,
    this.isLast = false,
    this.holdsMore = false,
  });

  final TutorialStep step;
  final String? bodyOverride;
  final double? maxHeight;
  final bool isLast;

  /// A page that asks for a gesture the owner should repeat: the first one shows what happened and
  /// leaves the buttons up, so the second and third can be tried before moving on.
  final bool holdsMore;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A fixed height, not a maximum: the row it sits in gives it `cardSpace`, and a column that
    // only says "at most" lets a long page grow past it, over the control the page explains. The
    // page scrolls inside this box; the buttons sit outside the scroll.
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
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
          // A wrap, not a row: at the largest text scale the two labels do not fit side by side,
          // and the way out used to paint outside the card.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (isLast)
                const SizedBox.shrink()
              else
                TextButton(
                  onPressed: onSkip,
                  child: Text(
                    context.appLocalizations.tutorialSkip,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              // No "Next" on a page that asks for a gesture: the gesture is the way forward, and
              // a button beside it reads as a second, weaker way to skip the lesson.
              if (isLast)
                FilledButton(
                  onPressed: onNext,
                  child: Text(context.appLocalizations.tutorialNext),
                )
              else if (step.number == 4 && holdsMore)
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

/// Places the card against the edge of the free gap, without a `Positioned` that
/// would let the card grow with its content: a row with no other child stretches, and a page of
/// two lines must not be a screen tall.
class _CardSlot extends StatelessWidget {
  const _CardSlot({
    required this.left,
    required this.width,
    required this.upper,
    required this.roomTop,
    required this.roomBottom,
    required this.cardSpace,
    required this.child,
  });

  final double left;
  final double width;
  final bool upper;
  /// Unused: kept for the record of which edge the room was measured from.
  final double roomTop;
  final double roomBottom;
  final double cardSpace;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: upper ? roomBottom - cardSpace : roomTop,
          child: ConstrainedBox(
            key: tutorialCardKey,
            constraints: BoxConstraints(maxHeight: cardSpace, maxWidth: width),
            // The card is as tall as its own words and no taller: the slot is a limit, not a
            // box. A page of two lines is a small card, however large the screen.
            child: child,
          ),
        ),
      ],
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
    _arrow(canvas, size, hole!);
  }






  /// The pointer: a yellow arrow beside the hole, at its own height, so it never lands on the
  /// card and never covers the text it belongs to. Ten-pixel shaft into a thirty-pixel head.
  void _arrow(Canvas canvas, Size size, Rect hole) {
    const yellow = Color(0xFFFFD400);
    const half = 16.0;
    const shaft = 9.0;
    final cy = hole.center.dy;
    final spaceRight = size.width - (hole.right + 18);
    final spaceLeft = hole.left - 18;
    final right = spaceRight >= spaceLeft;
    // Nothing to point with when the control spans the width: the frame alone carries it.
    // The arrow is as long as the dim beside the control allows: a wide control on a narrow
    // screen still gets a short one rather than none.
    final len = ((right ? spaceRight : spaceLeft) - 8).clamp(0.0, 92.0);
    if (len < 24) return;
    final headLen = (len * 0.45).clamp(14.0, 26.0);
    final tipX = right ? hole.right + 18 : hole.left - 18;
    final dirX = right ? -1.0 : 1.0; // the head looks at the hole
    final tailX = tipX - dirX * len;

    final head = Path()
      ..moveTo(tipX, cy)
      ..lineTo(tipX - dirX * headLen, cy - half)
      ..lineTo(tipX - dirX * headLen, cy + half)
      ..close();
    canvas.drawLine(
      Offset(tailX, cy),
      Offset(tipX - dirX * (headLen - 2), cy),
      Paint()
        ..color = yellow
        ..strokeWidth = shaft
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(head, Paint()..color = yellow);
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


