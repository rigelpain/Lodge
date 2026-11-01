"""売り台・ミシン・厨房の音を、代表が聞き比べるページ（sound/check/craft/index.html）を作る。
ゲームと同じ間で重ねたお手本（demo）も、ここで wav/ の音から組み立てて sound/check/craft/ に書く。
Finder から index.html を開くと聞ける。先に gen/shop.py・gen/sew.py・gen/cook.py を走らせておく。

.venv/bin/python gen/craft_page.py
"""
import html
import pathlib

import numpy as np
from scipy.io import wavfile

from lib import SR, n_of

ROOT = pathlib.Path(__file__).resolve().parents[1]
WAV, OUT = ROOT / "wav", ROOT / "check" / "craft"


def load(name):
    sr, x = wavfile.read(WAV / f"{name}.wav")
    return x.astype(np.float64) / 32767


def put(buf, x, at, gain=1.0, pitch=1.0):
    if pitch != 1.0:
        idx = np.arange(0, len(x) - 1, pitch)
        x = np.interp(idx, np.arange(len(x)), x)
    i = n_of(at)
    m = min(len(x), len(buf) - i)
    if m > 0:
        buf[i:i + m] += x[:m] * gain


def save(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    k = np.max(np.nonzero(np.abs(x) > 1e-4)[0]) + n_of(0.05)
    x = x[:k] / max(np.max(np.abs(x[:k])), 1e-9) * 10 ** (-3 / 20)
    wavfile.write(OUT / f"{name}.wav", SR, (x * 32767).astype(np.int16))


def db(v):
    return 10 ** (v / 20)


def sew_demo(helper=False):
    """sewing_machine.gd の流れと音量のお手本: 縫い始め → 布が入る → 押さえ → 8 目（だんだん速く）→ 糸切り → ばね → ふくらむ → 床へ → 止まる"""
    rng = np.random.default_rng(7)
    out = np.zeros(n_of(9.0))
    put(out, load("sew_start_01"), 0.0, db(-7))
    put(out, load("sew_draw"), 0.4, db(-10))
    put(out, load("sew_presser_01"), 1.12, db(-6))
    t, rate = 1.25, 1.5
    top = 5.5 if helper else 3.5
    hum = load("sew_hum_loop")
    stitch_times = []
    for k in range(8):
        rate = min(top, rate + (top - 1.5) / (1.0 if helper else 2.0) / rate)
        t += 1.0 / rate
        stitch_times.append((t, rate))
    end = stitch_times[-1][0] + 0.1
    # 回っているあいだのうなり（速さで高さと大きさ。ゲームでは pitch 0.7 + 0.08 × 速さ）
    seg = np.tile(hum, 4)[:n_of(end + 1.6 - 1.25)]
    env = np.interp(np.arange(len(seg)) / SR + 1.25, [1.25, 1.6, end, end + 1.6], [0, 1, 1, 0])
    put(out, seg * env, 1.25, db(-16 + 1.2 * 3.5) * 0.7, 0.7 + 0.08 * 3.5)
    for k, (st, r) in enumerate(stitch_times):
        put(out, load(f"sew_stitch_{rng.integers(1, 4):02d}"), st, db(-14 + min(r, 6)), 0.9 + 0.05 * r)
        if helper and k % 2:
            put(out, load(f"sew_treadle_{rng.integers(1, 4):02d}"), st, db(-11))
    put(out, load("sew_snip_01"), end, db(-4))
    put(out, load("sew_spring"), end + 0.12, db(-9))
    put(out, load("sew_pop"), end + 0.25, db(-5), 0.85)
    put(out, load("sew_land_01"), end + 0.25 + 0.85, db(-3))
    for k in range(3):   # 止まるまでの最後の数目
        put(out, load(f"sew_stitch_{k + 1:02d}"), end + 1.4 + 0.35 * k * (1 + 0.4 * k), db(-16))
    put(out, load("sew_rest"), end + 1.4 + 1.9, db(-10))
    return out


def cook_demo(dev, loop_s=3.5):
    out = np.zeros(n_of(loop_s + 4.0))
    put(out, load(f"cook_{dev}_in_01"), 0.0)
    loop = np.tile(load(f"cook_{dev}_loop"), 3)[:n_of(loop_s + 0.6)]
    env = np.interp(np.arange(len(loop)) / SR, [0, 0.6, loop_s, loop_s + 0.35], [0, 1, 1, 0])
    put(out, loop * env, 0.5, db(-4))
    put(out, load(f"cook_{dev}_done_01"), 0.5 + loop_s)
    return out


SECTIONS = [
    ("購入音", "買ったときに、店の台で鳴る音。画面の決定音にはせず、お皿に払いが落ちる → レジ → 品物を包む、の 3 つを重ねる。"
     "払う数でボタンの粒が増える。",
     [("おじいさんの番台（型紙と布）", ["check:buy_patch_demo_1", "check:buy_patch_demo_2", "check:buy_patch_demo_3"]),
      ("雪だるまの番台（ペレット。お代は雪玉）", ["check:buy_snow_demo_1", "check:buy_snow_demo_2", "check:buy_snow_demo_3"]),
      ("2 階の衣装掛けの横の売り台（小物とミニオン）", ["check:buy_pal_demo_1", "check:buy_pal_demo_2", "check:buy_pal_demo_3"]),
      ("案: 録音を使わず合成だけ", ["check:cand_buy_patch_synth_1", "check:cand_buy_snow_synth_1", "check:cand_buy_pal_synth_1"]),
      ("案: おじいさんのレジをそろばんに", ["check:cand_buy_patch_soroban_1", "check:cand_buy_patch_soroban_2"]),
      ("部品: 払い", [f"pay_button_{i:02d}" for i in range(1, 7)] + [f"pay_snowball_{i:02d}" for i in range(1, 4)]),
      ("部品: レジ", [f"till_{s}_{i:02d}" for s in ["patch", "snow", "pal"] for i in range(1, 4)]),
      ("部品: 包む", [f"wrap_{s}_{i:02d}" for s in ["paper", "bag", "tissue"] for i in range(1, 4)])]),
    ("ミシンでの制作音", "縫い始め・縫っている間・できあがり。木とフェルトの機械に、真鍮の小さな部品。",
     [("通し（一人で縫う）", ["check:sew_demo"]),
      ("通し（足踏みに仲間がいる。速く、踏み板がきしむ）", ["check:sew_demo_helper"]),
      ("縫い始め", ["sew_start_01", "sew_start_02", "sew_draw", "sew_presser_01", "sew_presser_02"]),
      ("縫っている間", [f"sew_stitch_{i:02d}" for i in range(1, 7)] + ["sew_hum_loop"] + [f"sew_treadle_{i:02d}" for i in range(1, 4)]),
      ("できあがり", ["sew_snip_01", "sew_snip_02", "sew_spring", "sew_pop", "sew_land_01", "sew_land_02", "sew_rest"])]),
    ("食べ物の調理音", "雪だるまの厨房の 4 つの装置。入れる → 動いている（ループ）→ できた。",
     [("アイロン台（挟んで焼く）", ["check:cook_iron_demo", "cook_iron_in_01", "cook_iron_in_02", "cook_iron_loop", "cook_iron_done_01", "cook_iron_done_02"]),
      ("プレス機（押して形に）", ["check:cook_press_demo", "cook_press_in_01", "cook_press_in_02", "cook_press_loop", "cook_press_done_01", "cook_press_done_02"]),
      ("乾燥機（回して茹でる・揚げる）", ["check:cook_dryer_demo", "cook_dryer_in_01", "cook_dryer_in_02", "cook_dryer_loop", "cook_dryer_done_01", "cook_dryer_done_02"]),
      ("飲み物のスチーマー", ["check:cook_drink_demo", "cook_drink_in_01", "cook_drink_in_02", "cook_drink_loop", "cook_drink_done_01", "cook_drink_done_02"])]),
]


def page():
    rows = []
    for title, note, groups in SECTIONS:
        rows.append(f"<h2>{html.escape(title)}</h2><p>{html.escape(note)}</p>")
        for g, names in groups:
            rows.append(f"<h3>{html.escape(g)}</h3><div class=grid>")
            for nm in names:
                src = f"{nm[6:]}.wav" if nm.startswith("check:") else f"../../wav/{nm}.wav"
                label = nm[6:] if nm.startswith("check:") else nm
                rows.append(f"<figure><figcaption>{html.escape(label)}</figcaption><audio controls preload=none src='{src}'></audio></figure>")
            rows.append("</div>")
    return f"""<!doctype html><meta charset=utf-8><title>売り台・ミシン・厨房の音</title>
<style>body{{font:15px/1.6 system-ui,sans-serif;max-width:980px;margin:24px auto;padding:0 16px;background:#faf7f2;color:#2b2622}}
h2{{border-bottom:2px solid #c9b79c;margin-top:2em}}h3{{margin:1.2em 0 .4em;font-size:15px}}
.grid{{display:flex;flex-wrap:wrap;gap:8px}}figure{{margin:0;background:#fff;border:1px solid #e4d9c8;border-radius:6px;padding:6px 8px}}
figcaption{{font-size:12px;color:#6b5f52}}audio{{width:230px;height:32px}}</style>
<h1>売り台・ミシン・厨房の音（2026-11-01）</h1>
<p>代表に聞いてほしいこと: (1) 3 つの音の世界がこれでよいか (2) 購入音は「録音まじり」「合成だけ」「そろばん」のどれがよいか
(3) 嫌な音・耳に残りすぎる音はどれか。作り方は sound/gen/shop.py・sew.py・cook.py、録音の出どころは sound/SOURCES.md。</p>
{''.join(rows)}"""


if __name__ == "__main__":
    save("sew_demo", sew_demo())
    save("sew_demo_helper", sew_demo(True))
    for d in ["iron", "press", "dryer", "drink"]:
        save(f"cook_{d}_demo", cook_demo(d))
    (OUT / "index.html").write_text(page())
    print(OUT / "index.html")
