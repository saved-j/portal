part of '../state.dart';

/// Both corner badges stay hidden until a double tap asks for them: a permanent
/// counter is noise on a screen that is about the portal, not about the numbers.
class PortalBadgeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final portalProfilesBadgeProvider =
    NotifierProvider<PortalBadgeNotifier, bool>(PortalBadgeNotifier.new);
final portalConnectionsBadgeProvider =
    NotifierProvider<PortalBadgeNotifier, bool>(PortalBadgeNotifier.new);



