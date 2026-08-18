import 'package:flutter/material.dart';

/// **'그린 펠트 & 브라스' DARK 테마** — 카지노 카드룸의 초록 펠트 위에
/// 아이보리 카드가 놓이는, 카드 게임 본연의 색.
/// 디자인 원칙: "판은 차분하게(두뇌), 사건은 화려하게(운)".
///   브라스 골드 = 운명(중앙선/선공/쉴드/드로우), 바이올렛 = 조커.
class AppColors {
  AppColors._();

  static const ink = Color(0xFF26251C); // 웜 블랙(카드 위 텍스트/칩 위 글자)
  static const inkSoft = Color(0xFFCBC9B2); // 어두운 배경 위 보조 아이콘/텍스트
  static const cardBody = Color(0xFFF5EFDF); // 카드 몸체(아이보리)

  // 배경: 카드룸의 딥 그린 그라데이션
  static const bgTop = Color(0xFF223B2F);
  static const bgMid = Color(0xFF1B3126);
  static const bgBottom = Color(0xFF14261D);

  static const panel = Color(0x14FFFFFF); // 살짝 비치는 밝은 패널
  static const panelStrong = Color(0x22FFFFFF);
  static const surface = Color(0xFF2A4436); // 스트립/다이얼로그 표면
  static const stroke = Color(0x1FFFFFFF); // 은은한 경계선
  static const textMain = Color(0xFFF0EAD6); // 본문 텍스트(크림)
  static const textMuted = Color(0xFF94A896); // 보조 텍스트(세이지 그레이)

  // 브라스 골드(운명의 색: 중앙선/선공/쉴드/드로우)
  static const gold = Color(0xFFD4A24A);
  static const goldSoft = Color(0xFFE8C88A);
  static const goldDeep = Color(0xFF8A6B30);

  static const red = Color(0xFFC63D2F); // 하트/다이아(클래식 카드 레드)
  static const dark = Color(0xFF2F2B24); // 클럽/스페이드(웜 블랙)
  static const purple = Color(0xFF8B5FC8); // 조커/포인트

  static const mePrimary = Color(0xFF4B87C2); // 나(스틸 블루)
  static const meSoft = Color(0x1A4B87C2);
  static const oppPrimary = Color(0xFFC2632F); // 상대(테라코타)
  static const oppSoft = Color(0x1AC2632F);

  static const win = Color(0xFF7CC47F);
  static const lose = Color(0xFFE06552);
  static const tie = Color(0xFFA9A28C);

  // 테이블(펠트) — 배경보다 채도를 올려 보드 존이 살아나게
  static const feltA = Color(0xFF2C5540); // 펠트 중앙
  static const feltB = Color(0xFF1F4030); // 펠트 가장자리(radial)
  static const feltEdge = Color(0x38D4A24A); // 테이블 테두리(브라스 은은히)

  // 보드 빈칸(파인 홈) — 전부 불투명(반투명 금지)
  static const slotRecess = Color(0xFF1A3427); // 빈칸 기본
  static const slotNext = Color(0xFF224231); // 다음에 놓일 칸(살짝 밝게)
  static const laneLine = Color(0x61FFFFFF); // 레인 사이 세로 구분선(가운데 최대 밝기)

  // 게이지/사다리의 미도달 칸(불투명 단색)
  static const gaugeOff = Color(0xFF33513F);

  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0, 0.55, 1],
  );

  static const feltGradient = RadialGradient(
    center: Alignment(0, -0.05),
    radius: 1.15,
    colors: [feltA, feltB],
  );
}

/// 앱 전역 반경/그림자 토큰.
class AppShapes {
  AppShapes._();
  static const radius = 18.0;
  static final panelShadow = <BoxShadow>[
    BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
  ];
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    primary: AppColors.mePrimary,
    secondary: AppColors.gold,
  );

  const display = TextStyle(
    color: AppColors.textMain,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    height: 1.05,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgMid,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displaySmall: display,
      headlineMedium: display,
      headlineSmall: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, letterSpacing: 0.5),
      titleLarge: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: AppColors.inkSoft),
      labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textMain,
      titleTextStyle: TextStyle(
        color: AppColors.textMain,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold, // 골드 CTA — '운명'을 누르는 버튼
        foregroundColor: AppColors.bgBottom,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkSoft,
        side: const BorderSide(color: Color(0x40FFFFFF), width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.radius),
        side: const BorderSide(color: AppColors.stroke),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2F4C3C),
      contentTextStyle: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
