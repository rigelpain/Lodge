"""風。麓は薄く、高いほど強い。滑走では体のまわりで低い帯域がうねる。

wind_loop       外にいつもある薄い風。中心が 200〜900 Hz をゆっくり移る
wind_rush_loop  滑走の風。広い帯域のうなりと、耳元の低い揺さぶり
"""
import numpy as np

from lib import SR, lp, moving_resonator, n_of, seamless, slow_random, write

LOOP = 10.0


def calm_loop(rng):
    n = n_of(LOOP + 0.6)
    white = rng.standard_normal(n)
    # 低い土台
    low = lp(white, 350, 2)
    low *= 1 + 0.7 * slow_random(n, 0.18, rng)
    # 移ろう中心（200〜900 Hz）
    center = 450 * 2 ** (0.9 * slow_random(n, 0.12, rng))
    center = np.clip(center, 180, 1000)
    howl = moving_resonator(white, center, 0.996)
    howl *= 1 + 0.9 * slow_random(n, 0.22, rng)
    howl = np.clip(howl, -3, 3)
    # かすかな高い息
    hiss = lp(white, 5000, 2) * (1 + 0.6 * slow_random(n, 0.3, rng))
    x = low / np.std(low) * 0.8 + howl / np.std(howl) * 1.1 + hiss / np.std(hiss) * 0.12
    return seamless(x, 0.6)


def rush_loop(rng):
    n = n_of(LOOP + 0.6)
    white = rng.standard_normal(n)
    # ピンク寄りの広い帯域
    body = lp(white, 2500, 1) + lp(white, 9000, 2) * 0.4
    turb = 1 + 0.5 * slow_random(n, 4.0, rng) + 0.3 * slow_random(n, 0.6, rng)
    body *= np.clip(turb, 0.2, 2.5)
    # 耳元の揺さぶり
    buffet = lp(white, 70, 2) * (1 + 0.8 * slow_random(n, 2.0, rng))
    x = body / np.std(body) + buffet / np.std(buffet) * 0.7
    return seamless(x, 0.6)


if __name__ == "__main__":
    write("wind_loop.wav", calm_loop(np.random.default_rng(600)), -6)
    write("wind_rush_loop.wav", rush_loop(np.random.default_rng(601)), -3)
