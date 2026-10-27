"""足あと。雪は粉雪のきしみ（ノイズの粒の重なり）、板は乾いた木の鳴り。

step_snow_01..06       歩く・走る一歩
step_snow_push_01..04  押しながらの踏ん張り。長く重く、圧された雪のきしみが入る
step_wood_01..04       ロッジの板の床
"""
import numpy as np

from lib import SR, bp, exp_decay, fade, hp, lp, modes, n_of, place, resonator, write


def grains(rng, dur, density, f_lo, f_hi, grain_ms=(1.0, 4.0), tilt=0.0):
    """密度 density(t) に従ってノイズの粒をまく。粒は短いノイズを 2 極の共鳴に通したもの。
    tilt > 0 で後の粒ほど高く（つま先）"""
    n = n_of(dur)
    out = np.zeros(n)
    t = np.arange(n) / SR
    dens = density(t)
    expected = dens.sum() / SR
    count = rng.poisson(expected)
    cdf = np.cumsum(dens)
    cdf /= cdf[-1]
    times = np.interp(rng.uniform(0, 1, count), cdf, t)
    for at in times:
        f = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi))) * (1 + tilt * at / dur)
        f = min(f, 12000)
        gl = n_of(rng.uniform(*grain_ms) / 1000)
        burst = rng.standard_normal(gl) * exp_decay(gl, gl / SR / 3)
        g = resonator(np.concatenate([burst, np.zeros(gl)]), f, rng.uniform(0.95, 0.985))
        g *= rng.uniform(0.4, 1.0)
        place(out, g, at)
    return out


def snow_step(rng, push=False):
    if push:
        dur = rng.uniform(0.34, 0.46)
        heel_tau, toe_at = 0.07, 0.68
        total = rng.uniform(900, 1300)
    else:
        dur = rng.uniform(0.17, 0.24)
        heel_tau, toe_at = 0.035, 0.6
        total = rng.uniform(380, 560)

    def density(t):
        heel = np.exp(-t / heel_tau)
        toe = 0.45 * np.exp(-0.5 * ((t - toe_at * dur) / (0.03 if not push else 0.05)) ** 2)
        d = heel + toe
        return d / d.sum() * total * SR

    x = grains(rng, dur, density, 1600, 7500, tilt=0.5)
    # 踏んだ重み。低いどすん、小さく
    nth = n_of(0.05)
    thump = lp(rng.standard_normal(nth), 220, 2) * exp_decay(nth, 0.012)
    place(x, thump * (0.9 if push else 0.5) * np.max(np.abs(x)) / (np.max(np.abs(thump)) + 1e-9), 0.0)
    if push:
        # 圧された雪のきしみ。細かいパルスの列が速まりながら共鳴を通る
        ck = n_of(0.22)
        rate = np.linspace(60, 170, ck)
        phase = np.cumsum(rate) / SR
        pulses = np.diff(np.floor(phase), prepend=0)
        creak = resonator(pulses, rng.uniform(900, 1500), 0.99)
        creak = creak * np.sin(np.pi * np.arange(ck) / ck) ** 1.5
        creak = creak / (np.max(np.abs(creak)) + 1e-9) * 0.22 * np.max(np.abs(x))
        place(x, creak, 0.08)
    x = hp(x, 140, 2)
    x = lp(x, 11000, 2)   # 雪が吸う。こもらない程度に
    return fade(x, 0.001, 0.03)


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
        write(f"step_snow_{i + 1:02d}.wav", snow_step(np.random.default_rng(100 + i)), -6)
    for i in range(4):
        write(f"step_snow_push_{i + 1:02d}.wav", snow_step(np.random.default_rng(200 + i), push=True), -5)
    for i in range(4):
        write(f"step_wood_{i + 1:02d}.wav", wood_step(np.random.default_rng(300 + i)), -8)
