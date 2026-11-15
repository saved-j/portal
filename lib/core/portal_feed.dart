/// The two documents a subscription must serve, and the two modes that need them.
///
/// A panel answers one link with two different bodies, and it decides per request which of
/// them to serve: the engine's own config (Clash YAML, proxies + rules) and the node list the
/// second core runs. Either can fail on its own — a panel that answers the engine format with
/// `502` may still serve the node list — so the two are counted apart, and one mode going
/// dark never touches the other.
///
/// The count is the app's own observation, not the file's state: a failed fetch deliberately
/// leaves the last good file on disk, because a working subscription must never be replaced
/// by an error page. A file that exists therefore proves nothing about whether the panel
/// still serves it. Three failures in a row are what turn a mode off, and the next success of
/// that same feed turns it back on — no restart, no cache to clear.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../enum/enum.dart';
import '../common/print.dart';
import '../plugins/portal_runtime.dart';

/// One document the app has to fetch.
enum PortalFeed {
  /// The engine's own format: `proxies:`, `proxy-groups:` and `rules:`. Without it the
  /// network mode has nothing to route.
  engine,

  /// The node list for the second core: share links or a ready client config. Without it the
  /// simple portal has nothing to run.
  xray;

  /// The name the log and the transitions file carry.
  String get label => switch (this) {
        PortalFeed.engine => 'engine',
        PortalFeed.xray => 'xray',
      };

  /// The mode this feed makes usable, as the app names its modes.
  String get mode => switch (this) {
        PortalFeed.engine => 'rule',
        PortalFeed.xray => 'global',
      };
}

/// A feed is refused after this many failures in a row.
///
/// Three, not one: a panel behind a flapping CDN answers `502` once and serves the next
/// request, and a mode that dies on the first hiccup is worse than one that waits. Three is
/// also the point where the owner has watched it fail repeatedly, so the control has to
/// start telling the truth instead of offering a switch that cannot work.
const portalFeedStrikeLimit = 3;

/// What one feed's own counter says.
@immutable
class FeedStrikes {
  const FeedStrikes({this.failures = 0, this.reason = '', this.at});

  /// Failures in a row, since this feed's last success.
  final int failures;

  /// The last failure's own words, for the control that has to explain itself.
  final String reason;

  /// When the last attempt that moved the count happened.
  final DateTime? at;

  /// True once the mode this feed enables must not be offered.
  bool get blocked => failures >= portalFeedStrikeLimit;

  /// The counter of a feed that answered: no failures, nothing to explain.
  static const FeedStrikes clear = FeedStrikes();

  FeedStrikes fail(String why) => FeedStrikes(
        failures: failures + 1,
        reason: why,
        at: DateTime.now(),
      );
}

/// The app's own record of both feeds, one counter each.
///
/// Process-wide and in memory on purpose: these are attempts made by *this* run of the app,
/// so a restart starts the count again and the portal may try once more. Nothing here is
/// written to disk — the profile files are the last good download, and they are deliberately
/// kept when a fetch fails.
class PortalFeeds extends ChangeNotifier {
  PortalFeeds._();

  static final PortalFeeds instance = PortalFeeds._();

  final Map<PortalFeed, FeedStrikes> _strikes = {};

  FeedStrikes strikesOf(PortalFeed feed) => _strikes[feed] ?? const FeedStrikes();

  /// Both counters, for a widget that has to draw them.
  Map<PortalFeed, FeedStrikes> get snapshot => {
        for (final feed in PortalFeed.values) feed: strikesOf(feed),
      };

  /// One attempt at one feed.
  ///
  /// [ok] is that attempt's whole answer: a body that arrived, parsed, carried what the mode
  /// needs and matched its format. A success clears this feed's counter and leaves the other
  /// feed exactly as it was — the two are independent, which is the point of counting them
  /// here instead of deriving one from the other.
  void note(PortalFeed feed, {required bool ok, String reason = ''}) {
    final before = strikesOf(feed);
    final next = ok
        ? FeedStrikes.clear
        : before.fail(
            reason.isEmpty ? 'the fetch did not answer' : reason,
          );
    // The counter moves only when the answer did. A success that follows a success changes
    // nothing on screen, but it is still written: the log is the record of every attempt, and
    // a line per attempt is what lets a device check quote the count instead of guessing it.
    final moved = next.failures != before.failures || next.reason != before.reason;
    if (moved) {
      _strikes[feed] = next;
      notifyListeners();
    }
    _record(feed, next, reset: ok && before.failures > 0);
  }

  /// The mode's refusal as a sentence, or null while the feed still answers.
  ///
  /// Callers put this inside a localized sentence; the words here name the fact, not the
  /// language.
  String? denialOf(PortalFeed feed) {
    final strikes = strikesOf(feed);
    if (!strikes.blocked) return null;
    return '${feed.label}: ${strikes.failures} failed attempts in a row'
        '${strikes.reason.isEmpty ? '' : ' (${strikes.reason})'}';
  }

  void _record(PortalFeed feed, FeedStrikes strikes, {required bool reset}) {
    final state = strikes.blocked ? 'unavailable' : 'ok';
    commonPrint.log(
      'availability: feed=${feed.label} mode=${feed.mode} '
      'attempts=${strikes.failures}/$portalFeedStrikeLimit state=$state'
      '${reset ? ' outcome=reset' : ''}'
      '${strikes.reason.isEmpty ? '' : ' reason=${strikes.reason}'}',
      logLevel: strikes.blocked ? LogLevel.warning : LogLevel.info,
    );
    // The same line in the file adb can read: a count that only exists on screen is a count
    // nobody can quote from a device.
    unawaited(
      portalRuntime.noteAvailability(
        feed: feed.label,
        mode: feed.mode,
        attempts: strikes.failures,
        limit: portalFeedStrikeLimit,
        state: state,
        reason: strikes.reason,
      ),
    );
  }
}

/// The one ledger both the fetch path and the controls read.
final portalFeeds = PortalFeeds.instance;
