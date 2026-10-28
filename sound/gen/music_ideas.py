"""チルい曲の案 3 つ（聞き比べ用。代表が選んだら music.py に移し、ここと chill_*.wav は片付ける）。

A エレピとブラシ（80 BPM、16 小節）、B 雪のパッドとベル（72 BPM、12 小節）、C ナイロンギターのボサ（90 BPM、12 小節）。
長さはどれも 3 で割り切れるサンプル数にしてある（Godot は 48 kHz を 16 kHz に間引いて持つので、継ぎ目がずれない）。

chill_<案>_1_loop  原曲
chill_<案>_2_loop  柱のそば（いまの speaker.py の horn）
chill_<案>_3_loop  柱のそば（癖を弱めた horn）
chill_<案>_4       遠く。60 m と 100 m の柱の間で聞いた形（柱を 95 m に下げた後の目安）

聞き比べのため、どれも実効値 −17 dB にそろえる（ゲームの大きさとは別）。

使い方: .venv/bin/python gen/music_ideas.py [A B C]
"""
import sys

import numpy as np
from scipy import signal

import lib
from lib import SR, hp, lp, n_of, normalize, peak_eq, place_wrap, softclip, write
from speaker import far_pass


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def t_of(n):
    return np.arange(n) / SR


def env_ar(n, a, gate, r):
    """a 秒で立ち上がり、gate 秒から r 秒で消える"""
    t = t_of(n)
    e = np.clip(t / a, 0, 1) if a > 0 else np.ones(n)
    e = 0.5 - 0.5 * np.cos(np.pi * e)
    rel = np.clip((t - gate) / r, 0, 1)
    return e * (1 - rel)


def circular(fn, x):
    """ループの頭と尾をつないだままフィルタをかける（3 回つないで真ん中を取る）"""
    n = len(x)
    return fn(np.tile(x, 3))[n:2 * n]


# ---- 音色 -------------------------------------------------------------------

def epiano(midi, dur, vel=0.8):
    """FM のエレピ。叩いた直後だけ明るく、すぐ丸くなる。ゆるいトレモロ"""
    n = n_of(dur + 0.6)
    t = t_of(n)
    f = hz(midi)
    idx = (0.25 + 1.6 * vel) * np.exp(-t * 4.0) + 0.15
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    x += 0.06 * vel * np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t * 40)   # 金属の芯の音
    tau = np.interp(midi, [40, 84], [2.6, 0.9])
    x *= np.exp(-t / tau) * env_ar(n, 0.004, dur, 0.35)
    x *= 1 + 0.12 * np.sin(2 * np.pi * 4.2 * t)
    return x * vel


def bell(midi, dur, vel=0.6):
    """やさしいベル（チェレスタ寄り）。倍音は少なめ"""
    n = n_of(max(dur, 1.6) + 0.4)
    t = t_of(n)
    f = hz(midi)
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t / 1.4)
         + 0.25 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.6)
         + 0.08 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t / 0.25)
         + 0.04 * np.sin(2 * np.pi * f * 5.43 * t) * np.exp(-t / 0.08))
    return x * env_ar(n, 0.006, n / SR - 0.3, 0.3) * vel


def vibe(midi, dur, vel=0.6):
    """ビブラフォン。モーターのトレモロ"""
    n = n_of(dur + 1.2)
    t = t_of(n)
    f = hz(midi)
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t / 1.6)
         + 0.12 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t / 0.35)
         + 0.03 * np.sin(2 * np.pi * f * 10.0 * t) * np.exp(-t / 0.06))
    x *= 1 + 0.25 * np.sin(2 * np.pi * 5.0 * t)
    return x * env_ar(n, 0.005, dur + 0.4, 0.6) * vel


def pad(midis, dur, rng, vel=0.5):
    """ゆっくり立ち上がるパッド。のこぎり波を少しずつずらし、こもらせる"""
    n = n_of(dur + 2.2)
    t = t_of(n)
    x = np.zeros(n)
    for m in midis:
        f = hz(m)
        for d in (0.993, 1.0, 1.007):
            ph = (f * d * t * (1 + 0.002 * np.sin(2 * np.pi * 0.3 * t)) + rng.uniform()) % 1.0
            x += 2 * ph - 1
    x /= 3 * len(midis)
    x = lp(x, 900, 2)
    x = lp(x, 1800, 2)
    return x * env_ar(n, 1.4, dur, 2.0) * vel


def guitar(midi, dur, rng, vel=0.6):
    """ナイロン弦（Karplus-Strong）。指の腹でやわらかく弾く"""
    n = n_of(dur + 0.4)
    f = hz(midi)
    L = max(2, int(round(SR / f - 0.5)))
    burst = lp(rng.standard_normal(L), 1500 + 15 * midi, 2)
    burst -= burst.mean()
    x = np.zeros(n)
    x[:L] = burst
    g = 0.996 if midi < 55 else 0.993
    a = np.zeros(L + 2)
    a[0] = 1
    a[L] = -g / 2
    a[L + 1] = -g / 2
    y = signal.lfilter([1.0], a, x)
    y = peak_eq(y, 220, 4, 1.2)
    y = lp(y, 3200, 2)
    y /= np.max(np.abs(y)) + 1e-9
    return y * env_ar(n, 0.002, dur, 0.25) * vel


def bass(midi, dur, vel=0.8):
    """やわらかいベース。スピーカーで低い所が落ちても形が残るよう、2・3 倍音を少し"""
    n = n_of(dur + 0.2)
    t = t_of(n)
    f = hz(midi)
    x = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t))
    x *= np.exp(-t / 1.2) * env_ar(n, 0.01, dur, 0.15)
    return lp(x, 900, 2) * vel


def kick_soft():
    n = n_of(0.3)
    t = t_of(n)
    f = 52 + 50 * np.exp(-t * 30)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    return lp(x, 400, 2) * env_ar(n, 0.003, 0.3, 0.01) * 0.7


def brush_tap(rng):
    """ブラシで叩く（2・4 拍）"""
    n = n_of(0.25)
    t = t_of(n)
    x = lib.bp(rng.standard_normal(n), 1200, 6000, 2) * np.exp(-t * 18)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 35) * 0.3
    return (x + body) * env_ar(n, 0.004, 0.25, 0.01) * 0.35


def brush_sweep(rng, dur):
    """ブラシの円を描くこすれ。ふわっと立ち上がって消える"""
    n = n_of(dur)
    x = lib.bp(rng.standard_normal(n), 1500, 5000, 2)
    e = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    return x * e * 0.08


def shaker(rng, vel=1.0):
    n = n_of(0.09)
    t = t_of(n)
    x = hp(rng.standard_normal(n), 3500, 2)
    e = np.clip(t / 0.012, 0, 1) * np.exp(-np.clip(t - 0.012, 0, None) * 45)
    return lp(x, 8000, 2) * e * 0.10 * vel


def rim(rng):
    """リムのやわらかい音（木の小さい鳴り）"""
    n = n_of(0.12)
    return lib.modes(n, [1650, 2500, 820], [0.018, 0.010, 0.03], [1.0, 0.4, 0.3], rng, 0.01) * 0.18


# ---- 組み立て -----------------------------------------------------------------

def humanize(rng, ms=8):
    return rng.normal(0, ms / 1000)


def swing(beat, amt):
    """16 分の裏だけ少し遅らせる"""
    frac = beat % 0.5
    return beat + (amt if abs(frac - 0.25) < 1e-6 else 0.0)


def finish(buf, cut=9000):
    buf = circular(lambda v: lp(v, cut, 2), buf)
    buf = buf / np.max(np.abs(buf))
    return softclip(buf * 1.1, 1.2)


def song_a(rng):
    """エレピとブラシ。ハ長調で IV–iii–ii–I（Fmaj9 Em7 Dm9 Cmaj9）、後半に B♭maj9 と Am7"""
    bpm, bars = 80, 16
    beat = 60 / bpm
    buf = np.zeros(n_of(beat * 4 * bars))
    V = {"F": (57, 60, 64, 67), "Em": (55, 59, 62, 64), "Dm": (53, 57, 60, 64), "C": (52, 55, 59, 62),
         "Bb": (57, 60, 62, 65), "Am": (55, 60, 64, 67), "Gs": (53, 57, 60, 62)}
    R = {"F": 41, "Em": 40, "Dm": 38, "C": 36, "Bb": 34, "Am": 33, "Gs": 31}
    prog = ["F", "Em", "Dm", "C"] * 3 + ["Bb", "Am", "Dm", "Gs"]
    mel_a = [
        [(0.5, .5, 72), (1, .5, 74), (1.5, 1.5, 76), (3, .5, 74), (3.5, .5, 72)],
        [(0, 2, 71), (2.5, .5, 67), (3, 1, 69)],
        [(0.5, .5, 69), (1, .5, 72), (1.5, 1, 76), (2.5, 1.5, 74)],
        [(0, 3, 71), (3.5, .5, 67)],
        [(0, .5, 69), (0.5, .5, 72), (1, 1, 79), (2, .5, 77), (2.5, 1, 76), (3.5, .5, 74)],
        [(0, 1.5, 74), (1.5, .5, 71), (2, 2, 67)],
        [(0.5, .5, 65), (1, .5, 69), (1.5, .5, 72), (2, 1, 76), (3, 1, 74)],
        [(0, 2.5, 72)],
    ]
    mel_b = [
        [(0, 1.5, 74), (1.5, .5, 72), (2, 1, 69), (3, 1, 65)],
        [(0, 2, 72), (2.5, .5, 71), (3, 1, 69)],
        [(0.5, .5, 69), (1, .5, 72), (1.5, 1, 74), (2.5, 1.5, 77)],
        [(0, 2, 76), (2.5, .5, 74), (3, 1, 72)],
    ]
    melody = mel_a + mel_a[:4] + mel_b
    for b, name in enumerate(prog):
        t0 = b * 4 * beat
        ch = V[name]
        # エレピ: 1 拍目、2 拍目の 16 分裏、3 拍目の裏
        for pos, length, vel in [(0, 1.6, 0.8), (1.75, 0.5, 0.5), (2.5, 1.4, 0.65)]:
            at = t0 + swing(pos, 0.06) * beat
            for i, m in enumerate(ch):
                place_wrap(buf, epiano(m, length * beat, vel * rng.uniform(0.85, 1.0)) * 0.22,
                           at + i * 0.008 + humanize(rng, 4))
        r = R[name]
        for pos, length, m in [(0, 1.4, r), (1.5, 0.9, r + 7), (3, 0.7, r + 12)]:
            place_wrap(buf, bass(m, length * beat) * 0.5, t0 + pos * beat + humanize(rng, 5))
        for k in range(4):
            if k in (0, 2):
                place_wrap(buf, kick_soft() * (0.9 if k == 0 else 0.6), t0 + (k + (0.5 if k == 2 else 0)) * beat)
            else:
                place_wrap(buf, brush_tap(rng), t0 + k * beat + humanize(rng, 6))
            place_wrap(buf, brush_sweep(rng, beat * 0.9), t0 + (k + 0.1) * beat)
        for pos, length, m in melody[b]:
            place_wrap(buf, bell(m, length * beat, 0.5) * 0.55, t0 + swing(pos, 0.06) * beat + humanize(rng, 6))
    return finish(buf)


def song_b(rng):
    """雪のパッドとベル。ニ長調、2 小節ずつ Dmaj9 F#m11 Gmaj9 Bm9 Em9 A9sus4。打楽器なし"""
    bpm, bars = 72, 12
    beat = 60 / bpm
    buf = np.zeros(n_of(beat * 4 * bars))
    chords = [((57, 61, 64, 66), 38), ((57, 59, 64, 66), 42), ((57, 59, 62, 66), 43),
              ((57, 61, 62, 66), 35), ((55, 59, 62, 66), 40), ((55, 59, 62, 64), 33)]
    # ベルの音形（2 小節＝8 拍ぶん）。和音の音から高い所で選ぶ
    figs = [
        [(0, 0), (1.5, 2), (2, 3), (3.5, 1), (5, 2), (6, 4), (7.5, 3)],
        [(0.5, 1), (2, 3), (3, 2), (4.5, 4), (6, 3), (7, 1)],
    ]
    for k, (ch, root) in enumerate(chords):
        t0 = k * 8 * beat
        place_wrap(buf, pad(ch, 8 * beat, rng, 0.5), t0 - 0.3)
        place_wrap(buf, pad([m + 12 for m in ch[1:3]], 8 * beat, rng, 0.18), t0 + 2 * beat)
        place_wrap(buf, bass(root, 3.5 * beat, 0.6) * 0.45, t0)
        place_wrap(buf, bass(root + 7, 3.5 * beat, 0.5) * 0.35, t0 + 4 * beat)
        tones = sorted({m + 12 for m in ch} | {m + 24 for m in ch})[2:]
        for pos, i in figs[k % 2]:
            m = tones[min(i + (k % 3 == 2), len(tones) - 1)]
            place_wrap(buf, bell(m, 1.5 * beat, rng.uniform(0.4, 0.6)) * 0.35, t0 + pos * beat + humanize(rng, 10))
        # ゆっくりしたエレピの和音を 2 小節目の頭にだけ、ごく小さく
        for i, m in enumerate(ch):
            place_wrap(buf, epiano(m, 3.5 * beat, 0.45) * 0.10, t0 + 4 * beat + i * 0.03)
    return finish(buf, 7000)


def song_c(rng):
    """ナイロンギターのボサ。ト長調、12 小節。ビブラフォンの旋律、シェイカーとリム"""
    bpm, bars = 90, 12
    beat = 60 / bpm
    buf = np.zeros(n_of(beat * 4 * bars))
    chords = [((54, 59, 62), 43), ((50, 55, 59), 40), ((55, 60, 64), 45), ((54, 60, 64), 50),
              ((54, 59, 62), 43), ((57, 62, 66), 47), ((55, 59, 64), 48), ((57, 63, 67), 48),
              ((57, 62, 66), 47), ((56, 62, 66), 40), ((55, 60, 64), 45), ((55, 60, 64), 50)]
    melody = [
        [(0, 1.5, 71), (1.5, .5, 74), (2, 2, 78)],
        [(0, 1, 79), (1, .5, 78), (1.5, .5, 76), (2, 2, 74)],
        [(0.5, .5, 72), (1, .5, 74), (1.5, 1, 76), (2.5, 1.5, 79)],
        [(0, 2, 78), (2, .5, 76), (2.5, 1.5, 72)],
        [(0, 1, 71), (1, .5, 74), (1.5, 2.5, 78)],
        [(0, 1.5, 76), (1.5, .5, 74), (2, 2, 69)],
        [(0, 1, 71), (1, 1, 74), (2, 2, 76)],
        [(0, 2, 75), (2, 1, 74), (3, 1, 72)],
        [(0, 3, 74), (3, .5, 71), (3.5, .5, 69)],
        [(0, 1.5, 68), (1.5, .5, 71), (2, 2, 74)],
        [(0, 1, 72), (1, 1, 71), (2, 1.5, 67)],
        [(0, 2, 69)],
    ]
    comp = [[0, 1.5, 3], [0.5, 2, 3.5]]
    for b, (ch, root) in enumerate(chords):
        t0 = b * 4 * beat
        # 親指: 1 拍目に根音、3 拍目に 5 度
        place_wrap(buf, guitar(root, 1.8 * beat, rng, 0.7) * 0.5, t0 + humanize(rng, 4))
        fifth = root + 7 if root < 45 else root - 5
        place_wrap(buf, guitar(fifth, 1.8 * beat, rng, 0.6) * 0.45, t0 + 2 * beat + humanize(rng, 4))
        for pos in comp[b % 2]:
            at = t0 + pos * beat + humanize(rng, 5)
            for i, m in enumerate(ch):
                place_wrap(buf, guitar(m, 0.55 * beat, rng, rng.uniform(0.45, 0.6)) * 0.32, at + i * 0.012)
        for s in range(8):
            place_wrap(buf, shaker(rng, 1.0 if s % 2 else 0.6), t0 + s * beat / 2 + humanize(rng, 4))
        for pos in ([0, 1.5, 3] if b % 2 == 0 else [1, 2.5]):
            place_wrap(buf, rim(rng), t0 + pos * beat + humanize(rng, 4))
        place_wrap(buf, kick_soft() * 0.5, t0)
        place_wrap(buf, kick_soft() * 0.4, t0 + 2 * beat)
        for pos, length, m in melody[b]:
            place_wrap(buf, vibe(m, length * beat, 0.55) * 0.45, t0 + pos * beat + humanize(rng, 6))
    return finish(buf)


# ---- スピーカー ------------------------------------------------------------------

def horn_now(x):
    """いまの speaker.py の horn と同じ"""
    y = hp(x, 300, 4)
    y = lp(y, 3500, 4)
    y = peak_eq(y, 1000, 6, 1.0)
    y = peak_eq(y, 2500, 5, 3.0)
    y = normalize(y, -6)
    y = softclip(y * 2.2, 2.0)
    y = lp(y, 4200, 2)
    return y


def horn_soft(x):
    """癖を弱めた案: 帯域を少し広く、鼻の癖を小さく、歪みを浅く"""
    y = hp(x, 250, 2)
    y = hp(y, 250, 2)
    y = lp(y, 4500, 4)
    y = peak_eq(y, 1000, 3, 0.8)
    y = peak_eq(y, 2500, 2, 2.0)
    y = normalize(y, -6)
    y = softclip(y * 1.4, 1.4)
    y = lp(y, 5500, 2)
    return y


def far_mix(post, secs):
    """2 本の柱（60 m と 100 m）の間で聞いた形"""
    two = np.tile(post, int(np.ceil(secs / (len(post) / SR))) + 1)
    rng = np.random.default_rng(1100)
    a = far_pass(two, 60, rng, 0.07)
    b = far_pass(two, 100, rng, 0.11)
    n = max(len(a), len(b))
    mix = np.zeros(n)
    mix[:len(a)] += a
    mix[:len(b)] += b
    return mix[:n_of(secs)]


def at_rms(x, rms_db=-17.0):
    """聞き比べで音量の差が出ないよう、実効値でそろえる"""
    return x / np.sqrt(np.mean(x * x)) * lib.db(rms_db)


SONGS = {"A": song_a, "B": song_b, "C": song_c}

if __name__ == "__main__":
    for key in (sys.argv[1:] or list(SONGS)):
        dry = SONGS[key](np.random.default_rng(2000 + ord(key)))
        k = key.lower()
        post = circular(horn_now, dry)
        write(f"chill_{k}_1_loop.wav", at_rms(dry), None)
        write(f"chill_{k}_2_loop.wav", at_rms(post), None)
        write(f"chill_{k}_3_loop.wav", at_rms(circular(horn_soft, dry)), None)
        write(f"chill_{k}_4.wav", at_rms(far_mix(post, 30)), None)
