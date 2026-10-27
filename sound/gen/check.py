"""sound/wav/ の各 wav について、波形とスペクトログラムの PNG を sound/check/ に出す。
あわせて summary.md に長さ・ピーク・実効値・重心・継ぎ目の段差を表にする。

使い方: .venv/bin/python gen/check.py [名前の一部...]
"""
import pathlib
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
WAV, CHECK = ROOT / "wav", ROOT / "check"


def analyze(path):
    sr, x = wavfile.read(path)
    x = x.astype(np.float64) / 32767
    dur = len(x) / sr
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    rms = 20 * np.log10(np.sqrt(np.mean(x * x)) + 1e-12)
    f, p = signal.welch(x, sr, nperseg=4096)
    centroid = float(np.sum(f * p) / np.sum(p))
    cum = np.cumsum(p) / np.sum(p)
    f90 = float(f[np.searchsorted(cum, 0.9)])
    seam = float(abs(x[-1] - x[0]))
    return x, sr, dict(dur=dur, peak=peak, rms=rms, centroid=centroid, f90=f90, seam=seam)


def plot(path, x, sr, info):
    short = len(x) / sr < 1.5
    nfft = 1024 if short else 4096
    fig, (a0, a1) = plt.subplots(2, 1, figsize=(10, 6.2), height_ratios=[1, 2.2], sharex=True)
    t = np.arange(len(x)) / sr
    a0.plot(t, x, lw=0.4, color="#3a4a6b")
    a0.set_ylim(-1, 1)
    a0.set_ylabel("振幅")
    a0.set_title(f"{path.name}   {info['dur']:.2f} s   peak {info['peak']:.1f} dB   rms {info['rms']:.1f} dB   重心 {info['centroid']:.0f} Hz   90% {info['f90']:.0f} Hz")
    f, tt, s = signal.spectrogram(x, sr, nperseg=nfft, noverlap=nfft * 3 // 4, window="hann")
    s_db = 10 * np.log10(s + 1e-12)
    vmax = s_db.max()
    a1.pcolormesh(tt, f, s_db, vmin=vmax - 80, vmax=vmax, shading="auto", cmap="magma", rasterized=True)
    a1.set_yscale("log")
    a1.set_ylim(40, 20000)
    a1.set_ylabel("Hz")
    a1.set_xlabel("秒")
    for ref in (300, 1000, 3500):
        a1.axhline(ref, color="white", lw=0.3, alpha=0.5)
    fig.tight_layout()
    fig.savefig(CHECK / (path.stem + ".png"), dpi=110)
    plt.close(fig)


if __name__ == "__main__":
    plt.rcParams["font.family"] = ["Hiragino Sans", "Hiragino Maru Gothic Pro", "sans-serif"]
    CHECK.mkdir(exist_ok=True)
    pats = sys.argv[1:]
    rows = []
    for path in sorted(WAV.glob("*.wav")):
        if pats and not any(p in path.name for p in pats):
            continue
        x, sr, info = analyze(path)
        plot(path, x, sr, info)
        rows.append((path.name, info))
    if not pats:
        lines = ["# 確かめ", "", "各 wav の波形とスペクトログラム（対数の周波数軸、白い線は 300 Hz・1 kHz・3.5 kHz）。`gen/check.py` が出す。", "",
                 "| ファイル | 長さ (s) | ピーク (dB) | 実効値 (dB) | 重心 (Hz) | 90% まで (Hz) | 継ぎ目の段差 |", "|---|---|---|---|---|---|---|"]
        for name, i in rows:
            seam = f"{i['seam']:.3f}" if name.endswith("_loop.wav") else "—"
            lines.append(f"| [{name}]({name[:-4]}.png) | {i['dur']:.2f} | {i['peak']:.1f} | {i['rms']:.1f} | {i['centroid']:.0f} | {i['f90']:.0f} | {seam} |")
        (CHECK / "summary.md").write_text("\n".join(lines) + "\n")
        # 聞くためのページ。Finder から開けば再生できる（wav は ../wav/ を参照）
        html = ["<!doctype html><meta charset=utf-8><title>Lodge の音</title>",
                "<style>body{font:14px/1.5 -apple-system,sans-serif;margin:24px;max-width:1100px}h1{font-size:18px}"
                "section{margin:28px 0}h2{font-size:15px;margin:0 0 6px}img{width:100%;max-width:1000px;display:block}"
                "audio{width:420px;vertical-align:middle}small{color:#666}</style>",
                "<h1>Lodge の音 — 聞いて確かめる</h1><p><small>合成の台本は gen/、音は wav/。表の数字は summary.md と同じ。</small></p>"]
        for name, i in rows:
            html.append(f"<section><h2>{name} <small>{i['dur']:.2f} s · peak {i['peak']:.1f} dB · rms {i['rms']:.1f} dB</small></h2>"
                        f"<audio controls preload=none src='../wav/{name}'{' loop' if name.endswith('_loop.wav') else ''}></audio>"
                        f"<img src='{name[:-4]}.png' loading=lazy></section>")
        (CHECK / "listen.html").write_text("\n".join(html) + "\n")
    print(f"{len(rows)} 枚")
