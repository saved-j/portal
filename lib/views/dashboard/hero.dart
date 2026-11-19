import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/enum/enum.dart' show Mode;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/tutorial/portal_tutorial.dart';
import 'package:fl_clash/views/tutorial/tutorial_bus.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/views/connection/connection_feeds.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'portal_controls.dart';
import 'portal_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fl_clash/common/outbound.dart';
import 'package:flutter/services.dart';

const heroMaxWidth = 520.0;

/// The controls keep the width they have on a phone; the list takes the rest.
const _wideControlsWidth = 420.0;

const _gap = 12.0;

/// The hero home page: the service's logo and name over the plan, the
/// server and one connect button, the way the fork drew it.
class HeroDashboard extends ConsumerStatefulWidget {
  const HeroDashboard({super.key});

  @override
  ConsumerState<HeroDashboard> createState() => _HeroDashboardState();
}

class _HeroDashboardState extends ConsumerState<HeroDashboard> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
    // The tour runs once, on the first screen a person can act on: a subscription is loaded
    // and there is something to point at. It is drawn after the frame, because it measures
    // the widgets underneath and they have to be laid out first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final setting = ref.read(appSettingProvider);
      if (setting.tutorialSeen && setting.tutorialVersion >= tutorialVersion) {
        return;
      }
      if (ref.read(profilesProvider).isEmpty) return;
      showPortalTutorial(context, fromStep: setting.tutorialStep);
    });
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final padding = EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 8,
      16,
      16 + context.bottomInset,
    );
    if (profile == null) {
      return Padding(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: heroMaxWidth),
            child: const _EmptyHero(),
          ),
        ),
      );
    }
    final headers = profile.headers;
    // How many columns the page gets is decided by the same rule the profiles and the
    // connection lists use — the fork's own: as many cards as fit, never fewer than one. The
    // dashboard does not invent a breakpoint of its own.
    return WidthBuilder(
      builder: (context, width) {
        final columns = getProfilesColumns(
          width - padding.horizontal,
          spacing: 16,
          minItemWidth: 320,
        );
        final wide = columns > 1;
        return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? width - padding.horizontal : heroMaxWidth,
        ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: padding.copyWith(bottom: _gap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // The name is centred on the screen itself, not on the space the
                            // buttons leave: two entry points on the left and up to two on the
                            // right made it drift every time one of them appeared or went away.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 112,
                              ),
                              child: Consumer(
                                // The working screen says the same two facts the list does:
                                // name, then traffic, then expiry, in one column.
                                builder: (context, ref, _) {
                                  // Only the name lives in the header. Traffic, expiry and the
                                  // state mark belong to the subscription card, which is where a
                                  // person looks for them.
                                  return EmojiText(
                                    headers.displayName ??
                                        headers.serviceName ??
                                        'portal-connect',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.title3.of(
                                      context,
                                      emphasized: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: context.appLocalizations.tools,
                                        // Pushed, not page-switched: a page index has no history, so
                                        // Back walked out of the app instead of returning here.
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ToolsView(),
                                              ),
                                            ),
                                        icon: const GlyphIcon(
                                          AppGlyphs.settings,
                                          size: 22,
                                        ),
                                      ),
                                      IconButton(
                                        // Shortcut to the per-app bypass list: the one setting a
                                        // user reaches for while looking at the server list.
                                        tooltip: context
                                            .appLocalizations
                                            .accessControl,
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const AccessView(),
                                              ),
                                            ),
                                        icon: const GlyphIcon(
                                          AppGlyphs.appsList,
                                          size: 22,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                // The connections list is the engine's answer, and in the simple
                                // portal no engine runs: the page could only ever be empty. The
                                // button exists exactly where its data exists — in the network.
                                if (ref.watch(
                                      patchClashConfigProvider.select(
                                        (s) => s.mode,
                                      ),
                                    ) !=
                                    Mode.global)
                                  GestureDetector(
                                    onDoubleTap: () => ref
                                        .read(
                                          portalConnectionsBadgeProvider
                                              .notifier,
                                        )
                                        .toggle(),
                                    child: IconButton(
                                      tooltip:
                                          context.appLocalizations.connections,
                                      // The connections page is not in the phone navigation any
                                      // more, so switching the page index did nothing: push it.
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ConnectionFeedsView(),
                                            ),
                                          ),
                                      icon: Badge(
                                        // Fixed colours: the hero is dark in both themes, so a
                                        // theme-derived label turned black-on-black on white.
                                        backgroundColor: const Color(
                                          0xFF00F5A0,
                                        ),
                                        textColor: const Color(0xFF07110C),
                                        isLabelVisible: ref.watch(
                                          portalConnectionsBadgeProvider,
                                        ),
                                        label: Text(
                                          '${ref.watch(requestsProvider).list.length}',
                                        ),
                                        child: const GlyphIcon(
                                          AppGlyphs.connections,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                GestureDetector(
                                  onDoubleTap: () => ref
                                      .read(
                                        portalProfilesBadgeProvider.notifier,
                                      )
                                      .toggle(),
                                  child: IconButton(
                                    tooltip: context.appLocalizations.profiles,
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const ProfilesView(),
                                      ),
                                    ),
                                    icon: Badge(
                                      backgroundColor: const Color(0xFF00F5A0),
                                      textColor: const Color(0xFF07110C),
                                      isLabelVisible: ref.watch(
                                        portalProfilesBadgeProvider,
                                      ),
                                      label: Text(
                                        '${ref.watch(profilesProvider).length}',
                                      ),
                                      child: const GlyphIcon(
                                        AppGlyphs.profiles,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: _wideControlsWidth,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ConnectButton(
                                      key: tutorialKeys[TutorialTarget.start],
                                    ),
                                    const SizedBox(height: 12),
                                    const PortalPlanCard(),
                                    const SizedBox(height: _gap),
                                    PortalModeSwitch(
                                      key: tutorialKeys[TutorialTarget.modeSwitch],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 20),
                              Expanded(child: PortalServerList()),
                            ],
                          )
                        else ...[
                          // The portal comes first and the choice comes after it, the
                          // order Happ and Incy taught people: the button you press
                          // before the list you read.
                          _ConnectButton(key: tutorialKeys[TutorialTarget.start]),
                          const SizedBox(height: 12),
                          // Announcement and subscription sit together right under the
                          // button, the way Happ and Incy put plan status next to the
                          // switch: visible, but out of the way of choosing a server.
                          const PortalPlanCard(),
                          const SizedBox(height: _gap),
                          PortalModeSwitch(key: tutorialKeys[TutorialTarget.modeSwitch]),
                          const SizedBox(height: 4),
                          const PortalServerList(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same portal the working screen draws, in its closed state: the start screen
        // is the product's face, not a stretched logo strip.
        LayoutBuilder(
          builder: (context, constraints) {
            final side = (constraints.maxWidth * 0.62).clamp(150.0, 300.0);
            return Center(
              child: PortalGatewayCore(
                isStart: false,
                suspended: false,
                runTime: null,
                size: side,
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          appName,
          textAlign: TextAlign.center,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 24),
        // No "Add profile" gate: the field, the paste key, the file picker, the scanner and
        // its Add button are on the screen from the first launch.
        const AddProfileForm(),
        const SizedBox(height: 40),
        const _GetSubscriptionLink(),
      ],
    );
  }
}

/// The quiet way to get a subscription, under the form.
///
/// It is deliberately small and low-contrast: the screen's job is to take the link a person
/// already has, and only to mention where one comes from.
class _GetSubscriptionLink extends StatelessWidget {
  const _GetSubscriptionLink();

  static const _botUrl = 'https://t.me/portalconnect_bot';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: TextButton(
        onPressed: () => unawaited(
          launchUrl(Uri.parse(_botUrl), mode: LaunchMode.externalApplication),
        ),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          context.appLocalizations.getSubscriptionHere,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// When the portal was switched off, in wall-clock milliseconds. Top-level because the
/// closing iris outlives the widget that started it.
final ValueNotifier<int?> portalClosedAtMs = ValueNotifier<int?>(null);

/// When the portal was switched on. The ignition runs from the press, not from the
/// moment the engine reports a tunnel — the picture leads, the task follows.
final ValueNotifier<int?> portalOpenedAtMs = ValueNotifier<int?>(null);

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({super.key});
  /// The press answers with its own rhythm: opening is a heavier double beat, closing a
  /// softer pair — the hand should feel which way the portal is going.
  void _portalHaptics({required bool starting}) {
    if (starting) {
      HapticFeedback.heavyImpact();
      Future<void>.delayed(
        const Duration(milliseconds: 130),
        HapticFeedback.mediumImpact,
      );
    } else {
      HapticFeedback.mediumImpact();
      Future<void>.delayed(
        const Duration(milliseconds: 150),
        HapticFeedback.lightImpact,
      );
    }
  }

  /// The mark of whatever is carrying traffic right now: the group's own icon when
  /// the panel ships one, its monogram otherwise.
  Widget? _connectedMark(WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    if (groups.isEmpty) return null;
    final current = ref.watch(
      currentProfileProvider.select((profile) => profile?.currentGroupName),
    );
    final group =
        groups.where((g) => g.name == current).firstOrNull ??
        groups.firstWhere(
          (g) => !isBuiltinOutboundName(g.name),
          orElse: () => groups.first,
        );
    // Only a real icon from the panel: a monogram letter inside the portal reads as a
    // stray glyph, not as a server.
    if (group.icon.isEmpty) return null;
    return SizedBox.square(
      dimension: 56,
      child: CommonTargetIcon(
        src: group.icon,
        fallback: const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final runTime = ref.watch(runTimeProvider);
    // Live traffic sets how busy the portal looks: 2 MB/s and above is a full flow.
    final live = ref.watch(portalLiveProvider);
    final rate = (live.up + live.down).toDouble();
    // No connections, no motion: the animation is the wire, not a loop.
    final intensity = live.connections == 0
        ? 0.0
        : (rate / (2 * 1024 * 1024)).clamp(0.08, 1.0);
    final label = suspended
        ? appLocalizations.suspended
        : isStart
        ? appLocalizations.closePortal
        : appLocalizations.openPortal;
    void toggle() => ref.read(commonActionProvider.notifier).toggleRunning();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: RisingHold(
              enabled: system.isAndroid,
              onHeld: () {
                _portalHaptics(starting: !isStart);
                if (isStart) {
                  portalClosedAtMs.value =
                      DateTime.now().millisecondsSinceEpoch;
                } else {
                  portalOpenedAtMs.value =
                      DateTime.now().millisecondsSinceEpoch;
                }
                toggle();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _portalHaptics(starting: !isStart);
                  if (isStart) {
                    portalClosedAtMs.value =
                        DateTime.now().millisecondsSinceEpoch;
                  } else {
                    portalOpenedAtMs.value =
                        DateTime.now().millisecondsSinceEpoch;
                    TutorialBus.fire(TutorialEvent.started);
                  }
                  toggle();
                },
                child: PortalGatewayCore(
                  isStart: isStart,
                  closedAtMs: portalClosedAtMs.value,
                  openedAtMs: portalOpenedAtMs.value,
                  suspended: suspended,
                  runTime: runTime,
                  center: _connectedMark(ref),
                  intensity: intensity,
                  connections: live.connections,
                  rateText: live.connections == 0
                      ? null
                      : context.appLocalizations.speedKilobytes(
                          (rate / 1024).toStringAsFixed(0),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: AppTextStyle.headline.of(context, emphasized: true)),
      ],
    );
  }
}
