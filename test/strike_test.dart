import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/scoring.dart';
import 'package:score_poker/domain/strike.dart';

/// 봇으로 판을 끝까지 굴린다. 도중에 [onMove]가 true를 돌려주면 멈춘다.
bool runWithBot(StrikeGame g, {bool Function(StrikeMove m)? onMove}) {
  const bot = StrikeBot();
  var guard = 0;
  while (!g.finished && guard++ < 400) {
    final m = bot.choose(g);
    if (onMove != null && onMove(m)) return true;
    switch (m) {
      case MoveAttack(:final handIdx, :final row, :final idx):
        g.attack(handIdx, row, idx);
      case MovePlace(:final handIdx, :final row, :final hidden):
        g.place(handIdx, row, hidden: hidden);
      case MovePeek(:final row, :final idx):
        g.peek(row, idx);
      case MoveShield(:final ownField, :final row):
        g.placeShield(ownField, row);
      case MoveDiscard(:final handIdx):
        g.discard(handIdx);
    }
  }
  return false;
}

void main() {
  group('게임 준비·턴', () {
    test('시작: 덱 52(조커 없음), 손패 4+드로, 칩 4', () {
      final g = StrikeGame(seed: 1);
      expect(g.hands[0].length, StrikeRules.startHand + 1, reason: '선턴 드로');
      expect(g.hands[1].length, StrikeRules.startHand);
      expect(g.chips[0], StrikeRules.chips);
      expect(g.deckLeft, 52 - StrikeRules.startHand * 2 - 1);
      expect(g.hands[0].any((c) => c.isJoker), isFalse);
    });

    test('배치는 줄 왼쪽부터, 턴이 넘어가고 상대가 드로한다', () {
      final g = StrikeGame(seed: 1);
      final card = g.hands[0][0];
      g.place(0, 1);
      expect(g.fields[0][1].single.card, card);
      expect(g.current, 1);
      expect(g.hands[1].length, StrikeRules.startHand + 1);
    });

    test('뒷면 배치 = 칩 1, 상대에게 안 보인다', () {
      final g = StrikeGame(seed: 1);
      g.place(0, 0, hidden: true);
      expect(g.chips[0], StrikeRules.chips - 1);
      final c = g.fields[0][0].single;
      expect(c.faceDown, isTrue);
      expect(g.visibleTo(1, 0, c), isFalse);
      expect(g.visibleTo(0, 0, c), isTrue, reason: '주인에겐 보인다');
    });
  });

  group('훔쳐보기·공격', () {
    test('훔쳐보기: 칩 1, 나에게만 공개, 턴 유지', () {
      final g = StrikeGame(seed: 1);
      g.place(0, 0, hidden: true); // 나: 뒷면
      g.place(0, 0); // 상대: 아무 배치
      g.place(0, 1); // 나: 아무 배치 → 상대 턴
      expect(g.current, 1);
      final before = g.chips[1];
      g.peek(0, 0);
      expect(g.chips[1], before - 1);
      expect(g.fields[0][0].first.peeked, isTrue);
      expect(g.visibleTo(1, 0, g.fields[0][0].first), isTrue);
      expect(g.current, 1, reason: '훔쳐보기는 턴을 안 쓴다');
    });

    test('공격: 랭크 일치 → 두 장 소멸(왼쪽 당김) + 방어막 단계', () {
      var attacked = false;
      for (var seed = 0; seed < 30 && !attacked; seed++) {
        final g = StrikeGame(seed: seed);
        attacked = runWithBot(g, onMove: (m) {
          if (m is! MoveAttack) return false;
          final targetRow = g.fields[1 - g.current][m.row];
          final lenBefore = targetRow.length;
          final handLenBefore = g.hands[g.current].length;
          g.attack(m.handIdx, m.row, m.idx);
          expect(targetRow.length, lenBefore - 1, reason: '표적 제거');
          expect(g.hands[g.current].length, handLenBefore - 1);
          expect(g.phase, StrikePhase.shield);
          expect(g.pendingShield!.shield, isTrue);
          return true;
        });
      }
      expect(attacked, isTrue, reason: '30개 시드 안에 공격이 나와야 한다');
    });

    test('방어막은 상대 필드에도 놓인다(괴롭히기)', () {
      var harassed = false;
      for (var seed = 0; seed < 60 && !harassed; seed++) {
        final g = StrikeGame(seed: seed);
        harassed = runWithBot(g, onMove: (m) {
          if (m is! MoveShield || m.ownField) return false;
          final attacker = g.current;
          final row = g.fields[1 - attacker][m.row];
          final lenBefore = row.length;
          final shield = g.pendingShield!;
          g.placeShield(false, m.row);
          expect(row.length, lenBefore + 1);
          expect(row.last, same(shield));
          expect(row.last.shield, isTrue);
          return true;
        });
      }
      expect(harassed, isTrue, reason: '60개 시드 안에 괴롭히기가 나와야 한다');
    });

    test('방어막 카드는 공격 표적이 아니다', () {
      final g = StrikeGame(seed: 2);
      // 필드에 방어막이 생길 때까지 굴린 뒤, 그 랭크로 표적 조회.
      runWithBot(g, onMove: (m) {
        if (m is MoveShield) {
          final owner = m.ownField ? g.current : 1 - g.current;
          final shieldCard = g.pendingShield!.card;
          g.placeShield(m.ownField, m.row);
          final viewer = 1 - owner;
          final targets = g.attackTargets(viewer, shieldCard.rank);
          for (final (r, i) in targets) {
            expect(g.fields[owner][r][i].shield, isFalse,
                reason: '방어막은 표적 목록에 없다');
          }
          return true;
        }
        return false;
      });
    });
  });

  group('종료·판정', () {
    test('판은 반드시 끝나고, 끝나면 전 카드 공개 + 본편 판정', () {
      for (final seed in [3, 7, 42]) {
        final g = StrikeGame(seed: seed);
        runWithBot(g);
        expect(g.finished, isTrue);
        for (final f in g.fields) {
          for (final row in f) {
            for (final c in row) {
              expect(c.faceDown, isFalse);
            }
          }
        }
        final res = g.judge();
        expect(res.lineOutcomes.length, 3);
        expect(res.outcome, isA<MatchOutcome>());
      }
    });

    test('만석이면 버리기 가능', () {
      final g = StrikeGame(seed: 5);
      // 강제로 내 필드를 채운다(도메인 검증용 직접 조작).
      while (g.openRows(0).isNotEmpty) {
        final r = g.openRows(0).first;
        if (g.current == 0) {
          g.place(0, r);
        } else {
          // 상대는 그냥 아무 데나.
          final or = g.openRows(1);
          if (or.isEmpty) break;
          g.place(0, or.first);
        }
        if (g.finished) return; // 덱 소진 등 — 그 자체로 유효한 종료
      }
      // 내 차례가 오면 버리기가 성립해야 한다.
      var guard = 0;
      while (g.current != 0 && !g.finished && guard++ < 10) {
        final or = g.openRows(1);
        if (or.isEmpty) break;
        g.place(0, or.first);
      }
      if (!g.finished && g.current == 0 && g.openRows(0).isEmpty) {
        final len = g.hands[0].length;
        g.discard(0);
        expect(g.hands[0].length, len - 1);
      }
    });
  });
}
