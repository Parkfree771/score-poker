# -*- coding: utf-8 -*-
"""칩 비행/충돌음 리믹스 — Sonniss GDC2024 발췌 2개로 chip_shot(비행)·chip_ting(충돌)을 새로 만든다.

실행: python tool/mix_chip_sfx.py <whoosh.wav> <click.wav>  →  assets/sfx/chip_shot·ting_*.wav

소재(Sonniss GDC 2024 번들 — 로열티프리·표기 불요, 원본 wav 재배포만 금지):
  whoosh  = Chupapsound "WHOOSH PASS SF LOW"        → 비행(슛-) 몸통
  click   = Bluezone "tiny_gears click_complex_011" → 충돌(탁!) 트랜지언트

요구사항(청취 피드백):
  - 충돌이 비행보다 확실히 커야 한다 → 충돌은 피크 -0.5dB + 새추레이션으로 RMS를
    올리고, 비행은 피크 -11dB 로 눌러 상대감을 파일에 굽는다(코드 볼륨 조절 없이).
  - 비행이 0.3s로 딱 끊기면 짧아서 별로 → 0.55s, 정점 뒤 여운이 충돌음 밑에 깔린다.
  - 타이밍은 game_screen._peekWithChip 의 타임라인과 한 몸: 팅이 비행 시작 +255ms에
    미리 발사되므로(출력 지연 상쇄) 비행 정점은 그 직전 ~235ms에 둔다.
"""
import sys
import numpy as np, soundfile as sf, os

SR = 44100
OUTS = [os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')]


def load(path):
    x, sr = sf.read(path, always_2d=True)
    x = x.mean(1)
    if sr != SR:
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x / (np.abs(x).max() + 1e-9)


def resample(x, factor):
    """factor<1 → 높고 짧게, factor>1 → 낮고 길게 (변형 제작용)."""
    n = int(len(x) * factor)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def _lfilter(b, a, x):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        y[i] = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, y[i]
    return y


def bq(x, f0, q, typ):
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / (2 * q)
    cw = np.cos(w)
    if typ == 'hp':
        b = np.array([(1 + cw) / 2, -(1 + cw), (1 + cw) / 2])
    else:
        b = np.array([(1 - cw) / 2, 1 - cw, (1 - cw) / 2])
    a = np.array([1 + al, -2 * cw, 1 - al])
    return _lfilter(b / a[0], a / a[0], x)


def best_window(x, sec):
    """RMS가 가장 큰 구간을 찾는다 — 휘익의 '지나가는 순간'."""
    n = int(SR * sec)
    e = np.convolve(x * x, np.ones(n) / n, 'valid')
    i = int(np.argmax(e))
    return x[i:i + n].copy()


def env_shape(x, attack=0.012, tail=0.06):
    na, nt = int(SR * attack), int(SR * tail)
    x[:na] *= np.linspace(0, 1, na) ** 0.7
    x[-nt:] *= np.linspace(1, 0, nt) ** 1.5
    return x


def thump(freq=100.0, dur=0.09, decay=0.02):
    """충돌 순간의 저역 몸통 — 클릭만으로는 '맞았다'는 무게가 없다."""
    t = np.arange(int(SR * dur)) / SR
    ph = 2 * np.pi * (freq * t - 18 * decay * (1 - np.exp(-t / decay)))  # 살짝 하강 피치
    return np.sin(ph) * np.exp(-t / decay) * (1 - np.exp(-t / 0.0012))


def mix(parts):
    n = max(len(p) + int(SR * d) for p, d, _ in parts)
    out = np.zeros(n)
    for p, d, g in parts:
        i = int(SR * d)
        out[i:i + len(p)] += p * g
    return out


def sat(x, drive=2.2):
    """소프트 새추레이션 — 피크는 그대로, RMS(체감 크기)를 올린다."""
    y = np.tanh(x * drive) / np.tanh(drive)
    return y


def save(name, x, peak_db):
    x = x / (np.abs(x).max() + 1e-9) * (10 ** (peak_db / 20))
    n = int(SR * 0.006)
    x[-n:] *= np.linspace(1, 0, n)
    x = np.clip(x, -1, 1)
    for o in OUTS:
        sf.write(os.path.join(o, name + '.wav'), x, SR, subtype='PCM_16')
    rms = 20 * np.log10(np.sqrt((x * x).mean()) + 1e-12)
    print(f"{name:14s} {len(x)/SR:5.2f}s  peak {peak_db:+.1f}dB  rms {rms:+.1f}dB")


whoosh = load(sys.argv[1])
click = load(sys.argv[2])

# ── 비행: chip_shot ────────────────────────────────────────────────
# 노이즈 플로어를 밴드로 걷어내고(200Hz~5.5kHz), 가장 힘있는 구간을 쓴다.
# 인게임 비행은 300ms지만 소리는 0.55s — 에너지 피크가 임팩트 시점(~0.28s)에
# 오도록 앞을 세우고, 나머지 0.27s는 지나간 여운으로 충돌음 밑에 깔린다.
# ("0.3s로 딱 자르니 짧아서 별로" 청취 피드백 → 꼬리를 살렸다.)
w_band = bq(bq(whoosh, 200, 0.71, 'hp'), 5500, 0.71, 'lp')
ck_soft = click[:int(SR * 0.045)].copy()
ck_soft[-int(SR * 0.01):] *= np.linspace(1, 0, int(SR * 0.01))


def shot(dur, peak_pos):
    w = best_window(w_band, dur)
    t = np.arange(len(w)) / len(w)
    # 상승(접근) → peak_pos에서 정점 → 자연 감쇠(지나감)
    env = np.where(t < peak_pos, (t / peak_pos) ** 1.4,
                   np.exp(-4.5 * (t - peak_pos) / (1 - peak_pos)))
    return env_shape(w * env, attack=0.008, tail=0.10)


# 정점 위치: 인게임에서 팅이 비행 시작 +255ms에 미리 발사되므로(출력 지연 상쇄,
# game_screen._peekWithChip 참고) 정점은 그 직전 235ms에 둔다.
# 0.012(클릭 오프셋) + 0.55×0.41 ≈ 0.238s.
for i, f in enumerate([1.0, 0.93]):
    x = mix([(resample(ck_soft, f), 0.0, 0.35),
             (resample(shot(0.55, 0.41), f), 0.012, 1.0)])
    save(f'chip_shot_{i+1}', x, -11.0)

# ── 충돌: chip_ting ────────────────────────────────────────────────
# 클릭 전체(0.25s) + 저역 썸프. 새추레이션으로 밀도 올리고 피크 -0.5dB.
ck = bq(click, 150, 0.71, 'hp')  # 럼블 제거, 트랜지언트만
for i, (f, th) in enumerate([(1.0, 105.0), (0.94, 118.0)]):
    x = mix([(resample(ck, f), 0.0, 1.0), (thump(th), 0.0, 0.9)])
    save(f'chip_ting_{i+1}', sat(x), -0.5)
