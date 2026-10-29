"""sound/wav/ の各 wav について、波形とスペクトログラムの PNG を sound/check/ に出す。
あわせて summary.md に長さ・ピーク・実効値・重心・継ぎ目の段差を表にする。

使い方: .venv/bin/python gen/check.py [名前の一部...]
"""
import html as htmlesc
import pathlib
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
WAV, CHECK = ROOT / "wav", ROOT / "check"
CONCEPT = ROOT.parent / "design" / "sound-concept.md"


def uses():
    """design/sound-concept.md の「音の一覧」の表から、ファイル名 → [(音, 鳴る条件, 何で変わるか, 添え書き)] を作る。
    使う所は表だけに書き、ここでは読むだけにする（二重に書かない）"""
    out = {}
    if not CONCEPT.exists():
        return out
    text = CONCEPT.read_text()
    m = re.search(r"^## 音の一覧\n(.*?)(?=^## )", text, re.S | re.M)
    if not m:
        return out
    for line in m.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4 or cells[0] in ("音", "") or set(cells[0]) <= set("-"):
            continue
        what, files, when, varies = cells[:4]
        note = re.sub(r"`[^`]*`", "", files).strip()   # （録音） のような添え書き
        for tok in re.findall(r"`([^`]+)`", files):
            r = re.match(r"(.+_)(\d+)\.\.(\d+)\.wav$", tok)
            names = [f"{r.group(1)}{i:0{len(r.group(2))}d}.wav" for i in range(int(r.group(2)), int(r.group(3)) + 1)] if r else [tok]
            for n in names:
                out.setdefault(n, []).append((what, when, varies, note))
    return out


def use_text(entries):
    """使う所を一行に（同じ音を二か所で使えば「／」でつなぐ）"""
    if not entries:
        return "（音の一覧にない。ゲームでは使っていない）"
    parts = []
    for what, when, varies, note in entries:
        t = f"{what}: {when}"
        if varies and varies != "—":
            t += f"（{varies}）"
        if note:
            t += f" {note}"
        parts.append(t)
    return " ／ ".join(parts)


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
        used = uses()
        lines = ["# 確かめ", "", "各 wav の波形とスペクトログラム（対数の周波数軸、白い線は 300 Hz・1 kHz・3.5 kHz）。`gen/check.py` が出す。",
                 "使う所は [音の設計](../../design/sound-concept.md) の「音の一覧」から読んでいる。", "",
                 "| ファイル | 使う所 | 長さ (s) | ピーク (dB) | 実効値 (dB) | 重心 (Hz) | 90% まで (Hz) | 継ぎ目の段差 |", "|---|---|---|---|---|---|---|---|"]
        for name, i in rows:
            seam = f"{i['seam']:.3f}" if name.endswith("_loop.wav") else "—"
            lines.append(f"| [{name}]({name[:-4]}.png) | {use_text(used.get(name)).replace('|', '／')} | {i['dur']:.2f} | {i['peak']:.1f} | {i['rms']:.1f} | {i['centroid']:.0f} | {i['f90']:.0f} | {seam} |")
        (CHECK / "summary.md").write_text("\n".join(lines) + "\n")
        # 聞くためのページ。Finder から開けば再生できる（wav は ../wav/ を参照）
        html = ["<!doctype html><meta charset=utf-8><title>Lodge の音</title>",
                "<style>body{font:14px/1.5 -apple-system,sans-serif;margin:24px;max-width:1100px}h1{font-size:18px}"
                "section{margin:28px 0}h2{font-size:15px;margin:0 0 6px}img{width:100%;max-width:1000px;display:block}"
                "audio{width:420px;vertical-align:middle}small{color:#666}p.use{margin:0 0 6px}p.unused{margin:0 0 6px;color:#999}</style>",
                "<h1>Lodge の音 — 聞いて確かめる</h1><p><small>合成の台本は gen/、音は wav/。表の数字は summary.md と同じ。"
                "「使う所」は design/sound-concept.md の「音の一覧」から。</small></p>"]
        # 聞き比べ: 同じ声（同じ抑揚）を、人の声と素材の声で横に並べる（voice_material.py の候補があるとき）
        mats = [("人の声", "voice_{}_01.wav"), ("紙", "voice_paper_{}_01.wav"), ("フェルト", "voice_felt_{}_01.wav"), ("紙の櫛笛", "voice_kazoo_{}_01.wav")]
        if (WAV / "voice_paper_wa_01.wav").exists():
            html.append("<section><h2>聞き比べ: 素材で喋る声 <small>同じ抑揚を、人の声・紙・フェルト・紙の櫛笛で</small></h2>"
                        "<table style='border-collapse:collapse'><tr><th></th>" + "".join(f"<th style='padding:4px 8px'>{m}</th>" for m, _ in mats) + "</tr>")
            for key, label in [("wa", "ワ〜"), ("un", "ウン"), ("nn", "ンーン"), ("unq", "ウン？"), ("surprise", "びっくり")]:
                cells = "".join(f"<td style='padding:4px 8px'><audio controls preload=none style='width:180px' src='../wav/{f.format(key)}'></audio></td>"
                                for _, f in mats if (WAV / f.format(key)).exists())
                html.append(f"<tr><th style='padding:4px 8px;text-align:left'>{label}</th>{cells}</tr>")
            html.append("</table></section>")
        for name, i in rows:
            u = used.get(name)
            html.append(f"<section><h2>{name} <small>{i['dur']:.2f} s · peak {i['peak']:.1f} dB · rms {i['rms']:.1f} dB</small></h2>"
                        f"<p class={'use' if u else 'unused'}>使う所: {htmlesc.escape(use_text(u))}</p>"
                        f"<audio controls preload=none src='../wav/{name}'{' loop' if name.endswith('_loop.wav') else ''}></audio>"
                        f"<img src='{name[:-4]}.png' loading=lazy></section>")
        (CHECK / "listen.html").write_text("\n".join(html) + "\n")
    print(f"{len(rows)} 枚")
