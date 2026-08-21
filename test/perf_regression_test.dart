import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/widgets/card_face.dart';

/// 성능 회귀 방지 — **시간을 재지 않고** 구조를 검증한다(기계마다 흔들리지 않게).
///
/// 여기서 막는 것:
/// 1. 카드 위젯이 매 프레임 새 인스턴스로 만들어지는 것
///    → Flutter는 `child.widget == newWidget`이면 서브트리를 건너뛰므로, 같은 카드는
///      같은 인스턴스여야 코너 랭크 텍스트를 다시 레이아웃하지 않는다.
/// 2. build() 안에서 GlobalKey를 새로 만드는 것
///    → 키가 바뀌면 엘리먼트가 매 프레임 파괴·재생성된다.
void main() {
  group('카드 위젯 인스턴스 캐시', () {
    test('같은 (카드, 크기)는 동일한 인스턴스를 돌려준다', () {
      const a = PlayingCard(7, Suit.hearts);
      const b = PlayingCard(7, Suit.hearts);
      expect(identical(cachedCardFace(a, 50), cachedCardFace(b, 50)), isTrue,
          reason: '인스턴스가 달라지면 서브트리 리빌드를 못 건너뛴다');
      expect(identical(cachedCardBack(50), cachedCardBack(50)), isTrue);
    });

    test('카드나 크기가 다르면 다른 인스턴스', () {
      const a = PlayingCard(7, Suit.hearts);
      const b = PlayingCard(7, Suit.spades);
      expect(identical(cachedCardFace(a, 50), cachedCardFace(b, 50)), isFalse);
      expect(identical(cachedCardFace(a, 50), cachedCardFace(a, 51)), isFalse);
    });

    test('크기가 계속 달라져도 캐시가 무한히 커지지 않는다', () {
      const c = PlayingCard(7, Suit.hearts);
      for (var i = 0; i < 2000; i++) {
        cachedCardFace(c, 10 + i * 0.5);
      }
      // 상한을 넘으면 통째로 비우므로, 마지막 항목은 여전히 캐시된다.
      expect(identical(cachedCardFace(c, 60), cachedCardFace(c, 60)), isTrue);
    });
  });

  testWidgets('손패 GlobalKey는 리빌드해도 그대로 유지된다', (tester) async {
    final g = ScoreGame.deal(seed: 5);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(initialGame: g),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    List<Key?> handKeys() => tester
        .widgetList(find.byType(CardFace))
        .map((w) => (w as CardFace).key)
        .toList();

    // 손패 카드가 붙어 있는 엘리먼트의 동일성을 본다.
    final before = tester.elementList(find.byType(CardFace)).toList();
    final beforeKeys = handKeys();

    final state = tester.state<State>(find.byType(GameScreen));
    for (var i = 0; i < 3; i++) {
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      await tester.pump();
    }

    final after = tester.elementList(find.byType(CardFace)).toList();
    expect(after.length, before.length);
    expect(handKeys(), beforeKeys);
    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isTrue,
          reason: '리빌드마다 엘리먼트가 재생성되고 있다 — build()에서 GlobalKey를 '
              '새로 만들고 있지 않은지 확인할 것');
    }
  });
}
