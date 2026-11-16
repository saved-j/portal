part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart, failed }

typedef _SetupInputs = (
  SetupState,
  PatchClashConfig,
  NetworkProps,
  SetupParams,
);

typedef BuiltProfile = ({
  String yaml,
  String md5,
  ConfigCounts counts,
  SetupBase? base,
});

/// One node's document, ready to be the whole transaction's payload.
class _PortalChildDocument {
  const _PortalChildDocument({
    required this.profileId,
    required this.name,
    required this.config,
  });

  final int? profileId;
  final String name;
  final String config;
}

class _RunRequest {
  final bool running;
  final bool initialize;

  /// Adopts a run the Android service has, config and groups alike.
  final bool resume;
  final DateTime? previousStartTime;
  final bool undoesFailedStart;

  const _RunRequest({
    required this.running,
    required this.initialize,
    required this.resume,
    required this.previousStartTime,
    this.undoesFailedStart = false,
  });
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  Timer? _runtimeTimer;
  final _setupScheduler = SerialTaskScheduler();
  final _listenerScheduler = SerialTaskScheduler();
  _RunRequest? _latestRunRequest;
  DateTime? _startTime;
  _SetupInputs? _appliedInputs;
  var _lastPushDuration = Duration.zero;
  var _pendingForceApply = false;
  var _pushes = 0;
  var _tunMissed = false;
  var _configRequests = 0;

  /// The last config push's own failure, empty when the last one was taken.
  ///
  /// A switch used to report "not applied in 12 s" because the reason the Core gave was
  /// never kept anywhere: the push's exception went into a log line and the waiter only
  /// knew that its condition had not become true.
  String _lastConfigError = '';

  /// What the engine last said about the config it was handed.
  String get lastConfigError => _lastConfigError;

  /// Why the simple portal last failed to start, empty when it did not fail.
  ///
  /// The start already showed its reason; a transaction that asked for the start and got
  /// `false` must not replace that reason with a generic sentence of its own.
  String _lastPortalFailure = '';

  String get lastPortalFailure => _lastPortalFailure;
  var _setupAfterInit = false;
  Completer<void>? _initialized;
  /// True while the simple portal's child is being started, so two paths cannot both
  /// start it — the cold start and a user who opened the portal at the same moment.
  var _startingChild = false;

  /// Moves as each config push starts and again once the Core answers it.
  int get pushes => _pushes;

  /// A start, stop or restart of the listeners has not finished yet.
  bool get isChangingRun => _listenerScheduler.isBusy;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  @override
  void build() {
    if (system.isAndroid) {
      // The native coordinator's reverse direction: an entry that arrives with no document
      // (Quick Settings, Always-on) asks this side for the one the profile names, and the
      // builder has to be in place before any such entry can arrive.
      portalRuntime.attach();
      portalRuntime.childConfigBuilder = () async => (await _portalChildDocument())?.config;
    }
    ref.onDispose(_stopRuntimeTicker);
    ref.listen(appVisibleProvider, (_, _) => _syncRuntimeTicker());
    ref.listen(
      appSettingProvider.select((state) => state.showTrayTitle),
      (_, _) => _syncRuntimeTicker(),
    );
    ref.listen(initProvider, (_, initialized) {
      if (initialized) {
        _initialized?.complete();
        _initialized = null;
      }
      if (initialized && _setupAfterInit) {
        _setupAfterInit = false;
        unawaited(fullSetup());
      }
    });
  }

  bool get _isTrafficShown =>
      ref.read(appVisibleProvider) ||
      (system.isMacOS &&
          !ref.read(safeModeProvider) &&
          ref.read(appSettingProvider).showTrayTitle);

  SetupParams get _setupParams {
    final selectedMap = ref.read(selectedMapProvider);
    final appSetting = ref.read(appSettingProvider);
    return SetupParams(
      selectedMap: selectedMap,
      testUrl: appSetting.testUrl,
      skipCertVerify: !appSetting.checkCertificate,
    );
  }

  // The selection reaches the Core through changeProxy, not through an apply.
  SetupParams get _appliedParams =>
      _setupParams.copyWith(selectedMap: const {});

  Future<bool> fullSetup() async {
    // Startup may already be applying the profile this replaces.
    if (!ref.read(initProvider)) {
      _setupAfterInit = true;
      return true;
    }
    ref.read(proxiesActionProvider.notifier).cancelDelayTests();
    ref.read(delayDataSourceProvider.notifier).value = {};
    final setupResult = applyProfile(force: true);
    ref.read(logsProvider.notifier).value = FixedList(maxLogsLength);
    ref.read(requestsProvider.notifier).value = FixedList(maxRequestsLength);
    ref.read(dnsQueriesProvider.notifier).value = FixedList(
      maxDnsQueriesLength,
    );
    ref.read(dnsQueryCountProvider.notifier).value = 0;
    ref.read(requestCountProvider.notifier).value = 0;
    try {
      return await setupResult;
    } catch (e, s) {
      commonPrint.log('fullSetup ===> ${compactError(e)}, $s');
      return false;
    }
  }

  void _setLocalRunning(bool running) {
    _stopRuntimeTicker();
    if (!running) {
      _startTime = null;
      debouncer.cancel(FunctionTag.applyProfile);
      _pendingForceApply = false;
      _updateRunTime();
      return;
    }

    _startTime ??= DateTime.now();
    _updateRunTime();
    _syncRuntimeTicker();
  }

  void _syncRuntimeTicker() {
    if (_startTime == null || !_isTrafficShown) {
      _stopRuntimeTicker();
      return;
    }
    if (_runtimeTimer != null) {
      return;
    }
    _refreshRunningState();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRunningState(),
    );
  }

  void _stopRuntimeTicker() {
    _runtimeTimer?.cancel();
    _runtimeTimer = null;
  }

  void _refreshRunningState() {
    _updateRunTime();
    unawaited(ref.read(commonActionProvider.notifier).updateTraffic());
  }

  void _updateRunTime() {
    final startTime = _startTime;
    ref.read(runTimeProvider.notifier).value = startTime == null
        ? null
        : DateTime.now().millisecondsSinceEpoch -
              startTime.millisecondsSinceEpoch;
  }

  @protected
  Future<DateTime?> serviceStartTime() async => service?.getRunTime();

  Future<void> initStatus() async {
    if (!globalState.needInitStatus) {
      return;
    }
    final intent = _latestRunRequest;
    final startTime = await serviceStartTime();
    final appliedMd5 = startTime != null && startTime.isBeforeNow
        ? await preferences.getAppliedConfigMd5()
        : null;
    if (!identical(_latestRunRequest, intent)) {
      await globalState.safeRun(() => applyProfile(force: true));
      return;
    }
    _startTime = startTime;
    if (_isRunning) {
      globalState.lastConfigMd5 = appliedMd5;
      await _run(true, initialize: true, resume: true);
    } else if (ref.read(appSettingProvider).autoRun) {
      await setRunning(true, initialize: true);
    } else {
      await globalState.safeRun(() => applyProfile(force: true));
    }
  }

  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    if (running && !initialize && !ref.read(initProvider)) {
      // A start from Quick Settings, automation or Always-on can arrive while
      // startup is still deciding the run; it waits for that, and yields to
      // whatever command startup or the user gave since.
      final before = _latestRunRequest;
      await (_initialized ??= Completer<void>()).future;
      if (!identical(_latestRunRequest, before)) {
        return true;
      }
    }
    return _run(running, initialize: running && initialize);
  }

  Future<bool> _run(
    bool running, {
    required bool initialize,
    bool resume = false,
    bool undoesFailedStart = false,
  }) {
    if (running) {
      // The last line of defence, for the entries that start the portal without asking which
      // mode to enter: Quick Settings, Always-on, a restore. A mode whose document stopped
      // answering three fetches ago must not open a tunnel nothing can carry.
      final denial = _feedDenial(
        ref.read(patchClashConfigProvider.select((state) => state.mode)),
      );
      if (denial != null) {
        _lastPortalFailure = denial;
        commonPrint.log(
          'portal not opened: $denial',
          logLevel: LogLevel.warning,
        );
        _setLocalRunning(false);
        return Future.value(false);
      }
    }
    final request = _RunRequest(
      running: running,
      initialize: initialize,
      resume: resume,
      previousStartTime: _startTime,
      undoesFailedStart: undoesFailedStart,
    );
    _latestRunRequest = request;
    _setLocalRunning(running);
    if (request.initialize) {
      globalState.needInitStatus = false;
    }
    return running ? _start(request) : _stop(request);
  }

  /// Whether the saved mode is the simple portal, where the tunnel is the child's.
  ///
  /// Android only: in this fork `Mode.global` names the portal on the phone, while on the
  /// desktop it is the engine's own global mode and keeps the engine exactly as it was.
  bool get _isSimplePortal =>
      system.isAndroid &&
      ref.read(patchClashConfigProvider.select((state) => state.mode)) ==
          Mode.global;

  Future<bool> _start(_RunRequest request) async {
    if (_isSimplePortal) {
      return _startSimplePortal(request);
    }
    if (request.initialize) {
      var applied = false;
      try {
        applied = await applyProfile(
          force: !request.resume,
          preloadInvoke: () => _startCoreRunning(request),
        );
      } catch (_) {
        applied = false;
      }
      if (!applied && _isCurrent(request)) {
        await globalState.safeRun(
          () => _run(false, initialize: false, undoesFailedStart: true),
        );
      }
      return applied;
    }

    try {
      await _startCoreRunning(request);
    } catch (_) {
      _rollbackRunning(request);
      rethrow;
    }
    _reconcileTun();
    final applied = await inputsApplied();
    if (_isCurrent(request) && !applied) {
      // The start of a switch is the switch's own ask for the profile. Pushed now, not through
      // the edit debouncer: the coalescing that keeps an editor from pushing ten times would
      // hold the engine's first config back for two to ten seconds, which is exactly the time
      // the owner spends looking at a list the new owner has not filled yet.
      applyProfileNow();
    }
    return true;
  }

  /// One cold start of the simple portal: the tunnel first, then the child that reads it.
  ///
  /// Nothing of the engine takes part — no config is built for it, none is pushed, its
  /// listeners are not opened, and GLOBAL keeps whatever the engine last held. If the child
  /// does not take the tunnel it is taken back down and the reason is shown: a tunnel nothing
  /// reads sends every packet into a black hole, and a portal reported as running over it is
  /// worse than one reported as broken.
  Future<bool> _startSimplePortal(_RunRequest request) async {
    if (_startingChild) {
      return true;
    }
    _startingChild = true;
    try {
      _lastPortalFailure = '';
      // The service reads its options from the shared state, so the mode that just changed
      // has to reach it before the tunnel is asked for.
      await _syncPortalOptions();
      // Prepared before anything is torn down: a profile with no node, or no engine format,
      // leaves whatever is running exactly as it was.
      final document = await _portalChildDocument();
      if (document == null) {
        _rollbackRunning(request);
        return false;
      }
      // One transaction: the previous owner lets go, the service establishes the tunnel, the
      // child acknowledges it, and only then is `Active` published. A refusal closes the
      // service again on the native side — a tunnel nothing reads is worse than no tunnel.
      final answer = await portalRuntime.open(
        PortalOwner.xray,
        config: document.config,
      );
      if (answer.ok) {
        _commitPortalPick(document);
        // What the run is made of, for the screens that show it: the same value the engine
        // path publishes once its listener answered.
        ref.read(runningVpnOptionsProvider.notifier).value =
            await ref.read(vpnOptionsProvider.future);
        return true;
      }
      _rollbackRunning(request);
      _reportPortalFailureReason(
        answer.cancelled
            ? 'the switch to the portal was cancelled'
            : (answer.reason.isEmpty
                  ? 'the portal did not start'
                  : answer.reason),
      );
      return false;
    } finally {
      _startingChild = false;
    }
  }

  /// The document the portal's child runs, and the node it belongs to.
  ///
  /// Building it is a read of the profile, never a start: the caller turns it into the one
  /// transaction, and a profile that cannot produce a node is reported before anything of
  /// the previous owner is stopped.
  Future<_PortalChildDocument?> _portalChildDocument() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      _reportPortalFailureReason('no profile is selected');
      return null;
    }
    final body = await profile.readXrayFormat();
    if (body == null) {
      _reportPortalFailureReason('this subscription has no engine format');
      return null;
    }
    // The stored pick is the node the child ran last for this profile, which is the one the
    // owner chose; an empty or stale name falls back to the panel's first server.
    final settings = ref.read(appSettingProvider);
    final server = xrayServerFor(
      parseXraySubscription(body),
      portalXrayPickFor(settings, profile.id),
    );
    if (server == null) {
      _reportPortalFailureReason(
        'this subscription has no node the portal core can run',
      );
      return null;
    }
    return _PortalChildDocument(
      profileId: profile.id,
      name: server.name,
      config: jsonEncode(server.config),
    );
  }

  /// The pick is a commit, not a hope: written only for a node the child acknowledged.
  void _commitPortalPick(_PortalChildDocument document) {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) => withPortalXrayPick(state, document.profileId, document.name),
        );
    commonPrint.log('portal child is reading the tunnel on ${document.name}');
  }

  void _reportPortalFailureReason(String reason) {
    _lastPortalFailure = reason;
    commonPrint.log('portal did not start: $reason', logLevel: LogLevel.error);
    dialogs.showNotifier(
      currentAppLocalizations.portalStartFailed(reason),
      level: MessageLevel.error,
    );
  }

  /// The service reads its options from the shared state, which the settings feed; a mode
  /// that just changed has to reach it before the service is asked to make the tunnel.
  Future<void> _syncPortalOptions() async {
    if (!system.isAndroid) return;
    await ref.read(vpnOptionsProvider.future);
    await service?.syncState(ref.read(sharedStateProvider).needSyncSharedState);
  }

  Future<void> _startCoreRunning(_RunRequest request) async {
    if (!await _setCoreRunning(request) && _isCurrent(request)) {
      throw _unanswered(CoreMethod.startListener);
    }
  }

  Future<bool> _setPortalServiceRunning(_RunRequest request) {
    return _listenerScheduler.run(() async {
      if (!_isCurrent(request)) {
        return true;
      }
      if (request.running && ref.read(suspendProvider)) {
        return true;
      }
      if (ref.read(safeModeProvider)) {
        return true;
      }
      return _setPortalListening(request.running);
    });
  }

  Future<bool> _setPortalListening(bool running) async {
    final vpnOptions = await ref.read(vpnOptionsProvider.future);
    final answered = await setPortalServiceRunning(running);
    ref.read(runningVpnOptionsProvider.notifier).value = running && answered
        ? vpnOptions
        : null;
    return answered;
  }

  Future<bool> _stop(_RunRequest request) async {
    // The simple portal's run is the service and the child it carries: stopping it is the
    // service's own stop on both sides, with no engine listener asked for either way.
    final simple = _isSimplePortal;
    final bool answered;
    try {
      answered = simple
          ? await _setPortalServiceRunning(request)
          : await _setCoreRunning(request);
    } catch (_) {
      _rollbackRunning(request);
      rethrow;
    }
    if (!_isCurrent(request)) {
      return true;
    }
    _clearTraffic();
    // A silent Core is gone or hung; running again would proxy traffic to it.
    if (!answered) {
      throw simple
          ? _unansweredPortalService()
          : _unanswered(CoreMethod.stopListener);
    }
    return true;
  }

  void _clearTraffic() {
    resetCoreTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
  }

  Future<bool> _setCoreRunning(_RunRequest request) {
    return _listenerScheduler.run(() async {
      if (!_isCurrent(request)) {
        return true;
      }
      if (request.running && ref.read(suspendProvider)) {
        return true;
      }
      if (ref.read(safeModeProvider)) {
        return true;
      }
      return _setListening(request.running);
    });
  }

  Future<bool> _setListening(bool running) async {
    final vpnOptions = await ref.read(vpnOptionsProvider.future);
    final answered = await setCoreRunning(running);
    ref.read(runningVpnOptionsProvider.notifier).value = running && answered
        ? vpnOptions
        : null;
    return answered;
  }

  CoreMethodException _unanswered(CoreMethod method) => CoreMethodException(
    code: 'no_response',
    message: 'Core did not answer ${method.name}',
  );

  /// The service's own refusal, not the engine's: no engine listener was asked for here.
  CoreMethodException _unansweredPortalService() => const CoreMethodException(
    code: 'no_response',
    message: 'The Android service did not start the portal tunnel',
  );

  /// An excluded SSID parks the listener without ending the run.
  void syncSuspend() {
    debouncer.call(FunctionTag.suspend, () {
      return _listenerScheduler.run(() async {
        if (!ref.read(isStartProvider) || ref.read(safeModeProvider)) {
          return;
        }
        await _setListening(!ref.read(suspendProvider));
      });
    });
  }

  Future<void> restartVpn() async {
    if (!ref.read(isStartProvider)) {
      return;
    }
    final request = _RunRequest(
      running: true,
      initialize: false,
      resume: false,
      previousStartTime: _startTime,
    );
    _latestRunRequest = request;
    _startTime = null;
    _setLocalRunning(true);
    final bool? answered;
    try {
      answered = await _listenerScheduler.run(() async {
        if (!_isCurrent(request) ||
            ref.read(suspendProvider) ||
            ref.read(safeModeProvider)) {
          return null;
        }
        final vpnOptions = await ref.read(vpnOptionsProvider.future);
        final answered = _isSimplePortal
            ? await restartPortalServiceRunning()
            : await restartCoreRunning();
        if (answered) {
          ref.read(runningVpnOptionsProvider.notifier).value = vpnOptions;
        }
        return answered;
      });
    } catch (_) {
      _keepRunning(request);
      rethrow;
    }
    if (answered == null || !_isCurrent(request)) {
      return;
    }
    if (!answered) {
      _keepRunning(request);
      throw _unanswered(CoreMethod.startListener);
    }
    _clearTraffic();
  }

  void _keepRunning(_RunRequest request) {
    if (_isCurrent(request)) {
      _startTime = request.previousStartTime;
      _setLocalRunning(true);
    }
  }

  void _rollbackRunning(_RunRequest request) {
    if (!_isCurrent(request)) {
      return;
    }
    _startTime = request.previousStartTime;
    _setLocalRunning(!request.running);
  }

  bool _isCurrent(_RunRequest request) => identical(_latestRunRequest, request);

  /// Identity of the latest run request, answered or rolled back alike.
  Object? get runIntent => _latestRunRequest;

  /// A stop that undid a failed start leaves the run still asked for.
  bool? get requestedRunning {
    final request = _latestRunRequest;
    return request == null
        ? null
        : request.running || request.undoesFailedStart;
  }

  Future<void> updateConfigDebounce() async {
    _configRequests++;
    debouncer.call(FunctionTag.updateConfig, updateConfig);
  }

  /// A start carries the settings that are true *now*.
  ///
  /// The service reads its options from the shared state, and the state is only as fresh as
  /// the last push: a mode that changed a moment ago is a setting the service has not heard
  /// of yet. A start that arrived before the push used to be the caller's problem; with one
  /// transaction it is this method's, because the transaction is what asks for the tunnel
  /// and cannot resend anything itself.
  @protected
  Future<bool> setCoreRunning(bool running) async {
    if (!running) return _core.stopListener();
    await _syncPortalOptions();
    return _core.startListener();
  }

  @protected
  Future<bool> restartCoreRunning() async {
    await _syncPortalOptions();
    return _core.restartListener();
  }

  /// The Android service alone: the simple portal's start, stop and restart.
  @protected
  Future<bool> setPortalServiceRunning(bool running) async {
    if (!running) return _core.stopPortalService();
    await _syncPortalOptions();
    return _core.startPortalService();
  }

  @protected
  Future<bool> restartPortalServiceRunning() async {
    await _syncPortalOptions();
    return _core.restartPortalService();
  }

  @protected
  void resetCoreTraffic() {
    _core.resetTraffic();
  }

  @visibleForTesting
  Future<void> updateConfig() async {
    _configRequests++;
    await globalState.safeRun(() async {
      // "Config is not applied" is the answer when there is no config to update: the simple
      // portal never builds the engine one, and between a stop and the next start nothing of
      // the engine listens at all. The start that follows pushes the profile itself, so this
      // push would be nothing but the error it produces — on screen, in the middle of a switch.
      if (_isSimplePortal || !ref.read(isStartProvider)) {
        return;
      }
      final patchConfig = ref.read(patchClashConfigProvider);
      final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
      if (!shouldContinueSetup) {
        await _restartCoreAfterAuthorization();
        return;
      }
      // Behind the apply in flight: until its push lands the Core has no
      // config to update and answers "config is not applied".
      final message = await _setupScheduler.run(() {
        final networkSetting = ref.read(networkSettingProvider);
        return _core.updateConfig(
          _effectivePatchConfig(
            ref.read(patchClashConfigProvider),
          ).toUpdateParams(
            authentication: networkSetting.authentication.credentials,
            skipCertVerify: !ref.read(appSettingProvider).checkCertificate,
          ),
        );
      });
      if (message.isNotEmpty) {
        // The engine has no config to update: the apply that gives it one is still in flight,
        // or none was pushed in this process yet. Nothing failed here — the push that follows
        // (or the one under way) carries the settings — so this is neither an error to show
        // nor a reason to fail a waiter that asked for a settings change.
        if (message == 'config is not applied') {
          commonPrint.log('config update skipped: the engine has no config yet');
          return;
        }
        throw MessageException(message);
      }
      _reconcileTun();
    });
  }

  @protected
  Duration get minApplyDebounce => const Duration(seconds: 2);

  /// A push held up by a rule-set download or a Core timeout says little
  /// about the load, yet would hold back every apply after it.
  @protected
  Duration get maxApplyDebounce => const Duration(seconds: 10);

  void applyProfileDebounce({bool silence = false, bool force = false}) {
    _configRequests++;
    _pendingForceApply |= force;
    debouncer.call(
      FunctionTag.applyProfile,
      (silence) {
        final force = _pendingForceApply;
        _pendingForceApply = false;
        applyProfile(silence: silence, force: force);
      },
      args: [silence],
      duration: Duration(
        microseconds: _lastPushDuration.inMicroseconds.clamp(
          minApplyDebounce.inMicroseconds,
          maxApplyDebounce.inMicroseconds,
        ),
      ),
    );
  }

  /// The same apply, pushed now — for the caller that is the reason the inputs changed.
  ///
  /// [applyProfileDebounce] exists for edits: an editor can change ten inputs in a minute and
  /// only the last one is worth a push. A mode switch is not an edit. The owner is watching
  /// the list that the push fills, and the 2–10 s the coalescing waits are the delay he sees
  /// between the tap and a portal whose engine has a config. The debounced push carries the
  /// same inputs, so it is cancelled rather than left to fire again behind this one.
  ///
  /// The push is not awaited, and it is a background task in the full sense: the tunnel
  /// already has its new owner, and a switch that waited on a rule-set download would be the
  /// same freeze under another name. Its failure is reported the way every scheduled push
  /// reports one — a line in the app's log — and not as a banner over a portal that is
  /// working: a switch that goes back the other way while this push is in flight leaves the
  /// engine with no config, and `config is not applied` there is not a defect to show.
  void applyProfileNow({bool force = true, bool silence = true}) {
    debouncer.cancel(FunctionTag.applyProfile);
    _pendingForceApply = false;
    unawaited(() async {
      try {
        await applyProfile(force: force, silence: silence);
      } catch (error, stackTrace) {
        commonPrint.log(
          'apply now: ${compactError(error)}, $stackTrace',
          logLevel: LogLevel.warning,
        );
      }
    }());
  }

  /// A mode the user picks in the app, asked first while the subscription
  /// sets it; the tray and hotkeys have nowhere to ask and take it over.
  ///
  /// The answer is typed: a mode that is not offered, or a take-over the user declined, is
  /// a cancellation, not a silent `void` the caller has to guess about.
  Future<PortalCoreResult> pickMode(Mode mode, {bool ask = true}) async {
    if (!ref.read(availableModesProvider).contains(mode)) {
      return PortalCoreResult.unavailable('the mode ${mode.name} is not offered here');
    }
    // The mode's own document has to still be answering. Three failed fetches in a row take
    // the mode off every entry at once, because this is the one place they all come through —
    // the switch, the tray, the hotkey and Quick Settings.
    final denial = _feedDenial(mode);
    if (denial != null) {
      commonPrint.log(
        'mode ${mode.name} refused: $denial',
        logLevel: LogLevel.warning,
      );
      return PortalCoreResult.unavailable(denial);
    }
    final managed = ref.read(managedSettingsActionProvider.notifier);
    if (!ask) {
      managed.takeOverIfLocked('clash.mode');
    } else if (!await managed.confirmTakeOver('clash.mode')) {
      return const PortalCoreResult.cancelled('the panel setting was left in place');
    }
    changeMode(mode);
    return const PortalCoreResult.ok();
  }

  /// The feed a mode needs, or null for a mode that has none (desktop's own modes).
  PortalFeed? _feedOf(Mode mode) => switch (mode) {
        Mode.global => PortalFeed.xray,
        Mode.rule => PortalFeed.engine,
        _ => null,
      };

  /// Why this mode must not be entered, or null while its document still answers.
  String? _feedDenial(Mode mode) {
    final feed = _feedOf(mode);
    return feed == null ? null : portalFeeds.denialOf(feed);
  }

  void changeMode(Mode mode) {
    if (!ref.read(availableModesProvider).contains(mode)) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(GroupName.GLOBAL.name);
    }
  }

  /// For leaving an editor: a profile whose inputs match the config the Core
  /// already runs is not rebuilt, which on a large profile takes a while.
  /// Replaces the running child's document with the profile that has just arrived.
  ///
  /// A subscription update in the simple portal used to change only the file: nothing asked
  /// the child to read it, so the portal kept running the nodes of the previous revision until
  /// it was closed and opened again. The child is replaced on the same tunnel the way a node
  /// tap replaces it — same node if it still exists, the profile's first otherwise — and a
  /// document that cannot be built leaves the running child exactly as it was.
  Future<bool> reapplyPortalDocument() async {
    if (!_isSimplePortal || !ref.read(isStartProvider)) return false;
    final document = await _portalChildDocument();
    if (document == null) return false;
    final answer = await portalRuntime.startChild(document.config);
    if (answer.ok) {
      _commitPortalPick(document);
      commonPrint.log('portal child reloaded on ${document.name}');
      return true;
    }
    commonPrint.log(
      'portal child reload refused, the previous document keeps running: '
      '${answer.reason}',
      logLevel: LogLevel.warning,
    );
    return false;
  }

  void autoApplyProfile() {
    runAfterFrame(() async {
      if (!await inputsApplied()) {
        await applyProfile();
      }
    });
  }

  void applyIfGlobalRulesUsed() {
    final profile = ref.read(currentProfileProvider);
    if (profile == null ||
        profile.type == ProfileType.custom ||
        profile.extendType != ExtendType.standard) {
      return;
    }
    applyProfileDebounce(silence: true);
  }

  /// Whether the Core runs what the current profile and settings make now.
  Future<bool> inputsApplied() async {
    final applied = _appliedInputs;
    if (applied == null) {
      return false;
    }
    final profileId = ref.read(currentProfileIdProvider);
    final SetupState setupState;
    try {
      setupState = await ref.read(setupStateProvider(profileId).future);
    } catch (_) {
      return false;
    }
    return applied ==
        (
          setupState,
          _effectivePatchConfig(ref.read(patchClashConfigProvider)),
          ref.read(networkSettingProvider),
          _appliedParams,
        );
  }

  // False means building the profile, the config write, or the Core setup
  // step failed; a profile that fails to build is still pushed to the Core
  // as the empty config so it never keeps serving the previous one.
  // authorizeCore failures still throw.
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    final result = await _runSetup(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
    );
    return result != _SetupTaskResult.failed;
  }

  Future<_SetupTaskResult> _runSetup({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    _configRequests++;
    final _SetupTaskResult result;
    try {
      result = await _setupScheduler.run(() {
        return _setupConfig(
          force: force,
          silence: silence,
          preloadInvoke: preloadInvoke,
          onUpdated: () async {
            await ref.read(proxiesActionProvider.notifier).updateGroups();
            await ref.read(providersProvider.notifier).syncProviders();
          },
        );
      });
    } catch (error) {
      // The engine's own complaint, kept for whoever is waiting on this push: a switch that
      // times out should say what the Core said, not how long it waited.
      _lastConfigError = compactError(error);
      rethrow;
    }
    if (result == _SetupTaskResult.failed) {
      if (_lastConfigError.isEmpty) {
        _lastConfigError = 'the profile could not be applied';
      }
    } else {
      _lastConfigError = '';
    }
    if (result != _SetupTaskResult.handoffToCoreRestart) {
      if (result == _SetupTaskResult.completed) _reconcileTun();
      return result;
    }
    // Release the current serial task before restartCore reapplies the profile.
    final restarted = await _restartCoreAfterAuthorization();
    return restarted ? _SetupTaskResult.completed : _SetupTaskResult.failed;
  }

  Future<bool> _restartCoreAfterAuthorization() async {
    _tunMissed = false;
    final coreAction = ref.read(coreActionProvider.notifier);
    // Awaited from inside its own restore, the restart would wait on itself.
    final underWay = coreAction.requestRelaunch();
    if (underWay != null) {
      unawaited(underWay.then((_) {}, onError: (_) => _reopenAuthorization()));
      return true;
    }
    try {
      return await coreAction.restartCore();
    } catch (_) {
      _reopenAuthorization();
      rethrow;
    }
  }

  void _reopenAuthorization() {
    ref.read(authorizedTunEnableProvider.notifier).value =
        TunAuthorizationState.none;
  }

  /// The Core goes on without a TUN it could not open; the next enable
  /// authorizes again, as the authorization the Core ran under did not hold.
  Future<void> tunFailed() async {
    while (true) {
      final tun = ref.read(patchClashConfigProvider).tun;
      final profileId = ref.read(currentProfileIdProvider);
      final requests = _configRequests;
      if (!tun.enable) return;
      // A push still waiting may open the TUN, or skip the Core as unchanged
      // and report nothing, so the Core is asked once it has gone.
      if (_pushWaiting) {
        await Future<void>.delayed(tunRecheckDelay);
        continue;
      }
      if (!await confirmTunFailed()) return;
      // A config asked for meanwhile may sit behind the answer, unpushed.
      if (!_pushWaiting &&
          requests == _configRequests &&
          ref.read(patchClashConfigProvider).tun == tun &&
          ref.read(currentProfileIdProvider) == profileId) {
        break;
      }
    }
    _tunMissed = true;
    _reopenAuthorization();
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: false));
    dialogs.showNotifier(
      currentAppLocalizations.tunStartFailed,
      level: MessageLevel.error,
    );
  }

  /// With a base, [BuiltProfile.yaml] is only the overlay the Core applies.
  Future<BuiltProfile> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) {
      return (yaml: '', md5: '', counts: configCountsOf(const {}), base: null);
    }
    final defaultUA = globalState.ua;
    final networkSetting = ref.read(
      networkSettingProvider.select(
        (state) => (
          appendSystemDns: state.appendSystemDns,
          bypassPrivateRoute: state.bypassPrivateRoute,
          authentication: state.authentication,
        ),
      ),
    );
    final appendSystemDns = networkSetting.appendSystemDns;
    final isCustom = setupState.profileType == ProfileType.custom;
    final scriptContent =
        !isCustom && setupState.extendType == ExtendType.script
        ? await setupState.script?.content
        : null;
    final hasScript = scriptContent?.isNotEmpty == true;
    // Chains build on the profile's own proxies and groups, which a base
    // leaves out for the Core to merge back in.
    final profileBase =
        !isCustom && !hasScript && setupState.proxyChains.isEmpty
        ? await _core.getProfileBase(profileId)
        : null;
    Map<String, dynamic> rawConfig = isCustom
        ? {
            'proxies': appProxiesPayload(
              setupState.appProxies,
              dialers: setupState.proxyDialers,
              groups: setupState.proxyGroups,
            ),
          }
        : profileBase?.base.config ?? await _core.getConfig(profileId);
    final proxyGroups = isCustom ? setupState.proxyGroups : <ProxyGroup>[];
    final rules = isCustom ? setupState.rules : <Rule>[];
    if (hasScript) {
      rawConfig = await handleEvaluate(scriptContent!, rawConfig);
    }
    final directory = await appPath.profilesPath;
    final injected = await _resolveInjectedProviders(
      setupState,
      proxyGroups: proxyGroups,
      rules: rules,
    );
    final res = await makeRealProfileTask(
      MakeRealProfileState(
        rules: rules,
        proxyGroups: proxyGroups,
        injectedProxyProviders: injected.proxies,
        injectedRuleProviders: injected.rules,
        profilesPath: directory,
        profileId: profileId,
        rawConfig: rawConfig,
        realPatchConfig: patchConfig,
        overrides: setupState.overrides,
        bypassPrivateRoute: networkSetting.bypassPrivateRoute,
        keepEmptyDnsOverrides: setupState.profileType != ProfileType.custom,
        appendSystemDns: appendSystemDns,
        addedRules: setupState.addedRules,
        defaultUA: defaultUA,
        authentication: networkSetting.authentication.credentials,
        matchTarget:
            profileBase == null ||
                setupState.matchTarget?.trim().isNotEmpty == true
            ? setupState.matchTarget
            : lastMatchTarget(profileBase.base.matchRules),
        safeMode: ref.read(safeModeProvider),
        proxyChains: setupState.proxyChains,
      ),
    );
    if (profileBase == null) {
      return (yaml: res.yaml, md5: res.md5, counts: res.counts, base: null);
    }
    final (:base, :path) = profileBase;
    return (
      yaml: res.yaml,
      md5: '${res.md5}${base.digest}'.toMd5(),
      counts: (
        groups: res.counts.groups + base.proxyGroups,
        proxies: res.counts.proxies + base.proxies,
        rules: res.counts.rules + base.rules,
      ),
      base: SetupBase(path: path, overlay: res.yaml),
    );
  }

  /// Only what the custom profile actually references is injected, so an
  /// app-level provider costs nothing in the profiles that never name it.
  Future<({Map<String, dynamic> proxies, Map<String, dynamic> rules})>
  _resolveInjectedProviders(
    SetupState setupState, {
    required List<ProxyGroup> proxyGroups,
    required List<Rule> rules,
  }) async {
    final usedProxyProviders = <String>{
      for (final proxyGroup in proxyGroups) ...?proxyGroup.use,
    };
    final usedRuleProviders = <String>{
      for (final rule in rules) ...rule.ruleSets,
      if (setupState.profileType == ProfileType.custom)
        ...setupState.overrides.ruleSets,
    };
    if (usedProxyProviders.isEmpty && usedRuleProviders.isEmpty) {
      return (
        proxies: const <String, dynamic>{},
        rules: const <String, dynamic>{},
      );
    }
    final options = setupState.overrides.proxyProviders;
    final proxies = <String, dynamic>{};
    for (final entry in setupState.profileProviders.entries) {
      if (!usedProxyProviders.contains(entry.key)) {
        continue;
      }
      proxies[entry.key] = {
        'type': 'file',
        'path': await appPath.getProfilePath(entry.value.toString()),
        ...?options[entry.key]?.definition,
      };
    }
    final clashProvidersAction = ref.read(
      clashProvidersActionProvider.notifier,
    );
    final ruleProviders = <String, dynamic>{};
    for (final provider in setupState.clashProviders) {
      if (!usedRuleProviders.contains(provider.label)) {
        continue;
      }
      final prepared = await clashProvidersAction.prepare(provider);
      ruleProviders[prepared.label] = prepared.definition(
        await prepared.corePath,
      );
    }
    return (proxies: proxies, rules: ruleProviders);
  }

  Future<String> getProfileWithId(int profileId) async {
    try {
      final setupState = await ref.read(setupStateProvider(profileId).future);
      final patchClashConfig = ref.read(patchClashConfigProvider);
      final res = await getProfile(
        setupState: setupState,
        patchConfig: patchClashConfig,
      );
      return switch (res.base) {
        final base? => await _core.buildProfile(base),
        null => res.yaml,
      };
    } catch (e) {
      dialogs.showNotifier(e.toString(), level: MessageLevel.error);
    }
    return '';
  }

  PatchClashConfig _effectivePatchConfig(PatchClashConfig patchConfig) {
    if (ref.read(safeModeProvider)) {
      return patchConfig.copyWith(
        tun: patchConfig.tun.copyWith(enable: false),
        externalController: '',
      );
    }
    final authorized =
        ref.read(authorizedTunEnableProvider) ==
        TunAuthorizationState.authorized;
    final secure = ref.read(androidSecureProvider);
    return patchConfig.copyWith(
      tun: patchConfig.tun.copyWith(
        enable: patchConfig.tun.enable && authorized,
      ),
      mixedPort: secure ? 0 : patchConfig.mixedPort,
      port: secure ? 0 : patchConfig.port,
      socksPort: secure ? 0 : patchConfig.socksPort,
      redirPort: secure ? 0 : patchConfig.redirPort,
      tproxyPort: secure ? 0 : patchConfig.tproxyPort,
    );
  }

  /// The event may describe a push a later one replaced.
  @protected
  Future<bool> confirmTunFailed() => _setupScheduler.run(_core.getTunFailed);

  /// A Core drops the event for a TUN it could not open once its queue is
  /// full, so a push that asked for TUN asks after it as well.
  void _reconcileTun() {
    if (!ref.mounted ||
        !coreNeedsAuthorization ||
        ref.read(safeModeProvider) ||
        !ref.read(patchClashConfigProvider).tun.enable) {
      return;
    }
    unawaited(
      tunFailed().catchError((Object error) {
        commonPrint.log('TUN check failed: $error', logLevel: LogLevel.warning);
      }),
    );
  }

  bool get _pushWaiting =>
      debouncer.isPending(FunctionTag.updateConfig) ||
      debouncer.isPending(FunctionTag.applyProfile);

  @protected
  Duration get tunRecheckDelay => const Duration(milliseconds: 300);

  @protected
  Future<AuthorizeCode> authorizeCore() {
    return system.authorizeCore();
  }

  /// Android drives its TUN through the VPN service; the core is never
  /// elevated there, so nothing is asked and the core's own tun stays off.
  @protected
  bool get coreNeedsAuthorization => !system.isAndroid;

  @visibleForTesting
  Future<bool> requestAdmin(bool enableTun) async {
    if (!enableTun || !coreNeedsAuthorization || ref.read(safeModeProvider)) {
      return true;
    }
    final authorizationState = ref.read(authorizedTunEnableProvider);
    if (authorizationState != TunAuthorizationState.none) {
      return true;
    }

    final authorizationNotifier = ref.read(
      authorizedTunEnableProvider.notifier,
    );
    authorizationNotifier.value = TunAuthorizationState.unauthorized;

    final code = await authorizeCore();

    switch (code) {
      case AuthorizeCode.success:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return false;
      case AuthorizeCode.none:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        // A fallback launch, or one from before the install, ran the Core
        // that missed the TUN without the authorization now in place.
        return !_tunMissed;
      case AuthorizeCode.error:
        authorizationNotifier.value = TunAuthorizationState.none;
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: false));
        dialogs.showNotifier(
          currentAppLocalizations.tunAuthorizationFailed,
          level: MessageLevel.error,
        );
        return true;
    }
  }

  /// An empty profile list is left alone: it is the first-run state, and it is
  /// what the profile stream holds before its first emission.
  @visibleForTesting
  Profile? recoverMissingProfile() {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return null;
    final profiles = ref.read(profilesProvider);
    if (profiles.isEmpty) return null;
    final fallback = profiles.first;
    commonPrint.log(
      'profile $profileId is missing, falling back to ${fallback.id}',
      logLevel: LogLevel.warning,
    );
    ref.read(currentProfileIdProvider.notifier).value = fallback.id;
    return fallback;
  }

  Future<_SetupTaskResult> _setupConfig({
    bool force = false,
    bool silence = false,
    Future<void> Function()? preloadInvoke,
    FutureOr Function()? onUpdated,
  }) async {
    var profile = ref.read(currentProfileProvider) ?? recoverMissingProfile();
    // A refresh failure is surfaced by safeRun; setup keeps the old profile.
    if (profile case final missing? when await missing.isMissingFile) {
      await globalState.safeRun(
        () => ref
            .read(profilesActionProvider.notifier)
            .fetchMissingFile(missing.id),
      );
      final current = ref.read(currentProfileProvider);
      profile = current;
    }
    commonPrint.log('setup ===> ${profile?.realLabel}');
    if (_isSimplePortal) {
      // The simple portal runs no engine: nothing is built for it, nothing is pushed and the
      // config it last applied stays untouched. The subscription is still read where the
      // child's node list comes from — that file, not the Core, is the source of the list.
      return _SetupTaskResult.completed;
    }
    final patchConfig = ref.read(patchClashConfigProvider);
    final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
    if (!shouldContinueSetup) {
      return _SetupTaskResult.handoffToCoreRestart;
    }
    final pushWatch = Stopwatch()..start();
    final realPatchConfig = _effectivePatchConfig(patchConfig);
    final networkSetting = ref.read(networkSettingProvider);
    SetupState? setupState;
    final realProfile = await globalState.safeRun(() async {
      final state = await ref.read(setupStateProvider(profile?.id).future);
      setupState = state;
      return getProfile(setupState: state, patchConfig: realPatchConfig);
    }, title: 'build profile');
    final profileFailed = realProfile == null;
    final setupParams = _setupParams.copyWith(base: realProfile?.base);
    final inputs = switch (setupState) {
      final state? when !profileFailed => (
        state,
        realPatchConfig,
        networkSetting,
        _appliedParams,
      ),
      _ => null,
    };
    final yamlString = realProfile?.yaml ?? '';
    final yamlMd5 = realProfile?.md5 ?? '';
    if (!profileFailed && yamlMd5 == globalState.lastConfigMd5 && !force) {
      _appliedInputs = inputs;
      globalState.lastConfigCounts = realProfile.counts;
      await preloadInvoke?.call();
      return _SetupTaskResult.completed;
    }
    // Go answers a config it rejects by running its built-in default, which
    // has no proxies, so until this push succeeds no applied config is known.
    _appliedInputs = null;
    _pushes++;
    globalState.lastConfigMd5 = null;
    globalState.lastConfigCounts = null;
    if (system.isAndroid) {
      await ref.read(vpnOptionsProvider.future);
      await preferences.saveShareState(ref.read(sharedStateProvider));
      await preferences.saveAppliedConfigMd5(null);
    }
    // Recaptured so _start's catch can roll back after safeRun swallows it.
    (Object, StackTrace)? handoffFailure;
    var setupFailed = false;
    await globalState.loadingRun(
      () async {
        try {
          if (setupParams.base == null) {
            final configFilePath = await appPath.configFilePath;
            await File(configFilePath).writeAsStringAtomically(yamlString);
          }
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          final String message;
          try {
            message = await _core.setupConfig(
              params: setupParams,
              preloadInvoke: preloadInvoke,
            );
          } finally {
            _pushes++;
          }
          if (message.isNotEmpty) {
            globalState.lastConfigCounts = configCountsOf(const {});
            await globalState.safeRun(() => onUpdated?.call());
            throw MessageException(message);
          }
        } catch (e, s) {
          setupFailed = true;
          _lastConfigError = compactError(e);
          if (preloadInvoke != null) {
            handoffFailure = (e, s);
          }
          rethrow;
        }
        globalState.lastConfigMd5 = yamlMd5;
        globalState.lastConfigCounts =
            realProfile?.counts ?? configCountsOf(const {});
        _appliedInputs = inputs;
        if (system.isAndroid) {
          await preferences.saveAppliedConfigMd5(yamlMd5);
        }
        if (profile?.id == ref.read(currentProfileIdProvider)) {
          await ref
              .read(proxiesActionProvider.notifier)
              .resendPicksSince(setupParams.selectedMap);
        }
        await onUpdated?.call();
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
    _lastPushDuration = pushWatch.elapsed;
    if (handoffFailure != null) {
      Error.throwWithStackTrace(handoffFailure!.$1, handoffFailure!.$2);
    }
    if (setupFailed || profileFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
