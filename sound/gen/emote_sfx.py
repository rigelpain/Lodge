"""身ぶりの小さな音。フェルトと綿の世界なので、どれも短く、やわらかく、乾いている。

felt_pat_01..03   フェルトの手袋が合う「ぽふっ」（ハイタッチ・拍手）。低い胴鳴りに、布のこすれが少し
snow_splat_01..03 雪玉が崩れる「ぼすっ」。綿の塊がつぶれる鈍い音に、粉雪の粒が少し散る
swish_01..02      腕を振る・雪玉を投げる「すっ」。袖が空気を切る、ごく小さな音
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, n_of, place, resonator, write


def felt_pat(rng):
    n = n_of(0.16)
    out = np.zeros(n)
    # 胴鳴り: 手袋の中の空気がつぶれる低い音
    body = resonator(rng.standard_normal(n), rng.uniform(210, 260), 0.985) * exp_decay(n, 0.018)
    # 布のこすれ: 中ほどの帯域の短いノイズ
    cloth = bp(rng.standard_normal(n), 700, 2600, 2) * exp_decay(n, 0.012) * 0.35
    out += lp(body, 900, 2) + cloth
    return fade(out, 0.001, 0.03)


def snow_splat(rng):
    n = n_of(0.42)
    out = np.zeros(n)
    thud = lp(rng.standard_normal(n), 500, 4) * exp_decay(n, 0.035)
    thud += resonator(rng.standard_normal(n), rng.uniform(120, 160), 0.98) * exp_decay(n, 0.03) * 0.4
    out += thud
    # 粉雪の粒が散る: まばらな小さな粒
    for _ in range(rng.integers(10, 18)):
        g = n_of(rng.uniform(0.003, 0.008))
        grain = bp(rng.standard_normal(g), 1800, 5200, 2) * np.hanning(g) * rng.uniform(0.05, 0.16)
        place(out, grain, rng.uniform(0.01, 0.22) ** 1.4)
    return fade(out, 0.002, 0.08)


def swish(rng):
    n = n_of(0.22)
    x = rng.standard_normal(n)
    # 帯域が上がって下がる（袖が速く通り過ぎる）
    t = np.linspace(0, 1, n)
    lo = 500 + 700 * np.sin(np.pi * t)
    y = np.zeros(n)
    blk = n_of(0.01)
    for s in range(0, n, blk):
        e = min(n, s + blk)
        y[s:e] = bp(x[max(0, s - blk):e], lo[s], lo[s] * 3.2, 2)[-(e - s):]
    env = ar(n, 0.07, 0.13, 1.5)
    return fade(lp(y * env, 3500, 2), 0.005, 0.03)


if __name__ == "__main__":
    for i in range(3):
        write(f"felt_pat_{i + 1:02d}.wav", felt_pat(np.random.default_rng(800 + i)), -6)
        write(f"snow_splat_{i + 1:02d}.wav", snow_splat(np.random.default_rng(810 + i)), -6)
    for i in range(2):
        write(f"swish_{i + 1:02d}.wav", swish(np.random.default_rng(820 + i)), -10)
