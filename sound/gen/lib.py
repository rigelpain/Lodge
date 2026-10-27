"""音の合成の共通部品。48 kHz、モノラル、16 bit の wav を sound/wav/ に書く。

外の素材は使わない。ここにあるのはノイズ・フィルタ・包絡・共鳴の部品だけ。
"""
from __future__ import annotations

import pathlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
WAV = pathlib.Path(__file__).resolve().parents[1] / "wav"


def seconds(dur: float) -> np.ndarray:
    return np.arange(int(round(dur * SR))) / SR


def n_of(dur: float) -> int:
    return int(round(dur * SR))


# ---- フィルタ -------------------------------------------------------------

def lp(x, fc, order=4):
    sos = signal.butter(order, fc, btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, fc, order=4):
    sos = signal.butter(order, fc, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bp(x, lo, hi, order=4):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak_eq(x, f0, gain_db, q):
    """RBJ のピーキング EQ"""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(np.array(b) / den[0], np.array(den) / den[0], x)


def resonator(x, f0, r):
    """2 極の共鳴。r は 0.9〜0.9995。狭いほど長く鳴る"""
    w = 2 * np.pi * f0 / SR
    return signal.lfilter([1 - r], [1, -2 * r * np.cos(w), r * r], x)


def moving_resonator(x, f_curve, r):
    """中心周波数が時間で動く 2 極の共鳴（1 サンプルずつ。短い音か、長くても数十秒まで）"""
    out = np.zeros_like(x)
    y1 = y2 = 0.0
    w = 2 * np.pi * np.asarray(f_curve, dtype=np.float64) / SR
    a1 = -2 * r * np.cos(w)
    a2 = r * r
    g = 1 - r
    for i in range(len(x)):
        y = g * x[i] - a1[i] * y1 - a2 * y2
        out[i] = y
        y2, y1 = y1, y
    return out


def modes(n, freqs, decays, amps, rng=None, detune=0.0):
    """減衰する正弦の重ね合わせ（板・器・金属の鳴り）。decays は時定数 (s)"""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        if rng is not None and detune > 0:
            f = f * (1 + rng.uniform(-detune, detune))
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    # 尾を切らない: 最後の 2 割をなだらかに落とす
    k = max(2, n // 5)
    out[-k:] *= ramp(k, "hann_out")
    return out


# ---- 包絡 -----------------------------------------------------------------

def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def ramp(n, kind="hann_in"):
    k = np.linspace(0, 1, n)
    if kind == "hann_in":
        return 0.5 - 0.5 * np.cos(np.pi * k)
    if kind == "hann_out":
        return 0.5 + 0.5 * np.cos(np.pi * k)
    return k


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    if a > 0:
        x[:a] *= ramp(a, "hann_in")
    if b > 0:
        x[-b:] *= ramp(b, "hann_out")
    return x


def ar(n, attack, release, curve=1.0):
    """立ち上がり attack 秒、残り release 秒で落ちる。curve>1 で凹の減衰"""
    a = n_of(attack)
    env = np.ones(n)
    env[:a] = ramp(a, "hann_in")
    r = min(n_of(release), n - a)
    if r > 0:
        env[-r:] = np.linspace(1, 0, r) ** curve
    return env


def slow_random(n, rate_hz, rng, depth=1.0):
    """ゆっくり揺れる乱数（0 中心、だいたい ±depth）。風や火のうねりに"""
    k = max(4, int(n * rate_hz / SR * 2) + 4)
    pts = rng.standard_normal(k)
    x = np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)
    x = lp(x, rate_hz * 1.5, 2)
    s = np.std(x)
    return x / s * depth * 0.5 if s > 0 else x


def place(buf, x, at):
    """x を buf の at 秒の所に足す。はみ出た分は捨てる"""
    i = n_of(at)
    if i >= len(buf):
        return
    m = min(len(x), len(buf) - i)
    buf[i:i + m] += x[:m]


def place_wrap(buf, x, at):
    """はみ出た分を頭に回す（継ぎ目のないループ用）"""
    i = n_of(at) % len(buf)
    idx = (i + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x)


# ---- 仕上げ ---------------------------------------------------------------

def seamless(x, xfade=0.25):
    """末尾を頭に重ねてクロスフェードし、継ぎ目をなくす。長さは xfade 秒だけ縮む"""
    k = n_of(xfade)
    y = x[:-k].copy()
    y[:k] = x[:k] * ramp(k, "hann_in") + x[-k:] * ramp(k, "hann_out")
    return y


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def db(v):
    return 10 ** (v / 20)


def normalize(x, peak_db=-3.0):
    p = np.max(np.abs(x))
    return x / p * db(peak_db) if p > 0 else x


def rms_db(x):
    r = np.sqrt(np.mean(x * x))
    return 20 * np.log10(r) if r > 0 else -120.0


def write(name, x, peak_db=-3.0):
    WAV.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    if peak_db is not None:
        x = normalize(x, peak_db)
    x = np.clip(x, -1, 1)
    wavfile.write(WAV / name, SR, (x * 32767).astype(np.int16))
    print(f"{name:28s} {len(x) / SR:6.2f} s  peak {20 * np.log10(np.max(np.abs(x)) + 1e-12):6.1f} dB  rms {rms_db(x):6.1f} dB")
    return x
