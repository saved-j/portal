import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// How the server list is ordered; the switch sits next to the mode control.
enum PortalSort { ping, alphabet }

class PortalSortNotifier extends Notifier<PortalSort> {
  @override
  PortalSort build() => PortalSort.ping;

  void toggle() =>
      state = state == PortalSort.ping ? PortalSort.alphabet : PortalSort.ping;
}

final portalSortProvider =
    NotifierProvider<PortalSortNotifier, PortalSort>(PortalSortNotifier.new);

/// Which group the strip shows. Null means "the first one the panel offers",
/// which survives subscription updates that reorder groups.
class PortalGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pick(String? name) => state = name;
}

final portalGroupProvider =
    NotifierProvider<PortalGroupNotifier, String?>(PortalGroupNotifier.new);

List<Group> portalGroups(List<Group> all) => [
      for (final item in all)
        if (item.hidden != true &&
            !{'DIRECT', 'REJECT'}.contains(item.name.toUpperCase()))
          item,
    ];

/// Mode control with the two list controls beside it: sorting and the delay test.
class PortalModeSwitch extends ConsumerWidget {
  const PortalModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final modes = ref.watch(availableModesProvider);
    final running = ref.watch(runTimeProvider) != null;
    final groups = portalGroups(ref.watch(groupsProvider));
    final groupName = ref.watch(portalGroupProvider);
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull;
    final sort = ref.watch(portalSortProvider);
    if (modes.length < 2) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<Mode>(
            segments: [
              for (final item in modes)
                ButtonSegment<Mode>(value: item, label: Text(item.label)),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              final next = selection.firstOrNull;
              if (next == null || next == mode) return;
              ref.read(setupActionProvider.notifier).pickMode(next);
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: sort == PortalSort.ping ? 'Сортировка: пинг' : 'Сортировка: A-Z',
          onPressed: () => ref.read(portalSortProvider.notifier).toggle(),
          icon: GlyphIcon(
            sort == PortalSort.ping ? AppGlyphs.sort : AppGlyphs.textShort,
            size: 18,
          ),
        ),
        IconButton(
          tooltip: running
              ? context.appLocalizations.delayTest
              : context.appLocalizations.openPortal,
          onPressed: running && group != null
              ? () => ref
                  .read(proxiesActionProvider.notifier)
                  .delayTest(group.all)
              : null,
          icon: GlyphIcon(AppGlyphs.bolt, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The working screen's server list: a group strip with arrows (network mode only),
/// a tinted row for the chosen server, name left and delay right.
class PortalServerList extends ConsumerWidget {
  const PortalServerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final simple = mode == Mode.global;
    final groups = portalGroups(ref.watch(groupsProvider));
    final groupName = ref.watch(portalGroupProvider);
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull;
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.appLocalizations.proxyGroupEmpty,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final sort = ref.watch(portalSortProvider);
    final members = [
      for (final proxy in group.all)
        if (!{'DIRECT', 'REJECT'}.contains(proxy.name.toUpperCase())) proxy,
    ];
    if (sort == PortalSort.alphabet) {
      members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      int rank(Proxy p) {
        final value = ref.watch(delayProvider(proxyName: p.name));
        // -1 is mihomo's timeout marker, not a fast server.
        return value == null || value <= 0 ? 1 << 30 : value;
      }
      members.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!simple && groups.length > 1) const _GroupStrip(),
        if (!simple && groups.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              group.name,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final proxy in members)
          _ServerRow(group: group, proxy: proxy, selected: group.now == proxy.name),
      ],
    );
  }
}

/// Horizontal group filter. The chevrons are hints, not buttons: they say the strip
/// can be dragged and hide themselves once that direction is exhausted.
class _GroupStrip extends ConsumerStatefulWidget {
  const _GroupStrip();

  @override
  ConsumerState<_GroupStrip> createState() => _GroupStripState();
}

class _GroupStripState extends ConsumerState<_GroupStrip> {
  final _controller = ScrollController();
  var _canBack = false;
  var _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncEdges);
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = portalGroups(ref.watch(groupsProvider));
    final active = ref.watch(portalGroupProvider) ?? groups.firstOrNull?.name;
    final hint = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: _canBack
              ? GlyphIcon(AppGlyphs.chevronBack, size: 14, color: hint)
              : null,
        ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _syncEdges();
              return false;
            },
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in groups)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(item.name),
                        selected: item.name == active,
                        onSelected: (_) => ref
                            .read(portalGroupProvider.notifier)
                            .pick(item.name),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 18,
          child: _canForward
              ? GlyphIcon(AppGlyphs.chevronForward, size: 14, color: hint)
              : null,
        ),
      ],
    );
  }
}

/// The legacy palette's three traffic lights: fast, tolerable, bad.
const _delayFast = Color(0xFF00F5A0);
const _delaySlow = Color(0xFFFFC107);
const _delayBad = Color(0xFFFF4B6E);

Color _delayColor(int? value) {
  if (value == null) return const Color(0xFF7C8699);
  if (value <= 0) return _delayBad; // timeout
  if (value <= 120) return _delayFast;
  if (value <= 350) return _delaySlow;
  return _delayBad;
}

String _delayText(int? value) {
  if (value == null) return '—';
  if (value <= 0) return 'таймаут';
  return '$value ms';
}

class _ServerRow extends ConsumerWidget {
  const _ServerRow({
    required this.group,
    required this.proxy,
    required this.selected,
  });

  final Group group;
  final Proxy proxy;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delay = ref.watch(delayProvider(proxyName: proxy.name));
    final color =
        selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      selected: selected,
      tileColor: selected ? theme.colorScheme.primaryContainer : null,
      selectedTileColor: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: GlyphIcon(
        selected ? AppGlyphs.check : AppGlyphs.proxies,
        size: 20,
        color: color,
      ),
      title: Text(
        proxy.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: selected ? theme.colorScheme.onPrimaryContainer : null,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      trailing: Text(
        _delayText(delay),
        style: theme.textTheme.labelMedium?.copyWith(
          color: _delayColor(delay),
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => ref.read(proxiesActionProvider.notifier).changeProxy(
            groupName: group.name,
            proxyName: proxy.name,
          ),
    );
  }
}

/// Plan status and the provider's announcement in one card.
class PortalPlanCard extends ConsumerWidget {
  const PortalPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider);
    final announcement = ref.watch(announcementProvider);
    final info = profile?.subscriptionInfo;
    final name = profile?.headers.serviceName ?? profile?.label ?? '';
    final used = info == null ? null : info.upload + info.download;
    final total = info?.total ?? 0;
    final expire = info?.expire ?? 0;
    final daysLeft = expire > 0
        ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
            .difference(DateTime.now())
            .inDays
        : null;
    String gb(int bytes) =>
        '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (used != null && total > 0)
                  Text(
                    '${gb(used)} / ${gb(total)}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                if (daysLeft != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '$daysLeft д',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ],
            ),
            if (announcement != null && announcement.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Text(
                announcement,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
