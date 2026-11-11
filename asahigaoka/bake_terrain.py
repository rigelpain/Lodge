"""旭ヶ丘スキー場（北海道 倶知安町）のワールドの地形を、国土地理院の標高タイルから焼く（天下森の台本を写した物）。

  python bake_terrain.py <タイルを置くフォルダ> <OSM の JSON のフォルダ>

出すもの（game/asahigaoka/）:
  near.bin  近くの地面。当たり判定と見た目。2 m おき 513 点四方（1024 m）。標高 1 m（航空レーザの dem1a、z17。欠けは 5 m の dem5a、10 m の dem で埋める。
            ゲレンデの斜面は dem5a が欠けていて、10 m では段々になった）
  mid.bin   羊蹄山までの山なみ。見た目だけ。24 m おき 667 点四方（16 km）。標高 10 m（dem z14、欠けは z12）
  far.bin   地平線までの山なみ。見た目だけ。96 m おき 401 点四方（38 km）。標高 30 m 相当（dem の z12）
  road.bin  道と駐車場の濃さ。near と同じ 2 m おき 513 点四方の uint8（0〜255）。見た目で踏み固めた雪の色にする
  piste.bin ゲレンデの雪面（圧雪の筋を描く所）の濃さ。near と同じ 2 m おき 513 点四方の uint8
  forest.bin 林の濃さ。clear.bin と同じ 4 m おき 256 点四方の uint8。国土地理院のシームレス空中写真（z17）で、暗い緑の所を林と見る
            （2026-11-09: OSM のスキー場の囲いが林間コースのまわりの林まで含んでいて、林間コースが開けて見えた。写真の林のとおりに木を立てる）
  clear.bin 木を立ててよい所。4 m おき 256 点四方の uint8。0 = 立てない（ゲレンデの中・リフトの下・道・建物）、
            1〜255 = ゲレンデの囲いからの距離 (m) + 1
  map.json  ゲレンデの囲い・コース・リフト・ロッジの形（OpenStreetMap）。遊びの座標で
どれも float32 の高さを、北の行から（z の小さい行から）、西から東へ並べる。

遊びの座標: 原点 = リフトの乗り場（OSM way 315744004 の低い端）。x = 東 (m)、z = 南 (m)。高さ = 標高 - BASE（乗り場の標高）。
遠くは地球の丸みと大気の屈折で下げる（見かけの半径 = 地球の半径 / (1 - 0.13)）。
"""
import json, math, os, sys, urllib.request
import numpy as np
from PIL import Image

TILES, OSMDIR = sys.argv[1], sys.argv[2]
PHOTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "photo")   # 空中写真は 17_x_y.jpg の名前でここにもある
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "asahigaoka")
LAT0, LON0 = 42.9018597, 140.7372343
BASE = 193.2   # 乗り場の標高（航空レーザの dem1a で読んだ値。降り場は 285.8 で、差 92.6 m）
MY = 111132.954 - 559.822 * math.cos(2 * math.radians(LAT0))
MX = 111412.84 * math.cos(math.radians(LAT0))
R_EFF = 6371000.0 / (1.0 - 0.13)

NEAR = dict(x0=-600.0, z0=-650.0, step=2.0, n=513)
MID = dict(x0=-4400.0, z0=-2400.0, step=24.0, n=676)     # 南南東 10 km の羊蹄山（頂は x=+6100, z=+8400）をすっぽり入れる
FAR = dict(x0=-19200.0, z0=-19200.0, step=96.0, n=401)


def to_ll(x, z):
    return LAT0 - z / MY, LON0 + x / MX


def fetch(name, z, x, y):
    p = os.path.join(TILES, f"{name}_{z}_{x}_{y}.png")
    if not os.path.exists(p):
        url = f"https://cyberjapandata.gsi.go.jp/xyz/{name}/{z}/{x}/{y}.png"
        req = urllib.request.Request(url, headers={"User-Agent": "lodge-terrain-bake"})
        try:
            data = urllib.request.urlopen(req, timeout=30).read()
        except Exception:
            return None
        open(p, "wb").write(data)
    a = np.asarray(Image.open(p).convert("RGB")).astype(np.int64)
    v = a[..., 0] * 65536 + a[..., 1] * 256 + a[..., 2]
    h = (np.where(v < 2**23, v, v - 2**24) * 0.01).astype(float)
    h[v == 2**23] = np.nan
    return h


def sample(name, zoom, lat, lon):
    """タイルの標高を双一次で読む。欠けは nan"""
    n = 2**zoom
    fx = (lon + 180) / 360 * n * 256 - 0.5
    fy = (1 - np.arcsinh(np.tan(np.radians(lat))) / np.pi) / 2 * n * 256 - 0.5
    tx0, tx1 = int(np.floor(fx.min() / 256)), int(np.floor((fx.max() + 1) / 256))
    ty0, ty1 = int(np.floor(fy.min() / 256)), int(np.floor((fy.max() + 1) / 256))
    M = np.full(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), np.nan)
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            h = fetch(name, zoom, tx, ty)
            if h is not None:
                M[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = h
    px = fx - tx0 * 256
    py = fy - ty0 * 256
    i = np.clip(np.floor(py).astype(int), 0, M.shape[0] - 2)
    j = np.clip(np.floor(px).astype(int), 0, M.shape[1] - 2)
    a, b = py - i, px - j
    return M[i, j] * (1 - a) * (1 - b) + M[i, j + 1] * (1 - a) * b + M[i + 1, j] * a * (1 - b) + M[i + 1, j + 1] * a * b


def grid(g):
    xs = g["x0"] + np.arange(g["n"]) * g["step"]
    zs = g["z0"] + np.arange(g["n"]) * g["step"]
    return np.meshgrid(xs, zs)


def blur(H, sigma_px):
    if sigma_px <= 0:
        return H
    r = int(math.ceil(sigma_px * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma_px) ** 2)
    k /= k.sum()
    P = np.pad(H, r, mode="edge")
    P = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 1, P)
    P = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 0, P)
    return P


def fill(H, *others):
    for o in others:
        m = np.isnan(H)
        H[m] = o[m]
    return H


def curve(X, Z, H):
    d2 = X * X + Z * Z
    return H - d2 / (2.0 * R_EFF)


LODGE_ID = 194877602   # ロッジ（休憩所「雪ん子館」と思われる建物）の way
ROAD_KINDS = ("primary", "secondary", "tertiary", "unclassified", "residential", "service")


def polys():
    osm = json.load(open(os.path.join(OSMDIR, "osm.json")))
    bld = json.load(open(os.path.join(OSMDIR, "bld.json")))
    def xz(p):
        return [round((p["lon"] - LON0) * MX, 2), round(-(p["lat"] - LAT0) * MY, 2)]
    out = {"pistes": [], "lifts": [], "area": None, "hutte": None, "lodge": None, "buildings": [], "roads": [], "parking": []}
    for e in osm["elements"]:
        t = e.get("tags", {})
        g = [xz(p) for p in e["geometry"]]
        if t.get("landuse") == "winter_sports":
            out["area"] = g
        elif t.get("aerialway"):
            out["lifts"].append({"kind": t["aerialway"], "name": t.get("name", ""), "line": g})
        elif t.get("piste:type") in ("downhill", "nordic"):
            out["pistes"].append({"name": t.get("name", ""), "level": t.get("piste:difficulty", ""), "kind": t["piste:type"], "line": g})
    # リフトの線は、乗り場（低い端）→ 降り場（高い端）の順にそろえる
    for l in out["lifts"]:
        la, lo = to_ll(np.array([l["line"][0][0], l["line"][-1][0]]), np.array([l["line"][0][1], l["line"][-1][1]]))
        h = fill(sample("dem1a_png", 17, la, lo), sample("dem5a_png", 15, la, lo), sample("dem_png", 14, la, lo))
        if h[0] > h[-1]:
            l["line"] = l["line"][::-1]
    for e in bld["elements"]:
        t = e.get("tags", {})
        g = [xz(p) for p in e["geometry"]]
        if e["id"] == LODGE_ID:
            out["lodge"] = g
        elif t.get("building"):
            out["buildings"].append(g)
        elif t.get("amenity") == "parking":
            out["parking"].append(g)
        elif t.get("highway") in ROAD_KINDS:   # path・footway・track・cycleway は道に入れない
            out["roads"].append({"kind": t["highway"], "line": g})
    return out


def inside_plain(poly, X, Z):
    P = np.array(poly)
    res = np.zeros(X.shape, bool)
    for k in range(len(P) - 1):
        (x1, z1), (x2, z2) = P[k], P[k + 1]
        c = ((z1 > Z) != (z2 > Z)) & (X < (x2 - x1) * (Z - z1) / ((z2 - z1) if z2 != z1 else 1e-9) + x1)
        res ^= c
    return res


def dense_points(line, every=2.0):
    P = np.array(line, float)
    out = [P[0]]
    for k in range(len(P) - 1):
        n = max(1, int(np.linalg.norm(P[k + 1] - P[k]) / every))
        out += [P[k] + (P[k + 1] - P[k]) * q / n for q in range(1, n + 1)]
    return np.array(out)


def dist_to(pts, X, Z):
    D = np.full(X.shape, np.inf)
    for c in range(0, len(pts), 200):
        q = pts[c:c + 200]
        d = np.hypot(X[..., None] - q[:, 0], Z[..., None] - q[:, 1]).min(-1)
        D = np.minimum(D, d)
    return D


def forest_mask():
    """空中写真の林（0〜1）。clear.bin と同じ格子"""
    s, n = 4.0, 256
    z = 17
    nt = 2 ** z
    def px(lat, lon):
        return (lon + 180) / 360 * nt * 256, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * nt * 256
    x0, y0 = px(*to_ll(NEAR["x0"], NEAR["z0"]))
    x1, y1 = px(*to_ll(NEAR["x0"] + n * s, NEAR["z0"] + n * s))
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    W = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            p = os.path.join(TILES, f"seamlessphoto_{z}_{tx}_{ty}.jpg")
            if not os.path.exists(p) and os.path.exists(os.path.join(PHOTO, f"{z}_{tx}_{ty}.jpg")):
                p = os.path.join(PHOTO, f"{z}_{tx}_{ty}.jpg")
            if not os.path.exists(p):
                req = urllib.request.Request(f"https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{tx}/{ty}.jpg", headers={"User-Agent": "lodge-terrain-bake"})
                try:
                    open(p, "wb").write(urllib.request.urlopen(req, timeout=30).read())
                except Exception:
                    continue
            W.paste(Image.open(p).convert("RGB"), ((tx - tx0) * 256, (ty - ty0) * 256))
    W = W.crop((int(x0 - tx0 * 256), int(y0 - ty0 * 256), int(x1 - tx0 * 256), int(y1 - ty0 * 256))).resize((n * 4, n * 4))
    a = np.asarray(W).astype(float)
    bright = a.mean(axis=2)
    f = ((bright < 92) & (a[..., 1] >= a[..., 0] - 2)).astype(float)
    f = f.reshape(n, 4, n, 4).mean(axis=(1, 3))
    return blur(f, 1.0)


def clear_mask(m):
    s = 4.0
    xs = NEAR["x0"] + np.arange(256) * s + s / 2
    zs = NEAR["z0"] + np.arange(256) * s + s / 2
    X, Z = np.meshgrid(xs, zs)
    D = dist_to(dense_points(m["area"]), X, Z)
    out = np.clip(D + 1, 1, 255)
    # スキー場の囲いの中でも、林は空中写真のとおり（forest.bin）
    out[inside_plain(m["area"], X, Z)] = 1
    for l in m["lifts"]:
        out[dist_to(dense_points(l["line"]), X, Z) < 8.0] = 0
    for r in m["roads"]:
        out[dist_to(dense_points(r["line"]), X, Z) < 7.0] = 0
    # ゲレンデの小物（game/asahi_slope.gd）のまわり: ジャンプ台の櫓と助走路、小さな台、審判の櫓 2 つ
    for cx, cz, r in ((-222, -215, 13), (-213, -208, 11), (-205, -201, 9), (-134, -186, 9), (-130, -181, 8), (-45, -105, 6), (-30, -88, 6)):
        out[np.hypot(X - cx, Z - cz) < r] = 0
    for b in m["buildings"] + ([m["lodge"]] if m["lodge"] else []) + m.get("parking", []):
        out[dist_to(dense_points(b), X, Z) < 7.0] = 0
        out[inside_plain(b, X, Z)] = 0
    return out.astype(np.uint8)


PAD_PAD = 4.0
PAD_BLEND = 12.0
STATION = {"bottom": ((0.0, 0.0), 14.0, 9.0)}   # 乗り場: まんなか、長さ、幅。降り場は線の最後の点（下で足す）
STATION_TOP = (12.0, 8.0)


def rect(c, length, wide, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    pts = []
    for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1), (-1, -1)):
        x, z = u * length / 2, v * wide / 2
        pts.append([round(c[0] + x * ca - z * sa, 2), round(c[1] + x * sa + z * ca, 2)])
    return pts


def pads(m, X, Z, H):
    """ならす所: [名前, 囲い, 高さ]。高さは囲いの中の地面の高さの中ほど"""
    out = []
    polys = []
    lift = np.array(m["lifts"][0]["line"]) if m["lifts"] else None
    if lift is not None:
        d = lift[-1] - lift[0]
        la = math.atan2(d[1], d[0])
        polys.append(("lift_bottom", rect(tuple(lift[0]), STATION["bottom"][1], STATION["bottom"][2], la)))
        polys.append(("lift_top", rect(tuple(lift[-1]), STATION_TOP[0], STATION_TOP[1], la)))
    if m["lodge"]:
        polys.append(("lodge", m["lodge"]))
    for key, poly in polys:
        ins = inside_plain(poly, X, Z)
        y = float(np.median(H[ins])) if ins.any() else 0.0
        out.append((key, poly, y))
    return out


ROAD_W = {"primary": 8.0, "secondary": 7.0, "tertiary": 6.0, "unclassified": 5.0, "residential": 4.0, "service": 4.5}   # 道の幅 (m)
ROAD_BLEND = 4.0      # 道の縁から地面へ戻す幅 (m)
BANK_H = 0.9          # 除雪で道の脇に積んだ雪の壁の高さ (m)
BANK_AT = 1.2         # 道の縁から雪の壁の頂までの距離 (m)
BANK_W = 1.0          # 雪の壁の広がり σ (m)
PARK_BLEND = 5.0


def roads_and_parking(m, X, Z, H):
    """道: 中心の線の高さを 20 m の長さでならし、幅の中を平らに、縁の外に雪の壁。駐車場: 中を平らに（高さの中ほど）。
    戻り値: ならした高さ、道と駐車場の濃さ（0〜1）"""
    mask = np.zeros(X.shape)
    target = np.zeros(X.shape)
    wsum = np.zeros(X.shape)
    bank = np.zeros(X.shape)
    for r in m["roads"]:
        w = ROAD_W.get(r["kind"])
        if not w:
            continue
        pts = dense_points(r["line"], 2.0)
        sel = (pts[:, 0] > X.min() - 20) & (pts[:, 0] < X.max() + 20) & (pts[:, 1] > Z.min() - 20) & (pts[:, 1] < Z.max() + 20)
        if sel.sum() < 2:
            continue
        # 中心の線の高さ（近い格子から読んで、長さ 20 m でならす）
        ii = np.clip(((pts[:, 1] - Z[0, 0]) / (Z[1, 0] - Z[0, 0])).round().astype(int), 0, X.shape[0] - 1)
        jj = np.clip(((pts[:, 0] - X[0, 0]) / (X[0, 1] - X[0, 0])).round().astype(int), 0, X.shape[1] - 1)
        hc = H[ii, jj]
        k = np.ones(11) / 11
        hc = np.convolve(np.pad(hc, 5, mode="edge"), k, "valid")
        # 各格子の、いちばん近い中心の点と距離（近い所だけ）
        x0, x1 = pts[:, 0].min() - w - 10, pts[:, 0].max() + w + 10
        z0, z1 = pts[:, 1].min() - w - 10, pts[:, 1].max() + w + 10
        box = (X > x0) & (X < x1) & (Z > z0) & (Z < z1)
        bx, bz = X[box], Z[box]
        best = np.full(bx.shape, np.inf)
        bh = np.zeros(bx.shape)
        for c in range(0, len(pts), 100):
            q = pts[c:c + 100]
            d = np.hypot(bx[:, None] - q[:, 0], bz[:, None] - q[:, 1])
            a = d.argmin(1)
            dm = d[np.arange(len(bx)), a]
            better = dm < best
            best[better] = dm[better]
            bh[better] = hc[c + a[better]]
        half = w / 2
        wt = np.clip(1 - (best - half) / ROAD_BLEND, 0, 1)
        wt = wt * wt * (3 - 2 * wt)
        m_road = (best <= half + 0.5).astype(float) * np.clip(1 - (best - half) / 0.5, 0, 1)
        mask[box] = np.maximum(mask[box], np.where(best <= half, 1.0, m_road))
        target[box] += bh * wt
        wsum[box] += wt
        bank[box] = np.maximum(bank[box], BANK_H * np.exp(-0.5 * ((best - half - BANK_AT) / BANK_W) ** 2) * (best > half))
    for poly in m.get("parking", []):
        ins = inside_plain(poly, X, Z)
        if not ins.any():
            continue
        y = float(np.median(H[ins]))
        d = np.where(ins, 0.0, dist_to(dense_points(poly), X, Z))
        wt = np.clip(1 - d / PARK_BLEND, 0, 1)
        wt = wt * wt * (3 - 2 * wt)
        target += y * wt * 4.0      # 駐車場は道より強く平らに
        wsum += wt * 4.0
        mask = np.maximum(mask, ins.astype(float))
        bank = np.where(ins, 0.0, bank)
    flat = np.where(wsum > 0, target / np.maximum(wsum, 1e-6), H)
    w_all = np.clip(wsum, 0, 1)
    H2 = H * (1 - w_all) + flat * w_all
    bank = bank * (1 - mask)
    return H2 + bank, mask


YOTEI = (6100.0, 8400.0)   # 羊蹄山の頂（遊びの座標）


def add_play_points(m):
    """遊びの座標: 始める所・向く所・スタート画面のカメラ"""
    lodge = np.array(m["lodge"][:-1], float)
    # ロッジの囲いのリフトの側（西）の辺の真ん中から、外（西）へ 6 m
    best = None
    for k in range(len(lodge)):
        a, b = lodge[k], lodge[(k + 1) % len(lodge)]
        mid = (a + b) / 2
        e = b - a
        nrm = np.array([e[1], -e[0]]) / np.linalg.norm(e)
        if nrm[0] > 0:
            nrm = -nrm
        if best is None or mid[0] + 20 * nrm[0] < best[0]:
            best = (mid[0] + 20 * nrm[0], mid, nrm)
    _, mid, nrm = best
    sx, sz = mid + nrm * 6.0
    m["start"] = [round(float(sx), 2), round(float(sz), 2)]
    m["look"] = [0.0, 0.0]
    # スタート画面: リフトの線の真ん中から、ゲレンデの側へ 30 m。羊蹄山の頂を見る
    L = np.array(m["lifts"][0]["line"], float)
    seg = np.hypot(*np.diff(L, axis=0).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    half = cum[-1] / 2
    k = int(np.searchsorted(cum, half)) - 1
    t = (half - cum[k]) / seg[k]
    c = L[k] + (L[k + 1] - L[k]) * t
    d = (L[-1] - L[0]) / np.linalg.norm(L[-1] - L[0])
    side = np.array([-d[1], d[0]])
    # 広いゲレンデはリフトの線の北東の側（空中写真。南西の側は林の島で、OSM の downhill の線はその向こうを回る細いコース）
    if side[0] - side[1] < 0:
        side = -side
    cam = c + side * 35.0
    m["start_view"] = [round(float(cam[0]), 2), round(float(cam[1]), 2), round(YOTEI[0] - float(cam[0]), 1), round(YOTEI[1] - float(cam[1]), 1), -40]


def main():
    os.makedirs(OUT, exist_ok=True)
    m = polys()
    add_play_points(m)
    json.dump(m, open(os.path.join(OUT, "map.json"), "w"), ensure_ascii=False, indent=1)
    cm = clear_mask(m)
    cm.tofile(os.path.join(OUT, "clear.bin"))
    fm = forest_mask()
    (np.clip(fm, 0, 1) * 255).astype(np.uint8).tofile(os.path.join(OUT, "forest.bin"))
    print("forest", (fm > 0.5).mean())
    print("clear", (cm > 0).mean())

    # 近く: 5 m → 10 m で埋める。道路の切り土などの細かい段は雪がならすので、全体を σ 2 m、ゲレンデの中は σ 5 m でならす
    X, Z = grid(NEAR)
    la, lo = to_ll(X, Z)
    H = fill(sample("dem1a_png", 17, la, lo), sample("dem5a_png", 15, la, lo), sample("dem_png", 14, la, lo)) - BASE
    print("near 欠け", np.isnan(H).mean())
    H = np.nan_to_num(H, nan=np.nanmin(H))
    soft = blur(H, 1.0)
    softer = blur(H, 2.5)
    area = inside_plain(m["area"], X, Z).astype(float)
    w = blur(area, 6.0)
    H = soft * (1 - w) + softer * w
    piste = inside_plain(m["area"], X, Z).astype(float)
    H, road = roads_and_parking(m, X, Z, H)
    (np.clip(piste * (1 - road), 0, 1) * 255).astype(np.uint8).tofile(os.path.join(OUT, "piste.bin"))
    print("piste", (piste > 0.5).mean())
    (np.clip(road, 0, 1) * 255).astype(np.uint8).tofile(os.path.join(OUT, "road.bin"))
    print("road", (road > 0.5).mean())
    # ロッジとリフトの乗り場・降り場の足もとをならす（囲いの外 PAD_PAD m まで平ら、そこから PAD_BLEND m で地面へ戻す）
    for key, poly, y in pads(m, X, Z, H):
        d = np.full(X.shape, np.inf)
        ins = inside_plain(poly, X, Z)
        d[ins] = 0
        out = ~ins
        d[out] = dist_to(dense_points(poly), X[out], Z[out])
        w = np.clip((d - PAD_PAD) / PAD_BLEND, 0, 1)
        w = w * w * (3 - 2 * w)
        H = H * w + y * (1 - w)
        m.setdefault("pads", {})[key] = {"y": round(float(y), 2), "poly": poly}
        print("pad", key, round(float(y), 2))
    json.dump(m, open(os.path.join(OUT, "map.json"), "w"), ensure_ascii=False, indent=1)
    near = H.astype(np.float32)
    near.tofile(os.path.join(OUT, "near.bin"))
    print("near", near.shape, near.min(), near.max())

    X, Z = grid(MID)
    la, lo = to_ll(X, Z)
    H = fill(sample("dem_png", 14, la, lo), sample("dem_png", 12, la, lo)) - BASE
    H = np.nan_to_num(H, nan=np.nanmin(H))
    H = curve(X, Z, H)
    mid = H.astype(np.float32)
    mid.tofile(os.path.join(OUT, "mid.bin"))
    print("mid", mid.shape, mid.min(), mid.max())

    X, Z = grid(FAR)
    la, lo = to_ll(X, Z)
    H = sample("dem_png", 12, la, lo) - BASE
    H = np.nan_to_num(H, nan=np.nanmin(H))
    H = curve(X, Z, H)
    far = H.astype(np.float32)
    far.tofile(os.path.join(OUT, "far.bin"))
    print("far", far.shape, far.min(), far.max())


if __name__ == "__main__":
    main()
