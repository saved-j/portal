import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/enum/enum.dart' show Mode, GroupName;
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
enum TutorialTarget { modeSwitch, modeLabel, filters, chip, chipStrip, start, autoPing, autoPingColumn }

final tutorialKeys = {
  TutorialTarget.modeSwitch: GlobalKey(debugLabel: 'tutorial-mode-switch'),
  TutorialTarget.modeLabel: GlobalKey(debugLabel: 'tutorial-mode-label'),
  TutorialTarget.filters: GlobalKey(debugLabel: 'tutorial-filters'),
  TutorialTarget.chip: GlobalKey(debugLabel: 'tutorial-chip'),
  TutorialTarget.chipStrip: GlobalKey(debugLabel: 'tutorial-chip-strip'),
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
const tutorialVersion = 53;

const tutorialSteps = <TutorialStep>[
  // The switch, and only the switch. The app opens in the simple portal, so the switch is off by
  // fact, not by paint: the owner's own press is what turns the network on. The card and the mask
  // then step aside so the chips arriving is the thing watched, not the words about it; sweeping
  // them left and right is the same page.
  TutorialStep(
    target: TutorialTarget.modeSwitch,
    number: 1,
    done: TutorialEvent.modeChanged,
  ),
  // A tap brings a filter into the portal; holding it takes it out again: the lesson of
  // tunnelling per service.
  TutorialStep(
    target: TutorialTarget.chip,
    number: 3,
    done: TutorialEvent.chipActivated,
  ),
  // A double tap changes the tile layout.
  TutorialStep(
    target: TutorialTarget.chip,
    number: 4,
    done: TutorialEvent.chipDoubleTapped,
  ),
  // Opening the filter list is a screen, not a card: the tour hides, the real page comes up,
  // and the next page is about what the owner does there.
  TutorialStep(
    target: TutorialTarget.filters,
    number: 2,
    opensScreen: true,
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
  // Adding the portal tile to the quick settings through the pencil on Android.
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

  /// How many times the owner has toggled a filter on the tap/hold page. Three toggles, or
  /// the OK, move the page on.
  int _chipToggles = 0;

  /// How many rows the owner has held to ping on the bolt page. Three held pings, or Next,
  /// are the two ways past the page.
  int _pingHolds = 0;

  /// How many filters the owner has toggled on the list page. One toggle shows the OK that
  /// closes the page.
  int _filterToggles = 0;

  /// The floating hint drawn over the filter list once it opens.
  OverlayEntry? _filterHint;

  /// The card is out of the way for a moment on purpose: the page wants the screen itself to be
  /// watched — the list arriving, a sheet closing — not the words about it.
  bool _cardHidden = false;

  /// The mask is lifted entirely while the chips arrive: the page is about the list appearing,
  /// and a hole over the switch would leave the arriving strip under the dim.
  bool _noMask = false;

  /// The bolt page has moved its focus onto the server list and freed the scroll, so the owner
  /// can sweep the pings before the last page.
  bool _showingPings = false;

  /// The switch page has moved its focus onto the chip strip, asking the owner to sweep the
  /// chips left and right.
  bool _showingChips = false;

  /// How many times the owner has swept the chip strip on the first page. Three or four sweeps,
  /// or the OK button, are the two ways past it.
  int _chipScrolls = 0;

  /// The page that asked for a screen has been served: it is not drawn again, not even for the
  /// moment the closing sheet takes to slide away.
  bool _served = false;

  Timer? _waitTimer;

  /// Closes the sheet this page opened when the owner has done enough inside it.
  NavigatorState? _nav;

  /// The screen this page opened is closed by the owner, not by the tour; the page advances on
  /// the close.

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
    // A screen left open by a previous run must not count against this one: start from the
    // current balance, not from zero, so a stale counter cannot fast-forward an opensScreen page.
    _screens = (tutorialScreenOpened.value - tutorialScreenClosed.value).clamp(0, 9);
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

  /// A page that opened a screen is done the moment the owner closes that screen himself: the
  /// tour steps aside while it is up, and the page advances on the way out — never on a timer,
  /// so a page cannot run past the owner.
  void _onScreenChanged() {
    if (!mounted) return;
    final screens = (tutorialScreenOpened.value - tutorialScreenClosed.value).clamp(0, 9);
    if (screens > _screens) {
      // A screen the tour asked for just opened: hide the tour until the owner closes it.
      _screens = screens;
      if (_steps[_index].opensScreen) {
        _served = true;
        // The filter list is a screen the owner works in, and the page after it points at the
        // first tile: sweep the strip back to its start while the list hides it, and put up the
        // hint that says what to do there.
        if (_steps[_index].number == 2) {
          tourResetTiles.value++;
          _showFilterHint();
        }
        // The server list is the routing rules in full; its symbols are worth a word before the
        // owner starts tapping servers.
        if (_steps[_index].number == 5) {
          _showServerListHint();
        }
      }
      setState(() {});
      return;
    }
    if (screens < _screens) {
      // The owner closed the screen this page opened. The lesson was to see it, so the page is
      // done the moment it closes — the filter list included, whether a filter was toggled or
      // the owner just backed out with the back button.
      _screens = screens;
      _removeFilterHint();
      if (_steps[_index].opensScreen && _served) {
        _next();
        return;
      }
      setState(() {});
      return;
    }
    setState(() => _screens = screens);
  }

  /// Draws the hint over the filter list once it opens. The sheet's route is pushed after this
  /// page learns it opened, so the hint waits a frame and lands on top of the sheet.
  void _showFilterHint() {
    _removeFilterHint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _filterHint != null) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _FilterHint(
          text: context.appLocalizations.tutorialBody2Off,
          ok: _filterToggles >= 1,
          onOk: () {
            _removeFilterHint();
            _nav?.pop();
          },
        ),
      );
      _filterHint = entry;
      overlay.insert(entry);
    });
  }

  /// Draws the routing-rules hint over the server list once the network-mode page opens it. The
  /// symbols are explained here so the first visit to the list already has a key to read it.
  void _showServerListHint() {
    _removeFilterHint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _filterHint != null) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _FilterHint(
          text: context.appLocalizations.tutorialServerListHint,
          ok: false,
          onOk: () {},
        ),
      );
      _filterHint = entry;
      overlay.insert(entry);
    });
  }

  void _removeFilterHint() {
    if (_filterHint != null && _filterHint!.mounted) {
      _filterHint!.remove();
    }
    _filterHint = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nav = Navigator.maybeOf(context);
  }

  @override
  void dispose() {
    tourScrollLocked.value = false;
    _removeFilterHint();
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
    // The switch page, after the switch: a swept chip strip is one more step toward the three
    // or four that move the page on.
    if (step.number == 1 &&
        _showingChips &&
        TutorialBus.last.value == TutorialEvent.chipScrolled) {
      TutorialBus.last.value = null;
      _chipScrolls += 1;
      setState(() {});
      if (_chipScrolls >= 2) {
        _next();
      }
      return;
    }
    // The bolt page, after the bolt: a held row is one more ping toward the three the page
    // asks for. It is a separate gesture from the bolt itself, so it is read here before the
    // page's own `done` gate.
    if (step.number == 7 &&
        _showingPings &&
        TutorialBus.last.value == TutorialEvent.pingRowHeld) {
      TutorialBus.last.value = null;
      _pingHolds += 1;
      setState(() {});
      if (_pingHolds >= 3) {
        _next();
      }
      return;
    }
    // The filter-list page: one filter off is enough for the hint's OK, so the owner can finish
    // by using the list instead of pressing back.
    if (step.number == 2 &&
        _served &&
        TutorialBus.last.value == TutorialEvent.filterToggled) {
      TutorialBus.last.value = null;
      _filterToggles += 1;
      _filterHint?.markNeedsBuild();
      return;
    }
    if (step.done == null || step.done != TutorialBus.last.value) return;
    TutorialBus.last.value = null;
    // The tile page shows the result before it closes: the owner should read what his own
    // gesture did, not be moved on with the question of whether it worked.
    // Switching the mode is followed by the list arriving: the owner has to see that before the
    // next page asks him for anything.
    if (step.number == 1) {
      // The switch has moved. The strip of tiles is sliding in, and the card with the focus
      // frame must not chase it: hide the card and the mask, let the strip arrive (its own
      // slide-down, ~260 ms), and only then come back asking the owner to sweep. The page then
      // advances on three or four sweeps, or the OK button.
      if (!_showingChips) {
        _cardHidden = true;
        _noMask = true;
        _waitTimer?.cancel();
        _waitTimer = Timer(const Duration(milliseconds: 420), () {
          if (!mounted) return;
          setState(() {
            _noMask = false;
            _cardHidden = false;
            _showingChips = true;
            _chipScrolls = 0;
          });
          tourScrollLocked.value = false;
        });
        setState(() {});
      }
      return;
    }
    if (step.number == 3) {
      _chipToggles += 1;
      setState(() => _confirmed = true);
      if (_chipToggles < 3) return;
    }
    // The bolt leaves numbers behind. The point of this page is to see the figures on the
    // servers, not the bolt: the focus moves onto the list, the mask lifts, the scroll is freed
    // so the owner can sweep up and down, and only then does the last page come up.
    if (step.number == 7) {
      if (!_showingPings) {
        _showingPings = true;
        _pingHolds = 0;
        // Unlock the scroll so the owner can look around while the pings arrive.
        tourScrollLocked.value = false;
        setState(() {});
      }
      // The page waits for three held pings or the owner's "Next" — no auto-advance.
      return;
    }
    // The look of the tiles changes under the finger, so one double tap is not enough to see it:
    // the page stays until four changes have happened or the owner presses Next himself.
    if (step.number == 4) {
      _chipTaps += 1;
      setState(() => _confirmed = true);
      if (_chipTaps < 4) return;
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
    _confirmed = false;
    _chipTaps = 0;
    _chipToggles = 0;
    _pingHolds = 0;
    _filterToggles = 0;
    _removeFilterHint();
    _chipScrolls = 0;
    _showingPings = false;
    _showingChips = false;
    tourScrollLocked.value = true;
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
    _removeFilterHint();
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
    // After the switch is pressed the page is about the tile strip, not the switch: the hole
    // widens onto the whole row of tiles while the owner sweeps them left and right.
    if (_showingChips && target == TutorialTarget.modeSwitch) {
      target = TutorialTarget.chipStrip;
    }
    // The hold and the double-tap on a tile have the same problem as the server column: one
    // tile can be scrolled off screen by the sweep on page one. Frame the whole strip, the way
    // the bolt page frames the whole column.
    if (target == TutorialTarget.chip) {
      target = TutorialTarget.chipStrip;
    }
    // After the bolt is pressed the page is about the pings on the servers, not the bolt: the
    // hole moves onto the whole server column while the owner sweeps it.
    final effective = (_showingPings && target == TutorialTarget.autoPing)
        ? TutorialTarget.autoPingColumn
        : target;
    final box = tutorialKeys[effective]?.currentContext?.findRenderObject();
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
    // While a screen the tour opened is up, the tour is not drawn at all: the owner reads the
    // screen first, and the page that follows is the one that says how to use it.
    if (_screens > 0) return const SizedBox.shrink();
    if (_served && _steps[_index].opensScreen) return const SizedBox.shrink();
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
    // A window can be far wider than a readable card. The card is capped so a page never turns
    // into a banner spanning the screen, while the gap's own width still decides where it sits.
    const maxCardWidth = 480.0;
    final cardWidth = room.width.clamp(0.0, maxCardWidth);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The dim is painted but never touched, and the only things that catch a tap are the
          // four bands around the hole. The hole itself belongs to the real control underneath:
          // the tour asks the owner to press it, so it must be pressable.
          // While the mask is lifted the whole screen is left bare: the owner watches the chips
          // arrive, and nothing dims or swallows a tap over them.
          if (!_noMask) ...[
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
          ],
          if (!_waiting && !_cardHidden)
          IgnorePointer(
            ignoring: false,
            child: _CardSlot(
            left: room.left,
            width: cardWidth,
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
                  : step.number == 1 && _showingChips
                      ? context.appLocalizations.tutorialBody1Chips
                      : null,
              isLast: _index == _steps.length - 1,
              holdsMore:
                  (step.number == 1 && _showingChips) ||
                      (step.number == 4 && _confirmed) ||
                      (step.number == 7 && _showingPings),
              onNext: _next,
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
    this.bodyOverride,
    this.maxHeight,
    this.isLast = false,
    this.holdsMore = false,
  });

  final TutorialStep step;
  final String? bodyOverride;
  final double? maxHeight;
  final bool isLast;
  final bool holdsMore;
  final int index;
  final int total;
  final VoidCallback onNext;

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
          // The gesture is the way forward on every page; no Skip. The last page, and the two
          // gesture pages that let the owner stop early, carry a plain OK.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (isLast || holdsMore)
                FilledButton(
                  onPressed: onNext,
                  child: Text(context.appLocalizations.tutorialOk),
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
    // An "above"/"left" card hugs the bottom edge of its gap — right against the control it
    // explains — and grows up only as tall as its own words. Anchoring with `bottom` instead of
    // `top = roomBottom - cardSpace` fixes a short card being pinned to the far end of the gap
    // with half a screen of air between it and the control.
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: upper ? null : roomTop,
          bottom: upper ? screenHeight - roomBottom : null,
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

/// The floating hint drawn over the filter list: it says what to do there, and its OK appears
/// once a filter is off. It lives in its own overlay entry so it can sit on top of the sheet the
/// page opened, without a barrier that would keep the sheet's own controls from the owner.
class _FilterHint extends StatelessWidget {
  const _FilterHint({required this.text, required this.ok, required this.onOk});

  final String text;
  final bool ok;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: SizedBox.expand()),
          SafeArea(
            child: Align(
              // The hint hangs in the lower quarter, not flush with the bottom: the list runs
              // under it and the OK window must not cover the bottom rows the owner is reading.
              alignment: const Alignment(0, 0.72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                        ),
                        if (ok) ...[
                          const SizedBox(height: 10),
                          // Centred, not pushed to an edge: one small window that holds its
                          // message and its OK, no wider than its own words.
                          FilledButton(
                            onPressed: onOk,
                            child: Text(context.appLocalizations.tutorialOk),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
  tourSimulatesSimple.value = true;
  // The tour teaches the network mode from the simple portal, so the switch must sit on the
  // simple mode before the tour opens — whatever launched the tour (the first run or the
  // settings item). Forced here, in the one shared entry point, and the `tourSimulatesSimple`
  // flag keeps a `noglobal` panel from pushing the rule mode back over it mid-tour.
  if (fromStep == 0) {
    final container = ProviderScope.containerOf(context, listen: false);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    container
        .read(proxiesActionProvider.notifier)
        .updateCurrentGroupName(GroupName.GLOBAL.name);
  }
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => PortalTutorial(
      fromStep: fromStep,
      onDone: () {
        if (_tourEntry != null && _tourEntry!.mounted) _tourEntry!.remove();
        if (identical(_tourEntry, entry)) _tourEntry = null;
        tourIsShowing = false;
        tourSimulatesSimple.value = false;
      },
    ),
  );
  _tourEntry = entry;
  overlay.insert(entry);
}


