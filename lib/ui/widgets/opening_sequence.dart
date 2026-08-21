import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../../domain/card.dart';
import '../../domain/game.dart';
import '../../feedback/haptics.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'card_face.dart';

/// 게임 오프닝 연출 (가로/세로 모두 대응).
///
/// 1) **딜링**: 가운데 덱에서 카드가 한 장씩 위(상대)/아래(나)로 부채꼴로 날아간다.
/// 2) **선택**: 내 카드 한 장을 탭 → 가운데(내 쪽)로 나온다. 상대 오픈 카드도 뒤집혀 나온다.
/// 3) **쇼다운**: 두 카드를 맞대 비교 → 이긴(선공) 카드에 골드 글로우 → [onFinished].
class OpeningSequence extends StatefulWidget {
  const OpeningSequence({
    super.key,
    required this.myHand,
    required this.oppHand,
    required this.oppPick,
    required this.decideFirst,
    required this.myName,
    required this.oppName,
    required this.onFinished,
  });

  final List<PlayingCard> myHand;
  final List<PlayingCard> oppHand;
  final int oppPick;
  final PlayerId Function(PlayingCard mine, PlayingCard opp) decideFirst;
  final String myName;
  final String oppName;
  final void Function(int myPickIndex) onFinished;

  @override
  State<OpeningSequence> createState() => _OpeningSequenceState();
}

enum _Stage { dealing, picking, showdown, result }

class _OpeningSequenceState extends State<OpeningSequence> with TickerProviderStateMixin {
  late final AnimationController _deal;
  _Stage _stage = _Stage.dealing;
  int? _myPick;
  PlayerId? _first;

  int get _n => widget.myHand.length;

  @override
  void initState() {
    super.initState();
    _deal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() => _stage = _Stage.picking);
      })
      ..forward();
    // 딜링과 함께 카드가 촤르륵 — 스코프가 없는 환경(테스트·스크린샷)에선 무음.
    context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(Sfx.deal);
  }

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  Future<void> _pick(int i) async {
    if (_stage != _Stage.picking) return;
    context.getInheritedWidgetOfExactType<SfxScope>()?.notifier?.play(Sfx.cardSlide);
    context.getInheritedWidgetOfExactType<HapticScope>()?.notifier?.play(Haptic.select);
    setState(() {
      _myPick = i;
      _first = widget.decideFirst(widget.myHand[i], widget.oppHand[widget.oppPick]);
      _stage = _Stage.showdown;
    });
    await Future<void>.delayed(const Duration(milliseconds: 640));
    if (!mounted) return;
    setState(() => _stage = _Stage.result);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    widget.onFinished(i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final geo = _Geo(cons.maxWidth, cons.maxHeight, _n);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (_stage == _Stage.dealing) _dealerDeck(geo),
            for (var i = 0; i < _n; i++) _card(geo, isMine: false, index: i),
            for (var i = 0; i < _n; i++) _card(geo, isMine: true, index: i),
            // 안내/배너는 카드 위에 — 아래에 두면 좁은 화면에서 카드에 덮인다.
            if (_stage == _Stage.picking) _pickPrompt(geo),
            if (_stage == _Stage.result && _first != null) _firstBanner(geo),
          ],
        );
      },
    );
  }

  Widget _dealerDeck(_Geo geo) {
    final c = geo.dealer;
    return Positioned(
      left: c.dx - geo.cardW / 2,
      top: c.dy - geo.cardH / 2,
      width: geo.cardW,
      height: geo.cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var k = 3; k >= 1; k--)
            Transform.translate(
              offset: Offset(-k * 1.5, -k * 1.5),
              child: Opacity(opacity: 0.45, child: cachedCardBack(geo.cardW)),
            ),
          cachedCardBack(geo.cardW),
        ],
      ),
    );
  }

  Widget _card(_Geo geo, {required bool isMine, required int index}) {
    final card = isMine ? widget.myHand[index] : widget.oppHand[index];
    final isPicked = isMine ? (_myPick == index) : (index == widget.oppPick);
    final slot = geo.slot(isMine: isMine, index: index);

    if (_stage == _Stage.dealing) {
      // 덱 → 슬롯으로 순차 비행(상대/나 번갈아).
      final order = isMine ? index * 2 + 1 : index * 2;
      final start = order * 0.045;
      const dur = 0.42;
      return AnimatedBuilder(
        animation: _deal,
        builder: (context, _) {
          final local = ((_deal.value - start) / dur).clamp(0.0, 1.0);
          final e = Curves.easeOutCubic.transform(local);
          final pos = Offset.lerp(geo.dealer, slot.pos, e)!;
          final scale = 0.5 + 0.5 * e;
          final ang = (1 - e) * 0.6 + slot.angle * e;
          return _positioned(geo, pos, ang, local <= 0 ? 0 : 1, scale,
              child: cachedCardBack(geo.cardW), faceUp: false, real: card, isMine: isMine, showFace: isMine && e > 0.5);
        },
      );
    }

    // picking / showdown / result: 슬롯 또는 가운데(선택 카드).
    final bool toCenter = (_stage == _Stage.showdown || _stage == _Stage.result) && isPicked;
    final center = toCenter ? geo.showdown(isMine: isMine) : slot.pos;
    final angle = toCenter ? 0.0 : slot.angle;
    final faded = (_stage == _Stage.showdown || _stage == _Stage.result) && !isPicked;
    final faceUp = isMine || toCenter; // 상대 오픈 카드는 가운데로 올 때 앞면
    final win = _stage == _Stage.result && isPicked &&
        ((isMine && _first == PlayerId.p0) || (!isMine && _first == PlayerId.p1));

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      left: center.dx - geo.cardW / 2,
      top: center.dy - geo.cardH / 2,
      width: geo.cardW,
      height: geo.cardH,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: faded ? 0 : 1,
        child: AnimatedRotation(
          duration: const Duration(milliseconds: 460),
          turns: angle / (2 * math.pi),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale: toCenter ? geo.showScale * (win ? 1.15 : 1.0) : 1.0,
            child: _glow(
              win,
              geo.cardW,
              GestureDetector(
                onTap: (isMine && _stage == _Stage.picking) ? () => _pick(index) : null,
                child: faceUp ? cachedCardFace(card, geo.cardW) : cachedCardBack(geo.cardW),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 선택 단계: 두 손패 사이 빈 공간에 VS 마크 + 안내 문구를 띄운다.
  Widget _pickPrompt(_Geo geo) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      left: 16,
      right: 16,
      top: geo.h / 2 - geo.promptH / 2,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VS',
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.9),
                    fontSize: geo.landscape ? 34 : 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  )),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.panelStrong,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Text(l10n.revealPrompt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textMain, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 쇼다운 결과: 두 카드 아래 걸치는 골드 배너로 선공을 알린다.
  Widget _firstBanner(_Geo geo) {
    final l10n = AppLocalizations.of(context);
    final name = _first == PlayerId.p0 ? widget.myName : widget.oppName;
    return Positioned(
      left: 0,
      right: 0,
      // 확대된 쇼다운 카드 아래 (겹침 방지)
      top: geo.h / 2 + geo.cardH * geo.showScale * 0.575 + 12,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, t, child) =>
              Opacity(opacity: t, child: Transform.scale(scale: 0.9 + 0.1 * t, child: child)),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.gold, width: 1.4),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14),
                ],
              ),
              child: Text('$name ${l10n.goesFirst}',
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glow(bool on, double w, Widget child) {
    if (!on) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.16),
        boxShadow: [
          BoxShadow(color: AppColors.gold.withValues(alpha: 0.9), blurRadius: 26, spreadRadius: 2),
          BoxShadow(color: AppColors.goldSoft.withValues(alpha: 0.7), blurRadius: 12),
        ],
      ),
      child: child,
    );
  }

  Widget _positioned(_Geo geo, Offset center, double angle, double opacity, double scale,
      {required Widget child, required bool faceUp, required PlayingCard real, required bool isMine, required bool showFace}) {
    return Positioned(
      left: center.dx - geo.cardW / 2,
      top: center.dy - geo.cardH / 2,
      width: geo.cardW,
      height: geo.cardH,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: showFace ? CardFace(card: real, size: geo.cardW) : child,
          ),
        ),
      ),
    );
  }
}

/// 오프닝 레이아웃 좌표(가로/세로 대응).
class _Geo {
  _Geo(this.w, this.h, this.n) {
    landscape = w > h;
    promptH = landscape ? 82.0 : 94.0; // VS 글자 + 안내 알약 블록 높이
    final edge = landscape ? 10.0 : 20.0; // 화면 가장자리 여백
    const pad = 14.0; // VS 블록과 카드 사이 숨통

    // 세로로 [내 손패][VS 블록][상대 손패]가 항상 겹치지 않고 들어가는 최대 카드 폭.
    //   바깥쪽(화면 끝) 여유: 0.62*cardH  — 카드 절반 + 회전 튀어나옴
    //   안쪽(VS 쪽) 여유:   0.60*cardH  — 카드 절반 + 부채꼴 들림(lift 0.10)
    //   h/2 - edge >= 0.62*cardH + promptH/2 + pad  이면서
    //   half(=0.60*cardH + promptH/2 + pad) 도 같은 식을 만족해야 하므로 1.22로 나눈다.
    // 이 상한을 지키면 아래 half 계산에서 두 항이 절대 어긋나지 않는다.
    final fitH = (h / 2 - edge - promptH / 2 - pad) / 1.22;
    cardW = [
      landscape ? 132.0 : 92.0, // 큰 화면에서도 과하게 커지지 않게
      n > 0 ? w * 0.84 / n : 66.0, // 손패가 가로로 넘치지 않게
      fitH / 1.36, // CardFace.heightFor 역산
    ].reduce(math.min);
    cardH = CardFace.heightFor(cardW);

    // 쇼다운은 가운데 두 장뿐 — 남는 폭/높이만큼 키워서 결정적 순간을 크게 보여준다.
    showScale = math.min(w * 0.58 / (cardW * 2), h * 0.34 / cardH).clamp(1.0, 2.0);

    final avail = w * 0.9;
    final maxStep = n > 1 ? (avail - cardW) / (n - 1) : 0.0;
    step = math.min(cardW * 1.02, maxStep);
    // 큰 화면에서 두 손패가 위아래 끝까지 벌어져 가운데가 텅 비던 문제 —
    // 필요한 만큼 벌린 뒤 남는 여유는 1/4만 더 쓴다(끝에 붙지도, 몰리지도 않게).
    final need = cardH * 0.60 + promptH * 0.5 + pad; // VS 블록이 들어갈 최소 간격
    final limit = h / 2 - cardH * 0.62 - edge; // 화면 밖으로 안 나가는 한계
    final half = need + math.max(0.0, limit - need) * 0.25;
    oppY = h / 2 - half;
    myY = h / 2 + half;
    dealer = Offset(w / 2, h / 2);
  }

  final double w, h;
  final int n;
  late final bool landscape;
  late final double cardW, cardH, step, oppY, myY, promptH, showScale;
  late final Offset dealer;

  ({Offset pos, double angle}) slot({required bool isMine, required int index}) {
    final mid = (n - 1) / 2;
    final t = mid == 0 ? 0.0 : (index - mid) / mid; // -1..1
    final lift = (1 - t * t) * cardH * 0.10;
    final x = w / 2 + (index - mid) * step;
    final baseY = isMine ? myY : oppY;
    final y = isMine ? baseY - lift : oppY + lift;
    final angle = (index - mid) * 0.07 * (isMine ? 1 : -1);
    return (pos: Offset(x, y), angle: angle);
  }

  Offset showdown({required bool isMine}) {
    final gap = cardW * showScale * 0.62; // 확대해도 두 장이 겹치지 않는 간격
    return Offset(w / 2 + (isMine ? -gap : gap), h / 2);
  }
}
