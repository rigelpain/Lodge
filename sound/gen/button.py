"""雪に縫い留められたボタン（game/snow_buttons.gd）の音。木のボタンと糸だけの音にする（金属の鳴りは入れない）。

button_snap_01..03  滑り木で糸がぷつんと切れる: 張った糸がはじける細いピッと、短くゆるむビン
button_pop_01..03   ボタンがぽんと跳ね上がる: 栓が抜けるような上がる「ぽ」と、木の円板のコン
button_land_01..02  空から降ってきたボタンが雪に着く: 綿の雪にぽふ
button_sew_01       落ちた所に糸がするっと縫い付く: 糸が穴を抜けるするっと、締まるキュッ
お金のボタン 4 段を取ったとき（ぽんのあとに重ねる。2026-10-30 代表の表）:
button_take_wood_01   1     木: コッ（乾いた短い木の音）
button_take_brass_01  10    真鍮: チン（小さな鈴のような、金属の澄んだ音）
button_take_pearl_01  100   白蝶貝: シャラン（薄い貝の板が触れ合う、細かく高い音が下りていく）
button_take_raden_01  1000  螺鈿: いちばん特別な音。低くやわらかい鐘のポーンに、貝のきらめきが上っていき、最後に澄んだ二つの音
shears_01..02         裁ちばさみでちょきん: シャキン（刃がすれ合って、刃先が合わさる）
button_chari_01..08   財布にボタンが入る 1 粒（2026-10-30 代表「手元に入ってくるときのお金の音、連続でチャリチャリってなってほしい」）。
                      ボタンが財布の山に当たって重なる、硬く軽い音: 当たるカッと、すぐ跳ねて落ち着くチッ（2 つの粒、15〜35 ms あけて）。
                      ゲームでは、入るボタンの数だけ 50〜75 ms ごとに続けて鳴らし（audio.gd の coin）、チャリチャリチャリ…にする。
                      8 つは当たる高さ・間・響きを少しずつ変えてある（機械的に聞こえないように）
button_stitch_01..03  滑っている最中、速さの表示の糸の上にボタンが縫い付いて積もる（2026-10-30 代表「滑り降りている最中もスタックする
                      報酬のコインの音はしてほしい」）: 糸が通るぷつっと、ボタンが前のボタンの上に落ち着くころん（木の小さな当たり 2 つ）
button_glint_01       真鍮が縫い付いたときに重ねる、きらっ（高く短い澄んだ粒が駆け上がる）
滑り終わって、もらったボタンが全部財布に入ったときの締めくくり（2026-10-30 代表「滑り終わったあとに手元に入ってくるお金の音がしないのが悲しい」）:
button_reward_01      少し（〜5 枚）: 木のボタンが手の中でまとまる、ちゃりっ
button_reward_02      ふつう（6〜12 枚）: もう少し多く重なって、ちゃりん
button_reward_03      たくさん・真鍮が混ざる: ちゃりんと鳴ったあと、真鍮の澄んだ 2 音が上る
止まらずに滑って、距離の節目でコンボが一段上がったとき（2026-10-31 代表「コンボしていることを、なにかで表示＋気持ちがいい音を追加で
出してほしい」。game/audio.gd の combo）:
button_combo_01..08   木琴のやわらかい「ポン」に、小さな鈴の「りん」を重ねた 1 音。段ごとに五音音階で一つずつ上がる
                      （ド・レ・ミ・ソ・ラ・ド・レ・ミ）。3 段目からは、5 度上と 1 オクターブ上の小さなきらめきが後ろに続き、段が上がるほど増える
button_combo_break_01 コンボが切れた: 木琴の 2 音が、短くやさしく下がる（ミ → ド。小さく）
"""
import numpy as np

from lib import SR, ar, bp, exp_decay, fade, hp, lp, modes, moving_resonator, n_of, place, write


def wood(rng, n, f0, decay=0.03):
    """木の円板が鳴るコン"""
    return modes(n, np.array([1.0, 2.31, 3.95, 5.6]) * f0 * rng.uniform(0.97, 1.03),
                 [decay, decay * 0.55, decay * 0.32, decay * 0.2], [1.0, 0.5, 0.28, 0.12], rng)


def snap(rng):
    out = np.zeros(n_of(0.22))
    n = n_of(0.02)
    tick = bp(rng.standard_normal(n), 2500, 9000, 2) * exp_decay(n, 0.0012)   # 張った糸がはじける
    place(out, tick, 0.0)
    n = n_of(0.16)
    t = np.arange(n) / SR
    f = rng.uniform(520, 640) * (1.0 - 0.45 * (1 - np.exp(-t / 0.03)))        # ゆるみながら下がるビン
    twang = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.035)
    twang += 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.02)
    place(out, twang * 0.35, 0.002)
    return fade(out, 0.0002, 0.04)


def pop(rng):
    out = np.zeros(n_of(0.35))
    n = n_of(0.09)
    t = np.arange(n) / SR
    f = 260 + 520 * (1 - np.exp(-t / 0.02)) * rng.uniform(0.9, 1.1)            # 栓が抜ける「ぽ」: 上がる共鳴
    puff = lp(rng.standard_normal(n), 2500, 2) * ar(n, 0.002, 0.08, 2.0)
    po = moving_resonator(puff, f, 0.995)
    place(out, po / np.max(np.abs(po)), 0.0)
    place(out, wood(rng, n_of(0.25), rng.uniform(640, 760), 0.04) * 0.55, 0.012)   # 木のコン
    return fade(out, 0.0005, 0.06)


def land(rng):
    n = n_of(0.25)
    p = lp(rng.standard_normal(n), 900, 2) * ar(n, 0.006, 0.2, 2.5)
    body = wood(rng, n, rng.uniform(380, 450), 0.012) * 0.25                 # 雪ごしの、こもった木
    return fade(p / np.max(np.abs(p)) + body, 0.001, 0.05)


def sew(rng):
    out = np.zeros(n_of(0.5))
    n = n_of(0.3)
    t = np.arange(n) / SR
    f = 1200 + 2400 * t / t[-1]                                              # 糸が穴を抜ける: 擦れが上がる
    rub = moving_resonator(rng.standard_normal(n), f, 0.97) * ar(n, 0.08, 0.12, 1.5)
    place(out, rub / np.max(np.abs(rub)) * 0.7, 0.0)
    m = n_of(0.05)
    tug = hp(rng.standard_normal(m), 1800) * exp_decay(m, 0.006)              # 締まるキュッ
    place(out, tug * 0.5, 0.31)
    place(out, wood(rng, n_of(0.12), 820, 0.012) * 0.3, 0.315)
    return fade(out, 0.002, 0.05)


def ting(rng, n, f0, decay, partials=(1.0, 2.76, 5.4, 8.9)):
    """小さな金属の鳴り（鈴・鐘）"""
    return modes(n, np.array(partials) * f0, [decay, decay * 0.6, decay * 0.35, decay * 0.2], [1.0, 0.45, 0.25, 0.12], rng)


def take_wood(rng):
    out = np.zeros(n_of(0.25))
    place(out, wood(rng, n_of(0.2), 1150, 0.018), 0.0)
    n = n_of(0.01)
    place(out, bp(rng.standard_normal(n), 2000, 7000, 2) * exp_decay(n, 0.0015) * 0.4, 0.0)
    return fade(out, 0.0003, 0.04)


def take_brass(rng):
    out = np.zeros(n_of(1.1))
    place(out, ting(rng, n_of(1.0), 2640, 0.28), 0.0)
    n = n_of(0.006)
    place(out, hp(rng.standard_normal(n), 4000) * exp_decay(n, 0.001) * 0.5, 0.0)
    return fade(out, 0.0003, 0.2)


def shell_clink(rng, f0):
    n = n_of(0.12)
    return modes(n, np.array([1.0, 1.9, 3.1]) * f0, [0.03, 0.02, 0.01], [1.0, 0.4, 0.2], rng)


def take_pearl(rng):
    out = np.zeros(n_of(1.2))
    for i in range(11):   # 高いところから下りていく、細かな触れ合い
        f = 5200 * (0.93 ** i) * rng.uniform(0.97, 1.03)
        place(out, shell_clink(rng, f) * (0.9 - i * 0.05), 0.035 * i + rng.uniform(0, 0.01))
    n = n_of(0.9)
    air = bp(rng.standard_normal(n), 5000, 11000, 2) * ar(n, 0.02, 0.8, 2.0) * 0.08
    place(out, air, 0.0)
    return fade(out, 0.0005, 0.2)


def take_raden(rng):
    out = np.zeros(n_of(2.4))
    place(out, ting(rng, n_of(2.2), 392, 0.9, (1.0, 2.0, 2.98, 4.1)) * 0.8, 0.0)   # 低くやわらかい鐘
    for i in range(14):   # 貝のきらめきが上っていく
        f = 1800 * (1.09 ** i) * rng.uniform(0.98, 1.02)
        place(out, shell_clink(rng, f) * 0.45, 0.12 + 0.045 * i)
    for k, (f0, at) in enumerate([(1568.0, 0.85), (2349.0, 1.05)]):   # 最後に澄んだ二つの音
        place(out, ting(rng, n_of(1.2), f0, 0.5) * 0.55, at)
    return fade(out, 0.0005, 0.4)


def shears(rng):
    out = np.zeros(n_of(0.4))
    n = n_of(0.16)
    t = np.arange(n) / SR
    f = 2500 + 5000 * t / t[-1]   # 刃がすれ合う: シャー（上がる）
    slide = moving_resonator(rng.standard_normal(n), f, 0.9) * ar(n, 0.02, 0.06, 1.5)
    place(out, slide / np.max(np.abs(slide)) * 0.5, 0.0)
    place(out, ting(rng, n_of(0.25), 3900 * rng.uniform(0.97, 1.03), 0.04) * 0.8, 0.15)   # 刃先が合わさるキン
    m = n_of(0.01)
    place(out, hp(rng.standard_normal(m), 3000) * exp_decay(m, 0.001) * 0.7, 0.15)
    return fade(out, 0.0005, 0.05)


def chari(rng):
    """財布の山にボタンが当たって重なる 1 粒: 硬い当たり（木のボタンどうし）と、跳ねて落ち着く小さな当たり"""
    out = np.zeros(n_of(0.14))
    for j, (gain, at) in enumerate([(1.0, 0.0), (rng.uniform(0.35, 0.6), rng.uniform(0.015, 0.035))]):
        n = n_of(0.05)
        click = bp(rng.standard_normal(n), 2200, 7500, 2) * exp_decay(n, rng.uniform(0.0012, 0.002))
        body = modes(n, np.array([1.0, 2.4, 4.1]) * rng.uniform(1500, 2300), [0.009, 0.006, 0.004], [1.0, 0.5, 0.25], rng)
        ring = modes(n, np.array([1.0, 1.7]) * rng.uniform(3200, 4200), [0.02, 0.012], [1.0, 0.4], rng) * 0.25
        place(out, (click * 0.9 + body * 0.6 + ring) * gain, at)
    return fade(out, 0.0002, 0.03)


def stitch_on(rng):
    out = np.zeros(n_of(0.3))
    n = n_of(0.03)
    pierce = bp(rng.standard_normal(n), 1800, 6000, 2) * exp_decay(n, 0.0025)   # 糸が通るぷつっ
    place(out, pierce * 0.7, 0.0)
    f0 = rng.uniform(700, 900)
    place(out, wood(rng, n_of(0.16), f0, 0.03) * 0.9, 0.03)                      # ころん: 落ちて
    place(out, wood(rng, n_of(0.12), f0 * 1.12, 0.018) * 0.45, 0.03 + rng.uniform(0.05, 0.07))   # 小さく転がって止まる
    return fade(out, 0.0003, 0.05)


def glint(rng):
    out = np.zeros(n_of(0.6))
    for i, f in enumerate([2637.0, 3136.0, 3951.0, 5274.0]):
        place(out, ting(rng, n_of(0.45), f * rng.uniform(0.99, 1.01), 0.12, (1.0, 2.76, 5.4, 8.9)) * (0.7 - 0.1 * i), 0.03 * i)
    n = n_of(0.3)
    place(out, bp(rng.standard_normal(n), 6000, 12000, 2) * ar(n, 0.01, 0.25, 2.0) * 0.08, 0.0)
    return fade(out, 0.0005, 0.12)


def clink_cluster(rng, count, spread, f_lo=900.0, f_hi=1500.0):
    """何枚ものボタンが手の中で触れ合う: 木のコッを、少しずつずらして重ねる（だんだん弱く）"""
    out = np.zeros(n_of(spread + 0.3))
    for i in range(count):
        at = spread * (i / max(1, count - 1)) ** 1.4 + rng.uniform(0, 0.012)
        place(out, wood(rng, n_of(0.2), rng.uniform(f_lo, f_hi), 0.016) * (1.0 - 0.5 * i / count), at)
    return out


COMBO_NOTES = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51]   # ド・レ・ミ・ソ・ラ・ド・レ・ミ（五音音階）


def mallet(rng, f0, dur=0.6, soft=1.0):
    """木琴のやわらかい鳴り: 木の板の 1・4・10 倍の部分音（高いほど早く消える）と、毛糸巻きのばちの柔らかい当たり"""
    n = n_of(dur)
    out = modes(n, np.array([1.0, 3.93, 9.8]) * f0, [0.32, 0.06, 0.018], [1.0, 0.22 * soft, 0.06 * soft], rng)
    m = n_of(0.008)
    place(out, lp(rng.standard_normal(m), 2500) * exp_decay(m, 0.002) * 0.15, 0.0)
    return out


def combo_up(rng, level):
    """コンボが一段上がる: 木琴のポン + 鈴のりん（同じ高さ）。段が上がるほど、後ろのきらめきが増える"""
    f0 = COMBO_NOTES[level]
    out = np.zeros(n_of(1.4))
    place(out, mallet(rng, f0), 0.0)
    place(out, lp(ting(rng, n_of(1.0), f0 * 2.0, 0.3), 7000) * 0.35, 0.004)
    sparks = max(0, level - 1)   # 3 段目（level 2）から 1 つ、2 つ…
    for i, ratio in enumerate([1.5, 2.0, 3.0, 4.0, 6.0][:sparks]):
        f = f0 * ratio
        while f > 2400.0:   # きらめきは 2.4 kHz までに折り返す（高い段で耳に刺さらないように）
            f /= 2.0
        place(out, lp(ting(rng, n_of(0.6), f, 0.12), 6000) * (0.16 - 0.02 * i), 0.07 + 0.055 * i)
    return fade(out, 0.0005, 0.25)


def combo_break(rng):
    """コンボが切れた: 木琴の 2 音が短く下がる（ミ → ド）"""
    out = np.zeros(n_of(0.7))
    place(out, mallet(rng, 659.25, 0.45, 0.6), 0.0)
    place(out, mallet(rng, 523.25, 0.5, 0.6) * 0.8, 0.11)
    return fade(out, 0.0005, 0.15)


def reward(rng, size):
    count, spread = [(5, 0.12), (9, 0.2), (13, 0.26)][size]
    out = np.zeros(n_of(1.6 if size == 2 else 0.8))
    place(out, clink_cluster(rng, count, spread), 0.0)
    place(out, ting(rng, n_of(0.7), 2900, 0.18) * (0.25 + 0.15 * size), spread * 0.8)   # 締めの「りん」
    if size == 2:
        for k, (f0, at) in enumerate([(1976.0, 0.42), (2637.0, 0.58)]):   # 真鍮の澄んだ 2 音
            place(out, ting(rng, n_of(0.9), f0, 0.35) * 0.45, at)
    return fade(out, 0.0005, 0.15)


if __name__ == "__main__":
    for i in range(3):
        write(f"button_snap_{i + 1:02d}.wav", snap(np.random.default_rng(1500 + i)), -4)
        write(f"button_pop_{i + 1:02d}.wav", pop(np.random.default_rng(1510 + i)), -4)
    for i in range(2):
        write(f"button_land_{i + 1:02d}.wav", land(np.random.default_rng(1530 + i)), -10)
    write("button_sew_01.wav", sew(np.random.default_rng(1540)), -9)
    write("button_take_wood_01.wav", take_wood(np.random.default_rng(1550)), -6)
    write("button_take_brass_01.wav", take_brass(np.random.default_rng(1551)), -5)
    write("button_take_pearl_01.wav", take_pearl(np.random.default_rng(1552)), -5)
    write("button_take_raden_01.wav", take_raden(np.random.default_rng(1553)), -3)
    for i in range(2):
        write(f"shears_{i + 1:02d}.wav", shears(np.random.default_rng(1560 + i)), -5)
    for i in range(3):
        write(f"button_reward_{i + 1:02d}.wav", reward(np.random.default_rng(1570 + i), i), -3)
    for i in range(8):
        write(f"button_chari_{i + 1:02d}.wav", chari(np.random.default_rng(1580 + i)), -4)
    for i in range(3):
        write(f"button_stitch_{i + 1:02d}.wav", stitch_on(np.random.default_rng(1590 + i)), -4)
    write("button_glint_01.wav", glint(np.random.default_rng(1595)), -5)
    for i in range(8):
        write(f"button_combo_{i + 1:02d}.wav", combo_up(np.random.default_rng(1600 + i), i), -3)
    write("button_combo_break_01.wav", combo_break(np.random.default_rng(1610)), -9)
