import 'package:fl_clash/common/redact.dart';
import 'package:flutter_test/flutter_test.dart';

/// A subscription URL carries its key, and the app's logs are readable over adb by design.
/// What is written about a URL therefore has to be the part that cannot fetch anything.
void main() {
  test('credentials and query are cut off', () {
    expect(
      redactUrl('https://user:secret@panel.example/sub/abc?token=xyz'),
      'https://panel.example',
    );
  });

  test('a key in the path is cut with the path', () {
    expect(
      redactUrl('https://rnpremiumsub.icu/8f3c1d2e9a'),
      'https://rnpremiumsub.icu',
    );
  });

  test('a plain host keeps its scheme', () {
    expect(redactUrl('http://192.168.2.3:8191/x'), 'http://192.168.2.3');
  });

  test('a value that is not a URL is not repeated', () {
    expect(redactUrl('8f3c1d2e9a'), '<unparsed-url>');
    expect(redactUrl(null), '');
  });
}
