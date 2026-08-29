import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/tribattle.dart';

TriCard c(int rank, [TriElement e = TriElement.water]) => TriCard(rank, e);

void main() {
  group('조합 판정', () {
    test('열: 페어/트리플/풀하우스/포카드/파이브', () {
      expect(colCombo([c(3), c(3)]), TriCombo.pair);
      expect(colCombo([c(3), c(3), c(3)]), TriCombo.trips);
      expect(colCombo([c(3), c(3), c(3), c(7), c(7)]), TriCombo.fullHouse);
      expect(colCombo([c(3), c(3), c(3), c(3), c(7)]), TriCombo.quad);
      expect(colCombo([c(3), c(3), c(3), c(3), c(3)]), TriCombo.five);
    });

    test('열: 연속 — 3연속과 5연속, 순서 무관', () {
      expect(colCombo([c(5), c(3), c(4)]), TriCombo.straight3);
      expect(colCombo([c(7), c(3), c(4), c(5), c(6)]), TriCombo.straight5);
      // 연속 3 + 페어면 더 높은 쪽(트리플 아님 — 페어보다 연속3이 위).
      expect(colCombo([c(3), c(4), c(5), c(9), c(9)]), TriCombo.straight3);
    });

    test('행: 트리플 > 연속 > 페어', () {
      expect(rowCombo([c(4), c(4), c(4)]), TriCombo.trips);
      expect(rowCombo([c(4), c(5), c(6)]), TriCombo.straight3);
      expect(rowCombo([c(4), c(4), c(9)]), TriCombo.pair);
    });
  });

  group('점수', () {
    test('열 점수 = 합 × 배율', () {
      expect(colScore([c(3), c(3)]), 6 * TriRules.colPair);
      // 원소를 섞어 플러시 없이 파이브만.
      expect(
          colScore([
            c(2),
            c(2, TriElement.fire),
            c(2),
            c(2, TriElement.forest),
            c(2)
          ]),
          10 * TriRules.colFive);
    });

    test('플러시는 줄이 가득 찼을 때만 — 열 5장 원소 통일 ×2', () {
      final flush = [for (var i = 1; i <= 5; i++) c(i, TriElement.fire)];
      expect(colScore(flush), 15 * TriRules.colStraight5 * TriRules.flushCol);
      // 4장까지는 플러시 미인정.
      expect(colScore(flush.sublist(0, 4)),
          (1 + 2 + 3 + 4) * TriRules.colStraight3);
    });
  });

  group('게임 진행', () {
    test('시작: 패 2장 + 첫 드로 = 선턴 3장, 코인 5', () {
      final g = TriGame(seed: 1);
      expect(g.hands[0].length, TriRules.startHand + 1);
      expect(g.hands[1].length, TriRules.startHand);
      expect(g.coins[0], TriRules.startCoins);
      expect(g.deckLeft, 81 - TriRules.startHand * 2 - 1);
    });

    test('배치는 아래부터 쌓이고 턴이 넘어간다', () {
      final g = TriGame(seed: 1);
      g.place(0, 0);
      expect(g.boards[0].cols[0].length, 1);
      expect(g.current, 1);
      expect(g.hands[1].length, TriRules.startHand + 1, reason: '상대 드로');
    });

    test('뒷면 배치는 코인 1 소모 + 상대에게 안 보임', () {
      final g = TriGame(seed: 1);
      g.place(0, 0, faceDown: true);
      expect(g.coins[0], TriRules.startCoins - 1);
      final card = g.boards[0].cols[0][0];
      expect(card.faceDown, isTrue);
      expect(g.visibleTo(1, card), isFalse);
    });

    test('훔쳐보기: 코인 1로 나에게만 공개, 턴 유지', () {
      final g = TriGame(seed: 1);
      g.place(0, 0, faceDown: true); // 나 → 뒷면
      // 상대 턴을 앞면 배치로 소비.
      g.place(0, 0);
      // 상대(1)가 아니라 내(0) 차례. 내가 상대 카드를 볼 필요는 없으니
      // 상대가 내 뒷면을 훔쳐보는 상황을 만들자: 내 턴 소비.
      g.place(0, 1);
      expect(g.current, 1);
      final target = g.boards[0].cols[0][0];
      final coinsBefore = g.coins[1];
      g.peek(0, 0);
      expect(g.coins[1], coinsBefore - 1);
      expect(target.peeked, isTrue);
      expect(g.visibleTo(1, target), isTrue);
      expect(g.current, 1, reason: '훔쳐보기는 턴을 안 쓴다');
    });

    test('공격: 랭크 일치 → 두 장 소멸 + 방어막 단계', () {
      final g = TriGame(seed: 1);
      // 상대 필드에 카드 하나 만들기.
      g.place(0, 0); // 나
      final placed = g.boards[1].cols.isEmpty;
      expect(placed, isFalse);
      g.place(0, 1); // 상대가 1열에 배치
      final target = g.boards[1].cols[1][0];
      // 내 손에서 같은 랭크를 찾거나, 없으면 배치로 턴을 소비하며 찾는다.
      var guard = 0;
      while (g.phase == TriPhase.action && guard++ < 60) {
        final idx =
            g.hands[g.current].indexWhere((h) => h.rank == target.rank);
        final targets = g.current == 0 && idx >= 0
            ? g.attackTargets(0, target.rank)
            : const <(int, int)>[];
        if (g.current == 0 && idx >= 0 && targets.isNotEmpty) {
          final before = g.boards[1].cols[targets.first.$1].length;
          g.attack(idx, targets.first.$1, targets.first.$2);
          expect(g.boards[1].cols[targets.first.$1].length, before - 1,
              reason: '표적 소멸(중력)');
          expect(g.phase, TriPhase.shield);
          expect(g.pendingShield!.shield, isTrue);
          return;
        }
        // 못 때리면 그냥 배치해서 진행.
        final open = g.boards[g.current].openCols;
        if (open.isEmpty) break;
        g.place(0, open.first);
      }
      fail('60턴 안에 공격 기회가 안 나옴 — 시드 확인');
    });

    test('방어막은 상대 필드에도 놓을 수 있다', () {
      final g = TriGame(seed: 3);
      // 공격 상황을 봇으로 빠르게 만든다.
      const bot = TriBot();
      var guard = 0;
      while (!g.finished && guard++ < 200) {
        final m = bot.choose(g);
        switch (m) {
          case BotAttack(:final handIdx, :final col, :final row):
            g.attack(handIdx, col, row);
            if (g.phase == TriPhase.shield) {
              final slots = g.shieldSlots();
              final oppSlot =
                  slots.where((s) => !s.$1).toList();
              if (oppSlot.isNotEmpty) {
                final before =
                    g.boards[1 - g.current].cols[oppSlot.first.$2].length;
                g.placeShield(false, oppSlot.first.$2);
                // placeShield 후 턴이 넘어가 current가 바뀌었다 — 원래 상대 보드 검사.
                expect(
                    g.boards[g.current].cols[oppSlot.first.$2].length >
                        before,
                    isTrue,
                    reason: '방어막이 상대(=이제 current) 필드에 박혔다');
                return;
              }
              g.placeShield(true, g.shieldSlots().first.$2);
            }
          case BotPlace(:final handIdx, :final col, :final faceDown):
            g.place(handIdx, col, faceDown: faceDown);
          case BotPeek(:final col, :final row):
            g.peek(col, row);
          case BotShield(:final ownField, :final col):
            g.placeShield(ownField, col);
          case BotDiscard(:final handIdx):
            g.discard(handIdx);
        }
      }
      fail('공격+상대 필드 방어막 상황이 안 나옴 — 시드 확인');
    });

    test('판은 끝난다(보드 완성 또는 덱 소진) + 끝나면 전부 공개', () {
      final g = TriGame(seed: 5);
      const bot = TriBot();
      var guard = 0;
      while (!g.finished && guard++ < 500) {
        final m = bot.choose(g);
        switch (m) {
          case BotAttack(:final handIdx, :final col, :final row):
            g.attack(handIdx, col, row);
          case BotPlace(:final handIdx, :final col, :final faceDown):
            g.place(handIdx, col, faceDown: faceDown);
          case BotPeek(:final col, :final row):
            g.peek(col, row);
          case BotShield(:final ownField, :final col):
            g.placeShield(ownField, col);
          case BotDiscard(:final handIdx):
            g.discard(handIdx);
        }
      }
      expect(g.finished, isTrue);
      expect(g.winner, isNotNull);
      for (final b in g.boards) {
        for (final col in b.cols) {
          for (final card in col) {
            expect(card.faceDown, isFalse, reason: '정산 시 전 카드 공개');
          }
        }
      }
    });
  });

  group('매치', () {
    test('진 쪽이 점수차만큼 깎인다', () {
      final g = TriGame(seed: 5);
      const bot = TriBot();
      var guard = 0;
      while (!g.finished && guard++ < 500) {
        final m = bot.choose(g);
        switch (m) {
          case BotAttack(:final handIdx, :final col, :final row):
            g.attack(handIdx, col, row);
          case BotPlace(:final handIdx, :final col, :final faceDown):
            g.place(handIdx, col, faceDown: faceDown);
          case BotPeek(:final col, :final row):
            g.peek(col, row);
          case BotShield(:final ownField, :final col):
            g.placeShield(ownField, col);
          case BotDiscard(:final handIdx):
            g.discard(handIdx);
        }
      }
      final match = TriMatch();
      final (winner, net) = match.applyGame(g);
      final (a, b) = g.scores;
      expect(net, (a - b).abs());
      if (winner == 0) {
        expect(match.hpB, TriRules.hp - net);
        expect(match.hpA, TriRules.hp);
      } else if (winner == 1) {
        expect(match.hpA, TriRules.hp - net);
      }
    });
  });
}
