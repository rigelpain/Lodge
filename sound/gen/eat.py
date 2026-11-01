"""手の料理を食べる音（2026-11-01。design/snowman-food/）。紙の人形の小さな口の、小さくやわらかい音。合成で、外の素材は使わない。

eat_chew_01..04    やわらかい物をもぐもぐ（おにぎり・肉まん・ホットケーキ・焼き芋・サンマ・牡蠣）: こもった「もぐ」
eat_crunch_01..04  皮がぱりっとした物（たい焼き・コロッケ・ハッシュドポテト・ポテト・ホットサンド）: 乾いた「さくっ」
eat_slurp_01..02   麺をすする（ラーメン・うどん・そば・焼きそば）: 息を吸う「ずずっ」が上ずる
eat_sip_01..02     飲み物をひと口（ココア・お汁粉・スープ・お茶・ミルク）: 短い「ずっ」と、飲み込む「こくっ」
eat_ah_01..02      食べ終わって、ほっと息をつく「ほっ」（言葉ではない、息の音）
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, moving_resonator, n_of, place, write


def chew(rng):
    """もぐもぐ: 口を閉じて噛む 3 回のリズム（4 回／秒）。それぞれ、ゆっくり立ち上がるこもった音と、ごく小さな湿った音"""
    out = np.zeros(n_of(0.95))
    for k in range(3):
        at = 0.24 * k + rng.uniform(0.0, 0.02)
        n = n_of(rng.uniform(0.16, 0.2))
        body = lp(rng.standard_normal(n), rng.uniform(380, 520), 4) * ar(n, 0.035, n / SR * 0.7, 1.3)
        place(out, body * (1.0, 0.8, 0.65)[k], at)
        for j in range(rng.integers(2, 4)):
            m = n_of(0.003)
            place(out, hp(rng.standard_normal(m), 2500) * exp_decay(m, 0.0007) * 0.06, at + rng.uniform(0.03, 0.14))
    return fade(out, 0.004, 0.08)


def crunch(rng):
    """さくっ: 前歯で皮を割る。細かい割れが 60〜90 ms のあいだ、だんだん減りながら続き、そのあと口を閉じてもぐ"""
    out = np.zeros(n_of(0.7))
    dur = rng.uniform(0.06, 0.09)
    t = 0.0
    while t < dur:
        n = n_of(rng.uniform(0.0015, 0.004))
        amp = (1.0 - t / dur) ** 0.7 * rng.uniform(0.4, 1.0)
        place(out, bp(rng.standard_normal(n), 2500, 8000, 2) * exp_decay(n, 0.0008) * amp, t)
        t += rng.uniform(0.002, 0.007) * (1.0 + 2.0 * t / dur)
    n = n_of(0.18)
    place(out, lp(rng.standard_normal(n), 450, 4) * ar(n, 0.03, 0.14, 1.3) * 0.35, 0.16)
    return fade(lp(out, 10000), 0.0005, 0.06)


def slurp(rng):
    """ずずっ: 息を吸いながら麺をすする。口の共鳴が上ずり、最後に短く切れる"""
    n = n_of(rng.uniform(0.38, 0.48))
    t = np.arange(n) / SR
    f = 700 + 900 * (t / t[-1]) ** 0.8 + 80 * np.sin(2 * np.pi * 14 * t)
    air = rng.standard_normal(n)
    x = moving_resonator(air, f, 0.985) * 0.6 + bp(air, 2000, 7000, 2) * 0.25
    env = ar(n, 0.04, n / SR * 0.5, 1.2) * (1 + 0.35 * np.sin(2 * np.pi * 9 * t))
    return fade(x * env, 0.002, 0.03)


def sip(rng):
    """ずっ・こくっ: 短く吸って、飲み込む低い「こくっ」"""
    out = np.zeros(n_of(0.55))
    n = n_of(0.16)
    t = np.arange(n) / SR
    f = 900 + 500 * t / t[-1]
    place(out, moving_resonator(rng.standard_normal(n), f, 0.98) * ar(n, 0.02, 0.12, 1.5) * 0.5, 0.0)
    m = n_of(0.09)
    tt = np.arange(m) / SR
    gulp = np.sin(2 * np.pi * np.cumsum(220 - 90 * tt / tt[-1]) / SR) * exp_decay(m, 0.02)
    place(out, lp(gulp + lp(rng.standard_normal(m), 400, 2) * exp_decay(m, 0.01) * 0.4, 1200) * 0.8, rng.uniform(0.24, 0.3))
    return fade(out, 0.002, 0.05)


def ah(rng):
    """ほっ: 満ち足りた息。「お」の口の形の、やわらかい吐く息が細っていく"""
    n = n_of(0.7)
    src = rng.standard_normal(n)
    x = bp(src, 380, 620, 2) * 0.8 + bp(src, 800, 1100, 2) * 0.45 + bp(src, 2400, 3200, 2) * 0.12
    return fade(lp(x * ar(n, 0.06, 0.62, 2.0), 4000), 0.01, 0.15)


if __name__ == "__main__":
    for i in range(4):
        write(f"eat_chew_{i + 1:02d}.wav", chew(np.random.default_rng(2700 + i)), -8)
        write(f"eat_crunch_{i + 1:02d}.wav", crunch(np.random.default_rng(2710 + i)), -8)
    for i in range(2):
        write(f"eat_slurp_{i + 1:02d}.wav", slurp(np.random.default_rng(2720 + i)), -9)
        write(f"eat_sip_{i + 1:02d}.wav", sip(np.random.default_rng(2730 + i)), -9)
        write(f"eat_ah_{i + 1:02d}.wav", ah(np.random.default_rng(2740 + i)), -12)
