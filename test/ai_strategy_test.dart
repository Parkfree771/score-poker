import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai_strategy.dart';
import 'package:score_poker/domain/game.dart';

void _apply(GameState s, AiMove m) {
  switch (m) {
    case FoldMove():
      s.fold();
    case PlaceMove(:final handIndex, :final target, :final row, :final col, :final jokerRank, :final jokerSuit):
      s.placeCard(handIndex, target, row, col, jokerRank: jokerRank, jokerSuit: jokerSuit);
    case RemoveMove(:final handIndex, :final row, :final col):
      s.removeOpponentCard(handIndex, row, col);
  }
}

void main() {
  for (final (name, style) in [
    ('크로드', AiStyle.clode),
    ('헷', AiStyle.het),
    ('제나', AiStyle.jenna),
  ]) {
    test('$name 기풍 AI는 합법 수만 두고 게임을 끝까지 완주한다', () {
      for (var seed = 1; seed <= 5; seed++) {
        final s = GameState.deal(seed: seed);
        s.revealForFirstTurn(0, 0);
        final ai = {
          PlayerId.p0: HeuristicAi(style, seed: seed),
          PlayerId.p1: HeuristicAi(style, seed: seed + 100),
        };
        var turns = 0;
        while (!s.isFinished && turns < 300) {
          final mover = s.current;
          final move = ai[mover]!.decide(s, mover);
          // IllegalMove가 던져지면 테스트 실패
          _apply(s, move);
          turns++;
        }
        expect(s.isFinished, isTrue, reason: 'seed $seed: $turns턴 안에 안 끝남');
      }
    });
  }

  test('공격형(헷)은 수비형(크로드)보다 제거 수를 더 많이 시도한다', () {
    var hetRemoves = 0, clodeRemoves = 0;
    for (var seed = 1; seed <= 5; seed++) {
      for (final (style, counter) in [(AiStyle.het, true), (AiStyle.clode, false)]) {
        final s = GameState.deal(seed: seed);
        s.revealForFirstTurn(0, 0);
        final me = HeuristicAi(style, seed: seed);
        final other = HeuristicAi(AiStyle.clode, seed: seed + 50);
        var turns = 0;
        while (!s.isFinished && turns < 300) {
          final mover = s.current;
          final move = (mover == PlayerId.p0 ? me : other).decide(s, mover);
          if (mover == PlayerId.p0 && move is RemoveMove) {
            if (counter) {
              hetRemoves++;
            } else {
              clodeRemoves++;
            }
          }
          _apply(s, move);
          turns++;
        }
      }
    }
    expect(hetRemoves, greaterThanOrEqualTo(clodeRemoves));
  });
}
