part of '../state.dart';

/// The portal's own record, as a provider: which core holds the tunnel, right now.
///
/// The list has to know that before it shows a core's rows: a group stays in memory after its
/// core stopped, and a list that draws it anyway is showing the previous owner's servers under
/// the current mode's heading. Only `Active` with the matching owner is a live answer.
class PortalStatusNotifier extends Notifier<PortalRuntimeStatus> {
  @override
  PortalRuntimeStatus build() {
    final source = portalRuntime.status;
    void onChange() => state = source.value;
    source.addListener(onChange);
    ref.onDispose(() => source.removeListener(onChange));
    return source.value;
  }
}

final portalStatusProvider =
    NotifierProvider<PortalStatusNotifier, PortalRuntimeStatus>(
        PortalStatusNotifier.new);

