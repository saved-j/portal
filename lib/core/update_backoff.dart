import 'package:fl_clash/l10n/l10n.dart';

/// What happens to a subscription that could not be fetched.
///
/// A download that fails is not the end of the subscription: the file on disk is the last
/// good one, and it keeps the portal running. What the owner needs from the app then is not a
/// warning that repeats on every start — it is a plain statement that the update did not
/// happen, and a next attempt that backs off instead of hammering a server that is already
/// unreachable. One hour, then two, then four, then every four hours: short enough that a
/// network that comes back is noticed the same day, long enough that a dead panel is not asked
/// every minute in the background.
///
/// The backoff is this app's own memory and never replaces the provider's interval: the first
/// attempt after a success follows the subscription, and only failures stretch it.
/// How long to wait after the given number of failures in a row.
///
/// 1 failure → 1 hour, 2 → 2 hours, 3 → 3 hours, 4 and more → 4 hours.
Duration updateBackoffAfter(int failures) {
  if (failures <= 0) return Duration.zero;
  final hours = failures >= 4 ? 4 : failures;
  return Duration(hours: hours);
}

/// A short sentence for the owner: what failed and when the app will try again.
///
/// `at` is the time of the next attempt, already in the reader's clock; the text says it as
/// an hour of the day, which is what a person can check against their own watch.
String updateFailureNote({
  required int failures,
  required DateTime nextAttempt,
  required AppLocalizations l,
  required String reason,
}) {
  final hh = nextAttempt.hour.toString().padLeft(2, '0');
  final mm = nextAttempt.minute.toString().padLeft(2, '0');
  // The sentence lives in the app's own translations like every other one: a Russian phrase in
  // an English app is the same defect whichever line it sits on.
  return failures <= 0 ? reason : l.updateFailedOffline('$hh:$mm');
}
