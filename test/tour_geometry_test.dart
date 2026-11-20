// The tour, checked by geometry instead of by eye.
//
// For every page, at three text scales and in both layouts, this test measures the control the
// page points at and the card it draws, and fails when the card covers the control or leaves the
// screen. A frame that lands beside its control, or a card that covers the page it explains, is a
// failing test rather than something to notice in a screenshot later.
//
//   flutter test test/tour_geometry_test.dart
//
// The three scales are forced through MediaQuery — the same channel the system uses when the
// owner raises the font size.

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/tutorial/portal_tutorial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ShotPage extends StatelessWidget {
  const _ShotPage();

  static const _servers = [
    'Германия',
    'Польша',
    'Эстония',
    'Финляндия',
    'Нидерланды',
    'США',
    'Япония',
    'Сингапур',
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
                    for (final name in const ['Auto', 'Auto Europe', 'Auto USA'])
                      Padding(
                        key: name == 'Auto' ? tutorialKeys[TutorialTarget.chip] : null,
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      ListTile(dense: true, title: Text(s), subtitle: const Text('VLESS')),
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

Future<void> _pumpTour(
  WidgetTester tester,
  double scale, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
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
    for (final layout in {
      'phone': const Size(824, 1830),
      'wide': const Size(1800, 1200),
    }.entries) {
      testWidgets('tour page geometry at ${layout.key}, scale $scale', (
        tester,
      ) async {
        await _pumpTour(tester, scale, size: layout.value);
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

        for (var page = 1; page <= 8; page++) {
          await tester.pump(const Duration(milliseconds: 400));

          final card = find.byKey(tutorialCardKey);
          if (card.evaluate().isEmpty) break;
          final cardRect = tester.getRect(card);
          // ignore: avoid_print
          print(
            'RENDER ${card.evaluate().first.renderObject.runtimeType} '
            'offset=${tester.getTopLeft(card)} size=${tester.getSize(card)}',
          );
          // ignore: avoid_print
          print(
            'CARD $page: ${cardRect.left.round()},${cardRect.top.round()} '
            '${cardRect.width.round()}x${cardRect.height.round()}',
          );

          // The control this page points at, read from the same key the tour reads.
          final step = tutorialSteps[page - 1];
          final target = step.target;
          Rect? targetRect;
          if (target != null) {
            final box = tutorialKeys[target]?.currentContext?.findRenderObject();
            if (box is RenderBox && box.hasSize) {
              final origin = box.localToGlobal(Offset.zero);
              targetRect = origin & box.size;
              // ignore: avoid_print
              print(
                'TARGET $page: ${origin.dx.round()},${origin.dy.round()} '
                '${box.size.width.round()}x${box.size.height.round()}',
              );
            }
          }

          // ignore: avoid_print
          print(
            '${layout.key} x$scale page $page: '
            'card=${_fmt(cardRect)} target=${_fmt(targetRect)} '
            'gaps=${_gapReport(tester, targetRect, screen)}',
          );

          expect(
            cardRect.left >= -0.5 && cardRect.top >= -0.5,
            isTrue,
            reason: 'page $page: the card leaves the screen at the top left',
          );
          expect(
            cardRect.right <= screen.width + 0.5 &&
                cardRect.bottom <= screen.height + 0.5,
            isTrue,
            reason: 'page $page: the card leaves the screen at the bottom right',
          );
          expect(
            cardRect.height <= screen.height * 0.45,
            isTrue,
            reason: 'page $page: the card takes more than its share of the screen',
          );
          if (targetRect != null) {
            expect(
              cardRect.overlaps(targetRect),
              isFalse,
              reason:
                  'page $page: the card covers the control it explains '
                  '(${_fmt(cardRect)} against ${_fmt(targetRect)})',
            );
          }

          final next = find.text('Далее');
          if (next.evaluate().isEmpty) break;
          await tester.tap(next.first, warnIfMissed: false);
          await tester.pumpAndSettle();
        }
      });
    }
  }
}

String _gapReport(WidgetTester tester, Rect? t, Size screen) {
  if (t == null) return 'no target';
  const m = 16.0, g = 24.0;
  final below = screen.height - (t.bottom + g) - m;
  final above = (t.top - g) - m;
  final right = screen.width - (t.right + g) - m;
  final left = (t.left - g) - m;
  return 'below=${below.round()} above=${above.round()} '
      'right=${right.round()} left=${left.round()} '
      'screen=${screen.width.round()}x${screen.height.round()}';
}

String _fmt(Rect? r) => r == null
    ? 'none'
    : '${r.left.round()},${r.top.round()} '
          '${r.width.round()}x${r.height.round()}';
