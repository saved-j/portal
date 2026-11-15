import 'package:fl_clash/core/portal_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule the two modes live by: three failures in a row take a mode off, and only that
/// mode's own success brings it back.
void main() {
  // The ledger writes its line through the portal channel; a unit test has no plugin behind
  // it, so the binding has to exist for the call to come back as a missing handler (which the
  // runtime catches) instead of "binding not initialized".
  TestWidgetsFlutterBinding.ensureInitialized();
  late PortalFeeds feeds;

  setUp(() {
    // The ledger is a process-wide singleton on purpose, so each case starts from the state
    // it has before anything was fetched: no failures, nothing refused.
    feeds = portalFeeds..note(PortalFeed.engine, ok: true)..note(PortalFeed.xray, ok: true);
  });

  test('a feed is offered until three failures in a row', () {
    expect(feeds.denialOf(PortalFeed.engine), isNull);
    feeds
      ..note(PortalFeed.engine, ok: false, reason: 'http 502')
      ..note(PortalFeed.engine, ok: false, reason: 'http 502');
    expect(feeds.strikesOf(PortalFeed.engine).failures, 2);
    expect(feeds.denialOf(PortalFeed.engine), isNull);

    feeds.note(PortalFeed.engine, ok: false, reason: 'http 502');
    expect(feeds.strikesOf(PortalFeed.engine).failures, portalFeedStrikeLimit);
    expect(feeds.denialOf(PortalFeed.engine), contains('http 502'));
  });

  test('one feed failing leaves the other one alone', () {
    for (var i = 0; i < portalFeedStrikeLimit; i++) {
      feeds
        ..note(PortalFeed.engine, ok: false, reason: 'http 502')
        ..note(PortalFeed.xray, ok: true);
    }
    expect(feeds.strikesOf(PortalFeed.engine).blocked, isTrue);
    expect(feeds.strikesOf(PortalFeed.xray).blocked, isFalse);
    expect(feeds.denialOf(PortalFeed.xray), isNull);
  });

  test('a successful fetch of its own feed resets the count, without a restart', () {
    for (var i = 0; i < portalFeedStrikeLimit; i++) {
      feeds.note(PortalFeed.engine, ok: false, reason: 'http 502');
    }
    expect(feeds.denialOf(PortalFeed.engine), isNotNull);

    feeds.note(PortalFeed.engine, ok: true);
    expect(feeds.strikesOf(PortalFeed.engine).failures, 0);
    expect(feeds.denialOf(PortalFeed.engine), isNull);
  });

  test('the two counters do not reset each other', () {
    feeds
      ..note(PortalFeed.engine, ok: false, reason: 'http 502')
      ..note(PortalFeed.engine, ok: false, reason: 'http 502')
      ..note(PortalFeed.xray, ok: true);
    // The Xray success above is a fact about the node list only: the engine is still on its
    // second strike, which is what makes the two counts independent.
    expect(feeds.strikesOf(PortalFeed.engine).failures, 2);
  });
}
