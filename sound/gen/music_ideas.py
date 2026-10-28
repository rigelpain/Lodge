"""曲の案（聞き比べ用。代表が選んだら music.py に移し、ここと idea_*.wav は片付ける）。

代表の参考は SZA「Snooze」（2026-10-28）。R&B のスロウの雰囲気だけを借りる。旋律・進行は写さない。
はじめの 3 案（エレピとブラシ、雪のパッドとベル、ナイロンギターのボサ）は「全部好きじゃない」で外した。

D R&B スロウ（72 BPM、12 小節）  澄んだエレキギターの和音と合いの手、808 のベース、声の「ウー」の重なり
E ネオソウル（75 BPM、16 小節）  ローズの和音と、言葉のない声の旋律（ずり上げ・ビブラート）、リムのドラム

長さはどれも 3 で割り切れるサンプル数にしてある（Godot は 48 kHz を 16 kHz に間引いて持つので、継ぎ目がずれない）。
響き（リバーブ）は曲の中の音作りとして、ループの頭と尾をつないだまま掛ける（外の残響ではない）。

idea_<案>_1_loop  原曲
idea_<案>_2_loop  柱のそば（いまの speaker.py の horn）
idea_<案>_3_loop  柱のそば（癖を弱めた horn）
idea_<案>_4       遠く。60 m と 100 m の柱の間で聞いた形（柱を 95 m に下げた後の目安）

聞き比べのため、どれも実効値 −17 dB にそろえる（ゲームの大きさとは別）。
使い方: .venv/bin/python gen/music_ideas.py [D E]
"""
import sys

import numpy as np

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


def rms(x):
    return np.sqrt(np.mean(x * x)) + 1e-12


def at_rms(x, rms_db=-17.0):
    """聞き比べで音量の差が出ないよう、実効値でそろえる"""
    return x / rms(x) * lib.db(rms_db)


# ---- 響きと揺れ（ループのまま） ------------------------------------------------------

def reverb(x, rng, rt=1.3, pre=0.018, bright=4500):
    """減衰するノイズを畳み込む。FFT の巡回畳み込みなので、尾はそのまま頭に回る"""
    n = len(x)
    m = n_of(rt * 1.2)
    t = t_of(m)
    ir = rng.standard_normal(m) * np.exp(-t * 6.9 / rt)
    ir = lp(ir, bright, 2)
    ir[:n_of(pre)] = 0
    ir /= rms(ir) * np.sqrt(m)
    h = np.zeros(n)
    h[:m] = ir
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)


def chorus(x, rate=0.7, depth=0.003, base=0.012, mix=0.7):
    """揺れる遅れを足す。ループの頭と尾はつながったまま"""
    n = len(x)
    t = t_of(n)
    pos = np.arange(n) - (base + depth * np.sin(2 * np.pi * rate * t)) * SR
    i0 = np.floor(pos).astype(int)
    fr = pos - i0
    d = x[i0 % n] * (1 - fr) + x[(i0 + 1) % n] * fr
    return (x + mix * d) / (1 + mix)


# ---- 音色 -------------------------------------------------------------------

def guitar_clean(midi, dur, rng, vel=0.7):
    """澄んだエレキギター。倍音を足し、高い倍音ほど早く消す。ピックの当たりを少し"""
    n = n_of(dur + 0.5)
    t = t_of(n)
    f = hz(midi)
    x = np.zeros(n)
    tau0 = np.interp(midi, [40, 84], [2.2, 0.9])
    tot = 0.0
    for k in range(1, 15):
        fk = f * k * np.sqrt(1 + 0.00008 * k * k)
        if fk > 7000:
            break
        a = abs(np.sin(np.pi * k * 0.23)) / k ** 1.1   # ピックアップの位置で倍音が抜ける
        x += a * np.sin(2 * np.pi * fk * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t * (1 + 0.45 * (k - 1)) / tau0)
        tot += a
    x /= tot
    pick = lib.bp(rng.standard_normal(n), 2000, 5000, 2) * np.exp(-t * 300) * 0.15
    return (x + pick) * env_ar(n, 0.002, dur, 0.12) * vel


def epiano(midi, dur, vel=0.8):
    """FM のローズ。叩いた直後だけ明るく、すぐ丸くなる。ゆるいトレモロ"""
    n = n_of(dur + 0.6)
    t = t_of(n)
    f = hz(midi)
    idx = (0.25 + 1.4 * vel) * np.exp(-t * 4.0) + 0.12
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    x += 0.05 * vel * np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t * 40)
    tau = np.interp(midi, [40, 84], [2.6, 0.9])
    x *= np.exp(-t / tau) * env_ar(n, 0.004, dur, 0.35)
    x *= 1 + 0.18 * np.sin(2 * np.pi * 3.8 * t)
    return x * vel


VOWELS = {   # 声の形（フォルマント）: 周波数と強さ
    "u": [(320, 1.0), (800, 0.35), (2500, 0.06)],
    "o": [(480, 1.0), (900, 0.5), (2600, 0.08)],
    "a": [(730, 1.0), (1150, 0.6), (2650, 0.12)],
}


def formant(src, vowel):
    out = np.zeros_like(src)
    for fc, g in VOWELS[vowel]:
        out += lib.bp(src, fc * 0.88, fc * 1.12, 2) * g
    return out


def voice(f_curve, amp, rng, vowel="u", breath=0.05):
    """言葉のない声。周波数の曲線をそのまま歌う（ずり上げも曲線で）。ビブラートは伸ばした音で深くなる"""
    n = len(f_curve)
    t = t_of(n)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.3 * t + rng.uniform(0, 6))
    src = np.zeros(n)
    for d in (0.997, 1.003):
        ph = np.cumsum(f_curve * vib * d) / SR
        src += 2 * (ph % 1.0) - 1
    src += rng.standard_normal(n) * breath
    y = formant(src, vowel)
    return lp(y, 5000, 2) * amp


def voice_line(notes, beat, n, rng, vowel="a", glide=0.07):
    """(拍, 長さ拍, 音) の並びを 1 本の声にする。音の間はなめらかにずり上げ・ずり下げる"""
    f = np.zeros(n)
    amp = np.zeros(n)
    last = None
    for at, length, m in notes:
        i0 = n_of(at * beat)
        i1 = min(n, n_of((at + length) * beat))
        f0 = hz(m)
        seg = np.full(i1 - i0, f0)
        g = min(n_of(glide), i1 - i0)
        start = last if last is not None and i0 - last_end < n_of(0.12) else f0 * 2 ** (-1.5 / 12)   # 前の音か、少し下から
        seg[:g] = start * (f0 / start) ** np.linspace(0, 1, g)
        f[i0:i1] = seg
        a = np.ones(i1 - i0)
        k = min(n_of(0.06), len(a))
        a[:k] = np.linspace(0, 1, k)
        r = min(n_of(0.12), len(a))
        a[-r:] *= np.linspace(1, 0, r)
        amp[i0:i1] = np.maximum(amp[i0:i1], a)
        last, last_end = f0, i1
    f[f == 0] = 200.0   # 黙っている所（音量 0）
    return voice(f, 1.0, rng, vowel) * lp(amp, 30, 1)


def vox_pad(midis, dur, rng, vowel="u", vel=0.5):
    """重ねた声の「ウー」。和音の音を 1 本ずつ"""
    n = n_of(dur + 1.2)
    out = np.zeros(n)
    for m in midis:
        out += voice(np.full(n, hz(m)) * (1 + rng.uniform(-0.002, 0.002)), 1.0, rng, vowel, 0.03)
    return out / len(midis) * env_ar(n, 0.5, dur, 1.0) * vel


def bass808(midi, dur, to=None, vel=0.9):
    """808 のベース。長く伸び、終わりで次の音へずり動く。少し歪ませ、倍音で形を残す"""
    n = n_of(dur + 0.1)
    t = t_of(n)
    f = np.full(n, hz(midi))
    if to is not None:
        g = n_of(min(0.12, dur * 0.4))
        f[-g:] = hz(midi) * (hz(to) / hz(midi)) ** np.linspace(0, 1, g)
    f *= 1 + 0.6 * np.exp(-t * 40)   # 頭の小さなぴしっ
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    x = np.tanh(2.2 * x) / np.tanh(2.2)
    x *= np.exp(-t / 2.5) * env_ar(n, 0.003, dur, 0.06)
    return lp(x, 1200, 2) * vel


def bass_finger(midi, dur, vel=0.8):
    """指弾きのやわらかいベース"""
    n = n_of(dur + 0.2)
    t = t_of(n)
    f = hz(midi)
    x = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t)
    x *= np.exp(-t / 1.2) * env_ar(n, 0.008, dur, 0.12)
    return lp(x, 900, 2) * vel


def kick(vel=1.0):
    n = n_of(0.45)
    t = t_of(n)
    f = 48 + 90 * np.exp(-t * 35)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    return lp(x, 500, 2) * env_ar(n, 0.002, 0.44, 0.01) * vel


def snare(rng, vel=1.0):
    """乾いたスネアに手拍子を重ねる。スピーカーで刺さらないよう、高い所は丸める"""
    n = n_of(0.35)
    t = t_of(n)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 28) * 0.6
    noise = lib.bp(rng.standard_normal(n), 900, 4000, 2) * np.exp(-t * 20) * 0.5
    clap = np.zeros(n)
    for k, d in enumerate((0.0, 0.011, 0.023)):
        i = n_of(d)
        m = n - i
        clap[i:] += lib.bp(rng.standard_normal(m), 900, 3000, 2) * np.exp(-t[:m] * (120 if k < 2 else 22))
    return (body + noise + clap * 0.2) * env_ar(n, 0.004, 0.34, 0.01) * vel * 0.6


def rim(rng, vel=1.0):
    n = n_of(0.12)
    return lib.modes(n, [1650, 2500, 820], [0.018, 0.010, 0.03], [1.0, 0.4, 0.3], rng, 0.01) * 0.3 * vel


def hat(rng, vel=1.0, open_=False):
    n = n_of(0.3 if open_ else 0.06)
    t = t_of(n)
    x = hp(rng.standard_normal(n), 7000, 2)
    return x * np.exp(-t * (10 if open_ else 60)) * 0.2 * vel


# ---- 組み立て -----------------------------------------------------------------

def humanize(rng, ms=8):
    return rng.normal(0, ms / 1000)


def swing(beat, amt):
    """16 分の裏だけ少し遅らせる"""
    frac = beat % 0.5
    return beat + (amt if abs(frac - 0.25) < 1e-6 else 0.0)


def mix(buses, levels, rng, wet):
    """各バスを実効値で並べ（levels は dB）、wet の分だけ響きに送る"""
    out = 0
    send = 0
    for name, x in buses.items():
        y = x / rms(x) * lib.db(levels[name])
        out = out + y
        send = send + y * wet.get(name, 0.0)
    out = out + reverb(send, rng)
    out = circular(lambda v: lp(v, 11000, 2), out)
    out = out / np.max(np.abs(out))
    return softclip(out * 1.15, 1.3)


def song_d(rng):
    """R&B スロウ。変ホ長調、72 BPM、12 小節（4 小節を 3 回、3 回目は始まりを変える）"""
    bpm, bars = 72, 12
    beat = 60 / bpm
    n = n_of(beat * 4 * bars)
    B = {k: np.zeros(n) for k in ("gtr", "vox", "lead", "bass", "kick", "snare", "hat")}
    V = {"Ab": (60, 63, 67, 70), "Gm": (55, 58, 62, 65), "Fm": (56, 60, 63, 67), "Bbs": (55, 60, 63, 68),
         "Bb7": (56, 62, 65, 68), "Cm": (58, 62, 63, 67)}
    R = {"Ab": 32, "Gm": 31, "Fm": 29, "Bbs": 34, "Cm": 36}
    prog = ["Ab", "Gm", "Fm", "Bbs"] * 2 + ["Cm", "Ab", "Fm", "Bbs"]
    fills = [
        [(3.25, .25, 75), (3.5, .25, 72), (3.75, .25, 70)],
        [(3.5, .25, 77), (3.75, .25, 75)],
        [(3, .5, 70), (3.5, .5, 72)],
        [(3.25, .25, 79), (3.5, .25, 77), (3.75, .25, 75)],
    ]
    lead = [   # 3 回目だけ、声の旋律をうっすら
        (32.5, 1.5, 70), (34, 2, 67), (36.5, 1, 72), (37.5, 2.5, 70), (40.5, 1.5, 68), (42, 2, 67), (44.5, 3, 65),
    ]
    for b, name in enumerate(prog):
        t0 = b * 4 * beat
        ch = V[name]
        # ギター: 1 拍目に下から鳴らす、2 拍目の 16 分裏に上 2 音、3 拍目の裏にもう一度、4 拍目に合いの手
        for pos, length, vel, notes in [(0, 1.6, 0.8, ch), (1.75, 0.4, 0.45, ch[2:]), (2.5, 1.2, 0.6, ch)]:
            use = V["Bb7"] if name == "Bbs" and pos >= 2.5 else notes
            for i, m in enumerate(use):
                place_wrap(B["gtr"], guitar_clean(m, length * beat, rng, vel * rng.uniform(0.85, 1.0)),
                           t0 + pos * beat + i * 0.022 + humanize(rng, 4))
        for pos, length, m in fills[b % 4]:
            place_wrap(B["gtr"], guitar_clean(m, length * beat, rng, 0.55), t0 + pos * beat + humanize(rng, 5))
        place_wrap(B["vox"], vox_pad(ch, 4 * beat, rng, "u"), t0 - 0.1)
        # 808: 根音を伸ばし、3 拍目の裏で 5 度、終わりで次の根音へずり動く
        r = R[name]
        nxt = R[prog[(b + 1) % bars]]
        place_wrap(B["bass"], bass808(r, 2.4 * beat), t0)
        place_wrap(B["bass"], bass808(r + 7, 1.4 * beat, to=nxt), t0 + 2.5 * beat)
        # ドラム: キックは 1 拍目と 2 拍目の裏、3 拍目の 16 分裏。スネアは 2・4 拍
        for pos, v in [(0, 1.0), (1.5, 0.6), (2.75, 0.75)]:
            place_wrap(B["kick"], kick(v), t0 + pos * beat)
        for pos in (1, 3):
            place_wrap(B["snare"], snare(rng), t0 + pos * beat + 0.012)   # 少し遅らせて、もたれる
        for s in range(8):
            place_wrap(B["hat"], hat(rng, 1.0 if s % 2 == 0 else 0.55), t0 + s * beat / 2 + humanize(rng, 4))
        if b % 4 == 3:   # 小節の終わりに 3 連の細かい刻み
            for k in range(6):
                place_wrap(B["hat"], hat(rng, 0.5 + 0.08 * k), t0 + (3 + k / 6) * beat)
    B["lead"] = voice_line(lead, beat, n, rng, "o")
    B["gtr"] = chorus(B["gtr"])
    levels = {"gtr": -14, "vox": -24, "lead": -21, "bass": -15, "kick": -19, "snare": -24, "hat": -32}
    wet = {"gtr": 0.35, "vox": 0.6, "lead": 0.6, "snare": 0.4}
    return mix(B, levels, rng, wet)


def song_e(rng):
    """ネオソウル。変ニ長調、75 BPM、16 小節。ローズと、言葉のない声の旋律"""
    bpm, bars = 75, 16
    beat = 60 / bpm
    n = n_of(beat * 4 * bars)
    B = {k: np.zeros(n) for k in ("keys", "vox", "lead", "bass", "kick", "rim", "hat")}
    V = {"Gb": (58, 61, 65, 68), "Fm": (56, 60, 63, 67), "Ebm": (54, 58, 61, 65), "Abs": (53, 58, 61, 66),
         "Bbm": (56, 60, 61, 65), "Eb9": (55, 58, 61, 65), "Ab7": (54, 60, 63, 68)}
    R = {"Gb": 42, "Fm": 41, "Ebm": 39, "Abs": 44, "Bbm": 46, "Eb9": 39, "Ab7": 44}
    prog = (["Gb", "Fm", "Ebm", "Abs"] * 2 + ["Bbm", "Eb9", "Gb", "Abs"] + ["Gb", "Fm", "Ebm", "Ab7"])
    phrase_a = [[(0.5, .5, 68), (1, 1, 70), (2, .5, 68), (2.5, 1.5, 65)],
                [(0, 1, 63), (1, 1, 65), (2.5, 1.5, 68)],
                [(0, 2, 70), (2, .5, 68), (2.5, .5, 66), (3, 1, 65)],
                [(0, 2.5, 63)]]
    phrase_a2 = [[(0.5, .5, 68), (1, .5, 70), (1.5, 1, 73), (2.5, 1.5, 70)],
                 [(0, 1.5, 72), (1.5, .5, 70), (2, 2, 68)],
                 [(0.5, .5, 66), (1, .5, 68), (1.5, 1, 70), (2.5, 1.5, 73)],
                 [(0, 2, 70), (2, 1, 68), (3, 1, 65)]]
    phrase_b = [[(0, 1, 65), (1, .5, 68), (1.5, 1, 72), (2.5, 1.5, 73)],
                [(0, 1.5, 75), (1.5, .5, 73), (2, 2, 70)],
                [(0.5, .5, 68), (1, 1, 70), (2, 2, 77)],
                [(0, 2, 75), (2, 1, 73), (3, 1, 70)]]
    melody = phrase_a + phrase_a2 + phrase_b + phrase_a
    notes = []
    for b, name in enumerate(prog):
        t0 = b * 4 * beat
        ch = V[name]
        # ローズ: 1 拍目を長く、2 拍目の裏で先取り、4 拍目の 16 分裏にかすかに
        for pos, length, vel in [(0, 1.8, 0.75), (1.5, 0.9, 0.5), (3.75, 0.25, 0.3)]:
            at = t0 + swing(pos, 0.08) * beat
            for i, m in enumerate(ch):
                place_wrap(B["keys"], epiano(m, length * beat, vel * rng.uniform(0.85, 1.0)),
                           at + i * 0.01 + humanize(rng, 5))
        place_wrap(B["vox"], vox_pad(ch[1:], 4 * beat, rng, "o", 0.5), t0 - 0.1)
        r = R[name]
        for pos, length, m in [(0, 1.4, r), (1.75, 0.6, r + 12), (2.5, 1.2, r + 7)]:
            place_wrap(B["bass"], bass_finger(m, length * beat), t0 + swing(pos, 0.08) * beat + humanize(rng, 6))
        for pos, v in [(0, 1.0), (2.5, 0.7)]:
            place_wrap(B["kick"], kick(v), t0 + pos * beat + humanize(rng, 4))
        for pos in (1, 3):
            place_wrap(B["rim"], rim(rng), t0 + pos * beat + 0.02 + humanize(rng, 4))   # 遅れ気味に置く
            place_wrap(B["rim"], snare(rng, 0.25), t0 + pos * beat + 0.02)
        for s in range(8):
            place_wrap(B["hat"], hat(rng, 0.9 if s % 2 == 0 else 0.5), t0 + swing(s / 2, 0.08) * beat + humanize(rng, 5))
        notes += [(b * 4 + at, length, m) for at, length, m in melody[b]]
    B["lead"] = voice_line(notes, beat, n, rng, "a")
    levels = {"keys": -14, "vox": -23, "lead": -16, "bass": -16, "kick": -20, "rim": -23, "hat": -31}
    wet = {"keys": 0.3, "vox": 0.6, "lead": 0.45, "rim": 0.3}
    return mix(B, levels, rng, wet)


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
    out = np.zeros(n)
    out[:len(a)] += a
    out[:len(b)] += b
    return out[:n_of(secs)]


SONGS = {"D": song_d, "E": song_e}

if __name__ == "__main__":
    for key in (sys.argv[1:] or list(SONGS)):
        dry = SONGS[key](np.random.default_rng(2000 + ord(key)))
        k = key.lower()
        post = circular(horn_now, dry)
        write(f"idea_{k}_1_loop.wav", at_rms(dry), None)
        write(f"idea_{k}_2_loop.wav", at_rms(post), None)
        write(f"idea_{k}_3_loop.wav", at_rms(circular(horn_soft, dry)), None)
        write(f"idea_{k}_4.wav", at_rms(far_mix(post, 30)), None)
