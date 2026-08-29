import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/ai.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/scoring.dart';

/// [m]을 실제로 적용한다 — 불법 수면 도메인이 던진다(그 자체가 검증).
void apply(ScoreGame g, PlayerId p, TurnMove m) {
  switch (m) {
    case MovePlace(:final handIndex, :final row, :final hidden, :final wildAs):
      if (wildAs != null) {
        g.placeWild(p, handIndex, row, wildAs, hidden: hidden);
      } else {
        g.place(p, handIndex, row, hidden: hidden);
      }
    case MoveAttack(:final handIndex, :final row, :final col):
      g.attack(p, handIndex, row, col);
    case MovePeek(:final row, :final col):
      g.peek(p, row, col);
    case MoveShield(:final ownField, :final row):
      g.placeShield(p, ownField, row);
    case MoveBurnShield():
      g.burnShield(p);
    case MoveDiscard(:final handIndex):
      g.discard(p, handIndex);
  }
}

/// 한 판 자가대전 — p0 관점 결과.
MatchOutcome selfPlay(int seed, VeiledAi a, VeiledAi b) {
  final g = ScoreGame.deal(seed: seed);
  final bots = {PlayerId.p0: a, PlayerId.p1: b};
  var guard = 0;
  while (!g.isFinished && guard++ < 500) {
    final p = g.turn;
    apply(g, p, bots[p]!.chooseTurn(g, p));
  }
  g.revealAll();
  return g.judge().outcome;
}

void main() {
  test('모든 기풍·레벨이 판을 끝까지 합법으로 둔다', () {
    for (final style in AiStyle.values) {
      for (final level in [1, 3, 5]) {
        final g = ScoreGame.deal(seed: style.index * 10 + level);
        final bot = VeiledAi(style, level: level, seed: 1);
        final opp = VeiledAi(AiStyle.clode, level: 3, seed: 2);
        var guard = 0;
        while (!g.isFinished && guard++ < 500) {
          final p = g.turn;
          final ai = p == PlayerId.p1 ? bot : opp;
          apply(g, p, ai.chooseTurn(g, p)); // 불법 수면 여기서 throw
        }
        expect(g.isFinished, isTrue, reason: '$style L$level 판이 안 끝남');
      }
    }
  });

  test('레벨 5가 레벨 1을 이긴다(30판 다수결)', () {
    var strong = 0, weak = 0;
    for (var i = 0; i < 30; i++) {
      final out = selfPlay(
        100 + i,
        VeiledAi(AiStyle.clode, level: 5, seed: i),
        VeiledAi(AiStyle.clode, level: 1, seed: i + 1),
      );
      if (out == MatchOutcome.win) strong++;
      if (out == MatchOutcome.lose) weak++;
    }
    expect(strong, greaterThan(weak),
        reason: '레벨 5 승수($strong)가 레벨 1 승수($weak)보다 많아야 한다');
  });

  test('레벨 4+는 방어막을 상대 줄에도 꽂는다(괴롭히기)', () {
    var harass = false;
    for (var seed = 0; seed < 60 && !harass; seed++) {
      final g = ScoreGame.deal(seed: seed);
      final bot = VeiledAi(AiStyle.grok, level: 5, seed: seed);
      final opp = VeiledAi(AiStyle.clode, level: 3, seed: seed + 1);
      var guard = 0;
      while (!g.isFinished && guard++ < 500) {
        final p = g.turn;
        final ai = p == PlayerId.p1 ? bot : opp;
        final m = ai.chooseTurn(g, p);
        if (p == PlayerId.p1 && m is MoveShield && !m.ownField) harass = true;
        apply(g, p, m);
      }
    }
    expect(harass, isTrue, reason: '그록 L5는 괴롭히기 방어막을 쓴다');
  });

  test('공격이 실제로 나온다(가치 공격 봇)', () {
    var attacks = 0;
    for (var seed = 0; seed < 10; seed++) {
      final g = ScoreGame.deal(seed: seed);
      final a = VeiledAi(AiStyle.het, level: 4, seed: seed);
      final b = VeiledAi(AiStyle.het, level: 4, seed: seed + 1);
      var guard = 0;
      while (!g.isFinished && guard++ < 500) {
        final p = g.turn;
        final m = (p == PlayerId.p0 ? a : b).chooseTurn(g, p);
        if (m is MoveAttack) attacks++;
        apply(g, p, m);
      }
    }
    expect(attacks, greaterThan(0), reason: '10판 안에 공격이 나와야 한다');
  });

  test('조커는 언젠가 와일드로 쓰인다', () {
    var wild = false;
    for (var seed = 0; seed < 30 && !wild; seed++) {
      final g = ScoreGame.deal(seed: seed);
      final a = VeiledAi(AiStyle.clode, level: 2, seed: seed); // 낮은 레벨 = 즉시 사용
      final b = VeiledAi(AiStyle.clode, level: 2, seed: seed + 1);
      var guard = 0;
      while (!g.isFinished && guard++ < 500) {
        final p = g.turn;
        final m = (p == PlayerId.p0 ? a : b).chooseTurn(g, p);
        if (m is MovePlace && m.wildAs != null) wild = true;
        apply(g, p, m);
      }
    }
    expect(wild, isTrue);
  });
}
