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
/// 아이보리 테두리 + 딥 레드 몸체 + 크림 격자/브라스 다이아몬드(클래식 트럼프 백).
String cardBackSvg() => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="96 72 230 312">
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="#F5EFDF"/>
<rect x="120" y="97" width="182" height="262" rx="16" fill="#7E3327"/>
<rect x="120" y="97" width="182" height="262" rx="16" fill="none" stroke="#D4A24A" stroke-width="3"/>
<rect x="131" y="108" width="160" height="240" rx="11" fill="none" stroke="#D4A24A" stroke-width="1.4" opacity="0.7"/>
<g stroke="#F5EFDF" stroke-width="2.4" stroke-linejoin="round" fill="none" opacity="0.28">
<path d="M211 172 L233 200 L211 228 L189 200 Z"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(-42,0)"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(42,0)"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(-21,-42)"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(21,-42)"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(-21,42)"/>
<path d="M211 172 L233 200 L211 228 L189 200 Z" transform="translate(21,42)"/>
</g>
<path d="M211 184 L227 200 L211 216 L195 200 Z" fill="#D4A24A" stroke="#26251C" stroke-width="3" stroke-linejoin="round"/>
<circle cx="211" cy="200" r="4.5" fill="#26251C"/>
<path d="M119.791 77.312c-11.045.102-19.916 9.138-19.814 20.184L102.41 360.5c.103 11.045 9.14 19.916 20.185 19.814l179.992-1.665c11.045-.103 19.916-9.14 19.814-20.185L319.968 95.46c-.103-11.045-9.14-19.916-20.185-19.814z" fill="none" stroke="#26251C" stroke-width="7" stroke-linejoin="round"/>
</svg>''';

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
