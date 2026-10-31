"""言葉にならない声。紙の人形の、小さくてやわらかい声。言葉ではない。

voice_wa_<人形>   「ワ〜」うれしい・解放。う の口から あ へ開き、高く上がってから下りる
voice_un_<人形>   「ウン」うなずき・了解。口を閉じた鼻の声で、短く下がる
voice_nn_<人形>   「ンーン」いやいや・ちがう。鼻の声が 2 つ。高いほうから低いほうへ
voice_unq_<人形>  「ウン？」たずねる・首をかしげる。鼻の声で、後半が上がる
voice_surprise_<人形>  びっくり（雪玉が当たったとき）。息を吸うかすれから、高い「あ」が短く跳ねる
voice_oi_<人形>   「おーーーい」遠くの人を呼ぶ。お を高めで平らに長く伸ばし、最後の い で下がって終わる

<人形> は game/doll.gd の VOICE の人形（まだゲームにいない人形も）。上がり下がりの形と長さは人形どうしで同じ。
声の高さは、性別と身長で決める（女性で背が低いほど高く、男性で背が高いほど低い。代表の言葉、2026-10-31）か、
VOICE に書いた高さにする。口の響きは体の大きさについていく（小さな体ほど響きが高い。男性は少し低い）。
声色（COLORS）は、ロボット・鋭い・丸い・獣のカタコト。ふつうの声は声色を足さない。

声帯の音（声門の波を 1 周ずつ作り、揺らぎを入れる）に息を混ぜ、口の形の共鳴（フォルマント）を通す。
録音も生成サービスも使わない。高さは wav に焼き込み、Godot 側の pitch_scale では変えない（速さと口の響きが崩れるので）。
やわらかくするため: 息を多めに混ぜ、高い倍音を落とし、立ち上がりと終わりをなだらかにする。
"""
import pathlib
import re

import numpy as np
from scipy import signal

from lib import SR, bp, db, fade, hp, lp, n_of, place, rms_db, write

# 小さな人形の声（子どもの声より少し高め）。母音ごとの共鳴 (Hz) と幅（r）
VOWEL = {
    "w": [(420, 0.94), (900, 0.95), (2600, 0.96)],
    "u": [(430, 0.94), (1500, 0.95), (2800, 0.96)],
    "a": [(980, 0.945), (1650, 0.95), (3200, 0.96)],
    "n": [(280, 0.975), (2300, 0.97), (3300, 0.96)],
    "o": [(560, 0.94), (950, 0.945), (2800, 0.96)],
    "i": [(340, 0.95), (2650, 0.955), (3400, 0.96)],
}
GAIN = {"w": [1.0, 0.3, 0.06], "u": [1.0, 0.45, 0.12], "a": [1.0, 1.4, 0.6], "n": [1.0, 0.05, 0.03],
        "o": [1.0, 0.9, 0.2], "i": [1.0, 0.55, 0.35]}
# 人形の声（性別・高さ・声色）と身長は game/doll.gd から読む（VOICE、TOP（人形の頭の高さ）× SCALE（ゲームでの大きさ））。人形を足すときもそちらに書く
SEX_PITCH = {"女": 1.0, "男": 0.6}    # 男性は約 9 半音低く
SEX_FORM = {"女": 1.0, "男": 0.9}     # 男性は口の響きも少し低く
HEIGHT_PITCH = 0.75    # 身長が半分なら、高さは 2^0.75 = 1.68 倍
HEIGHT_FORM = 0.5      # 口の響きは、体の大きさにゆるくついていく


def dolls():
    """game/doll.gd から、人形ごとの (性別, 高さ, 声色, 身長 (m) か None)。身長は TOP × SCALE（まだゲームにいない人形は None）"""
    src = (pathlib.Path(__file__).resolve().parents[2] / "game" / "doll.gd").read_text()
    def table(name):
        body = re.search(rf"^const {name} := \{{(.*?)\}}", src, re.M).group(1)
        return {k: float(v) for k, v in re.findall(r'"(\w+)":\s*([\d.]+)', body)}
    top, scale = table("TOP"), table("SCALE")
    body = re.search(r"^const VOICE := \{(.*?)^\}", src, re.M | re.S).group(1)
    return {k: (sex, float(pitch), color, top[k] * scale[k] if k in top and k in scale else None)
            for k, sex, pitch, color in re.findall(r'"(\w+)":\s*\["(.*?)",\s*([\d.]+),\s*"(.*?)"\]', body)}


def voices():
    """人形ごとの (身長, 声の高さの倍率, 口の響きの倍率, 声色)。あなた（kasa）の声を 1.0 にする"""
    ds = dolls()
    out = {}
    for k, (sex, pitch, color, h) in ds.items():
        if pitch > 0:
            # 高さを書いた人形: 口の響きも高さにゆるくついていく
            out[k] = (h, pitch, pitch ** HEIGHT_FORM, color)
        else:
            r = ds["kasa"][3] / h
            out[k] = (h, SEX_PITCH[sex] * r ** HEIGHT_PITCH, SEX_FORM[sex] * r ** HEIGHT_FORM, color)
    return out


# 声色。voice() が使う（COLOR に入れる）。どれも、ふつうの声からの変え方
COLORS = {
    # ロボット: 揺れをなくし、高さを 70 ms ずつの段にする（抑揚の形は残す）。段ボールの箱の響き（短いくし形）と、金属っぽい振幅の変調
    "robot": dict(jitter=0.0, shimmer=0.0, wobble=0.0, step=0.07, comb=(0.0028, 0.55), ring=(55.0, 0.35)),
    # 鋭い: 声門をすばやく閉じて倍音を増やし、息を少なく、高い所を落とさない
    "sharp": dict(tn=0.07, breath=0.5, src_lp=6000, out_lp=7500, tilt=0.9),
    # 丸い: 声門をゆっくり閉じて倍音を減らし、息を少し多く、高い所を早めに落とす
    "round": dict(tp=0.5, tn=0.32, breath=1.3, src_lp=2400, out_lp=3600, tilt=0.6),
    # 獣のカタコト: 1 周おきに声門の強さを落とすうなり（周期が倍に聞こえる）、大きな揺れ、かすれ。長い声は途中で何度か詰まる
    "beast": dict(jitter=0.03, shimmer=0.16, alt=0.45, breath=1.6, out_lp=4200, chop=(0.19, 0.8)),
}
COLOR = None


def glottal(f0, rng, jitter=0.012, shimmer=0.06, tp=0.42, tn=0.16, alt=0.0):
    """声門の波。f0 はサンプルごとの高さ。1 周ずつ Rosenberg の形を置き、高さと強さを少し揺らす。
    tp・tn は開く・閉じる割合（閉じるのが速いほど倍音が多い）。alt は 1 周おきに強さを落とす割合（うなり）"""
    n = len(f0)
    out = np.zeros(n)
    i = 0
    k = 0
    while i < n:
        f = f0[min(i, n - 1)] * (1 + rng.normal(0, jitter))
        period = max(8, int(SR / max(f, 40)))
        t = np.arange(period) / period
        g = np.where(t < tp, 0.5 * (1 - np.cos(np.pi * t / tp)),
                     np.where(t < tp + tn, np.cos(np.pi / 2 * (t - tp) / tn), 0.0))
        d = np.diff(g, prepend=0.0)   # 口から出るのは流れの変化（微分）
        a = (1 + rng.normal(0, shimmer)) * (1 - alt if k % 2 else 1.0)
        k += 1
        m = min(period, n - i)
        out[i:i + m] += d[:m] * a
        i += period
    return out


def tract(src, path, form=1.0):
    """口の形を時間で変えながら通す。path は [(秒, 母音), ...]。共鳴は前後の母音のあいだを滑らかにつなぐ。
    form は口の響きの倍率（大きいほど小さな体の声）"""
    n = len(src)
    t = np.arange(n) / SR
    times = [p[0] for p in path]
    out = np.zeros(n)
    for k in range(3):
        fs = np.interp(t, times, [VOWEL[v][k][0] for _, v in path]) * form
        rs = np.interp(t, times, [VOWEL[v][k][1] for _, v in path])
        gs = np.interp(t, times, [GAIN[v][k] for _, v in path])
        # 共鳴は 1 ブロック（10 ms）ずつ、その時の中心で
        blk = n_of(0.01)
        y = np.zeros(n)
        zi = np.zeros(2)
        for s in range(0, n, blk):
            e = min(n, s + blk)
            f, r = fs[s], rs[s]
            w = 2 * np.pi * f / SR
            b, a = [1 - r], [1, -2 * r * np.cos(w), r * r]
            y[s:e], zi = signal.lfilter(b, a, src[s:e], zi=zi)
        out += y * gs
    return out


# 声の素材を替える口（voice_material.py が使う）。None なら人の声（声帯と口の形）。
# 入れると、同じ抑揚（高さの点・強さの点・長さ）のまま、その素材で鳴らす
MATERIAL = None


def voice(f0_pts, path, dur, rng, breath=0.22, env_pts=None, form=1.0):
    """高さの点 [(秒, Hz)] と口の形の点で、声を 1 つ作る"""
    if MATERIAL is not None:
        return MATERIAL(f0_pts, path, dur, rng, env_pts, form)
    c = COLOR or {}
    n = n_of(dur)
    t = np.arange(n) / SR
    f0 = np.interp(t, [p[0] for p in f0_pts], [p[1] for p in f0_pts])
    if c.get("step"):
        # 高さを段にする（段の中ほどの高さで止める）
        h = n_of(c["step"])
        f0 = np.repeat(f0[np.minimum(np.arange(0, n, h) + h // 2, n - 1)], h)[:n]
    # ゆっくりした揺れ（人の声のふらつき）
    f0 *= 1 + c.get("wobble", 0.012) * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t + rng.uniform(0, 6.28))
    src = glottal(f0, rng, c.get("jitter", 0.012), c.get("shimmer", 0.06), c.get("tp", 0.42), c.get("tn", 0.16), c.get("alt", 0.0))
    src = src - c.get("tilt", 0.8) * np.concatenate([[0.0], src[:-1]])   # 倍音の傾きを少し起こす（母音が「う」にこもらないように）
    src = lp(src, c.get("src_lp", 3800), 2)
    # 息: 声と同じ口を通る、かすれ
    noise = hp(rng.standard_normal(n), 400, 2) * breath * c.get("breath", 1.0) * 0.03
    y = tract(src + noise, path, form)
    env = np.interp(t, [p[0] for p in env_pts], [p[1] for p in env_pts]) if env_pts else np.ones(n)
    if c.get("chop") and dur > 0.45:
        # カタコト: 一定の間で、声を短く詰まらせる（なめらかにへこませる）
        gap, depth = c["chop"]
        dip = np.zeros(n)
        for s in np.arange(gap, dur - 0.12, gap):
            dip = np.maximum(dip, np.exp(-0.5 * ((t - s) / 0.018) ** 2))
        env = env * (1 - depth * dip)
    y = y * env
    if c.get("comb"):
        d, g = c["comb"]
        y = y + g * np.concatenate([np.zeros(n_of(d)), y[:-n_of(d)]])
    if c.get("ring"):
        f, depth = c["ring"]
        y = y * (1 - depth + depth * np.sin(2 * np.pi * f * t))
    y = hp(y, 120, 2)
    y = lp(y, c.get("out_lp", 5200), 2)   # やわらかく
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
    h = bp(rng.standard_normal(gasp), 1500 * form, 5500, 2) * np.hanning(gasp) * 0.05   # 息をのむ「ひ」
    place(out, h, 0.0)
    place(out, y, gasp / SR * 0.6)
    return fade(out, 0.003, 0.05)


def oi(rng, pitch=1.0, form=1.0):
    """「おーーーい」: 遠くへ呼ぶ。お を高めで平らに長く、少しずつ強く伸ばし、最後の い で下がって、ふっと抜ける
    （遠くの人を呼ぶときの、語尾が下がる抑揚）。
    遠くまで届くよう、ほかの声より息を少なく、ゆるい揺れ（ビブラート）を後半に"""
    d = rng.uniform(1.25, 1.4)
    f = 320 * pitch * rng.uniform(0.97, 1.03)
    rise = d - 0.3
    y = voice(
        [(0, f * 0.9), (0.12, f * 1.02), (rise, f * 1.04), (d - 0.12, f * 0.84), (d, f * 0.76)],
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
        # 人形どうしで同じ乱数にして、長さと抑揚をそろえる（ちがうのは高さと口の響きだけ）
        base = None
        for doll, (_, pitch, form, color) in voices().items():
            COLOR = COLORS.get(color)
            x = fn(np.random.default_rng(seed), pitch, form)
            if COLOR is None:
                x = write(f"voice_{name}_{doll}.wav", x, peak)
                base = rms_db(x) if doll == "kasa" else base
            else:
                # 声色を変えた声は、ピークでなく聞こえの大きさ（実効値）をあなたの声にそろえる。ピークは -1 dB まで
                x = x * db(base - rms_db(x))
                write(f"voice_{name}_{doll}.wav", x / max(1.0, np.max(np.abs(x)) / db(-1.0)), None)
    COLOR = None
