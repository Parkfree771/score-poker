import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/card.dart';
import '../theme.dart';
import 'card_back.dart';
import 'suit_glyphs.dart';

String rankLabel(int rank) => switch (rank) {
      Ranks.jack => 'J',
      Ranks.queen => 'Q',
      Ranks.king => 'K',
      Ranks.ace => 'A',
      _ => '$rank',
    };

const String _inkHex = '#121330';

/// 카드 한 장: **lordicon 카드 프레임(SVG) 그대로** + 코너 랭크 + 가운데 무늬(작게).
///
/// **성능**: 여러 장을 동시에 그리는 곳(보드·손패)에서는 [cachedCardFace]로 만들 것.
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card, required this.size});

  final PlayingCard card;
  final double size; // 카드 폭

  static double heightFor(double size) => size * 1.36;


  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = heightFor(size);
    final red = suitIsRed(card.suit);
    final ink = red ? AppColors.red : AppColors.dark;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          // 은은한 그림자 (밝은 배경에서 카드가 떠 보이게)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(w * 0.04),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w * 0.16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.16),
                      blurRadius: w * 0.09,
                      offset: Offset(0, w * 0.045),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 카드 프레임 (lordicon 원본).
          Positioned.fill(
            child: SvgPicture(cardFrameLoader(_inkHex), fit: BoxFit.fill),
          ),
          // 가운데 무늬
          Align(
            alignment: const Alignment(0, -0.02),
            child: SizedBox(
              width: w * 0.38,
              height: w * 0.38,
              child: SvgPicture(suitLoader(card.suit), fit: BoxFit.contain),
            ),
          ),
          // 코너 랭크
          Positioned(left: w * 0.13, top: h * 0.04, child: _rank(ink, w)),
          Positioned(
            right: w * 0.13,
            bottom: h * 0.04,
            child: Transform.rotate(angle: 3.14159, child: _rank(ink, w)),
          ),
        ],
      ),
    );
  }

  Widget _rank(Color ink, double w) => Text(
        rankLabel(card.rank),
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: w * 0.27, height: 1),
      );
}

// ---- 위젯 인스턴스 캐시 ----
//
// Flutter는 `child.widget == newWidget`이면 그 서브트리 리빌드를 통째로 건너뛴다.
// Widget의 `==`는 @nonVirtual이라 값 비교로 재정의할 수 없으므로(프레임워크가 위젯의
// 동일성에 의존한다), **같은 인스턴스를 재사용**해 같은 효과를 낸다.
//
// 보드 30칸 + 손패가 매 프레임 코너 랭크 텍스트 2개씩을 다시 레이아웃하던 비용이 사라진다.
// (측정: 게임화면 리빌드 프레임당 세로 16.3ms → 7.3ms)
//
// 카드 종류(58) × 실제로 쓰이는 크기(수 종)라 캐시는 작게 유지되지만, 오프닝처럼 화면
// 크기에서 계산한 연속적인 size가 들어올 수 있으므로 상한을 두고 넘치면 통째로 비운다.

const int _faceCacheLimit = 256;
final Map<(PlayingCard, double), CardFace> _faceCache = {};

/// 같은 (카드, 크기)면 **같은 위젯 인스턴스**를 돌려준다 → 부모가 리빌드돼도 서브트리를 건너뛴다.
///
/// 키를 붙여야 하거나 한 번만 그리는 곳에서는 그냥 `CardFace(...)`를 쓰면 된다.
CardFace cachedCardFace(PlayingCard card, double size) {
  final key = (card, size);
  final hit = _faceCache[key];
  if (hit != null) return hit;
  if (_faceCache.length >= _faceCacheLimit) _faceCache.clear();
  return _faceCache[key] = CardFace(card: card, size: size);
}

const int _backCacheLimit = 32;
final Map<double, CardBack> _backCache = {};

/// [cachedCardFace]의 뒷면 버전.
CardBack cachedCardBack(double size) {
  final hit = _backCache[size];
  if (hit != null) return hit;
  if (_backCache.length >= _backCacheLimit) _backCache.clear();
  return _backCache[size] = CardBack(size: size);
}
