import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';

/// **목(mock) 보상형 광고** — 실제 광고 SDK가 붙기 전까지의 예시 화면.
///
/// 실제 광고와 같은 규칙을 흉내 낸다:
/// - 카운트다운이 끝나기 전에 닫으면(X·뒤로가기) → `false` = 이탈, 보상 없음
/// - 끝까지 보고 "보상 받기"를 누르면 → `true`
///
/// 돌려주는 값은 "끝까지 봤는가"뿐이다. 지급은 여기서 하지 않는다
/// (`Monetization.watchAdForBoost`가 결과를 받아 지갑에 한 번만 넣는다).
Future<bool> showMockRewardedAd(NavigatorState navigator,
    {Duration length = const Duration(seconds: 5)}) async {
  final r = await navigator.push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _MockRewardedAdPage(length: length),
  ));
  return r ?? false; // 뒤로가기 등으로 결과 없이 닫힘 = 이탈
}

class _MockRewardedAdPage extends StatefulWidget {
  const _MockRewardedAdPage({required this.length});
  final Duration length;

  @override
  State<_MockRewardedAdPage> createState() => _MockRewardedAdPageState();
}

class _MockRewardedAdPageState extends State<_MockRewardedAdPage> {
  late int _left = widget.length.inSeconds;
  Timer? _timer;

  bool get _done => _left <= 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_done) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 뒤로가기는 그냥 닫히게 둔다 — 결과 없는 pop은 호출한 쪽에서 false(이탈)로 본다.
    return Scaffold(
      backgroundColor: const Color(0xFF111114),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.adMockLabel,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 28),
                  const Icon(Icons.play_circle_outline_rounded,
                      size: 96, color: Colors.white24),
                  const SizedBox(height: 18),
                  Text(l10n.adMockBody,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 32),
                  if (_done)
                    FilledButton.icon(
                      key: const ValueKey('ad-claim'),
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l10n.adMockClaim,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    )
                  else
                    Text(l10n.adMockCountdown(_left),
                        key: const ValueKey('ad-countdown'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            // 닫기(이탈)는 언제나 가능하다 — 실제 광고와 같다.
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                key: const ValueKey('ad-close'),
                tooltip: l10n.adMockClose,
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
