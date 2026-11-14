import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
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

/// The working screen's server list: name on the left, delay on the right, one
/// tap to make it the outbound of the group in charge.
class PortalServerList extends ConsumerWidget {
  const PortalServerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(currentGroupsStateProvider).value;
    final group = groups.firstOrNull;
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
    final members = group.all;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final proxy = members[index];
        final selected = group.now == proxy.name;
        final delay = ref.watch(delayProvider(proxyName: proxy.name));
        return ListTile(
          dense: true,
          selected: selected,
          leading: GlyphIcon(
            AppGlyphs.proxies,
            size: 20,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(proxy.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(
            delay == null ? '—' : '$delay ms',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => ref.read(proxiesActionProvider.notifier).changeProxy(
            groupName: group.name,
            proxyName: proxy.name,
          ),
        );
      },
    );
  }
}
