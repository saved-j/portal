import 'package:dio/dio.dart';
import 'package:fl_clash/common/file_logger.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';

String compactError(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    return statusCode != null
        ? 'DioException(${error.type.name}, HTTP $statusCode)'
        : 'DioException(${error.type.name})';
  }
  return error.toString();
}

/// The URL query is the account: panels put the token there and nothing else of interest,
/// so the whole query goes rather than a best guess at which key is the secret one.
final _urlQuery = RegExp(r'(\bhttps?://[^\s?#]+)\?[^\s#]*');

final _uuid = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
  caseSensitive: false,
);

/// `token=…`, `uuid: "…"`, `password = …` and the names panels use for the same thing.
///
/// The name is kept so the line still says what was removed, which is what makes a redacted
/// log readable in the first place.
final _secretAssignment = RegExp(
  r'(token|uuid|password|passwd|pwd|secret|apikey|authkey|authtoken|access[_-]token'
  r'|api[_-]key|key|auth)'
  r'("?\s*[=:]\s*"?)([^\s,;}"&]+)',
  caseSensitive: false,
);

/// The single redaction boundary of the app: everything printed passes through here.
///
/// A log is something people read, paste into a chat and send to a support account, so it
/// must not carry credentials. The wash happens at the printer instead of at every call
/// site, because a call site added tomorrow will not remember. It never throws: a line is
/// worth losing, the app is not, and a redaction that failed loudly would be worse than the
/// leak it was guarding.
String redactLogText(String text) {
  if (text.isEmpty) return text;
  try {
    return text
        .replaceAllMapped(_urlQuery, (match) => '${match.group(1)}?[redacted]')
        .replaceAllMapped(_uuid, (_) => '[uuid]')
        .replaceAllMapped(
          _secretAssignment,
          (match) => '${match.group(1)}${match.group(2)}[redacted]',
        );
  } catch (_) {
    return '[line withheld: redaction failed]';
  }
}

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel logLevel = LogLevel.info}) {
    // Nothing here may be fatal: the printer is called from core callbacks and from timers,
    // where a throw has no caller left to catch it.
    try {
      final payload = '[APP] ${redactLogText('$text')}';
      debugPrint(payload);
      final log = Log.app(payload).copyWith(logLevel: logLevel);
      if (!globalState.isAttach) {
        fileLogger.write(log);
        return;
      }
      globalState.container.read(logsProvider.notifier).add(log);
    } catch (error) {
      // The sink is gone, not the app.
      debugPrint('[APP] log dropped: ${error.runtimeType}');
    }
  }
}

final commonPrint = CommonPrint();
