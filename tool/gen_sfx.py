# -*- coding: utf-8 -*-
# 효과음 합성기 — 외부 음원 없이 순수 합성(라이선스 문제 원천 차단).
# 실행: python tool/gen_sfx.py  →  assets/sfx/*.wav
import math, random, struct, wave

SR = 44100
random.seed(7)

def env_exp(n, decay):  # 지수 감쇠
    return [math.exp(-i / (SR * decay)) for i in range(n)]

def sine(freq, n, phase=0.0):
    return [math.sin(2 * math.pi * freq * i / SR + phase) for i in range(n)]

def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]

def lowpass(x, alpha):
    y, prev = [], 0.0
    for v in x:
        prev += alpha * (v - prev)
        y.append(prev)
    return y

def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out

def gain(x, g):
    return [v * g for v in x]

def delay(x, sec):
    return [0.0] * int(SR * sec) + x

def normalize(x, peak=0.85):
    m = max(abs(v) for v in x) or 1.0
    return [v / m * peak for v in x]

def fade_out(x, sec=0.01):
    n = int(SR * sec)
    for i in range(n):
        x[-n + i] *= 1 - i / n
    return x

def save(name, x):
    x = fade_out(normalize(x))
    with wave.open(f'assets/sfx/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in x))
    print('ok', name)

# 1~2) 카드 배치·비행·타격음은 전부 실사(tool/import_sfx.py, Kenney CC0)가 만든다.
#      합성 whoosh는 8비트처럼 들려 폐기 — 돌진음도 실사 카드 슬라이드를 쓴다.

# 3) 쉴드: 금속성 딩 — 비배음 파셜 3개
n = int(SR * 0.5)
def partial(freq, dec, g, n):
    return gain([s * e for s, e in zip(sine(freq, n), env_exp(n, dec))], g)
save('shield', mix(partial(523, 0.16, 0.9, n), partial(1307, 0.10, 0.5, n), partial(2093, 0.06, 0.3, n)))

# 4) 토큰 사용: 동전 핑 2연타
def ping(freq, dur, g):
    n = int(SR * dur)
    return gain([s * e for s, e in zip(sine(freq, n), env_exp(n, 0.05))], g)
save('token', mix(ping(988, 0.18, 0.8), delay(ping(1319, 0.22, 0.8), 0.09)))

# 5) 승리: 상승 아르페지오 C5-E5-G5-C6 (플럭 톤)
def pluck(freq, dur, g):
    n = int(SR * dur)
    fund = [s * e for s, e in zip(sine(freq, n), env_exp(n, 0.12))]
    harm = [s * e for s, e in zip(sine(freq * 2, n), env_exp(n, 0.06))]
    return gain(mix(fund, gain(harm, 0.35)), g)
save('win', mix(
    pluck(523.25, 0.5, 0.7), delay(pluck(659.25, 0.5, 0.7), 0.12),
    delay(pluck(783.99, 0.5, 0.7), 0.24), delay(pluck(1046.5, 0.8, 0.85), 0.36),
))

# 5.5) 공개 스팅: "두-둥" — 낮은 북 두 방. 카드 공개·대결 판정의 예고음.
def drum(freq, dur, g, decay=0.09):
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        f = freq * (1 + 0.6 * math.exp(-i / (SR * 0.015)))  # 피치가 툭 떨어지는 북
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * math.exp(-i / (SR * decay)))
    return gain(out, g)
save('sting', mix(drum(72, 0.35, 0.75), delay(drum(58, 0.7, 1.0, decay=0.16), 0.26)))

# 6) 패배: 하강 두 음 (부드러운 웜프)
def soft(freq, dur, g, slide=0.0):
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        f = freq * (1 + slide * i / n)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * math.exp(-i / (SR * 0.25)))
    return gain(out, g)
save('lose', mix(soft(311.1, 0.45, 0.7), delay(soft(233.1, 0.7, 0.8, slide=-0.06), 0.28)))
