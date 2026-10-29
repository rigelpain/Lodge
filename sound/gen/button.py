"""雪に縫い留められたボタン（game/snow_buttons.gd）の音。木のボタンと糸だけの音にする（金属の鳴りは入れない）。

button_snap_01..03  滑り木で糸がぷつんと切れる: 張った糸がはじける細いピッと、短くゆるむビン
button_pop_01..03   ボタンがぽんと跳ね上がる: 栓が抜けるような上がる「ぽ」と、木の円板のコン
button_land_01..02  空から降ってきたボタンが雪に着く: 綿の雪にぽふ
button_sew_01       落ちた所に糸がするっと縫い付く: 糸が穴を抜けるするっと、締まるキュッ
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, modes, moving_resonator, n_of, place, write


def wood(rng, n, f0, decay=0.03):
    """木の円板が鳴るコン"""
    return modes(n, np.array([1.0, 2.31, 3.95, 5.6]) * f0 * rng.uniform(0.97, 1.03),
                 [decay, decay * 0.55, decay * 0.32, decay * 0.2], [1.0, 0.5, 0.28, 0.12], rng)


def snap(rng):
    out = np.zeros(n_of(0.22))
    n = n_of(0.02)
    tick = bp(rng.standard_normal(n), 2500, 9000, 2) * exp_decay(n, 0.0012)   # 張った糸がはじける
    place(out, tick, 0.0)
    n = n_of(0.16)
    t = np.arange(n) / SR
    f = rng.uniform(520, 640) * (1.0 - 0.45 * (1 - np.exp(-t / 0.03)))        # ゆるみながら下がるビン
    twang = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.035)
    twang += 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.02)
    place(out, twang * 0.35, 0.002)
    return fade(out, 0.0002, 0.04)


def pop(rng):
    out = np.zeros(n_of(0.35))
    n = n_of(0.09)
    t = np.arange(n) / SR
    f = 260 + 520 * (1 - np.exp(-t / 0.02)) * rng.uniform(0.9, 1.1)            # 栓が抜ける「ぽ」: 上がる共鳴
    puff = lp(rng.standard_normal(n), 2500, 2) * ar(n, 0.002, 0.08, 2.0)
    po = moving_resonator(puff, f, 0.995)
    place(out, po / np.max(np.abs(po)), 0.0)
    place(out, wood(rng, n_of(0.25), rng.uniform(640, 760), 0.04) * 0.55, 0.012)   # 木のコン
    return fade(out, 0.0005, 0.06)


def land(rng):
    n = n_of(0.25)
    p = lp(rng.standard_normal(n), 900, 2) * ar(n, 0.006, 0.2, 2.5)
    body = wood(rng, n, rng.uniform(380, 450), 0.012) * 0.25                 # 雪ごしの、こもった木
    return fade(p / np.max(np.abs(p)) + body, 0.001, 0.05)


def sew(rng):
    out = np.zeros(n_of(0.5))
    n = n_of(0.3)
    t = np.arange(n) / SR
    f = 1200 + 2400 * t / t[-1]                                              # 糸が穴を抜ける: 擦れが上がる
    rub = moving_resonator(rng.standard_normal(n), f, 0.97) * ar(n, 0.08, 0.12, 1.5)
    place(out, rub / np.max(np.abs(rub)) * 0.7, 0.0)
    m = n_of(0.05)
    tug = hp(rng.standard_normal(m), 1800) * exp_decay(m, 0.006)              # 締まるキュッ
    place(out, tug * 0.5, 0.31)
    place(out, wood(rng, n_of(0.12), 820, 0.012) * 0.3, 0.315)
    return fade(out, 0.002, 0.05)


if __name__ == "__main__":
    for i in range(3):
        write(f"button_snap_{i + 1:02d}.wav", snap(np.random.default_rng(1500 + i)), -4)
        write(f"button_pop_{i + 1:02d}.wav", pop(np.random.default_rng(1510 + i)), -4)
    for i in range(2):
        write(f"button_land_{i + 1:02d}.wav", land(np.random.default_rng(1530 + i)), -10)
    write("button_sew_01.wav", sew(np.random.default_rng(1540)), -9)
