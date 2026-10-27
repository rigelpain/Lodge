"""ロッジの炉。薪のはぜる音は散発の破裂、火の唸りは低いノイズのゆらぎ。

fire_bed_loop     火の低い唸りと、かすかな高い息
fire_crack_01..08 「ぱち」。1〜3 発。たまに大きい
"""
import numpy as np

from lib import SR, bp, exp_decay, fade, hp, lp, n_of, place, resonator, seamless, slow_random, write


def bed_loop(rng):
    n = n_of(8.6)
    white = rng.standard_normal(n)
    low = lp(white, 240, 2)
    flicker = 1 + 0.6 * slow_random(n, 6.0, rng) + 0.3 * slow_random(n, 0.5, rng)
    low *= np.clip(flicker, 0.1, 3)
    hiss = bp(white, 2500, 6000, 2) * (1 + 0.8 * slow_random(n, 3.0, rng))
    x = low / np.std(low) + hiss / np.std(hiss) * 0.08
    return seamless(x, 0.6)


def crack(rng):
    out = np.zeros(n_of(rng.uniform(0.18, 0.32)))
    pops = rng.choice([1, 1, 2, 2, 3])
    t = 0.0
    big = rng.uniform() < 0.3
    for k in range(pops):
        gl = n_of(rng.uniform(0.0008, 0.003))
        b = rng.standard_normal(gl) * exp_decay(gl, gl / SR / 2.5)
        b = np.concatenate([b, np.zeros(n_of(0.03))])
        p = resonator(b, rng.uniform(2200, 5500), rng.uniform(0.9, 0.97))
        p += bp(b, 1200, 8000, 2) * 0.6
        amp = rng.uniform(0.5, 1.0) * (1.0 if k == 0 else rng.uniform(0.3, 0.8))
        place(out, p / (np.max(np.abs(p)) + 1e-9) * amp, t)
        if big and k == 0:
            nt = n_of(0.04)
            th = lp(rng.standard_normal(nt), 260, 2) * exp_decay(nt, 0.01)
            place(out, th / (np.max(np.abs(th)) + 1e-9) * 0.5, t)
        t += rng.uniform(0.01, 0.045)
    out = hp(out, 300, 2)
    return fade(out, 0.0002, 0.03)


if __name__ == "__main__":
    import sys
    # 炉の音は 2026-10-27 に録音（gen/cut.py）へ差し替えた。合成は聞き比べ用に --synth
    if "--synth" in sys.argv:
        write("fire_bed_synth_loop.wav", bed_loop(np.random.default_rng(700)), -8)
        for i in range(8):
            write(f"fire_crack_synth_{i + 1:02d}.wav", crack(np.random.default_rng(710 + i)), -6 if i % 3 else -3)
