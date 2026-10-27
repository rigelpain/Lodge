"""厨房と食堂。鍋の湯気、鍋の蓋、食器。乾いた部屋の中の小さな音。

pot_steam_loop  湯気の細い音と、ときどきの泡
pot_lid_01..03  金属の蓋がかたかた
dish_01..06     陶の器が触れる。木の卓に置く音も
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, lp, modes, n_of, place, place_wrap, seamless, slow_random, write


def steam_loop(rng):
    n = n_of(6.6)
    white = rng.standard_normal(n)
    hiss = bp(white, 2500, 9500, 2) * (1 + 0.35 * slow_random(n, 1.5, rng))
    x = hiss / np.std(hiss)
    # 泡: 上がりながら消える短い正弦
    for at in rng.uniform(0, 6.6, 40):
        k = n_of(rng.uniform(0.04, 0.09))
        t = np.arange(k) / SR
        f0 = rng.uniform(260, 700)
        f = f0 * (1 + 0.6 * t / t[-1])
        ph = 2 * np.pi * np.cumsum(f) / SR
        b = np.sin(ph) * exp_decay(k, k / SR / 3) * rng.uniform(0.15, 0.45)
        place_wrap(x, b, at)
    return seamless(x, 0.5)


def lid(rng):
    out = np.zeros(n_of(0.65))
    hits = rng.integers(2, 5)
    t = 0.0
    base = np.array([1250, 2900, 4400, 6100, 7800]) * rng.uniform(0.95, 1.05)
    for k in range(hits):
        n = n_of(0.3)
        m = modes(n, base, [0.09, 0.06, 0.045, 0.03, 0.02], [1.0, 0.7, 0.5, 0.35, 0.2], rng, 0.01)
        click = bp(rng.standard_normal(n), 3000, 9000, 2) * exp_decay(n, 0.0015)
        h = (m * 0.8 + click * 0.4) * rng.uniform(0.4, 1.0) * (1.0 if k == 0 else 0.7)
        place(out, h, t)
        t += rng.uniform(0.04, 0.12)
    return fade(out, 0.0003, 0.05)


def dish(rng, on_table=False):
    out = np.zeros(n_of(0.75))
    scale = rng.uniform(0.85, 1.2)
    base = np.array([1850, 3400, 5600, 7900, 9800]) * scale
    n = n_of(0.6)
    ring = modes(n, base, [0.22, 0.14, 0.09, 0.05, 0.03], [1.0, 0.6, 0.45, 0.25, 0.12], rng, 0.01)
    tick = bp(rng.standard_normal(n), 2500, 9000, 2) * exp_decay(n, 0.001)
    x = ring * 0.7 + tick * 0.3
    place(out, x, 0.0)
    if rng.uniform() < 0.5:
        # 二つ目が触れる
        ring2 = modes(n, base * rng.uniform(0.9, 1.1), [0.15, 0.1, 0.07, 0.04, 0.02], [0.8, 0.5, 0.4, 0.2, 0.1], rng, 0.01)
        place(out, ring2 * rng.uniform(0.3, 0.7), rng.uniform(0.05, 0.15))
    if on_table:
        nt = n_of(0.08)
        thud = lp(rng.standard_normal(nt), 320, 2) * exp_decay(nt, 0.012)
        thud += modes(nt, [140, 210], [0.04, 0.03], [1.0, 0.5], rng)
        place(out, thud / (np.max(np.abs(thud)) + 1e-9) * 0.9, 0.0)
    return fade(out, 0.0003, 0.12)


if __name__ == "__main__":
    write("pot_steam_loop.wav", steam_loop(np.random.default_rng(800)), -12)
    for i in range(3):
        write(f"pot_lid_{i + 1:02d}.wav", lid(np.random.default_rng(810 + i)), -10)
    for i in range(6):
        write(f"dish_{i + 1:02d}.wav", dish(np.random.default_rng(820 + i), on_table=(i >= 3)), -9)
