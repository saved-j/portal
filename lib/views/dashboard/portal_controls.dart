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

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final group = groups
        .where((item) => item.hidden == false)
        .where((item) {
      final name = item.name.toUpperCase();
      return name != 'DIRECT' && name != 'REJECT';
    }).firstOrNull;
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
            Text(
              group.name,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
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
            selected: group.now == proxy.name,
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
  });

  final Group group;
  final Proxy proxy;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delay = ref.watch(delayProvider(proxyName: proxy.name));
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      selected: selected,
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
      onTap: () => ref.read(proxiesActionProvider.notifier).changeProxy(
            groupName: group.name,
            proxyName: proxy.name,
          ),
    );
  }
}
