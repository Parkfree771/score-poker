"""비공개권 포커 칩 로티 생성기 → assets/lottie/chip.json

0~120f: 아이들(림 글린트 한 바퀴 + 미세 틸트, 루프)
120~150f: 플립(탭 반응 — 가로로 납작해졌다 펴진다)
"""
import json

W = 200
GOLD, GOLD_D, CREAM, INK = "#d6b25c", "#a8843a", "#f4e7c2", "#2b1d0e"


def col(h, a=1):
    h = h.lstrip('#')
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)] + [a]


def st(v):
    return {"a": 0, "k": v}


def kf(frames, ease=(0.42, 0.58)):
    ks = []
    for i, (t, v) in enumerate(frames):
        k = {"t": t, "s": v if isinstance(v, list) else [v]}
        if i < len(frames) - 1:
            n = len(k["s"])
            k["i"] = {"x": [ease[1]] * n, "y": [1] * n}
            k["o"] = {"x": [ease[0]] * n, "y": [0] * n}
        ks.append(k)
    return {"a": 1, "k": ks}


def tr(p=(0, 0), s=(100, 100), r=0, o=100):
    return {"ty": "tr", "p": st(list(p)), "a": st([0, 0]), "s": st(list(s)),
            "r": st(r), "o": st(o), "sk": st(0), "sa": st(0)}


def ellipse(d):
    return {"ty": "el", "p": st([0, 0]), "s": st([d, d])}


def rect(w, h, rnd=0):
    return {"ty": "rc", "p": st([0, 0]), "s": st([w, h]), "r": st(rnd)}


def fill(c, o=100):
    return {"ty": "fl", "c": st(col(c)), "o": st(o), "r": 1}


def stroke(c, w, o=100):
    return {"ty": "st", "c": st(col(c)), "o": st(o), "w": st(w), "lc": 2, "lj": 2}


def group(nm, items, t=None):
    return {"ty": "gr", "nm": nm, "it": items + [t or tr()]}


items = [
    group("shadow", [ellipse(184), fill(INK, 28)], tr(p=(0, 4))),
    group("rim", [ellipse(180), fill(GOLD), stroke(GOLD_D, 4)]),
]
for k in range(8):
    notch = group(f"notch{k}", [rect(30, 20, 4), fill(CREAM)], tr(p=(0, -80)))
    items.append({"ty": "gr", "nm": f"notchR{k}", "it": [notch, tr(r=k * 45)]})
items += [
    group("inner", [ellipse(118), fill(GOLD), stroke(CREAM, 5)]),
    group("ring", [ellipse(66), stroke(CREAM, 5)]),
    group("dot", [ellipse(22), fill(CREAM)]),
    # 림 글린트: 트림 패스가 한 바퀴 도는 밝은 호
    group("glint", [
        ellipse(150),
        {"ty": "tm", "s": kf([(0, 0), (120, 100)]), "e": kf([(0, 14), (120, 114)]),
         "o": st(0), "m": 1},
        stroke("#ffffff", 10, 55),
    ]),
]
layer = {
    "ddd": 0, "ind": 1, "ty": 4, "nm": "chip", "sr": 1,
    "ks": {
        "o": st(100),
        "r": kf([(0, -3), (60, 3), (120, -3)]),
        "p": st([100, 100, 0]), "a": st([0, 0, 0]),
        "s": kf([(0, [100, 100, 100]), (120, [100, 100, 100]),
                 (133, [8, 104, 100]), (150, [100, 100, 100])], ease=(0.3, 0.7)),
    },
    # Lottie는 목록 **앞쪽이 위**에 그려진다 — 그림자→림→…→글린트 순으로 쌓으려면 뒤집는다.
    "ao": 0, "shapes": items[::-1], "ip": 0, "op": 150, "st": 0, "bm": 0,
}
anim = {"v": "5.9.0", "fr": 60, "ip": 0, "op": 150, "w": W, "h": W, "nm": "veil-chip",
        "ddd": 0, "assets": [], "layers": [layer],
        "markers": [{"tm": 0, "cm": "idle", "dr": 120}, {"tm": 120, "cm": "flip", "dr": 30}]}
json.dump(anim, open("assets/lottie/chip.json", "w"), separators=(",", ":"))
print("wrote assets/lottie/chip.json")
