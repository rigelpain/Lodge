# 旭ヶ丘のワールド（2026-11-11）

北海道 倶知安町の旭ヶ丘スキー場（町営・ペアリフト 1 基）を、本物の標高で起こしたワールド。天下森（`../tenkamori/README.md`）と同じやり方で作り、スタート画面の 3 枚目の札で選ぶ。

代表「倶知安町旭ヶ丘スキー場ステージを作りましょう。横手市天下森スキー場ステージのできが良いので、同様の方法で」

- ゲームの側: `game/tenkamori.gd` を本物の地形のワールドの共通にした（`SITES` に場所ごとの格子・林の割合・霧。`use()` で選ぶ）。`game/main.gd` の `WORLDS` に `asahigaoka`、`tenka()` は「本物の地形のワールド」の意味に。リフトは `game/tenkamori_lift.gd` をそのまま使う（`map.json` の lifts と pads を読む）
- 焼いた表: `game/asahigaoka/`（`bake_terrain.py` が書く）
- 確かめ: `game/tools/asahi_views.gd`（リフトの線から決めた所で撮る）。絵は `design/asahigaoka/01-views.jpg`、空中写真にリフト（赤）・コース（水色）・囲い（青）・休憩所（桃）・林（白い点）を重ねた絵は `02-photo-map.jpg`

## 焼き直し

```bash
python3.11 -I asahigaoka/bake_terrain.py asahigaoka/tiles asahigaoka/osm
```

タイルは無ければ国土地理院から取る（`asahigaoka/tiles/`。git には入れない）。

## 決めたこと

- 座標: 原点 = ペアリフトの乗り場（北緯 42.90186・東経 140.73723）、x = 東、z = 南。高さ = 標高 − 193.2 m。大きさは本物のまま（リフト 340 m、高さの差 93 m、乗って 179 秒）
- 近く（1024 m 四方、2 m おき）: 航空レーザの 1 m の標高（dem1a）。5 m の標高（dem5a）はゲレンデの斜面が欠けていて、10 m では段々になった
- 景色の主役は南南東 10.4 km の羊蹄山。谷の向かい（mid）を 24 m おき 16 km 四方で南東へ広くとる。霧は天下森より薄く（10 km 先が霞みすぎない）
- 林の塗り: 平野（町と畑）より高い所は、なだらかでも林（羊蹄山の裾）。森林限界（標高 900〜1350 m）から上は雪だけ。杉の植林でなく葉の落ちた広葉樹が多いので、針葉樹の割合を下げ、雑木の灰を濃くした
- 主コースはリフトの線の北東の側。南西の側は林の島で、その向こう（乗り場の南西）に初級コースの広い斜面が開け、南の一角がそりコース。主コースと初級コースが、林の島をはさんで V 字に見えるのが、ロッジから見たこのスキー場の形（2026-11-11 代表「ソリコースなくない？…ロッジから見える V 字の坂が特徴的なのに」）。夏の空中写真ではこの斜面が濃い緑の草地で、林と読み違えて木で埋めていたので、囲い（`bake_terrain.py` の `BEGINNER`）の中は木を払う。OSM の downhill の線は、降り場から西へ回ってこの斜面へ下りる初級コース
- 始める所: 休憩所（雪ん子館と思われる建物）の西の辺の外。建物はまだ無く、足もとだけならしてある

## 見取り図と図面（2026-11-11。代表に見せて、よければこれで組む）

手本の動画のコマ・写真を並べた絵（下の `slope/01-slope-map.png`・`slope/02-compare.jpg`・`lodge/01-plans.png`・`lodge/02-compare.jpg`・`trees/00-reference.jpg`・`trees/01-bare-tree-ideas.jpg`・`trees/02-compare.jpg`・`slope/03-v-compare.jpg`）は、第三者の動画のコマを含むので、公開リポジトリには入れていない（`.gitignore`。手元の作業場所にだけある）。

- ゲレンデの見取り図: `design/asahigaoka/slope/01-slope-map.png`（`draw_slope_map.py`）。乗り場・柱・降り場・ジャンプ台の櫓・ネット・照明・2 本のコース・そりの広場・休憩所・駐車場・林
- 休憩所「雪ん子館」の図面: `design/asahigaoka/lodge/01-plans.png`（寸法は `lodge_dims.py`、描くのは `draw_lodge_plans.py`）。棟の場所・駐車場の側の壁・中の柱は推しはかり
- 葉の落ちた木（2026-11-11 代表「①②③ で入れて」）: 案の絵 `design/asahigaoka/trees/01-bare-tree-ideas.jpg`、手本と並べた絵 `02-compare.jpg`。台本は `props/build_bare_tree.py`（書き出しは `--look flat --export game/props`。1 本 約 520 三角）。雑木（毛糸を巻いた枝）・シラカバ（白いフェルトの幹に黒い糸の縫い目）・カラマツ（フェルトの幹に毛糸の枝を段々に）。植え方は `game/tenkamori.gd` の `_trees`（`BARE`）: 空中写真の林に 3.7 m おき、開けた所の縁はシラカバを多く、大きな斑の濃い所はカラマツ、ほかは雑木、針葉樹は 3%。④ フェルトの切り抜きは見送り
- 木の見え方の比べ: `design/asahigaoka/trees/00-reference.jpg`。本物は葉の落ちた木（カラマツ・シラカバ）がほとんどで、いまのゲームは緑の針葉樹だけ

## 作り込み（2026-11-11 代表「これで作って」）

- リフト（`game/tenkamori_lift.gd` の `STYLES`）: 旭ヶ丘は赤茶の鉄骨の乗り場と柱・灰の腕木、椅子は灰のパイプに黒い座面で前の手すりなし。乗り場の上の機械小屋は無く、板張りの運転室はゲレンデの側。降り場の脇に小さな木の小屋。天下森は今までのまま
- ゲレンデの小物（`game/asahi_slope.gd`）: リフト沿いと降り場のオレンジのネット、ナイターの照明の柱 15 本、ジャンプ台の櫓と助走路、小さな台、審判の櫓 2 つ、そりコースの仕切り（オレンジのネットとピンクの旗のポール）と入口のそりの絵の札、乗り場の札、石の看板。櫓と台のまわりは木を払う（`bake_terrain.py` の clear_mask）
- 休憩所「雪ん子館」（`game/asahi_lodge.gd`。寸法は `lodge_dims.py` の写し）: 大きな屋根と厚い雪、軒先の鉄の柱と木の梁、西の正面（灰のパネル・縦張りの木・背の高いガラス・白い庇の入口）、西と南のデッキ、南の壁いっぱいの窓、東の入口、中は一部屋（黒い鉄の柱・カウンター・長机）。入口の戸は開いたまま
  - 人が両方の入口から入れることは `game/tools/asahi_lodge_walk_check.gd` で確かめた（つかえた点 0）
- 手本と並べた絵: `design/asahigaoka/lodge/02-compare.jpg`、`design/asahigaoka/slope/02-compare.jpg`。撮るのは `game/tools/asahi_lodge_views.gd` と `asahi_views.gd`
- 箱の部品の面の向き: `tenkamori_lift.gd` の `box` は面が裏返しで、裏も描く素材だと陽の当たる面が陰の色になる。雪ん子館と小物は表を外へ向けた箱（`asahi_lodge.gd` の `_bx`）を使う。天下森の物は色を目で合わせてあるので直していない

## まだ無いもの

- 倶知安の町の家並み（建物の位置は `osm/town.json` に取ってある。約 6,800 棟）と、駐車場の車
- 乗り場の滑車の上の屋根の形（いまは天下森と同じ床と手すり）、ナイターの灯り（夜に光る）
- 雪ん子館の中の店や機械、入口の戸の開け閉め、駐車場の側の壁の確かな形
- 山をめぐる仲間（CPU）、雪のボタン（天下森と同じ）

## 出どころ（台帳）

| 使いみち | 中身 | 出どころ | 条件 |
|---|---|---|---|
| 地面の高さ（近く） | 基盤地図情報 数値標高モデル 1 m（標高タイル `dem1a_png`、z17）。欠けは `dem5a_png`（z15）、`dem_png`（z14） | 国土地理院 https://maps.gsi.go.jp/development/ichiran.html | 出典の記載: 「国土地理院の標高タイルを加工して作成」 |
| 羊蹄山・地平線 | 標高タイル `dem_png`（z14・z12） | 同上 | 同上 |
| ゲレンデの囲い・リフト・コース・建物・道（`osm/*.json`・`map.json`） | OpenStreetMap（Overpass API、2026-11-11 取得） | https://www.openstreetmap.org/ | ODbL 1.0。「© OpenStreetMap contributors」を載せる |
| 林の所（木を立てる所） | 国土地理院 シームレス空中写真（z17） | https://maps.gsi.go.jp/development/ichiran.html | 出典の記載。写真そのものはゲームに入れず、林の濃さの表（forest.bin）にする |
| 施設の事実（ペアリフト 1 基・2 コース・最長 560 m・最大 30 度・ナイター・休憩所「雪ん子館」） | 倶知安町の旭ケ丘スキー場のページ | https://www.town.kutchan.hokkaido.jp/culture-sports/sports-shisetsu/asahigaoka-ski/ | 見て読むだけ |
| ゲレンデ・休憩所・リフトの作り込みの手本（ゲームには入れない） | YouTube 6 本: 「旭ヶ丘スキー場◆ニセコだけどローカルゲレンデ！」https://www.youtube.com/watch?v=RDjgc2loGfI 、「ニセコじゃない倶知安町のスキー場に行ったら羊蹄山めっちゃキレイでした。」https://www.youtube.com/watch?v=DzKCk9QjJkc 、ほか 4 本（F4Is5ZsEzGw・2CoO1JFa5Bo・2Y3oWnGmc10・G8lcEZpPFpI）。町の公式ページ・個人ブログの写真 | 代表「資料は無いので YouTube 動画とかから持ってきて」（2026-11-11）で探した物 | 見て汲み取るだけ。画像・音は使わない。コマと目録は ~/research/asahigaoka/（map.md） |

取得日はどれも 2026-11-11。出典を載せる所と利用規約の細かい所は、天下森と同じく出す前に確かめる。

### OSM の取り方

```
[out:json];(way(around:2500,42.90080,140.73346)["piste:type"];way(around:2500,42.90080,140.73346)["aerialway"];
way(around:2500,42.90080,140.73346)["landuse"="winter_sports"];);out geom;      → osm/osm.json
[out:json];(way(around:600,42.90186,140.73723)["building"];way(around:600,42.90186,140.73723)["highway"];
way(around:600,42.90186,140.73723)["amenity"="parking"];);out geom;                → osm/bld.json
```
