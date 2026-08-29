import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/tribattle.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/tribattle_screen.dart';

/// 스모크: 화면이 뜨고, 내 배치가 되고, 봇이 이어받아 진행되는지.
/// (연출·정산의 시각 검증은 실기기 몫 — 여기서는 상태 기계와 상호작용만.)
void main() {
  testWidgets('트라이 배틀 v3 — 배치·봇 진행 스모크', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const TriBattleScreen(seed: 7),
    ));
    await tester.pump();

    final state =
        tester.state(find.byType(TriBattleScreen)) as dynamic; // ignore: avoid_dynamic_calls
    final TriGame g = state.game as TriGame;
    expect(g.current, 0, reason: '첫 판은 내가 선턴');
    expect(g.hands[0].length, TriRules.startHand + 1, reason: '시작 패 + 드로');

    // 내 배치: 손패 0을 0열에.
    final rank0 = g.hands[0][0].rank;
    state.placeForTest(0, 0);
    await tester.pump();
    expect(g.boards[0].cols[0].first.rank, rank0, reason: '내 배치가 보드에 반영');

    // 봇 턴이 돌아 다음 내 차례(또는 판 종료)까지 진행된다.
    for (var i = 0; i < 40 && !g.finished && g.current == 1; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    final botCards =
        g.boards[1].cols.fold<int>(0, (a, c) => a + c.length);
    final botAttacked = g.boards[0].cols[0].isEmpty;
    expect(botCards >= 1 || botAttacked, isTrue, reason: '봇이 실제로 행동했다');

    // 남은 비동기 타이머 정리.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
