"""天下森の雪面に、こぶとうねりを足す（2026-11-12 代表「天下森もロッジも起伏増やしたいね」）。

  python3.11 -I tenkamori/add_snow_relief.py        （作業場所の直下から）

天下森の地形は 2026-11-09 に焼いたきりで、焼き直しに要る OSM の JSON が手元に残っていない。なので焼いた地面（near.bin）に、
旭ヶ丘と同じ起伏（asahigaoka/bake_terrain.py の snow_relief・RELIEF）を足す。足す前の地面は tenkamori/near_base.bin に取っておき
（無ければ今の near.bin を写す）、何度走らせても足すのは 1 回分。bake_terrain.py で焼き直したら、near_base.bin を消してからこれを走らせる。

足す所: 林でない雪面（forest.bin）。ゲレンデ（piste.bin）は全部、ほかの開けた所は半分。道・駐車場（road.bin）と、ヒュッテ・リフトの
乗り場と降り場の足もと（map.json の pads）とそのまわり 6 m は足さない
"""
import json, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
G = os.path.join(HERE, "..", "game", "tenkamori")
X0, Z0, STEP, N = -650.0, -150.0, 2.0, 513
RELIEF = [(40.0, 0.55, 3), (16.0, 0.20, 4), (8.0, 0.18, 5)]   # 旭ヶ丘と同じ（波長 m, 高さ m, 数）


def blur(H, s):
    r = int(np.ceil(s * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    k /= k.sum()
    P = np.pad(H, r, mode="edge")
    P = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 1, P)
    return np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 0, P)


def inside(poly, X, Z):
    P = np.array(poly)
    res = np.zeros(X.shape, bool)
    for k in range(len(P) - 1):
        (x1, z1), (x2, z2) = P[k], P[k + 1]
        c = ((z1 > Z) != (z2 > Z)) & (X < (x2 - x1) * (Z - z1) / ((z2 - z1) if z2 != z1 else 1e-9) + x1)
        res ^= c
    return res


def main():
    base_p = os.path.join(HERE, "near_base.bin")
    near_p = os.path.join(G, "near.bin")
    if not os.path.exists(base_p):
        np.fromfile(near_p, dtype=np.float32).tofile(base_p)
    H = np.fromfile(base_p, dtype=np.float32).reshape(N, N).astype(float)
    xs = X0 + np.arange(N) * STEP
    zs = Z0 + np.arange(N) * STEP
    X, Z = np.meshgrid(xs, zs)
    rnd = np.random.default_rng(7)
    R = np.zeros(X.shape)
    for lam, amp, n in RELIEF:
        part = np.zeros(X.shape)
        for _ in range(n):
            a = rnd.uniform(0, np.pi)
            k = 2 * np.pi / (lam * rnd.uniform(0.8, 1.25))
            part += np.cos(k * (X * np.cos(a) + Z * np.sin(a)) + rnd.uniform(0, 2 * np.pi))
        R += amp * part / np.sqrt(n)
    f4 = np.fromfile(os.path.join(G, "forest.bin"), dtype=np.uint8).reshape(256, 256) / 255.0
    f = np.repeat(np.repeat(f4, 2, axis=0), 2, axis=1)
    f = np.pad(f, ((0, N - f.shape[0]), (0, N - f.shape[1])), mode="edge")[:N, :N]
    piste = np.fromfile(os.path.join(G, "piste.bin"), dtype=np.uint8).reshape(N, N) / 255.0
    road = np.fromfile(os.path.join(G, "road.bin"), dtype=np.uint8).reshape(N, N) / 255.0
    w = np.clip(1.0 - f * 1.4, 0.0, 1.0) * (0.5 + 0.5 * piste)
    w *= 1.0 - np.clip(road * 1.5, 0, 1)
    m = json.load(open(os.path.join(G, "map.json")))
    keep = np.zeros(X.shape)
    for key, pad in m.get("pads", {}).items():
        keep = np.maximum(keep, inside(pad["poly"], X, Z).astype(float))
    keep = np.clip(blur(keep, 3.0) * 2.5, 0, 1)   # 足もとのまわり 6 m ほどもなだらかに 0 へ
    w = blur(w, 2.0) * (1.0 - keep)
    out = (H + R * w).astype(np.float32)
    out.tofile(near_p)
    print("足した起伏: いちばん %.2f m、ゲレンデの 1〜99%% の幅 %.2f m" % (np.abs(R * w).max(), np.percentile((R * w)[piste > 0.5], 99) - np.percentile((R * w)[piste > 0.5], 1)))


if __name__ == "__main__":
    main()
