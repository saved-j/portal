import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const _minDesktopWidth = 640.0;
const _minTwoColumnWidth = 560.0;
const _minFourColumnWidth = 860.0;
const _minStandardFourColumnWidth = 1040.0;
const _minStandardHeight = 824.0;
const _stackedMaxWidth = 900.0;

/// Columns the dashboard may use: one on a phone in portrait, two as soon as the window is
/// wide enough for a pair of cards, four when it is a desktop-sized window. A landscape phone
/// gets its two columns from the first rule, which is the point — the interface stretches
/// instead of sitting in the middle of the screen.
int dashboardColumnsOf(double width) {
  if (width < _minTwoColumnWidth) return 1;
  return width < _minFourColumnWidth ? 2 : 4;
}

/// The side margin the stacked cards keep.
///
/// They used to be centred in one 560 pt column, which on a landscape phone left a strip of
/// card in the middle of a 900 pt window with empty space on both sides. The margin now
/// stays a margin: the cards use the width they are given, and only an absurdly wide window
/// gets a limit, so a line of text does not run a metre across.
double dashboardMobileSideOf(double width) =>
    math.max(16, (width - _stackedMaxWidth) / 2);

/// [compact] shrinks type, the start button and tiles, and drops subtitles.
enum DashboardDensity {
  standard,
  compact,
  mobile;

  bool get isDesktop => this != mobile;

  bool get isCompact => this == compact;

  /// A landscape phone is a wide screen, not a phone.
  ///
  /// The phone is decided by the shorter side: a device held on its side has plenty of room
  /// for two columns of cards, and refusing it that room left a strip of interface in the
  /// middle of a 900 pt window. [shortest] is the physical shortest side, so a tablet in
  /// portrait still counts as a tablet.
  /// [shortest] is what decides phone-versus-wider: the window's shorter side. It defaults
  /// to the shorter side of the layout itself, but a phone lying on its side must not pass
  /// the test on the strength of its landscape width — the caller passes the device's own
  /// shorter side, which does not change when the phone turns.
  static DashboardDensity of(Size size, {double? shortest}) {
    final short = shortest ?? math.min(size.width, size.height);
    if (short < _minDesktopWidth) {
      return mobile;
    }
    final narrowColumns =
        dashboardColumnsOf(size.width) == 4 &&
        size.width < _minStandardFourColumnWidth;
    return narrowColumns || size.height < _minStandardHeight
        ? compact
        : standard;
  }
}

/// Every fixed height on the dashboard grows by [scale] so its text fits.
class DashboardDensityScope extends InheritedWidget {
  const DashboardDensityScope({
    super.key,
    required this.density,
    required this.scale,
    required super.child,
  });

  final DashboardDensity density;
  final double scale;

  static DashboardDensityScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardDensityScope>();

  static DashboardDensity of(BuildContext context) =>
      _of(context)?.density ?? DashboardDensity.mobile;

  static double scaleOf(BuildContext context) => _of(context)?.scale ?? 1;

  @override
  bool updateShouldNotify(DashboardDensityScope oldWidget) =>
      density != oldWidget.density || scale != oldWidget.scale;
}
