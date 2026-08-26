"""wired-lineal 칩 로티(사용자 Desktop/lottie 폴더)를 게임 팔레트로 재채색한다.

  python tool/recolor_chip_lottie.py

- chip_spade.json   : 검정·크림·브라스 (글리프 포함 전부 팔레트)
- chip_diamond.json : 같은 팔레트, 글리프('Fill 1' #ff0000)만 카지노 레드
원본 색 → 팔레트 매핑은 chip_spade.json을 만들 때 쓴 것과 같다.
"""
import json, os
SRC = 'C:/Users/park yu ro/Desktop/lottie/'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'lottie')
PALETTE = {  # (원본 hex, ty) → 새 hex
    ('#121331', 'st'): '#050507',
    ('#3a3347', 'fl'): '#efe3c4',
    ('#ff0000', 'fl'): '#d6b25c',
    ('#ebe6ef', 'fl'): '#17161a',
    ('#f24c00', 'fl'): '#f0d48a',
}
def hx(k): return '#%02x%02x%02x' % tuple(int(round(v * 255)) for v in k[:3])
def rgb(h): return [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)] + [1]

def recolor(src, dst, glyph=None):
    d = json.load(open(SRC + src, encoding='utf-8'))
    def walk(o):
        if isinstance(o, dict):
            if o.get('ty') in ('fl', 'st') and isinstance(o.get('c', {}).get('k'), list) \
                    and not isinstance(o['c']['k'][0], dict):
                key = (hx(o['c']['k']), o['ty'])
                if glyph and key == ('#ff0000', 'fl') and o.get('nm') == 'Fill 1':
                    o['c']['k'] = rgb(glyph)
                elif key in PALETTE:
                    o['c']['k'] = rgb(PALETTE[key])
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(d)
    json.dump(d, open(os.path.join(OUT, dst), 'w', encoding='utf-8'), separators=(',', ':'))
    print('wrote', dst)

recolor('wired-lineal-3174-spade-chip-in-reveal.json', 'chip_spade.json')
recolor('wired-lineal-3173-diamond-chip-in-reveal.json', 'chip_diamond.json', glyph='#c8262e')
