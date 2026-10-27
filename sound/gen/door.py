"""風除室の戸。木の戸に金具。

door_open   取っ手の金具、木のこすれ、止まる音
door_close  木のどん、少し遅れて金具のかちり
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, lp, modes, n_of, place, write


def latch(rng, n):
    m = modes(n, np.array([2600, 4100, 6300]) * rng.uniform(0.95, 1.05), [0.02, 0.015, 0.01], [1.0, 0.6, 0.3], rng)
    c = bp(rng.standard_normal(n), 2000, 8000, 2) * exp_decay(n, 0.0012)
    return m * 0.6 + c * 0.6


def thud(rng, n, scale=1.0):
    body = modes(n, np.array([85, 140, 230, 360]) * scale, [0.12, 0.08, 0.05, 0.03], [1.0, 0.6, 0.35, 0.2], rng)
    mid = bp(rng.standard_normal(n), 300, 1500, 2) * exp_decay(n, 0.008)
    return body * 0.8 + mid * 0.5


def door_open(rng):
    out = np.zeros(n_of(1.1))
    place(out, latch(rng, n_of(0.1)) * 0.5, 0.0)
    # 木のこすれ（蝶番と敷居）
    n = n_of(0.55)
    rub = bp(rng.standard_normal(n), 250, 900, 2) * ar(n, 0.12, 0.3, 1.3)
    rub += bp(rng.standard_normal(n), 1800, 3200, 2) * ar(n, 0.2, 0.25) * 0.15
    place(out, rub / (np.max(np.abs(rub)) + 1e-9) * 0.35, 0.12)
    place(out, thud(rng, n_of(0.25), 1.2) * 0.45, 0.7)
    return fade(out, 0.0005, 0.08)


def door_close(rng):
    out = np.zeros(n_of(0.8))
    place(out, thud(rng, n_of(0.45)), 0.0)
    place(out, latch(rng, n_of(0.1)) * 0.7, 0.07)
    return fade(out, 0.0003, 0.1)


if __name__ == "__main__":
    write("door_open.wav", door_open(np.random.default_rng(900)), -8)
    write("door_close.wav", door_close(np.random.default_rng(901)), -5)
