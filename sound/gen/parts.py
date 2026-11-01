"""手芸の世界の小さな部品の音（売り台・ミシン・厨房で共有する）。木・真鍮・紙・布・湯気・泡。

lib.py の部品（フィルタ・包絡・共鳴）を組み合わせるだけ。外の素材は使わない。
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, modes, n_of, place, ramp


def norm(x):
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


def mix(*xs):
    """長さの違う音を、頭をそろえて足す"""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def _ring(exc, f, tau):
    """雑音で打つ 2 極の共鳴。tau 秒で 1/e に落ちる（正弦の重ねより、木や布の鈍い鳴りになる）"""
    from lib import resonator
    r = float(np.exp(-1.0 / (tau * SR)))
    return resonator(exc, f, r)


def wood(rng, f0=900.0, dur=0.09, dry=1.0):
    """木の小さな部品が当たる「コト」。f0 で大きさ（低いほど大きな板）。dry を上げると鳴りが短い。
    分音は木の板の不ぞろいな並び（1・1.47・2.09・2.56・3.13 倍）で、短く鈍く鳴らす（長く澄むと木琴やカリンバに聞こえる）"""
    n = n_of(dur)
    exc = rng.standard_normal(n) * exp_decay(n, 0.0004)
    f = f0 * rng.uniform(0.95, 1.05)
    x = np.zeros(n)
    for ratio, tau, a in [(1.0, 0.009, 1.0), (1.47, 0.006, 0.7), (2.09, 0.004, 0.5), (2.56, 0.003, 0.35), (3.13, 0.0025, 0.25)]:
        x += norm(_ring(exc, min(f * ratio * rng.uniform(0.97, 1.03), 18000), tau / dry)) * a
    c = bp(rng.standard_normal(n), min(f0 * 1.5, 9000), min(f0 * 8, 18000), 2) * exp_decay(n, 0.0008)
    return norm(norm(x) + norm(c) * 0.35)


def thud(rng, f0=110.0, dur=0.18):
    """重い木（台・床）に物が置かれる「ごとん」。低い板の鈍い鳴りと、こもった当たり（立ち上がりは少しやわらかく）"""
    n = n_of(dur)
    exc = lp(rng.standard_normal(n), 1200, 2) * ar(n, 0.002, 0.012, 2.0)
    f = f0 * rng.uniform(0.95, 1.05)
    x = np.zeros(n)
    for ratio, tau, a in [(1.0, 0.04, 1.0), (1.55, 0.025, 0.6), (2.3, 0.015, 0.4), (3.4, 0.008, 0.25)]:
        x += norm(_ring(exc, f * ratio, tau)) * a
    return norm(x + norm(lp(exc, 700, 2)) * 0.25)


def brass(rng, f0=3200.0, dur=0.12, ring=1.0):
    """真鍮の小物（ピン・つめ・留め金）の「チッ」。ring で鳴りの長さ"""
    n = n_of(dur)
    m = modes(n, np.array([1.0, 1.59, 2.31, 3.1]) * f0 * rng.uniform(0.97, 1.03),
              np.array([0.03, 0.02, 0.012, 0.008]) * ring, [1.0, 0.6, 0.35, 0.2], rng, 0.01)
    c = hp(rng.standard_normal(n), 4000) * exp_decay(n, 0.0006)
    return norm(m * 0.7 + c * 0.4)


def bell(rng, f0=1800.0, dur=1.6, decay=0.55, bright=1.0):
    """真鍮の卓上の鐘の「チン」。小さな椀の鐘の分音（1・2.76・5.4・8.9 倍）と、打った瞬間の当たり。
    高い分音ほど早く消え、二つにわずかにずれた分音がうなる"""
    n = n_of(dur)
    ratios = np.array([1.0, 1.003, 2.76, 2.765, 5.40, 8.93])
    decays = np.array([1.0, 0.9, 0.45, 0.4, 0.18, 0.08]) * decay
    amps = np.array([1.0, 0.55, 0.5 * bright, 0.3 * bright, 0.22 * bright, 0.1 * bright])
    m = modes(n, ratios * f0, decays, amps, rng)
    strike = bp(rng.standard_normal(n), 2500, 9000, 2) * exp_decay(n, 0.0008)
    return norm(lp(m, 9000, 2) + strike * 0.25)


def suzu(rng, f0=2600.0, dur=0.7, shakes=3):
    """鈴（中に玉の入った丸い鈴）。玉が殻を打つ小さな当たりが何度か続き、そのたびに殻が鳴る"""
    out = np.zeros(n_of(dur))
    t = 0.0
    for k in range(shakes * 3):
        n = n_of(0.35)
        f = f0 * rng.uniform(0.985, 1.015)
        m = modes(n, np.array([1.0, 1.46, 2.12, 2.98]) * f, [0.12, 0.07, 0.04, 0.025], [1.0, 0.6, 0.4, 0.2], rng, 0.01)
        tick = hp(rng.standard_normal(n), 5000) * exp_decay(n, 0.0005)
        place(out, (m * 0.6 + tick * 0.3) * rng.uniform(0.3, 1.0) * (0.85 ** k), t)
        t += rng.uniform(0.025, 0.06) if k % 3 else rng.uniform(0.07, 0.12)
    return norm(fade(out, 0.0005, 0.08))


def paper(rng, dur=0.45, density=180.0, lo=900.0, hi=7000.0, gestures=2, crisp=1.0):
    """紙のかさかさ。折る手の動き（gestures 回）ごとに、細かい折れの「ぱり」が群がって起きる。
    crisp を下げると柔らかい紙（薄葉紙）、上げると硬い紙（クラフト紙）"""
    n = n_of(dur)
    out = np.zeros(n)
    centers = np.sort(rng.uniform(0.05, 0.85, gestures)) * dur
    width = dur / (gestures * 2.2)
    count = int(density * dur)
    for _ in range(count):
        c = centers[rng.integers(0, gestures)]
        at = c + rng.normal(0, width)
        if not 0 <= at < dur - 0.01:
            continue
        k = n_of(rng.uniform(0.0008, 0.004))
        f = rng.uniform(lo, hi)
        g = bp(rng.standard_normal(k + 64), f * 0.7, min(f * 1.4, 20000), 2)[64:]
        g *= exp_decay(k, k / SR / (2.0 + crisp)) * rng.pareto(2.5) * 0.4
        place(out, g, at)
    env = np.zeros(n)
    t = np.arange(n) / SR
    for c in centers:
        env += np.exp(-0.5 * ((t - c) / width) ** 2)
    rustle = bp(rng.standard_normal(n), lo * 0.6, hi, 2) * env
    out = out / (np.max(np.abs(out)) + 1e-9) + norm(rustle) * (0.35 / crisp)
    return norm(fade(out, 0.003, 0.03))


def felt_puff(rng, f0=150.0, dur=0.25, air=0.5):
    """フェルトのやわらかい当たり「ぽふ」。立ち上がりをゆるくし（4〜7 ms）、高い音を落とす（太鼓に聞こえないように）"""
    n = n_of(dur)
    exc = lp(rng.standard_normal(n), 900, 2) * ar(n, rng.uniform(0.004, 0.007), 0.03, 2.0)
    body = norm(_ring(exc, f0 * rng.uniform(0.93, 1.07), 0.02)) + 0.4 * norm(_ring(exc, f0 * 1.6, 0.012))
    puff = lp(rng.standard_normal(n), 900, 2) * ar(n, 0.008, dur * 0.6, 2.5)
    return norm(lp(norm(body) + norm(puff) * air, 1800, 2))


def hiss(rng, dur, lo=1800.0, hi=9000.0, attack=0.02, release=None, curve=1.6):
    """湯気の「しゅー」。帯域を通した息のような雑音"""
    n = n_of(dur)
    x = bp(rng.standard_normal(n), lo, hi, 2)
    x *= ar(n, attack, release if release is not None else dur * 0.7, curve)
    return norm(x)


def bubble(rng, f0=600.0, dur=0.06, rise=0.7, amp=1.0):
    """泡がはじける・生まれる「ぽこ」。周波数が上ずる短い正弦（小さな泡ほど高い）"""
    n = n_of(dur)
    t = np.arange(n) / SR
    f = f0 * (1 + rise * t / max(t[-1], 1e-6))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * exp_decay(n, dur / 3.5) * ramp_in(n, 0.0015) * amp


def ramp_in(n, sec):
    k = min(n, n_of(sec))
    e = np.ones(n)
    if k > 0:
        e[:k] = ramp(k, "hann_in")
    return e


def sizzle(rng, dur, rate=900.0, lo=2200.0, hi=11000.0, swell=None):
    """焼ける「じゅー」。細かいはぜ（ポアソンの点）と、薄い湯気の帯。swell は密度の包絡（長さ n の配列）"""
    n = n_of(dur)
    out = np.zeros(n)
    dens = np.ones(n) if swell is None else swell
    count = int(rate * dur)
    at = rng.uniform(0, dur, count * 2)
    keep = rng.uniform(0, 1, len(at)) < np.interp(at, np.arange(n) / SR, dens)
    imp = np.zeros(n)
    idx = (at[keep][:count] * SR).astype(int).clip(0, n - 1)
    np.add.at(imp, idx, np.minimum(rng.pareto(3.0, len(idx)), 1.5) * rng.choice([-1, 1], len(idx)))
    crack = bp(imp, lo, hi, 2)
    bed = bp(rng.standard_normal(n), lo * 1.3, hi, 2) * dens
    out = norm(crack) + norm(bed) * 0.18
    return norm(out)


def ratchet(rng, count=6, start_gap=0.07, end_gap=0.035, f0=3600.0):
    """真鍮のつめ車の「カチカチカチ」。だんだん詰まる"""
    gaps = np.linspace(start_gap, end_gap, count)
    out = np.zeros(n_of(float(np.sum(gaps)) + 0.12))
    t = 0.0
    for k in range(count):
        tick = mix(brass(rng, f0 * rng.uniform(0.95, 1.05), 0.06, 0.4) * 0.7, wood(rng, 1400, 0.05, 1.5) * 0.5)
        place(out, tick * rng.uniform(0.75, 1.0), t)
        t += gaps[k]
    return norm(out)


def creak(rng, dur=0.3, f_start=35.0, f_end=120.0, res=(600.0, 1700.0)):
    """木と木がこすれるきしみ（くっついては滑る）。速まるパルスの列の間をばらつかせ、こすれの雑音を混ぜて板の共鳴に通す。
    間がそろうと電気のうなりに聞こえるので、1 つずつ ±25% ずらす"""
    n = n_of(dur)
    pulses = np.zeros(n)
    t = 0.0
    while t < dur:
        u = t / dur
        f = f_start * (f_end / f_start) ** u
        pulses[min(n - 1, int(t * SR))] = rng.uniform(0.3, 1.0)
        t += rng.uniform(0.75, 1.25) / f
    rub = bp(rng.standard_normal(n), res[0] * 0.6, res[1] * 1.6, 2) * 0.05
    x = norm(_ring(pulses + rub, res[0] * rng.uniform(0.9, 1.1), 0.006)) + 0.6 * norm(_ring(pulses + rub, res[1] * rng.uniform(0.9, 1.1), 0.003))
    return norm(x * ar(n, 0.03, dur * 0.5, 1.5))


def thread_pluck(rng, f0=420.0, dur=0.35, damp=0.55):
    """ぴんと張った糸をはじく「ぴん」（カープラス・ストロング）。damp を上げるとすぐ止む（綿の糸）"""
    n = n_of(dur)
    period = int(SR / f0)
    buf = rng.uniform(-1, 1, period) * np.hanning(period)
    out = np.zeros(n)
    k = 1.0 - 0.02 * damp
    for i in range(n):
        j = i % period
        nxt = buf[(j + 1) % period]
        out[i] = buf[j]
        buf[j] = k * 0.5 * (buf[j] + nxt)
    return norm(lp(out, 5000, 2) * ar(n, 0.001, dur * 0.8, 1.5))


def slide(rng, dur=0.3, lo=300.0, hi=2500.0, rough=1.0):
    """木の引き出し・板がすべる「すー」。こすれの雑音に、木目のでこぼこのゆらぎ"""
    n = n_of(dur)
    x = bp(rng.standard_normal(n), lo, hi, 2)
    grain = 1 + 0.6 * rough * np.sin(2 * np.pi * np.cumsum(rng.uniform(20, 45, n)) / SR)
    return norm(x * grain * ar(n, dur * 0.15, dur * 0.4, 1.3))
