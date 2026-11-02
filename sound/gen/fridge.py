"""雪だるまの冷蔵庫の扉（2026-11-02。game/fridge_door.gd）。どれも合成で、外の素材は使わない。

扉はフェルトでくるんだ綿の板で、内に瓶の牛乳とジャムの瓶を並べた棚がある。人が近づくと 220° まで開いて、前の床に
畳んであった番台が組み立ち、離れると番台を畳んでから閉まる。

fridge_open    木の蝶番のきしみ、扉があおる空気の「ふわっ」、止まるときに棚の瓶が「かちゃ」
fridge_close   閉まる「ぽす」（綿を詰めた扉がパッキンに当たる）、少し遅れて棚の瓶が「かちん」
stall_flap     畳める番台の板が起きて止まる・床に寝る「ぱたん」（藍のフェルトを張った木の板。木のこつんを布でくるむ）
stall_tap      横の板・天板が開いて止まる、小さな「ぱた」
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, lp, modes, n_of, place, write


def creak(rng, dur, f0, f1):
    """木の蝶番のきしみ: 高さがゆっくり上がる、こすれの多いうなり（小さく）"""
    n = n_of(dur)
    t = np.arange(n) / SR
    f = f0 + (f1 - f0) * t / dur + 12 * np.sin(2 * np.pi * 7 * t)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    rub = bp(rng.standard_normal(n), 500, 2200, 2)
    return (tone * 0.5 + rub * 0.8) * ar(n, dur * 0.3, dur * 0.6, 1.5)


def swish(rng, dur):
    """扉があおる空気: 低い帯域のノイズがふくらんでしぼむ"""
    n = n_of(dur)
    return bp(rng.standard_normal(n), 120, 900, 2) * ar(n, dur * 0.45, dur * 0.55, 1.4)


def clink(rng, f0):
    """棚の瓶どうしが触れる: 小さなガラスの「かちっ」"""
    n = n_of(0.25)
    ring = modes(n, np.array([1.0, 1.47, 2.32, 3.61]) * f0, [0.018, 0.012, 0.008, 0.005], [1.0, 0.7, 0.5, 0.3], rng)
    tick = bp(rng.standard_normal(n), 2500, 9000, 2) * exp_decay(n, 0.002)
    return ring * 0.4 + tick * 0.7


def bump(rng, dur=0.35):
    """綿を詰めた扉が止まる「ぽす」: 低いノイズの塊と、布の空気が抜ける短い「ふっ」（音程を持たせない）"""
    n = n_of(dur)
    body = lp(rng.standard_normal(n), 220, 4) * ar(n, 0.025, dur * 0.6, 1.8)
    body += bp(rng.standard_normal(n), 80, 400, 2) * ar(n, 0.015, dur * 0.35, 2.0) * 0.6
    air = bp(rng.standard_normal(n), 300, 1000, 2) * ar(n, 0.04, 0.18, 2.0) * 0.12
    return lp(body + air, 900)


def flap(rng, size=1.0):
    """布を張った木の板が当たる: 木の短いこつん（高い倍音を布で落とす）と、布の空気の「ぱふ」"""
    n = n_of(0.3)
    knock = modes(n, np.array([180, 410, 690, 1150]) * size * rng.uniform(0.95, 1.05), [0.05, 0.03, 0.018, 0.01],
                  [1.0, 0.55, 0.3, 0.15], rng)
    puff = bp(rng.standard_normal(n), 200, 1200, 2) * ar(n, 0.004, 0.08, 2.0) * 0.6
    return lp(knock * 0.8 + puff, 2500)


def fridge_open(rng):
    out = np.zeros(n_of(1.4))
    place(out, creak(rng, 0.45, 260, 340) * 0.12, 0.0)
    place(out, swish(rng, 0.8) * 0.7, 0.05)
    place(out, bump(rng, 0.25) * 0.35, 0.78)    # 開ききって止まる
    for at, f0, g in ((0.8, 2900, 0.18), (0.87, 3400, 0.12), (0.97, 3100, 0.07)):
        place(out, clink(rng, f0 * rng.uniform(0.97, 1.03)) * g, at)
    return fade(out, 0.002, 0.12)


def fridge_close(rng):
    out = np.zeros(n_of(0.9))
    place(out, bump(rng) * 1.0, 0.0)
    for at, f0, g in ((0.06, 3200, 0.15), (0.14, 2800, 0.08)):
        place(out, clink(rng, f0 * rng.uniform(0.97, 1.03)) * g, at)
    return fade(out, 0.0005, 0.12)


if __name__ == "__main__":
    write("fridge_open.wav", fridge_open(np.random.default_rng(1100)), -10)
    write("fridge_close.wav", fridge_close(np.random.default_rng(1101)), -8)
    write("stall_flap.wav", fade(flap(np.random.default_rng(1102), 0.85), 0.0005, 0.08), -8)
    write("stall_tap.wav", fade(flap(np.random.default_rng(1103), 1.2) * 0.6, 0.0005, 0.06), -12)
