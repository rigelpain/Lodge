"""売り台で買ったときの音（2026-11-01 代表「購入音…をしっかり作ってほしい」）。
画面の決定音にはしない（design/sound-concept.md の決まり 1）。番台のお皿とレジ、売り台の箱で鳴る音を、3 つの層に分けて作り、
ゲーム（game/audio.gd の purchase）で重ねる。払う数でボタンの粒が増えるので、毎回少しずつ違って聞こえる。

1. 払う  お皿に払いが落ちる
   pay_button_01..06    ボタンが朱塗りの木のお皿に落ちて、2〜3 回はねて止まる（01〜03 木・04〜05 真鍮・06 白蝶貝）
   pay_snowball_01..03  羊毛の雪玉をお皿に置く「ぽふ」（雪だるまの店。お代は雪玉。ぬいぐるみの録音）
2. レジ  店ごとに違う
   till_patch_01..03    おじいさんのレジ: 古い手回しのレジの録音（CC0。引き出しが開いて鐘が「チン」）。合成の木の打ち鍵を頭に重ねる
   till_snow_01..03     雪だるまの藍のレジ: 同じ録音を 1.22 倍の速さ（小さく高いレジ）にし、少し小さく
   till_pal_01..03      2 階の売り台: 木の小箱のふたが「ぱこ」と開き、小さな鈴が鳴る（どちらも録音）
3. 包む  品物を包んで渡す（紙は合成だと太鼓のように聞こえたので録音。earshot で「スネア」z +4 前後）
   wrap_paper_01..03    型紙と布を包装紙で包み（録音）、台に「とん」と置く（合成）
   wrap_bag_01..03      ペレットを紙袋に入れ、口を折る（録音）
   wrap_tissue_01..03   小物を薄い紙でくるむ（録音を高い方に寄せて小さく）
録音の出どころは sound/SOURCES.md、切る所は gen/rec.py の PICKS。

聞き比べ用（ゲームでは鳴らさない。sound/check/craft/ に書く）:
   buy_<店>_demo_1..3   ゲームと同じ間で 3 つの層を重ねたもの
   cand_buy_<店>_synth_1  レジと包むを合成だけで作った案（録音を使わない。払いの雪玉だけは録音）
   cand_till_soroban    おじいさんのレジの代わりの案: そろばんの珠を「パチパチ」と弾く
"""
import pathlib
import sys

import numpy as np

from lib import SR, fade, lp, n_of, place, write
import rec
from parts import bell, brass, mix, felt_puff, norm, paper, slide, suzu, thud, wood

CHECK = pathlib.Path(__file__).resolve().parents[1] / "check" / "craft"


def pay_button(rng, material):
    """ボタンがお皿に落ち、はずみながら間を詰めて止まる（跳ねるたびに小さく、高さもわずかに上がる）"""
    out = np.zeros(n_of(0.42))
    bounces = rng.integers(2, 4)
    t, gap, amp = 0.0, rng.uniform(0.07, 0.1), 1.0
    tray = rng.uniform(380, 460)   # 朱塗りのお皿（木）の低い鳴り
    for k in range(bounces + 1):
        if material == "wood":
            hit = wood(rng, rng.uniform(1900, 2600) * (1 + 0.04 * k), 0.07, 1.4)
        elif material == "brass":
            hit = mix(brass(rng, rng.uniform(3400, 4300), 0.12, 0.7) * 0.55, wood(rng, 2200, 0.05, 1.5) * 0.6)
        else:   # 白蝶貝: 薄く硬い殻の、高く短い鳴り
            hit = mix(brass(rng, rng.uniform(5200, 6200), 0.1, 0.8) * 0.7, wood(rng, 3000, 0.04, 2.0) * 0.4)
        place(out, hit * amp, t)
        if k == 0:
            place(out, wood(rng, tray, 0.12, 0.8) * 0.35, t)
        t += gap
        gap *= rng.uniform(0.55, 0.7)
        amp *= rng.uniform(0.4, 0.6)
    # 最後に、平らに倒れて回る「ちりり」
    for j in range(rng.integers(3, 6)):
        place(out, wood(rng, 2600, 0.03, 2.0) * 0.06 * (0.8 ** j), t + 0.012 * j)
    return fade(out, 0.0003, 0.05)


def pay_snowball(rng, i=0):
    """羊毛の雪玉をお皿に置く「ぽふ」（ぬいぐるみが落ちる録音）"""
    return fade(rec.pick("plop", i, low=120, high=4500), 0.0005, 0.05)


def till_patch(rng):
    """木のレジ: 打ち鍵 2 つ → 引き出しのつめが外れて「がたっ」と飛び出す → 鐘の「チン」"""
    out = np.zeros(n_of(1.6))
    place(out, wood(rng, rng.uniform(1000, 1150), 0.08) * 0.55, 0.0)
    place(out, wood(rng, rng.uniform(850, 980), 0.08) * 0.6, rng.uniform(0.1, 0.13))
    t = rng.uniform(0.23, 0.27)
    place(out, brass(rng, 2900, 0.05, 0.5) * 0.35, t)                        # つめが外れる
    place(out, slide(rng, 0.16, 250, 1800) * 0.4, t + 0.005)                 # 引き出しが走る
    place(out, thud(rng, rng.uniform(150, 175), 0.2) * 0.75, t + 0.16)       # 止まりに当たる
    place(out, bell(rng, rng.uniform(1650, 1820), 1.3, 0.5) * 0.65, t + 0.02)
    return fade(out, 0.0005, 0.25)


def till_patch_rec(i, rng):
    """録音のレジ。頭に合成の木の打ち鍵を 2 つ（録音の前に、店番が鍵を打つ）"""
    r = rec.pick("till_patch", i, low=120, high=10000)
    out = np.zeros(n_of(0.24) + len(r))
    place(out, wood(rng, rng.uniform(1000, 1150), 0.08) * 0.35, 0.0)
    place(out, wood(rng, rng.uniform(850, 980), 0.08) * 0.4, rng.uniform(0.1, 0.13))
    place(out, r, 0.24)
    return fade(out, 0.0005, 0.12)


def till_snow_rec(i, rng):
    r = rec.speed(rec.pick("till_snow", i, low=160, high=9000), 1.22)
    out = np.zeros(n_of(0.13) + len(r))
    place(out, wood(rng, rng.uniform(1250, 1400), 0.07) * 0.35, 0.0)
    place(out, r, 0.13)
    return fade(out, 0.0005, 0.12)


def wrap_paper_rec(i, rng):
    r = rec.pick("wrap_paper", i, low=200, high=11000)
    out = np.zeros(len(r) + n_of(0.2))
    place(out, r * 0.9, 0.0)
    place(out, thud(rng, rng.uniform(230, 270), 0.12) * 0.4, len(r) / SR - 0.02)   # 台に「とん」
    return fade(out, 0.003, 0.06)


def wrap_bag_rec(i, rng):
    return fade(rec.pick("wrap_bag", i, low=150, high=10000), 0.003, 0.06)


def wrap_tissue_rec(i, rng):
    return fade(rec.pick("wrap_tissue", i, low=900, high=12000), 0.004, 0.06)


def till_snow(rng):
    out = np.zeros(n_of(1.2))
    place(out, wood(rng, rng.uniform(1250, 1400), 0.07) * 0.5, 0.0)
    t = rng.uniform(0.12, 0.15)
    place(out, brass(rng, 3300, 0.04, 0.5) * 0.3, t)
    place(out, slide(rng, 0.1, 350, 2400) * 0.3, t + 0.004)
    place(out, thud(rng, rng.uniform(210, 240), 0.14) * 0.5, t + 0.1)
    place(out, bell(rng, rng.uniform(2450, 2650), 1.0, 0.38, 0.8) * 0.55, t + 0.015)
    return fade(out, 0.0005, 0.2)


def till_pal(rng, i=0):
    """木の小箱のふたが開き（録音）、小さな鈴が鳴る（日本の小さな鈴の録音）"""
    out = np.zeros(n_of(1.3))
    place(out, rec.pick("box", i, low=150) * 0.55, 0.0)
    place(out, rec.pick("bell", i, low=500) * 0.5, rng.uniform(0.08, 0.12))
    return fade(out, 0.0005, 0.15)


def till_pal_synth(rng):
    """合成だけの案: 木の小箱と鈴"""
    out = np.zeros(n_of(1.0))
    place(out, wood(rng, rng.uniform(650, 760), 0.1) * 0.5, 0.0)
    place(out, wood(rng, rng.uniform(1150, 1300), 0.08) * 0.35, rng.uniform(0.07, 0.09))
    place(out, suzu(rng, rng.uniform(2600, 3000), 0.75, int(rng.integers(2, 4))) * 0.45, rng.uniform(0.04, 0.07))
    return fade(out, 0.0005, 0.15)


def wrap_paper(rng):
    out = np.zeros(n_of(0.85))
    place(out, paper(rng, 0.62, 260, 700, 6500, 3, 1.6), 0.0)
    place(out, thud(rng, rng.uniform(230, 270), 0.12) * 0.45, rng.uniform(0.64, 0.68))   # 台に「とん」
    return fade(out, 0.003, 0.06)


def wrap_bag(rng):
    out = np.zeros(n_of(0.75))
    n = n_of(0.12)
    air = lp(rng.standard_normal(n), 900, 2) * np.hanning(n)
    place(out, norm(air) * 0.35, 0.0)                                           # 袋の口が「ぱふ」と開く
    place(out, felt_puff(rng, rng.uniform(260, 320), 0.15, 0.3) * 0.4, 0.12)   # ペレットが袋の底に落ちる
    place(out, paper(rng, 0.45, 200, 600, 5500, 2, 1.2) * 0.9, 0.22)           # 口を 2 回折る
    return fade(out, 0.003, 0.06)


def wrap_tissue(rng):
    return fade(paper(rng, 0.55, 220, 1500, 9500, 3, 0.5) * 0.8, 0.005, 0.08)


def soroban(rng):
    """そろばんの珠を弾く「パチ、パチパチ」。硬い木の珠が軸の上で当たる"""
    out = np.zeros(n_of(0.7))
    t = 0.0
    for k in range(int(rng.integers(4, 7))):
        place(out, wood(rng, rng.uniform(2300, 2900), 0.05, 1.8) * rng.uniform(0.6, 1.0), t)
        t += rng.choice([0.06, 0.11, 0.16])
    place(out, wood(rng, 600, 0.12, 0.8) * 0.4, t)   # 最後に枠を「とん」
    return fade(out, 0.0003, 0.06)


# ---- 聞き比べ: ゲームと同じ間で重ねる（game/audio.gd の purchase と同じ数） --------------------------

PAY_GAP = 0.075   # 払いの粒の間 (s)
TILL_AFTER = 0.12  # 最後の払いからレジまで
WRAP_AFTER = 0.55  # レジから包むまで


def demo(rng, pays, till, wrap):
    out = np.zeros(n_of(3.0))
    t = 0.0
    for p in pays:
        place(out, p * 0.5, t)
        t += PAY_GAP * rng.uniform(0.8, 1.25)
    t += TILL_AFTER
    place(out, till * 0.8, t)
    place(out, wrap * 0.55, t + WRAP_AFTER)
    k = np.max(np.nonzero(np.abs(out) > 1e-4)[0]) + n_of(0.05)
    return fade(out[:k], 0.0, 0.05)


def write_check(name, x, peak=-3.0):
    import lib
    keep = lib.WAV
    lib.WAV = CHECK
    try:
        write(name, x, peak)
    finally:
        lib.WAV = keep


if __name__ == "__main__":
    mats = ["wood", "wood", "wood", "brass", "brass", "pearl"]
    buttons = []
    for i, m in enumerate(mats):
        buttons.append(write(f"pay_button_{i + 1:02d}.wav", pay_button(np.random.default_rng(3100 + i), m), -4))
    balls = [write(f"pay_snowball_{i + 1:02d}.wav", pay_snowball(np.random.default_rng(3110 + i), i), -5) for i in range(3)]
    tills = {
        "patch": [write(f"till_patch_{i + 1:02d}.wav", till_patch_rec(i, np.random.default_rng(3120 + i)), -3) for i in range(3)],
        "snow": [write(f"till_snow_{i + 1:02d}.wav", till_snow_rec(i, np.random.default_rng(3130 + i)), -4) for i in range(3)],
        "pal": [write(f"till_pal_{i + 1:02d}.wav", till_pal(np.random.default_rng(3140 + i), i), -3) for i in range(3)],
    }
    wraps = {
        "patch": [write(f"wrap_paper_{i + 1:02d}.wav", wrap_paper_rec(i, np.random.default_rng(3150 + i)), -6) for i in range(3)],
        "snow": [write(f"wrap_bag_{i + 1:02d}.wav", wrap_bag_rec(i, np.random.default_rng(3160 + i)), -6) for i in range(3)],
        "pal": [write(f"wrap_tissue_{i + 1:02d}.wav", wrap_tissue_rec(i, np.random.default_rng(3170 + i)), -8) for i in range(3)],
    }
    synth_till = {"patch": till_patch, "snow": till_snow, "pal": till_pal_synth}
    synth_wrap = {"patch": wrap_paper, "snow": wrap_bag, "pal": wrap_tissue}
    if "--no-demo" not in sys.argv:
        rng = np.random.default_rng(3190)
        for k in range(3):
            # 店ごとの払い: おじいさんは木・真鍮のボタンを数枚、雪だるまは雪玉 1〜2 つ、2 階は木のボタンを少し
            pays = {
                "patch": [buttons[j] for j in rng.choice(6, 2 + k * 2, p=[0.25, 0.25, 0.2, 0.12, 0.12, 0.06])],
                "snow": [balls[j] for j in rng.choice(3, 1 + k % 2, replace=False)],
                "pal": [buttons[j] for j in rng.choice(4, 1 + k)],
            }
            for shop in ["patch", "snow", "pal"]:
                write_check(f"buy_{shop}_demo_{k + 1}.wav", demo(rng, pays[shop], tills[shop][k], wraps[shop][k]), -3)
        for shop in ["patch", "snow", "pal"]:   # 録音を使わない案
            r2 = np.random.default_rng(3180)
            t = synth_till[shop](r2)
            pays = [buttons[0], buttons[3]] if shop != "snow" else [balls[0]]
            write_check(f"cand_buy_{shop}_synth_1.wav", demo(r2, pays, t, synth_wrap[shop](r2)), -3)
        for k in range(2):
            s = soroban(np.random.default_rng(3195 + k))
            write_check(f"cand_till_soroban_{k + 1}.wav", s, -3)
            pays = [buttons[j] for j in rng.choice(6, 3)]
            write_check(f"cand_buy_patch_soroban_{k + 1}.wav", demo(rng, pays, norm(s), wraps["patch"][k]), -3)
