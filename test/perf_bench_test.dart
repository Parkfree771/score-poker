import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:score_poker/ui/widgets/card_face.dart';
import 'package:score_poker/ui/widgets/suit_glyphs.dart';

/// 성능 벤치마크.
///
/// **절대 ms를 믿지 말 것.** 이 PC에서 다른 프로그램이 CPU를 쓰면 모든 수치가 함께
/// 2배까지 부풀어서, 멀쩡한 코드를 회귀로 오진하게 된다(실제로 한 번 그랬다).
/// 대신 같은 실행에서 잰 **기준선 대비 배수**를 본다 — 부하가 걸려도 배수는 유지된다.
///
/// 기준 배수 (가림 룰 화면으로 전환한 뒤 이 PC에서 5회 측정):
///   게임화면 세로 ≈ 기준선의 **2.2~3.7배** (기준값 3.0)
///   게임화면 가로 ≈ 기준선의 **1.2~2.9배** (기준값 2.5)
/// **한 번 재고 판단하지 말 것.** 같은 코드로도 실행마다 위 범위를 오간다 —
/// 한 판만 보고 "회귀"라고 부르면 멀쩡한 코드를 뜯게 된다(실제로 한 번 그럴 뻔했다).
/// 여러 번 돌려 중앙값이 기준값을 뚜렷이 넘을 때가 진짜 회귀다.
void main() {
  Widget app(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  /// 15칸이 다 찬 판 + 손패 3장 — 가장 무거운 프레임.
  ScoreGame fullBoard() {
    final g = ScoreGame.deal(seed: 3);
    var r = 0;
    for (final p in PlayerId.values) {
      for (var row = 0; row < kRows; row++) {
        for (var col = 0; col < kCols; col++) {
          g.fields[p]![row][col] = VeiledSlot(
            PlayingCard(2 + (r++ % 13), Suit.values[r % 4]),
            faceUp: (row + col) % 4 != 0, // 몇 칸은 뒷면으로 남긴다
          );
        }
      }
    }
    return g;
  }

  Future<void> setScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(size);
  }

  testWidgets('BENCH 카드 30장 반복 리빌드', (tester) async {
    await setScreen(tester, const Size(1000, 800));
    var tick = 0;
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: Column(
          children: [
            Text('$tick'),
            Expanded(
              child: Wrap(
                children: [
                  for (var i = 0; i < 30; i++)
                    CardFace(card: PlayingCard(2 + i % 13, Suit.values[i % 4]), size: 46),
                ],
              ),
            ),
            ElevatedButton(
                onPressed: () => setState(() => tick++), child: const Text('go')),
          ],
        ),
      ),
    )));
    await tester.pumpAndSettle();

    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.text('go'));
      await tester.pump();
    }
    sw.stop();
    // ignore: avoid_print
    print('[BENCH] CardFace×30 리빌드 30회: ${sw.elapsedMilliseconds}ms '
        '(프레임당 ${(sw.elapsedMicroseconds / 30 / 1000).toStringAsFixed(2)}ms)');
  });


  // 병목 분리: SVG를 쓰는 CardFace vs 같은 개수의 단순 위젯
  testWidgets('BENCH 병목 분리', (tester) async {
    await setScreen(tester, const Size(1000, 800));

    Future<double> measure(String label, Widget Function(int) item) async {
      var tick = 0;
      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Column(children: [
            Text('$tick'),
            Expanded(child: Wrap(children: [for (var i = 0; i < 30; i++) item(i)])),
            ElevatedButton(onPressed: () => setState(() => tick++), child: const Text('go')),
          ]),
        ),
      )));
      await tester.pumpAndSettle();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 30; i++) {
        await tester.tap(find.text('go'));
        await tester.pump();
      }
      sw.stop();
      final per = sw.elapsedMicroseconds / 30 / 1000;
      // ignore: avoid_print
      print('[BENCH] $label: 프레임당 ${per.toStringAsFixed(2)}ms');
      return per;
    }

    await measure('  (a) CardFace 전체(SVG 2개/장)',
        (i) => CardFace(card: PlayingCard(2 + i % 13, Suit.values[i % 4]), size: 46));
    await measure('  (b) SVG 1개만(무늬)',
        (i) => SizedBox(width: 46, height: 62, child: SvgPicture.string(suitSvg(Suit.values[i % 4]))));
    await measure('  (b2) 프레임 SVG만(매번 문자열 생성)',
        (i) => SizedBox(width: 46, height: 62, child: SvgPicture.string(cardFrameSvg('#121330'))));
    final cachedFrame = cardFrameSvg('#121330');
    await measure('  (b3) 프레임 SVG만(문자열 캐시)',
        (i) => SizedBox(width: 46, height: 62, child: SvgPicture.string(cachedFrame)));
    final cachedLoader = SvgStringLoader(cachedFrame);
    await measure('  (b4) 프레임 SVG만(loader 캐시)',
        (i) => SizedBox(width: 46, height: 62, child: SvgPicture(cachedLoader)));
    await measure('  (c) SVG 없이 텍스트+박스', (i) => Container(
          width: 46, height: 62,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: const Center(child: Text('A')),
        ));
  });

  /// 같은 실행에서 잰 기준선(단순 위젯 30개 리빌드). 부하 보정용 분모.
  Future<double> measureBaseline(WidgetTester tester) async {
    var tick = 0;
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: Column(children: [
          Text('$tick'),
          Expanded(
            child: Wrap(children: [
              for (var i = 0; i < 30; i++)
                Container(
                  width: 46,
                  height: 62,
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(6)),
                  child: const Center(child: Text('A')),
                ),
            ]),
          ),
          ElevatedButton(onPressed: () => setState(() => tick++), child: const Text('go')),
        ]),
      ),
    )));
    await tester.pumpAndSettle();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.text('go'));
      await tester.pump();
    }
    sw.stop();
    return sw.elapsedMicroseconds / 30 / 1000;
  }

  for (final (label, size, expected) in [
    ('세로 430x930', const Size(430, 930), 3.0),
    ('가로 1512x760', const Size(1512, 760), 2.5),
  ]) {
    testWidgets('BENCH 게임화면 리빌드 — $label', (tester) async {
      await setScreen(tester, size);
      final baseline = await measureBaseline(tester);
      await tester.pumpWidget(app(GameScreen(initialGame: fullBoard())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final state = tester.state<State>(find.byType(GameScreen));
      final sw = Stopwatch()..start();
      for (var i = 0; i < 30; i++) {
        // ignore: invalid_use_of_protected_member
        state.setState(() {});
        await tester.pump();
      }
      sw.stop();
      final per = sw.elapsedMicroseconds / 30 / 1000;
      final ratio = per / baseline;
      // ignore: avoid_print
      print('[BENCH] 게임화면 $label — 프레임당 ${per.toStringAsFixed(2)}ms '
          '(기준선 ${baseline.toStringAsFixed(2)}ms의 ${ratio.toStringAsFixed(2)}배, '
          '기준 $expected배) ${ratio > expected * 1.5 ? "*** 회귀 의심 ***" : "OK"}');
    });
  }
}
