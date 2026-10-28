"""言葉にならない声。紙の人形の、小さくてやわらかい声。言葉ではない。

voice_wa_01..03   「ワ〜」うれしい・解放。う の口から あ へ開き、高く上がってから下りる
voice_un_01..03   「ウン」うなずき・了解。口を閉じた鼻の声で、短く下がる
voice_nn_01..03   「ンーン」いやいや・ちがう。鼻の声が 2 つ。高いほうから低いほうへ

声帯の音（声門の波を 1 周ずつ作り、揺らぎを入れる）に息を混ぜ、口の形の共鳴（フォルマント）を通す。
録音も生成サービスも使わない。高さは人ごとに Godot 側で少し変える（pitch_scale）。
やわらかくするため: 息を多めに混ぜ、高い倍音を落とし、立ち上がりと終わりをなだらかにする。
"""
import numpy as np
from scipy import signal

from lib import SR, fade, hp, lp, n_of, write

# 小さな人形の声（子どもの声より少し高め）。母音ごとの共鳴 (Hz) と幅（r）
VOWEL = {
    "w": [(420, 0.94), (900, 0.95), (2600, 0.96)],
    "u": [(430, 0.94), (1500, 0.95), (2800, 0.96)],
    "a": [(980, 0.945), (1650, 0.95), (3200, 0.96)],
    "n": [(280, 0.975), (2300, 0.97), (3300, 0.96)],
}
GAIN = {"w": [1.0, 0.3, 0.06], "u": [1.0, 0.45, 0.12], "a": [1.0, 1.4, 0.6], "n": [1.0, 0.05, 0.03]}


def glottal(f0, rng, jitter=0.012, shimmer=0.06):
    """声門の波。f0 はサンプルごとの高さ。1 周ずつ Rosenberg の形を置き、高さと強さを少し揺らす"""
    n = len(f0)
    out = np.zeros(n)
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
        i += period
    return out


def tract(src, path):
    """口の形を時間で変えながら通す。path は [(秒, 母音), ...]。共鳴は前後の母音のあいだを滑らかにつなぐ"""
    n = len(src)
    t = np.arange(n) / SR
    times = [p[0] for p in path]
    out = np.zeros(n)
    for k in range(3):
        fs = np.interp(t, times, [VOWEL[v][k][0] for _, v in path])
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


def voice(f0_pts, path, dur, rng, breath=0.22, env_pts=None):
    """高さの点 [(秒, Hz)] と口の形の点で、声を 1 つ作る"""
    n = n_of(dur)
    t = np.arange(n) / SR
    f0 = np.interp(t, [p[0] for p in f0_pts], [p[1] for p in f0_pts])
    # ゆっくりした揺れ（人の声のふらつき）
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t + rng.uniform(0, 6.28))
    src = glottal(f0, rng)
    src = src - 0.8 * np.concatenate([[0.0], src[:-1]])   # 倍音の傾きを少し起こす（母音が「う」にこもらないように）
    src = lp(src, 3800, 2)
    # 息: 声と同じ口を通る、かすれ
    noise = hp(rng.standard_normal(n), 400, 2) * breath * 0.03
    y = tract(src + noise, path)
    env = np.interp(t, [p[0] for p in env_pts], [p[1] for p in env_pts]) if env_pts else np.ones(n)
    y = y * env
    y = hp(y, 120, 2)
    y = lp(y, 5200, 2)   # やわらかく
    return fade(y, 0.01, 0.06)


def wa(rng):
    d = rng.uniform(0.72, 0.85)
    top = rng.uniform(1.18, 1.3)
    f = 300 * rng.uniform(0.97, 1.03)
    return voice(
        [(0, f * 0.92), (0.1, f), (0.28, f * top), (d * 0.7, f * top * 0.92), (d, f * 0.82)],
        [(0, "w"), (0.07, "w"), (0.17, "a"), (d * 0.8, "a"), (d, "u")],
        d, rng, breath=0.28,
        env_pts=[(0, 0), (0.06, 0.5), (0.16, 1.0), (d * 0.6, 0.85), (d, 0)])


def un(rng):
    d = rng.uniform(0.3, 0.36)
    f = 290 * rng.uniform(0.97, 1.03)
    return voice(
        [(0, f * 1.04), (0.06, f * 1.06), (d, f * 0.78)],
        [(0, "u"), (0.05, "u"), (0.11, "n"), (d, "n")],
        d, rng, breath=0.18,
        env_pts=[(0, 0), (0.035, 0.9), (0.09, 1.0), (d * 0.7, 0.7), (d, 0)])


def nn(rng):
    a = rng.uniform(0.24, 0.3)
    gap = rng.uniform(0.05, 0.07)
    b = rng.uniform(0.28, 0.34)
    d = a + gap + b
    f = 300 * rng.uniform(0.97, 1.03)
    hi, lo = f * 1.1, f * 0.8
    return voice(
        [(0, f), (a * 0.6, hi), (a, hi * 0.98), (a + gap, lo * 1.08), (d, lo * 0.9)],
        [(0, "n"), (d, "n")],
        d, rng, breath=0.2,
        # あいだで声を一度止める（喉で区切る）
        env_pts=[(0, 0), (0.04, 0.9), (a * 0.6, 1.0), (a - 0.02, 0.7), (a, 0.05), (a + gap, 0.05),
                 (a + gap + 0.04, 0.85), (d * 0.85, 0.55), (d, 0)])


if __name__ == "__main__":
    for i in range(3):
        write(f"voice_wa_{i + 1:02d}.wav", wa(np.random.default_rng(700 + i)), -6)
        write(f"voice_un_{i + 1:02d}.wav", un(np.random.default_rng(710 + i)), -7)
        write(f"voice_nn_{i + 1:02d}.wav", nn(np.random.default_rng(720 + i)), -7)
