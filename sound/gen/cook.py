"""雪だるまの厨房で、ペレットから料理を作る音（2026-11-01 代表「食べ物の調理音をしっかり作ってほしい」）。
装置は洗濯の道具から形を借りた巨大な手芸の機械（design/snowman-food/README.md）。電子音は使わない。
装置ごとに 入れる（in）→ 動いている（loop）→ できた（done）の 3 つ。ゲームでは game/audio.gd の cook(装置, 段, 所) で鳴らす。

木の当たり・きしみ・ぬいぐるみの「ぽふ」・焼ける音・湯気・沸く湯・注ぐ音は録音（CC0。出どころは sound/SOURCES.md、切る所は gen/rec.py）。
つめ車・真鍮の小物・泡の「ぽこ」・ホースの「ごぼ」・ループの組み立ては合成。

アイロン台 iron（挟んで焼く）
  cook_iron_in_01..02    フェルトのペレットを当て布に置く「ぽふ」と、木の取っ手の大きなアイロンを下ろす「ごとん」（真鍮の底がかすかに鳴る）
  cook_iron_loop         焼ける「じゅー」と、当て布の湯気の「しゅー」がゆっくり寄せては返す
  cook_iron_done_01..02  アイロンを持ち上げる「かこ」と、こもっていた湯気が「しゅわっ」、焼けた生地が当て布から「ぺり」とはがれる
プレス機 press（押して形に）
  cook_press_in_01..02   真鍮のつめ車のレバーを引き下ろす「カチカチカチ」と、木の枠のきしみ
  cook_press_loop        押さえ込んだ板の低いうなりと、すき間から細く漏れる湯気
  cook_press_done_01..02 たまった湯気が「ぷしゅーっ」と抜け、レバーがばねで戻って「がちゃん」
乾燥機 dryer（回して茹でる・揚げる）
  cook_dryer_in_01..02   丸い窓の扉を開けて入れ、真鍮の留め金を「かちゃ」、扉を「ばたん」
  cook_dryer_loop        木の胴が回るうなりに、中で具が「ころん」と転がり、湯が「ちゃぷ」と揺れ、泡が「ふつふつ」（1 周 1.2 秒）
  cook_dryer_done_01..02 留め金を外して扉が開き、湯気が「ふわっ」、具が受け皿へ「ころん」
飲み物のスチーマー drink
  cook_drink_in_01..02   ペレットがタンクの水に落ちる「ぽちゃん」と、泡がのぼる「こぽこぽ」
  cook_drink_loop        タンクの中で泡が立ち、毛糸のホースを湯が「ごぼ、ごぼ」とのぼる
  cook_drink_done_01..02 頭から綿の湯気が「ぷしゅっ」と出て、カップに「とくとくとく」と注がれ、受け皿に「かちん」
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, lp, n_of, place, place_wrap, seamless, slow_random, softclip, write
import rec
from parts import brass, bubble, creak, hiss, norm, paper, ratchet, wood


def chain(parts, xf=0.25):
    """録音の切れ端を、重ねてなめらかにつなぐ"""
    k = n_of(xf)
    out = parts[0].copy()
    for x in parts[1:]:
        out[-k:] = out[-k:] * np.linspace(1, 0, k) + x[:k] * np.linspace(0, 1, k)
        out = np.concatenate([out, x[k:]])
    return out


def fit(x, n):
    """長さ n に（足りなければ繰り返す）"""
    return np.resize(x, n)


def loop_bubbles(out, rng, dur, rate, f_lo, f_hi, amp, rise=0.7):
    for at in rng.uniform(0, dur, int(rate * dur)):
        b = bubble(rng, rng.uniform(f_lo, f_hi), rng.uniform(0.03, 0.08), rise, rng.uniform(0.3, 1.0) * amp)
        place_wrap(out, b, at)


# ---- アイロン台 ---------------------------------------------------------------

def iron_in(rng):
    out = np.zeros(n_of(0.8))
    place(out, rec.pick("plop", int(rng.integers(0, 3)), low=120, high=5000) * 0.4, 0.0)   # ペレットを置く（録音）
    place(out, rec.speed(rec.pick("lid", 0, low=60), 0.75) * 0.85, 0.22)                     # アイロンを下ろす（木のふたの録音を低く）
    place(out, brass(rng, rng.uniform(1900, 2200), 0.4, 3.0) * 0.06, 0.222)                  # 真鍮の底
    burst = rec.pick("sizzle", int(rng.integers(0, 3)), low=600)[:n_of(0.45)]
    place(out, burst * ar(len(burst), 0.03, 0.4, 1.5) * 0.5, 0.26)                          # 当たってすぐ焼ける（録音）
    return fade(out, 0.0005, 0.06)


def iron_loop(rng):
    dur = 6.0 + 0.4
    n = n_of(dur)
    swell = 0.55 + 0.45 * (0.5 + 0.5 * slow_random(n, 0.6, rng))   # 寄せては返す
    s = fit(chain([rec.pick("sizzle", i, low=500, fin=0.2, fout=0.2) for i in range(3)], 0.3), n) * swell   # 焼ける（録音）
    steam = bp(rng.standard_normal(n), 1500, 7000, 2) * (0.5 + 0.5 * slow_random(n, 0.4, rng)) ** 2
    out = norm(s) * 0.8 + norm(steam) * 0.2
    loop_bubbles(out, rng, dur, 3.0, 700, 1600, 0.12, 1.2)   # 生地の中の水がときどき「ぷつ」
    return seamless(softclip(norm(out) * 3.0, 1.0), 0.4)   # はぜの尖りを丸め、ならした大きさをほかのループにそろえる


def iron_done(rng):
    out = np.zeros(n_of(1.2))
    place(out, rec.pick("box", 2, low=200) * 0.4, 0.0)                              # 取っ手を握って持ち上げる（録音）
    h = rec.pick("iron_hiss", int(rng.integers(0, 2)), low=300, fout=0.15)     # 湯気が「しゅわっ」（スチームアイロンの録音）
    place(out, h * ar(len(h), 0.01, len(h) / SR * 0.7, 1.6) * 0.75, 0.03)
    place(out, paper(rng, 0.3, 160, 900, 6000, 1, 1.4) * 0.35, 0.45)              # 当て布から「ぺり」
    place(out, rec.pick("plop", 2, low=120, high=5000) * 0.3, 0.8)                  # 焼けた生地を置く（録音）
    return fade(out, 0.0005, 0.08)


# ---- プレス機 -----------------------------------------------------------------

def press_in(rng):
    out = np.zeros(n_of(1.0))
    place(out, ratchet(rng, int(rng.integers(5, 8)), 0.075, 0.04, rng.uniform(3200, 3800)) * 0.5, 0.0)
    cr = rec.pick("door_creak", int(rng.integers(0, 2)), low=150)[:n_of(0.5)]
    place(out, cr * ar(len(cr), 0.05, 0.25, 1.5) * 0.45, 0.04)                           # 木の枠のきしみ（録音）
    place(out, rec.speed(rec.pick("lid", 1, low=60), 0.8) * 0.85, 0.5)                    # 板が生地に当たる（録音）
    return fade(out, 0.0005, 0.08)


def press_loop(rng):
    dur = 4.0 + 0.4
    n = n_of(dur)
    t = np.arange(n) / SR
    groan = lp(bp(rng.standard_normal(n), 60, 260, 2), 400, 2) * (0.7 + 0.3 * slow_random(n, 0.5, rng))
    leak = bp(rng.standard_normal(n), 2500, 8000, 2) * (0.4 + 0.6 * (0.5 + 0.5 * slow_random(n, 1.2, rng)))
    out = norm(groan) * 0.5 + norm(leak) * 0.35 + 0.0 * t
    for at in rng.uniform(0, dur, 4):                                                # 枠がときどき「きっ」
        place_wrap(out, creak(rng, 0.15, 50, 90, (500, 1400)) * 0.15, at)
    loop_bubbles(out, rng, dur, 2.0, 500, 1100, 0.1, 1.0)
    return seamless(out, 0.4)


def press_done(rng):
    out = np.zeros(n_of(1.4))
    n = n_of(0.08)
    place(out, norm(lp(rng.standard_normal(n), 500, 2) * ar(n, 0.003, 0.07, 2.0)) * 0.55, 0.0)   # 「ぷ」
    h = rec.pick("press_hiss" if rng.uniform() < 0.5 else "iron_hiss", 2, low=250, fout=0.2)[:n_of(0.9)]
    place(out, h * ar(len(h), 0.01, len(h) / SR * 0.8, 1.4) * 0.8, 0.01)                      # 「しゅーっ」（録音）
    place(out, rec.pick("latch", 2, low=150) * 0.4, 0.68)                                          # つめが外れる（録音）
    place(out, rec.pick("clunk", int(rng.integers(0, 2)), low=80) * 0.8, 0.82)                     # レバーが戻って「がちゃん」（録音）
    return fade(out, 0.0005, 0.08)


# ---- 乾燥機 -------------------------------------------------------------------

def dryer_in(rng):
    out = np.zeros(n_of(1.4))
    place(out, rec.pick("latch", 1, low=150) * 0.5, 0.0)                                # 留め金を外す（録音）
    cr = rec.pick("door_creak", 1, low=150)[:n_of(0.4)]
    place(out, cr * ar(len(cr), 0.03, 0.2, 1.5) * 0.35, 0.12)                           # 扉が開く（録音）
    place(out, rec.pick("plop", int(rng.integers(0, 3)), low=120, high=5000) * 0.4, 0.5)   # ペレットを入れる（録音）
    place(out, rec.pick("clunk", int(rng.integers(0, 3)), low=70) * 0.85, 0.72)         # 扉を「ばたん」（録音）
    place(out, brass(rng, rng.uniform(2800, 3100), 0.1, 0.8) * 0.15, 0.82)              # 留め金を「かちゃ」
    return fade(out, 0.0005, 0.08)


def dryer_loop(rng):
    turn = 1.2
    dur = turn * 4 + 0.4
    n = n_of(dur)
    t = np.arange(n) / SR
    rumble = lp(rng.standard_normal(n), 180, 2) * (1 + 0.3 * np.sin(2 * np.pi * t / turn))
    rumble += 0.4 * np.sin(2 * np.pi * 48 * t) * (1 + 0.2 * np.sin(2 * np.pi * t / turn))
    out = norm(rumble) * 0.45
    slosh = bp(rng.standard_normal(n), 300, 2500, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * t / turn + 2.0)) ** 3
    out += norm(slosh) * 0.18
    for k in range(int(dur / turn) + 1):   # 1 周に 1〜2 度、具が上から落ちて「ころん」
        place_wrap(out, rec.pick("plop", k, low=100, high=4000) * 0.3, k * turn + 0.55 + rng.uniform(-0.03, 0.03))   # 具が「ころん」（録音）
        if rng.uniform() < 0.6:
            place_wrap(out, rec.pick("plop", k + 1, low=150, high=4000) * 0.15, k * turn + 0.75)
    loop_bubbles(out, rng, dur, 8.0, 350, 900, 0.1, 0.8)    # 湯が「ふつふつ」
    boil = fit(rec.pick("boil", 0, low=150, high=3000), n)   # 胴の中で沸く湯（録音。こもらせる）
    out = norm(out) + norm(boil) * 0.35
    return seamless(out, 0.4)


def dryer_done(rng):
    out = np.zeros(n_of(1.4))
    place(out, rec.speed(rec.pick("lid", 0, low=50, high=2500), 0.7) * 0.3, 0.0)        # 胴が止まる
    place(out, rec.pick("latch", 0, low=150) * 0.45, 0.3)                              # 留め金（録音）
    cr = rec.pick("door_creak", 0, low=150)[:n_of(0.45)]
    place(out, cr * ar(len(cr), 0.03, 0.25, 1.5) * 0.35, 0.4)                          # 扉が開く（録音）
    place(out, hiss(rng, 0.7, 900, 6000, 0.08, 0.6, 2.0) * 0.3, 0.45)                 # 湯気が「ふわっ」
    place(out, rec.pick("plop", int(rng.integers(0, 3)), low=120, high=5000) * 0.5, 0.9)   # 具が受け皿へ（録音）
    return fade(out, 0.0005, 0.08)


def plop(rng, f0=420.0):
    """水に落ちる「ぽちゃん」: 当たりの雑音と、落ちてできた泡の上ずる音"""
    n = n_of(0.35)
    hit = bp(rng.standard_normal(n), 500, 4000, 2) * exp_decay(n, 0.006)
    t = np.arange(n) / SR
    f = f0 * (1 + 2.2 * (1 - np.exp(-t / 0.02)))
    ring = np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(n, 0.035)
    return norm(norm(hit) * 0.6 + ring)


def drink_in(rng):
    out = np.zeros(n_of(1.1))
    place(out, plop(rng, rng.uniform(380, 460)) * 0.8, 0.0)
    t = 0.2
    for k in range(int(rng.integers(5, 8))):                                         # 泡がのぼる
        place(out, bubble(rng, rng.uniform(700, 1300) * (1 + 0.05 * k), 0.06, 0.8, 0.3), t)
        t += rng.uniform(0.06, 0.12)
    return fade(out, 0.0005, 0.08)


def drink_loop(rng):
    dur = 4.0 + 0.4
    n = n_of(dur)
    out = np.zeros(n)
    loop_bubbles(out, rng, dur, 10.0, 500, 1500, 0.3, 0.9)
    tank = fit(rec.pick("bubble", 0, low=200, high=8000), n)                         # タンクの泡（録音）
    for k in range(int(dur / 0.55)):                                                  # ホースを湯がのぼる「ごぼ」
        at = k * 0.55 + rng.uniform(-0.05, 0.05)
        for j in range(int(rng.integers(2, 4))):
            place_wrap(out, bubble(rng, rng.uniform(140, 220), 0.11, 0.5, 0.9), at + j * 0.06)
    bed = bp(rng.standard_normal(n), 2000, 7000, 2) * (0.6 + 0.4 * slow_random(n, 0.5, rng))
    out = norm(lp(out, 5000, 2)) * 0.7 + norm(tank) * 0.6 + norm(bed) * 0.06
    return seamless(out, 0.4)


def drink_done(rng):
    out = np.zeros(n_of(2.3))
    n = n_of(0.06)
    place(out, norm(lp(rng.standard_normal(n), 700, 2) * ar(n, 0.002, 0.05, 2.0)) * 0.5, 0.0)    # 「ぷ」
    h = rec.pick("iron_hiss", 0, low=300)[:n_of(0.5)]
    place(out, h * ar(len(h), 0.006, 0.45, 2.0) * 0.7, 0.01)                                      # 「しゅっ」（録音）
    pour = rec.pick("pour", int(rng.integers(0, 2)), low=200, fin=0.05, fout=0.15)[:n_of(1.1)]       # カップに注ぐ（録音）
    place(out, pour * ar(len(pour), 0.05, 0.25, 1.0) * 0.6, 0.5)
    t = 0.5 + len(pour) / SR
    place(out, brass(rng, rng.uniform(2300, 2600), 0.25, 2.5) * 0.25, t + 0.15)          # カップを受け皿に「かちん」
    place(out, wood(rng, 1300, 0.06, 1.5) * 0.2, t + 0.151)
    return fade(out, 0.0005, 0.1)


if __name__ == "__main__":
    seed = 4000
    for dev, fin, floop, fdone in [("iron", iron_in, iron_loop, iron_done), ("press", press_in, press_loop, press_done),
                                     ("dryer", dryer_in, dryer_loop, dryer_done), ("drink", drink_in, drink_loop, drink_done)]:
        for i in range(2):
            write(f"cook_{dev}_in_{i + 1:02d}.wav", fin(np.random.default_rng(seed + i)), -4)
        write(f"cook_{dev}_loop.wav", floop(np.random.default_rng(seed + 5)), -10)
        for i in range(2):
            write(f"cook_{dev}_done_{i + 1:02d}.wav", fdone(np.random.default_rng(seed + 10 + i)), -4)
        seed += 100
