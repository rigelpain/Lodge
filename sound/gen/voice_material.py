"""素材で喋る声の候補（聞き比べ用）。2026-10-29 に代表が聞き比べて、人の声のままに決めた。
音は外した（all.py からも外す）。聞き直すときはこの台本を走らせ、gen/check.py で試聴ページを作り直す。


カペリートや Don't Starve のように、言葉でも人の声でもない音が、抑揚で喋っているように聞こえる声を試す。
抑揚（高さの上がり下がり・強さの山・長さ）は voice.py の声とまったく同じものを使い、鳴らす素材だけを替える。

voice_paper_<声>_01.wav   紙を丸めるカシャカシャ。細かくはぜる粒の密度が声の強さに、粒の響きの高さが声の高さについていく
voice_felt_<声>_01.wav    フェルトをこするごそごそ。こする速さと強さが声の強さに、こもった擦れの響きが声の高さについていく
voice_kazoo_<声>_01.wav   紙の櫛笛（紙のカズー）。声の芯の代わりに、紙がびりびり震える音。高さがいちばんはっきり伝わる

<声> は wa（ワ〜）・un（ウン）・nn（ンーン）・unq（ウン？）・surprise（びっくり）。大きさは 01（ふつう）だけ。
録音も生成サービスも使わない。
"""
import numpy as np
from scipy import signal

import voice as V
from lib import SR, bp, db, fade, hp, lp, n_of, resonator, rms_db, softclip, write


def _curves(f0_pts, dur, env_pts, rng):
    """抑揚の点を、サンプルごとの高さと強さにする（高さには人の声と同じゆっくりした揺れ）"""
    n = n_of(dur)
    t = np.arange(n) / SR
    f0 = np.interp(t, [p[0] for p in f0_pts], [p[1] for p in f0_pts])
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t + rng.uniform(0, 6.28))
    env = np.interp(t, [p[0] for p in env_pts], [p[1] for p in env_pts]) if env_pts else np.ones(n)
    return n, t, f0, env


def _moving_band(x, fc, r):
    """中心が時間で動く共鳴を、10 ms ずつ当てる"""
    n = len(x)
    blk = n_of(0.01)
    y = np.zeros(n)
    zi = np.zeros(2)
    for s in range(0, n, blk):
        e = min(n, s + blk)
        w = 2 * np.pi * float(np.clip(fc[s], 60, SR * 0.45)) / SR
        y[s:e], zi = signal.lfilter([1 - r], [1, -2 * r * np.cos(w), r * r], x[s:e], zi=zi)
    return y


def paper(f0_pts, path, dur, rng, env_pts, form):
    """紙を丸める音で喋る。はぜる粒を、声の強さの分だけ密に置く。粒は声の高さに合わせて響く"""
    n, t, f0, env = _curves(f0_pts, dur, env_pts, rng)
    out = np.zeros(n)
    rate = 900.0   # 声がいちばん強いときの、1 秒あたりの粒
    i = 0
    while i < n:
        e = env[i]
        i += max(1, int(rng.exponential(SR / (rate * max(e, 0.04)))))
        if i >= n or e < 0.03:
            continue
        g = n_of(rng.uniform(0.0015, 0.005))
        grain = rng.standard_normal(g) * np.exp(-np.arange(g) / (g * 0.3))
        # 粒の響き: 声の高さの 5 倍あたりに細く（声が上がると紙の鳴りも上がる。散らしすぎると抑揚が消える）
        fc = f0[i] * rng.uniform(4.7, 5.3) * form
        grain = resonator(np.concatenate([grain, np.zeros(n_of(0.008))]), fc, 0.975)
        m = min(len(grain), n - i)
        out[i:i + m] += grain[:m] * e * rng.uniform(0.4, 1.0)
    # カシャッとした高い成分を少し、紙のこすれ（声の高さで鳴る細い音）を薄く重ねる
    crack = hp(out, 3000, 2) * 0.35
    rustle = _moving_band(rng.standard_normal(n), f0 * 2.5 * form, 0.996) * env * 0.9
    y = out + crack + rustle
    return fade(lp(hp(y, 300, 2), 9000, 2), 0.004, 0.05)


def felt(f0_pts, path, dur, rng, env_pts, form):
    """フェルトをこする音で喋る。こする往復（ごそ、ごそ）を声の強さに、こもった擦れの響きを声の高さに"""
    n, t, f0, env = _curves(f0_pts, dur, env_pts, rng)
    noise = rng.standard_normal(n)
    # こする往復: 1 秒に 10〜14 回。速さは少しずつ揺らす
    stroke_hz = rng.uniform(10.0, 14.0) * (1 + 0.15 * np.sin(2 * np.pi * rng.uniform(1.0, 2.0) * t))
    phase = np.cumsum(stroke_hz) / SR
    strokes = 0.35 + 0.65 * np.abs(np.sin(np.pi * phase)) ** 1.5
    rub = lp(noise, 1800, 2)
    body = _moving_band(noise, f0 * 2.2 * form, 0.993) * 2.6   # 声の高さで鳴る、こもった響き
    y = (rub * 0.5 + body) * strokes * env
    return fade(lp(hp(y, 120, 2), 3200, 2), 0.01, 0.06)


def kazoo(f0_pts, path, dur, rng, env_pts, form):
    """紙の櫛笛で喋る。息で紙が震え、びりびりと鳴る（倍音の多い鋸の波を紙が叩く）。紙の膜の響きを 2 つ"""
    n, t, f0, env = _curves(f0_pts, dur, env_pts, rng)
    phase = np.cumsum(f0) / SR
    saw = 2.0 * (phase % 1.0) - 1.0
    saw = lp(saw, 7000, 2)
    # 紙が櫛に張りついて離れる: 片側だけ強く潰れる
    buzz = np.where(saw > 0, softclip(saw * 4.0, 2.0), saw * 0.35)
    # ふち鳴り: 波の山ごとに、紙のふちが細かくびりつく
    rattle = hp(rng.standard_normal(n), 3000, 2) * np.clip(saw, 0, None) ** 2 * 0.9
    y = buzz + rattle
    y = y + bp(y, 1100 * form, 1500 * form, 2) * 1.2 + bp(y, 2500 * form, 3300 * form, 2) * 0.9   # 紙の膜の響き
    y = y * env
    return fade(lp(hp(y, 200, 2), 7500, 2), 0.008, 0.05)


if __name__ == "__main__":
    for mat_name, mat in [("paper", paper), ("felt", felt), ("kazoo", kazoo)]:
        V.MATERIAL = mat
        for name, fn, seed in [("wa", V.wa, 700), ("un", V.un, 710), ("nn", V.nn, 720),
                               ("unq", V.unq, 730), ("surprise", V.surprise, 740)]:
            _, pitch, form = V.voices()["kasa"]
            x = fn(np.random.default_rng(seed), pitch, form)
            # 聞き比べのため、素材どうしで聞こえの大きさ（実効値）をそろえる。ピークは -2 dB まで
            x = x * db(-21.0 - rms_db(x))
            x = x / max(1.0, np.max(np.abs(x)) / db(-2.0))
            write(f"voice_{mat_name}_{name}_01.wav", x, None)
    V.MATERIAL = None
