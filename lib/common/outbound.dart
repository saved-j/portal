/// The engine ships built-in outbounds whose names are decorated by the panel
/// (`DIRECT 🇷🇺`, `DIRECT `, `Reject`). DIRECT and REJECT are routing targets, not
/// portals: picking one by hand is how a user silently ends up without a tunnel.
///
/// One predicate for the whole app — state layer, chip filter and the portal's own
/// fallback must agree, or a built-in reappears somewhere it was already banned.
bool isBuiltinOutboundName(String name) {
  final word = name.trim().split(RegExp(r'[\s_\-|·/]+')).first.toUpperCase();
  return word == 'DIRECT' || word == 'REJECT';
}
