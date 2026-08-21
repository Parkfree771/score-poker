import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/personas.dart';
import 'package:score_poker/ui/widgets/board_view.dart';

/// **한 판을 실제로 끝까지 눌러 본다.** 도메인 테스트가 통과해도 화면에서
/// 손이 막히면 게임은 안 되는 것이다 — 여기서 보는 것은 흐름 그 자체다:
/// 딜 → (배치 → 봉인 → 공개 → 보충) × 5 → 최후 공개 → 결과 → 다시 하기.
void main() {
  final l10n = AppLocalizationsKo();

  Finder labeled(String label) => find.byWidgetPredicate(
      (w) => w.key is GlobalKey && w.key.toString().contains(label));

  Future<void> pumpFor(WidgetTester tester, Duration total,
      {Duration step = const Duration(milliseconds: 250)}) async {
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  /// [f]가 나타날 때까지(최대 [max]) 시간을 흘린다. 라운드 길이는 상대 AI가 언제
  /// 놓느냐에 따라 달라지므로 고정 시간으로 기다리면 다음 라운드까지 지나가 버린다.
  Future<void> waitFor(WidgetTester tester, Finder f,
      {Duration max = const Duration(seconds: 90)}) async {
    const step = Duration(milliseconds: 250);
    for (var t = Duration.zero; t < max; t += step) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(step);
    }
    expect(f, findsWidgets, reason: '제한 시간 안에 나타나지 않았다');
  }

  testWidgets('한 판 전체 흐름 — 배치·봉인·공개·정산·다시 하기', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clode = buildPersonas(l10n)[0];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(seed: 4, persona: clode),
    ));

    // ── 딜링 ────────────────────────────────────────────────────────────────
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(find.byType(BoardView), findsOneWidget);
    expect(labeled('hand-'), findsNWidgets(6), reason: '시작 손패 6장');
    expect(find.text(l10n.roundLabel(1)), findsOneWidget);
    // 상대 캐릭터가 인사한다.
    expect(find.text(clode.lines.greeting.first), findsOneWidget);

    for (var round = 1; round <= 5; round++) {
      expect(find.text(l10n.roundLabel(round)), findsOneWidget,
          reason: '$round라운드 표시');

      // 라운드 표시는 딜링이 시작될 때 이미 바뀐다 — **딜링 중 탭은 무시되므로**
      // 배치 안내가 뜰 때까지(= 배치 단계) 기다렸다가 손을 댄다.
      await waitFor(tester, find.text(l10n.vlPlacePrompt),
          max: const Duration(seconds: 10));

      // ── 배치: 손패에서 3장을 골라 세 줄에 한 장씩 ──────────────────────────
      for (var row = 0; row < 3; row++) {
        await tester.tap(labeled('hand-0'));
        await tester.pump();
        await tester.tap(labeled('cell-p0-$row-${round - 1}'),
            warnIfMissed: false);
        await pumpFor(tester, const Duration(milliseconds: 600));
      }
      expect(labeled('hand-'), findsNWidgets(3), reason: '3장 내면 3장 남는다');

      // ── 봉인: 2라운드에 한 번, 방금 놓은 카드를 덮어 둔다 ──────────────────
      if (round == 2) {
        final coinsBefore = tester
            .widgetList<VeilCoin>(find.byType(VeilCoin))
            .where((c) => c.filled)
            .length;
        await tester.tap(labeled('cell-p0-0-${round - 1}'), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(SealStamp), findsOneWidget, reason: '봉인 도장');
        final coinsAfter = tester
            .widgetList<VeilCoin>(find.byType(VeilCoin))
            .where((c) => c.filled)
            .length;
        expect(coinsAfter, coinsBefore - 1, reason: '비공개권 1개 소모');
      }

      // ── 공개까지: 타이머(양쪽 배치 완료 시 5초) + 공개 연출 + 줄별 판정 ──────
      final resultTitles = [l10n.matchWin, l10n.matchLose, l10n.matchDraw];
      final resultShown = find.byWidgetPredicate(
          (w) => w is Text && resultTitles.contains(w.data));
      await waitFor(
        tester,
        round < 5 ? find.text(l10n.roundLabel(round + 1)) : resultShown,
        max: const Duration(seconds: 120),
      );
      expect(tester.takeException(), isNull, reason: '$round라운드 진행 중 예외');

      if (round < 5) {
        expect(labeled('hand-'), findsNWidgets(6), reason: '라운드마다 3장 보충');
      } else {
        expect(resultShown, findsOneWidget, reason: '결과 오버레이');
      }
    }

    // 모든 칸이 공개됐다 — 봉인도, 뒷면도 남지 않는다.
    expect(find.byType(SealStamp), findsNothing);

    // ── 다시 하기 ───────────────────────────────────────────────────────────
    await tester.tap(find.text(l10n.playAgain));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(find.text(l10n.roundLabel(1)), findsOneWidget, reason: '1라운드부터 다시');
    expect(labeled('hand-'), findsNWidgets(6));

    // 새 판의 타이머·AI 예약을 끝까지 흘려보낸다.
    await pumpFor(tester, const Duration(seconds: 420),
        step: const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
