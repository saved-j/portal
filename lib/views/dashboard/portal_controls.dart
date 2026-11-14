import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// How the server list is ordered; the switch sits next to the mode control.
enum PortalSort { ping, alphabet }

class PortalSortNotifier extends Notifier<PortalSort> {
  @override
  PortalSort build() => PortalSort.alphabet;

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

class PortalFiltersNotifier extends Notifier<({Set<String> hidden, List<String> order})> {
  @override
  ({Set<String> hidden, List<String> order}) build() =>
      (hidden: <String>{}, order: const <String>[]);

  void toggle(String name) {
    final hidden = {...state.hidden};
    if (!hidden.remove(name)) hidden.add(name);
    state = (hidden: hidden, order: state.order);
  }

  void reorder(List<String> order) =>
      state = (hidden: state.hidden, order: order);

  void reset() => state = (hidden: <String>{}, order: const <String>[]);
}

final portalFiltersProvider = NotifierProvider<PortalFiltersNotifier,
    ({Set<String> hidden, List<String> order})>(PortalFiltersNotifier.new);

List<Group> portalGroups(List<Group> all) => [
      for (final item in all)
        if (item.hidden != true &&
            !{'DIRECT', 'REJECT'}.contains(item.name.toUpperCase()))
          item,
    ];

/// Same list, after the user's own order and hidden set.
List<Group> portalVisibleGroups(List<Group> all, Set<String> hidden, List<String> order) {
  final visible = [
    for (final group in portalGroups(all))
      if (!hidden.contains(group.name)) group,
  ];
  if (order.isEmpty) return visible;
  visible.sort((a, b) {
    final ia = order.indexOf(a.name);
    final ib = order.indexOf(b.name);
    if (ia == -1 && ib == -1) return 0;
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return visible;
}

/// Mode control with the two list controls beside it: sorting and the delay test.
class PortalModeSwitch extends ConsumerWidget {
  const PortalModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final modes = ref.watch(availableModesProvider);
    final running = ref.watch(runTimeProvider) != null;
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(
      ref.watch(groupsProvider),
      filters.hidden,
      filters.order,
    );
    final groupName = ref.watch(portalGroupProvider);
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull;
    final sort = ref.watch(portalSortProvider);
    if (modes.length < 2) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (final item in modes)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _ModeButton(
                      label: item.label,
                      selected: item == mode,
                      // The network mode carries the hidden tricks: a double tap
                      // opens the filter editor, a long press the proxies dashboard.
                      onDoubleTap: item == Mode.rule
                          ? () => showPortalFilterEditor(context)
                          : null,
                      onLongPress: item == Mode.rule
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProxiesView(),
                                ),
                              )
                          : null,
                      onTap: () {
                        if (item == mode) return;
                        ref.read(setupActionProvider.notifier).pickMode(item);
                      },
                    ),
                  ),
                ),
            ],
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
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(
      ref.watch(groupsProvider),
      filters.hidden,
      filters.order,
    );
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
/// can be dragged and hide themselves once that direction is exhausted. A double tap
/// reveals an icon on every filter — a hidden trick, not a visible control.
class _GroupStrip extends ConsumerStatefulWidget {
  const _GroupStrip();

  @override
  ConsumerState<_GroupStrip> createState() => _GroupStripState();
}

class _GroupStripState extends ConsumerState<_GroupStrip> {
  final _controller = ScrollController();
  var _canBack = false;
  var _canForward = false;
  /// 0 — текст, 1 — иконка и текст, 2 — только иконка.
  var _display = 0;

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
    final allGroups = ref.watch(groupsProvider);
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(allGroups, filters.hidden, filters.order);
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
          child: GestureDetector(
            onDoubleTap: () => setState(() => _display = (_display + 1) % 3),
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
                          showCheckmark: false,
                          // No avatar anywhere: an avatar plus an empty or short label
                          // never centres. The mark and the name are one centred row.
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_display >= 1)
                                SizedBox.square(
                                  dimension: 16,
                                  child: CommonTargetIcon(
                                    src: item.icon,
                                    fallback: GroupMonogram(item.name),
                                  ),
                                ),
                              if (_display == 1) const SizedBox(width: 6),
                              if (_display != 2) Text(item.name),
                            ],
                          ),
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
  if (value <= 399) return _delayFast;
  if (value <= 1499) return _delaySlow;
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
    // A selector row says nothing useful without the node behind it: 'Auto' alone
    // hides which server carries the traffic and what it costs.
    final allGroups = ref.watch(groupsProvider);
    final byName = {for (final item in allGroups) item.name: item};
    String? resolve(String? name, [int depth = 0]) {
      if (name == null || depth > 6) return null;
      final next = byName[name];
      if (next == null) return name;
      return resolve(next.now, depth + 1);
    }

    final node = byName.containsKey(proxy.name) ? resolve(proxy.name) : null;
    final delay = ref.watch(delayProvider(proxyName: node ?? proxy.name));
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
        node == null || node == proxy.name
            ? proxy.name
            : '${proxy.name} · $node',
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


/// One mode button. Looks like a Material 3 segment, but keeps its own gestures so
/// the network mode can carry a hidden double tap and long press.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    );
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reorder and hide the group filters. A sheet, not a page: it edits a row of chips.
Future<void> showPortalFilterEditor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _FilterEditorSheet(),
  );
}

class _FilterEditorSheet extends ConsumerWidget {
  const _FilterEditorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalGroups(ref.watch(groupsProvider));
    final order = filters.order.isEmpty
        ? [for (final group in groups) group.name]
        : [
            ...filters.order.where((name) => groups.any((g) => g.name == name)),
            ...groups
                .map((g) => g.name)
                .where((name) => !filters.order.contains(name)),
          ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Фильтры', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Перетащите, чтобы изменить порядок. Выключите, чтобы скрыть.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                onReorder: (from, to) {
                  final next = [...order];
                  if (to > from) to -= 1;
                  next.insert(to, next.removeAt(from));
                  ref.read(portalFiltersProvider.notifier).reorder(next);
                },
                children: [
                  for (final (index, name) in order.indexed)
                    ListTile(
                      key: ValueKey(name),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The handle people already know how to drag.
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: GlyphIcon(AppGlyphs.dragHandle, size: 20),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 20,
                            child: CommonTargetIcon(
                              src: groups
                                      .where((g) => g.name == name)
                                      .firstOrNull
                                      ?.icon ??
                                  '',
                              fallback: GroupMonogram(name),
                            ),
                          ),
                        ],
                      ),
                      title: Text(name),
                      trailing: Switch(
                        value: !filters.hidden.contains(name),
                        onChanged: (_) => ref
                            .read(portalFiltersProvider.notifier)
                            .toggle(name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
