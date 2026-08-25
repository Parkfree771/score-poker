import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/card.dart';

/// lordicon SVG에서 추출한 무늬 글리프 + 직접 구성한 조커. flutter_svg로 렌더.
/// 빨강(하트/다이아) / 검정(클럽/스페이드) 색을 입혀 둠. viewBox는 글리프에 맞춰 중앙 정렬.
// '그린 펠트 & 브라스' 테마 팔레트(theme.dart와 동기화)
const String _outline = '#26251C'; // 웜 블랙
const String _red = '#C63D2F'; // 하트/다이아 (클래식 카드 레드)
const String _dark = '#2F2B24'; // 클럽/스페이드 (웜 블랙)

String suitSvg(Suit suit) {
  switch (suit) {
    case Suit.hearts:
      return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-44 -42 88 96">
<path d="M35.195-23.262c8.728 8.756 8.728 22.952 0 31.708L-.162 43.92-35.519 8.446c-8.727-8.756-8.727-22.952 0-31.708s22.878-8.756 31.605 0a22.4 22.4 0 0 1 3.752 4.988 22.4 22.4 0 0 1 3.752-4.988c8.727-8.756 22.878-8.756 31.605 0Z" fill="$_red" stroke="$_outline" stroke-width="5" stroke-linejoin="round"/>
</svg>''';
    case Suit.diamonds:
      return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="115 145 110 110">
<path d="M215 200 L170 145 L125 200 L170 255 Z" fill="$_red" stroke="$_outline" stroke-width="6" stroke-linejoin="round"/>
</svg>''';
    case Suit.clubs:
      return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="108 128 126 130">
<path d="M195 255h-25m-25 0h25m0 0v-39m27.5-48.5c0-15.188-12.312-27.5-27.5-27.5s-27.5 12.312-27.5 27.5q0 1.483.154 2.926C129.777 172.715 120 183.966 120 197.5c0 15.188 12.312 27.5 27.5 27.5 9.302 0 17.523-4.62 22.5-11.688C174.977 220.38 183.198 225 192.5 225c15.188 0 27.5-12.312 27.5-27.5 0-13.535-9.778-24.785-22.655-27.074q.154-1.443.155-2.926Z" fill="$_dark" stroke="$_outline" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/>
</svg>''';
    case Suit.spades:
      return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="120 130 100 112">
<path d="M174.029 205.965c9.373 9.38 24.569 9.38 33.942 0s9.373-24.586 0-33.966L170 134l-37.971 37.999c-9.373 9.38-9.373 24.586 0 33.966s24.569 9.38 33.942 0a24 24 0 0 0 4.029-5.342 24 24 0 0 0 4.029 5.342Z" fill="$_dark" stroke="$_outline" stroke-width="6" stroke-linejoin="round"/>
<path d="M170 196 L158 236 L182 236 Z" fill="$_dark" stroke="$_outline" stroke-width="6" stroke-linejoin="round"/>
</svg>''';
  }
}

/// lordicon 하트 카드(in-reveal)에서 추출한 **카드 프레임**(몸체+외곽선, 무늬/빗금 제거).
/// 모든 카드의 공통 틀. [outlineHex]로 외곽선 색 지정(기본 잉크 / 쉴드는 골드).
/// 카드 비율 ≈ 312/230 ≈ 1.36.
String cardFrameSvg(String outlineHex) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="96 72 230 312">
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="#F5EFDF"/>
<path d="M134.976 97.172c-.103-11.046 8.768-20.082 19.814-20.184l-34.999.324c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l34.998-.324c-11.045.102-20.082-8.769-20.184-19.814z" fill="#EAE2CC"/>
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="none" stroke="$outlineHex" stroke-width="7" stroke-linejoin="round"/>
</svg>''';

/// 카드 **뒷면**: 카드 프레임과 같은 viewBox(96 72 230 312)로 정렬.
///
/// 카지노 백의 문법으로 다시 그렸다 — 아이보리 테두리 → 브라스 이중 프레임(모서리 ◆) →
/// 딥 버건디 몸체에 **사선 격자(다이아퍼)** → 가운데 크림 메달리온 + 브라스 ◆(테이블
/// 프레임의 ◆캡과 같은 언어). 50px에서도 읽히도록 격자는 성기고, 메달리온은 크게.
String cardBackSvg() {
  const x0 = 120.0, y0 = 97.0, w = 182.0, h = 262.0; // 몸체
  const cx = x0 + w / 2, cy = y0 + h / 2;
  final lattice = StringBuffer();
  // 45° 사선 두 방향. 간격 26 — 촘촘하면 작은 카드에서 회색 얼룩이 된다.
  for (var k = -h; k <= w + h; k += 26) {
    lattice.write('<path d="M${x0 + k} $y0 L${x0 + k - h} ${y0 + h}"/>');
    lattice.write('<path d="M${x0 + k - h} $y0 L${x0 + k} ${y0 + h}"/>');
  }
  String corner(double x, double y) =>
      '<path d="M$x ${y - 7} L${x + 7} $y L$x ${y + 7} L${x - 7} $y Z" fill="#D4A24A"/>';
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="96 72 230 312">
<defs>
<clipPath id="body"><rect x="$x0" y="$y0" width="$w" height="$h" rx="16"/></clipPath>
<radialGradient id="field" cx="0.5" cy="0.42" r="0.75">
<stop offset="0" stop-color="#8A3A2C"/><stop offset="1" stop-color="#5E2019"/>
</radialGradient>
</defs>
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="#F5EFDF"/>
<rect x="$x0" y="$y0" width="$w" height="$h" rx="16" fill="url(#field)"/>
<g clip-path="url(#body)" stroke="#F5EFDF" stroke-width="1.3" opacity="0.2" fill="none">
$lattice
</g>
<rect x="$x0" y="$y0" width="$w" height="$h" rx="16" fill="none" stroke="#D4A24A" stroke-width="3.2"/>
<rect x="${x0 + 10}" y="${y0 + 10}" width="${w - 20}" height="${h - 20}" rx="10" fill="none" stroke="#F5EFDF" stroke-width="1.2" opacity="0.55"/>
${corner(x0 + 10, y0 + 10)}${corner(x0 + w - 10, y0 + 10)}${corner(x0 + 10, y0 + h - 10)}${corner(x0 + w - 10, y0 + h - 10)}
<ellipse cx="$cx" cy="$cy" rx="46" ry="60" fill="#5E2019" opacity="0.55"/>
<ellipse cx="$cx" cy="$cy" rx="40" ry="54" fill="#F5EFDF"/>
<ellipse cx="$cx" cy="$cy" rx="34" ry="48" fill="none" stroke="#D4A24A" stroke-width="2"/>
<path d="M$cx ${cy - 30} L${cx + 22} $cy L$cx ${cy + 30} L${cx - 22} $cy Z" fill="#D4A24A" stroke="#26251C" stroke-width="3" stroke-linejoin="round"/>
<circle cx="$cx" cy="$cy" r="5" fill="#26251C"/>
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="none" stroke="#26251C" stroke-width="7" stroke-linejoin="round"/>
</svg>''';
}

/// 코너/텍스트용 무늬 색.
bool suitIsRed(Suit s) => s == Suit.hearts || s == Suit.diamonds;

// ---- loader 캐시 ----
//
// 아래 SVG 문자열들은 색을 보간해서 만들기 때문에 **호출할 때마다 새 String**이 되고,
// `SvgPicture.string`은 그때마다 새 loader를 만든다. 보드에 카드가 30장 넘게 깔리는
// 게임이라 이 낭비가 프레임 예산을 갉아먹는다. 인스턴스를 재사용해 flutter_svg의
// 디코드 캐시가 실제로 맞도록 한다. (측정: 프레임당 2.05ms → 0.33ms)

final Map<Suit, SvgStringLoader> _suitLoaders = {};
SvgStringLoader suitLoader(Suit suit) => _suitLoaders[suit] ??= SvgStringLoader(suitSvg(suit));


final Map<String, SvgStringLoader> _frameLoaders = {};
SvgStringLoader cardFrameLoader(String outlineHex) =>
    _frameLoaders[outlineHex] ??= SvgStringLoader(cardFrameSvg(outlineHex));

final SvgStringLoader cardBackLoader = SvgStringLoader(cardBackSvg());
