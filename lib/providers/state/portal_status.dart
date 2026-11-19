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
    void onChange() {
      final next = source.value;
      state = next;
      // A tunnel that died is not a tunnel. The native record is the one that knows — the
      // engine can stop under a screen that was never told — and this side's clock is what
      // `isStart` reads, so the clock is cleared here. Without it the portal keeps a running
      // timer over a connection that is gone.
      if (next.phase == 'Off' &&
          next.owner == null &&
          ref.read(runTimeProvider) != null) {
        ref.read(runTimeProvider.notifier).value = null;
      }
    }
    source.addListener(onChange);
    ref.onDispose(() => source.removeListener(onChange));
    if (system.isAndroid) return source.value;
    // A desktop has no native coordinator writing that record: the same question is answered
    // from what this side runs. Same rule as on the phone — only the owner's own live answer
    // fills the list — and the same shape, so nothing downstream needs a second code path.
    void follow() => state = _desktopStatus();
    ref.listen(isStartProvider, (_, _) => follow());
    ref.listen(patchClashConfigProvider.select((s) => s.mode), (_, _) => follow());
    return _desktopStatus();
  }

  /// What a desktop is running, in the shape the Android coordinator publishes.
  PortalRuntimeStatus _desktopStatus() {
    if (!ref.read(isStartProvider)) {
      return const PortalRuntimeStatus.unknown();
    }
    final simple =
        ref.read(patchClashConfigProvider.select((s) => s.mode)) == Mode.global;
    return PortalRuntimeStatus(
      generation: 1,
      phase: 'Active',
      owner: simple ? PortalOwner.xray : PortalOwner.mihomo,
      fdEpoch: 0,
      reason: '',
      engine: !simple,
      child: simple,
      childLine: '',
    );
  }
}

final portalStatusProvider =
    NotifierProvider<PortalStatusNotifier, PortalRuntimeStatus>(
        PortalStatusNotifier.new);

