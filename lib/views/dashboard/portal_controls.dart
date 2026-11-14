import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Material 3 mode switch: the two modes Portal Connect actually has, with the
/// engine's own names kept out of the UI.
class PortalModeSwitch extends ConsumerWidget {
  const PortalModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final modes = ref.watch(availableModesProvider);
    if (modes.length < 2) return const SizedBox.shrink();
    return SegmentedButton<Mode>(
      segments: [
        for (final item in modes)
          ButtonSegment<Mode>(
            value: item,
            label: Text(item.label),
          ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        final next = selection.firstOrNull;
        if (next == null || next == mode) return;
        ref.read(setupActionProvider.notifier).pickMode(next);
      },
    );
  }
}

/// The working screen's server list: name on the left, delay on the right, a
/// marker on the row that is actually in use, and a sort switch between ping and
/// alphabetical order.
class PortalServerList extends ConsumerStatefulWidget {
  const PortalServerList({super.key});

  @override
  ConsumerState<PortalServerList> createState() => _PortalServerListState();
}

enum _SortOrder { ping, alphabet }

class _PortalServerListState extends ConsumerState<PortalServerList> {
  var _order = _SortOrder.ping;

  /// The row the user picked. Before the portal is open the choice is only
  /// visual: it is applied the moment the tunnel comes up.
  String? _picked;

  /// Which group the strip shows; the list follows it.
  String? _groupName;

  @override
  Widget build(BuildContext context) {
    final allGroups = ref.watch(groupsProvider);
    final groups = allGroups.where((item) {
      if (item.hidden == true) return false;
      final name = item.name.toUpperCase();
      return name != 'DIRECT' && name != 'REJECT';
    }).toList();
    final group = groups
            .where((item) => item.name == _groupName)
            .firstOrNull ??
        groups.firstOrNull;
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.appLocalizations.proxyGroupEmpty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final theme = Theme.of(context);
    final running = ref.watch(runTimeProvider) != null;
    if (running && _picked != null && group.now != _picked) {
      final pending = _picked!;
      _picked = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(proxiesActionProvider.notifier).changeProxy(
              groupName: group.name,
              proxyName: pending,
            );
      });
    }
    final selectedName = _picked ?? group.now;
    final members = [...group.all];
    if (_order == _SortOrder.alphabet) {
      members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      int rank(Proxy p) => ref.watch(delayProvider(proxyName: p.name)) ?? 1 << 30;
      members.sort((a, b) => rank(a).compareTo(rank(b)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (groups.length <= 1)
              Text(
                group.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in groups)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(item.name),
                            selected: item.name == group.name,
                            onSelected: (_) =>
                                setState(() => _groupName = item.name),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            IconButton(
              tooltip: context.appLocalizations.delayTest,
              onPressed: () => ref
                  .read(proxiesActionProvider.notifier)
                  .delayTest(group.all),
              icon: const GlyphIcon(AppGlyphs.bolt, size: 18),
            ),
            IconButton(
              tooltip: '${context.appLocalizations.sort}: '
                  '${_order == _SortOrder.ping ? 'пинг' : 'A-Z'}',
              onPressed: () => setState(() {
                _order = _order == _SortOrder.ping
                    ? _SortOrder.alphabet
                    : _SortOrder.ping;
              }),
              icon: GlyphIcon(
                _order == _SortOrder.ping ? AppGlyphs.sort : AppGlyphs.proxies,
                size: 18,
              ),
            ),
          ],
        ),
        for (final proxy in members)
          _ServerRow(
            group: group,
            proxy: proxy,
            selected: selectedName == proxy.name,
            onPick: (name) => setState(() => _picked = name),
          ),
      ],
    );
  }
}

class _ServerRow extends ConsumerWidget {
  const _ServerRow({
    required this.group,
    required this.proxy,
    required this.selected,
    required this.onPick,
  });

  final Group group;
  final Proxy proxy;
  final bool selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delay = ref.watch(delayProvider(proxyName: proxy.name));
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      selected: selected,
      // Colour, not just the marker: a tinted row is what the eye finds first.
      tileColor: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
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
          color: selected ? theme.colorScheme.primary : null,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      trailing: Text(
        delay == null ? '—' : '$delay ms',
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
      onTap: () {
        onPick(proxy.name);
        ref.read(proxiesActionProvider.notifier).changeProxy(
              groupName: group.name,
              proxyName: proxy.name,
            );
      },
    );
  }
}


/// Plan status and the provider's announcement in one card: the thing you glance
/// at, not the thing you operate. Kept deliberately small so the server list stays
/// the centre of the screen.
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
    String gb(int bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';

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
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (used != null)
                  Text(
                    '$used/$total'.replaceFirst('$used', gb(used)).replaceFirst('$total', gb(total)),
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
