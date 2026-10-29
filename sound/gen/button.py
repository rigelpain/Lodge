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
滑り終わって、もらったボタンが全部財布に入ったときの締めくくり（2026-10-30 代表「滑り終わったあとに手元に入ってくるお金の音がしないのが悲しい」）:
button_reward_01      少し（〜5 枚）: 木のボタンが手の中でまとまる、ちゃりっ
button_reward_02      ふつう（6〜12 枚）: もう少し多く重なって、ちゃりん
button_reward_03      たくさん・真鍮が混ざる: ちゃりんと鳴ったあと、真鍮の澄んだ 2 音が上る
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


def clink_cluster(rng, count, spread, f_lo=900.0, f_hi=1500.0):
    """何枚ものボタンが手の中で触れ合う: 木のコッを、少しずつずらして重ねる（だんだん弱く）"""
    out = np.zeros(n_of(spread + 0.3))
    for i in range(count):
        at = spread * (i / max(1, count - 1)) ** 1.4 + rng.uniform(0, 0.012)
        place(out, wood(rng, n_of(0.2), rng.uniform(f_lo, f_hi), 0.016) * (1.0 - 0.5 * i / count), at)
    return out


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
