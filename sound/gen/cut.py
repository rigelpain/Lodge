"""raw/ の録音から、一歩・一発ずつ切り出して wav/ に入れる。

使い方:
  .venv/bin/python gen/cut.py scan        raw の各ファイルの包絡と見つけた音の頭を check/raw_*.png に描き、時刻を出す
  .venv/bin/python gen/cut.py             PICKS に従って切り出し、wav/ に書く

切り出し: モノラルにして 48 kHz に直し、60 Hz 以下を落とす。音の頭の 6 ms 手前から、
包絡が床に戻るまで（上限あり）。頭 2 ms・尾 25 ms のフェード。音量はピークでそろえる。
"""
import pathlib
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lib import SR, fade, hp, lp, n_of, seamless, write  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
RAW, CHECK = ROOT / "raw", ROOT / "check"


def load(name):
    path = next(RAW.glob(name + "*"))
    sr, x = wavfile.read(path)
    x = x.astype(np.float64)
    if x.ndim == 2:
        x = x.mean(axis=1)
    peak = {np.dtype("int16"): 32768.0, np.dtype("int32"): 2147483648.0}.get(wavfile.read(path)[1].dtype, 1.0)
    x /= peak
    if sr != SR:
        g = np.gcd(sr, SR)
        x = signal.resample_poly(x, SR // g, sr // g)
    x = hp(x, 60, 2)
    return x, path.name


def envelope(x, win=0.003):
    k = n_of(win)
    e = np.sqrt(np.convolve(x * x, np.ones(k) / k, mode="same"))
    return 20 * np.log10(e + 1e-9)


def onsets(x, gap=0.15, rise_db=12.0, floor_pct=20, min_db=-45.0):
    env = envelope(x)
    floor = np.percentile(env, floor_pct)
    thr = max(floor + rise_db, min_db)
    above = env > thr
    starts = np.flatnonzero(above[1:] & ~above[:-1]) + 1
    out = []
    last = -1e9
    for s in starts:
        if (s - last) / SR < gap:
            continue
        out.append(s)
        last = s
    return np.array(out), env, floor, thr


def cut(x, start, env, floor, max_len=0.5, pre=0.006, settle_db=6.0, min_len=0.0):
    i0 = max(0, start - n_of(pre))
    i_peak = start + int(np.argmax(env[start:start + n_of(min(0.25, max_len))]))
    end_thr = floor + settle_db
    i1 = min(len(x), start + n_of(max_len))
    hold = n_of(0.03)
    below = 0
    for i in range(max(i_peak, start + n_of(min_len)), i1):
        below = below + 1 if env[i] < end_thr else 0
        if below >= hold:
            i1 = i
            break
    seg = x[i0:i1]
    return fade(seg, 0.002, min(0.025, len(seg) / SR / 3))


# どの録音の、何秒の音を使うか（scan の絵を見て決めた）。時刻は音の頭のだいたいの位置
PICKS = [
    # 雪の足あと: Vrymaa の粉雪の歩き（代表が 2026-10-27 に聞き比べて選んだ。eZZin の冷えた雪は針のような突起が多く不採用）
    dict(out="step_snow", src="773740", times=[0.88, 1.50, 2.07, 2.94, 3.52, 4.17], gap=0.3, max_len=0.42, min_len=0.15, peak=-9, rms=-25, hp_hz=120),
    # 踏ん張り: Nox_Sound の山靴。重く長い
    dict(out="step_snow_push", src="613849", times=[0.03, 1.92, 2.79, 8.39], gap=0.5, max_len=0.5, min_len=0.3, peak=-8, rms=-24, hp_hz=100),
    # 器: Vrymaa の皿の片づけ 4 つと、bbrocer の皿を卓に置く 2 つ
    dict(out="dish", src="797581", times=[0.62, 1.84, 3.64, 5.52], gap=0.3, max_len=0.7, peak=-9, hp_hz=150),
    dict(out="dish", src="382643", times=[2.31, 8.92], gap=0.3, max_len=0.7, peak=-9, hp_hz=150, start_index=5),
]
# 薪のはぜる音: ceich93 の暖炉から、床より十分に大きい破裂を 8 つ（自動で選ぶ）
CRACKS = dict(out="fire_crack", src="263864", count=8, peak=-5, hp_hz=500)
# 火の唸り: Vrymaa の薪ストーブ 19〜27 秒。破裂はならして（はぜる音は別に鳴らす）、継ぎ目をなくす
BED = dict(out="fire_bed_loop", src="770108", start=19.0, length=8.6, peak=-8)


def cut_at(x, t, gap, max_len, min_len=0.0, tame=False):
    """t 秒のあたりの一歩を切る。細かいクリックの頭ではなく、30 ms でならした包絡の山で一歩を見つけ、
    山の前後で包絡が床へ戻る所を端にする"""
    env = envelope(x, 0.03)
    floor = np.percentile(env, 20)
    lo, hi = n_of(max(0.0, t - 0.3)), min(len(x), n_of(t + 0.3))
    pk = lo + int(np.argmax(env[lo:hi]))
    thr = max(floor + 8.0, env[pk] - 22.0)
    i0 = pk
    while i0 > max(0, pk - n_of(0.2)) and env[i0] > thr:
        i0 -= 1
    i1 = pk
    limit = min(len(x), i0 + n_of(max_len))
    while i1 < limit and (env[i1] > thr or i1 - i0 < n_of(min_len)):
        i1 += 1
    i0 = max(0, i0 - n_of(0.008))
    seg = x[i0:i1]
    if tame:
        seg = tame_clicks(seg)
    return fade(seg, 0.003, min(0.03, len(seg) / SR / 3))


def tame_clicks(seg, over_db=10.0):
    """1 ms の針のような突起だけをならす。30 ms の包絡より over_db 以上出た所を押さえ、きしみの体を前に出す"""
    fast = envelope(seg, 0.0015)
    slow = envelope(seg, 0.03)
    over = fast - (slow + over_db)
    g = np.where(over > 0, 10 ** (-over / 20), 1.0)
    g = np.convolve(g, np.ones(n_of(0.001)) / n_of(0.001), mode="same")
    return seg * g


def run():
    counters = {}
    for pk in PICKS:
        x, _ = load(pk["src"])
        x = hp(x, pk["hp_hz"], 2)
        k = pk.get("start_index", counters.get(pk["out"], 1))
        for t in pk["times"]:
            seg = cut_at(x, t, pk["gap"], pk["max_len"], pk.get("min_len", 0.0), pk.get("tame", False))
            if "rms" in pk:
                # 実効値でそろえる（針のような突起があるとピークでは体が小さくなる）。ピークは -1 dB まで
                g = 10 ** (pk["rms"] / 20) / (np.sqrt(np.mean(seg * seg)) + 1e-9)
                g = min(g, 10 ** (-1 / 20) / (np.max(np.abs(seg)) + 1e-9))
                write(f"{pk['out']}_{k:02d}.wav", seg * g, None)
            else:
                write(f"{pk['out']}_{k:02d}.wav", seg, pk["peak"])
            k += 1
        counters[pk["out"]] = k
    # 薪
    x, _ = load(CRACKS["src"])
    x = hp(x, CRACKS["hp_hz"], 2)
    ons, env, floor, thr = onsets(x, gap=0.25, rise_db=18)
    peaks = np.array([env[o:o + n_of(0.05)].max() for o in ons])
    order = np.argsort(-peaks)
    chosen = sorted(ons[order[:CRACKS["count"]]])
    for k, o in enumerate(chosen):
        seg = cut(x, o, env, floor, max_len=0.3, settle_db=8)
        write(f"{CRACKS['out']}_{k + 1:02d}.wav", seg, CRACKS["peak"] - (0 if k % 3 == 0 else 3))
    # 火の唸り
    x, _ = load(BED["src"])
    seg = x[n_of(BED["start"]):n_of(BED["start"] + BED["length"])].copy()
    env = envelope(seg, 0.01)
    lim = np.percentile(env, 70) + 4
    over = env > lim
    seg[over] *= 10 ** ((lim - env[over]) / 20)
    seg = lp(seg, 9000, 2)
    write(f"{BED['out']}.wav", seamless(seg, 0.6), BED["peak"])


def scan():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.family"] = ["Hiragino Sans", "sans-serif"]
    for path in sorted(RAW.glob("*.wav")):
        x, name = load(path.name[:6])
        ons, env, floor, thr = onsets(x)
        t = np.arange(len(x)) / SR
        fig, ax = plt.subplots(2, 1, figsize=(16, 5), sharex=True)
        ax[0].plot(t, x, lw=0.3, color="#3a4a6b")
        ax[0].set_title(f"{name}  {len(x) / SR:.1f} s  音の頭 {len(ons)} 個")
        ax[1].plot(t, env, lw=0.4, color="#333")
        ax[1].axhline(thr, color="#ff4f30", lw=0.6)
        ax[1].axhline(floor, color="#888", lw=0.6)
        ax[1].set_ylim(-80, 0)
        for k, o in enumerate(ons):
            ax[1].axvline(o / SR, color="#ff4f30", lw=0.4)
            if k % max(1, len(ons) // 40) == 0:
                ax[1].text(o / SR, -2, str(k), fontsize=6, ha="center", va="top", color="#ff4f30")
        fig.tight_layout()
        fig.savefig(CHECK / f"raw_{name[:6]}.png", dpi=90)
        plt.close(fig)
        print(f"{name}: {len(ons)} 個  床 {floor:.0f} dB  しきい {thr:.0f} dB")
        print("   " + " ".join(f"{k}:{o / SR:.2f}" for k, o in enumerate(ons)))


if __name__ == "__main__":
    if sys.argv[1:] == ["scan"]:
        scan()
    else:
        run()
