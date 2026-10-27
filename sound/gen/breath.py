"""押している人の吐く息。苦しい音ではなく、働いている音。

breath_01..04  短い吸い込みのあと、ふっと吐く。母音のない「は」の息
"""
import numpy as np

from lib import SR, ar, bp, fade, hp, lp, n_of, peak_eq, place, write


def breath(rng):
    out = np.zeros(n_of(1.1))
    # 吸う: 高めの細い息、小さく
    ni = n_of(rng.uniform(0.2, 0.28))
    inh = bp(rng.standard_normal(ni), 1200, 5000, 2) * ar(ni, 0.08, 0.1, 1.5) * 0.22
    place(out, inh, 0.0)
    # 吐く: 広めの息に口の形の山を 2 つ
    dur = rng.uniform(0.5, 0.75)
    ne = n_of(dur)
    x = rng.standard_normal(ne)
    f1, f2 = rng.uniform(450, 650), rng.uniform(1500, 2100)
    y = lp(x, 3800, 2) * 0.5 + peak_eq(peak_eq(x, f1, 10, 2.5), f2, 7, 3) * 0.08
    y = hp(y, 180, 2)
    env = ar(ne, 0.07, dur * 0.7, 1.6)
    # 息の揺れ
    trem = 1 + 0.12 * lp(rng.standard_normal(ne), 12, 2) / 0.3
    place(out, y * env * trem, 0.3)
    return fade(out, 0.005, 0.05)


if __name__ == "__main__":
    for i in range(4):
        write(f"breath_{i + 1:02d}.wav", breath(np.random.default_rng(400 + i)), -10)
