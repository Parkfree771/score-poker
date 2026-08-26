import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/main.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:score_poker/ui/shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 보상형 광고의 **지급 규칙**을 고정한다.
///
/// 조용히 망가지는 것들: 중간 이탈에도 주기(광고 수익 없이 토큰만 샘), 하루 캡이 안 걸리기
/// (무료 무제한 = 판매 사망), 같은 노출로 두 번 주기, 더블탭으로 두 번 띄우기.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TokenWallet.grantAdReward', () {
    test('끝까지 본 광고 1회 = 부스트 1판, 하루 캡 2회', () async {
      final w = TokenWallet();
      await w.load();
      final day = DateTime(2026, 8, 26, 10);
      expect(w.adRewardsLeftToday(now: day), 2);

      expect(await w.grantAdReward(rewardId: 'a', now: day), isTrue);
      expect(w.balanceOf(TokenKind.boost), 4);
      expect(await w.grantAdReward(rewardId: 'b', now: day), isTrue);
      expect(w.balanceOf(TokenKind.boost), 5);
      expect(w.adRewardsLeftToday(now: day), 0);

      expect(await w.grantAdReward(rewardId: 'c', now: day), isFalse,
          reason: '캡을 넘겨 주면 무료 무제한 = 팩이 안 팔린다');
      expect(w.balanceOf(TokenKind.boost), 5);
    });

    test('날짜가 바뀌면 캡이 리셋된다', () async {
      final w = TokenWallet();
      await w.load();
      final day1 = DateTime(2026, 8, 26, 23, 50);
      await w.grantAdReward(rewardId: 'a', now: day1);
      await w.grantAdReward(rewardId: 'b', now: day1);
      expect(w.adRewardsLeftToday(now: day1), 0);

      final day2 = DateTime(2026, 8, 27, 0, 5);
      expect(w.adRewardsLeftToday(now: day2), 2);
      expect(await w.grantAdReward(rewardId: 'c', now: day2), isTrue);
    });

    test('같은 보상 id로는 두 번 주지 않는다', () async {
      final w = TokenWallet();
      await w.load();
      final day = DateTime(2026, 8, 26, 10);
      expect(await w.grantAdReward(rewardId: 'same', now: day), isTrue);
      expect(await w.grantAdReward(rewardId: 'same', now: day), isFalse);
      expect(w.balanceOf(TokenKind.boost), 4);
      expect(w.adRewardsLeftToday(now: day), 1, reason: '거부된 중복은 캡을 소모하지 않는다');
    });

    test('캡·중복 기록은 앱을 다시 켜도 남는다', () async {
      final a = TokenWallet();
      await a.load();
      final day = DateTime(2026, 8, 26, 10);
      await a.grantAdReward(rewardId: 'a', now: day);
      await a.grantAdReward(rewardId: 'b', now: day);

      final b = TokenWallet();
      await b.load();
      expect(b.adRewardsLeftToday(now: day), 0);
      expect(await b.grantAdReward(rewardId: 'a', now: day), isFalse);
      expect(b.balanceOf(TokenKind.boost), 5);
    });

    test('정책으로 광고 보상을 끌 수 있다(캡 0)', () async {
      final w = TokenWallet(policy: const TokenGrantPolicy(adDailyCap: 0));
      await w.load();
      expect(w.adRewardsLeftToday(), 0);
      expect(await w.grantAdReward(rewardId: 'a'), isFalse);
    });
  });

  group('Monetization.watchAdForBoost', () {
    Future<Monetization> make(List<AdShowResult> script) async {
      final m = Monetization(
        purchases: StubPurchaseService(),
        rewardedAds: StubRewardedAdService(scripted: script),
      );
      await m.startAsync();
      return m;
    }

    test('끝까지 봤을 때만 지급한다 — 이탈·실패·미준비는 0', () async {
      final m = await make([
        AdShowResult.dismissed,
        AdShowResult.failed,
        AdShowResult.notReady,
        AdShowResult.rewarded,
      ]);
      final before = m.wallet.balanceOf(TokenKind.boost);

      expect(await m.watchAdForBoost(), AdRewardOutcome.dismissed);
      expect(m.wallet.balanceOf(TokenKind.boost), before,
          reason: '중간 이탈에 주면 광고 수익 없이 토큰만 샌다');
      expect(await m.watchAdForBoost(), AdRewardOutcome.failed);
      expect(m.wallet.balanceOf(TokenKind.boost), before);
      expect(await m.watchAdForBoost(), AdRewardOutcome.notReady);
      expect(m.wallet.balanceOf(TokenKind.boost), before);

      expect(await m.watchAdForBoost(), AdRewardOutcome.rewarded);
      expect(m.wallet.balanceOf(TokenKind.boost), before + 1);
    });

    test('캡에 닿으면 광고를 띄우지도 않는다', () async {
      final ads = StubRewardedAdService(scripted: [
        AdShowResult.rewarded,
        AdShowResult.rewarded,
        AdShowResult.rewarded
      ]);
      final m =
          Monetization(purchases: StubPurchaseService(), rewardedAds: ads);
      await m.startAsync();
      final day = DateTime(2026, 8, 26, 10);
      expect(await m.watchAdForBoost(now: day), AdRewardOutcome.rewarded);
      expect(await m.watchAdForBoost(now: day), AdRewardOutcome.rewarded);
      expect(await m.watchAdForBoost(now: day), AdRewardOutcome.capReached);
      expect(ads.shows, 2, reason: '줄 수 없는데 광고를 보여주면 사용자를 속이는 것이다');
    });

    test('동시에 두 번 누르면 두 번째는 busy — 광고는 한 번만 뜬다', () async {
      final ads = StubRewardedAdService(
          scripted: [AdShowResult.rewarded, AdShowResult.rewarded]);
      final m =
          Monetization(purchases: StubPurchaseService(), rewardedAds: ads);
      await m.startAsync();
      final before = m.wallet.balanceOf(TokenKind.boost);
      final results =
          await Future.wait([m.watchAdForBoost(), m.watchAdForBoost()]);
      expect(results,
          containsAll([AdRewardOutcome.rewarded, AdRewardOutcome.busy]));
      expect(m.wallet.balanceOf(TokenKind.boost), before + 1);
    });

    test('노출 뒤에는 다음 광고를 다시 준비한다', () async {
      final m = await make([AdShowResult.rewarded, AdShowResult.rewarded]);
      expect(m.adReady.value, isTrue);
      await m.watchAdForBoost();
      await Future<void>.delayed(Duration.zero);
      expect(m.adReady.value, isTrue, reason: '두 번째 광고가 준비되지 않으면 버튼이 죽은 채 남는다');
    });
  });

  group('상점 화면 + 목 광고', () {
    // 홈 화면의 로티가 무한 반복이라 pumpAndSettle은 끝나지 않는다 — 고정 시간으로 흘린다.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<Monetization> pumpShop(WidgetTester tester) async {
      // 첫 실행 튜토리얼이 상점 위를 덮지 않게, 그리고 카드가 스크롤 없이 보이게 세로로 길게.
      SharedPreferences.setMockInitialValues(
          {'settings.seenHowToPlay.v1': true});
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final m = Monetization(
        purchases: StubPurchaseService(),
        rewardedAds: StubRewardedAdService(), // presenter는 앱이 꽂는다(목 광고 화면)
      );
      // FakeAsync 안에서 dispose(스트림 close)를 await하면 끝나지 않는다 — 테스트 밖에서 정리.
      addTearDown(m.dispose);
      await tester.pumpWidget(ScorePokerApp(monetization: m));
      await settle(tester);
      // 홈 → 상점
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
      await settle(tester);
      return m;
    }

    testWidgets('현황 표시: 오늘 2/2 → 광고 완주 → 1/2, 잔량 +1', (tester) async {
      final m = await pumpShop(tester);
      expect(find.byKey(const ValueKey('ad-left-today')), findsOneWidget);
      expect(find.textContaining('2/2'), findsOneWidget);
      final before = m.wallet.balanceOf(TokenKind.boost);
      await tester.tap(find.byKey(const ValueKey('ad-watch')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ad-countdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('ad-claim')), findsNothing,
          reason: '카운트다운 전엔 보상 버튼이 없다');

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(find.byKey(const ValueKey('ad-claim')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ad-claim')));
      await settle(tester);

      expect(m.wallet.balanceOf(TokenKind.boost), before + 1);
      expect(find.textContaining('1/2'), findsOneWidget);
    });

    testWidgets('중간에 닫으면(X) 아무것도 주지 않고 현황도 그대로', (tester) async {
      final m = await pumpShop(tester);
      final before = m.wallet.balanceOf(TokenKind.boost);

      await tester.tap(find.byKey(const ValueKey('ad-watch')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('ad-close')));
      await settle(tester);

      expect(m.wallet.balanceOf(TokenKind.boost), before,
          reason: '끝까지 안 봤는데 주면 안 된다');
      expect(find.textContaining('2/2'), findsOneWidget);
    });

    testWidgets('뒤로가기로 빠져나가도 이탈로 처리한다', (tester) async {
      final m = await pumpShop(tester);
      final before = m.wallet.balanceOf(TokenKind.boost);

      await tester.tap(find.byKey(const ValueKey('ad-watch')));
      await settle(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await settle(tester);

      expect(find.byKey(const ValueKey('ad-countdown')), findsNothing,
          reason: '광고 화면이 닫혀야 한다');
      expect(m.wallet.balanceOf(TokenKind.boost), before);
    });
  });
}
