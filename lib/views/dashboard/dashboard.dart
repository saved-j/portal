import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit.dart';
import 'hero.dart';
import 'layout.dart';
import 'style.dart';
import 'wide.dart';
import 'widget_registry.dart';
import 'widgets/core_status_button.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.platform});

  /// The host's platform when null.
  final SupportPlatform? platform;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  var _editing = false;
  var _wide = false;

  /// What editing started from, kept across resizes until the cards are picked.
  List<DashboardWidget>? _editedArrangement;
  final _cardKeys = <DashboardWidget, GlobalKey>{};

  void _setEditing(bool editing, SupportPlatform platform) {
    final chosen = ref.read(appSettingProvider).dashboardWidgetsChosen;
    setState(() {
      _editing = editing;
      _editedArrangement = editing && _wide && !chosen
          ? wideDashboardWidgetsOf(platform)
          : null;
    });
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final hero = ref.watch(
      themeSettingProvider.select(
        (state) => state.style == ThemeStyle.enhanced,
      ),
    );
    final mode = hero
        ? ref.watch(patchClashConfigProvider.select((state) => state.mode))
        : null;
    final editable = !hero && !ref.watch(widgetEditingDeniedProvider);
    final chosen = ref.watch(
      appSettingProvider.select((state) => state.dashboardWidgetsChosen),
    );
    if (!editable) {
      _editing = false;
    }
    final editing = _editing;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    if (hero) {
      // No app bar at all on the working screen: an empty bar still reserves its
      // height and reads as a hole above the portal.
      return Material(
        color: DashboardColors.of(context).page,
        child: SafeArea(
          bottom: false,
          child: DashboardDensityScope(
            density: DashboardDensity.mobile,
            scale: scale,
            child: const HeroDashboard(),
          ),
        ),
      );
    }
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      // The hero screen carries its own header: a title bar with the page name,
      // a mode toggle and the developer core-reset button is noise there.
      title: editing
          ? appLocalizations.editDashboard
          : (hero ? '' : appLocalizations.dashboard),
      actions: [if (!editing && !hero) const CoreStatusButton()],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false, platform),
            )
          : null,
      iconActions: [
        // The original dashboard has no bottom island any more, and the island was where
        // settings lived. A gear at the right edge of the bar, beside the core status and the
        // mode toggle, keeps the way in where someone used to ClashX expects to find it.
        if (!editing && !hero)
          IconButtonData(
            glyph: AppGlyphs.settings,
            tooltip: appLocalizations.tools,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ToolsView()),
            ),
          ),
        if (mode != null && !hero && ref.watch(globalModeAllowedProvider))
          IconButtonData(
            glyph: mode == Mode.global ? AppGlyphs.proxies : AppGlyphs.rules,
            tooltip:
                '${appLocalizations.outboundMode}: ${mode.label}',
            onPressed: () => ref
                .read(setupActionProvider.notifier)
                .pickMode(mode == Mode.global ? Mode.rule : Mode.global),
          ),
        if (editable && !editing)
          IconButtonData(
            glyph: AppGlyphs.edit,
            tooltip: appLocalizations.editDashboard,
            onPressed: () => _setEditing(true, platform),
          ),
      ],
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          // A phone turned on its side is still a phone: the shorter side of the *layout*
          // grows in landscape, which is what used to fool this into the wide layout. The
          // density is decided by the physical shorter side instead, so the stacked cards
          // stay stacked and fill the wide window — and a tablet or a desktop window, whose
          // shorter side is already large, gets the columns it has room for.
          // `MediaQuery.size` is already in logical points — dividing by the device pixel
          // ratio again turned a phone's 389 pt into 250 and nothing was ever wide.
          final view = MediaQuery.sizeOf(context);
          final shortestSide = math.min(view.width, view.height);
          final layout = DashboardDensity.of(room, shortest: shortestSide);
          if (hero) {
            return DashboardDensityScope(
              density: DashboardDensity.mobile,
              scale: scale,
              child: const HeroDashboard(),
            );
          }
          _wide = layout.isDesktop;
          final arranged = editing
              ? (chosen ? null : _editedArrangement)
              : layout.isDesktop && !chosen
              ? wideDashboardWidgetsOf(platform)
              : null;
          if (layout.isDesktop && !editing) {
            return DashboardDensityScope(
              density: layout,
              scale: scale,
              child: _WideCards(
                platform: platform,
                arranged: arranged,
                columns: dashboardColumnsOf(room.width),
                gap: gap,
              ),
            );
          }
          return DashboardDensityScope(
            density: DashboardDensity.mobile,
            scale: scale,
            child: _MobileDashboard(
              platform: platform,
              arranged: arranged,
              gap: gap,
              editing: editing,
              cardKeyOf: _cardKeyOf,
              onDone: () => _setEditing(false, platform),
            ),
          );
        },
      ),
    );
  }
}

class _WideCards extends ConsumerWidget {
  const _WideCards({
    required this.platform,
    required this.arranged,
    required this.columns,
    required this.gap,
  });

  final SupportPlatform platform;
  final List<DashboardWidget>? arranged;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DashboardWidget> saved =
        arranged ??
        ref.watch(
          dashboardStateProvider.select((state) => state.dashboardWidgets),
        );
    final announcement = ref.watch(announcementProvider) != null;
    return WideDashboard(
      cards: withFixedCards([
        for (final widget in saved)
          if (widget.platforms.contains(platform)) widget,
      ], announcement: announcement),
      columns: columns,
      gap: gap,
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.platform,
    required this.arranged,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;

  /// The wide arrangement a wide window edits until someone picks the cards.
  final List<DashboardWidget>? arranged;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DashboardWidget> saved =
        arranged ??
        ref.watch(
          dashboardStateProvider.select((state) => state.dashboardWidgets),
        );
    final announcement = ref.watch(announcementProvider) != null;
    final top = MediaQuery.paddingOf(context).top + 4;
    final bottom = 16 + context.bottomInset;
    return CustomScrollView(
      // A viewport per card lays them all out and holds the scroll end still.
      scrollCacheExtent: editing
          ? ScrollCacheExtent.viewport(DashboardWidget.values.length.toDouble())
          : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = dashboardMobileSideOf(constraints.crossAxisExtent);
            final widgets = withFixedCards([
              for (final widget in saved)
                if (widget.platforms.contains(platform)) widget,
            ], announcement: announcement);
            if (editing) {
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              // A lazy list estimates the cards it has not laid out from the
              // ones it has; cards this uneven move the scroll end as it goes.
              sliver: SliverToBoxAdapter(
                child: Column(
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      RepaintBoundary(
                        key: cardKeyOf(widget),
                        child: widget.card,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
