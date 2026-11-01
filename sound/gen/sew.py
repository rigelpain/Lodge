"""大きなミシン（game/sewing_machine.gd）の音。木とフェルトのぬいぐるみの機械に、真鍮の小さな部品（針棒の留め・かま・つめ）。
金属の鋭さは真鍮の小物にだけ残し、土台は木の「コト」と布の「ぷす」と糸の「しゅっ」。
2026-11-01 代表「ミシンでの制作音…をしっかり作ってほしい」で、仮の音から作り直し、縫い始め・縫っている間・できあがりに分けた。

木・布・はさみの当たりは録音（CC0。出どころは sound/SOURCES.md、切る所は gen/rec.py）。合成だけの当たりは、earshot で
「スネア」「電子のうなり」「カリンバ」に聞こえたので、録音を土台にして、真鍮の小さな「ちっ」や糸の「ぴん」だけ合成で足す。

縫い始め
  sew_start_01..02    画面で縫うを押した: 木の留め金のレバーを倒す「カタン」、はずみ車を手で少し回すきしみと「ごとっ」、糸巻きが「からら」
  sew_draw            布が針の下へ吸い込まれる（布のこすれが強まり、糸案内の真鍮が「ちっ」）
  sew_presser_01..02  押さえが布に下りる「とん」と、糸案内の「ちっ」
縫っている間
  sew_stitch_01..06   針 1 目: ゆっくり回すミシンの録音（CC0）から 1 目ずつ切った「カタン」に、布を刺す「ぷす」を重ねる
                      （01〜03 薄い布・04〜06 厚い布。厚い布は少し低く、こもらせる）。合成だけの 1 目は、earshot で「ハイハット」「画面のクリック」に聞こえた
  sew_hum_loop        回っているあいだの機構: はずみ車と革ベルトのうなり、ベルトの継ぎ目の「とっ」、歯車の噛み合い（合成）に、
                      古いミシンが回る録音（CC0）の低いところ（1.6 kHz より下。1 目の「カタン」は落とす）を敷く。ゲームで音程を上げる
  sew_treadle_01..03  足踏みに仲間がいるとき、踏み板が「ぎっ」ときしみ、「とん」と戻る（2 目に 1 度）
できあがり
  sew_snip_01..02     糸切りのはさみ「ちょきん」
  sew_spring          止めが明けて、ミシンが戻る布の「ぽすっ」と、綿くずが舞う「ふわっ」
  sew_pop             できたソリがフェルトの袋のようにふくらむ「ぽふん」
  sew_land_01..02     ソリが台から床へ滑り下りて止まる（木の「ごとん」と、フェルトの「ずさっ」）
  sew_rest            針が上で止まる「かたん」と、つめの「かち」
そのほか
  sew_clack           呼ぶ: 布送りの歯のカタッ
"""
import numpy as np

from lib import SR, ar, bp, fade, lp, n_of, place, place_wrap, seamless, write
import rec
from parts import brass, creak, norm, thud, wood


def knock(rng, n, f0=900.0):
    """木の小さな部品が当たる音（呼ぶの「カタッ」）"""
    return wood(rng, f0, n / SR)


def start(rng):
    """木の留め金のレバーを倒す（録音）→ はずみ車を手で回すきしみ（録音）→ 糸巻きが「からら」（合成）"""
    out = np.zeros(n_of(1.0))
    place(out, rec.pick("latch", int(rng.integers(0, 2)), low=150) * 0.8, 0.0)
    cr = rec.pick("creak", 0, low=200)[:n_of(0.4)]
    place(out, cr * ar(len(cr), 0.03, 0.2, 1.5) * 0.4, 0.18)
    place(out, rec.pick("lid", 1, low=90, high=6000) * 0.45, 0.48)                          # 回りきって「ごとっ」
    for j in range(4):
        place(out, wood(rng, rng.uniform(1700, 2100), 0.04, 2.0) * 0.12 * (0.75 ** j), 0.6 + 0.035 * j)
    return fade(out, 0.0005, 0.06)


def draw(rng):
    """布が針の下へ吸い込まれる: 布をこする録音を、だんだん強く、すっと止める"""
    r = rec.pick("rustle", 0, low=200, high=9000)
    n = n_of(0.75)
    x = np.resize(r, n) * ar(n, 0.4, 0.25, 1.6)
    out = norm(x) * 0.8
    place(out, brass(rng, 4200, 0.05, 0.5) * 0.08, 0.3)                      # 糸案内
    place(out, rec.pick("box", 0, low=200) * 0.3, 0.6)
    return fade(out, 0.01, 0.04)


def presser(rng):
    """押さえが布に下りる「とん」（木の箱の録音）と、糸が張る真鍮の糸案内の「ちっ」（合成、小さく）。
    糸をはじく「ぴん」は earshot で「ウクレレ」に聞こえたので入れない"""
    out = np.zeros(n_of(0.45))
    place(out, rec.pick("box", int(rng.integers(0, 3)), low=150) * 0.8, 0.0)
    place(out, brass(rng, rng.uniform(4300, 4800), 0.05, 0.4) * 0.08, 0.035)
    return fade(out, 0.0005, 0.08)


def stitch_rec(rng, take, thick=False):
    """録音の 1 目に、合成の「ぷす」（布を刺す）を重ねる"""
    r = take.copy()
    if thick:
        r = lp(rec.speed(r, 0.9), 3200, 2)
    out = np.zeros(max(len(r), n_of(0.2)))
    place(out, r, 0.0)
    n = n_of(0.04)
    lo, hi = (450, 2200) if thick else (800, 3400)
    poke = bp(rng.standard_normal(n), lo, hi, 2) * ar(n, 0.0025, 0.035, 2.2)
    place(out, norm(poke) * 0.22, 0.032)
    return fade(out, 0.0005, 0.04)


def hum_loop(rng):
    """1 周 0.25 秒の機構（ゲームでは縫う速さで pitch_scale 0.8〜1.15）。ループの長さ 4 秒は 1 周の 16 倍"""
    period = 0.25
    n = n_of(4.0 + 0.25)
    t = np.arange(n) / SR
    rot = 2 * np.pi * t / period
    # はずみ車と軸の低いうなり（1 周ごとにわずかに強弱）
    base = 0.55 * np.sin(2 * np.pi * 55 * t) + 0.3 * np.sin(2 * np.pi * 110 * t + 0.5) + 0.12 * np.sin(2 * np.pi * 165 * t + 1.1)
    base *= 1 + 0.25 * np.sin(rot)
    # 革ベルトが車にこすれる帯域の雑音。1 周ごとに張りが変わる
    belt = bp(rng.standard_normal(n), 150, 700, 2) * (0.75 + 0.25 * np.sin(rot + 1.3))
    # 木の歯車の噛み合い: 歯の数 18 で 1 周 → 72 Hz の粒が、狭い帯域の「じー」になる
    teeth = np.zeros(n)
    for k in range(int(4.25 * 72)):
        at = k / 72.0
        place(teeth, wood(rng, rng.uniform(1300, 1500), 0.012, 2.5) * rng.uniform(0.3, 1.0), at)
    out = norm(base) * 0.5 + norm(belt) * 0.3 + norm(teeth) * 0.16
    # ベルトの継ぎ目が車を通る「とっ」: 1 周に 1 度
    for k in range(int(4.25 / period) + 1):
        place_wrap(out, thud(rng, rng.uniform(170, 190), 0.06) * 0.22, k * period + 0.11)
    # 木の軸受けが、ときどきかすかに鳴く
    for at in rng.uniform(0, 4.0, 5):
        place_wrap(out, creak(rng, 0.12, 60, 90, (900, 2100)) * 0.05, at)
    run = rec.pick("sew_run", 0, low=60, high=1600)       # 古いミシンが回る録音の低いところ
    run = np.resize(run, n) * (np.arange(n) < len(run))
    out = norm(out) + norm(run) * 0.5
    return seamless(lp(out, 3500), 0.25)


def treadle(rng):
    """踏み板のきしみ（揺り椅子の録音を短く）と、戻る「とん」（木の戸の録音を低く）"""
    out = np.zeros(n_of(0.6))
    cr = rec.pick("creak", 0, low=150)
    k = int(rng.integers(0, max(1, len(cr) - n_of(0.3))))
    piece = cr[k:k + n_of(0.28)]
    place(out, piece * ar(len(piece), 0.03, 0.15, 1.5) * 0.5, 0.0)
    place(out, rec.speed(rec.pick("clunk", 0, low=80, high=4000), 0.85) * 0.7, rng.uniform(0.16, 0.2))
    return fade(out, 0.001, 0.05)


def snip(rng, i=0):
    """糸切りのはさみ（録音）。木の柄の「コト」を小さく重ねる"""
    r = rec.pick("snip", i, low=300)
    out = np.zeros(len(r) + n_of(0.1))
    place(out, r, 0.0)
    place(out, wood(rng, rng.uniform(560, 640), 0.1) * 0.15, 0.01)
    return fade(out, 0.0002, 0.06)


def spring(rng):
    """止めが明けてミシンが戻る: 布をつかむ「ぽすっ」と、綿くずが舞う布の「ふわっ」（どちらも録音）。
    合成のばねの「ぼよん」は earshot で「スネア」に聞こえたのでやめた"""
    out = np.zeros(n_of(0.8))
    place(out, rec.pick("fabric", 2, low=150) * 0.7, 0.0)
    fluff = rec.pick("rustle", 1, low=400)[:n_of(0.45)]
    place(out, fluff * ar(len(fluff), 0.05, 0.35, 1.5) * 0.45, 0.08)
    return fade(out, 0.002, 0.08)


def pop(rng):
    """フェルトの袋がふくらむ「ぽふん」: 布をつかむ録音と、ぬいぐるみが落ちる録音"""
    out = np.zeros(n_of(0.6))
    place(out, rec.pick("fabric", 0, low=150) * 0.6, 0.0)
    place(out, rec.pick("plop", 0, low=80, high=5000) * 0.8, 0.12)
    return fade(out, 0.002, 0.06)


def land(rng, i=0):
    """ソリが床へ下りる: 重い木のふたの「ごとん」（録音を低く）と、ぬいぐるみの「ぽふ」、床をすべる布"""
    out = np.zeros(n_of(0.9))
    place(out, rec.speed(rec.pick("lid", i, low=60), 0.8) * 0.9, 0.0)
    place(out, rec.pick("plop", 1 + i, low=80, high=4000) * 0.4, 0.004)
    sl = rec.pick("rustle", 0, low=200)[:n_of(0.35)]
    place(out, sl * ar(len(sl), 0.02, 0.3, 1.5) * 0.3, 0.06)
    return fade(out, 0.0005, 0.08)


def rest(rng):
    """針が上で止まる「かたん」（木の留め金の録音を小さく）と、つめの「かち」（合成）"""
    out = np.zeros(n_of(0.45))
    place(out, rec.pick("latch", 0, low=200) * 0.6, 0.0)
    place(out, brass(rng, 3600, 0.06, 0.5) * 0.1, 0.08)
    return fade(out, 0.0005, 0.05)


def clack(rng):
    out = np.zeros(n_of(0.2))
    place(out, knock(rng, n_of(0.1), 1300), 0.0)
    place(out, knock(rng, n_of(0.1), 950) * 0.7, 0.045)
    return fade(out, 0.0005, 0.03)


if __name__ == "__main__":
    for i in range(2):
        write(f"sew_start_{i + 1:02d}.wav", start(np.random.default_rng(1230 + i)), -4)
    write("sew_draw.wav", draw(np.random.default_rng(1212)), -8)
    for i in range(2):
        write(f"sew_presser_{i + 1:02d}.wav", presser(np.random.default_rng(1235 + i)), -5)
    takes = rec.stitches(6)
    for i in range(6):
        write(f"sew_stitch_{i + 1:02d}.wav", stitch_rec(np.random.default_rng(1200 + i), takes[i], thick=i >= 3), -6)
    write("sew_hum_loop.wav", hum_loop(np.random.default_rng(1210)), -10)
    for i in range(3):
        write(f"sew_treadle_{i + 1:02d}.wav", treadle(np.random.default_rng(1240 + i)), -6)
    for i in range(2):
        write(f"sew_snip_{i + 1:02d}.wav", snip(np.random.default_rng(1213 + i * 30), i), -3)
    write("sew_spring.wav", spring(np.random.default_rng(1245)), -5)
    write("sew_pop.wav", pop(np.random.default_rng(1214)), -5)
    for i in range(2):
        write(f"sew_land_{i + 1:02d}.wav", land(np.random.default_rng(1250 + i), i), -4)
    write("sew_rest.wav", rest(np.random.default_rng(1255)), -6)
    write("sew_clack.wav", clack(np.random.default_rng(1211)), -6)
