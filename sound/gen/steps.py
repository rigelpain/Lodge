"""足あと。雪は、片栗粉を握ったときの「ギュッ」。板は乾いた木の鳴り。

雪の音は粒の重なりではなく、狭い帯域の鳴きが短く上ずるもの。冷えた粉雪を踏むと
粒どうしがこすれて止まり、を細かく繰り返して鳴く（片栗粉と同じ）。小さく、短く。

step_snow_01..06       歩く・走る一歩。60〜95 ms の「キュッ」
step_snow_push_01..04  押しながらの踏ん張り。長めに「ギュ…ッ」と上ずり、揺れが入る
step_wood_01..04       ロッジの板の床
"""
import numpy as np

from lib import SR, bp, exp_decay, fade, hp, lp, modes, moving_resonator, n_of, place, write


def squeak(rng, dur, f0, f1, r=0.997, chatter=(90, 160), rough=0.45, curve=0.45):
    """f0 から f1 へ上ずる狭い鳴き。chatter Hz のこすれ止まりの揺れを乗せる"""
    n = n_of(dur)
    t = np.linspace(0, 1, n)
    f = f0 * (f1 / f0) ** (t ** curve)
    white = rng.standard_normal(n)
    x = moving_resonator(white, f, r)
    x += moving_resonator(white, np.minimum(f * 2.0, 16000), r) * 0.25   # 倍音で少し張る
    # こすれ止まりの揺れ（不揃い）
    ch = rng.uniform(*chatter)
    ph = 2 * np.pi * np.cumsum(ch * (1 + 0.25 * lp(rng.standard_normal(n), 40, 1) / 0.3)) / SR
    x *= 1 - rough * 0.5 * (1 + np.sin(ph + rng.uniform(0, 6.28)))
    env = np.ones(n)
    a = n_of(0.004)
    env[:a] = np.linspace(0, 1, a)
    rel = n_of(dur * 0.35)
    env[-rel:] *= np.linspace(1, 0, rel) ** 1.5
    return x * env / (np.max(np.abs(x)) + 1e-9)


def snow_step(rng, push=False):
    if push:
        dur = rng.uniform(0.17, 0.26)
        f0 = rng.uniform(1300, 1800)
        x = squeak(rng, dur, f0, f0 * rng.uniform(1.5, 1.9), r=0.996, chatter=(60, 110), rough=0.6, curve=0.7)
        out = np.zeros(n_of(dur + 0.08))
        place(out, x, 0.0)
        # 踏ん張りの終わりに、短くもう一度「ッ」
        if rng.uniform() < 0.7:
            d2 = rng.uniform(0.03, 0.05)
            x2 = squeak(rng, d2, f0 * 1.6, f0 * 2.1, r=0.996, rough=0.3)
            place(out, x2 * 0.6, dur * 0.92)
        press_gain = 0.35
    else:
        dur = rng.uniform(0.06, 0.095)
        f0 = rng.uniform(1700, 2500)
        x = squeak(rng, dur, f0, f0 * rng.uniform(1.3, 1.75))
        out = np.zeros(n_of(dur + 0.05))
        place(out, x, 0.0)
        press_gain = 0.22
    # 踏んだ重み。低く小さく、鳴きの下に
    nth = n_of(0.035)
    press = lp(rng.standard_normal(nth), 220, 2) * exp_decay(nth, 0.009)
    place(out, press / (np.max(np.abs(press)) + 1e-9) * press_gain, 0.0)
    out = hp(out, 300, 2)
    out = lp(out, 9000, 2)
    return fade(out, 0.001, 0.02)


def wood_step(rng):
    n = n_of(0.16)
    f = np.array([115, 180, 265, 420]) * rng.uniform(0.94, 1.06)
    body = modes(n, f, [0.07, 0.05, 0.035, 0.02], [1.0, 0.6, 0.35, 0.2], rng)
    click = bp(rng.standard_normal(n), 1800, 5200, 2) * exp_decay(n, 0.003)
    scuff = bp(rng.standard_normal(n), 400, 2000, 2) * exp_decay(n, 0.02) * 0.25
    x = body * 0.8 + click * 0.5 + scuff
    return fade(x, 0.0005, 0.03)


if __name__ == "__main__":
    for i in range(6):
        write(f"step_snow_{i + 1:02d}.wav", snow_step(np.random.default_rng(100 + i)), -9)
    for i in range(4):
        write(f"step_snow_push_{i + 1:02d}.wav", snow_step(np.random.default_rng(200 + i), push=True), -8)
    for i in range(4):
        write(f"step_wood_{i + 1:02d}.wav", wood_step(np.random.default_rng(300 + i)), -8)
