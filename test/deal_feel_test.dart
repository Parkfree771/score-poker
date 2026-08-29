import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/audio/sfx.dart';
import 'package:score_poker/feedback/haptics.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/ui/game_screen.dart';

/// 딜링의 **소리 타이밍**을 지킨다.
///
/// 카드가 손에 닿는 프레임과 "착"이 어긋나면 딜링 전체가 싸구려로 들린다.
/// 여기서 검증하는 계약:
/// 1. 내 손에 카드가 들어오는 **그 프레임**에 소리와 햅틱이 같이 난다.
/// 2. 상대에게 가는 카드는 **무음**(애니메이션만) — 100ms 차로 겹치면 뭉개진다.
/// 3. 내 6장이 한 장에 한 번씩 — 한 방 "촤르륵"이 아니다.
class _RecordingSfx extends SfxService {
  final List<Sfx> played = [];

  @override
  void play(Sfx sfx, {int? variant}) => played.add(sfx);
}

class _RecordingHaptics extends HapticService {
  final List<Haptic> played = [];

  @override
  void play(Haptic haptic) => played.add(haptic);
}

void main() {
  testWidgets('딜링: 내 카드만 소리 + 햅틱, 상대 카드는 무음', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sfx = _RecordingSfx();
    final haptics = _RecordingHaptics();
    await tester.pumpWidget(SfxScope(
      service: sfx,
      child: HapticScope(
        service: haptics,
        child: const MaterialApp(
          locale: Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(seed: 3),
        ),
      ),
    ));

    // 딜링 연출이 끝날 때까지만(약 1.5초). 더 흘리면 AI가 카드를 놓기 시작해
    // 그 소리까지 섞인다 — 여기서 재는 것은 딜링뿐이다.
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final deals = sfx.played.where((e) => e == Sfx.cardPlace).toList();
    // 내 손에 들어온 5장(시작 4 + 첫 드로)만 운다(상대 4장은 무음).
    expect(deals.length, 5);
    // 내 카드가 손에 닿을 때마다 손끝의 톡.
    expect(haptics.played.where((h) => h == Haptic.select).length,
        greaterThanOrEqualTo(5));

    // 타이머·AI 예약을 끝까지 흘려 보낸다(살아 있는 타이머가 남으면 실패한다).
    for (var i = 0; i < 1600; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
