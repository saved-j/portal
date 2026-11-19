import 'config.dart';

/// The picks the portal keeps, in one place: they are read and written from the setup action
/// and from the dashboard, and both must agree on what "the pick for this profile" means.
///
/// A name belongs to the subscription it was delivered in. The two modes keep their own
/// pick, and so does every profile: switching profiles, or switching to a subscription that
/// names its servers differently, must never move the highlight onto a name that is not in
/// the list.
///
/// The pre-per-profile fields ([AppSettingProps.portalSelectionXray] and
/// [AppSettingProps.portalSelectionRules]) are read only while no profile has been picked in
/// the new shape. The first commit writes the new shape and clears them, so an upgrade keeps
/// the node it was running and a new profile starts from the panel's first server instead of
/// borrowing another subscription's pick.

/// Keys are strings because that is what JSON object keys are; a profile id is stable.
String portalProfileKey(int? profileId) => '${profileId ?? 0}';

/// The Xray node the child of [profileId] was last started on, or ''.
String portalXrayPickFor(AppSettingProps settings, int? profileId) {
  final picks = settings.portalXrayPicks;
  final stored = picks[portalProfileKey(profileId)];
  if (stored != null) return stored;
  // Nothing has been picked in the new shape yet: the legacy name is the one this profile
  // was running when the app was updated.
  if (picks.isEmpty) return settings.portalSelectionXray;
  return '';
}

/// [settings] with the child's node written for [profileId], and the legacy name retired.
AppSettingProps withPortalXrayPick(
  AppSettingProps settings,
  int? profileId,
  String name,
) =>
    settings.copyWith(
      portalXrayPicks: {
        ...settings.portalXrayPicks,
        portalProfileKey(profileId): name,
      },
      portalSelectionXray: '',
    );

/// The engine server picked for one filter of [profileId], or ''.
String portalRulePickFor(
  AppSettingProps settings,
  int? profileId,
  String group,
) {
  final byFilter = settings.portalRulesPicks[portalProfileKey(profileId)];
  if (byFilter != null) return byFilter[group] ?? '';
  if (settings.portalRulesPicks.isEmpty) {
    return settings.portalSelectionRules[group] ?? '';
  }
  return '';
}

/// Every filter pick of [profileId], for a list that wants to read them all.
Map<String, String> portalRulePicksFor(AppSettingProps settings, int? profileId) {
  final byFilter = settings.portalRulesPicks[portalProfileKey(profileId)];
  if (byFilter != null) return byFilter;
  if (settings.portalRulesPicks.isEmpty) return settings.portalSelectionRules;
  return const {};
}

/// The filter whose chip the strip had open, for [profileId], or null.
///
/// It is not a pick: no server is chosen by it. It lives here so that the chip the owner
/// last looked at and the servers chosen inside it are read from one place and restored by
/// the same rules — and so that a filtered list never comes back empty because the group it
/// remembered is the other mode's.
String? portalGroupFor(AppSettingProps settings, int? profileId, bool simple) {
  final stored = simple ? settings.portalGroupXray : settings.portalGroupRules;
  if (stored.isEmpty) return null;
  final profile = portalProfileKey(profileId);
  final forThisProfile =
      simple ? settings.portalGroupXrayProfile : settings.portalGroupRulesProfile;
  // A group remembered under another profile is a name from another subscription.
  if (forThisProfile.isEmpty || forThisProfile == profile) return stored;
  return null;
}

/// [settings] with the open chip written for [profileId] and this mode.
AppSettingProps withPortalGroup(
  AppSettingProps settings,
  int? profileId,
  bool simple,
  String? name,
) {
  final profile = portalProfileKey(profileId);
  final value = name ?? '';
  return simple
      ? settings.copyWith(
          portalGroupXray: value,
          portalGroupXrayProfile: profile,
        )
      : settings.copyWith(
          portalGroupRules: value,
          portalGroupRulesProfile: profile,
        );
}

/// [settings] with one filter's pick written for [profileId], and the legacy map retired.
AppSettingProps withPortalRulePick(
  AppSettingProps settings,
  int? profileId,
  String group,
  String proxy,
) {
  final key = portalProfileKey(profileId);
  return settings.copyWith(
    portalRulesPicks: {
      ...settings.portalRulesPicks,
      key: {...?settings.portalRulesPicks[key], group: proxy},
    },
    portalSelectionRules: const {},
  );
}
