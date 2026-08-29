import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/personas.dart';
import 'package:score_poker/ui/widgets/board_view.dart';
import 'package:score_poker/ui/widgets/joker_card.dart';

/// **한 판을 실제로 끝까지 눌러 본다.** 도메인 테스트가 통과해도 화면에서
/// 손이 막히면 게임은 안 되는 것이다 — v4 흐름: 딜 → 교대 턴(배치·공격·칩)
/// → 최후 공개 → 결과 → 다시 하기. (안 두면 타임업이 대신 둔다)
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

  /// 손패에서 **조커가 아닌** 첫 카드의 키를 찾는다.
  Finder firstPlainHandCard(WidgetTester tester) {
    for (var i = 0; i < 6; i++) {
      final f = labeled('hand-$i');
      if (f.evaluate().isEmpty) continue;
      if (find.descendant(of: f, matching: find.byType(JokerFace)).evaluate().isEmpty) return f;
    }
    fail('조커 아닌 손패가 없다');
  }

  Future<void> waitFor(WidgetTester tester, Finder f,
      {Duration max = const Duration(seconds: 90)}) async {
    const step = Duration(milliseconds: 250);
    for (var t = Duration.zero; t < max; t += step) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(step);
    }
    expect(f, findsWidgets, reason: '제한 시간 안에 나타나지 않았다');
  }

  testWidgets('한 판 전체 흐름 — 배치·턴 교대·정산·다시 하기', (tester) async {
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
    expect(labeled('hand-'), findsNWidgets(5), reason: '시작 손패 4 + 첫 드로');
    // 상대 캐릭터가 인사한다.
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && clode.lines.greeting.contains(w.data)),
        findsOneWidget);

    // ── 내 첫 세 턴: 손패를 골라 세 줄에 한 장씩 ─────────────────────────────
    for (var row = 0; row < 3; row++) {
      // 내 차례 안내가 뜰 때까지(봇 턴·연출 사이) 기다린다.
      await waitFor(
          tester,
          find.byWidgetPredicate((w) =>
              w is Text &&
              (w.data?.contains('내 차례') ?? false)),
          max: const Duration(seconds: 40));
      await tester.tap(firstPlainHandCard(tester));
      await tester.pump();
      await tester.tap(labeled('cell-p0-$row-0'), warnIfMissed: false);
      await pumpFor(tester, const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: '$row줄 배치 중 예외');
    }

    // ── 나머지는 타임업 자동 진행으로 결과까지 ───────────────────────────────
    final resultTitles = [l10n.matchWin, l10n.matchLose, l10n.matchDraw];
    final resultShown = find.byWidgetPredicate(
        (w) => w is Text && resultTitles.contains(w.data));
    await waitFor(tester, resultShown, max: const Duration(seconds: 900));
    expect(resultShown, findsOneWidget, reason: '결과 오버레이');
    expect(tester.takeException(), isNull);

    // ── 다시 하기 ───────────────────────────────────────────────────────────
    await tester.tap(find.text(l10n.playAgain));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(labeled('hand-'), findsNWidgets(5), reason: '새 판 딜링');

    // 새 판의 타이머·봇 예약을 끝까지 흘려보낸다.
    await pumpFor(tester, const Duration(seconds: 900),
        step: const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
