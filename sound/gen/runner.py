"""ソリの滑り木が雪をこする音。「しゃー」の 1 本を、Godot 側で速さに応じて音量とピッチを変える。

runner_fast_loop  高く連続した「しゃー」
（止まりかけの「ざ、ざ」の遅いループは、代表が要らないと言ったので 2026-10-27 に外した。
  作り方は slow_loop() に残す。--slow で書ける）
"""
import numpy as np

from lib import SR, bp, exp_decay, lp, n_of, peak_eq, place_wrap, resonator, seamless, slow_random, write

LOOP = 4.0


def slow_loop(rng):
    n = n_of(LOOP + 0.3)
    base = bp(rng.standard_normal(n), 150, 900, 2)
    # 不揃いな塊: 4〜6 Hz くらいで押しては止まる
    env = np.full(n, 0.12)
    t = 0.0
    while t < LOOP + 0.3:
        k = n_of(rng.uniform(0.06, 0.16))
        burst = np.concatenate([np.linspace(0, 1, n_of(0.012)), exp_decay(k, 0.045)])
        i = n_of(t)
        m = min(len(burst), n - i)
        env[i:i + m] += burst[:m] * rng.uniform(0.5, 1.0)
        t += rng.uniform(0.12, 0.28)
    x = base * env
    # 木の台の鳴り
    x += resonator(x, 230, 0.985) * 0.2
    # 粗い粒（押しつぶされる雪）
    g = np.zeros(n)
    for at in rng.uniform(0, LOOP + 0.3, 260):
        gl = n_of(rng.uniform(0.002, 0.006))
        b = rng.standard_normal(gl) * exp_decay(gl, 0.0015)
        b = resonator(np.concatenate([b, np.zeros(gl)]), rng.uniform(700, 2600), 0.97)
        place_wrap(g, b * rng.uniform(0.3, 1.0), at)
    x += g * 0.5 * env / (np.max(env) + 1e-9) * np.max(np.abs(x)) / (np.max(np.abs(g)) + 1e-9)
    return seamless(x, 0.3)


def fast_loop(rng):
    n = n_of(LOOP + 0.3)
    x = bp(rng.standard_normal(n), 800, 7000, 2)
    x = peak_eq(peak_eq(x, 1900, 5, 1.8), 3300, 4, 2.5)
    # 細かな揺らぎ（雪面の起伏）
    flutter = 1 + 0.28 * slow_random(n, 14, rng)
    x *= flutter
    # 滑り木の振動の低い唸り
    rumble = lp(rng.standard_normal(n), 170, 2)
    rumble *= 1 + 0.5 * slow_random(n, 3, rng)
    x = x / np.max(np.abs(x)) + rumble / np.max(np.abs(rumble)) * 0.2
    return seamless(x, 0.3)


if __name__ == "__main__":
    import sys
    if "--slow" in sys.argv:
        write("runner_slow_loop.wav", slow_loop(np.random.default_rng(500)), -6)
    write("runner_fast_loop.wav", fast_loop(np.random.default_rng(501)), -4)
