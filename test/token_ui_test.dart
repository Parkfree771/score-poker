import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/shop_screen.dart';
import 'package:score_poker/ui/widgets/card_face.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 화면에서 토큰을 실제로 쓰는 흐름을 고정한다.
///
/// 도메인 규칙은 `token_rules_test.dart`가 지킨다. 여기서 지키는 것은 **돈과 관련된
/// 순서**다: 규칙이 거부하면 토큰이 차감되면 안 되고, 없는데 쓰려 하면 상점으로 갈 길이
/// 있어야 한다.

/// 내 필드에 7♥ 한 장, 손패에 평범한 4♣ 한 장. 둘 다 토큰의 대상이 되는 상태다.
GameState _state({GameRules mine = GameRules.standard}) {
  final s = GameState.custom(Deck.shuffled(seed: 3), rules: {PlayerId.p0: mine});
  s.fields[PlayerId.p0]![0][0] =
      PlacedCard(const PlayingCard(7, Suit.hearts), PlayerId.p0);
  s.hands[PlayerId.p0]!
    ..clear()
    ..add(const PlayingCard(4, Suit.clubs));
  s.hands[PlayerId.p1]!.clear();
  s.current = PlayerId.p0;
  return s;
}

Finder _cardOnScreen(bool Function(PlayingCard) test) =>
    find.byWidgetPredicate((w) => w is CardFace && test(w.card));

Future<Monetization> _pump(
  WidgetTester tester, {
  GameRules mine = GameRules.standard,
  TokenGrantPolicy policy = const TokenGrantPolicy(),
}) async {
  tester.view.physicalSize = const Size(430, 930);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final m = Monetization(
    purchases: StubPurchaseService(),
    wallet: TokenWallet(policy: policy),
  );
  await m.startAsync();
  addTearDown(m.dispose);

  // 실제 앱(main.dart)과 같은 순서: MonetizationScope가 **MaterialApp 위**에 있어야
  // push로 열린 화면(상점)도 스코프 안에 들어온다.
  await tester.pumpWidget(MonetizationScope(
    monetization: m,
    child: MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: GameScreen(initialState: _state(mine: mine)),
    ),
  ));
  await tester.pump();
  return m;
}

void main() {
  testWidgets('쉴드 토큰: 버튼 → 내 카드 탭 → 쉴드가 되고 1개 차감된다', (tester) async {
    final m = await _pump(tester);
    expect(m.wallet.balanceOf(TokenKind.shield), 3);
    expect(_cardOnScreen((c) => c.rank == 7 && c.isShield), findsNothing);

    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();

    await tester.tap(_cardOnScreen((c) => c.rank == 7).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_cardOnScreen((c) => c.rank == 7 && c.isShield), findsWidgets,
        reason: '내 카드가 쉴드로 바뀌어야 한다');
    expect(m.wallet.balanceOf(TokenKind.shield), 2);
  });

  testWidgets('공격 토큰: 버튼 → 손패 탭 → 공격 표식이 붙고 1개 차감된다', (tester) async {
    final m = await _pump(tester);
    expect(_cardOnScreen((c) => c.rank == 4 && c.isAttacker), findsNothing);

    await tester.tap(find.byIcon(Icons.local_fire_department_rounded));
    await tester.pump();

    await tester.tap(_cardOnScreen((c) => c.rank == 4).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_cardOnScreen((c) => c.rank == 4 && c.isAttacker), findsWidgets);
    expect(m.wallet.balanceOf(TokenKind.attack), 2);
  });

  testWidgets('규칙이 거부하면 토큰은 차감되지 않는다 (이미 쉴드인 카드)', (tester) async {
    final m = await _pump(tester);

    // 첫 번째 선언으로 7♥가 쉴드가 된다 (3 → 2)
    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    await tester.tap(_cardOnScreen((c) => c.rank == 7).first);
    await tester.pump();
    expect(m.wallet.balanceOf(TokenKind.shield), 2);

    // 판당 1회를 다 썼으므로 두 번째는 시작조차 못 한다
    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    expect(m.wallet.balanceOf(TokenKind.shield), 2,
        reason: '거부된 시도로 토큰이 사라지면 환불 문의가 된다');
  });

  testWidgets('판당 1회를 다 쓰면 안내가 뜨고 더 못 쓴다', (tester) async {
    final m = await _pump(tester);

    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    await tester.tap(_cardOnScreen((c) => c.rank == 7).first);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    expect(find.textContaining('이 판에서 이미'), findsOneWidget);
    expect(m.wallet.balanceOf(TokenKind.shield), 2);
  });

  testWidgets('토큰이 없으면 상점으로 가는 길을 준다', (tester) async {
    await _pump(tester, policy: const TokenGrantPolicy(welcome: {}, daily: {}));

    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 스낵바가 다 올라올 때까지
    expect(find.text('상점'), findsOneWidget, reason: '없다고만 하고 끝나면 팔 기회를 버리는 것');

    // 게임 화면의 골드 링이 무한 반복이라 pumpAndSettle은 끝나지 않는다 — 고정 펌프.
    await tester.tap(find.widgetWithText(TextButton, '상점'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ShopScreen), findsOneWidget);
  });

  testWidgets('상한이 0인 판에서는 토큰 버튼이 아무 일도 하지 않는다', (tester) async {
    final m = await _pump(tester, mine: GameRules.none);

    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pump();
    await tester.tap(_cardOnScreen((c) => c.rank == 7).first);
    await tester.pump();

    expect(_cardOnScreen((c) => c.rank == 7 && c.isShield), findsNothing);
    expect(m.wallet.balanceOf(TokenKind.shield), 3);
  });

  testWidgets('지갑이 없는 화면(테스트·스크린샷)에서는 토큰 버튼이 아예 없다', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: GameScreen(initialState: _state()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.shield_rounded), findsNothing);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget, reason: '나머지 버튼은 그대로다');
  });
}
