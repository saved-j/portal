// Renders the tour at three text scales and writes one PNG per page.
//
// The tour measures the widgets under it, so the page it is given has to carry the same keys the
// real working screen carries: the frames are checked here, not guessed from a phone screenshot.
//
//   flutter test test/tour_shots_test.dart --update-goldens
//
// The scale is forced through MediaQuery, which is exactly what the system does when the owner
// raises the font size — the app does not clamp it.

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/tutorial/portal_tutorial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ShotPage extends StatelessWidget {
  const _ShotPage();

  static const _servers = [
    ('DE', 'Германия', 96),
    ('PL', 'Польша', 112),
    ('EE', 'Эстония', 134),
    ('FI', 'Финляндия', 158),
    ('NL', 'Нидерланды', 171),
    ('US', 'США', 208),
    ('JP', 'Япония', 226),
    ('SG', 'Сингапур', 241),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'portal-connect',
                key: tutorialKeys[TutorialTarget.modeLabel],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                key: tutorialKeys[TutorialTarget.modeSwitch],
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: const [
                  Switch(value: true, onChanged: null),
                  Text('Portal network'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: tutorialKeys[TutorialTarget.filters],
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final name in const [
                      'Auto',
                      'Auto Europe',
                      'Auto USA',
                      'Auto Asia',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF23262B),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(name),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  key: tutorialKeys[TutorialTarget.autoPingColumn],
                  children: [
                    for (final s in _servers)
                      ListTile(
                        dense: true,
                        title: Text('${s.$1} ${s.$2}'),
                        subtitle: const Text('VLESS'),
                        trailing: Text('${s.$3} ms'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: tutorialKeys[TutorialTarget.start],
                    onPressed: () {},
                    child: const Text('Open portal'),
                  ),
                  IconButton(
                    key: tutorialKeys[TutorialTarget.autoPing],
                    onPressed: () {},
                    icon: const Icon(Icons.bolt),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpTour(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(824, 1830);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  late BuildContext pageContext;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        locale: const Locale('ru'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const _ShotPage();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  showPortalTutorial(pageContext);
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('tour pages at text scale $scale', (tester) async {
      await _pumpTour(tester, scale);
      final tag = scale.toStringAsFixed(0);
      for (var page = 1; page <= 8; page++) {
        // A page that waits for the screen to settle is drawn a beat late.
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/tour_${tag}x_$page.png'),
        );
        final next = find.text('Далее');
        if (next.evaluate().isEmpty) break;
        await tester.tap(next.first, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
    });
  }
}
