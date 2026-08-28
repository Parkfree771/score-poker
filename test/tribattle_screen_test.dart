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

    final state = tester.state(find.byType(TriBattleScreen))
        as dynamic; // ignore: avoid_dynamic_calls
    final TriGame g = state.game as TriGame;
    expect(g.market.whereType<TriCard>().length, TriRules.marketSize);
    expect(g.turnOwner, isTrue, reason: '첫 라운드는 내가 선픽');

    // 내 픽: 마켓 첫 슬롯 카드를 0번 열에 배치.
    final card0 = g.market[0]!;
    state.myPlaceForTest(0, 0);
    await tester.pump();
    expect(g.rowA[0]?.value, card0.value, reason: '내 배치가 열에 반영');
    expect(g.market[0], isNull, reason: '픽된 슬롯은 빈 홈으로 남는다');
    expect(g.openA.contains(0), isFalse, reason: '이번 라운드에 채운 열');

    // 봇 턴(다음 2픽)이 돌아 내 차례로 돌아온다.
    for (var i = 0; i < 40 && g.turnOwner == false; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(g.rowB.whereType<TriCard>().length, greaterThanOrEqualTo(1),
        reason: '봇이 실제로 배치했다');

    // 남은 비동기 타이머·오버레이 정리.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
