import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/strike.dart';
import 'package:score_poker/ui/strike_screen.dart';
import 'package:score_poker/ui/theme.dart';

/// 스모크: 화면이 뜨고, 내 배치가 되고, 봇이 이어받아 진행되는지.
/// (연출은 instantMoves로 생략 — 상태 기계와 상호작용만 검증한다.)
void main() {
  testWidgets('스트라이크 — 배치·봇 진행 스모크', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const StrikeScreen(seed: 7, instantMoves: true),
    ));
    await tester.pump();

    final st = tester.state(find.byType(StrikeScreen)) as StrikeScreenState;
    final g = st.game;
    expect(g.current, 0, reason: '첫 판은 내가 선턴');
    expect(g.hands[0].length, StrikeRules.startHand + 1, reason: '시작 패 + 드로');
    expect(g.hands[0].any((c) => c.isJoker), isFalse, reason: '조커 없는 52장');

    // 내 배치: 손패 0을 0줄에.
    final card = g.hands[0][0];
    await st.placeForTest(0, 0);
    await tester.pump();
    expect(g.fields[0][0].first.card, card, reason: '내 배치가 필드에 반영');

    // 봇 턴이 돌아 다음 내 차례(또는 판 종료)까지 진행된다.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 350));
      if (g.finished ||
          (g.current == 0 && g.phase == StrikePhase.action)) {
        break;
      }
    }
    final botActed = g.fields[1].any((r) => r.isNotEmpty) ||
        g.fields[0][0].isEmpty; // 배치했거나 내 카드를 쳐냈거나
    expect(botActed, isTrue, reason: '봇이 실제로 행동했다');

    // 남은 비동기 타이머 정리.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
