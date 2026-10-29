"""大きなミシン（game/sewing_machine.gd）の仮の音。木とフェルトのぬいぐるみの機械なので、金属の鋭さは抑え、
木の「コト」と布の「ぷす」を土台にする。

sew_stitch_01..03  針が布を通る 1 目: 木の軸のコトと、布を刺す短いぷす
sew_hum_loop       回っているあいだの低いうなり（はずみ車と軸の木のこすれ）。ゲームで音程を上げる
sew_clack          布送りの歯のカタッ（呼ぶ・押さえが下りる）
sew_draw           布が針の下へ吸い込まれる、布のこすれ
sew_snip           糸切りのパチン
sew_pop            できたソリがふくらむ・天板へ下りる、フェルトのぽふ
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, modes, n_of, place, place_wrap, seamless, slow_random, write


def knock(rng, n, f0=900.0):
    """木の小さな部品が当たる音"""
    m = modes(n, np.array([1.0, 2.3, 3.9]) * f0 * rng.uniform(0.95, 1.05), [0.025, 0.014, 0.008], [1.0, 0.5, 0.25], rng)
    c = bp(rng.standard_normal(n), 1500, 6000, 2) * exp_decay(n, 0.0015)
    return m * 0.7 + c * 0.5


def stitch(rng):
    out = np.zeros(n_of(0.12))
    place(out, knock(rng, n_of(0.08), rng.uniform(800, 1000)), 0.0)
    n = n_of(0.035)
    poke = bp(rng.standard_normal(n), 900, 3500, 2) * ar(n, 0.003, 0.03, 2.0)   # 布を刺す
    place(out, poke * 0.5, 0.012)
    return fade(out, 0.0005, 0.02)


def hum_loop(rng):
    n = n_of(4.25)
    t = np.arange(n) / SR
    # 低いうなり: 軸の回転（ゲームで pitch_scale を上げる）と、木のこすれ
    base = 0.6 * np.sin(2 * np.pi * 55 * t) + 0.3 * np.sin(2 * np.pi * 110 * t + 0.5) + 0.12 * np.sin(2 * np.pi * 165 * t)
    base *= 1 + 0.15 * np.sin(2 * np.pi * 4.0 * t)
    rub = bp(rng.standard_normal(n), 200, 900, 2) * (0.6 + 0.4 * slow_random(n, 3.0, rng))
    x = base * 0.5 + rub / np.std(rub) * 0.25
    return seamless(lp(x, 2500), 0.25)


def clack(rng):
    out = np.zeros(n_of(0.2))
    place(out, knock(rng, n_of(0.1), 1300), 0.0)
    place(out, knock(rng, n_of(0.1), 950) * 0.7, 0.045)
    return fade(out, 0.0005, 0.03)


def draw(rng):
    n = n_of(0.7)
    swish = bp(rng.standard_normal(n), 600, 4500, 2) * ar(n, 0.35, 0.3, 1.5)   # だんだん強く、すっと止まる
    swish *= 1 + 0.3 * slow_random(n, 12.0, rng)
    out = swish / np.max(np.abs(swish))
    place(out, knock(rng, n_of(0.08), 700) * 0.4, 0.6)
    return fade(out, 0.01, 0.04)


def snip(rng):
    """はさみの刃が合わさるパチン: 高い金属の鳴りは短く、木の柄のコトを重ねる"""
    out = np.zeros(n_of(0.35))
    n = n_of(0.25)
    ring = modes(n, np.array([3100, 4700, 6900]) * rng.uniform(0.98, 1.02), [0.03, 0.02, 0.012], [1.0, 0.6, 0.3], rng)
    crack = hp(rng.standard_normal(n), 3000) * exp_decay(n, 0.0009)
    place(out, ring * 0.5 + crack * 0.9, 0.0)
    place(out, knock(rng, n_of(0.1), 600) * 0.6, 0.004)
    return fade(out, 0.0002, 0.05)


def pop(rng):
    n = n_of(0.3)
    body = modes(n, np.array([140, 230, 380]), [0.05, 0.03, 0.02], [1.0, 0.5, 0.25], rng)
    puff = lp(rng.standard_normal(n), 1200, 2) * ar(n, 0.004, 0.12, 2.0)
    return fade(body * 0.8 + puff / np.max(np.abs(puff)) * 0.5, 0.001, 0.05)


if __name__ == "__main__":
    for i in range(3):
        write(f"sew_stitch_{i + 1:02d}.wav", stitch(np.random.default_rng(1200 + i)), -6)
    write("sew_hum_loop.wav", hum_loop(np.random.default_rng(1210)), -10)
    write("sew_clack.wav", clack(np.random.default_rng(1211)), -6)
    write("sew_draw.wav", draw(np.random.default_rng(1212)), -8)
    write("sew_snip.wav", snip(np.random.default_rng(1213)), -3)
    write("sew_pop.wav", pop(np.random.default_rng(1214)), -6)
