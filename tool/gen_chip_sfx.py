"""칩 열어보기 전용 효과음 합성 (numpy).

- chip_ting_1/2.wav : 금속 칩이 카드에 "팅" 맞는 소리 — 비조화 배음(벨) + 2ms 트랜지언트.
- chip_whoosh.wav   : 칩을 던질 때의 "슉" — 대역통과 노이즈가 스윕하며 부풀었다 꺼진다.
실행: python tool/gen_chip_sfx.py  → assets/sfx/ 에 저장.
"""
import numpy as np, wave, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')

def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    # 끝 5ms 페이드
    n = int(SR * 0.005); x[-n:] *= np.linspace(1, 0, n)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())

def ting(f0, dur=0.42, seed=0):
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * dur)) / SR
    # 원형 판(칩)의 비조화 모드 비율 근사 — 벨/심벌 계열 느낌
    ratios = [1.0, 1.58, 2.32, 2.94, 3.77, 4.62, 5.41]
    gains  = [1.0, 0.55, 0.42, 0.22, 0.18, 0.10, 0.07]
    decays = [9.0, 12.0, 16.0, 22.0, 28.0, 36.0, 44.0]   # 높은 배음이 먼저 죽는다
    x = np.zeros_like(t)
    for r, g, d in zip(ratios, gains, decays):
        f = f0 * r * (1 + rng.uniform(-0.004, 0.004))
        # 아주 미세한 비트(두 개의 근접 모드) — 금속 특유의 일렁임
        x += g * np.exp(-d * t) * (np.sin(2*np.pi*f*t) + 0.35*np.sin(2*np.pi*f*1.006*t + 0.7))
    # 타격 트랜지언트: 2.5ms 고역 노이즈 클릭
    n = int(SR * 0.0025)
    click = rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n))
    click = np.diff(np.concatenate([[0], click]))  # 고역 강조
    x[:n] += click / (np.abs(click).max() + 1e-9) * 0.9
    # 살짝의 몸통(저역 '톡') — 카드에 닿는 질감
    body_t = t[: int(SR * 0.03)]
    x[: len(body_t)] += 0.5 * np.exp(-90 * body_t) * np.sin(2*np.pi*520*body_t)
    return x

def whoosh(dur=0.34, seed=3):
    rng = np.random.default_rng(seed)
    n = int(SR * dur); t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    # 시간에 따라 중심주파수 1.2k→3.8k로 스윕하는 공진 대역통과(상태변수 필터)
    fc = 1200 + 2600 * (t / dur) ** 1.4
    q = 0.9
    lp = bp = 0.0; out = np.zeros(n)
    for i in range(n):
        f = 2 * np.sin(np.pi * fc[i] / SR)
        hp = noise[i] - lp - q * bp
        bp += f * hp
        lp += f * bp
        out[i] = bp
    env = np.sin(np.pi * (t / dur)) ** 1.6 * np.exp(-2.5 * t / dur)  # 부풀었다 꺼짐
    return out * env

save('chip_ting_1', ting(2350, seed=1))
save('chip_ting_2', ting(2620, seed=2))
save('chip_whoosh', whoosh(), peak=0.55)
# 틱: 팅의 축소판 — 높고 짧고 작다 (되튄 칩이 테이블에 닿는 소리)
save('chip_tick_1', ting(3100, dur=0.13, seed=5), peak=0.42)
save('chip_tick_2', ting(3400, dur=0.11, seed=6), peak=0.38)
print('ok')
