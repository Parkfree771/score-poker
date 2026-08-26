"""사용자 Desktop/lottie 폴더의 wired-lineal 로티를 게임 팔레트로 재채색해 assets/lottie에 넣는다.

  python tool/recolor_lottie.py

레이어 이름이 'Group n'뿐이라 코드(ValueDelegate)로는 부위를 못 집는다 — 원본 색 → 새 색
매핑으로 파일 자체를 바꾼다. 원본 팔레트(wired-lineal 공통):
  #121331 스트로크 · #ffc738 노랑 · #f24c00 주황 · #ebe6ef 밝은 면 · #3a3347 어두운 면 · #ff0000 빨강
"""
import json, os
SRC = 'C:/Users/park yu ro/Desktop/lottie/'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'lottie')

def hx(k): return '#%02x%02x%02x' % tuple(int(round(v * 255)) for v in k[:3])
def rgb(h): return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)] + [1]

def recolor(src, dst, palette, glyph=None):
    d = json.load(open(SRC + src, encoding='utf-8'))
    def walk(o):
        if isinstance(o, dict):
            if o.get('ty') in ('fl', 'st') and isinstance(o.get('c', {}).get('k'), list) \
                    and not isinstance(o['c']['k'][0], dict):
                key = (hx(o['c']['k']), o['ty'])
                if glyph and key == ('#ff0000', 'fl') and o.get('nm') == 'Fill 1':
                    o['c']['k'] = rgb(glyph)
                elif key in palette:
                    o['c']['k'] = rgb(palette[key])
                elif (key[0], '*') in palette:
                    o['c']['k'] = rgb(palette[(key[0], '*')])
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(d)
    json.dump(d, open(os.path.join(OUT, dst), 'w', encoding='utf-8'), separators=(',', ':'))
    print('wrote', dst)

# ---- 비공개권 칩 (검정·크림·브라스)
CHIP = {('#121331', 'st'): '#050507', ('#3a3347', 'fl'): '#efe3c4', ('#ff0000', 'fl'): '#d6b25c',
        ('#ebe6ef', 'fl'): '#17161a', ('#f24c00', 'fl'): '#f0d48a'}
recolor('wired-lineal-3174-spade-chip-in-reveal.json', 'chip_spade.json', CHIP)

# ---- 페르소나 프로필
# 딥시(중국풍): 붉은 별 — 주홍 면 + 금빛 하이라이트, 어두운 적갈 선
recolor('wired-lineal-237-star-rating-hover-pinch.json', 'persona_star.json', {
    ('#ffc738', 'fl'): '#d8342a', ('#ebe6ef', 'fl'): '#f7d774',
    ('#121331', '*'): '#3a0d0b',
})
# 그록: 광대 모자 — 보라 모자 + 라임 방울 + 크림 챙
recolor('wired-lineal-1451-card-joker-hover-pinch.json', 'persona_joker.json', {
    ('#f24c00', 'fl'): '#7c4dff', ('#ffc738', 'fl'): '#c6f135', ('#ebe6ef', 'fl'): '#f0ead6',
    ('#3a3347', 'fl'): '#2b1b5a', ('#121331', '*'): '#1a1030',
})
# 미스트: 스톱워치 — 강청 몸통 + 얼음빛 문자판 + 오렌지 버튼/바늘
recolor('wired-lineal-46-timer-stopwatch-hover-start.json', 'persona_stopwatch.json', {
    ('#f24c00', 'fl'): '#ff7a1a', ('#ebe6ef', 'fl'): '#eaf2ff', ('#3a3347', 'fl'): '#3d6fa3',
    ('#121331', '*'): '#12213a',
})
