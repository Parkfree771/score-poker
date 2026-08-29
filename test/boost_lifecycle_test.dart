import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/widgets/joker_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 부스트 토큰의 수명 — 토큰 하나는 **딱 한 판**이다.
///
/// 1. "다시 하기"는 토큰을 하나 더 쓴다(없으면 보통 판). 토큰 하나로 무한 부스트 금지.
/// 2. 판을 시작해 놓고 한 수도 안 두고 나가면 토큰을 돌려준다.
/// 3. 한 수라도 뒀으면 나가도 돌려주지 않는다.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Monetization> pump(WidgetTester tester, {required int boosts}) async {
    final m = Monetization(
        purchases: StubPurchaseService(),
        wallet: TokenWallet(policy: TokenGrantPolicy(welcome: {TokenKind.boost: boosts})));
    await m.wallet.load();
    await tester.pumpWidget(MonetizationScope(
      monetization: m,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('go'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const GameScreen(seed: 1, boosted: true))),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    return m;
  }

  /// 화면을 내리고, AI가 걸어 둔 지연 타이머(seq 가드로 무시됨)까지 흘려보낸다.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  Future<void> settle(WidgetTester tester, [int ms = 4000]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('다시 하기는 토큰을 하나 더 쓴다 — 없으면 보통 판', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    // 매칭 화면이 이미 하나 썼다고 가정: 잔량 1개로 시작(=재시작 한 번만 부스트 가능).
    final m = await pump(tester, boosts: 1);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    final state = tester.state(find.byType(GameScreen)) as dynamic;
    expect(state.g.veilLeft[PlayerId.p0], 5, reason: '첫 판은 부스트(칩 4+1)');

    state.restartForTest();
    await settle(tester);
    expect(m.wallet.balanceOf(TokenKind.boost), 0, reason: '재시작이 토큰을 썼다');
    expect(state.g.veilLeft[PlayerId.p0], 5, reason: '토큰이 있었으니 부스트 판');

    state.restartForTest();
    await settle(tester, 500);
    expect(find.text('남은 부스트가 없어요'), findsOneWidget);
    await settle(tester);
    expect(state.g.veilLeft[PlayerId.p0], 4, reason: '토큰이 없으면 보통 판');
    await drain(tester);
  });

  testWidgets('한 수도 안 두고 나가면 부스트를 돌려준다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final m = await pump(tester, boosts: 3);
    await m.wallet.spend(TokenKind.boost); // 매칭 화면 몫
    expect(m.wallet.balanceOf(TokenKind.boost), 2);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await settle(tester, 1000);
    expect(m.wallet.balanceOf(TokenKind.boost), 3, reason: '미사용 → 환불');
    await drain(tester);
  });

  testWidgets('한 수라도 뒀으면 나가도 돌려주지 않는다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final m = await pump(tester, boosts: 3);
    await m.wallet.spend(TokenKind.boost);
    await tester.tap(find.byKey(const ValueKey('go')));
    await settle(tester);
    // 손패에서 조커 아닌 첫 장을 첫 칸에 놓는다(조커는 시트가 열린다).
    var idx = 0;
    for (; idx < 5; idx++) {
      final f = find.byWidgetPredicate(
          (w) => w.key is GlobalKey && w.key.toString().contains('hand-$idx'));
      if (f.evaluate().isEmpty) continue;
      if (find
          .descendant(of: f, matching: find.byType(JokerFace))
          .evaluate()
          .isEmpty) {
        break;
      }
    }
    await tester.tap(find.byWidgetPredicate(
        (w) => w.key is GlobalKey && w.key.toString().contains('hand-$idx')));
    await tester.pump();
    await tester.tap(
        find.byWidgetPredicate(
            (w) => w.key is GlobalKey && w.key.toString().contains('cell-p0-0-0')),
        warnIfMissed: false);
    await settle(tester, 1500);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await settle(tester, 1000);
    expect(m.wallet.balanceOf(TokenKind.boost), 2, reason: '사용 → 환불 없음');
    await drain(tester);
  });
}
