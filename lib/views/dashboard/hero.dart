import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/views/connection/connection_feeds.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'portal_controls.dart';
import 'portal_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';
import 'widgets/card.dart';
import 'widgets/widgets.dart';
import 'package:fl_clash/common/outbound.dart';

const heroMaxWidth = 520.0;

const _logoSize = 96.0;
const _flagSize = 52.0;
const _connectHeight = 56.0;
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: heroMaxWidth),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: padding.copyWith(bottom: _gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: context.appLocalizations.tools,
                          // Pushed, not page-switched: a page index has no history, so
                          // Back walked out of the app instead of returning here.
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ToolsView(),
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
                          tooltip: context.appLocalizations.accessControl,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AccessView(),
                            ),
                          ),
                          icon: const GlyphIcon(
                            AppGlyphs.appsList,
                            size: 22,
                          ),
                        ),
                        // No app icon and no app name here: the screen shows the
                        // service the subscription belongs to, not the product that
                        // opened the door.
                        Expanded(
                          child: Center(
                            child: EmojiText(
                              headers.serviceName ?? 'portal-connect',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.title3.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onDoubleTap: () => ref
                              .read(portalConnectionsBadgeProvider.notifier)
                              .toggle(),
                          child: IconButton(
                            tooltip: context.appLocalizations.connections,
                          // The connections page is not in the phone navigation any
                          // more, so switching the page index did nothing: push it.
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ConnectionFeedsView(),
                              ),
                            ),
                            icon: Badge(
                              isLabelVisible:
                                  ref.watch(portalConnectionsBadgeProvider),
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
                              .read(portalProfilesBadgeProvider.notifier)
                              .toggle(),
                          child: IconButton(
                            tooltip: context.appLocalizations.profiles,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ProfilesView(),
                              ),
                            ),
                            icon: Badge(
                              isLabelVisible:
                                  ref.watch(portalProfilesBadgeProvider),
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
                    const SizedBox(height: 8),
                    // The portal comes first and the choice comes after it, the
                    // order Happ and Incy taught people: the button you press
                    // before the list you read.
                    const _ConnectButton(),
                    const SizedBox(height: 12),
                    // Announcement and subscription sit together right under the
                    // button, the way Happ and Incy put plan status next to the
                    // switch: visible, but out of the way of choosing a server.
                    const PortalPlanCard(),
                    const SizedBox(height: _gap),
                    const PortalModeSwitch(),
                    const SizedBox(height: 4),
                    const PortalServerList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero();

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ServiceLogo(),
        const SizedBox(height: 14),
        Text(
          appName,
          textAlign: TextAlign.center,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: _connectHeight,
          child: AddProfileMenu(
            builder: (open) => FilledButton.icon(
              onPressed: open,
              icon: const GlyphIcon(AppGlyphs.add, fill: 1),
              label: Text(appLocalizations.addProfile),
            ),
          ),
        ),
      ],
    );
  }
}

/// The panel's logo, png or svg, else the app's own icon.
class _ServiceLogo extends ConsumerWidget {
  const _ServiceLogo({
    this.url,
    this.size = _logoSize,
    this.radius = AppRadius.xxl,
  });

  final String? url;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = this.url;
    final fallback = Image.asset(
      'assets/images/icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    final path = url == null
        ? null
        : ref.watch(panelLogoPathProvider(url)).value;
    final Widget logo = url == null || path == null
        ? fallback
        : url.toLowerCase().endsWith('.svg')
        ? SvgPicture.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => fallback,
          )
        : Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return Center(
      child: ClipRSuperellipse(
        borderRadius: radius,
        child: SizedBox.square(dimension: size, child: logo),
      ),
    );
  }
}

/// The selection the panel's group, or the first group with one, is on,
/// with its flag, the exit address while running and its delay; a tap
/// opens the picker.
/// countries.
class _FlagBadge extends StatelessWidget {
  const _FlagBadge({
    required this.code,
    required this.count,
    required this.active,
    required this.checking,
    required this.onRefresh,
  });

  final String? code;
  final int count;
  final bool active;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return SizedBox.square(
      dimension: _flagSize + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: CountryBadge(
              countryCode: code,
              size: _flagSize,
              active: active,
              checking: checking,
              onRefresh: onRefresh,
            ),
          ),
          if (count > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: ShapeDecoration(
                  color: colorScheme.primary,
                  shape: AppShape.full.copyWith(
                    side: BorderSide(color: colors.card, width: 1.5),
                  ),
                ),
                child: Text(
                  '+$count',
                  style: DashboardText.figure(
                    context,
                    AppTextStyle.caption2,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Four bars, as a phone shows its signal, lit by how low the delay is.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.delay});

  static const _heights = [8.0, 12.0, 16.0, 20.0];

  final int? delay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dim = colorScheme.onSurfaceVariant.withValues(alpha: 0.25);
    final delay = this.delay;
    final level = switch (delay) {
      null || 0 => 0,
      < 0 => 0,
      < 150 => 4,
      < 300 => 3,
      < 600 => 2,
      _ => 1,
    };
    final lit = colorScheme.delayColor(delay) ?? dim;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 3,
      children: [
        for (final (index, height) in _heights.indexed)
          Container(
            width: 4,
            height: height,
            decoration: ShapeDecoration(
              color: index < level ? lit : dim,
              shape: AppShape.full,
            ),
          ),
      ],
    );
  }
}

/// Full width: filled with a play glyph while stopped, easing into an
/// outline in the primary color with a stop glyph and the run time while
/// running.
class _ConnectButton extends ConsumerWidget {

  /// The mark of whatever is carrying traffic right now: the group's own icon when
  /// the panel ships one, its monogram otherwise.
  Widget? _connectedMark(WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    if (groups.isEmpty) return null;
    final current = ref.watch(
      currentProfileProvider.select((profile) => profile?.currentGroupName),
    );
    final group = groups.where((g) => g.name == current).firstOrNull ??
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
  const _ConnectButton();

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
              onHeld: toggle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: PortalGatewayCore(
                  isStart: isStart,
                  suspended: suspended,
                  runTime: runTime,
                  center: _connectedMark(ref),
                  intensity: intensity,
                  connections: live.connections,
                  rateText: live.connections == 0
                      ? null
                      : '${(rate / 1024).toStringAsFixed(0)} КБ/с',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: AppTextStyle.headline.of(context, emphasized: true),
        ),
      ],
    );
  }
}
