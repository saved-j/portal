part of '../state.dart';

@riverpod
UpdateParams updateParams(Ref ref) {
  final authentication = ref.watch(
    networkSettingProvider.select((state) => state.authentication),
  );
  final checkCertificate = ref.watch(
    appSettingProvider.select((state) => state.checkCertificate),
  );
  return ref.watch(
    patchClashConfigProvider.select(
      (state) => state.toUpdateParams(
        authentication: authentication.credentials,
        skipCertVerify: !checkCertificate,
      ),
    ),
  );
}

@riverpod
({PatchClashConfig patchConfig, bool appendSystemDns, bool bypassPrivateRoute})
setupPatch(Ref ref) {
  return (
    patchConfig: ref.watch(
      patchClashConfigProvider.select((state) => state.setupOnly),
    ),
    appendSystemDns: ref.watch(
      networkSettingProvider.select((state) => state.appendSystemDns),
    ),
    // Android's VPN service takes it on its next start instead.
    bypassPrivateRoute:
        system.isDesktop &&
        ref.watch(
          networkSettingProvider.select((state) => state.bypassPrivateRoute),
        ),
  );
}

@riverpod
TrayState trayState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final systemProxy = ref.watch(
    networkSettingProvider.select((state) => state.systemProxy),
  );
  final clashConfig = ref.watch(
    patchClashConfigProvider.select(
      (state) => (
        mode: state.mode,
        mixedPort: state.mixedPort,
        tunEnable: state.tun.enable,
      ),
    ),
  );
  final appSetting = ref.watch(
    appSettingProvider.select(
      (state) => (
        autoLaunch: state.autoLaunch,
        showTrayTitle: state.showTrayTitle,
        menuBarMode: state.menuBarMode,
        monochromeTrayIcon: state.monochromeTrayIcon,
      ),
    ),
  );
  final groups = clashConfig.mode == Mode.global
      ? () {
          // The simple portal has no engine groups; the tray lists its Xray servers as one
          // synthetic group instead, so the mode switch is reflected in the menu.
          final servers =
              ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[];
          return servers.isEmpty
              ? const <Group>[]
              : [portalGroupOfServers(servers)];
        }()
      : ref.watch(currentGroupsStateProvider).value;
  final selectedMap = ref.watch(selectedMapProvider);
  final safeMode = ref.watch(safeModeProvider);
  final suspended = ref.watch(suspendProvider);
  final hotKeys = _trayHotKeys(ref);

  return TrayState(
    mode: clashConfig.mode,
    port: clashConfig.mixedPort,
    autoLaunch: appSetting.autoLaunch,
    systemProxy: systemProxy,
    tunEnable: clashConfig.tunEnable,
    isStart: isStart,
    suspended: isStart && suspended,
    groups: groups,
    selectedMap: selectedMap,
    showTrayTitle: appSetting.showTrayTitle,
    menuBarMode: appSetting.menuBarMode,
    monochromeTrayIcon: appSetting.monochromeTrayIcon,
    safeMode: safeMode,
    hotKeys: hotKeys,
    globalModeAllowed: ref.watch(globalModeAllowedProvider),
    darkTheme: ref.watch(currentBrightnessProvider) == Brightness.dark,
  );
}

Map<HotAction, HotKeyAction> _trayHotKeys(Ref ref) {
  final failures = ref.watch(hotKeyFailuresProvider);
  return {
    for (final hotKeyAction in ref.watch(hotKeyActionsProvider))
      if (isValidHotKey(hotKeyAction.modifiers, hotKeyAction.key) &&
          !failures.containsKey(hotKeyAction.action))
        hotKeyAction.action: hotKeyAction,
  };
}

/// Measured delays of the proxies the tray lists, by group and then proxy
/// name. Resolved like a proxy card, so a nested group shows its selection.
@riverpod
Map<String, Map<String, int>> trayDelays(Ref ref) {
  final delayMap = ref.watch(delayDataSourceProvider);
  if (delayMap.isEmpty) {
    return const {};
  }
  final groups = ref.watch(currentGroupsStateProvider).value;
  final allGroups = ref.watch(groupsProvider);
  final selectedMap = ref.watch(selectedMapProvider);
  final defaultTestUrl = ref.watch(
    appSettingProvider.select((state) => state.testUrl),
  );
  final delays = <String, Map<String, int>>{};
  for (final group in groups) {
    final testUrl = group.testUrl.takeFirstValid([defaultTestUrl]);
    final selected = allGroups
        .getGroup(group.name)
        ?.getCurrentSelectedName(selectedMap[group.name] ?? '');
    final groupDelays = <String, int>{};
    for (final proxy in group.trayProxies(selected)) {
      final delay = computeProxyDelayState(
        proxyName: proxy.name,
        testUrl: testUrl,
        groups: allGroups,
        selectedMap: selectedMap,
        delayMap: delayMap,
      ).delay;
      if (delay != 0) {
        groupDelays[proxy.name] = delay;
      }
    }
    if (groupDelays.isNotEmpty) {
      delays[group.name] = groupDelays;
    }
  }
  return delays;
}

@riverpod
TrayTitleState trayTitleState(Ref ref) {
  final showTrayTitle = ref.watch(
    appSettingProvider.select((state) => state.showTrayTitle),
  );
  final traffic = ref.watch(
    trafficsProvider.select((state) => state.list.safeLast(const Traffic())),
  );
  return TrayTitleState(showTrayTitle: showTrayTitle, traffic: traffic);
}

@riverpod
HotKeyAction getHotKeyAction(Ref ref, HotAction hotAction) {
  return ref.watch(
    hotKeyActionsProvider.select((state) {
      final index = state.indexWhere((item) => item.action == hotAction);
      return index != -1 ? state[index] : HotKeyAction(action: hotAction);
    }),
  );
}

@riverpod
bool shouldPatchSystemDns(Ref ref) {
  final autoSetSystemDns = ref.watch(
    networkSettingProvider.select((state) => state.autoSetSystemDns),
  );
  if (!autoSetSystemDns || ref.watch(safeModeProvider)) {
    return false;
  }
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final tunEnable = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.enable),
  );
  final authorizationState = ref.watch(authorizedTunEnableProvider);
  return isStart &&
      tunEnable &&
      authorizationState == TunAuthorizationState.authorized;
}

@riverpod
SharedState sharedState(Ref ref) {
  ref.watch(loadedLocaleProvider);
  final currentProfile = ref.watch(
    currentProfileProvider.select(
      // A panel's profile label is often the user's name; the VPN notification is titled with
      // the service, as the expiry notice is. The raw `label` can be the whole title header the
      // panel packs (`portal-connect Статус Active 163.76 GiB | 0`), so the cleaned name is used.
      (state) => CurrentProfileSelectorState(
        label: state?.headers.serviceName ?? state?.realLabel ?? '',
        selectedMap: state?.selectedMap ?? {},
      ),
    ),
  );
  final appSetting = ref.watch(
    appSettingProvider.select(
      (state) => (
        showStopAction: state.showNotificationStopAction,
        testUrl: state.testUrl,
        checkCertificate: state.checkCertificate,
      ),
    ),
  );
  final currentProfileName = currentProfile.label;
  final selectedMap = currentProfile.selectedMap;
  final testUrl = appSetting.testUrl;
  final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
  final profileId = ref.watch(currentProfileIdProvider);
  final fullSettings = ref.watch(appSettingProvider);
  final liveGroup = portalGroupFor(fullSettings, profileId, false);
  final groups = ref.watch(currentGroupsStateProvider).value;
  // The server the notification names: the Xray node in the simple portal, the pick of the
  // filter whose chip is open in the network mode (the first filter when none is open). The
  // engine's raw selected-map is not the pick — it is the core's own state, not the choice the
  // owner sees.
  final activeGroup = liveGroup ?? groups.firstOrNull?.name ?? '';
  final allGroups = ref.watch(groupsProvider);
  // The pick is the filter's choice — often the "⚡️ Auto" group, not a node. The shade should
  // name the server the tunnel is really on, so the pick is walked through url-test/selector
  // groups down to the leaf node.
  final pick = mode == Mode.global
      ? portalXrayPickFor(fullSettings, profileId)
      : portalRulePickFor(fullSettings, profileId, activeGroup);
  // The stored pick is the owner's choice; when none is stored (a default-DIRECT filter or one
  // never picked) the engine's own selection is the honest route — DIRECT shows DIRECT, never an
  // empty line.
  final pickOrEngine = pick.isNotEmpty ? pick : (selectedMap[activeGroup] ?? '');
  final resolvedPick = computeRealSelectedProxyState(
    pickOrEngine,
    groups: allGroups,
    selectedMap: selectedMap,
  );
  // A group pick resolves to a node; the shade shows the whole chain so the owner reads both
  // the pick ("⚡ Auto") and the node it landed on ("Южная Корея").
  final resolvedName = resolvedPick.proxyName;
  final serverLine = resolvedName.isNotEmpty && resolvedName != pickOrEngine
      ? '$pickOrEngine - $resolvedName'
      : pickOrEngine;
  // The latency is measured for the actual node, not for the chain name shown above.
  final delayMap = ref.watch(delayDataSourceProvider);
  final defaultTestUrl = ref.watch(
    appSettingProvider.select((state) => state.testUrl),
  );
  final connectedDelay = mode == Mode.global
      ? 0
      : computeProxyDelayState(
          proxyName: resolvedName,
          testUrl: (groups
                      .where((g) => g.name == liveGroup)
                      .firstOrNull
                      ?.testUrl)
                  .takeFirstValid([defaultTestUrl]),
          groups: allGroups,
          selectedMap: selectedMap,
          delayMap: delayMap,
        ).delay;
  // The server line carries the server only; the latency sits beside it on the right. The
  // filter's flag or first letter rides in front so the owner reads which filter the route
  // belongs to even in the collapsed shade.
  final filterMark = mode == Mode.global ? '' : _filterMark(activeGroup);
  final currentServer =
      filterMark.isNotEmpty ? '$filterMark  $serverLine' : serverLine;
  final latency = connectedDelay > 0 ? '⚡ ${connectedDelay} ms' : '';
  final pingText = mode == Mode.global
      ? currentAppLocalizations.nextServer
      : currentAppLocalizations.testShort;
  // The info line: used traffic and the subscription's end date. This panel states usage only
  // in its own title and sends no subscription-userinfo, so the title's number is the fallback.
  final profile = ref.watch(currentProfileProvider);
  final subInfo = profile?.subscriptionInfo;
  final usedTraffic = (subInfo?.upload ?? 0) + (subInfo?.download ?? 0);
  final trafficLimit = subInfo?.total ?? 0;
  final statedTraffic = profile?.headers.trafficText;
  final trafficText = usedTraffic > 0 || trafficLimit > 0
      ? '${usedTraffic.traffic.show} / ${trafficLimit > 0 ? trafficLimit.traffic.show : '♾️'}'
      : statedTraffic != null
          ? '$statedTraffic / ♾️'
          : '';
  final expireDate = subInfo?.expireDate;
  final expiryText = expireDate == null
      ? ''
      : '${expireDate.day.toString().padLeft(2, '0')}.'
          '${expireDate.month.toString().padLeft(2, '0')}.${expireDate.year}';
  final detail = [trafficText, expiryText]
      .where((part) => part.isNotEmpty)
      .join(' · ');
  // The stats row: data actually transferred through the tunnel, and how long it has been up.
  final sessionTraffic = ref.watch(totalTrafficProvider);
  final runTime = ref.watch(runTimeProvider);
  final downText = sessionTraffic.down.traffic.show;
  final upText = sessionTraffic.up.traffic.show;
  final stats = runTime == null
      ? '↓ $downText · ↑ $upText'
      : '↓ $downText · ↑ $upText · ⏱ ${_uptime(runTime)}';
  // The servers the notification bolt pings: every node of the live group, the same sweep the
  // working screen's bolt runs. Empty in the simple portal — its bolt lives in the app, not in
  // the notification.
  final pingServers = mode == Mode.global
      ? const <String>[]
      : [
          for (final group in groups)
            if (group.name == liveGroup)
              for (final proxy in group.all) proxy.name,
        ];
  return SharedState(
    currentProfileName: currentProfileName,
    currentServer: currentServer,
    pingText: pingText,
    showPing: true,
    pingServers: pingServers,
    latency: latency,
    detail: detail,
    stats: stats,
    showStopAction: appSetting.showStopAction,
    stopText: currentAppLocalizations.stop,
    stopTip: currentAppLocalizations.stopVpn,
    startTip: currentAppLocalizations.startVpnNetwork,
    localNetworkTip: currentAppLocalizations.localNetworkDeniedTip,
    setupParams: SetupParams(
      selectedMap: selectedMap,
      testUrl: testUrl,
      skipCertVerify: !appSetting.checkCertificate,
    ),
    vpnOptions: ref.watch(vpnOptionsProvider).value,
  );
}

/// The tunnel's uptime as the owner reads it — "3ч 24м", "12м 5с", "40с".
String _uptime(int milliseconds) {
  final total = Duration(milliseconds: milliseconds);
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  final seconds = total.inSeconds % 60;
  if (hours > 0) return '${hours}ч ${minutes}м';
  if (minutes > 0) return '${minutes}м ${seconds}с';
  return '${seconds}с';
}

@Riverpod(keepAlive: true)
Future<List<String>> vpnRouteAddress(Ref ref) {
  final routes = ref.watch(
    patchClashConfigProvider.select(
      (state) => Tun(
        routeAddress: state.tun.routeAddress,
        routeExcludeAddress: state.tun.routeExcludeAddress,
      ),
    ),
  );
  final bypassPrivateRoute = ref.watch(
    networkSettingProvider.select((state) => state.bypassPrivateRoute),
  );
  return routes.vpnRouteAddress(bypassPrivateRoute: bypassPrivateRoute);
}

@Riverpod(keepAlive: true)
Future<VpnOptions> vpnOptions(Ref ref) async {
  final networkSetting = ref.watch(
    networkSettingProvider.select(
      (state) => (
        bypassDomain: state.bypassDomain,
        authenticated: state.authentication.credentials.isNotEmpty,
        bypassPrivateRoute: state.bypassPrivateRoute,
      ),
    ),
  );
  final clashConfig = ref.watch(
    patchClashConfigProvider.select(
      (state) => (tun: state.tun, mixedPort: state.mixedPort, mode: state.mode),
    ),
  );
  final vpnSetting = ref.watch(vpnSettingProvider);
  final safeMode = ref.watch(safeModeProvider);
  final androidSecure = ref.watch(androidSecureProvider);
  final routeAddress = await ref.watch(vpnRouteAddressProvider.future);
  final tun = clashConfig.tun;
  return VpnOptions(
    enable: vpnSetting.enable && !safeMode,
    stack: tun.stack.name,
    // VpnService.setHttpProxy cannot carry credentials, so an authenticated
    // mixed port is left to TUN instead of declared as the system proxy.
    systemProxy:
        vpnSetting.systemProxy &&
        !networkSetting.authenticated &&
        !safeMode &&
        !androidSecure,
    port: clashConfig.mixedPort,
    ipv6: vpnSetting.ipv6,
    dnsHijacking: vpnSetting.dnsHijacking,
    accessControlProps: vpnSetting.accessControlProps.withPackages(
      include: tun.includePackage,
      exclude: tun.excludePackage,
    ),
    allowBypass: vpnSetting.allowBypass,
    bypassDomain: networkSetting.bypassDomain,
    routeAddress: routeAddress,
    excludesAllRoutes: tun.excludesEveryRoute(
      routeAddress,
      bypassPrivateRoute: networkSetting.bypassPrivateRoute,
    ),
    mtu: tun.mtu,
    congestionController: tun.congestionController,
    // The simple portal has no engine to forward into: the service makes the tunnel and the
    // Xray child reads it. In the network mode the engine keeps it, exactly as before.
    xrayTun: clashConfig.mode == Mode.global,
  );
}

@riverpod
class AccessControlState extends _$AccessControlState
    with AutoDisposeNotifierMixin {
  @override
  AccessControlProps build() => const AccessControlProps();
}

@riverpod
bool suspend(Ref ref) {
  final currentSSID = ref.watch(currentSSIDProvider);
  final excludeSSIDs = ref.watch(excludeSSIDsProvider);
  return excludeSSIDs.contains(currentSSID);
}

/// The filter's own mark for the shade: a leading flag (two regional indicators) when the name
/// carries one, otherwise the first letter or digit — the same mark the tile shows.
String _filterMark(String name) {
  final flag = RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true).firstMatch(name);
  if (flag != null) return flag.group(0)!;
  final letter = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(name)?.group(0);
  return letter?.toUpperCase() ?? '';
}
