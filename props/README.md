# 外の小物

丘に置く小物（ソリ・木・雪・斜面の小物）。ロッジ（[lodge/](../lodge/README.md)）と同じく、Blender 5.2 を画面なしで動かす台本で組み、glb に書き出す。外の素材（モデル・画像）は使わず、形も質感もコードで作る。

世界観は [design/art-concept.md](../design/art-concept.md)。裁縫の素材（毛糸・フェルト・綿・羊毛・麻ひも・紙・木）だけで作る。

![4 台のソリ](renders/24-sleds-line.png)

## ファイル

| ファイル | 中身 |
|---|---|
| [common.py](common.py) | 共通の部品。素材（`lodge/materials.py` を読むだけで使い、麻ひも・曲げ木・綿を足す）、管・座布団・縫い目の形、描画と書き出し |
| [build_sled.py](build_sled.py) | ソリ 4 種（米袋・小・中・大）と滑りあと |
| [build_tree.py](build_tree.py) | ミニチュアの木 4 種 |
| [build_snow.py](build_snow.py) | ふわふわの雪（吹きだまり・雪の山・雪をかぶったフェルトの岩・パウダー） |
| [build_slope.py](build_slope.py) | 斜面の小物（スピーカーの柱・コースの旗・毛糸の安全ネット・案内板） |
| [build_machines.py](build_machines.py) | ロッジの中の機械と小物（ミシンの制作機・アイロン台の焼き台・スチーマー・乾燥機・カップ・食べ物の粒） |
| [kit.py](kit.py) | ロッジの中の小物の台本が使う組み立て部品（品物ごとの部品箱、箱・円板・回転体・縫い目、並べて描く、書き出す） |
| [build_food.py](build_food.py) | 食べ物と飲み物 28 品（中華まん・缶・ラーメン・そば・うどん・マグ・おにぎり・おでんなど） |
| [build_room.py](build_room.py) | 床・壁・敷物・座布団・布団・小上がり・掘りごたつ |
| [build_furniture.py](build_furniture.py) | 調度品と灯り（椅子・ソファ・プフ・卓・本棚・膝掛け・吊り灯り・行灯など） |
| [build_hearth.py](build_hearth.py) | 暖炉・ストーブ・やかん・薪 |
| [build_counter.py](build_counter.py) | 食べ物を買うカウンターまわり（メニュー板・レジ・お盆・給水機・ティッシュなど） |
| [build_misc.py](build_misc.py) | 乾かす物干し、入口まわり、自動販売機、壁と窓の飾り |
| [build_kitchen.py](build_kitchen.py) | 厨房の作業台と、卓に載せる調理の道具（アイロン台・プレス機・乾燥機）とペレットの入れ物 |
| [build_scenes.py](build_scenes.py) | 書き出した glb を組み合わせた場面（暖炉の前・こたつ・食堂・厨房）。Godot の場面も書き出す |
| [stitches.md](stitches.md) | 滑りあとの縫い目の見本帳（作ったものと、これから作る候補） |
| `renders/` | 描いた画像 |
| `../game/props/*.glb` | ゲームで使う見た目と目印 |

## 動かし方

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_sled.py -- --kind mid --views quarter,back,low --prefix props/renders/01-sled-mid
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_sled.py -- --kind all --look flat --export game/props
```

引数:

- `--kind sack|small|mid|large|all`: ソリの種類。`all` は 4 台を並べる（書き出しでは 4 つの glb）。`mid` の glb は 2026-10-28 のまま。書き出すときは `--kind sack` のように 1 つずつ
- `--trail`: 後ろの雪に滑りあとを描く（描くときだけ）
- `--views`: カメラの名前をカンマで区切る。`quarter` `side` `back` `low` `top`、並べたとき `line` `line_back` `line_trail` `trail_top`
- `--look day|flat`: `day` は素材と光、`flat` は書き出し用（役割の名前と色だけ）
- `--export <フォルダ>`: 描かずに glb を書き出す
- `--prefix` `--size` `--blend`: ロッジと同じ

1 枚の描画は数秒。

## ソリ

4 種類。大きさごとに形が違う（2026-10-29 代表「小がホームセンターに売ってるプラスチックの1~2人用、大がサンタさんが乗ってるような8人乗りくらいのやつ」「1人用の重さ0の米袋もほしい」、そのあと米袋は 1 kg に）。寸法・席・重さは `game/sled.gd` の `KINDS`（sled-drag のブランチ）に合わせた。

| 種類 | 乗れる人数 | 当たりの箱（幅 × 高さ × 長さ） | 重さ | 形 | 滑りあと | 三角形（書き出し） |
|---|---|---|---|---|---|---|
| `sack` | 1 | 0.6 × 0.15 × 1.1 m | 1 kg | 米袋 | なみ縫い | 約 1,500 |
| `small` | 2（縦に 2） | 0.75 × 0.45 × 1.6 m | 15 kg | 成形ソリ | なみ縫い | 約 2,500 |
| `mid` | 3（縦に 3） | 1.5 × 0.45 × 2.8 m | 60 kg | 座布団と曲げ木 | くさり縫い | 約 2,000 |
| `large` | 8（横 2 × 縦 4） | 2.2 × 0.45 × 4.8 m | 220 kg | サンタのそり | サドルステッチ | 約 4,500 |

![米袋・小・大](renders/21-sled-sack-quarter.png)

- **米袋（sack）**: クラフト紙の米袋に、わらを少し詰めて尻に敷く。座る所が少しへこみ、たたんだ跡の折りじわ。表に赤い丸に筆の「米」、両脇に稲穂、前に赤い 2 本の帯の印刷。口（前）と底（後ろ）は、本物の米袋と同じく紙テープを折りかぶせて糸で縫い閉じる（赤い糸のくさり縫い）。前の両耳に穴をあけ、紐を結ぶ
- **小（small）**: ホームセンターのプラスチックのソリを、**型に入れて固めた厚いフェルト**に置き換えた（帽子の帽体と同じ作り方。プラ板は工作の素材なので使わない）。平たい盆に低い縁、前は上へ反る。縁はクリームのバイアステープでくるみ、内側を赤い糸のなみ縫いで押さえる。前の反りの 2 つの穴に紐を通し、横の壁には座る人ごとに握りの穴（どれもボタンホールかがり）。底に座る所の楕円のなみ縫い、下に滑り木の代わりのフェルトの帯 2 本（x = ±0.28）
- **中（mid）**: 赤いフェルトの座布団を曲げ木の滑り木に載せ、腕の高さに曲げ木の手すり。2026-10-28 のまま（下の「中の作り」）
- **大（large）**: サンタのそり。赤いフェルトの胴は、前が高く反り返る板、後ろが上で巻く背の高い背板、横は中ほどが低い板。縁は金茶の毛糸の撚りひも、横の外に渦 2 つと波、前の板に渦 2 つ。中は緑のフェルトの長椅子が 4 列（人ごとに座布団、列ごとに背もたれ）。滑り木（x = ±0.95）は前で大きく渦を巻き、前の板の上の両角にフェルトの鈴
- **紐の結び先**（`rope_tie_l`・`rope_tie_r`。`game/sled_rope.gd` が読み、印の上の向きを巻く軸にする）: 米袋は前の耳の角（軸は前後）、小は前の穴と縁のあいだ（軸は左右）、大は滑り木の渦のいちばん前（軸は上下）
- **席**（`seat_N`）: `small` だけ物理（0.35）と違い、成形ソリの座る面に合わせて 0.06。物理側に相談中（共有メモ）

### 中の作り

赤いフェルトの座布団を木の曲げ木の滑り木に載せ、麻ひもで仕立てる。

- **座布団の数が乗れる人数。** 1 人に 1 枚。真ん中を木のボタンで綴じ、2 枚のフェルトを縫い合わせた耳をクリームの糸で巻きかがる
- **背もたれ**は後ろ。同じ作りの座布団を少し後ろへ倒し、木の枠で支える
- **滑り木**は薄い曲げ木の板。前で反り上がって少し巻き戻る
- **横の手すり**: 座った人の腕の高さに曲げ木の手すりを渡し、座る所ごとにフェルトの握り。紐は手すりの前の巻き下りに結ぶ
- 下は木のすのこ

### 滑りあと

ミシンの縫い目を雪に残す。**重いソリほど太くて丈夫な縫い目**（なみ縫い → くさり縫い → サドルステッチ。2026-10-27 に代表が選んだ）。糸の色はソリのフェルトに合わせる。花の蔓のような凝った柄は、報酬や買い物で手に入れる差し替え。柄の一覧と候補は [stitches.md](stitches.md)。

![滑りあと](renders/04-sleds-trail_top.png)

- `--trail-large <柄>` で 6 人乗りの跡を差し替えて描ける（`herringbone` `triple_zigzag` `garden` など）
- `--swatch all` で見本帳（柄を 1 本ずつ縦に並べた画像）を描く

### Godot で使う

- 前は +Y（Blender）＝ -Z（Godot）。原点は台の中心の真下、雪の高さ
- 素材は役割の名前（`felt_red` `felt_red_dark` `wood` `wood_dark` `wood_bent` `button` `hemp` `thread`）と色だけ。ロッジと同じく `look.gd` の素材に名前で差し替える
- 目印（空の節点）: `seat_0`〜、`rope_anchor`（紐の付け根。ゲームの紐はここから `player.gd` が描く）
- 根元の節点の extras: `seats`（人数）、`mass`（重さ）、`box`（当たり判定の箱の幅・高さ・長さ）
- 垂れた紐は画像の中だけ。glb には結び目まで

## 木

フェルトの円錐を 2 段重ね、てっぺんに綿の雪の帽子、幹はロクロで挽いた木の丸棒。

![木 4 種](renders/05-trees-low.png)

- **縮尺**: 高さ 20 cm の手芸作品を、丘の大きさ（3〜7 m）に引き伸ばしたもの。縫い目・縁の厚み・揺らぎを高さに比例させるので、丘に置くと小さく丸く見える
- **円錐**は綿を詰めたフェルト。少しふくらんだ横顔、丸い先、厚く丸い裾の縁、手作りの少しの傾きと歪み。上の段は少し明るい緑
- 脇に 1 本、縫い合わせの巻きかがり。裾は種類ごとに切り方と縫い方を変える
- **雪の帽子**は先に載せた丸い綿玉と、そこから舌のように垂れる綿。下の段の肩にも、上の段の裾のすぐ外に綿が積もる（`round` 以外）

| 種類 | 高さ | 形 | 裾 | 肩の雪 | 三角形（書き出し） |
|---|---|---|---|---|---|
| `tall` | 7 m | ほっそり | 波形に裁ち、少し上をなみ縫い | あり | 約 9,700 |
| `zigzag` | 6 m | ふつう、青みの緑 | ピンキングばさみ、なみ縫い | あり | 約 1.2 万 |
| `round` | 5 m | ずんぐり、先が丸い | まっすぐ切って巻きかがり | なし | 約 1.1 万 |
| `little` | 3 m | 低く丸い、黄緑 | 波形、なみ縫い | あり | 約 9,600 |

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_tree.py -- --kind all --views line,low --prefix props/renders/05-trees
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_tree.py -- --kind all --look flat --export game/props
```

- `--kind tall|zigzag|round|little|all`、カメラは `line` `line_high` `close` `low` `one`
- 原点は幹の真下、雪の高さ。根元の節点の extras に `height`
- 素材の名前: `felt_tree_<種類>`（下の段）、`felt_tree_<種類>2`（上の段）、`trunk`、`cotton`、`thread`
- 画像の綿とフェルトの輪郭の毛羽は、同じ形を法線の向きに少しずつ膨らませて重ねたもの（シェルテクスチャリング。`common.fuzz()`）。glb には入れない。ゲームでは Godot のシェーダーで同じことをする（`design/art-concept.md` の「質感の作り方」）

## ふわふわの雪

雪の硬さで素材を変える。踏み固めた雪は目の詰んだメリヤス編み（丘の地面。ゲームのシェーダー）、柔らかい積雪はふっくらした綿、パウダーはちぎった綿と小さな毛玉。

![綿の雪と編み目の雪](renders/06-snow-powder.png)

| 名前 | 中身 | 大きさ | 三角形（書き出し） |
|---|---|---|---|
| `snow_drift` | 吹きだまり。風上はゆるい坂、風下は切り立ち、てっぺんが庇のように張り出す | 長さ 7 m、幅 2.6 m、高さ 0.9 m | 下の表 |
| `snow_pile_a` `snow_pile_b` | ちぎった綿のかたまりを山に積んだもの | 直径 2.2 m / 1.2 m | |
| `rock_a` `rock_b` `rock_c` | 縫い合わせたフェルトの小石に、綿の雪が積もる。横に一周、巻きかがり。`c` は小石 3 つ | 1.2 m / 2.1 m / 0.9 m | |
| `powder` | パウダーの粒 4 つ（`powder_0` `_1` は毛玉、`_2` `_3` はちぎった綿）。ゲームの粒子の形に | 5〜14 cm | |

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow.py -- --views scene,close,drift,powder --prefix props/renders/06-snow
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_snow.py -- --look flat --export game/props
```

- 綿の輪郭の毛羽（にじみ）は、木と同じく画像の中だけ。ゲームでは Godot のシェーダーで
- 原点は地面の高さ。少し地面に埋めて置くと、編み目の雪と綿の雪の境がなじむ
- 素材の名前: `cotton`、`felt_stone` `felt_stone2`、`thread_dark`

## 斜面の小物

木の棒にフェルトと毛糸を縫い付けた手芸作品。根元と上には綿の雪。

![斜面の小物](renders/08-slope-line.png)

| 名前 | 中身 | 目印・extras |
|---|---|---|
| `speaker_pole` | 高さ 5 m の木の柱に、腕木でラッパ型のスピーカー。ラッパはフェルトで、上の継ぎ目と口の縁を巻きかがる。黒い毛糸の線が柱に巻きついて下りる | `horn`（ラッパの口）、extras `horn_dir`（Godot の座標で、口の向き。前へ 15 度下向き） |
| `flag_red` `flag_navy` | 高さ 1.7 m の細い棒に、風で波打つフェルトの三角旗。縁の内側をなみ縫い、糸の輪で棒に結ぶ | `height` |
| `net_span` | 杭 1 本と、その先 2.5 m の毛糸の網（山吹の 3 本撚り、ひし形の網目、交わる所に結び目、上の綱はたるむ）。並べてつなぐ。最後だけ杭を足す | `span`（2.5） |
| `sign_lodge` `sign_slope` | 板 2 枚の案内板に、フェルトのアップリケ。左にアイコン（ロッジ: 片流れ屋根の家と煙突 / 斜面: ソリの横顔）、右へ型紙の記号のような燕尾の矢印。文字なし | `icon` |

- 前は +Y（Blender）＝ -Z（Godot）。案内板の表と、ラッパの向きが前
- 案内板の矢印の向きを逆にしたいときは、Godot で x を -1 倍する（アップリケが左右に入れ替わる）
- スピーカーの柱は、音の設計（`design/sound-concept.md` の「柱 1」）の 6 本の柱の見た目。`horn` の位置と `horn_dir` を、音を鳴らす場所と向きに使える

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_slope.py -- --views line,speaker,sign,net,flag --prefix props/renders/08-slope
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_slope.py -- --look flat --export game/props
```

素材の名前: `pole`（柱の木）、`wood`（板）、`felt_horn` `felt_horn_in`（ラッパの外と中）、`yarn_yellow`（網）、`thread_dark`（線）、`felt_red` `felt_navy2` `felt_yellow` `felt_cream`（旗とアップリケ）、`thread`、`cotton`

## ロッジの機械と小物

布と糸を扱う道具の形を借りた機械（`design/game-concept.md` の「ロッジで作る・買う・休む」）。ふっくらしたフェルトの箱を縫い合わせた、ぬいぐるみの機械。人（背 1.6 m）が前に立って使う大きさ。部屋の灯りは電球色より少し赤み。

![ロッジの機械](renders/09-lodge-line.png)

| 名前 | 中身 | 置き場 | 目印 |
|---|---|---|---|
| `craft_machine` | 制作機。大きなミシンの形（幅 2.8 m、高さ 2.2 m）。藍のフェルトの胴に金の花のアップリケ、縁を巻きかがる。木の作業台と足踏み、はずみ車、赤とクリームの糸巻き、針の下に紙の灯り、押さえの前に布送りの歯。動く部品は `mv_*` に分けてある（`game/sewing_machine.gd` が動かす。[design/sewing-motion](../design/sewing-motion/README.md)） | `slot_craft_rental` | `work`（針の下。縫う物が通る所）、`stand`（人が立つ所）、`pedal`（もう一人が足踏みに立つ所）、`out`（できた物が止まる所）、`lamp`、`thread_0..4`（糸の道）、`mv_needle` の下に `eye` |
| `iron_grill` | 焼き台。アイロン台（パッチワークの覆い、X の木の脚）の上に、熱をもった橙のフェルト。後ろにフェルトのアイロンを立てて休ませる | `slot_food_kitchen` | `cook`、`stand` |
| `steamer` | 蒸し器。湯の缶から毛糸のホースでスチーマーの頭へ。麻ひもを巻き上げたせいろに綿の湯気 | `slot_food_kitchen` | `cook`、`stand` |
| `dryer` | あたため。丸い窓の箱。窓は透明なフィルムに白い糸の枠（ロッジのガラスと同じ決まり）、中は編み地の胴。木のつまみと、目盛りを縫った赤い盤 | `slot_food_kitchen` | `cook`、`stand` |
| `cup` | 両手で包む木の器（直径 9 cm、実寸）。毛糸のゴム編みのカバーとクリームのなみ縫い、ココアと綿の湯気 | — | `hand_l` `hand_r` |
| `food_pellets` | 材料の粒。フェルトの毛玉 4 色と短い円柱 2 色（`pellet_0`〜`5`、直径 4〜5 cm） | — | — |

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_machines.py -- --views line,craft,cook,cup --prefix props/renders/09-lodge
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_machines.py -- --look flat --export game/props
```

- 前は +Y（Blender）＝ -Z（Godot）。原点は床の高さ。根元の extras `slot` に置き場の名前
- 素材の名前: `felt_navy2` `felt_gold` `felt_cream` `felt_red` `felt_heat`（ほのかに光る）`felt_brown` `felt_beige` `felt_green` `felt_yellow`、`wood` `wood_light`、`yarn_red` `yarn_cream`、`hemp`、`thread`、`paper`（灯り）、`quilt`（パッチワーク）、`glass`（窓のフィルム）、`knit_drum`、`cotton`（湯気）
- 湯気（綿）は glb に入れてある。ゲームでゆらすか、粒子に置き換えるかは組み込むときに決める
- 画像の床・壁・小さな卓は描くときだけ

## 質感・形・大きさの作り直し（2026-10-28 朝）

代表がゲームで見て「テクスチャがぼやける」「形にメリハリがなく、大きな塊に見える（自販機・こたつ）」「もっと大きく、頂点を増やし、重力を当てて」と言ったので、作り方を変えた。

- **質感**: CC0 の写真の質感（フェルト・綿・麻・毛糸・木・紙。[SOURCES.md](SOURCES.md)）を全部の小物で使い回し、縫い目・色むら・くぼみの陰・使い込んだ汚れは品物ごとに焼く
  - 書き出し（`--export`）は、素材を描くときと同じに組み、部品ごとに展開（UV）して Cycles で色と凹凸を焼き、JPEG で glb に入れる（`kit.prepare()`）。焼く細かさは 1 m あたり 160 画素（64〜1024）。細い糸・毛糸・麻ひも・綿・光る紙・フィルムは焼かない
  - ゲームでは `game/props.gd` が、焼いた色と凹凸に、役割の仲間ごとの細部（`game/props/textures/*_detail.png` をかけ算、`*_normal.png` を重ねる。物の向きに合わせて 3 方向から貼る）を重ねる。縁の光は弱めた（白っぽくぼやける元だった）
  - 細部の画像は `make_textures.py` で CC0 の画像から作る
- **形**: 硬い物（自販機・レジ・給水機・ストーブ・カウンター・床と壁の板）は、角を少しだけ丸めた箱と板を組む（`Parts.hard`）。何の機械かを形で読ませる（窓・棚・ボタン・お金の口・取り出し口・打ち鍵・戸と蝶番）
- **重力**: 布は Blender の布の計算で落とす（`kit.cloth_sim()`）。こたつ布団・掛け布団は卓や敷き布団の上から垂らし、角で折れて床に溜まる。座布団・敷き布団・椅子とソファの座と背は、綿を詰めた袋を内から押して重さで沈ませる（`kit.cushion()`）
- **大きさ**: 書き出しで形にかける（`kit.setup(..., scale=)`）。食べ物と飲み物は 1.5 倍、ロッジの中のほかの物は 2 倍（ロッジの間取りの倍率とそろう）。ミシンの制作機だけ、貸出に収まるよう 1.5 倍。外の物（ソリ・木・雪・斜面の小物）は今の大きさのまま。描いた画像（`renders/`）は元の大きさで並べている
- 頂点: 書き出しでも割りを粗くしすぎない。布と袋は細かく割って計算し、丸みを 1 段足す

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/make_textures.py -- <CC0 の元の画像のフォルダ>
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_misc.py -- --export game/props/misc --only vending_red
```

`--only` で品物を選べる（ロッジの中の小物の台本）。書き出しは品物ごとに 30 秒〜1 分。

## ロッジの中の小物（2026-10-28 の夜に足した）

代表の頼み「ロッジの落ち着き空間のためのリッチな調度品、食べ物飲み物、床、壁、掘りごたつ…」から。ロッジの建物（`lodge/`）は別のセッションの持ち物なので、建物は変えず、置いて使う部品として作った。どれもフェルト・毛糸・綿・紙・木・麻ひも。書き出しは種類ごとのフォルダ（`game/props/<種類>/`）。

![暖炉の前](renders/15-scene-hearth.png)

| 種類 | 台本 | 書き出し | 品物 |
|---|---|---|---|
| 食べ物と飲み物 | `build_food.py` | `game/props/food/` | 肉まん・あんまん・ピザまん・カレーまん、中華まんのケース、缶（コーンポタージュ・ココア・コーヒー・お茶・おしるこ）、ラーメン（しょうゆ・みそ・しお。麺は毛糸）、そば（かき揚げ）、うどん（きつね）、マグ 3 種（ココアに綿のマシュマロ・ホットミルク・ゆず茶）、おにぎり 3 種、おでん、たい焼き、みかん、湯のみ 2 種、三色団子、カレー |
| 床・壁・寝具 | `build_room.py` | `game/props/room/` | 床（板 2 色・畳。2 m 角）、編んだ敷物 2 色、壁（羽目板・パッチワーク 2 色・フェルトの丸太。幅 2 m）、座布団 5 種、布団一組 3 種、小上がり（畳 2 枚・4 枚）、掘りごたつ 2 種と床置きのこたつ |
| 調度品と灯り | `build_furniture.py` | `game/props/furniture/` | ひじ掛け椅子 3 色、ソファ（3 人・2 人）、編んだプフ 3 色、小卓（かぎ針の敷物）、ちゃぶ台、本棚 2 種、膝掛け 2 色、吊り灯り（プリーツの筒・提灯・円錐）、床置きの灯り、行灯、壁の灯り、卓の灯り、紙の玉の飾り |
| 暖炉まわり | `build_hearth.py` | `game/props/hearth/` | 暖炉（フェルトの小石・フェルトのレンガ）、薪ストーブ、丸い石油ストーブ 2 色、やかん 3 色、薪置き、薪のかご |
| カウンター | `build_counter.py` | `game/props/counter/` | メニュー板 3 枚（料理・飲み物・甘味。絵と金の丸の数で値段）、レジ 2 色、呼び鈴、お盆 3 種、給水機、紙コップ、ティッシュ箱 3 種、箸立て、薬味、カウンター 2 区画 |
| そのほか | `build_misc.py` | `game/props/misc/` | 物干し（濡れた上着と手袋）、手袋干し、帽子掛け、長靴の置き台、スキー立て、自動販売機 2 色、掛け時計（文字なし）、壁掛け 2 種、カーテン 2 色、鉢植え 2 種、額 2 種 |

- 手に持つ物（食べ物・カップ）は実寸。部屋の物は人（背 1.6 m）の大きさ。床と壁は 2 m 角でつなげる
- 灯り・暖炉・ストーブ・自販機には `light*` の目印がある。ゲームでは `game/props.gd` が暖色の灯りをともす
- 座れる物には `sit*`、卓には `top`、こたつには `seat_0`〜`3`、機械には `cook` `stand` などの目印
- 手に持つ小物はフェルトの繊維を細かくして描いた（`kit.setup(..., fiber=4)`）。部屋の物は 1.5

### 場面

`build_scenes.py` が、書き出した glb を並べて場面にする。Godot の場面も同じ配置で `game/props/sets/<名前>.tscn` に書き出す（`game/props_set.gd` が素材と灯りを着せる）。

| 場面 | 中身 |
|---|---|
| `hearth_nook` | 暖炉の前のくつろぎ場所: 石の暖炉、編んだ敷物、ひじ掛け椅子 2 脚、プフ、小卓と灯り、お茶とみかん、薪のかご、やかん、床置きの灯り |
| `kotatsu_room` | 小上がりの掘りごたつ: 畳 4 枚の台、パッチワークのこたつ、座布団 4 枚、提灯、行灯、お茶とたい焼き、布団 |
| `dining` | 食堂のカウンター: カウンター 2 区画、メニュー板 3 枚、レジと呼び鈴、お盆にラーメンとお茶・カレーとココア、中華まんのケース、給水機、吊り灯り |

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_scenes.py -- --views hearth,kotatsu,dining --prefix props/renders/15-scene
```

## パッチワークと厨房（2026-10-28 の昼）

代表がゲームの画像を見て「モザイク柄はパッチワークに」「布団の枕に乗り上げた所が骨でも入ったように固い」「厨房がさみしい」と言った。

- **パッチワーク**: 役割 `patch_warm` `patch_cool` `patch_mix` `patch_rose`（`common.PATCH` に色を足せば柄違いが増える）。四角い端切れごとに、無地・縞・水玉・ギンガムの柄と色を変え、3 枚に 1 枚ほどは対角に三角 2 枚をはぐ。縫い目は少しへこみ、端切れの縁の内側になみ縫い、端切れの真ん中はふっくら（`common.patchwork()`）
  - 柄は布に貼った UV（`cloth`）でつける。垂らす布は平らな形のときの位置なので、垂らしたあとも端切れが布にそう。箱や袋は面の向きで投影する（小さな品物は `uv_scale` で端切れを細かく）。焼くときは別の UV を作り、焼いたら `cloth` は捨てる
  - 使っている品物: こたつ布団（`kotatsu_patch`）、掛け布団（`futon_patch`）、座布団（`zabuton_patch`）、カウンターの前（`counter_patch`）、ティッシュ箱（`tissue_patch`）、アイロン台の覆い
  - 前のロッジの `quilt`（3 次元の格子の色分け）は、垂らした布を斜めに切ってモザイクに見えていた
- **布団**: 掛け布団を枕の手前までにし、どこも留めずに落とす（前は枕の側を留めていて、折れた縁が固く浮いた）。曲げの硬さも下げた
- **厨房**: 料理は「レジでペレットを買い、アイロン台でプレスしたり、乾燥機で温めたりすると食べられる」（代表）。道具を卓に載る大きさにして、作業台に並べた（`build_kitchen.py`、書き出しは `game/props/kitchen/`、2 倍）

| 品物 | 中身 |
|---|---|
| `work_table_moss` `_indigo` `_rust` | 作業台（ゲームで 1.8 × 0.9 m、高さ 0.94 m）。方眼をなみ縫いしたフェルトのマット（裁縫の切り台）。下の棚に麻の籠と粒。目印 `top`、人が立つ所 `stand_0` `stand_1` |
| `press_board` `press_board_cool` | 卓上のアイロン台。パッチワークの覆いに熱をもった楕円。アイロンは横の鍋敷きに寝かせる。目印 `cook` |
| `heat_press` `heat_press_mustard` | 服のプレス機。下の熱板に、蝶番で上の板を開けてある。柱に目盛り、熱板に押された粒。目印 `cook` |
| `table_dryer` `table_dryer_red` | 卓上の乾燥機。背の高い前開きの形で、上に操作盤、丸い戸に透明なフィルム、中に羽根のある編み地の胴と粒、奥に熱。目印 `cook` |
| `giant_press_board` `giant_press_board_cool` | 巨大なアイロン台（ゲームで長さ 3.4 m、面の高さ 1 m）。X の脚、後ろの鍋敷きに長さ 1 m のアイロン、熱い楕円から湯気。目印 `cook` |
| `giant_heat_press` `giant_heat_press_mustard` | 巨大なプレス機。引き出しの台に卓上のプレス機を 3.5 倍で載せる（熱板の高さ 1 m、開けた上の板の上まで 2.8 m）。目印 `cook` |
| `giant_dryer` `giant_dryer_red` | 巨大な乾燥機。卓上の乾燥機を 5 倍に（幅 2.4 m、高さ 3.4 m、戸の径 1.5 m）。上に粒を入れる漏斗、横に湯気を吐く毛糸のホース、胴の底に大きな粒。目印 `hopper` `cook` |
| `pellet_jar_mix` `_red` `_green` `_yellow` | 粒の瓶。布の蓋を麻ひもで縛る |
| `pellet_sack_mix` `_green` `_brown` | 粒の麻袋。口を折り返し、木の匙。前にフェルトのしるし |
| `pellet_bag` | レジで買った紙袋。口を折って赤いシールで留める |
| `pellet_tray` | 仕分けの盆（3 × 2 に色ごと） |

- 調理の道具は、厨房の顔になるよう巨大な装置にした（代表「アイコニックにするために巨大な装置に。今のも可愛いからバージョン違いとして」）。卓上の道具は同じ形の小さい版として残す（`heat_press_body()` `dryer_body()` を大きさを変えて使う）
- 場面 `kitchen`（`build_scenes.py`、`game/props/sets/kitchen.tscn`）: 巨大なアイロン台・プレス機・乾燥機を奥に並べ、正面をカウンターの側へ。東の端の作業台に卓上のアイロン台と乾燥機。床に麻袋と仕分けの盆、ロッジの奥の台に瓶と紙袋。装置と作業台には当たり判定の箱。`main.gd` がロッジの `slot_food_kitchen` に置く
- **入口はまだない**: 厨房はロッジのカウンターと両脇の間仕切りでふさがっていて、すき間は 0.3〜0.43 m（人の太さは 0.7 m）。カウンターの端に抜ける所（跳ね上げの板など、幅 1 m ほど）を作るのはロッジのセッションの仕事なので、頼んである

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_kitchen.py -- --views all,press,hpress,dryer,pellets,giant,giant_press,giant_dryer --prefix props/renders/18-kitchen
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P props/build_scenes.py -- --scenes kitchen --views kitchen,kitchen_near --prefix props/renders/19-scene
```

## 縫い目・煙・乾燥機（2026-10-28 の午後）

代表「縫い目が本体から浮いているのがすごく嫌」「煙が魂みたい。もっとリアルなもくもくに。調理中は煙が出るとよい」「乾燥機が乾燥機っぽくない、もっと高さがある」。

- **縫い目**: 浮いて見えた元は、書き出しで本体の割りを粗くするのに、糸は滑らかな形の上に置いていたこと（平らな面の上に糸が浮く）。いまは糸を画像に焼く（下の「軽くする」）。描く前（`kit.render_views()`）と焼く前に、`kit.seat_threads()` が糸（役割 `thread*`）の 1 本ずつを、本体の実際の面に沿わせて少し沈める（いちばん低い所を面の下、糸の芯は面より半径の 0.25 倍下）。巻きかがりの輪の形はそのまま。面から 0.1 より離れた糸は触らない。岩・ソリ・木・機械など `kit` で書き出す全部に効く
- **煙**: ゲームでは `game/props.gd` が湯気の形（`*steam*`）を隠し、その根元に煙の粒子を置く（ふちの溶けた雲の模様の板を、ふくらませながら上へ流し、ゆらぎを足して薄れさせる）。調理の道具（目印 `cook*` のある品物）の煙は調理中だけ出す（`Props.set_cooking(品物, true)`）。調理の仕組みができるまで、厨房では `Props.cook_cycle()` が装置を順に「調理 9 秒・休み 6 秒」させる。食べ物の湯気はいつも出す。描く画像の湯気は、上へ広がる丸いかたまりの房（`kit.steam()`）
- **乾燥機**: 背の高い前開きの形に（幅 0.24、高さ 0.34。巨大な版はゲームで幅 2.4 m、高さ 3.4 m、戸の径 1.5 m）。上に操作盤（大きなつまみと目盛り・ボタン 3 つ・動いている灯り）、真ん中に丸い戸（蝶番と取っ手）、中に羽根 3 枚の編み地の胴、下に蹴込みの帯と通気の溝。巨大な版は上に粒を入れる漏斗、横に湯気を吐くホース

## 軽くする（2026-10-28 の夕方）

ゲーム開発のセッションから「全体に重い。いずれスマホでも」（代表の頼み）。小物の組（厨房は物体 400）が描画の回数と三角を押し上げていた。

- **細かい形 → 軽い形に焼く**（`kit.prepare()`）: 書き出しで、細かい形（縫い目の糸も）を、素材の組ごとに 1 つの軽い形（減らした形）へ Cycles で焼く。組は `felt`（フェルト・毛糸・麻・綿・紙）、`wood`、光る物（`paper` の笠・`felt_heat`・`fire`）、`glass`、`snow`。組ごとに画像（色と凹凸）1 枚。Godot の素材は組の数だけ（品物 1 つで描画 2〜4 回）
  - 縫い目の糸は形にせず、本体の画像に焼く（面から離れて垂れた糸は形を残す）。糸が浮く心配もなくなる
  - 三角の目安: 品物は `kit.setup(..., tris=)`（ふつう 3,000、カウンター・厨房 2,500、食べ物 1,200）、品物ごとに `Parts(..., tris=)`（巨大な装置 5,000）。木 500、ソリ 1,500〜4,500（種類ごとに build_sled.py の KINDS の tris）、岩と雪 800、斜面の小物 1,500、機械 4,000
  - 湯気は形をやめ、根元の目印（大きさ: 幅と高さ）にする。Godot が煙の粒子を出す
- **場面は 1 つの glb に結合**（`build_scenes.py`）: 組の小物を読み、素材の組ごとに 1 つに結合して減らし（1 組で三角 2 万以下）、組ごとに 1 枚の画像（2048 まで）へ焼き直して `game/props/sets/<名前>.glb` に。目印（灯り・湯気・座る所）は組の根元へ移す。`.tscn` はその glb 1 つと当たり判定の箱
- 名前: 軽い形は `prop_<品物>_<組>`、場面の根元は `prop_set_<名前>`（360° 映像から小物を外す目印 `PIP_SKIP_WORDS` に当たる）

## ゲームへの組み込み（2026-10-28）

- `game/props.gd`: glb を読み、素材を役割の名前で `look.gd` の手芸の素材に差し替える。`light*` の目印に暖色の灯りをともす
- `game/main.gd`: 丘の木 70 本を `tree_*.glb` に（高さ 4〜8 m に合わせて大きさを変える）。登り道の両脇に旗 8 本、スタートとロッジの前に案内板、右の外れに網、まわりに岩と雪のかたまり（`_make_slope_props()`。当たり判定はまだない）。音の柱（`audio.gd` が立てる）の仮の見た目を隠して、フェルトのスピーカーの柱に着せ替える（`_dress_speakers()`。`audio.gd` は変えていない）
- `game/sled.gd`: 箱のソリの見た目を `sled_mid.glb` に。物理（当たり判定・つかむ縁・紐の付け根）は変えていない
- `game/main.gd` の `_furnish_lodge()`: ロッジの glb の機械の置き場の目印に機械を置く。`slot_vending_1`〜`3` に自販機（赤・青・赤）、`slot_craft_rental` にミシンの制作機。どれも正面を南（食堂の側）へ。`slot_food_kitchen` には厨房の場面（前は床置きの焼き台・スチーマー・乾燥機を置いていた）
- ロッジの中の調度品と場面（`game/props/sets/`）は、まだロッジに置いていない。置く場所はロッジのセッションと決める（場面は `load("res://props/sets/hearth_nook.tscn").instantiate()` で置ける）

## 画像

| 画像 | 中身 |
|---|---|
| `01-sled-mid-*.png` | 3 人乗り（今の大きさ） |
| `02-sled-small-*.png` | 1 人乗り |
| `03-sled-large-*.png` | 6 人乗り |
| `04-sleds-line.png` `04-sleds-line_trail.png` | 3 台を並べ、後ろに滑りあと（2026-10-28 までの形） |
| `21-sled-sack-*.png` | 米袋（quarter・side・back） |
| `22-sled-small-*.png` | 小: 成形ソリ（quarter・side・back） |
| `23-sled-large-*.png` | 大: サンタのそり（quarter・side・back） |
| `24-sleds-line.png` `24-sleds-line_back.png` | 4 台を並べる（左から米袋・小・中・大） |
| `25-sleds-godot.png` `25-sleds-godot-front.png` | 4 台を Godot で、ゲームと同じ素材の差し替えで撮る。赤い玉が紐の結び先（`game/tools/sled_models_shot.gd`） |
| `04-sleds-trail_top.png` | 滑りあとを真上から（左からサドルステッチ、くさり縫い、なみ縫い） |
| `05-trees-line.png` `05-trees-line_high.png` | 木 4 種を並べる（左から tall、zigzag、round、little） |
| `05-trees-low.png` `05-trees-close.png` | 近くから。フェルトの毛羽、裾、綿の雪 |
| `06-snow-scene.png` `06-snow-drift.png` | 吹きだまり、雪の山、雪をかぶった岩 |
| `06-snow-close.png` `06-snow-powder.png` | 岩とパウダー。綿の雪と編み目の雪の違い |
| `07-stitches-swatch.png` | 縫い目の見本帳 |
| `07-stitches-garden.png` | 6 人乗りに花の蔓（報酬の柄の例） |
| `08-slope-line.png` | 斜面の小物を並べる |
| `08-slope-speaker.png` `08-slope-sign.png` `08-slope-net.png` `08-slope-flag.png` | スピーカー、案内板、網、旗の近く |
| `09-lodge-line.png` | ロッジの機械を並べる |
| `09-lodge-craft.png` `09-lodge-cook.png` `09-lodge-cup.png` | ミシン、焼き台・スチーマー・乾燥機、カップと食べ物の粒 |
| `10-food-*.png` | 食べ物と飲み物（全体、中華まん、缶、ラーメン、そのほか、ケース、マグとそば・うどん） |
| `11-room-*.png` | 床・壁・小上がり・こたつ・布団・敷物 |
| `12-furniture-*.png` | 椅子とソファ、灯り、本棚 |
| `13-hearth-*.png` | 暖炉、ストーブ、やかん |
| `14-counter-*.png` | メニュー板、レジ、卓の小物、給水機 |
| `15-scene-*.png` | 場面: 暖炉の前、こたつ、食堂 |
| `16-misc-*.png` | 物干し、入口まわり、自動販売機、飾り |
| `17-room-*.png` | パッチワークにした布団とこたつ |
| `18-kitchen-*.png` | 厨房の作業台と道具（全体、アイロン台、プレス機、乾燥機、ペレット） |
| `19-scene-*.png` | 場面: 厨房 |
| `20-giant-*.png` | 巨大なアイロン台・プレス機・乾燥機（人の大きさの目安の柱と並べて） |
