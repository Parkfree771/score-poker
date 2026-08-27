"""칩 열어보기 효과음 — Kenney CC0 실사 샘플을 레이어링해 "쾌감 있는" 슛/팅을 만든다.

  python tool/gen_chip_sfx.py <kenney_impact-sounds 폴더> <kenney_casino-audio 폴더>

  출처(CC0, 표기 불요): https://kenney.nl/assets/impact-sounds · https://kenney.nl/assets/casino-audio

- chip_shot_1/2.wav : 칩을 쏘는 순간 — 칩 충돌 클릭(chips-collide, 6.5kHz 트랜지언트)이
                      "탁" 하고 붙고, 그 뒤로 80ms짜리 짧고 날카로운 스윕이 "슛" 하고 빠진다.
- chip_ting_1/2.wav : 칩이 카드에 맞는 순간 — 밝은 금속판 링(impactPlate_light, ~4kHz)
                      + 클릭(chips-collide) + 저역 몸통(impactGeneric_light). 어택 0ms,
                      링은 0.28s에서 잘라 다음 소리(틱)와 안 겹친다.
합성만으로 만든 옛 버전은 '띵' 하고 얇았다 — 실사 트랜지언트가 있어야 손맛이 난다.
"""
import os, sys, glob
import numpy as np, soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
IMPACT, CASINO = sys.argv[1], sys.argv[2]

def load(folder, name):
    path = glob.glob(os.path.join(folder, '**', name), recursive=True)[0]
    x, sr = sf.read(path, always_2d=True); x = x.mean(1)
    if sr != SR:
        x = np.interp(np.linspace(0, len(x) - 1, int(len(x) * SR / sr)), np.arange(len(x)), x)
    # 앞 무음 제거(피크의 1% 이상이 나오는 첫 샘플부터) — 어택이 0ms에 오게.
    i = np.flatnonzero(np.abs(x) > np.abs(x).max() * 0.01)[0]
    return x[i:] / (np.abs(x).max() + 1e-9)

def cut(x, sec, fade=0.03):
    n = min(len(x), int(SR * sec)); x = x[:n].copy()
    f = int(SR * fade); x[-f:] *= np.linspace(1, 0, f) ** 1.5
    return x

def mix(parts):
    n = max(len(p) + int(SR * d) for p, d, _ in parts)
    out = np.zeros(n)
    for p, delay, gain in parts:
        i = int(SR * delay); out[i:i + len(p)] += p * gain
    return out

def save(name, x, peak=0.95):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    n = int(SR * 0.005); x[-n:] *= np.linspace(1, 0, n)
    sf.write(os.path.join(OUT, name + '.wav'), np.clip(x, -1, 1), SR, subtype='PCM_16')
    print('wrote', name, f'{len(x)/SR:.2f}s')

def sweep(dur=0.085, f_hi=5200, f_lo=900, seed=0):
    """짧고 날카로운 하강 스윕 노이즈 — '슛'. 부풀지 않고 즉시 터져 빠르게 꺼진다."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur); t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    fc = f_hi * (f_lo / f_hi) ** (t / dur)
    lp = bp = 0.0; out = np.zeros(n)
    for i in range(n):
        f = 2 * np.sin(np.pi * fc[i] / SR)
        hp = noise[i] - lp - 1.1 * bp
        bp += f * hp; lp += f * bp; out[i] = bp
    env = np.exp(-9 * t / dur) * (1 - np.exp(-t / 0.002))
    return out / (np.abs(out).max() + 1e-9) * env

# ---- 슛: 클릭 "탁" + 스윕 "슛"
for k, (click, seed) in enumerate([('chips-collide-4.ogg', 1), ('chips-collide-1.ogg', 2)], 1):
    c = cut(load(CASINO, click), 0.06, fade=0.02)
    save(f'chip_shot_{k}', mix([(c, 0.0, 1.0), (sweep(seed=seed), 0.004, 0.7)]), peak=0.8)

# ---- 팅: 금속판 링 + 클릭 + 저역 몸통
for k, (plate, click, body) in enumerate([
    ('impactPlate_light_003.ogg', 'chips-collide-2.ogg', 'impactGeneric_light_000.ogg'),
    ('impactPlate_light_000.ogg', 'chips-collide-3.ogg', 'impactGeneric_light_002.ogg'),
], 1):
    ring = cut(load(IMPACT, plate), 0.28, fade=0.08)
    c = cut(load(CASINO, click), 0.04, fade=0.01)
    b = cut(load(IMPACT, body), 0.06, fade=0.02)
    save(f'chip_ting_{k}', mix([(c, 0.0, 1.0), (ring, 0.0, 0.9), (b, 0.0, 0.55)]))
