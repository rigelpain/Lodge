"""雪だるまの食べ物屋と、厨房の調理（2026-11-01。design/snowman-food/）。どれも合成で、外の素材は使わない。

場にあるものしか鳴らない決まり（design/sound-concept.md）なので、調理の曲は「装置に仕込んだオルゴール」として装置から鳴らす。
装置が動いているあいだだけ、その装置の場所で小さく回る。120 BPM（1 拍 = 0.5 秒 = 人形の 12 コマ／秒で 6 コマ）、4 小節 8 秒でつながる。

cook_music_press_loop   オルゴール + フェルトのどすん（拍ごと）。プレス機
cook_music_iron_loop    オルゴール + 布をこする小さなシャカシャカ（8 分の裏が強い）。アイロン台
cook_music_dryer_loop   オルゴール + 木の玉がころころ転がる（3 連）。乾燥機
cook_music_drink_loop   オルゴール + 泡のぽこぽこ。衣類スチーマー
cook_bell_01..02        雪だるまの手のベル「ちりん」（買ったとき）
cook_pellet_01..03      ペレットが跳ねる・手に収まる「ぽこ」（フェルトの粒）
cook_press_01..03       巨大なプレス機が押す「ぼすっ」（綿を詰めた熱板が合わさる。低く柔らかく、最後に小さく湯気）
cook_sizzle_loop        アイロン台で焼く「ジュー」
cook_fry_loop           乾燥機で揚げる「ぱちぱち」（細かいはぜ）
cook_boil_loop          乾燥機で茹でる「ぐつぐつ」（低い泡）
cook_drum_loop          乾燥機の胴が回る「ごろごろ」
cook_plop_01            スチーマーのタンクにペレットが落ちる「ぽとん」
cook_gurgle_loop        スチーマーのタンクの泡「ごぼごぼ」
cook_puff_01..03        スチーマーの頭から湯気「ぷしゅっ」
cook_done_01..02        できあがり: 装置のタイマーの「チン」（装置から鳴る）
"""
import numpy as np

from lib import (SR, ar, bp, exp_decay, fade, hp, lp, modes, n_of, place, place_wrap, seamless, slow_random, softclip,
                 write)

BPM = 120.0
BEAT = 60.0 / BPM
BARS = 4
LOOP = BEAT * 4 * BARS   # 8 秒


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# ---------------------------------------------------------------- オルゴール
def tine(rng, f0, dur=1.6, vel=1.0):
    """オルゴールの櫛の歯: 澄んだ基音と、少しずれた高い部分音（速く消える）。ピンがはじく小さなカチ"""
    n = n_of(dur)
    out = modes(n, np.array([1.0, 2.0, 5.95, 9.2]) * f0, [0.9, 0.35, 0.08, 0.03], [1.0, 0.22, 0.12, 0.05], rng, 0.002)
    k = n_of(0.004)
    place(out, hp(rng.standard_normal(k), 3000) * exp_decay(k, 0.0008) * 0.06, 0.0)
    return lp(out, 7500) * vel


# 旋律（8 分音符で 1 小節 8 つ。None は休み）と、低い歯の伴奏（拍 1 と 3）。ハ長調の五音音階で、なつかしく
MELODY = [
    [76, 79, 81, 79, 76, 74, 72, 74],
    [76, 79, 84, 81, 79, 76, 74, None],
    [72, 74, 76, 79, 81, 79, 76, 74],
    [76, 74, 72, 74, 72, None, None, None],
]
BASS = [[48, 55], [45, 52], [41, 48], [43, 50]]   # C・Am・F・G の根音と 5 度


def music_box(rng):
    out = np.zeros(n_of(LOOP))
    for b, bar in enumerate(MELODY):
        for i, m in enumerate(bar):
            if m is None:
                continue
            at = (b * 8 + i) * BEAT / 2 + rng.uniform(0, 0.006)
            vel = (0.95 if i % 2 == 0 else 0.75) * rng.uniform(0.92, 1.0)
            place_wrap(out, tine(rng, hz(m), 1.6, vel), at)
        for j, m in enumerate(BASS[b]):
            place_wrap(out, tine(rng, hz(m + 12), 2.2, 0.55), (b * 4 + j * 2) * BEAT + rng.uniform(0, 0.004))
    return out


def felt_thump(rng, f0=70.0, dur=0.35):
    n = n_of(dur)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * f0 * t * (1 - 0.15 * t / dur)) * exp_decay(n, 0.07)
    puff = lp(rng.standard_normal(n), 600, 2) * exp_decay(n, 0.03) * 0.5
    return lp(body + puff, 1200)


def shaker(rng, dur=0.08):
    n = n_of(dur)
    return bp(rng.standard_normal(n), 3000, 9000, 2) * ar(n, 0.012, dur - 0.012, 2.0)


def woodball(rng, f0):
    n = n_of(0.12)
    return modes(n, np.array([1.0, 2.6, 4.1]) * f0, [0.03, 0.015, 0.008], [1.0, 0.4, 0.2], rng)


def bubble(rng, f0, dur=0.07):
    n = n_of(dur)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.8 * t / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(n, dur / 3)


def music(rng, kind):
    box = music_box(rng)
    layer = np.zeros_like(box)
    beats = int(round(LOOP / BEAT))
    if kind == "press":
        for k in range(beats):
            place_wrap(layer, felt_thump(rng) * (1.0 if k % 2 == 0 else 0.6), k * BEAT)
        gain = 0.55
    elif kind == "iron":
        for k in range(beats * 2):
            place_wrap(layer, shaker(rng) * (1.0 if k % 2 else 0.45), k * BEAT / 2 + rng.uniform(0, 0.005))
        gain = 0.18
    elif kind == "dryer":
        for k in range(beats * 3):
            f = 900.0 * (1.0, 1.26, 1.12)[k % 3] * rng.uniform(0.97, 1.03)
            place_wrap(layer, woodball(rng, f) * (1.0 if k % 3 == 0 else 0.6), k * BEAT / 3 + rng.uniform(0, 0.008))
        gain = 0.3
    else:   # drink
        for k in range(beats * 4):
            if rng.uniform() < 0.55:
                place_wrap(layer, bubble(rng, rng.uniform(350, 800)) * rng.uniform(0.5, 1.0), k * BEAT / 4 + rng.uniform(0, 0.02))
        gain = 0.3
    mix = box / (np.max(np.abs(box)) + 1e-9) + layer / (np.max(np.abs(layer)) + 1e-9) * gain
    return mix   # place_wrap で頭と尾がつながっているので、そのまま 8 秒でループする


# ---------------------------------------------------------------- 効果音
def ting(rng, n, f0, decay, partials=(1.0, 2.76, 5.4, 8.9)):
    return modes(n, np.array(partials) * f0, [decay, decay * 0.6, decay * 0.35, decay * 0.2], [1.0, 0.45, 0.25, 0.12], rng)


def bell(rng):
    """雪だるまの手のベル: 小さな真鍮のベルを 2 度振る「ちりりん」"""
    out = np.zeros(n_of(1.4))
    f0 = 2350 * rng.uniform(0.97, 1.03)
    for k, at in enumerate((0.0, 0.11, 0.2)):
        place(out, ting(rng, n_of(1.1), f0 * rng.uniform(0.995, 1.005), 0.35) * (1.0, 0.7, 0.5)[k], at)
        m = n_of(0.006)
        place(out, hp(rng.standard_normal(m), 5000) * exp_decay(m, 0.001) * 0.3, at)
    return fade(lp(out, 9000), 0.0003, 0.3)


def pellet(rng):
    """フェルトの粒が跳ねる・手に収まる: やわらかい「ぽこ」（立ち上がりを丸め、上がる泡のような高さで、打楽器にしない）"""
    n = n_of(0.2)
    t = np.arange(n) / SR
    f0 = rng.uniform(320, 440)
    f = f0 * (1 + 0.9 * t / 0.06).clip(max=1.9)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * ar(n, 0.006, 0.12, 1.5)
    fuzz = lp(rng.standard_normal(n), 1200, 2) * ar(n, 0.004, 0.04, 2.0) * 0.15
    return fade(lp(body + fuzz, 3000), 0.002, 0.05)


def cloth_thud(rng, dur=0.45):
    """綿を詰めた布どうしが合わさる「ぼすっ」: 低い帯域のノイズの塊（音程を持たせない）と、布の空気が抜ける短い「ふっ」"""
    n = n_of(dur)
    t = np.arange(n) / SR
    body = lp(rng.standard_normal(n), 220, 4) * ar(n, 0.03, dur * 0.7, 1.6)
    body += np.sin(2 * np.pi * 48 * t) * ar(n, 0.03, dur * 0.5, 1.6) * 0.5
    air = bp(rng.standard_normal(n), 400, 1500, 2) * ar(n, 0.04, 0.15, 2.0) * 0.12
    return lp(body + air, 1800)


def press(rng):
    """巨大なプレス機が押す: 木の台のきしみ → 綿を詰めた熱板が合わさる「ぼすっ」→ 湯気がしゅう"""
    out = np.zeros(n_of(1.5))
    k = n_of(0.16)
    t = np.arange(k) / SR
    creak = np.sin(2 * np.pi * np.cumsum(220 + 140 * t / t[-1]) / SR) * ar(k, 0.03, 0.12) * 0.12
    creak += bp(rng.standard_normal(k), 400, 1800, 2) * ar(k, 0.03, 0.12) * 0.15
    place(out, creak, 0.0)
    place(out, cloth_thud(rng, 0.5) * 1.0, 0.12)
    h = n_of(0.9)
    hiss = bp(rng.standard_normal(h), 2000, 7000, 2) * ar(h, 0.08, 0.8, 1.5) * 0.35
    place(out, hiss, 0.25)
    return fade(out, 0.0005, 0.15)


def sizzle_loop(rng):
    """アイロンで焼く「ジュー」: 帯域のノイズのうなりと、細かいはぜ"""
    n = n_of(6.0)
    x = bp(rng.standard_normal(n), 2500, 10000, 2) * (1 + 0.4 * slow_random(n, 2.0, rng))
    x = x / np.std(x) * 0.5
    for at in rng.uniform(0, 6.0, 260):
        m = n_of(rng.uniform(0.002, 0.006))
        place_wrap(x, hp(rng.standard_normal(m), 3500) * exp_decay(m, 0.0012) * rng.uniform(0.6, 2.0), at)
    return seamless(x, 0.3)


def fry_loop(rng):
    """揚げる「ぱちぱち」: 油のしゅわしゅわした地に、はっきりしたはぜが散る（雨やラジオの雑音にしない: 地は狭く、はぜは粒を立てる）"""
    n = n_of(6.0)
    x = bp(rng.standard_normal(n), 2500, 8000, 2) * 0.35 * (1 + 0.5 * slow_random(n, 3.0, rng))   # 油のしゅわしゅわ
    for at in rng.uniform(0, 6.0, 1400):
        m = n_of(rng.uniform(0.002, 0.006))
        f0 = rng.uniform(2500, 6000)
        tick = modes(m, [f0, f0 * 1.7], [0.0015, 0.001], [1.0, 0.4], rng) + hp(rng.standard_normal(m), 2500) * 0.6
        amp = rng.uniform(0.3, 1.0) * (2.2 if rng.uniform() < 0.08 else 1.0)
        place_wrap(x, tick * exp_decay(m, 0.0015) * amp, at)
    return seamless(x, 0.3)


def boil_loop(rng):
    """茹でる「ぐつぐつ」: 低い泡がぽこぽこ続く"""
    n = n_of(6.0)
    x = lp(rng.standard_normal(n), 500, 2) * 0.08
    for at in rng.uniform(0, 6.0, 90):
        place_wrap(x, bubble(rng, rng.uniform(120, 260), rng.uniform(0.06, 0.12)) * rng.uniform(0.3, 1.0), at)
    return seamless(x, 0.3)


def drum_loop(rng):
    """乾燥機の胴が回る「ごろごろ」: 低いうなりと、胴の中で布の粒が転がる柔らかい当たり（1 回りに 2 回）"""
    n = n_of(6.0)
    t = np.arange(n) / SR
    hum = np.sin(2 * np.pi * 55 * t) * 0.25 + lp(rng.standard_normal(n), 220, 2) * 0.4
    hum *= 1 + 0.25 * np.sin(2 * np.pi * 1.0 * t)
    for k in range(12):
        place_wrap(hum, felt_thump(rng, rng.uniform(90, 120), 0.2) * 0.6, k * 0.5 + rng.uniform(0, 0.04))
    return seamless(hum, 0.3)


def plop(rng):
    """タンクに粒が落ちる「ぽとん」"""
    out = np.zeros(n_of(0.6))
    place(out, bubble(rng, 300, 0.12) * 1.0, 0.0)
    place(out, bubble(rng, 520, 0.08) * 0.5, 0.05)
    m = n_of(0.01)
    place(out, lp(rng.standard_normal(m), 3000) * exp_decay(m, 0.002) * 0.3, 0.0)
    return fade(out, 0.0003, 0.1)


def gurgle_loop(rng):
    """タンクの泡「ごぼごぼ」: 低い泡が連なって、ときどき固まって上がる"""
    n = n_of(6.0)
    x = lp(rng.standard_normal(n), 400, 2) * 0.06
    at = 0.0
    while at < 6.0:
        for j in range(rng.integers(2, 6)):
            place_wrap(x, bubble(rng, rng.uniform(150, 420), rng.uniform(0.05, 0.1)) * rng.uniform(0.4, 1.0), at + j * rng.uniform(0.04, 0.08))
        at += rng.uniform(0.25, 0.55)
    return seamless(x, 0.3)


def puff(rng):
    """湯気が「ぷしゅっ」: 弁が開いて息が抜ける。立ち上がりは 20 ms ほど、高さが下がりながら細る（打楽器の頭にしない）"""
    n = n_of(0.7)
    t = np.arange(n) / SR
    env = ar(n, 0.02, 0.6, 2.2)
    src = rng.standard_normal(n)
    hi = bp(src, 1200, 6500, 2)
    lo = bp(src, 400, 1400, 2) * 0.5
    sweep = np.exp(-t / 0.25)   # 抜けるにつれて暗く
    x = (hi * sweep + lo * (1 - 0.5 * sweep)) * env
    x += lp(rng.standard_normal(n), 300, 2) * ar(n, 0.01, 0.08, 2.0) * 0.4   # 弁の「ぷ」
    return fade(lp(x, 8000), 0.002, 0.12)


def done(rng):
    """できあがり: 装置のタイマーの「チン」（澄んだ 1 打と、余韻）"""
    out = np.zeros(n_of(1.6))
    f0 = 1760.0 * rng.uniform(0.99, 1.01)
    place(out, ting(rng, n_of(1.5), f0, 0.55, (1.0, 2.4, 4.1, 6.3)), 0.0)
    m = n_of(0.005)
    place(out, hp(rng.standard_normal(m), 4000) * exp_decay(m, 0.001) * 0.4, 0.0)
    return fade(lp(out, 9000), 0.0003, 0.3)


if __name__ == "__main__":
    for i, kind in enumerate(("press", "iron", "dryer", "drink")):
        write(f"cook_music_{kind}_loop.wav", music(np.random.default_rng(2600 + i), kind), -6)
    for i in range(2):
        write(f"cook_bell_{i + 1:02d}.wav", bell(np.random.default_rng(2610 + i)), -5)
        write(f"cook_done_{i + 1:02d}.wav", done(np.random.default_rng(2620 + i)), -6)
    for i in range(3):
        write(f"cook_pellet_{i + 1:02d}.wav", pellet(np.random.default_rng(2630 + i)), -6)
        write(f"cook_press_{i + 1:02d}.wav", press(np.random.default_rng(2640 + i)), -3)
        write(f"cook_puff_{i + 1:02d}.wav", puff(np.random.default_rng(2650 + i)), -5)
    write("cook_sizzle_loop.wav", sizzle_loop(np.random.default_rng(2660)), -9)
    write("cook_fry_loop.wav", fry_loop(np.random.default_rng(2661)), -9)
    write("cook_boil_loop.wav", boil_loop(np.random.default_rng(2662)), -8)
    write("cook_drum_loop.wav", drum_loop(np.random.default_rng(2663)), -8)
    write("cook_plop_01.wav", plop(np.random.default_rng(2664)), -5)
    write("cook_gurgle_loop.wav", gurgle_loop(np.random.default_rng(2665)), -8)
