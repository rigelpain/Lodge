"""ゲレンデで流れていそうな軽い曲。8 小節のループ、128 BPM、ハ長調の王道進行（F G Em Am）。

音色は単純でよい。本題はスピーカーを通した聞こえ方（speaker.py）。
音は 8 小節ぶんのバッファに書き、はみ出た尾は頭に回して継ぎ目をなくす。

music_loop  原曲（乾いた音）
"""
import numpy as np

from lib import SR, lp, n_of, place_wrap, softclip, write

BPM = 128
BEAT = 60 / BPM
BARS = 8
LEN = BEAT * 4 * BARS   # 15.0 s


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def adsr(n, a, d, s, r, gate):
    """gate 秒まで鳴って r 秒で消える。全体 n サンプル"""
    t = np.arange(n) / SR
    env = np.where(t < a, t / a, np.where(t < a + d, 1 - (1 - s) * (t - a) / d, s))
    rel = np.clip((t - gate) / r, 0, 1)
    return env * (1 - rel) * (t < gate + r)


def saw(f, n, detune=(1.0,)):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for d in detune:
        ph = (f * d * t) % 1.0
        out += 2 * ph - 1
    return out / len(detune)


def pulse(f, n, duty=0.3, vib=0.0, vib_hz=5.5):
    t = np.arange(n) / SR
    fm = f * (1 + vib * np.sin(2 * np.pi * vib_hz * t) * np.clip((t - 0.12) / 0.2, 0, 1))
    ph = np.cumsum(fm) / SR % 1.0
    return np.where(ph < duty, 1.0, -1.0)


# ---- 音色 -------------------------------------------------------------------

def lead(midi, dur):
    n = n_of(dur + 0.25)
    x = pulse(hz(midi), n, 0.32, vib=0.006)
    x = lp(x, 2600 + 20 * midi, 2)
    return x * adsr(n, 0.01, 0.1, 0.8, 0.18, dur) * 0.5


def chord_stab(midis, dur):
    n = n_of(dur + 0.2)
    x = sum(saw(hz(m), n, (0.996, 1.0, 1.004)) for m in midis) / len(midis)
    x = lp(x, 1800, 2)
    return x * adsr(n, 0.005, 0.12, 0.5, 0.12, dur) * 0.55


def bass(midi, dur):
    n = n_of(dur + 0.08)
    x = saw(hz(midi), n) * 0.7 + np.sign(saw(hz(midi), n)) * 0.3
    x = lp(x, 500, 2)
    return x * adsr(n, 0.004, 0.08, 0.6, 0.05, dur) * 0.9


def pluck(midi, dur):
    n = n_of(dur + 0.15)
    t = np.arange(n) / SR
    f = hz(midi)
    x = np.sin(2 * np.pi * f * t + 1.6 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 14))
    return x * adsr(n, 0.002, 0.08, 0.3, 0.1, dur) * 0.3


def kick():
    n = n_of(0.25)
    t = np.arange(n) / SR
    f = 48 + 110 * np.exp(-t * 28)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)
    return x * 0.9


def snare(rng):
    n = n_of(0.2)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30) * 0.5
    noise = lp(rng.standard_normal(n), 7000, 2) * np.exp(-t * 20) * 0.6
    return (body + noise) * 0.6


def hat(rng, open_=False):
    n = n_of(0.3 if open_ else 0.05)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    x = x - lp(x, 6000, 2)   # 高い方だけ
    return x * np.exp(-t * (9 if open_ else 70)) * 0.25


# ---- 譜面 -------------------------------------------------------------------

C, D, E, F, G, A, B = 60, 62, 64, 65, 67, 69, 71
CHORDS = [  # (小節, 拍, 長さ拍, 音)
    [F, A, C + 12], [G, B, D + 12], [E, G, B], [A, C + 12, E + 12],
    [F, A, C + 12], [G, B, D + 12], [E, G, B], [A, C + 12, E + 12],
]
ROOTS = [F - 24, G - 24, E - 24, A - 24, F - 24, G - 24, E - 24, A - 24]
# 旋律: (小節, 拍, 長さ拍, 音)
MELODY = [
    (0, 0, 1.5, C + 12), (0, 1.5, 0.5, A), (0, 2, 1, G), (0, 3, 1, F),
    (1, 0, 1.5, D + 12), (1, 1.5, 0.5, B), (1, 2, 1, G), (1, 3, 1, B),
    (2, 0, 1, E + 12), (2, 1, 0.5, G + 12), (2, 1.5, 0.5, E + 12), (2, 2, 2, B),
    (3, 0, 1, C + 12), (3, 1, 0.5, B), (3, 1.5, 0.5, A), (3, 2, 1, E), (3, 3, 1, G),
    (4, 0, 0.5, A), (4, 0.5, 0.5, C + 12), (4, 1, 1, F + 12), (4, 2, 0.5, E + 12), (4, 2.5, 0.5, C + 12), (4, 3, 1, A),
    (5, 0, 0.5, G), (5, 0.5, 0.5, B), (5, 1, 1, D + 12), (5, 2, 1, G + 12), (5, 3, 1, D + 12),
    (6, 0, 1.5, E + 12), (6, 1.5, 0.5, D + 12), (6, 2, 1, B), (6, 3, 1, G),
    (7, 0, 1, A), (7, 1, 1, C + 12), (7, 2, 1, B), (7, 3, 0.5, D + 12), (7, 3.5, 0.5, B),
]


def render(rng):
    buf = np.zeros(n_of(LEN))
    for bar in range(BARS):
        t0 = bar * 4 * BEAT
        ch = CHORDS[bar]
        root = ROOTS[bar]
        # ドラム
        for beat in range(4):
            place_wrap(buf, kick(), t0 + beat * BEAT)
            if beat in (1, 3):
                place_wrap(buf, snare(rng), t0 + beat * BEAT)
            place_wrap(buf, hat(rng, open_=(beat == 3)), t0 + (beat + 0.5) * BEAT)
        # ベース: 拍に根音、裏にオクターブ上
        for e in range(8):
            m = root if e % 2 == 0 else root + 12
            place_wrap(buf, bass(m, BEAT * 0.45), t0 + e * BEAT / 2)
        # 和音は裏拍の刻み
        for e in range(4):
            place_wrap(buf, chord_stab(ch, BEAT * 0.4), t0 + (e + 0.5) * BEAT)
        # 分散和音（小節 5〜8 だけ、高く小さく）
        if bar >= 4:
            tones = [m + 12 for m in ch] + [ch[0] + 24]
            for s in range(16):
                place_wrap(buf, pluck(tones[s % 4], BEAT / 4 * 0.8) * 0.6, t0 + s * BEAT / 4)
    for bar, beat, length, midi in MELODY:
        place_wrap(buf, lead(midi, BEAT * length * 0.92), bar * 4 * BEAT + beat * BEAT)
    buf = buf / np.max(np.abs(buf))
    return softclip(buf * 1.3, 1.6)


if __name__ == "__main__":
    write("music_loop.wav", render(np.random.default_rng(1000)), -1)
