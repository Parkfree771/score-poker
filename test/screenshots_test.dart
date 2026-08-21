import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_poker/domain/card.dart';
import 'package:score_poker/domain/deck.dart';
import 'package:score_poker/domain/game.dart';
import 'package:score_poker/domain/records.dart';
import 'package:score_poker/domain/scoring.dart';
import 'package:score_poker/l10n/app_localizations.dart';
import 'package:score_poker/l10n/app_localizations_en.dart';
import 'package:score_poker/l10n/app_localizations_ko.dart';
import 'package:score_poker/ui/game_screen.dart';
import 'package:score_poker/ui/home_screen.dart';
import 'package:score_poker/ui/persona_select_screen.dart';
import 'package:score_poker/ui/personas.dart';
import 'package:score_poker/data/app_settings.dart';
import 'package:score_poker/ui/ranking_screen.dart';
import 'package:score_poker/ui/how_to_play_screen.dart';
import 'package:score_poker/ui/rules_screen.dart';
import 'package:score_poker/ui/settings_screen.dart';
import 'package:score_poker/ui/shop_screen.dart';
import 'package:score_poker/ui/widgets/celebration.dart';
import 'package:score_poker/ui/theme.dart';
import 'package:score_poker/ui/widgets/card_face.dart';
import 'package:score_poker/ui/widgets/opening_sequence.dart';
import 'package:score_poker/monetization/monetization.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Renders screens to PNG (goldens/shot_*.png) for visual review.
// Run: flutter test test/screenshots_test.dart --update-goldens
// 실제 폰트(맑은 고딕 + MaterialIcons)를 로드해서 텍스트/아이콘이 그대로 보인다.

Future<ByteData> _readFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(bytes.buffer);
}

Future<void> _loadRealFonts() async {
  // 기본 패밀리(Roboto) 자리에 한글 지원 폰트를 등록 — 레이아웃 검토용.
  await (FontLoader('Roboto')..addFont(_readFont(r'C:\Windows\Fonts\malgun.ttf'))).load();
  await (FontLoader('AlfaSlabOne')..addFont(_readFont('assets/fonts/AlfaSlabOne-Regular.ttf'))).load();
  const iconOtf = 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf';
  if (File(iconOtf).existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(_readFont(iconOtf))).load();
  }
}

/// fontFamily가 비어 있는 테마 스타일(앱바 제목/스낵바/버튼)은 테스트 기본
/// 폰트(네모)로 그려지므로, 캡처용으로만 'Roboto'(=맑은 고딕)를 주입한다.
ThemeData _testTheme() {
  final base = buildAppTheme();
  TextStyle? fix(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? fixBtn(ButtonStyle? st) => st?.copyWith(
        textStyle: WidgetStatePropertyAll(fix(st.textStyle?.resolve(const {}))),
      );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(titleTextStyle: fix(base.appBarTheme.titleTextStyle)),
    snackBarTheme: base.snackBarTheme.copyWith(contentTextStyle: fix(base.snackBarTheme.contentTextStyle)),
    filledButtonTheme: FilledButtonThemeData(style: fixBtn(base.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: fixBtn(base.outlinedButtonTheme.style)),
  );
}

Widget _app(Widget child, {String locale = 'ko'}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _testTheme(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

/// 설정 화면은 AppSettingsScope를 요구한다(실제 앱과 같은 순서로 감싼다).
Widget _appWithSettings(Widget child, {String locale = 'ko', Locale? selected}) {
  final settings = AppSettings();
  if (selected != null) settings.setLocale(selected);
  return AppSettingsScope(settings: settings, child: _app(child, locale: locale));
}

void _place(GameState s, PlayerId p, int row, List<PlayingCard> cards) {
  for (var i = 0; i < cards.length; i++) {
    s.fields[p]![row][i] = PlacedCard(cards[i], p);
  }
}

GameState _demoState({Map<PlayerId, GameRules> rules = const {}}) {
  final s = GameState.custom(Deck.shuffled(seed: 7), rules: rules);
  const h = Suit.hearts, sp = Suit.spades, d = Suit.diamonds, c = Suit.clubs;
  _place(s, PlayerId.p0, 0, [const PlayingCard(14, sp), const PlayingCard(14, h)]);
  _place(s, PlayerId.p0, 1, [const PlayingCard(10, c), const PlayingCard(10, d), const PlayingCard(10, sp)]);
  _place(s, PlayerId.p0, 2, [const PlayingCard(7, h)]);
  _place(s, PlayerId.p1, 0, [const PlayingCard(13, d), const PlayingCard(12, d)]);
  _place(s, PlayerId.p1, 1, [const PlayingCard(9, sp), const PlayingCard(9, h)]);
  _place(s, PlayerId.p1, 2, [const PlayingCard(3, c, isShield: true)]);
  s.hands[PlayerId.p0]!
    ..clear()
    ..addAll([
      const PlayingCard(5, c),
      const PlayingCard(13, sp),
      PlayingCard.undesignatedJoker(),
      const PlayingCard(8, d, isShield: true),
    ]);
  s.hands[PlayerId.p1]!
    ..clear()
    ..addAll([for (var i = 0; i < 4; i++) const PlayingCard(2, sp)]);
  s.current = PlayerId.p0;
  return s;
}

GameState _finishedState() {
  final s = GameState.custom(Deck.shuffled(seed: 7));
  const h = Suit.hearts, sp = Suit.spades, d = Suit.diamonds, c = Suit.clubs;
  // L0: 나 Four of a Kind vs 상대 High Card → 나 승
  _place(s, PlayerId.p0, 0, [const PlayingCard(10, c), const PlayingCard(10, d), const PlayingCard(10, sp), const PlayingCard(10, h), const PlayingCard(5, c)]);
  _place(s, PlayerId.p1, 0, [const PlayingCard(2, sp), const PlayingCard(3, d), const PlayingCard(4, c), const PlayingCard(6, h), const PlayingCard(9, sp)]);
  // L1: 나 Full House vs 상대 Four of a Kind → 상대 승
  _place(s, PlayerId.p0, 1, [const PlayingCard(13, sp), const PlayingCard(13, h), const PlayingCard(13, d), const PlayingCard(12, c), const PlayingCard(12, d)]);
  _place(s, PlayerId.p1, 1, [const PlayingCard(7, sp), const PlayingCard(7, h), const PlayingCard(7, d), const PlayingCard(7, c), const PlayingCard(2, sp)]);
  // L2: 나 Straight vs 상대 One Pair → 나 승
  _place(s, PlayerId.p0, 2, [const PlayingCard(5, sp), const PlayingCard(6, d), const PlayingCard(7, c), const PlayingCard(8, h), const PlayingCard(9, sp)]);
  _place(s, PlayerId.p1, 2, [const PlayingCard(3, c), const PlayingCard(3, d), const PlayingCard(8, sp), const PlayingCard(11, h), const PlayingCard(14, sp)]);
  s.hands[PlayerId.p0]!.clear();
  s.hands[PlayerId.p1]!.clear();
  s.current = PlayerId.p0;
  s.phase = GamePhase.finished;
  return s;
}

Widget _opening() => Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: OpeningSequence(
          myHand: Deck.shuffled(seed: 2).draw(6),
          oppHand: (Deck.shuffled(seed: 2)..draw(6)).draw(6),
          oppPick: 0,
          myName: 'P1',
          oppName: 'P2',
          decideFirst: (a, b) => PlayerId.p0,
          onFinished: (_) {},
        ),
      ),
    );

const _portrait = Size(430, 930);
const _landscape = Size(930, 430);
const _smallPhone = Size(360, 740);

/// 랭킹 화면 데모 데이터(스크린샷용 고정값).
RankingData _demoRanking() {
  GameRecord rec(int month, int day, int my, int opp, MatchOutcome o) => GameRecord(
      playedAt: DateTime(2026, month, day), myScore: my, oppScore: opp, outcome: o);
  const w = MatchOutcome.win, l = MatchOutcome.lose, d = MatchOutcome.draw;
  return RankingData(
    rating: 315,
    games: 24,
    wins: 14,
    losses: 8,
    draws: 2,
    records: [
      rec(8, 16, 211, 117, w),
      rec(8, 15, 96, 158, l),
      rec(8, 15, 187, 187, d),
      rec(8, 14, 232, 141, w),
      rec(8, 12, 174, 120, w),
      rec(8, 11, 88, 190, l),
      rec(8, 9, 205, 132, w),
      rec(8, 7, 152, 171, l),
      rec(8, 4, 198, 90, w),
      rec(8, 1, 165, 60, w),
      rec(7, 29, 121, 119, w),
      rec(7, 25, 140, 220, l),
    ],
  );
}

void main() {
  setUpAll(_loadRealFonts);

  // setSurfaceSize만으로는 MediaQuery(가로/세로 판정)가 안 바뀐다 —
  // view.physicalSize까지 함께 설정해야 실제 기기와 같은 방향 판정이 된다.
  Future<void> setScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(size);
  }

  testWidgets('home portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(HomeScreen(rankingPreloaded: _demoRanking())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/shot_01_home_portrait.png'));
  });

  testWidgets('home landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(HomeScreen(rankingPreloaded: _demoRanking())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/shot_02_home_landscape.png'));
  });

  testWidgets('home pvp coming soon snackbar', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.public));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/shot_03_home_pvp_comingsoon.png'));
    await tester.pumpAndSettle();
  });

  testWidgets('opening picking portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(_opening()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 600)); // VS 프롬프트 페이드인 완료
    await expectLater(find.byType(OpeningSequence), matchesGoldenFile('goldens/shot_04_opening_portrait.png'));
  });

  testWidgets('opening picking landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(_opening()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 600)); // VS 프롬프트 페이드인 완료
    await expectLater(find.byType(OpeningSequence), matchesGoldenFile('goldens/shot_05_opening_landscape.png'));
  });

  testWidgets('game board portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    // 내 차례 골드 링이 무한 반복 애니메이션이라 pumpAndSettle 대신 고정 펌프.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_06_game_portrait.png'));
  });

  testWidgets('game board landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_07_game_landscape.png'));
  });

  testWidgets('result overlay portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(GameScreen(initialState: _finishedState())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_08_result_portrait.png'));
  });

  testWidgets('result overlay landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(GameScreen(initialState: _finishedState())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_09_result_landscape.png'));
  });

  testWidgets('ranking portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(RankingScreen(preloaded: _demoRanking())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(RankingScreen), matchesGoldenFile('goldens/shot_11_ranking_portrait.png'));
  });

  testWidgets('ranking landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(RankingScreen(preloaded: _demoRanking())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(RankingScreen), matchesGoldenFile('goldens/shot_12_ranking_landscape.png'));
  });

  testWidgets('ranking empty state', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const RankingScreen(preloaded: RankingData.empty)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(RankingScreen), matchesGoldenFile('goldens/shot_13_ranking_empty.png'));
  });

  testWidgets('opening first-turn banner', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(_opening()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.tap(find.byType(CardFace).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(OpeningSequence), matchesGoldenFile('goldens/shot_14_opening_banner.png'));
    await tester.pump(const Duration(milliseconds: 1400));
  });

  testWidgets('game board small phone', (tester) async {
    await setScreen(tester, _smallPhone);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_15_game_small.png'));
  });

  testWidgets('result overlay small landscape', (tester) async {
    await setScreen(tester, const Size(740, 360));
    await tester.pumpWidget(_app(GameScreen(initialState: _finishedState())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_16_result_small_landscape.png'));
  });

  // 로티 JSON 디코딩은 비동기라 runAsync로 실제 완료를 기다린 뒤 캡처한다.
  Future<void> pumpLottie(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('persona select portrait', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const PersonaSelectScreen()));
    await pumpLottie(tester);
    await expectLater(find.byType(PersonaSelectScreen), matchesGoldenFile('goldens/shot_17_persona_portrait.png'));
  });

  testWidgets('persona select landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(const PersonaSelectScreen()));
    await pumpLottie(tester);
    await expectLater(find.byType(PersonaSelectScreen), matchesGoldenFile('goldens/shot_18_persona_landscape.png'));
  });

  testWidgets('persona in game with greeting', (tester) async {
    await setScreen(tester, _portrait);
    final clode = buildPersonas(AppLocalizationsKo())[0];
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState(), persona: clode)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 인사 말풍선 팝 완료
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_22_persona_game.png'));
    await tester.pump(const Duration(seconds: 4)); // 말풍선 타이머 정리
  });

  testWidgets('result with persona portrait', (tester) async {
    await setScreen(tester, _portrait);
    final clode = buildPersonas(AppLocalizationsKo())[0];
    await tester.pumpWidget(_app(GameScreen(initialState: _finishedState(), persona: clode)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_23_result_persona.png'));
  });

  testWidgets('emote picker open', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.emoji_emotions_rounded));
    await pumpLottie(tester);
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_19_emote_picker.png'));
  });

  testWidgets('emote bubbles both sides', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.emoji_emotions_rounded));
    await pumpLottie(tester);
    await tester.tap(find.byType(PersonaIcon).at(3)); // 시무룩(sad) 전송
    await tester.pump(const Duration(milliseconds: 1000)); // 상대(AI) 반응 도착
    await tester.pump(const Duration(milliseconds: 300)); // 말풍선 팝 애니메이션 완료
    await pumpLottie(tester);
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_20_emote_bubbles.png'));
    await tester.pump(const Duration(seconds: 4)); // 말풍선 타이머 정리
  });

  testWidgets('emote bubbles landscape', (tester) async {
    await setScreen(tester, _landscape);
    await tester.pumpWidget(_app(GameScreen(initialState: _demoState())));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.emoji_emotions_rounded));
    await pumpLottie(tester);
    await tester.tap(find.byType(PersonaIcon).at(1)); // 웃음(lol) 전송
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 300)); // 말풍선 팝 애니메이션 완료
    await pumpLottie(tester);
    await expectLater(find.byType(GameScreen), matchesGoldenFile('goldens/shot_21_emote_landscape.png'));
    await tester.pump(const Duration(seconds: 4));
  });

  Widget celebrationDemo({String title = 'FOUR CARD!', String subtitle = '포카드'}) => Stack(
        key: const Key('celebration-demo'),
        children: [
          GameScreen(initialState: _demoState()),
          HandCelebration(title: title, subtitle: subtitle, seed: 3),
        ],
      );

  // 최장 족보명이 FittedBox로 한 줄 수납되는지 확인.
  testWidgets('celebration long title', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(
        _app(celebrationDemo(title: 'STRAIGHT FLUSH!', subtitle: '스트레이트 플러쉬')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(const Key('celebration-demo')),
        matchesGoldenFile('goldens/shot_25_celebration_long.png'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('celebration hero shot', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(celebrationDemo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 배너 정착 + 축포 절정
    await expectLater(
        find.byKey(const Key('celebration-demo')), matchesGoldenFile('goldens/shot_24_celebration.png'));
    await tester.pump(const Duration(seconds: 2)); // 연출 종료까지 재생
  });

  testWidgets('celebration animation frames', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(celebrationDemo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 10; i++) {
      await expectLater(
          find.byKey(const Key('celebration-demo')),
          matchesGoldenFile('goldens/anim_celebration_f$i.png'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));
  });

  // 공격(빼앗기) 연출 확인용: 돌진(잔상)→명중(플래시·파편·히트스톱)→녹아웃→강탈→
  // 쉴드 글린트를 100ms 간격 14프레임으로 떠서 갤러리에서 돌려본다.
  testWidgets('attack sequence frames', (tester) async {
    await setScreen(tester, _portrait);
    final s = _demoState();
    // 상대 9♠(줄2)를 노리는 공격 표식 카드 + 배치용 필러.
    s.hands[PlayerId.p0]!
      ..clear()
      ..addAll([
        const PlayingCard(9, Suit.clubs, isAttacker: true),
        const PlayingCard(5, Suit.clubs),
      ]);
    await tester.pumpWidget(_app(GameScreen(initialState: s)));
    // 게임 화면은 턴 아바타가 계속 움직여 pumpAndSettle이 끝나지 않는다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 보드 칸은 비공개 위젯이라 카드 앞면(CardFace)으로 찾아 탭한다 —
    // 탭은 위의 GestureDetector(opaque)로 전달된다.
    final myAttacker = find.byWidgetPredicate((w) =>
        w is CardFace && w.card == const PlayingCard(9, Suit.clubs, isAttacker: true));
    final target = find.byWidgetPredicate(
        (w) => w is CardFace && w.card == const PlayingCard(9, Suit.spades));

    await tester.tap(myAttacker);
    await tester.pump();
    await tester.tap(target);
    for (var i = 0; i < 14; i++) {
      // 연출은 앱 Overlay(화면 위 레이어)에 그려지므로 MaterialApp째 떠야 보인다.
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile('goldens/anim_attack_f$i.png'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 남은 연출·스낵바 타이머를 전부 소진한다(pumpAndSettle은 아바타 때문에 불가).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });

  // 로티 재생 확인용: 120ms 간격 10프레임을 떠서 갤러리에서 GIF처럼 돌려본다.
  testWidgets('persona select animation frames', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const PersonaSelectScreen()));
    await pumpLottie(tester);
    for (var i = 0; i < 10; i++) {
      await expectLater(
          find.byType(PersonaSelectScreen), matchesGoldenFile('goldens/anim_persona_f$i.png'));
      await tester.pump(const Duration(milliseconds: 120));
    }
  });

  testWidgets('card gallery', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 340));
    await tester.pumpWidget(_app(
      Scaffold(
        body: Container(
        color: AppColors.bgMid,
        padding: const EdgeInsets.all(16),
        child: const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            CardFace(card: PlayingCard(14, Suit.hearts), size: 84),
            CardFace(card: PlayingCard(13, Suit.spades), size: 84),
            CardFace(card: PlayingCard(10, Suit.diamonds), size: 84),
            CardFace(card: PlayingCard(7, Suit.clubs), size: 84),
            CardFace(card: PlayingCard(11, Suit.spades, isJoker: true), size: 84),
            CardFace(card: PlayingCard(8, Suit.diamonds, isShield: true), size: 84),
          ],
        ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Wrap), matchesGoldenFile('goldens/shot_10_card_gallery.png'));
  });

  testWidgets('shop portrait', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _portrait);
    final m = Monetization(purchases: StubPurchaseService(autoGrant: true));
    await m.startAsync();
    addTearDown(m.dispose);
    await tester.pumpWidget(_app(MonetizationScope(
      monetization: m,
      child: const ShopScreen(),
    )));
    await tester.pumpAndSettle();
    await expectLater(find.byType(ShopScreen), matchesGoldenFile('goldens/shot_26_shop_portrait.png'));
  });

  testWidgets('shop landscape', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _landscape);
    final m = Monetization(purchases: StubPurchaseService(autoGrant: true));
    await m.startAsync();
    addTearDown(m.dispose);
    await tester.pumpWidget(_app(MonetizationScope(
      monetization: m,
      child: const ShopScreen(),
    )));
    await tester.pumpAndSettle();
    await expectLater(find.byType(ShopScreen), matchesGoldenFile('goldens/shot_27_shop_landscape.png'));
  });

  testWidgets('game with tokens portrait', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _portrait);
    final m = Monetization(purchases: StubPurchaseService());
    await m.startAsync();
    addTearDown(m.dispose);
    await tester.pumpWidget(_app(MonetizationScope(
      monetization: m,
      child: GameScreen(
        initialState: _demoState(rules: const {PlayerId.p0: GameRules.standard}),
      ),
    )));
    // 내 차례 골드 링이 무한 반복이라 pumpAndSettle 대신 고정 펌프.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(
        find.byType(GameScreen), matchesGoldenFile('goldens/shot_28_game_tokens.png'));
  });

  testWidgets('game with tokens landscape', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _landscape);
    final m = Monetization(purchases: StubPurchaseService());
    await m.startAsync();
    addTearDown(m.dispose);
    await tester.pumpWidget(_app(MonetizationScope(
      monetization: m,
      child: GameScreen(
        initialState: _demoState(rules: const {PlayerId.p0: GameRules.standard}),
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(GameScreen),
        matchesGoldenFile('goldens/shot_29_game_tokens_landscape.png'));
  });

  // ── 언어: 영어 빌드가 실제로 영어로 나오는지 눈으로 확인하는 샷들 ──────────────

  testWidgets('settings korean', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_appWithSettings(const SettingsScreen()));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(SettingsScreen), matchesGoldenFile('goldens/shot_30_settings_ko.png'));
  });

  testWidgets('settings english', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_appWithSettings(const SettingsScreen(),
        locale: 'en', selected: const Locale('en')));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(SettingsScreen), matchesGoldenFile('goldens/shot_31_settings_en.png'));
  });

  testWidgets('home english', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(
        _app(HomeScreen(rankingPreloaded: _demoRanking()), locale: 'en'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(HomeScreen), matchesGoldenFile('goldens/shot_32_home_en.png'));
  });

  testWidgets('shop english', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setScreen(tester, _portrait);
    final m = Monetization(purchases: StubPurchaseService());
    await m.startAsync();
    addTearDown(m.dispose);
    await tester.pumpWidget(_app(
      MonetizationScope(monetization: m, child: const ShopScreen()),
      locale: 'en',
    ));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(ShopScreen), matchesGoldenFile('goldens/shot_33_shop_en.png'));
  });

  testWidgets('persona select english', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const PersonaSelectScreen(), locale: 'en'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(PersonaSelectScreen),
        matchesGoldenFile('goldens/shot_34_persona_select_en.png'));
  });

  testWidgets('persona speech english', (tester) async {
    await setScreen(tester, _portrait);
    final clode = buildPersonas(AppLocalizationsEn())[0];
    await tester.pumpWidget(
        _app(GameScreen(initialState: _demoState(), persona: clode), locale: 'en'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(GameScreen),
        matchesGoldenFile('goldens/shot_35_persona_speech_en.png'));
    await tester.pump(const Duration(seconds: 4));
  });

  // ── 튜토리얼 · 규칙 ─────────────────────────────────────────────────────────

  testWidgets('how to play korean', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const HowToPlayScreen()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(HowToPlayScreen),
        matchesGoldenFile('goldens/shot_36_howtoplay_ko.png'));
  });

  testWidgets('how to play english (attack page)', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const HowToPlayScreen(), locale: 'en'));
    await tester.pumpAndSettle();
    // 3번째 장(빼앗기) — 삽화가 가장 복잡한 장이라 넘침 검증에 좋다.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(HowToPlayScreen),
        matchesGoldenFile('goldens/shot_37_howtoplay_en.png'));
  });

  testWidgets('rules korean', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const RulesScreen()));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(RulesScreen), matchesGoldenFile('goldens/shot_38_rules_ko.png'));
  });

  testWidgets('rules english', (tester) async {
    await setScreen(tester, _portrait);
    await tester.pumpWidget(_app(const RulesScreen(), locale: 'en'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(RulesScreen), matchesGoldenFile('goldens/shot_39_rules_en.png'));
  });
}
