import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/state.dart';
import 'package:material_ui/material_ui.dart';

extension AppContextExtension on BuildContext {
  void showNotifier(
    String text, {
    MessageLevel level = MessageLevel.info,
    MessageActionState? actionState,
  }) {
    return findAncestorStateOfType<StatusManagerState>()?.message(
      text,
      level: level,
      actionState: actionState,
    );
  }

  AppLocalizations get appLocalizations => AppLocalizations.of(this);
}

/// The name a filter is shown under.
///
/// A label is a filter's identity: the settings store keys on it and the panel's own
/// filters are matched by it, so it is never translated in place. The eleven defaults the
/// app ships are shown in the interface language instead, and a filter the owner renamed is
/// shown exactly as typed.
String localizedFilterLabel(BuildContext context, String label) {
  final appLocalizations = AppLocalizations.of(context);
  return switch (label) {
    'Hong Kong' => appLocalizations.filterHongKong,
    'Taiwan' => appLocalizations.filterTaiwan,
    'Japan' => appLocalizations.filterJapan,
    'Singapore' => appLocalizations.filterSingapore,
    'United States' => appLocalizations.filterUnitedStates,
    'South Korea' => appLocalizations.filterSouthKorea,
    'United Kingdom' => appLocalizations.filterUnitedKingdom,
    'Remaining Traffic' => appLocalizations.filterRemainingTraffic,
    'Expiry Date' => appLocalizations.filterExpiryDate,
    'Traffic Reset' => appLocalizations.filterTrafficReset,
    'Website & Notices' => appLocalizations.filterWebsiteNotices,
    _ => label,
  };
}
