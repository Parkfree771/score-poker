import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/tribattle.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/tribattle_screen.dart';

/// 스모크: 화면이 뜨고, 내 픽 → 배치가 되고, 봇이 이어받아 진행되는지.
/// (연출·정산의 시각 검증은 실기기 몫 — 여기서는 상태 기계와 상호작용만.)
void main() {
  testWidgets('트라이 배틀 — 픽·배치·봇 진행 스모크', (tester) async {
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
    expect(g.market.length, TriRules.marketSize);
    expect(g.turnOwner, isTrue, reason: '첫 판은 내가 선픽');

    // 내 픽: 마켓 첫 카드 선택 → 빈 칸 (0,0)에 배치.
    final card0 = g.market[0];
    state.selectedMarket = 0; // 탭 좌표 대신 상태로 직접(스크롤 위치 무관하게)
    // ignore: invalid_use_of_protected_member
    state.setState(() {});
    await tester.pump();
    state.myPlaceForTest(0, 0, 0);
    await tester.pump();
    expect(g.boardA.g[0][0]?.value, card0.value, reason: '내 배치가 보드에 반영');

    // 봇 턴이 돌아 다음 내 차례(또는 판 종료)까지 진행된다.
    for (var i = 0; i < 40 && g.turnOwner == false; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(g.boardB.g.expand((r) => r).whereType<TriCard>().length,
        greaterThanOrEqualTo(1), reason: '봇이 실제로 배치했다');

    // 남은 비동기 타이머 정리.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
