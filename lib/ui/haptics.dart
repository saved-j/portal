import 'package:flutter/services.dart';

/// The one place a tap's feedback is decided.
///
/// The portal asks for a response on every press, not only on the few controls that remembered
/// to call the platform themselves: a list where three rows vibrate and the fourth does not
/// reads as a bug. Widgets call this instead of importing the service each time, so the choice
/// of intensity is one decision rather than a habit per file.
class AppHaptics {
  const AppHaptics._();

  /// A press: a switch, a chip, a button, a row that does something.
  static Future<void> tap() async {
    await HapticFeedback.selectionClick();
  }

  /// A deliberate change with a visible consequence — connecting the portal, starting a node.
  static Future<void> commit() async {
    await HapticFeedback.mediumImpact();
  }

  /// Long enough to mean something: holding a row to measure it, holding the bolt to set the
  /// period.
  static Future<void> hold() async {
    await HapticFeedback.heavyImpact();
  }
}
