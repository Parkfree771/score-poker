# -*- coding: utf-8 -*-
# 실사 효과음 임포터 — Kenney "Casino Audio" 팩(CC0)을 앱 포맷으로 가공한다.
#
# 출처: https://kenney.nl/assets/casino-audio (License: CC0 — 저작권 표기 불요)
# iOS는 ogg를 재생하지 못하므로 16-bit mono WAV로 변환하고, 앞뒤 무음을 잘라
# 탭→소리 지연을 없앤 뒤 피크를 맞춘다.
#
# 실행: python tool/import_sfx.py <kenney_Audio_폴더>  →  assets/sfx/*.wav
#   예: python tool/import_sfx.py C:/downloads/kenney_casino-audio/Audio
#
# 합성음(shield/token/win/lose/attack_whoosh)은 tool/gen_sfx.py 담당.
import math
import sys

import numpy as np
import soundfile as sf

SR = 44100


def load_mono(path):
    data, sr = sf.read(path, always_2d=True)
    x = data.mean(axis=1)
    if sr != SR:  # 케니 팩은 44.1k지만, 아니어도 선형 보간으로 맞춘다
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x


def trim(x, thresh_db=-42.0, tail_sec=0.06):
    """앞 무음은 바싹, 뒤는 자연 여운을 조금 남기고 자른다."""
    amp = 10 ** (thresh_db / 20)
    idx = np.flatnonzero(np.abs(x) > amp)
    if len(idx) == 0:
        return x
    start = max(0, idx[0] - int(SR * 0.004))
    end = min(len(x), idx[-1] + int(SR * tail_sec))
    return x[start:end]


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def fade_out(x, sec=0.012):
    n = min(len(x), int(SR * sec))
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x):
    x = fade_out(normalize(np.asarray(x, dtype=np.float64)))
    sf.write(f'assets/sfx/{name}.wav', x, SR, subtype='PCM_16')
    print('ok', name, f'{len(x) / SR:.2f}s')


def thump(freq=85.0, dur=0.11, decay=0.028):
    """타격 순간의 저역 펀치(북소리 몸통). 실사 카드음만으로는 '맞았다'는 무게가 없다."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    # 피치가 살짝 떨어지는 킥 드럼형 사인
    sweep = freq * (1 + 0.9 * np.exp(-t / 0.012))
    phase = np.cumsum(2 * math.pi * sweep / SR)
    return np.sin(phase) * np.exp(-t / decay)


def layered_hit(clack, gain_body=0.95, gain_card=0.85):
    """공격 명중음 = 실사 클랙(chips-collide) + 합성 저역 펀치.

    v1은 card-shove(미는 소리)를 썼는데 타격이 아니라 슬라이드처럼 들려 어색했다.
    짧은 "딱!"이 되도록 클랙에 빠른 감쇠 엔벨로프를 걸고 0.22초로 자른다.
    """
    card = trim(clack, tail_sec=0.02)
    n_max = int(SR * 0.16)
    card = card[:n_max]
    card = card * np.exp(-np.arange(len(card)) / (SR * 0.045))  # 잔향 컷
    body = thump()
    n = max(len(card), len(body), int(SR * 0.22))
    out = np.zeros(n)
    out[: len(body)] += body * gain_body
    out[: len(card)] += card * gain_card
    return out


def main(src):
    src = src.rstrip('/\\')
    # 카드 배치: 실사 스냅 4종 — 매번 다른 샘플이 무작위 재생되어 반복감이 없다
    for i in (1, 2, 3, 4):
        save(f'card_place_{i}', trim(load_mono(f'{src}/card-place-{i}.ogg')))
    # 카드 슬라이드(드로우·비행): 4종
    for out_i, src_i in enumerate((1, 3, 5, 7), start=1):
        save(f'card_slide_{out_i}', trim(load_mono(f'{src}/card-slide-{src_i}.ogg')))
    # 오프닝 딜링(부채꼴로 촤르륵)
    save('deal', trim(load_mono(f'{src}/card-fan-2.ogg')))
    save('shuffle', trim(load_mono(f'{src}/card-shuffle.ogg')))
    # 공격 명중: 실사 클랙 + 저역 펀치 레이어 2종 (짧고 퍼커시브한 "딱!")
    save('attack_hit_1', layered_hit(load_mono(f'{src}/chips-collide-1.ogg')))
    save('attack_hit_2', layered_hit(load_mono(f'{src}/chips-collide-3.ogg')))
    # 비공개권 칩 — 전부 실사. 합성 핑/탭은 8비트처럼 들려 폐기했다.
    #  token(봉인 지정): 칩 한 개를 테이블에 놓는 소리 3종
    for i in (1, 2, 3):
        save(f'token_{i}', trim(load_mono(f'{src}/chip-lay-{i}.ogg'), tail_sec=0.05))
    #  chip_ping(레일에서 튀어 오름): 칩을 손에서 굴리는 가벼운 소리 — 짧게 자른다
    for out_i, src_i in enumerate((2, 4), start=1):
        x = trim(load_mono(f'{src}/chips-handle-{src_i}.ogg'), tail_sec=0.03)
        save(f'chip_ping_{out_i}', x[: int(SR * 0.16)])
    #  chip_flick(뒷면을 쳐냄): 칩끼리 부딪히는 클랙 2종 — 잔향은 짧게
    for out_i, src_i in enumerate((2, 4), start=1):
        x = trim(load_mono(f'{src}/chips-collide-{src_i}.ogg'), tail_sec=0.03)
        save(f'chip_flick_{out_i}', x[: int(SR * 0.2)])


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__ or 'usage: python tool/import_sfx.py <kenney Audio dir>')
    main(sys.argv[1])
