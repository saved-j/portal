import 'package:flutter/foundation.dart';

/// What the tour is waiting for, fired by the widget that actually does it.
///
/// The tour does not press anything on the owner's behalf and does not guess from state alone:
/// the button says when it was pressed, the switch says when it moved. A tour that closed its
/// page because a value changed in the background would be teaching the owner that the value
/// changes by itself.
enum TutorialEvent {
  modeChanged,
  filtersOpened,
  chipHeld,
  chipDoubleTapped,
  labelTapped,
  started,
  pingAllStarted,
  pingRowHeld,
  filterToggled,
}

/// The one channel between a control and the tour.
final class TutorialBus {
  TutorialBus._();

  static final ValueNotifier<TutorialEvent?> last = ValueNotifier<TutorialEvent?>(null);

  static void fire(TutorialEvent event) => last.value = event;
}

/// A page that opened a full screen says so, and says when that screen is gone.
///
/// The tour hides while the screen is up: a card and a hole over a page the owner must read is
/// in the way of what the same page is teaching. The counter, not a flag: two screens can be
/// pushed in a row and the tour comes back only after the last one.
final tutorialScreenOpened = ValueNotifier<int>(0);
final tutorialScreenClosed = ValueNotifier<int>(0);

void tutorialScreenPushed() => tutorialScreenOpened.value++;

void tutorialScreenPopped() => tutorialScreenClosed.value++;
