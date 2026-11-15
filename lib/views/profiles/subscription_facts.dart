import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/models/provider_headers.dart';

/// The two facts every subscription shows, in one place.
///
/// The list and the working screen must say the same thing, and a panel that sends no usage
/// must still produce the same shape — a dash, never a missing line.
class SubscriptionFacts {
  const SubscriptionFacts._(this.traffic, this.expiry, this.mark);

  final String traffic;
  final String expiry;
  final String mark;

  static SubscriptionFacts of(Profile profile) {
    final info = profile.subscriptionInfo;
    final used = (info?.upload ?? 0) + (info?.download ?? 0);
    final total = info?.total ?? 0;
    final spendable = info != null && (used > 0 || total > 0);
    // The panel states usage only in its own title for this account; that text stands in
    // when there is no usage header. The total is unknown there, shown as unlimited.
    final stated = profile.headers.trafficText;
    final traffic = spendable
        ? '${used.traffic.show} / ${total > 0 ? total.traffic.show : '♾️'}'
        : stated != null
            ? '$stated / ♾️'
            : '— / —';
    final expire = info?.expireDate;
    final mark = expire == null
        ? '⏳'
        : expire.isAfter(DateTime.now())
            ? '✅'
            : '❌';
    return SubscriptionFacts._(traffic, expire == null ? '—' : _dayMonthYear(expire), mark);
  }

  /// Words for the two facts live in the ARB files, not here: a hardcoded Russian label
  /// spilled into the English and Chinese interface.
}

/// 25.12.2026 — the shape the owner reads at a glance, without a locale library.
String _dayMonthYear(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';
