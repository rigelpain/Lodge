"""ソリの木のきしみ。押す力が入った瞬間に、まれに。

sled_creak_01..03  木と木がこすれて止まる。パルスの列が速まりながら共鳴を通る
"""
import numpy as np

from lib import SR, fade, hp, n_of, resonator, write


def creak(rng):
    n = n_of(rng.uniform(0.22, 0.34))
    r0, r1 = rng.uniform(25, 45), rng.uniform(90, 160)
    rate = r0 + (r1 - r0) * np.linspace(0, 1, n) ** 1.4
    phase = np.cumsum(rate) / SR
    pulses = np.diff(np.floor(phase), prepend=0) * rng.uniform(0.7, 1.0, n)
    x = resonator(pulses, rng.uniform(480, 900), 0.993) + resonator(pulses, rng.uniform(1400, 2200), 0.985) * 0.5
    x *= np.sin(np.pi * np.arange(n) / n) ** 1.2
    x = hp(x, 200, 2)
    return fade(x, 0.005, 0.04)


if __name__ == "__main__":
    for i in range(3):
        write(f"sled_creak_{i + 1:02d}.wav", creak(np.random.default_rng(950 + i)), -12)
