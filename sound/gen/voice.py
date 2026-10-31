"""言葉にならない声。紙の人形の、小さくてやわらかい声。言葉ではない。

voice_wa_01..03   「ワ〜」うれしい・解放。う の口から あ へ開き、高く上がってから下りる
voice_un_01..03   「ウン」うなずき・了解。口を閉じた鼻の声で、短く下がる
voice_nn_01..03   「ンーン」いやいや・ちがう。鼻の声が 2 つ。高いほうから低いほうへ
voice_unq_01..03  「ウン？」たずねる・首をかしげる。鼻の声で、後半が上がる
voice_surprise_01..03  びっくり（雪玉が当たったとき）。息を吸うかすれから、高い「あ」が短く跳ねる
voice_oi_01..03   「おーーーい」遠くの人を呼ぶ。お を長く強く伸ばし、最後の い で上がって届かせる

どれも 01 がふつう、02 が全体に高い声、03 が全体に低い声（上がり下がりの形は同じ。SIZES）。
高い声は口の響きも少し上げて小さな体に、低い声は響きも下げて大きな体に聞こえるようにする。

声帯の音（声門の波を 1 周ずつ作り、揺らぎを入れる）に息を混ぜ、口の形の共鳴（フォルマント）を通す。
録音も生成サービスも使わない。高さは人ごとに Godot 側で少し変える（pitch_scale）。
やわらかくするため: 息を多めに混ぜ、高い倍音を落とし、立ち上がりと終わりをなだらかにする。

人の声に聞こえるための 3 つ（earshot で前後を比べて決めた。2026-10-31）:
- 共鳴は人の喉と同じく縦につなぎ（Klatt の cascade）、幅を子どもの声の 90〜300 Hz にする。
  幅が 1 kHz 近くあると母音の形がぼやけ、「風船のきしみ」「虫の羽音」に聞かれた
- 3〜5 kHz に F4・F5 を置く。ないと 4 kHz から上が抜けて、作った音に聞こえる
- 息のかすれは声門が開いているあいだに強くなる（周期で脈打つ）。揺らぎは人の声の幅（高さ 0.7%・強さ 4%）
"""
import numpy as np
from scipy import signal

from lib import SR, bp, fade, hp, lp, n_of, place, write

# 小さな人形の声（子どもの声より少し高め）。母音ごとの共鳴 F1..F3 (Hz)
VOWEL = {
    "w": [420, 900, 2600],
    "u": [430, 1500, 2800],
    "a": [980, 1650, 3200],
    "n": [280, 2300, 3300],
    "o": [560, 950, 2800],
    "i": [340, 2650, 3400],
}
BW = [90, 120, 180]                  # 共鳴の幅 (Hz)。子どもの声
F45 = [(4300, 300), (5200, 300)]     # 母音で動かない F4・F5 (Hz, 幅)
# 01 ふつう・02 高い・03 低い の、声の高さと口の響きの倍率 [(高さ, 響き), ...]
SIZES = {
    "wa": [(1.0, 1.0), (1.32, 1.1), (0.68, 0.88)],
    "un": [(1.0, 1.0), (1.32, 1.1), (0.68, 0.88)],
    "nn": [(1.0, 1.0), (1.42, 1.12), (0.52, 0.82)],   # 03 はがっつり低く
    "unq": [(1.0, 1.0), (1.32, 1.1), (0.68, 0.88)],
    "surprise": [(1.0, 1.0), (1.25, 1.08), (0.72, 0.9)],
    "oi": [(1.0, 1.0), (1.32, 1.1), (0.68, 0.88)],
}


def glottal(f0, rng, jitter=0.007, shimmer=0.04):
    """声門の波。f0 はサンプルごとの高さ。1 周ずつ Rosenberg の形を置き、高さと強さを少し揺らす。
    (流れの変化, 声門の開き 0..1) を返す。開きは息のかすれを脈打たせるのに使う"""
    n = len(f0)
    out = np.zeros(n)
    flow = np.zeros(n)
    i = 0
    while i < n:
        f = f0[min(i, n - 1)] * (1 + rng.normal(0, jitter))
        period = max(8, int(SR / max(f, 40)))
        tp, tn = 0.42, 0.16   # 開く・閉じる割合
        t = np.arange(period) / period
        g = np.where(t < tp, 0.5 * (1 - np.cos(np.pi * t / tp)),
                     np.where(t < tp + tn, np.cos(np.pi / 2 * (t - tp) / tn), 0.0))
        d = np.diff(g, prepend=0.0)   # 口から出るのは流れの変化（微分）
        a = 1 + rng.normal(0, shimmer)
        m = min(period, n - i)
        out[i:i + m] += d[:m] * a
        flow[i:i + m] = g[:m]
        i += period
    return out, flow


def formant(x, fs, bws):
    """2 極の共鳴 1 つ。fs・bws はサンプルごとの中心と幅 (Hz)。2.5 ms ずつその時の値で。
    低い所の利得を 1 にそろえる（縦につないだとき、母音ごとの山の高さが自然に決まる）"""
    n = len(x)
    blk = n_of(0.0025)
    y = np.zeros(n)
    zi = np.zeros(2)
    for s in range(0, n, blk):
        e = min(n, s + blk)
        r = np.exp(-np.pi * bws[s] / SR)
        a = [1, -2 * r * np.cos(2 * np.pi * fs[s] / SR), r * r]
        y[s:e], zi = signal.lfilter([sum(a)], a, x[s:e], zi=zi)
    return y


def tract(src, path, form=1.0):
    """口の形を時間で変えながら通す。path は [(秒, 母音), ...]。共鳴は前後の母音のあいだを滑らかにつなぐ。
    form は口の響きの倍率（大きいほど小さな体の声）"""
    n = len(src)
    t = np.arange(n) / SR
    times = [p[0] for p in path]
    y = src
    for k in range(3):
        fs = np.interp(t, times, [VOWEL[v][k] for _, v in path]) * form
        y = formant(y, fs, np.full(n, BW[k] * form))
    for f, bw in F45:
        y = formant(y, np.full(n, f * form), np.full(n, bw * form))
    return y


# 声の素材を替える口（voice_material.py が使う）。None なら人の声（声帯と口の形）。
# 入れると、同じ抑揚（高さの点・強さの点・長さ）のまま、その素材で鳴らす
MATERIAL = None


def voice(f0_pts, path, dur, rng, breath=0.22, env_pts=None, form=1.0):
    """高さの点 [(秒, Hz)] と口の形の点で、声を 1 つ作る"""
    if MATERIAL is not None:
        return MATERIAL(f0_pts, path, dur, rng, env_pts, form)
    n = n_of(dur)
    t = np.arange(n) / SR
    f0 = np.interp(t, [p[0] for p in f0_pts], [p[1] for p in f0_pts])
    # ゆっくりした揺れ（人の声のふらつき）
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t + rng.uniform(0, 6.28))
    src, flow = glottal(f0, rng)
    src = src - 0.8 * np.concatenate([[0.0], src[:-1]])   # 倍音の傾きを少し起こす（母音が「う」にこもらないように）
    src = lp(src, 3800, 2)
    # 息: 声と同じ口を通る、かすれ。声門が開いているあいだに強く（周期で脈打つ）
    pulse = 0.3 + 1.4 * flow / (np.max(flow) + 1e-9)
    noise = hp(rng.standard_normal(n) * pulse, 400, 2) * breath * 0.06
    y = tract(src + noise, path, form)
    env = np.interp(t, [p[0] for p in env_pts], [p[1] for p in env_pts]) if env_pts else np.ones(n)
    y = y * env
    y = hp(y, 120, 2)
    y = lp(y, 5200, 2)   # やわらかく
    return fade(y, 0.01, 0.06)


def wa(rng, pitch=1.0, form=1.0):
    d = rng.uniform(0.72, 0.85)
    top = rng.uniform(1.18, 1.3)
    f = 300 * pitch * rng.uniform(0.97, 1.03)
    return voice(
        [(0, f * 0.92), (0.1, f), (0.28, f * top), (d * 0.7, f * top * 0.92), (d, f * 0.82)],
        [(0, "w"), (0.07, "w"), (0.17, "a"), (d * 0.8, "a"), (d, "u")],
        d, rng, breath=0.28, form=form,
        env_pts=[(0, 0), (0.06, 0.5), (0.16, 1.0), (d * 0.6, 0.85), (d, 0)])


def un(rng, pitch=1.0, form=1.0):
    d = rng.uniform(0.3, 0.36)
    f = 290 * pitch * rng.uniform(0.97, 1.03)
    return voice(
        [(0, f * 1.04), (0.06, f * 1.06), (d, f * 0.78)],
        [(0, "u"), (0.05, "u"), (0.11, "n"), (d, "n")],
        d, rng, breath=0.18, form=form,
        env_pts=[(0, 0), (0.035, 0.9), (0.09, 1.0), (d * 0.7, 0.7), (d, 0)])


def nn(rng, pitch=1.0, form=1.0):
    a = rng.uniform(0.24, 0.3)
    gap = rng.uniform(0.05, 0.07)
    b = rng.uniform(0.28, 0.34)
    d = a + gap + b
    f = 300 * pitch * rng.uniform(0.97, 1.03)
    hi, lo = f * 1.1, f * 0.8
    return voice(
        [(0, f), (a * 0.6, hi), (a, hi * 0.98), (a + gap, lo * 1.08), (d, lo * 0.9)],
        [(0, "n"), (d, "n")],
        d, rng, breath=0.2, form=form,
        # あいだで声を一度止める（喉で区切る）
        env_pts=[(0, 0), (0.04, 0.9), (a * 0.6, 1.0), (a - 0.02, 0.7), (a, 0.05), (a + gap, 0.05),
                 (a + gap + 0.04, 0.85), (d * 0.85, 0.55), (d, 0)])


def unq(rng, pitch=1.0, form=1.0):
    """「ウン？」: う の口からすぐ鼻の声へ。少し沈んでから、後半でたずねるように上がる"""
    d = rng.uniform(0.4, 0.46)
    f = 280 * pitch * rng.uniform(0.97, 1.03)
    return voice(
        [(0, f * 0.98), (0.12, f * 0.92), (d * 0.55, f * 0.98), (d, f * 1.4)],
        [(0, "u"), (0.05, "u"), (0.12, "n"), (d, "n")],
        d, rng, breath=0.2, form=form,
        env_pts=[(0, 0), (0.035, 0.85), (0.1, 1.0), (d * 0.75, 0.9), (d, 0)])


def surprise(rng, pitch=1.0, form=1.0):
    """びっくり: 息をのむ小さなかすれのあと、高い「あ」が短く跳ねて落ちる（痛いのではなく、わっ、と楽しい）"""
    d = rng.uniform(0.26, 0.3)
    f = 430 * pitch * rng.uniform(0.97, 1.03)
    gasp = n_of(0.045)
    y = voice(
        [(0, f * 0.92), (0.035, f * 1.18), (0.09, f * 1.22), (d, f * 0.8)],
        [(0, "u"), (0.03, "a"), (d * 0.8, "a"), (d, "u")],
        d, rng, breath=0.45, form=form,
        env_pts=[(0, 0), (0.012, 1.0), (0.07, 0.9), (d * 0.6, 0.45), (d, 0)])
    out = np.zeros(gasp + len(y))
    if MATERIAL is None:
        # 息をのむ「ひ」: 息だけが「い」から「あ」へ開く口を通る（帯をそろえたノイズだと太鼓の皮の音に聞かれた）
        h = lp(tract(rng.standard_normal(gasp) * np.hanning(gasp), [(0, "i"), (gasp / SR, "a")], form), 5200, 2)
        h *= 0.25 * np.max(np.abs(y)) / (np.max(np.abs(h)) + 1e-9)
    else:
        h = bp(rng.standard_normal(gasp), 1500 * form, 5500, 2) * np.hanning(gasp) * 0.05
    place(out, h, 0.0)
    place(out, y, gasp / SR * 0.6)
    return fade(out, 0.003, 0.05)


def oi(rng, pitch=1.0, form=1.0):
    """「おーーーい」: 遠くへ呼ぶ。お を長く、少しずつ強く伸ばし、最後の い で高く上がって、ふっと抜ける。
    遠くまで届くよう、ほかの声より息を少なく、ゆるい揺れ（ビブラート）を後半に"""
    d = rng.uniform(1.25, 1.4)
    f = 320 * pitch * rng.uniform(0.97, 1.03)
    rise = d - 0.3
    y = voice(
        [(0, f * 0.9), (0.12, f), (rise, f * 1.03), (d - 0.12, f * 1.28), (d, f * 1.2)],
        [(0, "o"), (rise, "o"), (d - 0.14, "i"), (d, "i")],
        d, rng, breath=0.12, form=form,
        env_pts=[(0, 0), (0.08, 0.75), (0.3, 0.9), (rise, 1.0), (d - 0.1, 0.9), (d, 0)])
    # 後半のゆるい揺れ（呼び声の伸ばし）: 強さを 5 Hz ほどで少しだけ揺らす
    t = np.arange(len(y)) / SR
    wob = 1 + 0.08 * np.sin(2 * np.pi * rng.uniform(4.6, 5.4) * t) * np.clip((t - 0.35) / 0.4, 0, 1)
    return fade(y * wob, 0.01, 0.08)


if __name__ == "__main__":
    for name, fn, seed, peak in [("wa", wa, 700, -6), ("un", un, 710, -7), ("nn", nn, 720, -7),
                                 ("unq", unq, 730, -7), ("surprise", surprise, 740, -6), ("oi", oi, 750, -5)]:
        for i, (pitch, form) in enumerate(SIZES[name]):
            write(f"voice_{name}_{i + 1:02d}.wav", fn(np.random.default_rng(seed + i), pitch, form), peak)
