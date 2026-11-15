import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:material_ui/material_ui.dart';

/// The two lights on a subscription row.
///
/// A panel decides what to serve per client, so one link can carry the engine's YAML, the
/// second core's node list, both, or neither. Each light is a fact: green when the format
/// was downloaded and parsed, dim when this link does not offer it.
class SubscriptionFormatsLights extends StatefulWidget {
  const SubscriptionFormatsLights({super.key, required this.profile});

  final Profile profile;

  @override
  State<SubscriptionFormatsLights> createState() =>
      _SubscriptionFormatsLightsState();
}

class _SubscriptionFormatsLightsState extends State<SubscriptionFormatsLights> {
  bool _mihomo = false;
  bool _xray = false;
  bool _loaded = false;

  /// The engine's format is the profile file itself; a save only lands when it parsed.
  Future<bool> _hasEngineFormat() async {
    try {
      final file = await widget.profile.file;
      return await file.exists() && await file.length() > 32;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SubscriptionFormatsLights oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.lastUpdateDate != widget.profile.lastUpdateDate) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.profile.hasXrayFormat(),
      _hasEngineFormat(),
    ]);
    if (!mounted) return;
    setState(() {
      _xray = results[0];
      _mihomo = results[1];
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile.type != ProfileType.url) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Light(
          on: _mihomo,
          label: 'M',
          tooltip: _mihomo
              ? 'Mihomo / призрак: формат есть'
              : 'Mihomo / призрак: формат не отдаётся',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        _Light(
          on: _loaded && _xray,
          label: 'X',
          tooltip: _xray
              ? 'Xray: формат есть'
              : 'Xray: формат не отдаётся',
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.on,
    required this.label,
    required this.tooltip,
    required this.color,
  });

  final bool on;
  final String label;
  final String tooltip;
  final Color color;

  /// The green the app already uses for a live portal, so the lights read as the same
  /// language rather than a new palette.
  static const _live = Color(0xFF00F5A0);
  static const _liveLight = Color(0xFF0E9F6E);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = isDark ? _live : _liveLight;
    final dot = on ? active : Theme.of(context).colorScheme.outlineVariant;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? active.withValues(alpha: 0.18) : Colors.transparent,
          border: Border.all(
            color: on ? active.withValues(alpha: 0.7) : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: on ? dot : color.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
