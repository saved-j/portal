/// Anything that goes into a log is a string somebody else can read.
///
/// The app's logs land in an external-files directory (adb-readable by design: that is how a
/// refused start on a release build can be diagnosed at all), so a URL written whole is a
/// subscription's token written whole. A URL is logged for one reason — which host failed —
/// and that reason survives being cut down to its host and path.
library;

/// [url] with its credentials and query removed: `https://host/path`.
///
/// A subscription URL carries its key in the path or the query depending on the panel, so both
/// go; the host is what a person reading the log needs, and what is left cannot be used to
/// fetch anything.
String redactUrl(Object? url) {
  final text = '${url ?? ''}'.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    // Not a URL at all. Nothing about it is known, so nothing of it is repeated.
    return '<unparsed-url>';
  }
  final host = uri.host;
  if (host.isEmpty) return '<unparsed-url>';
  // No userinfo (it is `user:pass@`), no query, no fragment: a panel may put the key in any.
  return '${uri.scheme}://$host';
}
