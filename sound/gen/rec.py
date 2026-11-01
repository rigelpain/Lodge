"""売り台・ミシン・厨房の音に混ぜる録音（CC0）を、sound/raw/craft_dl/ から切り出す部品。
出どころは sound/SOURCES.md の「売り台・ミシン・厨房」の表。元は freesound の試聴用の mp3（-hq、128 kbps）で、
git には入れない。取り直すときは SOURCES.md の番号から落として、ffmpeg で 48 kHz モノラルの wav（raw/craft_dl/wav/<番号>_<作者番号>.wav）にする。

使う所（秒は元のファイルの中）は PICKS にまとめる。どこを選んだかは、earshot の find で探した区間（2026-11-01）から決めた。
"""
import pathlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

from lib import SR, hp, lp, n_of, ramp

RAW = pathlib.Path(__file__).resolve().parents[1] / "raw" / "craft_dl" / "wav"

FILES = {
    "register_a": "584168_11720717",    # clubmydia+  old cash register open and close with a bing
    "register_b": "475915_1693743",     # Tompalompa  Vintage cash register
    "register_c": "452572_612689",      # kyles       cash register old antique open close drawer with bell ring
    "sew_old": "721883_11519060",       # bruno.auzet old sewing machine
    "sew_slow": "477836_10201334",      # Astounded   sewing machine (slow running)
    "wrap": "344433_3278936",           # GrayJoy     Wrapping Paper Rustle
    "bag": "537739_11976230",           # steeltowngaming Paper Bag Crunching
    "bag2": "495911_8769399",           # WilliamJMeyer FOLEY_Handling paper bag_1
    "crumple": "634323_13601611",       # uniuniversal Paper_Wrap
    "sizzle": "593182_12165093",        # dannydandanshababaloo Bacon Sizzling
    "pour": "240125_1061768",           # mdayalan    Tea Pouring
    "iron": "346778_5690194",           # Diramus     Steam Iron used on board
    "iron2": "424971_8224400",          # dersinnsspace Steam iron
    "bubble": "127540_1777005",         # romulofs    Bubbling
    "boil": "248296_1900515",           # Ezcah       Water Boiling Strong
    "scissors": "546366_12222745",      # PanosA      Snip with scissor
    "scissors2": "436768_7085413",      # Kiyoshiakira scissors quick cut
    "trunk": "271377_4709749",          # OverlookHotelRecords Opening Antique Trunk - More Latches
    "dresser": "797575_13973196",       # Vrymaa      Furniture Door - Open close
    "chair": "547466_12275732",         # JK129645    rocking chair creak
    "box": "676420_283869",             # arduenn     Little Wooden Box Opening And Closing
    "plush": "831458_18047279",         # Artistic_Dragonborn Plushy Plop
    "bell": "739753_13973196",          # Vrymaa      Bell - Japanese, small
    "grab": "846612_9603502",           # Takimeko    Clothes/Fabric Grab
    "rustle": "850705_9616576",         # IENBA       Soft Fabric Rustle
}

# 使う区間 [元, 始め, 終わり]（秒）
PICKS = {
    "till_patch": [("register_a", 1.537, 3.469), ("register_b", 2.509, 4.363), ("register_c", 69.855, 71.3)],
    "till_snow": [("register_b", 9.814, 11.67), ("register_c", 105.15, 106.554), ("register_a", 10.331, 11.445)],
    "wrap_paper": [("wrap", 7.684, 9.075), ("wrap", 9.263, 10.6), ("wrap", 0.17, 1.6)],
    "wrap_bag": [("bag", 0.416, 1.7), ("bag", 9.158, 10.345), ("bag", 6.755, 8.13)],
    "wrap_tissue": [("crumple", 1.461, 2.239), ("crumple", 4.63, 5.072), ("crumple", 2.239, 3.1)],
    "sew_run": [("sew_old", 62.5, 67.0)],
    "sizzle": [("sizzle", 10.916, 13.099), ("sizzle", 2.183, 4.366), ("sizzle", 7.641, 9.824)],
    "iron_hiss": [("iron", 8.218, 9.147), ("iron", 9.147, 10.875), ("iron", 17.273, 19.273)],
    "press_hiss": [("iron2", 7.43, 9.43)],
    "bubble": [("bubble", 0.0, 5.0)],
    "boil": [("boil", 2.25, 6.75)],
    "pour": [("pour", 2.015, 4.003), ("pour", 0.3, 2.015)],
    "snip": [("scissors2", 0.603, 0.85), ("scissors2", 1.042, 1.29), ("scissors", 9.302, 9.575)],
    "latch": [("trunk", 8.068, 8.31), ("trunk", 17.053, 17.425), ("trunk", 1.705, 2.2)],
    "lid": [("trunk", 30.2, 30.602), ("trunk", 4.247, 4.735)],
    "clunk": [("dresser", 9.955, 10.3), ("dresser", 11.12, 11.817), ("dresser", 2.063, 2.935)],
    "door_creak": [("dresser", 8.042, 9.095), ("dresser", 5.956, 7.41)],
    "creak": [("chair", 0.137, 1.86)],
    "box": [("box", 8.973, 9.235), ("box", 13.685, 14.075), ("box", 10.006, 10.57)],
    "plop": [("plush", 20.992, 21.25), ("plush", 18.694, 18.94), ("plush", 38.582, 38.85)],
    "bell": [("bell", 28.522, 29.395), ("bell", 18.053, 18.87), ("bell", 15.634, 16.065)],
    "fabric": [("grab", 3.095, 3.785), ("grab", 10.568, 11.025), ("grab", 5.391, 5.81)],
    "rustle": [("rustle", 6.291, 7.649), ("rustle", 1.693, 2.192)],
}

_cache = {}


def load(key):
    if key not in _cache:
        path = RAW / (FILES[key] + ".wav")
        if not path.exists():
            raise FileNotFoundError(f"{path} がない。sound/SOURCES.md の番号から落として wav にする（rec.py の頭の説明）")
        sr, x = wavfile.read(path)
        x = x.astype(np.float64) / 32768.0
        if x.ndim > 1:
            x = x.mean(axis=1)
        if sr != SR:
            x = signal.resample_poly(x, SR, sr)
        _cache[key] = x
    return _cache[key]


def cut(key, t0, t1, low=80.0, high=None, fin=0.004, fout=0.03):
    """[t0, t1) を切り、low より低い唸りを落とし（high があれば高い方も）、頭と尾をなだらかにし、ピークを 1 にそろえる"""
    x = load(key)[int(t0 * SR):int(t1 * SR)].copy()
    x = hp(x, low, 2)
    if high:
        x = lp(x, high, 2)
    a, b = n_of(fin), n_of(fout)
    x[:a] *= ramp(a, "hann_in")
    x[-b:] *= ramp(b, "hann_out")
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


def pick(name, i=0, **kw):
    key, t0, t1 = PICKS[name][i % len(PICKS[name])]
    return cut(key, t0, t1, **kw)


def speed(x, k):
    """速さと高さを k 倍に（小さなレジを、大きなレジの録音から作る）"""
    n = int(len(x) / k)
    return signal.resample(x, n) if n > 0 else x


def stitches(count=6, gap_min=0.15):
    """ゆっくり回るミシン（sew_slow）の録音から、1 目ずつの「カタン」を、前後のすき間が gap_min 秒より長いものから強い順に切る"""
    x = hp(load("sew_slow"), 120, 2)
    env = np.sqrt(np.maximum(signal.sosfilt(signal.butter(2, 40, fs=SR, output="sos"), x * x), 0))
    peaks, props = signal.find_peaks(env, distance=int(gap_min * SR), prominence=np.percentile(env, 90))
    order = np.argsort(props["prominences"])[::-1]
    out = []
    for i in order:
        t = peaks[i] / SR
        if t < 0.1 or t > len(x) / SR - 0.3:
            continue
        s = cut("sew_slow", t - 0.03, t + 0.17, low=120, fin=0.003, fout=0.06)
        out.append(s)
        if len(out) >= count:
            break
    return out
