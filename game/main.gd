extends Node3D

const Look := preload("res://look.gd")
## 原型の場面: こんもりした丘、ソリ、あなた（手だけ見える一人称）、押すのを手伝う仲間。
## 確かめ用の起動引数（-- のあとに付ける）:
##   --bots=N      ソリを押す仲間の数（既定 0。--lodge-bots か --no-player を書いたときは 1。通信ではホストの数。つなぐ側では効かない）
##   --no-player   あなたを出さず、仲間だけで押す（速さを比べる用）
##   --shot=PATH   数秒後に画面を PNG で保存して終わる
##   --log         ソリの高さを1秒ごとに出す
##   --no-wind     滑るときの風のエフェクトを出さない（重さを比べる用）
##   --cam=x,y,z,tx,ty,tz  --no-player のときのカメラの位置と見る先（ロッジを撮る用）
##   --hud-debug   画面の左上の隅に確かめ用の数字（fps・通信の速さ）を小さく出す
##   --hud-idle=秒  何も操作しないでこの秒数たつと、HUD を画面の外へ引っこめる（既定 5。0 なら引っこめない）
##   --bot-lean=follow|off  一緒に乗った仲間が、あなたの体重移動に合わせるか（既定 follow）
##   --sled=KIND   ソリの大きさ（sack 米袋 1 人・small 2 人・mid 3 人（既定）・large 8 人）
##   --sled-color=色  ソリのメインカラー（ソリの主なフェルトと滑りあとの糸）。2F5DA8 のような 16 進か、white・navy などの色の名前
##   --stitch=名前  滑りあとの縫い目の差し替え（名前は stitches.gd の表。running なみ縫い・chain くさり縫い・fly フライ など）
##   --trail-fade=fray|bury  滑りあとの消え方（ほつれる・雪に埋もれる）
##   --no-buttons  雪に縫い留められたボタン（snow_buttons.gd）を出さない
##   --bot-lanterns=形,形…  仲間の帯に提げるランタン（lantern.gd の LOOKS。ソリを押す仲間、ロッジの仲間の順に。確かめ用）
##   --spawn=lanterns  おじいさんの番台の横のランタン掛けの前から始める（F でランタンを買って提げ替える）
##   --roam-bots=N  山をめぐる仲間の数（既定 5。--bots か --lodge-bots か --no-player を書いたときは 0）。自分で山を選んで登り、米袋で滑り降りて、別の山へ（bot.gd の roam）
##   --roam-all-hill  確かめ用: 山をめぐる仲間をみんな丘のそばから始める
##   --lodge-bots=N  ロッジでくつろぐ仲間の数（既定 0。--bots か --no-player を書いたときは 2）。ソリは押さず、ロッジの空いた席に座り、ときどき席を替える
##   --spawn=wardrobe  1 階の人台の前から始める（F で人形を選び直す）
##   --spawn=mirror    入口の横の大きな鏡の前から始める（F で自分の人形が映る）
##   --spawn=dye       2 階の染め桶の前から始める（F で服を染める）
##   --spawn=book      ミシンの近くの布の見本帳の前から始める（F で自分のソリの色と滑りあとを替える）
##   --doll=人形   あなたの始めの人形（doll.gd の KINDS: kasa・origami・news・robo・musha・ningyo・golem）。保存した人形より勝つ
##   --bot-dolls=人形,人形…  ソリを押す仲間の人形（既定は右が origami、左が news）
##   --lodge-dolls=人形,人形…  ロッジでくつろぐ仲間の人形（既定は robo・ningyo・golem・musha の順）
##   --spawn=pals  2 階の衣装掛けの横の売り台の前から始める（F で頭・肩の小物とミニオンを買って付け替える）
##   --no-pets     頭・肩の小物とミニオン（companions.gd）を出さない
##   --bot-pals=名前,名前…  仲間（ソリを押す仲間とロッジの仲間）に付ける頭・肩の小物とミニオン（pals.gd の名前。確かめ用）

const HILL_H := 18.0      # 丘の高さ (m)
const HILL_R := 25.0      # 丘の広がり (m)
const SIZE := 256         # 地面の 1 枚の一辺 (m)。Jolt の地形は 2 のべき乗 + 1 点で作る
const TILES_Z := [0.0, 256.0, 512.0]   # 地面の区画のまんなかの z。丘の 1 枚と、南の大きな山（mountain.gd）の 2 枚。x は -128〜128
const START := Vector3(0, 0, 38)

## ふもとのくぼみ（2026-10-30 代表「丘のふもとをへこませて、ロッジに突っ込まないような減速の仕組みを」）。
## 丘はすり鉢の中に立つ: 丘の裾が浅い輪の溝に下り、その外はゆるく上り返して、まわりの高台（ロッジもこの上）になる。
## 滑り降りたソリは溝に落ち、上り返しで止まって底へ戻る。丘はどの向きにも滑れるので、どこへ下りても受け止められるよう輪にする
const BOWL_R := 60.0      # くぼみの底の半径 (m)
const BOWL_W := 16.0      # 底から内側へ、くぼみが丘の裾に溶けるまでの幅 (m)
const BOWL_D := 1.5       # くぼみの深さ（丘の裾から下へ, m）
const RIM_W := 26.0       # 底から外の高台へ上り返す幅 (m)
const RIM_H := 3.0        # 外の高台の高さ（もとの地面から, m）

## ロッジ（lodge/ の Blender の台本で作った glb）。くぼみの外、スタートの先の少し西に置き、
## 正面（ガラスの食堂とテラス、glb の +Z）を頂上へ向ける。足もとの地面はならす。
## 2026-10-30 代表「ロッジを丘からちょっと離して」: 頂上から 81 m → 104 m（向きは同じ）
const LODGE_POS := Vector2(-35, 98)          # (x, z)
const LODGE_YAW := 2.7986                    # atan2(35, -98): 正面を頂上の向きへ
const LODGE_PAD := Rect2(-32, -16, 57, 37)   # ならす範囲（ロッジの座標の x, z）。下屋から外階段の踊り場まで
const LODGE_BLEND := 10.0                    # ならした所から丘へ戻るまでの幅 (m)

## 山をめぐる仲間のはじめの所: [向かう山, (x, z)]。尾根の途中や麓に分けて、はじめからばらけて見える
const ROAM_START := [["hill", Vector2(2, 41)], ["slope", Vector2(22, 262)], ["peak", Vector2(232, 96)], ["hill", Vector2(-30, -34)], ["slope", Vector2(32, 385)]]
const ROAM_DOLLS := ["origami", "news", "robo", "ningyo", "golem"]

const Sled := preload("res://sled.gd")
const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")
const Props := preload("res://props.gd")
const Player := preload("res://player.gd")
const Bot := preload("res://bot.gd")
const Settings := preload("res://settings.gd")
const Audio := preload("res://audio.gd")
const RideWind := preload("res://ride_wind.gd")
const SewingMachine := preload("res://sewing_machine.gd")
const Emotes := preload("res://emotes.gd")
const Duel := preload("res://duel.gd")
const DuelHud := preload("res://duel_hud.gd")
const Hud := preload("res://hud.gd")
const SelfCam := preload("res://self_cam.gd")
const Craft := preload("res://craft.gd")
const Shopkeeper := preload("res://shopkeeper.gd")
const BandaiCurtain := preload("res://bandai_curtain.gd")
const CraftUi := preload("res://craft_ui.gd")
const FoodUi := preload("res://food_ui.gd")
const MountainMan := preload("res://mountain_man.gd")
const MountainUi := preload("res://mountain_ui.gd")
const MountainGoods := preload("res://mountain_goods.gd")
const SnowmanShop := preload("res://snowman_shop.gd")
const FridgeDoor := preload("res://fridge_door.gd")
const CookStation := preload("res://cook_station.gd")
const SnowButtons := preload("res://snow_buttons.gd")
const Seats := preload("res://seats.gd")
const KotatsuFuton := preload("res://kotatsu_futon.gd")
const Wardrobe := preload("res://wardrobe.gd")
const WardrobeUi := preload("res://wardrobe_ui.gd")
const PaperLady := preload("res://paper_lady.gd")
const PaperShopUi := preload("res://paper_shop_ui.gd")
const Damp := preload("res://damp.gd")
const Badges := preload("res://badges.gd")
const Companions := preload("res://companions.gd")
const Pals := preload("res://pals.gd")
## 紙細工屋さん（paper_lady.gd。黒い折り紙の婦人と大きなスタンド）の立つ所（ロッジの座標 (x, y)。lodge/dims.py と同じ）。
## 1 階の南西の隅、人台（WARDROBE_AT）の北どなり（2026-11-04 代表「染台と紙細工士さんは今のソリ屋が外に行って開いた場所に」）。正面は東（入口からの通り道）。
## テント（paper_tent.gd）の真ん中は、婦人の左手（北）へ 0.85 m、西へ 0.085 m
const PAPER_LADY_AT := Vector2(-19.5, -5.85)
const DyeVat := preload("res://dye_vat.gd")
const DyeUi := preload("res://dye_ui.gd")
const SledBookUi := preload("res://sled_book_ui.gd")
## 布の見本帳（sled_book.gd）の立つ所（ロッジの座標 (x, y)）。ミシンと番台の前、立てかけ台の前の通り道の南。下屋の外の雪の上で、正面は西
const SLED_BOOK_AT := Vector2(-30.3, -3.3)
const Net := preload("res://net.gd")
const Start := preload("res://start.gd")
## 染めと着替えの人台（wardrobe.gd と子の dye_vat.gd）の真ん中（ロッジの座標 (x, y)）。1 階の南西の隅。もとはソリ屋（ミシン・番台・貸出の棚）のあった所。
## 正面は東（入口からの通り道）で、長い布は西のガラスの側。天井の輪があるので 1 階の天井の下にしか置けない
const WARDROBE_AT := Vector2(-19.0, -9.6)
const Mirror := preload("res://mirror.gd")
## 大きな鏡（mirror.gd）の枠の真ん中の、壁の面の所（ロッジの座標 (x, y)）。1 階の南の壁の内の面（lodge/dims.py の Y0 + LOG_D / 2）。
## 東は自動ドアの額縁（x -14.98）との間 0.17 m。幅 3.1 m で西の端は x -18.25（人台の裾に隠れすぎず、桶とのあいだを人が通れる）
const MIRROR_AT := Vector2(-16.70, -12.546)

## 売り子のおじさんの立つ所（ミシンの置き場の目印 slot_craft_rental の座標。+z がミシンの正面の側）と向き。
## 目印は西を向いている（lodge/dims.py の SLOTS。ソリ屋ごと外の下屋へ出した）ので、+x がロッジの南。売り子はミシンの南、貸出の棚の前に立つ
## （2026-10-31 代表の並びを、外へ出すときに東西に裏返した）
const SHOP_AT := Vector3(3.3, 0, -0.1)
const SHOP_YAW := PI          # 真西（番台の向こうの客）を向く
## ご飯係の雪だるまの冷蔵庫の立つ所（厨房の目印 slot_food_kitchen の座標。厨房の奥の並びのいちばん西＝炉の右。
## 厨房の装置は props/build_scenes.py）と大きさ（ミシンと同じくらいの高さ 3.7 m）。当たり判定の箱は倍率 1 の幅・高さ・奥行き
const SNOWMAN_AT := Vector3(-4.6, 0, 0.5)
const SNOWMAN_SCALE := 1.85
const FRIDGE_BOX := Vector3(1.1, 2.0, 0.85)
## 厨房の巨大な調理の装置（2026-11-01 代表の並び: 西から冷蔵庫 → プレス機 → アイロン台 → 乾燥機 → 衣類スチーマー。design/snowman-food/）。
## [名前, glb, 置く所（slot_food_kitchen の座標）, 向き（度）, 当たりの箱 [大きさ, 中心] の列]。正面（+Z）は食堂の側
const KITCHEN := [
	["press", "res://props/kitchen/giant_heat_press.glb", Vector3(-2.7, 0, 0.3), 180.0, [[Vector3(1.6, 1.0, 1.96), Vector3(0, 0.5, 0)]]],
	["iron", "res://props/kitchen/giant_press_board.glb", Vector3(0.2, 0, 0.6), 90.0, [[Vector3(3.8, 1.0, 1.24), Vector3(0, 0.5, 0)]]],
	["dryer", "res://props/kitchen/giant_dryer.glb", Vector3(3.7, 0, -0.2), 180.0, [[Vector3(2.7, 3.46, 2.7), Vector3(0, 1.73, 0)]]],
	["drink", "res://props/kitchen/giant_vapor.glb", Vector3(6.5, 0, 0.0), 180.0,
		[[Vector3(2.08, 1.5, 1.52), Vector3(0, 0.75, 0.04)], [Vector3(0.14, 3.6, 0.14), Vector3(-0.68, 1.8, -0.48)]]],
]
## 2 階の掘りごたつ 8 卓の柄（props/sets/kotatsu_lodge_<柄>.tscn。patch・indigo・rust）。8 卓ともパッチワーク（2026-11-02 代表「パッチワークにそろえる」）。
## 並びはロッジの目印 slot_kotatsu_0〜7: 0〜3 が南の列、4〜7 が北の列、どちらも西から
const KOTATSU_SETS := ["patch", "patch", "patch", "patch", "patch", "patch", "patch", "patch"]
## こたつの横の行灯（2026-11-02 代表「行灯を置く」）: こたつの組の座標で、壁の側の隅（座布団のあいだ）。
## 南の列（0〜3）は南（+Z）、北の列は北の隅。東西は卓ごとに交互。行灯は 2 倍で書き出してあるので半分（高さ 0.74 m）
const KOTATSU_ANDON := Vector3(1.75, 0, 1.35)
## こたつの上の吊り灯り（2026-11-02 代表「天井からの明かりが低すぎる」「謎の光るボックスなのはもったいない」）:
## props/furniture/pendant_<形>.glb（drum プリーツの筒・lantern 提灯・cone 円錐）を、天井の目印 slot_pendant_<番号> から吊る。
## 傘の上端は畳から KOTATSU_LAMP_TOP（lodge/dims.py の KOTATSU_LAMP）。コードは天井まで伸ばす。灯りは座敷の 2 つ（lodge.gd）で足りるので、吊り灯りそれぞれには灯さない
const KOTATSU_PENDANT := "drum"   # プリーツの筒（2026-11-02 代表「まんなかの筒」）
const KOTATSU_PENDANT_SCALE := 0.7
const KOTATSU_LAMP_TOP := 3.2
## 番台（店番の商人のカウンターとレジ。2026-10-31 代表「パッチワークおじいさんにも、雪だるまにも、番台的なカウンターとレジを」）。
## [カウンター, レジ, お皿に盛る物, ロッジの座標 (x, y), 正面（客の側）の向き（度。0 = 南、90 = 東。lodge/dims.py の SLOTS と同じ）]。
## おじいさんは真東を向いて番台の後ろに立ち、雪だるまは冷蔵庫の中から番台ごしに食堂を向く。置き方は design/lodge-layout/
const BANDAI := [
	["counter_patch", "register", "buttons", Vector2(-26.05, -8.07), 270.0],   # 外の下屋（床は雪の上。_put_bandai）
	["counter_indigo", "register_navy", "snowballs", Vector2(-1.6, 7.95), 0.0],
]
## カウンターは 2 倍で書き出してあるので、人の大きさに戻す。高さは店番のおじいさんの胸の下（0.84 m）まで低くする
const BANDAI_SCALE := Vector3(0.5, 0.4, 0.5)
const BANDAI_BOX := Vector3(1.8, 0.84, 0.68)
const LODGE_FLOOR := 0.45     # ロッジの 1 階の床の高さ（lodge/dims.py の FL1）

var sled: RigidBody3D
var player: CharacterBody3D
var emotes: Emotes          # 身ぶりと声の配り役（人より先に置く。人が登録する）
var duel: Duel              # 雪合戦の対決の配り役（duel.gd）。握手から始まる 1 対 1
var duel_hud: CanvasLayer   # 対決の画面（duel_hud.gd）
var duel_focus := false     # 自分が雪合戦で戦っているあいだ（set_duel_focus）
var hud: CanvasLayer        # 画面の表示（hud.gd）。文字を使わず、アイコンと形で伝える
var args := {}
var elapsed := 0.0
var log_t := 0.0
var _duty := 0
var _frames := 0
var _sim_sent := false
var _ft_max := 0.0
var _ft_sum := 0.0
var _ft_n := 0
var pip_label: Label
var sewing: Node3D            # 大きなミシンの動き（sewing_machine.gd）
var kitchen := {}             # 厨房の装置（KITCHEN の名前 → 置いた Node3D）
var stations: Array = []      # 厨房の装置の調理の動き（cook_station.gd）
var snowman_shop: Node        # ご飯係の雪だるま（snowman_shop.gd）
var food_ui: CanvasLayer      # 雪だるまの食べ物屋の売り場（food_ui.gd）
var mountain_man: Node3D      # 山の道具の売り子（mountain_man.gd）。ロッジの 1 階の、大きなミシンの奥
var mountain_ui: CanvasLayer  # 山男の売り場（mountain_ui.gd）
var craft: Node               # 工房の配り役（craft.gd）: 買う・縫う・畳む・広げるの出来事と、財布と持ち物
var shopkeeper: Node3D        # 型紙と布の売り子（shopkeeper.gd）
var sled_rack: Node3D         # ソリの立てかけ台（sled_rack.gd）
var craft_ui: CanvasLayer     # 持ち物の列と売り台（craft_ui.gd）
var wardrobe: Node3D          # 1 階の人台（wardrobe.gd）
var wardrobe_ui: CanvasLayer  # 人形を選び直す画面（wardrobe_ui.gd）
var mirror: Node3D            # 入口の横の大きな鏡（mirror.gd）
var paper_lady: Node3D        # テントの紙細工屋さん（paper_lady.gd。婦人と大きなスタンド）
var paper_shop_ui: CanvasLayer   # 提灯と頭・肩の小物を買って付け替える画面（paper_shop_ui.gd）
var minion_ui: CanvasLayer    # 山師が育てているミニオンを買って連れ替える画面（pals_ui.gd の連れの段。山師の売り場の「連れ」の札から）
var dye_vat: Node3D           # 人台の桶の染め液（dye_vat.gd）
var dye_ui: CanvasLayer       # 服を染める画面（dye_ui.gd）
var sled_book: Node3D         # 布の見本帳（sled_book.gd）
var sled_book_ui: CanvasLayer # ソリの色と滑りあとを替える画面（sled_book_ui.gd）
var snow_buttons: Node3D      # 斜面の雪に縫い留められたボタン（snow_buttons.gd）。滑り木で糸を切ると財布に入る
var damp: Damp                # 紙の人形の「よれ」（湿り気）の配り役（damp.gd）。人より先に置く。人が名前（"Damp"）で探す
var badges: Badges            # 体の調子のバッジ（badges.gd）。湿り気・ご飯の効き目などが入れ、hud.gd が描く
var net: Net                  # 通信（net.gd）。--host でホスト、--join=IP でつなぐ
var start: Start              # スタート画面（start.gd）。引数なしで起動したときだけ
var seats: Seats              # ロッジの席（椅子・丸椅子・暖炉のまわりのソファ・揺り椅子・ビーズクッション・こたつの座布団）の配り役。人より先に置く


static func hill(x: float, z: float) -> float:
	return HILL_H * exp(-(x * x + z * z) / (2.0 * HILL_R * HILL_R))


## すり鉢: 底（半径 BOWL_R）で BOWL_D だけ下がる溝（cos² でなめらかに）と、底から外へ RIM_H まで上る高台
static func bowl(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var dip := 0.0
	var t := (r - BOWL_R) / BOWL_W
	if absf(t) < 1.0:
		var c := cos(t * PI * 0.5)
		dip = -BOWL_D * c * c
	return dip + RIM_H * smoothstep(BOWL_R, BOWL_R + RIM_W, r)


## ロッジでならす前の地面: 丘とくぼみと、南の大きな山と、東の大山
static func ground(x: float, z: float) -> float:
	return hill(x, z) + bowl(x, z) + Mountain.lift(x, z) + Grand.lift(x, z)


## 地面の端までの距離 (m)。地面は x ±128・z -128〜640 の長方形（丘と大きな山）と、東の大山の長方形。どちらにも入っていなければ負（一方の縁までの深さの大きいほう）
static func edge_gap(x: float, z: float) -> float:
	var hill_side := minf(minf(x + SIZE * 0.5, SIZE * 0.5 - x), minf(z - TILES_Z[0] + SIZE * 0.5, TILES_Z[TILES_Z.size() - 1] + SIZE * 0.5 - z))
	var grand_side := minf(minf(x - Grand.GX0, Grand.GX1 - x), minf(z - Grand.GZ0, Grand.GZ1 - z))
	# 2 つの長方形の重なる帯（丘の東の端から大山へ続く所）。継ぎ目は地面の端ではない
	var joined := minf(minf(x + SIZE * 0.5, Grand.GX1 - x), minf(z - TILES_Z[0] + SIZE * 0.5, Grand.GZ1 - z))
	return maxf(maxf(hill_side, grand_side), joined)


## ロッジの座標 (x, z) を世界の (x, z) へ
static func lodge_to_world(l: Vector2) -> Vector2:
	var c := cos(LODGE_YAW)
	var s := sin(LODGE_YAW)
	return LODGE_POS + Vector2(l.x * c + l.y * s, -l.x * s + l.y * c)


## くぼみからロッジへの道: 風除室の前（ロッジの座標 (PATH_X, 17)）から頂上の向きへ、くぼみの底まで。
## 踏み固めた雪の帯（見た目の色と、吹きだまりのうねりがないこと）。道の上で 1、外で 0。margin だけ幅を広げて測れる
const PATH_X := -13.4      # 風除室の中心（audio.gd の VEST.x と同じ）
const PATH_HALF := 1.6     # 道の半分の幅 (m)
const SIGN_SLOPE_AT := Vector2(PATH_X + 3.0, 31.0)   # 丘への案内板（ロッジの座標）。道の脇、広場の段（z 24.9 まで）と届いたソリの先
const PATH_TINT := Color(0.86, 0.88, 0.93)   # 踏み固めた雪の色（少し灰青に沈む）

static func path_weight(x: float, z: float, margin := 0.0) -> float:
	var a := lodge_to_world(Vector2(PATH_X, 17.0))
	var dir := -a.normalized()
	var d := Vector2(x, z) - a
	var along := clampf(d.dot(dir), 0.0, a.length() - BOWL_R)
	var off := (d - dir * along).length()
	return 1.0 - smoothstep(PATH_HALF + margin, PATH_HALF + margin + 1.2, off)


## ロッジの足もとで 0、離れると 1
static func lodge_weight(x: float, z: float) -> float:
	var d := Vector2(x, z) - LODGE_POS
	var c := cos(LODGE_YAW)
	var s := sin(LODGE_YAW)
	var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var q := Vector2(maxf(LODGE_PAD.position.x - l.x, l.x - LODGE_PAD.end.x),
			maxf(LODGE_PAD.position.y - l.y, l.y - LODGE_PAD.end.y))
	return smoothstep(0.0, LODGE_BLEND, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length())


static func height(x: float, z: float) -> float:
	return lerpf(ground(LODGE_POS.x, LODGE_POS.y), ground(x, z), lodge_weight(x, z))


static var _drift: FastNoiseLite

## 吹きだまりのうねりのもと（−1 〜 1）
static func _drift_at(x: float, z: float) -> float:
	if _drift == null:
		_drift = FastNoiseLite.new()
		_drift.seed = 5
		_drift.frequency = 0.06
		_drift.fractal_octaves = 3
	return _drift.get_noise_2d(x, z)


## 見た目の雪面だけにある吹きだまりのうねり（当たり判定にはない）。地面の 1 m 刻みの点の値
static func drift(x: float, z: float) -> float:
	return _drift_at(x, z) * 0.35 * lodge_weight(x, z) * (1.0 - maxf(maxf(path_weight(x, z), Mountain.path_weight(x, z)), Grand.path_weight(x, z))) * Grand.seam_fade(x, z)


## 見た目の雪面が当たり判定の地面からずれている量。1 m 刻みの点のあいだは直線でつなぐ（滑りあとを雪面に載せる用）
static func snow_lift(x: float, z: float) -> float:
	if Grand.on_ground(x, z):   # 大山の地面は 2 m おき
		var gx := floorf(x * 0.5) * 2.0
		var gz := floorf(z * 0.5) * 2.0
		var tx := (x - gx) * 0.5
		var tz := (z - gz) * 0.5
		return lerpf(lerpf(drift(gx, gz), drift(gx + 2, gz), tx), lerpf(drift(gx, gz + 2), drift(gx + 2, gz + 2), tx), tz)
	var x0 := floorf(x)
	var z0 := floorf(z)
	var fx := x - x0
	var fz := z - z0
	return lerpf(lerpf(drift(x0, z0), drift(x0 + 1, z0), fx), lerpf(drift(x0, z0 + 1), drift(x0 + 1, z0 + 1), fx), fz)


static var _snow_cache := {}   # 格子の点 → 見た目の雪面の高さ（滑りあとが何度も同じ点を読むので覚えておく）

static func _snow_vertex(x: float, z: float) -> float:
	var key := Vector2i(int(x), int(z))
	if _snow_cache.has(key):
		return _snow_cache[key]
	if _snow_cache.size() > 8192:
		_snow_cache.clear()
	var y := height(x, z) + drift(x, z)
	_snow_cache[key] = y
	return y


## 見た目の雪面の、(x, z) の所の向きと高さ Vector4(法線 x, y, z, 高さ)。地面の三角と同じ割り方（格子の対角線は右上から左下）で求めるので、
## 雪面にぴったり載る（滑りあと用）。snow_lift は格子の四隅をならした値なので、三角の中では数 cm ずれる
static func snow_plane(x: float, z: float) -> Vector4:
	var s := 2.0 if Grand.on_ground(x, z) else 1.0   # 大山の地面は 2 m おき
	var gx := floorf(x / s) * s
	var gz := floorf(z / s) * s
	var tx := (x - gx) / s
	var tz := (z - gz) / s
	var y10 := _snow_vertex(gx + s, gz)
	var y01 := _snow_vertex(gx, gz + s)
	var dx: float
	var dz: float
	var y: float
	if tx + tz <= 1.0:
		var y00 := _snow_vertex(gx, gz)
		dx = (y10 - y00) / s
		dz = (y01 - y00) / s
		y = y00 + dx * (x - gx) + dz * (z - gz)
	else:
		var y11 := _snow_vertex(gx + s, gz + s)
		dx = (y11 - y01) / s
		dz = (y11 - y10) / s
		y = y11 - dx * (gx + s - x) - dz * (gz + s - z)
	var n := Vector3(-dx, 1.0, -dz).normalized()
	return Vector4(n.x, n.y, n.z, y)


## 小物を雪に立てる高さ: 根もと（半径 r）のまんなかとまわり 8 か所で、見た目の雪面（吹きだまりを含む）がいちばん低い所。
## 斜面でも根もとが雪から浮かない（上りの側は雪に埋まる）。地形を変えても、置く所の高さはここから取る
static func foot_y(x: float, z: float, r := 0.3) -> float:
	var low := height(x, z) + snow_lift(x, z)
	for k in 8:
		var a := TAU * k / 8.0
		var px := x + cos(a) * r
		var pz := z + sin(a) * r
		low = minf(low, height(px, pz) + snow_lift(px, pz))
	return low


## 置いた小物（シーンに入れたあと）を、いちばん下の部分のどこも見た目の雪面から浮かないところまで下げる。
## 岩や雪のかたまりのように、斜面に沿わせて寝かせた物の仕上げに使う。沈めるのは形の高さの半分まで
func settle(n: Node3D) -> void:
	var pts := PackedVector3Array()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for sf in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX]:
				pts.append(m.global_transform * v)
	if pts.is_empty():
		return
	var low := INF
	var high := -INF
	for p in pts:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var gap := 0.0
	for p in pts:
		if p.y < low + (high - low) * 0.25:   # 下の 4 分の 1 の頂点
			gap = maxf(gap, p.y - (height(p.x, p.z) + snow_lift(p.x, p.z)))
	n.position.y -= minf(gap + 0.03, (high - low) * 0.5)


## 置く所の雪面の向き（上を向いた単位ベクトル）。岩や雪のかたまりを斜面に沿わせる用
static func ground_normal(x: float, z: float, e := 1.0) -> Vector3:
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	args.merge(Net.boot, true)   # スタート画面で選んだホスト・つなぐ
	if args.has("join"):
		# 仲間（CPU）はホストの画面だけが動かす。つなぐ側には、ホストから姿が届く（net.gd の "cpu"）。数はホストの --roam-bots など（一人で遊ぶときと同じ）
		args["bots"] = "0"
		args["lodge-bots"] = "0"
		args["roam-bots"] = "0"

	_make_world()
	_make_ground()
	craft = Craft.new()
	craft.name = "Craft"
	craft.world = self
	add_child(craft)
	if not args.has("no-lodge"):
		_make_lodge()
		_furnish_lodge()
		_put_mountain_man()
		seats = Seats.new()
		seats.name = "Seats"
		seats.lodge = get_node("Lodge")
		add_child(seats)

	sled = Sled.new()
	sled.kind = args.get("sled", "mid")
	sled.stitch_override = args.get("stitch", "")
	sled.trail_fade = args.get("trail-fade", sled.TRAIL_FADE)
	if args.has("sled-color"):
		sled.main_color = Color.from_string(args["sled-color"], Color(0, 0, 0, 0))
	sled.position = START + Vector3(0, height(START.x, START.z - 3) + 0.6 + sled.place_lift(), -3)   # 長いソリが坂に埋まらないように
	sled.snow_lift = snow_lift
	sled.snow_plane = snow_plane
	sled.name = "Sled"   # 出来事（snow_buttons.gd の snip）は、ソリを名前で指す
	add_child(sled)
	if args.has("sled-yaw"):   # 確かめ用: 最初からソリを横や逆に向けておく
		sled.rotation.y = deg_to_rad(float(args["sled-yaw"]))

	emotes = Emotes.new()
	emotes.name = "Emotes"
	add_child(emotes)
	duel = Duel.new()
	duel.name = "Duel"
	duel.world = self
	duel.hub = emotes
	duel.craft = craft
	add_child(duel)
	badges = Badges.new()
	badges.name = "Badges"
	add_child(badges)
	damp = Damp.new()
	damp.name = "Damp"
	damp.hub = emotes
	damp.badges = badges
	add_child(damp)

	# 通信は人より先に始める（人の番号を通信の番号にするため。emotes.gd の join）
	net = Net.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.start(args)
	if net.online:   # 湿り気の値は、その人の画面が決めて姿といっしょに送る（net.gd の "dv"。通信の相手の値は damp_from_net で受けるだけ）。
		# ホストは自分と仲間の値を配る（つなぐ側の down は何もしない）
		damp.sent.connect(func(ev: Dictionary): net.down("damp", ev))

	if not args.has("no-player"):
		player = Player.new()
		player.point_level = not args.has("point-tilt")   # 確かめ用: 指さしの手形を、前の腕に沿った向きに
		player.point_lift = float(args.get("point-lift", str(player.point_lift)))   # 確かめ用: 指さしの手形を目のほうへ起こす角度
		player.sled = sled
		player.position = START + Vector3(0, height(START.x, START.z) + 0.2, 0)
		add_child(player)
		player.look_at(sled.position, Vector3.UP)
		player.rotation.x = 0
		_add_pals(player)

	# 山をめぐる仲間（bot.gd の roam）。1 人目はゆき。はじめから、ばらけた所にいる
	var cast_named := args.has("bots") or args.has("lodge-bots") or args.has("no-player")   # 確かめの道具が仲間を指定している
	var roamers := int(args.get("roam-bots", "0" if cast_named else "5"))
	var pushers := int(args.get("bots", "1" if cast_named else "0"))
	for i in roamers:
		var spot: Array = ROAM_START[i % ROAM_START.size()]
		var at: Vector2 = spot[1]
		if args.has("roam-all-hill"):   # 確かめ用（いちばん重いとき）: みんな丘の、遊ぶ人のそばから
			spot = ["hill", Vector2(2.0 + 3.0 * i, 41.0)]
			at = spot[1]
		var b := Bot.new()
		b.sled = sled
		b.player = player
		b.roam = true
		b.side = 1 if i % 2 == 0 else -1
		if args.has("bot-dolls"):
			var ds: PackedStringArray = String(args["bot-dolls"]).split(",")
			b.doll_kind = ds[i % ds.size()]
		else:
			b.doll_kind = ROAM_DOLLS[i % ROAM_DOLLS.size()]
		b.position = Vector3(at.x, height(at.x, at.y) + 0.2, at.y)
		add_child(b)
		b.roam_from(spot[0])
		_bot_lantern(b, i)
		_add_pals(b)
	for i in pushers:
		var b := Bot.new()
		b.sled = sled
		b.player = player
		b.side = 1 if i % 2 == 0 else -1
		if args.has("bot-dolls"):
			var ds: PackedStringArray = String(args["bot-dolls"]).split(",")
			b.doll_kind = ds[i % ds.size()]
		b.lean_mode = args.get("bot-lean", "follow")
		b.position = START + Vector3(2.0 * b.side, height(START.x + 2.0 * b.side, START.z) + 0.2, 1)
		add_child(b)
		_bot_lantern(b, i)
		_add_pals(b)
	if seats:
		# ロッジでくつろぐ仲間: 食堂の空いた席に座った姿で始まる（bot.gd の lounge）
		for i in int(args.get("lodge-bots", "2" if cast_named else "0")):
			var b := Bot.new()
			b.sled = sled
			b.player = player
			b.side = 1 if i % 2 == 0 else -1
			var ld: PackedStringArray = String(args.get("lodge-dolls", "robo,ningyo,golem,musha")).split(",")
			b.doll_kind = ld[i % ld.size()]   # ロッジには 4 回目の人形たちがいる
			b.lounge = true
			b.position = get_node("Lodge").to_global(Vector3(6.0 + 3.0 * i, 0.6, -4.0))
			add_child(b)
			_bot_lantern(b, pushers + i)
			_add_pals(b)

	if args.has("duel-bot"):
		# 確かめ用: 雪合戦の対決をすぐ始められるように、あなたと最初の仲間に雪玉を 1 つ
		for c in get_children():
			if c.get_script() == Bot and not c.lounge:   # 山をめぐる仲間も
				emotes._set_balls(c.id, 1)
				break
		if player:
			emotes._set_balls(player.id, 1)
	if player and net.spawn_slot() > 0:
		# つなぐ側は、ホストの横に並んで始める（同じ所に重ならないように）
		var slot := net.spawn_slot()
		var at := START + Vector3(2.5 * ceili(slot / 2.0) * (1 if slot % 2 == 1 else -1), 0, 1.5)
		player.position = at + Vector3(0, height(at.x, at.z) + 0.2, 0)

	if not args.has("no-buttons"):
		snow_buttons = SnowButtons.new()
		snow_buttons.world = self
		add_child(snow_buttons)

	# 音（game/audio.gd）。--spawn=lodge でロッジの前から、--spawn=inside で食堂の中から始める（音の確かめ用）
	if not args.has("no-sound"):   # --no-sound は確かめ用: 音を入れない
		var audio := Audio.new()
		audio.name = "Audio"
		audio.setup(self, sled, player, get_children().filter(func(c): return c.get_script() == Bot), get_node_or_null("Lodge"))
		add_child(audio)
		_dress_speakers()
		_make_volume_buses()
		if args.has("buses"):   # 確かめ用: バスのつながりを出す
			for i in AudioServer.bus_count:
				print("bus %d %s -> %s" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])
	if player and args.has("spawn") and has_node("Audio"):
		player.global_position = get_node("Audio").spawn_point(args["spawn"])

	if player == null:
		var cam := Camera3D.new()
		cam.cull_mask &= ~PIP_SUN_LAYER   # 小窓用の太陽の写しは映さない
		add_child(cam)
		cam.position = Vector3(-30, 26, 40)
		cam.look_at(Vector3(0, 8, 10))
		if args.has("cam"):
			var v: PackedFloat64Array = args["cam"].split_floats(",")
			cam.position = Vector3(v[0], v[1], v[2])
			cam.look_at(Vector3(v[3], v[4], v[5]))

	if player and not args.has("no-pip"):
		_make_pip()
	if player and not args.has("no-selfcam"):   # 右下の、自分を前から映す小窓
		self_cam = SelfCam.new()
		self_cam.main = self
		self_cam.player = player
		add_child(self_cam)
	if not args.has("no-snow"):
		_make_snowfall(player if player else self)
	if player and not args.has("no-wind"):   # 滑るときの風（あなたの画面だけ）
		ride_wind = RideWind.new()
		ride_wind.setup(player, sled)
		add_child(ride_wind)

	# 設定画面（Esc）。保存してある値を起動時に当てる
	settings = Settings.new()
	add_child(settings)
	settings.changed.connect(_apply_setting)
	settings.to_start.connect(func(): net.leave())
	for key in settings.values:
		_apply_setting(key, settings.values[key])
	if get_tree().current_scene == self:
		use_game_pacing()
	if args.has("settings"):   # 確かめ用: 設定画面を開いた状態で始める
		settings.set_open(true)
		if player: player.menu_open = true

	call_deferred("_split_pip_layers")   # 全部が置かれたあとで

	hud = Hud.new()
	hud.main = self
	hud.debug_on = args.has("hud-debug") or settings.values.get("hud_debug", false)
	hud.hints_on = settings.values.get("hints", true)
	add_child(hud)

	if player:
		duel_hud = DuelHud.new()
		duel_hud.main = self
		duel_hud.duel = duel
		duel_hud.player = player
		add_child(duel_hud)
		craft_ui = CraftUi.new()
		craft_ui.main = self
		craft_ui.craft = craft
		craft_ui.player = player
		add_child(craft_ui)
		food_ui = FoodUi.new()
		food_ui.main = self
		food_ui.craft = craft
		food_ui.player = player
		food_ui.shop = snowman_shop
		add_child(food_ui)
		mountain_ui = MountainUi.new()
		mountain_ui.main = self
		mountain_ui.craft = craft
		mountain_ui.player = player
		mountain_ui.shop = mountain_man
		add_child(mountain_ui)
		# 山師が育てているミニオンの画面: pals_ui.gd を連れの段だけで開く（2 階の売り台の画面とは別のもの。2 階の売り台が
		# ほかの店に替わっても、ここは pals_ui.gd を直に読むので残る）
		minion_ui = preload("res://pals_ui.gd").new()
		minion_ui.name = "MinionUi"
		minion_ui.main = self
		minion_ui.craft = craft
		minion_ui.player = player
		minion_ui.tabs = ["pet"]
		minion_ui.board_color = MountainUi.FELT
		minion_ui.lead_tab = "mountain"   # 段の札の上の、山の道具の売り場へ戻る札
		minion_ui.lead_pressed.connect(func(): mountain_ui.open())
		add_child(minion_ui)
		if args.get("spawn", "") == "mountain" and mountain_man:   # --spawn=mountain: 山男の前から始める
			var at := mountain_man.to_global(Vector3(0, 0.1, -1.9))
			player.global_position = at
			var to := mountain_man.global_position
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		if wardrobe:
			wardrobe.player = player
		if mirror:
			mirror.player = player
		wardrobe_ui = WardrobeUi.new()
		wardrobe_ui.main = self
		wardrobe_ui.craft = craft
		wardrobe_ui.player = player
		add_child(wardrobe_ui)
		paper_shop_ui = PaperShopUi.new()
		paper_shop_ui.main = self
		paper_shop_ui.craft = craft
		paper_shop_ui.player = player
		add_child(paper_shop_ui)
		if paper_lady:
			paper_lady.player = player
			paper_lady.ui = paper_shop_ui
		if args.get("spawn", "") in ["paper_shop", "pals", "lanterns"] and paper_lady:   # --spawn=paper_shop: 紙細工屋さんの前から始める
			var at := paper_lady.to_global(Vector3(0.6, 0.1, 2.2))
			player.global_position = at
			var to := paper_lady.to_global(Vector3(0.6, 0.0, 0.0))
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		if dye_vat:
			dye_vat.player = player
		dye_ui = DyeUi.new()
		dye_ui.main = self
		dye_ui.craft = craft
		dye_ui.player = player
		add_child(dye_ui)
		sled_book_ui = SledBookUi.new()
		sled_book_ui.main = self
		sled_book_ui.craft = craft
		sled_book_ui.player = player
		add_child(sled_book_ui)
		if args.get("spawn", "") == "book" and sled_book:   # --spawn=book: 見本帳の前から始める
			player.global_position = sled_book.to_global(Vector3(0, 0.1, 2.6))
			var to := sled_book.global_position
			player.rotation.y = atan2(-(to.x - player.global_position.x), -(to.z - player.global_position.z))
		if args.get("spawn", "") == "dye" and dye_vat:   # --spawn=dye: 人台の桶を見下ろして始める
			var at := dye_vat.to_global(Vector3(0, 0.1, 2.6))
			player.global_position = at
			var to := dye_vat.global_position
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
			player._pitch = -0.6
		if args.get("spawn", "") == "wardrobe" and wardrobe:   # --spawn=wardrobe: 人台の前から始める
			var at := wardrobe.to_global(Vector3(0, 0.1, 2.6))
			player.global_position = at
			var to := wardrobe.global_position
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		if args.get("spawn", "") == "mirror" and mirror:   # --spawn=mirror: 大きな鏡の前から始める
			var at := mirror.to_global(Vector3(0, 0.1, 3.2))
			player.global_position = at
			var to := mirror.global_position
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		if args.get("spawn", "") == "shop" and shopkeeper:   # --spawn=shop: 売り子のおじさんの前から始める
			var at := shopkeeper.to_global(Vector3(0, 0.1, -1.9))   # 番台の向こう（客の側）。話しかけられる距離（2.2 m）の内
			player.global_position = at
			var to := shopkeeper.global_position
			player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))

	# 引数なしで起動した: スタート画面（一人・ホスト・つなぐ）。スタート画面からつなぎに行ったときは、つながるまで出しておく
	var waiting := Net.boot.has("join") and net.online and not net.joined()
	if Start.wanted(args) or waiting:
		start = Start.new()
		start.main = self
		start.waiting = waiting
		add_child(start)


## 山の道具の売り子（mountain_man.gd）: ロッジの 1 階の、大きなミシンの奥（北）の空き
## （2026-11-02 代表「山師ロッジの中に入れてあげよう。ミシンの奥空いてるし。」）。ミシンと同じ列（x）に、同じ向き（東。
## 客は東の通り道の側から話しかける）で立ち、棚は左手（北）に並べる（同日 代表「ミシンと同じ並び、同じ向きが良いです」）。
## ミシンの北の端から 3 m ほどあけ（ミシンは 2026-11-02 に南へ 2 m 寄せた）、後ろにヤク、左手（北）にソリの屋台とミニオンの柵と遊び場。
## [ロッジの座標 (x, y)（lodge/dims.py。y が北）, 正面の向き（度。0 = 南、90 = 東。SLOTS と同じ）, 棚の側（1 右手、-1 左手）]。
## 確かめ用に --mountain-at=x,y,度,棚の側 で置き直せる
const MOUNTAIN_MAN := [Vector2(-18.3, -0.9), 90.0, -1]   # ミシンを南へ寄せたぶん、山師も 1.5 m 南へ（北に出店と柵の場所をとる）

func _put_mountain_man() -> void:
	MountainGoods.all_on = args.has("shelf-all")   # 確かめ用: まだ売っていない品目も並べて売る
	var lodge: Node3D = get_node_or_null("Lodge")
	if lodge == null:
		return
	var at: Vector2 = MOUNTAIN_MAN[0]
	var deg: float = MOUNTAIN_MAN[1]
	var side: float = MOUNTAIN_MAN[2]
	if args.has("mountain-at"):
		var v: PackedFloat64Array = String(args["mountain-at"]).split_floats(",")
		at = Vector2(v[0], v[1])
		deg = v[2]
		side = v[3] if v.size() > 3 else 1.0
	mountain_man = MountainMan.new()
	mountain_man.name = "MountainMan"
	mountain_man.main = self
	mountain_man.craft = craft
	mountain_man.rack_side = side
	mountain_man.position = Vector3(at.x, LODGE_FLOOR, -at.y)
	mountain_man.rotation.y = deg_to_rad(deg) + PI   # 模型の正面は -Z（番台と同じ）
	lodge.add_child(mountain_man)


## ロッジの中から運び出せない大きさのソリ（craft.gd の OUT_FRONT）を、縫ったときに出す所: 玄関前の広場の先の雪の上。
## 向きは頂上（ロッジの正面と同じ）。重なる物があれば、横へずらす
const DELIVER_Z := 26.0   # ロッジの座標で正面へ (m)。高台の上、すり鉢の上り返しの手前（33 m だと坂の途中になる）

func delivery_spot(kind: String) -> Transform3D:
	var lodge: Node3D = get_node_or_null("Lodge")
	var yaw := LODGE_YAW + PI
	var k: Dictionary = Sled.KINDS.get(kind, Sled.KINDS["mid"])
	for dx in [0.0, 3.0, -3.0, 6.0, -6.0]:
		var p := lodge.to_global(Vector3(-13.4 + dx, 0, DELIVER_Z)) if lodge else START
		p.y = height(p.x, p.z)
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = k.box
		q.shape = box
		q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * (k.box.y * 0.5 + 0.3))
		var clear := true
		for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
			if not (r.collider is StaticBody3D and (r.collider as Node).get_child_count() > 0 and (r.collider as Node).get_child(0) is CollisionShape3D \
					and ((r.collider as Node).get_child(0) as CollisionShape3D).shape is HeightMapShape3D):
				clear = false
		if clear:
			return Transform3D(Basis(Vector3.UP, yaw), p)
	var p0 := lodge.to_global(Vector3(-13.4, 0, DELIVER_Z)) if lodge else START
	p0.y = height(p0.x, p0.z)
	return Transform3D(Basis(Vector3.UP, yaw), p0)


## 右上のライブ映像: 自分の頭の上に載せた 360° カメラの映像。
## 6 方向を同時に撮り、シェーダで 1 枚の全天球（正距円筒）に合成する。V でリトルプラネット
const FACE_PX := 160
const PIP_PHONE := Vector2(216, 384)    # スマホ向けの縦長 (9:16)。超広角の魚眼で切り出す
const PIP_EQ := Vector2(420, 210)       # 全天球の窓 (2:1)
const PIP_PLANET := Vector2(260, 260)   # リトルプラネットの窓
const PIP_SIZES := [PIP_PHONE, PIP_EQ, PIP_PLANET]
# 面ごとの [前 A, 上 U, 右 R]。シェーダ側も同じ向きで読む
const FACES := [
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],   # 前
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],   # 後ろ
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],    # 右
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],  # 左
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],    # 上
	[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],  # 下
]
const PIP_SHADER := """
shader_type canvas_item;
uniform sampler2D f0; uniform sampler2D f1; uniform sampler2D f2;
uniform sampler2D f3; uniform sampler2D f4; uniform sampler2D f5;
uniform int mode = 0;   // 0: 縦長の超広角魚眼  1: 全天球  2: リトルプラネット
uniform float aspect = 0.5625;   // 窓の 幅/高さ
uniform float vfov = 2.97;       // 魚眼の縦の画角 (rad)。170°
uniform float tilt = 0.17;       // 魚眼の中心を下へ向ける角 (rad)
uniform int face_back = 1;       // 1: 後ろ向き（背中側を中央に）

vec4 sample_face(int i, vec2 uv) {
	if (i == 0) return texture(f0, uv);
	if (i == 1) return texture(f1, uv);
	if (i == 2) return texture(f2, uv);
	if (i == 3) return texture(f3, uv);
	if (i == 4) return texture(f4, uv);
	return texture(f5, uv);
}

// 向き d をどの面のどこで読むか（カメラの座標: 前 -z, 上 +y, 右 +x）
vec4 sample_dir(vec3 d) {
	vec3 a = abs(d);
	int i; vec3 A; vec3 U; vec3 R;
	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { i = 2; A = vec3(1,0,0); U = vec3(0,1,0); R = vec3(0,0,1); }
		else { i = 3; A = vec3(-1,0,0); U = vec3(0,1,0); R = vec3(0,0,-1); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { i = 4; A = vec3(0,1,0); U = vec3(0,0,1); R = vec3(1,0,0); }
		else { i = 5; A = vec3(0,-1,0); U = vec3(0,0,-1); R = vec3(1,0,0); }
	} else {
		if (d.z < 0.0) { i = 0; A = vec3(0,0,-1); U = vec3(0,1,0); R = vec3(1,0,0); }
		else { i = 1; A = vec3(0,0,1); U = vec3(0,1,0); R = vec3(-1,0,0); }
	}
	float t = dot(d, A);
	vec2 uv = vec2(0.5 + 0.5 * dot(d, R) / t, 0.5 - 0.5 * dot(d, U) / t);
	return sample_face(i, uv);
}

void fragment() {
	vec3 d;
	if (mode == 0) {
		// 等距離射影の魚眼: 中央はふつうに、端へ行くほどぎゅっと縮む
		vec2 p = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;
		float r = length(p);
		float theta = r * vfov * 0.5;
		vec2 u = (r > 0.0001) ? p / r : vec2(0.0, -1.0);
		d = cos(theta) * vec3(0.0, 0.0, -1.0) + sin(theta) * (-u.y * vec3(0.0, 1.0, 0.0) + u.x * vec3(1.0, 0.0, 0.0));
		float cy = d.y * cos(tilt) + d.z * sin(tilt);
		float cz = -d.y * sin(tilt) + d.z * cos(tilt);
		d = vec3(d.x, cy, cz);
		if (face_back == 1) d = vec3(-d.x, d.y, -d.z);
		COLOR = sample_dir(d);
	} else if (mode == 1) {
		float lon = (UV.x - 0.5) * 6.2831853;
		float lat = (0.5 - UV.y) * 3.1415927;
		d = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
		COLOR = sample_dir(d);
	} else {
		vec2 p = (UV - 0.5) * 2.0;
		float r = length(p);
		if (r > 1.0) { COLOR = vec4(0.08, 0.1, 0.16, 1.0); }
		else {
			float theta = 2.0 * atan(r * 5.0);          // 真下 0 → 地平線 → 空
			float el = theta - 1.5707963;
			float phi = atan(p.x, -p.y);                 // 上が前
			d = vec3(sin(phi) * cos(el), sin(el), -cos(phi) * cos(el));
			COLOR = sample_dir(d);
		}
	}
}
"""

var pip_cams: Array[Camera3D] = []
var _pip_vps: Array[SubViewport] = []
var _pip_next := 0        # 次に描き直す面
var _pip_due := 0.0       # 描き直す面の数のたまり（1 たまるごとに 1 面）
var _pip_env: Environment # 小窓の面だけの軽い環境（陰・照り返し・にじみを描かない）
## 小窓は人形と同じ 12 fps で描き直す。6 面を一度に描くとそのコマだけ重くなるので、毎フレーム 1〜2 面ずつ順に描く
## （2026-11-01 代表「60fpsって出すの難しい？」。6 面を毎フレーム描いていて、M2 で 26 fps だった）
const PIP_FPS := 12.0
var pip_hidden := false
var settings: CanvasLayer
var ground_mesh: MeshInstance3D
var sun_light: DirectionalLight3D
var _pip_sun: DirectionalLight3D   # 小窓の面だけを照らす、影を落とさない太陽の写し
## 太陽を層で分ける: 本物（影を落とす）は層 8、小窓用の写し（影なし）は層 9。光はカメラの映す層で選ばれる。
## 小窓の 6 面が本物の太陽を見ると、面ごとに影の地図を描き直し、1 面で本体の画面と同じくらい重くなる
const SUN_LAYER := 1 << 7
const PIP_SUN_LAYER := 1 << 8
var env: Environment
var snowfall: GPUParticles3D
var ride_wind: Node3D
var _pip_layer: CanvasLayer
var self_cam: CanvasLayer
var pip_frame: PanelContainer
var pip_mat: ShaderMaterial
var pip_mode := 0


## 右上の 360° 映像は場面を 6 回描くので、小物・連れの動物・スピーカーの柱・遠景は層 4 にして映さない
## （描画回数が 7 倍になるのを防ぐ）。地面・木・ロッジの建物・ソリ・人は映す。本体のカメラは層 4 も映す
const PIP_SKIP_WORDS := ["prop", "kitchen", "companion", "pet", "speaker", "mound", "furnish", "machine", "vending"]
## ロッジの中身（床・階段・家具・灯りの道具）は、カメラがロッジの箱の中にいるときだけ映す。外から映す数は増やさないので、外の見え方も重さも変わらない。
## 1 階の床も中身の 1 つなので、映さないと床の下の雪が見えていた（2026-11-04 代表「ロッジの内側が魚眼カメラで描画されていません」）
const PIP_INSIDE_LAYER := 1 << 9
const PIP_INSIDE_MIN := 0.5   # これより小さい物（対角の長さ, m）は映さない。160 px の面では見えず、数だけ多い
var _pip_lodge_box := AABB()  # ロッジの建物（デッキとテラスも）の箱（ロッジの座標）。まだなければ大きさ 0
var _pip_inside := false      # カメラがロッジの箱の中にいるか

func _split_pip_layers() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	var lodge_inv := Transform3D.IDENTITY
	if lodge:
		lodge_inv = lodge.global_transform.affine_inverse()
		var body: Node = lodge.find_child("lodge_body", true, false)
		if body is VisualInstance3D:
			_pip_lodge_box = lodge_inv * (body as VisualInstance3D).global_transform * (body as VisualInstance3D).get_aabb()
	for m in find_children("*", "VisualInstance3D", true, false):
		if m == ground_mesh or m is Camera3D or m is Light3D:
			continue
		var top: Node = m
		while top.get_parent() != null and top.get_parent() != self:
			top = top.get_parent()
		if top == sled:
			continue   # ソリの glb の部品は名前に prop が付くが、ソリは映す
		var names := [top.name.to_lower(), m.name.to_lower()]
		var p := m.get_parent()
		if p and p != self:
			names.append(p.name.to_lower())
		var skip := false
		for w in PIP_SKIP_WORDS:
			for nm in names:
				if nm.contains(w):
					skip = true
		if top.name == "Lodge" and not m.name.to_lower().contains("lodge_body") and not m.name.to_lower().contains("door"):
			skip = true   # ロッジの外からは建物だけ映す。中身は箱の中にいるときだけ（下の PIP_INSIDE_LAYER）
		if skip:
			m.layers = 1 << 3
			if top == lodge:
				var box: AABB = lodge_inv * m.global_transform * m.get_aabb()
				if box.size.length() >= PIP_INSIDE_MIN and _in_pip_lodge_box(box.get_center()):
					m.layers |= PIP_INSIDE_LAYER


## ロッジの座標の点が、ロッジの箱の中か（高さは見ない）
func _in_pip_lodge_box(at: Vector3) -> bool:
	var b := _pip_lodge_box
	return b.has_volume() and at.x >= b.position.x and at.x <= b.end.x and at.z >= b.position.z and at.z <= b.end.z


## カメラがロッジの箱に出入りしたら、6 面に映す層を替える
func _sync_pip_inside() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	var inside := lodge != null and _in_pip_lodge_box(lodge.to_local(player.global_position))
	if inside == _pip_inside:
		return
	_pip_inside = inside
	for cam in pip_cams:
		cam.cull_mask = (cam.cull_mask | PIP_INSIDE_LAYER) if inside else (cam.cull_mask & ~PIP_INSIDE_LAYER)


func _make_pip() -> void:
	var textures: Array[Texture2D] = []
	for f in FACES:
		var vp := SubViewport.new()
		vp.size = Vector2i(FACE_PX, FACE_PX)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # 始めに 1 度。あとは _process が順に描く
		vp.mesh_lod_threshold = 6.0   # 160 px の面なので、形は粗くてよい（本体は 1.0）
		vp.positional_shadow_atlas_size = 0   # ランタンなどの点の灯りの影は描かない
		add_child(vp)
		_pip_vps.append(vp)
		var cam := Camera3D.new()
		cam.fov = 90.0
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.near = 0.08
		cam.cull_mask = (1 << 0) | (1 << 1) | PIP_SUN_LAYER   # 地面・ソリ・人・あなたの体と、影なしの太陽。手（層 3）と飾り（層 4）は映さない
		cam.far = 120.0
		cam.environment = _pip_env_of()
		vp.add_child(cam)
		cam.current = true
		pip_cams.append(cam)
		textures.append(vp.get_texture())
	_place_pip_cams()
	_pip_sun = DirectionalLight3D.new()
	_pip_sun.shadow_enabled = false
	_pip_sun.layers = PIP_SUN_LAYER
	add_child(_pip_sun)

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_pip_layer = layer
	pip_frame = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.22)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(5)
	sb.shadow_size = 14
	sb.shadow_color = Color(0.1, 0.15, 0.3, 0.2)
	pip_frame.add_theme_stylebox_override("panel", sb)
	layer.add_child(pip_frame)
	var view := ColorRect.new()
	var sh := Shader.new()
	sh.code = PIP_SHADER
	pip_mat = ShaderMaterial.new()
	pip_mat.shader = sh
	for i in 6:
		pip_mat.set_shader_parameter("f%d" % i, textures[i])
	pip_mat.set_shader_parameter("mode", pip_mode)
	view.material = pip_mat
	pip_frame.add_child(view)
	pip_label = Label.new()
	pip_label.add_theme_font_size_override("font_size", 13)
	pip_label.add_theme_color_override("font_color", Color.WHITE)
	pip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	pip_label.add_theme_constant_override("shadow_offset_y", 1)
	pip_label.visible = false   # 映像の上には文字も印も重ねない（2026-11-02 代表「小窓のカメラに LIVE とか小さい文字いろいろありますが全部消してほしい」）
	layer.add_child(pip_label)
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = Color(0.95, 0.2, 0.15)
	dot.visible = false
	layer.add_child(dot)
	_layout_pip()


## 3D を描く大きさ: 設定の「3D の描画の解像度」（縦 1080 px の画面での割合）に、画面の縦が 1080 px より大きいとき
## （Retina の全画面など）の縮めをかけ合わせ、FSR で広げる。HUD・文字・小窓はそのままの細かさ。
## --scale3d=割合 で、設定も画面の大きさも見ずにその割合で描く（確かめ用。1 なら縮めない）
const SCALE_3D_HEIGHT := 1080.0

var _fit_h := -1   # 3D の大きさを決めたときの画面の縦 (px)。窓の大きさが変わったら決め直す（起動の直後にも変わる）

func _fit_3d_scale() -> void:
	var vp := get_viewport()
	if vp.size.y == _fit_h:
		return
	_fit_h = vp.size.y
	var user: float = settings.values.get("scale", 0.67) if settings else 0.67
	var k := clampf(user * clampf(SCALE_3D_HEIGHT / maxf(vp.size.y, 1.0), 0.5, 1.0), 0.25, 1.0)
	if args.has("scale3d"):
		k = clampf(float(args["scale3d"]), 0.25, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if k < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = k


## 小窓の面の環境: 本体の環境の写しから、160 px の面では見えない重いもの（陰・色の照り返し・光のにじみ・空気の厚み）を抜く
func _pip_env_of() -> Environment:
	if _pip_env == null:
		_pip_env = env.duplicate()
		_pip_env.ssao_enabled = false
		_pip_env.ssil_enabled = false
		_pip_env.glow_enabled = false
		_pip_env.volumetric_fog_enabled = false
	return _pip_env


## 右上の 360° の小窓を出す・消す。pip_hidden は遊ぶ人の選び（P・設定）で、雪合戦のあいだ（duel_focus）はそれと別に消す
func _sync_pip_shown() -> void:
	if _pip_layer:
		_pip_layer.visible = not pip_hidden and not duel_focus


## 雪合戦で戦っているあいだ、ふだんの HUD をよけて一人称に固定する（2026-11-05 代表「タグやインベントリ、体力ゲージ、時間ゲージ、
## ミニマップ以外のHUDをよけることってできますか？集中して戦いたいので。あ、雪玉ストック数は避けなくていいです」「一人称視点固定にしてほしいです」）。
## 残す物: 名札の札（hud.gd）・持ち物の列と雪玉のストック（craft_ui.gd）・ハート・時計・円の地図（duel_hud.gd）。
## ここでよけるのは、右上の小窓・右下の刺繍枠とバッジ・日時計。案内のワッペン・糸巻き・確かめ用の数字（hud.gd）、I・N・R の札・財布（craft_ui.gd）は
## それぞれ duel_focus を見て描かない。遊ぶ人の選び（小窓の P・設定の刺繍枠・三人称）は書き換えないので、終わると元のとおりに戻る
func set_duel_focus(on: bool) -> void:
	duel_focus = on
	_sync_pip_shown()
	if self_cam:
		self_cam.set_focus_off(on)
	var dc := get_node_or_null("/root/DayCycle")
	var dial = dc.get("_dial") if dc else null
	if is_instance_valid(dial):
		dial.visible = not on
	if player:
		player.lock_first(on)


func _layout_pip() -> void:
	var size: Vector2 = PIP_SIZES[pip_mode]
	if pip_mat:
		pip_mat.set_shader_parameter("aspect", size.x / size.y)
	pip_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pip_frame.offset_left = -(size.x + 16)
	pip_frame.offset_right = -16
	pip_frame.offset_top = 16
	pip_frame.offset_bottom = 16 + size.y
	pip_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pip_label.offset_left = pip_frame.offset_left + 16
	pip_label.offset_right = pip_frame.offset_right - 8
	pip_label.offset_top = 28
	pip_label.offset_bottom = 48
	var dot: ColorRect = pip_label.get_parent().get_node("Dot")
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = pip_frame.offset_left + 18
	dot.offset_right = dot.offset_left + 8
	dot.offset_top = 34
	dot.offset_bottom = 42


## 6 台のカメラを、頭のてっぺんに、体の向きに合わせて置く（水平は固定）
func _place_pip_cams() -> void:
	var head: Vector3 = player.global_position + Vector3.UP * 2.35   # 帽子の先の少し上
	var yaw := Basis(Vector3.UP, player.rotation.y)
	for i in FACES.size():
		var f: Array = FACES[i]
		var A: Vector3 = f[0]
		var U: Vector3 = f[1]
		var R: Vector3 = f[2]
		pip_cams[i].global_transform = Transform3D(yaw * Basis(R, U, -A), head)


var _cloud_t := 0.0

func _process(_dt: float) -> void:
	_fit_3d_scale()
	_cloud_t += _dt
	if _cloud_t >= 0.5:   # 雲は 0.5 秒ごとに焼き直す
		_cloud_t = 0.0
		Look.tick_clouds(elapsed)
	_ft_max = maxf(_ft_max, _dt)
	_ft_sum += _dt
	_ft_n += 1
	if pip_cams.is_empty():
		return
	_place_pip_cams()
	if pip_hidden or duel_focus:
		_pip_due = 0.0
	else:
		_sync_pip_inside()
		_pip_env.ambient_light_energy = env.ambient_light_energy   # 時刻で変わる分（daycycle.gd）
		_pip_env.fog_light_color = env.fog_light_color
		_pip_sun.global_transform = sun_light.global_transform   # 時刻で変わる分（daycycle.gd）
		_pip_sun.light_color = sun_light.light_color
		_pip_sun.light_energy = sun_light.light_energy
		_pip_sun.light_angular_distance = sun_light.light_angular_distance
		_pip_sun.visible = sun_light.visible
		_pip_due = minf(_pip_due + _dt * PIP_FPS * FACES.size(), FACES.size())
		while _pip_due >= 1.0:
			_pip_due -= 1.0
			_pip_vps[_pip_next].render_target_update_mode = SubViewport.UPDATE_ONCE
			_pip_next = (_pip_next + 1) % FACES.size()


## 裏に回ったゲームは 15 コマ／秒に落とす。閉じ忘れた窓が CPU と GPU を使い続けて、手前で遊んでいるゲームまで遅くしていた
## （2026-11-05 測定。熱の余裕も食う）。物理は 1 コマに何歩でも進むので、ゲームの中の時間と通信は同じ速さで進む。
## 確かめの道具（-s で動かす）は current_scene が空なので、落とさない
const BACKGROUND_FPS := 15
const GAME_FPS := 60
var _game_pacing := false


func _notification(what: int) -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = BACKGROUND_FPS
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = GAME_FPS


## 遊ぶときのコマの出し方: 縦同期を切り、60 FPS で頭打ちにする。縦同期があると 1 コマが 16.7 ms を少し超えただけで
## 30 FPS に張りつく（ファンのない Air は熱で少し遅くなるので、遊んでいるうちに 60 → 30 と段差で落ちていた。2026-11-05 測定）。
## ズレが気になるときは設定の「縦同期」で戻せる。確かめの道具（-s）は、速く回せるように当てない
func use_game_pacing() -> void:
	Engine.max_fps = GAME_FPS
	_game_pacing = true
	_apply_setting("vsync", settings.values.get("vsync", false))


func _make_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Look.sky(self)
	if args.has("plain-sky"):   # 確かめ用: 雲の計算をしない空
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.50, 0.66, 0.88)
		psm.sky_horizon_color = Color(0.87, 0.91, 0.95)
		psm.ground_horizon_color = Color(0.87, 0.91, 0.95)
		var ps := Sky.new()
		ps.sky_material = psm
		env.sky = ps
	# 光（2026-10-28 代表「のっぺりして安っぽい。素材感が掴める光に。マイクラの影 MOD っぽく」）:
	# 強い暖色の陽と、空の青を映した暗めの影で、日なたと日かげの差をはっきりさせる。
	# 白い雪が飛ばないよう白の上限を高くし（ACES）、明るい所は光がにじみ、遠くは青く霞む。
	# 環境光の強さは daycycle.gd が時刻で決め直す
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.7
	env.tonemap_white = 6.0
	env.ssao_enabled = not args.has("no-ssao")          # くぼみに影が落ちる
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.1                         # 日なたは陽の色のまま、かげの側で効かせる
	env.ssil_enabled = not args.has("no-ssao")          # 色の照り返し（フェルトの色が近くの雪に移る）
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2
	env.glow_enabled = true                              # 明るい所が光ってにじむ
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true                               # 遠くは空の色に青く霞む。陽の側は明るく
	env.fog_light_color = Color(0.74, 0.82, 0.95)
	env.fog_density = 0.0016   # 南の大きな山（300〜500 m 先）が霞みすぎないよう
	env.fog_aerial_perspective = 0.4
	env.fog_sun_scatter = 0.08
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = args.has("vfog")   # 空気の厚みと光の筋（重いので確かめ用）
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_albedo = Color(0.92, 0.95, 1.0)
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 太陽: 低めの暖かい光。影は濃く、長く、遠くまで落とす。高さ・色・強さは daycycle.gd が時刻で決める
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -40, 0)
	sun.light_color = Color(1.0, 0.86, 0.70)
	sun.light_energy = 3.2
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110
	sun.directional_shadow_blend_splits = true
	sun.layers = SUN_LAYER
	sun_light = sun
	add_child(sun)

	# 遠景: 地平線にフェルトの山なみ。地面（x は ±128 m、z は -128〜640 m の長方形と、東の大山の長方形）の外周に沿って、すき間なく並べ、
	# 地面の端を隠す。高台の高さぶん持ち上げる。大山の地面に重なる分は並べない（乱数は引いておく。ほかの山の位置が変わらないように）
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var far_mat := Look.felt(Color(0.72, 0.79, 0.90), 0.3)
	var x0 := -SIZE / 2.0
	var x1 := SIZE / 2.0
	var z0: float = TILES_Z[0] - SIZE / 2.0
	var z1: float = TILES_Z[TILES_Z.size() - 1] + SIZE / 2.0
	var edges := [[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1)], [Vector2(x1, z0), Vector2(x1, z1), Vector2(1, 0)],
		[Vector2(x1, z1), Vector2(x0, z1), Vector2(0, 1)], [Vector2(x0, z1), Vector2(x0, z0), Vector2(-1, 0)],
		[Vector2(Grand.GX0, Grand.GZ0), Vector2(Grand.GX1, Grand.GZ0), Vector2(0, -1)], [Vector2(Grand.GX1, Grand.GZ0), Vector2(Grand.GX1, Grand.GZ1), Vector2(1, 0)],
		[Vector2(Grand.GX1, Grand.GZ1), Vector2(Grand.GX0, Grand.GZ1), Vector2(0, 1)]]
	var k := 0
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var out: Vector2 = e[2]
		var count := int(ceilf(a.distance_to(b) / 40.0))
		for q in count:
			var c: Vector2 = a.lerp(b, (q + rng.randf_range(0.2, 0.8)) / count) + out * rng.randf_range(0.0, 14.0)
			var sc := Vector3(rng.randf_range(45, 75), rng.randf_range(14, 26), rng.randf_range(30, 50))
			if out.x > 0.0 and c.y > Grand.GZ0 - 40.0 and c.y < Grand.GZ1 + 40.0 and c.x < Grand.GX1:   # 丘の東の端: 大山の地面が続く
				continue
			var m := MeshInstance3D.new()
			m.mesh = SphereMesh.new()
			m.material_override = far_mat
			m.position = Vector3(c.x, RIM_H - 3.0, c.y)
			m.scale = sc
			m.rotation.y = (0.0 if out.y != 0.0 else PI / 2) + rng.randf_range(-0.3, 0.3)   # 長い向きを地面の縁に沿わせる
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.name = "FarMound%d" % k
			add_child(m)
			k += 1
	# 山なみの外の雪原: 大山の頂上（高さ 144 m）からは山なみの向こうまで見下ろせるので、地面の外を空のままにしない。当たりはない
	const FAR := 5000.0
	var plain := SurfaceTool.new()
	plain.begin(Mesh.PRIMITIVE_TRIANGLES)
	plain.set_normal(Vector3.UP)
	for rc: Rect2 in [Rect2(-FAR, -FAR, FAR + x0, 2.0 * FAR), Rect2(Grand.GX1, -FAR, FAR - Grand.GX1, 2.0 * FAR),
			Rect2(x0, -FAR, Grand.GX1 - x0, FAR + Grand.GZ0), Rect2(x0, Grand.GZ0, x1 - x0, z0 - Grand.GZ0),
			Rect2(x1, Grand.GZ1, Grand.GX1 - x1, FAR - Grand.GZ1), Rect2(x0, z1, x1 - x0, FAR - z1)]:
		var e := rc.end
		for c in [Vector2(rc.position.x, rc.position.y), Vector2(e.x, rc.position.y), Vector2(rc.position.x, e.y),
				Vector2(rc.position.x, e.y), Vector2(e.x, rc.position.y), Vector2(e.x, e.y)]:
			plain.add_vertex(Vector3(c.x, RIM_H - 0.4, c.y))
	var plain_mi := MeshInstance3D.new()
	plain_mi.name = "FarMoundPlain"   # 名前に mound: 右上の 360° 映像には映さない（PIP_SKIP_WORDS）
	plain_mi.mesh = plain.commit()
	plain_mi.material_override = Look.snow()
	plain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plain_mi)


## ロッジ（game/lodge/lodge.tscn）。main.tscn に置いてあり、エディタでも見える。
## 位置と向きはここの定数（地面をならす範囲と同じ）で決め直す
func _make_lodge() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	if lodge == null:
		lodge = (load("res://lodge/lodge.tscn") as PackedScene).instantiate()
		add_child(lodge)
	lodge.position = Vector3(LODGE_POS.x, ground(LODGE_POS.x, LODGE_POS.y), LODGE_POS.y)
	lodge.rotation = Vector3(0, LODGE_YAW, 0)
	_shelter_snow(lodge)


## ロッジの機械の置き場の目印（slot_*。lodge/ の glb にある）に、props/ の機械を置く。
## どれも正面を南（ロッジの食堂の側、目印の +Z）へ向ける。目印のない古い glb なら何もしない
func _furnish_lodge() -> void:
	var lodge: Node3D = get_node_or_null("Lodge")
	if lodge == null:
		return
	var put := func(slot_name: String, path: String, offset: Vector3, yaw := PI) -> Node3D:
		var slot := lodge.find_child(slot_name, true, false) as Node3D
		if slot == null:
			return null
		var n := Props.make(path)
		n.position = offset
		n.rotation.y = yaw
		slot.add_child(n)
		return n
	# 機械は 2 倍（ミシンは貸出に収まるよう 1.5 倍）の大きさで書き出してある
	# 自販機は半分にして、前の箱の大きさ（高さ 1.83 m。代表「全部 前の箱の大きさに」）。食堂（1〜3）、
	# 風除室の自動ドアの左右（4・5）、外階段のミニテラス（6・7）。前は 4〜7 はロッジに箱を組んでいた。
	# 見た目の大きさの当たりの箱つき（人がすり抜けず、三人称のカメラも中に埋まらない）
	var vend_colors := ["red", "blue", "red", "red", "blue", "red", "blue"]   # 風除室は西が赤、東が青
	for k in range(1, 8):
		if k == 1:   # 西のガラスの壁ぎわの 1 台は、山師のミニオンの柵と遊び場に場所をゆずってやめた（2026-11-02 代表「自販機は撤去でもいいですよ」）
			continue
		var v: Node3D = put.call("slot_vending_%d" % k, "res://props/misc/vending_%s.glb" % vend_colors[k - 1], Vector3.ZERO)
		if v:
			v.scale = Vector3.ONE * 0.5
			_solid(v)
	var machine: Node3D = put.call("slot_craft_rental", "res://props/craft_machine.glb", Vector3.ZERO)
	if machine:   # ミシンの動き（そばで T で縫う。Y でコマ撮り、H で仲間を足踏みに）
		sewing = SewingMachine.new()
		sewing.name = "Sewing"
		sewing.world = self
		machine.add_child(sewing)
		# ミシンの横に、型紙と布の売り子（頭の上に品書きの看板）。ミシンの前の貸出のカウンター（塀）は lodge/ で外した
		shopkeeper = Shopkeeper.new()
		shopkeeper.name = "Shopkeeper"
		shopkeeper.world = self
		shopkeeper.position = SHOP_AT
		shopkeeper.rotation.y = SHOP_YAW
		machine.get_parent().add_child(shopkeeper)
	# 厨房: 巨大なアイロン台・プレス機・乾燥機と、卓上の道具（props/build_scenes.py の kitchen）
	var kitchen_slot := lodge.find_child("slot_food_kitchen", true, false) as Node3D
	if kitchen_slot:
		var set_node := (load("res://props/sets/kitchen.tscn") as PackedScene).instantiate()
		kitchen_slot.add_child(set_node)
		_put_kitchen(kitchen_slot)
		_put_snowman(kitchen_slot)
	# 1 階の暖炉と、まわりの居場所（ラグ・揺り椅子・ビーズクッション・大きなソファ。席の目印 nook_seat_* は seats.gd が拾う）
	var hs := lodge.find_child("slot_hearth", true, false) as Node3D
	if hs:
		hs.add_child(preload("res://hearth_nook.gd").new())
	# 2 階の掘りごたつ: 穴の目印に、こたつと座布団 8 枚の組（座布団の座る所の目印 sit_* は seats.gd が拾う）。
	# 屋根の下で日は届かないので、太陽の影は落とさない（影の地図に 8 組を描き直さない）
	for i in KOTATSU_SETS.size():
		var ks := lodge.find_child("slot_kotatsu_%d" % i, true, false) as Node3D
		if ks:
			var kset := (load("res://props/sets/kotatsu_lodge_%s.tscn" % KOTATSU_SETS[i]) as PackedScene).instantiate()
			ks.add_child(kset)
			KotatsuFuton.attach(kset)   # 座布団に座った人の側の布団をめくって、膝に掛ける
			var andon := Props.make("res://props/furniture/andon.glb")   # 灯りの目印に暖色の灯り（影なし）
			andon.scale = Vector3.ONE * 0.5
			andon.position = KOTATSU_ANDON * Vector3(1.0 if i % 2 else -1.0, 0, 1.0 if i < 4 else -1.0)
			ks.add_child(andon)
			_solid(andon)
			var hook := lodge.find_child("slot_pendant_%d" % i, true, false) as Node3D
			if hook:
				_hang_pendant(hook, hook.position.y - ks.position.y - KOTATSU_LAMP_TOP)
			for g in ks.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for b in BANDAI:
		_put_bandai(lodge, b)
	# ソリ屋の北どなりの、ソリの立てかけ台（前で F を押して、自分のソリを戻す・持ち出す。sled_rack.gd）
	var rack_slot := lodge.find_child("slot_sled_rack", true, false) as Node3D
	if rack_slot:
		sled_rack = preload("res://sled_rack.gd").new()
		sled_rack.name = "SledRack"
		rack_slot.add_child(sled_rack)
	# ミシンの近くの、布の見本帳（前で F を押して、自分のソリの色と滑りあとを替える）
	sled_book = preload("res://sled_book.gd").new()
	sled_book.name = "SledBook"
	sled_book.position = Vector3(SLED_BOOK_AT.x, 0.0, -SLED_BOOK_AT.y)
	sled_book.rotation.y = -PI / 2.0
	lodge.add_child(sled_book)
	if not args.has("no-lean-lights"):   # 下屋の吊り灯り（ソリ屋と立てかけ台の上。lean_lights.gd）
		var lean_lights: Node3D = preload("res://lean_lights.gd").new()
		lean_lights.name = "LeanLights"
		lean_lights.kind = String(args.get("lean-light", lean_lights.KIND_DEFAULT))
		lodge.add_child(lean_lights)
	# 1 階の人台: 人形の高さを見て F で人形を選び直す。桶を見下ろして F で服を染める
	wardrobe = Wardrobe.new()
	wardrobe.name = "Wardrobe"
	wardrobe.player = player
	wardrobe.position = Vector3(WARDROBE_AT.x, LODGE_FLOOR, -WARDROBE_AT.y)
	wardrobe.rotation.y = PI / 2.0   # 正面（+Z）を東へ
	lodge.add_child(wardrobe)
	dye_vat = DyeVat.new()
	dye_vat.name = "DyeVat"
	dye_vat.player = player
	dye_vat.craft = craft
	wardrobe.add_child(dye_vat)
	# 入口の横の大きな鏡: 前で F を押すと、自分の人形が大きく映る
	mirror = Mirror.new()
	mirror.name = "Mirror"
	mirror.player = player
	mirror.main = self
	mirror.position = Vector3(MIRROR_AT.x, LODGE_FLOOR, -MIRROR_AT.y)
	mirror.rotation.y = PI   # 正面（+Z）を北（部屋の側）へ
	lodge.add_child(mirror)
	# 紙細工屋さん: テントの中で、提灯と頭・肩の小物を売る
	paper_lady = PaperLady.new()
	paper_lady.name = "PaperLady"
	paper_lady.player = player
	paper_lady.craft = craft
	paper_lady.main = self
	paper_lady.position = Vector3(PAPER_LADY_AT.x, LODGE_FLOOR, -PAPER_LADY_AT.y)
	paper_lady.rotation.y = PI / 2.0   # 正面（+Z）を東へ
	lodge.add_child(paper_lady)


## 天井の目印 hook から、cord（m）のコードの先に吊り灯り（形は kind）を提げる
func _hang_pendant(hook: Node3D, cord: float, kind := KOTATSU_PENDANT) -> void:
	var p: Node3D = (load("res://props/furniture/pendant_%s.glb" % kind) as PackedScene).instantiate()
	for m in p.find_children("light*", "Node3D", true, false):   # 灯りの目印は外す（灯さない）
		if not m is MeshInstance3D:
			m.free()
	Props.dress(p)
	var k := KOTATSU_PENDANT_SCALE
	p.scale = Vector3.ONE * k
	p.position = Vector3(0, -cord, 0)
	hook.add_child(p)
	for c in p.find_children("*", "MeshInstance3D", true, false):   # コード（glb では 2 m）を天井まで
		var mi := c as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if "felt" in String(mi.name) or "thread" in String(mi.name):
			mi.scale.y = cord / (mi.get_aabb().size.y * k)


## 持ち主（あなた・仲間）に、頭・肩の小物とミニオン（companions.gd）を付ける。--bot-pals で仲間に付ける物を決める（確かめ用）
func _add_pals(host: Node3D) -> void:
	if args.has("no-pets"):
		return
	if host != player and args.has("bot-pals") and craft and int(host.get("id")) >= 0:
		var who := int(host.get("id"))
		for k in String(args["bot-pals"]).split(","):
			craft.send({"kind": "pal_own", "who": who, "key": k})
			craft.send({"kind": "pal_wear", "who": who, "slot": Pals.slot_of(k), "key": k})
	var c := Companions.new()
	c.host = host
	c.craft = craft
	add_child(c)


## --bot-lanterns の i 番目の形を、仲間に持たせて提げる（あなたと同じ出来事。ほかの人の画面にも、その人のランタンが見える）
func _bot_lantern(b: Node3D, i: int) -> void:
	if not args.has("bot-lanterns") or craft == null or int(b.get("id")) < 0:
		return
	var ls: PackedStringArray = String(args["bot-lanterns"]).split(",")
	var look := ls[i % ls.size()]
	var who := int(b.get("id"))
	craft.send({"kind": "lantern_own", "who": who, "look": look})
	craft.send({"kind": "equip", "who": who, "gear": "lantern", "index": craft.lantern_index(who, look)})


## 番台 1 つ: パッチワーク（または藍）のフェルトを張った木のカウンター。上に、店番の側を向いたレジと、払いを受けるお皿。
## お皿には、おじいさんはお金のボタン、雪だるまは雪玉を盛る（文字は使わない）。カウンターに当たりの箱
func _put_bandai(lodge: Node3D, b: Array) -> void:
	var at: Vector2 = b[3]
	var root := Node3D.new()
	root.name = "Bandai_" + String(b[0])
	root.position = Vector3(at.x, 0.0 if b[2] == "buttons" else LODGE_FLOOR, -at.y)   # おじいさんの番台は外の下屋の雪の上
	root.rotation.y = deg_to_rad(b[4]) + PI   # 模型の正面は -Z
	lodge.add_child(root)
	var counter: Node3D
	if b[2] == "snowballs":   # 雪だるまの番台は畳める（props/build_snowman.py の snowman_counter。実寸。組み立ては fridge_door.gd）
		counter = Props.make("res://props/snowman_counter.glb")
	else:
		counter = Props.make("res://props/counter/%s.glb" % b[0])
		counter.scale = BANDAI_SCALE
	root.add_child(counter)
	var top := BANDAI_BOX.y
	var reg := Props.make("res://props/counter/%s.glb" % b[1])
	reg.name = "Register"
	reg.scale = Vector3.ONE * 0.45
	reg.position = Vector3(0.6, top, 0.06)
	reg.rotation.y = PI + 0.25                # 打ち鍵を店番の側へ
	root.add_child(reg)
	var dish := Props.make("res://props/counter/tray_round_red.glb")
	dish.name = "Dish"
	dish.scale = Vector3.ONE * 0.5
	dish.position = Vector3(-0.5, top, -0.08)
	root.add_child(dish)
	if b[2] == "snowballs" and snowman_shop:   # 雪だるまの番台: 話しかける所と、ペレットを跳ばすお皿
		snowman_shop.counter = root
		snowman_shop.dish_at = dish.position
	if b[2] == "buttons":   # おじいさんの番台: パッチワークのカーテン（ふだんは閉じて、人が近づくと開く）
		var curtain := BandaiCurtain.new()
		curtain.name = "Curtain"
		curtain.shopkeeper = shopkeeper
		curtain.world = self
		root.add_child(curtain)
	var heap := Node3D.new()
	heap.name = "Heap"
	heap.position = dish.position + Vector3.UP * 0.03
	root.add_child(heap)
	if b[2] == "buttons":   # 木・真鍮・白蝶貝のボタンを重ねて
		for i in 3:
			var btn := Props.make("res://props/snow_button/%s.glb" % ["snow_button", "snow_button_brass", "snow_button_pearl"][i])
			btn.scale = Vector3.ONE * 0.24
			btn.position = Vector3(-0.05 + 0.06 * i, 0.012 * i, 0.03 * (i % 2))
			btn.rotation = Vector3(0.12 * (i - 1), 0.9 * i, 0.0)
			heap.add_child(btn)
	else:                   # 羊毛の雪玉を 3 つ
		var ball := SphereMesh.new()
		ball.radius = 0.065
		ball.height = 0.13
		ball.material = Look.snow()
		for p in [Vector3(-0.05, 0.06, 0.0), Vector3(0.07, 0.06, 0.03), Vector3(0.01, 0.17, 0.01)]:
			var mi := MeshInstance3D.new()
			mi.mesh = ball
			mi.position = p
			heap.add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.name = "CounterShape"
	var box := BoxShape3D.new()
	box.size = BANDAI_BOX
	col.shape = box
	col.position.y = BANDAI_BOX.y / 2.0
	body.add_child(col)
	root.add_child(body)


## 置いた物 n に、見た目（MeshInstance3D）を包む箱の当たり判定を付ける。null なら何もしない
func _solid(n: Node3D) -> void:
	if n == null:
		return
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = inv * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = box.get_center()
	body.add_child(col)
	n.add_child(body)


## 厨房の巨大な調理の装置を KITCHEN の並びで 1 台ずつ置く（調理で動かすので、小物の場面には結合しない）。
## スチーマーのふた（giant_vapor_lid）は目印 lid に付ける。装置ごとに調理の動き（cook_station.gd）を付ける
func _put_kitchen(slot: Node3D) -> void:
	for k in KITCHEN:
		var dev := Props.make(k[1])
		dev.name = "Kitchen_" + String(k[0])
		dev.position = k[2]
		dev.rotation.y = deg_to_rad(k[3])
		slot.add_child(dev)
		kitchen[k[0]] = dev
		var body := StaticBody3D.new()
		for b in k[4]:
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = b[0]
			col.shape = box
			col.position = b[1]
			body.add_child(col)
		dev.add_child(body)
		var hinge := dev.find_child("lid", true, false) as Node3D
		if hinge:
			var lid := Props.make("res://props/kitchen/giant_vapor_lid.glb")
			lid.name = "Lid"
			hinge.add_child(lid)
		var st := CookStation.new()   # F で手のペレットを入れて調理する
		st.name = "Station"
		st.main = self
		st.kind = k[0]
		dev.add_child(st)
		stations.append(st)


## 厨房の奥の並びのいちばん西（ミシンの右）に、扉を開けた冷蔵庫と、中に立つご飯係の雪だるま（props/build_snowman.py）。
## 正面は食堂（+Z）、扉は人が近づくと装置の並びと反対の側へ開く（fridge_door.gd）。雪だるまは段ごとの節点（base・chest・head・arm_l・arm_r）を回せば動く（まだ動かさない）
func _put_snowman(slot: Node3D) -> void:
	var fridge := Props.make("res://props/snowman_fridge.glb")
	fridge.name = "SnowmanFridge"
	fridge.position = SNOWMAN_AT
	fridge.rotation.y = PI
	fridge.scale = Vector3.ONE * SNOWMAN_SCALE
	slot.add_child(fridge)
	var spot := fridge.find_child("snowman_spot", true, false) as Node3D
	if spot:
		var man := Props.make("res://props/snowman.glb")
		man.name = "Snowman"
		spot.add_child(man)
		snowman_shop = SnowmanShop.new()   # 番台ごしにペレットを売る（売り場は food_ui.gd）
		snowman_shop.name = "SnowmanShop"
		snowman_shop.main = self
		snowman_shop.man = man
		add_child(snowman_shop)
	var body := StaticBody3D.new()   # 冷蔵庫の箱（中の雪だるまごと。扉は通れる）
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = FRIDGE_BOX
	col.shape = box
	col.position.y = FRIDGE_BOX.y / 2.0
	body.add_child(col)
	fridge.add_child(body)
	var door := FridgeDoor.new()   # 扉は人が近づくと開いて番台が組み立ち、離れると番台を畳んで閉じる
	door.name = "FridgeDoor"
	door.main = self
	fridge.add_child(door)


## 舞う雪: 羊毛のふわふわが、あなたのまわりでゆっくり落ちる
func _make_snowfall(follow: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 500
	p.lifetime = 14.0
	p.preprocess = 10.0
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 2, 32)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.35, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var flake := SphereMesh.new()
	flake.radius = 0.045
	flake.height = 0.09
	flake.radial_segments = 6
	flake.rings = 3
	p.draw_pass_1 = flake
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1, 0.9)
	fm.roughness = 1.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = fm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT   # ロッジの屋根の箱（_shelter_snow）に当たった粒は消える
	p.position = Vector3(0, 22, 0)
	follow.add_child(p)
	snowfall = p
	p.top_level = false


## 雪よけ: ロッジの建物を見えない箱（GPUParticlesCollisionBox3D）で包み、舞う雪の粒が当たったら消す
## （2026-11-02 代表「ロッジの中もゆきふっちゃってる」）。中にいるあいだ雪を止めるのではなく、建物の形で雪を止めるので、
## 窓や開いた戸の外では今までどおり降り、戸口を出入りしても雪がぱっと消えたり出たりしない。
## 箱はロッジの座標（glb: x 東、y 上、z 南。lodge/dims.py の x, 高さ, -y）。デッキ・テラスは箱に入れない
const SHELTER_1F := AABB(Vector3(-22.1, -1.0, -13.0), Vector3(44.2, 7.0, 26.0))     # 1 階: 外の壁から 0.3 m 外まで、テラスの床（FL2 6.1）の下まで
## 2 階: 西の壁（dims.X2_0 = -11.82。西の端はテラス）から東の壁の 0.3 m 外まで、北の軒（1 m）から南の軒（2 m）まで、北の屋根の下（10.3）まで
const SHELTER_2F := AABB(Vector3(-12.12, 6.0, -13.73), Vector3(34.22, 4.3, 21.18))
const SHELTER_LEAN := AABB(Vector3(-30.2, -1.0, -12.9), Vector3(8.1, 4.8, 25.8))     # 外の下屋（ソリ屋と立てかけ台の上。dims.LEAN の屋根の外の端の高さ 3.6 m より少し上まで）
const SHELTER_VEST := AABB(Vector3(-17.8, -1.0, 12.7), Vector3(8.8, 7.4, 5.2))      # 風除室: 両脇の丸太の端まで、前はアーチ戸の外面まで
const ROOF_N := Vector2(-13.73, 10.72)    # 2 階の屋根（雪を載せた上面）の北の軒先 (z, 高さ)
const ROOF_S := Vector2(7.45, 13.96)      # 南の軒先。片流れなので、2 階の箱の上に屋根なりに傾けた板を重ねる
const ROOF_SLAB := 4.0                    # 傾けた板の厚み。南の端で 2 階の箱の上端より下まで届く

func _shelter_snow(lodge: Node3D) -> void:
	for b in [SHELTER_1F, SHELTER_2F, SHELTER_VEST, SHELTER_LEAN]:
		var c := GPUParticlesCollisionBox3D.new()
		c.size = b.size
		c.position = b.get_center()
		lodge.add_child(c)
	var slope := ROOF_S - ROOF_N
	var slab := GPUParticlesCollisionBox3D.new()
	slab.basis = Basis(Vector3.RIGHT, -atan2(slope.y, slope.x))   # 南（+z）ほど高い
	slab.size = Vector3(SHELTER_2F.size.x, ROOF_SLAB, slope.length())
	var top := (ROOF_N + ROOF_S) / 2.0
	slab.position = Vector3(SHELTER_2F.get_center().x, top.y, top.x) - slab.basis.y * ROOF_SLAB / 2.0
	lodge.add_child(slab)


func _make_ground() -> void:
	var half := SIZE / 2.0
	var z0: float = TILES_Z[0] - half
	var rows := int(TILES_Z[TILES_Z.size() - 1] + half - z0) + 1
	# 高さは 1 m おきに 1 回だけ計算し、当たり判定と見た目で使い回す。まわり 1 点ずつ広げる（法線用）
	var g := SIZE + 3
	var gr := rows + 2
	var hs := PackedFloat32Array()   # 当たり判定の高さ
	var vs := PackedFloat32Array()   # 見た目の雪面の高さ（吹きだまりのうねりを足す）
	hs.resize(g * gr)
	vs.resize(g * gr)
	for j in gr:
		for i in g:
			var x := i - 1 - half
			var z := j - 1 + z0
			var h := height(x, z)
			hs[j * g + i] = h
			vs[j * g + i] = h + drift(x, z)
	var at := func(i: int, j: int) -> float: return hs[(j + 1) * g + i + 1]   # i: x + half、j: z - z0

	# 当たり判定: 丘の 1 枚（257 点四方）と、大きな山の 1 枚（513 点四方。x の ±128 m の外は縁の高さを延ばす）。
	# 山のコースは継ぎ目のない 1 枚に載せる（別々の地形の継ぎ目では、重いソリが段に引っかかって止まる）。
	# 2 枚の継ぎ目は z = 128 m の平らな高台（ロッジの裏）
	var n := SIZE + 1
	var hill_h := PackedFloat32Array()
	hill_h.resize(n * n)
	for j in n:
		for i in n:
			hill_h[j * n + i] = at.call(i, j)
	_add_height_body(hill_h, n, Vector3(0, 0, TILES_Z[0]))
	var m := SIZE * 2 + 1
	var mz0 := int(TILES_Z[0] + half - z0)   # 山の 1 枚の北の端の行
	var mtn_h := PackedFloat32Array()
	mtn_h.resize(m * m)
	for j in m:
		var jj := mini(mz0 + j, rows - 1)
		for i in m:
			mtn_h[j * m + i] = at.call(clampi(i - SIZE / 2, 0, SIZE), jj)
			if i - SIZE / 2 > SIZE and jj + z0 < Grand.GZ1:   # 大山の当たりと重なる所は、窪地より下へ下げておく
				mtn_h[j * m + i] = RIM_H - 2.0
	_add_height_body(mtn_h, m, Vector3(0, 0, TILES_Z[0] + half + SIZE))

	# 見た目: 256 m 四方ずつ。1 m 刻み、頂点を共有してなめらかに。法線は格子から出すので、継ぎ目で影がずれない
	var snow := Look.snow()
	snow.vertex_color_use_as_albedo = true   # 道の踏み固めた色
	for t in TILES_Z.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in n:
			var jr := t * SIZE + j
			for i in n:
				var x := i - half
				var z := jr + z0
				var c := (jr + 1) * g + i + 1
				st.set_normal(Vector3(vs[c - 1] - vs[c + 1], 2.0, vs[c - g] - vs[c + g]).normalized())
				st.set_color(Color.WHITE.lerp(PATH_TINT, maxf(path_weight(x, z), Mountain.path_weight(x, z))))
				st.set_uv(Vector2(x, z) * 0.5)
				st.add_vertex(Vector3(x, vs[c], z))
		for j in n - 1:
			for i in n - 1:
				var a := j * n + i
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(a + n)
				st.add_index(a + n)
				st.add_index(a + 1)
				st.add_index(a + n + 1)
		st.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = "Ground%d" % t
		mesh.mesh = st.commit()
		mesh.material_override = snow
		if ground_mesh == null:
			ground_mesh = mesh
		add_child(mesh)
	_make_grand_ground(snow)
	var mt := Mountain.new()
	mt.name = "Mountain"
	mt.world = self
	add_child(mt)
	var gm := Grand.new()
	gm.name = "GrandMountain"
	gm.world = self
	add_child(gm)
	_make_hill_trees()


## 東の大山（grand_mountain.gd）の地面。広いので、見た目も当たりも 2 m おき（丘と大きな山は 1 m おき）。
## 見た目は 128 m 四方ずつに分ける（画面の外の分を描かないように）。SurfaceTool は頂点が多いと遅いので、配列から直に作る
## （雪の素材は三面投影なので、UV と接線は要らない）。
## 当たりは 513 点四方を 2 倍に広げた 1 枚で、山の全部を継ぎ目なく載せる。丘と大きな山の地面との継ぎ目（x = 128 m）は平らな高台
func _make_grand_ground(snow: Material) -> void:
	const STEP := 2
	const CHUNK := 64   # 1 枚のマス数（128 m）
	var nx := int((Grand.GX1 - Grand.GX0) / STEP) + 1
	var nz := int((Grand.GZ1 - Grand.GZ0) / STEP) + 1
	# まわり 1 点ずつ広げて、高さを 1 回だけ計算する（法線用）
	var g := nx + 2
	var hs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	var tint := PackedFloat32Array()
	hs.resize(g * (nz + 2))
	vs.resize(g * (nz + 2))
	tint.resize(g * (nz + 2))
	for j in nz + 2:
		var z := Grand.GZ0 + (j - 1) * STEP
		for i in g:
			var x := Grand.GX0 + (i - 1) * STEP
			var h := RIM_H + Grand.lift(x, z)
			var pw := Grand.path_weight(x, z)
			hs[j * g + i] = h
			vs[j * g + i] = h + _drift_at(x, z) * 0.35 * (1.0 - pw) * Grand.seam_fade(x, z)
			tint[j * g + i] = pw
	# 当たり
	var m := SIZE * 2 + 1
	var col_h := PackedFloat32Array()
	col_h.resize(m * m)
	col_h.fill(RIM_H)
	var off := (m - nz) / 2   # 南北のまんなかにそろえる
	for j in nz:
		for i in nx:
			col_h[(j + off) * m + i] = hs[(j + 1) * g + i + 1]
	var center := Vector3(Grand.GX0 + SIZE * STEP, 0, Grand.GZ0 + (nz - 1) * 0.5 * STEP)
	_add_height_body(col_h, m, center, float(STEP))
	# 見た目
	var cn := CHUNK + 1
	var ids := PackedInt32Array()
	ids.resize(CHUNK * CHUNK * 6)
	var q := 0
	for j in CHUNK:
		for i in CHUNK:
			var a := j * cn + i
			ids[q] = a
			ids[q + 1] = a + 1
			ids[q + 2] = a + cn
			ids[q + 3] = a + cn
			ids[q + 4] = a + 1
			ids[q + 5] = a + cn + 1
			q += 6
	var k := 0
	for cj in (nz - 1) / CHUNK:
		for ci in (nx - 1) / CHUNK:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(cn * cn)
			norms.resize(cn * cn)
			cols.resize(cn * cn)
			for j in cn:
				for i in cn:
					var c := (cj * CHUNK + j + 1) * g + ci * CHUNK + i + 1
					var x := Grand.GX0 + (ci * CHUNK + i) * STEP
					var z := Grand.GZ0 + (cj * CHUNK + j) * STEP
					var v := j * cn + i
					verts[v] = Vector3(x, vs[c], z)
					norms[v] = Vector3(vs[c - 1] - vs[c + 1], 2.0 * STEP, vs[c - g] - vs[c + g]).normalized()
					cols[v] = Color.WHITE.lerp(PATH_TINT, tint[c])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = ids
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "GrandGround%d" % k
			mi.mesh = am
			mi.material_override = snow
			add_child(mi)
			k += 1


## 地形の当たり判定を 1 枚足す（n 点四方、step m おき、まんなかが center）
func _add_height_body(heights: PackedFloat32Array, n: int, center: Vector3, step := 1.0) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var body := StaticBody3D.new()
	body.position = center
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	body.physics_material_override = pm
	add_child(body)


func _make_hill_trees() -> void:
	# 木（ソリの通り道は空ける）。フェルトの円錐を 2 段重ねたミニチュアの木（props/build_tree.py の glb）
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_round.glb",
		"res://props/tree_little.glb"]
	for k in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(32, 90)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 20 and abs(p.x) < 14:
			continue
		if lodge_weight(p.x, p.z) < 1.0 or path_weight(p.x, p.z, 2.0) > 0.0:   # ロッジと道に重ねない
			continue
		var h := rng.randf_range(4, 8)
		var tree := Props.make(TREES[k % TREES.size()])
		tree.scale = Vector3.ONE * h / 6.0
		tree.position = p + Vector3(0, foot_y(p.x, p.z, 0.35 * h / 6.0) - 0.05, 0)
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
	_make_slope_props()
	var flags := preload("res://area_flags.gd").new()   # 山の目印の大きな旗（標高の札と同じ布）
	flags.name = "AreaFlags"
	flags.main = self
	add_child(flags)


## 斜面の小物（props/build_slope.py・build_snow.py の glb）。当たり判定はまだない（見た目だけ）
func _make_slope_props() -> void:
	# コースの旗: 登り道の両脇に、赤と藍を交互に
	var i := 0
	for z in [34.0, 27.0, 20.0, 13.0]:
		for x in [-9.0, 9.0]:
			_put_prop("res://props/flag_%s.glb" % ("red" if i % 2 == 0 else "navy"), x, z, 0.4 if x < 0 else PI - 0.4)
			i += 1
	# 案内板（文字なし）: スタートの横に、ロッジ（風除室の前）への矢印。表はスタートの側へ
	var entrance := lodge_to_world(Vector2(PATH_X, 17.0))
	_put_sign("res://props/sign_lodge.glb", Vector2(5.0, 41.0), entrance, Vector2(START.x, START.z))
	# ロッジの前の道の脇に、丘（頂上）への矢印。表は道の側へ。前は広場の縁の段の上に立っていて、矢印も横を向いていた。
	# 届いたソリが並ぶ所（DELIVER_Z の前後 2.4 m）より先に立てる
	_put_sign("res://props/sign_slope.glb", lodge_to_world(SIGN_SLOPE_AT), Vector2.ZERO, lodge_to_world(Vector2(PATH_X, SIGN_SLOPE_AT.y)))
	# 毛糸の安全ネット: 登り道の右の外れに 4 区間と、終わりの杭
	for k in 5:
		var net := _put_prop("res://props/net_span.glb", 13.0, 30.0 - 2.5 * k, PI / 2)
		if k == 4:
			for n in net.find_children("*", "MeshInstance3D", true, false):
				if "_yarn" in n.name or "_knots" in n.name:
					n.visible = false
	# 岩と雪のかたまり: 丘のまわりに散らす（登り道とロッジは空ける）
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	const LUMPS := ["res://props/rock_a.glb", "res://props/rock_b.glb", "res://props/rock_c.glb",
		"res://props/snow_pile_a.glb", "res://props/snow_pile_b.glb", "res://props/snow_drift.glb"]
	for k in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22, 85)
		var x := cos(a) * r
		var z := sin(a) * r
		if z > 8 and abs(x) < 16:
			continue
		if lodge_weight(x, z) < 1.0 or path_weight(x, z, 1.0) > 0.0:
			continue
		_put_prop(LUMPS[k % LUMPS.size()], x, z, rng.randf() * TAU, 0.0, true)


## 小物を雪に立てる。r は根もとの半径（foot_y）。lay: 岩や雪のかたまりは斜面に沿わせて、まんなかの雪面へ少し沈める
func _put_prop(path: String, x: float, z: float, yaw: float, r := 0.3, lay := false) -> Node3D:
	var n := Props.make(path)
	if lay:
		var up := ground_normal(x, z, 1.5)
		n.basis = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
		n.position = Vector3(x, height(x, z) + snow_lift(x, z) - 0.06, z)
	else:
		n.position = Vector3(x, foot_y(x, z, r) - 0.05, z)
		n.rotation.y = yaw
	add_child(n)
	if lay:
		settle(n)
	return n


## 案内板を at（世界の x, z）に立てる。板の矢印（glb の +X）が target をまっすぐ指し、表（アップリケの面、glb の -Z）が
## reader の側を向くように回す。表を reader へ向けると矢印が逆を向くときは、左右に映す（家とソリの絵も映るが、絵は矢印の向きにそろう）
func _put_sign(path: String, at: Vector2, target: Vector2, reader: Vector2) -> Node3D:
	var d := (target - at).normalized()
	var mirror := Vector2(d.y, -d.x).dot(reader - at) < 0.0   # 映さないときの表の向きが reader と逆
	var n := _put_prop(path, at.x, at.y, atan2(d.y, -d.x) if mirror else atan2(-d.y, d.x))
	if mirror:
		n.scale.x = -1.0
	return n


## 音（audio.gd）が立てた柱の仮の見た目を隠し、フェルトのスピーカーの柱に着せ替える。ラッパは丘を向く
func _dress_speakers() -> void:
	for post in find_children("SpeakerPost*", "Node3D", true, false):
		for n in post.find_children("*", "MeshInstance3D", true, false):
			n.visible = false
		var look := Props.make("res://props/speaker_pole.glb")
		look.scale = Vector3.ONE * Audio.POST_H / 5.0
		var d := -Vector2(post.position.x, post.position.z)
		look.rotation.y = atan2(-d.x, -d.y)
		post.add_child(look)


func _physics_process(dt: float) -> void:
	elapsed += dt
	var s := sled.global_position
	var top := Vector2(s.x, s.z).length()

	# --sim: あなたが W を押し続けたことにする（吸い付き→押すの確かめ用）
	# --sim=rope: 先にソリの前に回って紐を持ち、それから W で歩く（引く確かめ用）
	# --sim=side: 先にソリの横に立ち、それから W で押す（横から押す確かめ用）
	if args.has("sim") and player and elapsed > 1.0 and not _sim_sent:
		_sim_sent = true
		var fwd: Vector3 = -sled.global_basis.z
		if args["sim"] == "rope":
			player.global_position = sled.to_global(Vector3(0, 0, -2.6)) + Vector3.UP * 0.2
			player.rotation.y = atan2(-fwd.x, -fwd.z)
			player.grab_rope()
		elif args["sim"] == "side":
			player.global_position = sled.to_global(Vector3(2.0, 0, 0)) + Vector3.UP * 0.2
			var inward: Vector3 = -sled.global_basis.x
			player.rotation.y = atan2(-inward.x, -inward.z)
		if args["sim"] == "left":
			player.global_position = sled.to_global(Vector3(-2.0, 0, 0)) + Vector3.UP * 0.2
			var inward: Vector3 = sled.global_basis.x
			player.rotation.y = atan2(-inward.x, -inward.z)
			player.grab()
			var eva := InputEventKey.new()
			eva.physical_keycode = KEY_A
			eva.pressed = true
			Input.parse_input_event(eva)
			return
		if args["sim"] == "turn":
			player.global_position = sled.to_global(Vector3(0, 0, 2.4)) + Vector3.UP * 0.2
			player.rotation.y = atan2(-fwd.x, -fwd.z)
			player.grab()
			var evd := InputEventKey.new()
			evd.physical_keycode = KEY_D
			evd.pressed = true
			Input.parse_input_event(evd)
			return
		if args.has("third"):
			player.third = true
			player.cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | SUN_LAYER
		if args["sim"] == "1":
			player.grab()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if args.has("sim") and player and _sim_sent and player.mode == player.Mode.GRIP and args["sim"] == "1":
		var fwd: Vector3 = -sled.global_basis.z
		player.rotation.y = atan2(-fwd.x, -fwd.z)
	if args.has("log"):
		_duty += 1 if sled.pushers > 0 else 0
		_frames += 1
		log_t += dt
		if log_t >= float(args.get("log-every", "1")):
			log_t = 0.0
			var bots := get_children().filter(func(c): return c.get_script() == Bot)
			var bd: float = bots[0].global_position.distance_to(s) if bots.size() > 0 else 0.0
			var me := ("　あなた=%s 向き=%.0f°" % [["歩く", "つかむ", "乗る", "紐"][player.mode], rad_to_deg(player.rotation.y)]) if player else ""
			me += "　ソリ向き=%.0f° 速さ=%.2f 保持=%s" % [rad_to_deg(sled.rotation.y), sled.linear_velocity.length(), sled.hold_debug]
			me += "　つかんでいる人=%d 回転=%.2f 横滑り=%.2f" % [sled.holders.size(), sled.angular_velocity.y, sled.linear_velocity.dot(sled.global_basis.x)]
			if bots.size() > 0:
				me += "　仲間=%s" % bots[0].debug
			if has_node("Audio"):
				me += "　" + get_node("Audio").debug
			print("fps=%d コマ 平均%.1fms 最長%.1fms " % [Engine.get_frames_per_second(), 1000.0 * _ft_sum / maxi(_ft_n, 1), 1000.0 * _ft_max], "t=%.0f 高さ=%.2f 頂上まで=%.1f 押していた割合=%.0f%% 乗る人=%d 仲間との距離=%.1f%s" % [elapsed, s.y, top, 100.0 * _duty / _frames, sled.riders.size(), bd, me])
			_duty = 0
			_frames = 0
			_ft_max = 0.0
			_ft_sum = 0.0
			_ft_n = 0

	if args.has("shot") and elapsed > float(args.get("shot-at", "4")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("保存: ", args["shot"])
		get_tree().quit()
	if args.has("quit-at") and elapsed > float(args["quit-at"]):
		get_tree().quit()


## ソリをふもとに戻す（Backspace。通信ではホストの画面だけ。net.gd）
func reset_sled() -> void:
	sled.reset_to(START + Vector3(0, height(START.x, START.z - 3) + 0.6, -3))


## 音量の区分のバス。音楽は Speaker → Music → Outdoor、効果音は Inside・Self → SFX → Master、
## ボイスは Voice → Master。audio.gd の環境のバス（Outdoor・Inside）はそのまま生かす。
## 送り先は自分より前のバスにしか指定できないので、挿す位置に注意する
func _make_volume_buses() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "SFX")
	AudioServer.set_bus_send(1, "Master")
	AudioServer.add_bus(2)
	AudioServer.set_bus_name(2, "Voice")
	AudioServer.set_bus_send(2, "Master")
	var o := AudioServer.get_bus_index("Outdoor")
	if o >= 0:
		AudioServer.add_bus(o + 1)
		AudioServer.set_bus_name(o + 1, "Music")
		AudioServer.set_bus_send(o + 1, "Outdoor")
		var sp := AudioServer.get_bus_index("Speaker")
		if sp >= 0:
			AudioServer.set_bus_send(sp, "Music")
	else:
		AudioServer.add_bus(3)
		AudioServer.set_bus_name(3, "Music")
		AudioServer.set_bus_send(3, "Master")
	for b in ["Inside", "Self"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_send(i, "SFX")


func _set_volume(buses: Array, v: float) -> void:
	for b in buses:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _apply_setting(key: String, v) -> void:
	match key:
		"vol_music":
			_set_volume(["Music"], v)
		"vol_sfx":
			_set_volume(["SFX", "Wind", "OutdoorSfx"], v)   # 風と外の効果音は Outdoor の処理を通したいので、バスの音量で合わせる
		"vol_voice":
			_set_volume(["Voice"], v)
		"bob":
			if player: player.bob_enabled = v
			if ride_wind: ride_wind.calm = not v   # 揺れを切った人には、風も控えめに
		"wind":
			if ride_wind: ride_wind.strength = v
		"fov_kick":
			if player: player.fov_kick_enabled = v
		"ride_fov":
			if player: player.ride_fov_enabled = v
		"ride_fov_amt":
			if player: player.ride_fov_amount = v
		"pip":
			pip_hidden = not v
			_sync_pip_shown()
		"selfcam":
			if self_cam: self_cam.set_shown(v)
		"snow":
			if snowfall: snowfall.emitting = v; snowfall.visible = v
		"third":
			if player: player.set_third(v)
		"cam_dist":
			if player: player.cam_dist = v
		"cam_frame":
			if player: player.cam_frame = v
		"fov":
			if player: player.base_fov = v
		"sens":
			if player: player.mouse_sens = v
		"scale":
			_fit_h = -1   # 窓の大きさの縮めとかけ合わせて当て直す（_fit_3d_scale）
			_fit_3d_scale()
		"vsync":
			if _game_pacing:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"glow":
			if env: env.glow_enabled = v
		"ssao":
			if env:
				env.ssao_enabled = v
				env.ssil_enabled = v   # 照り返しも同じく重いので一緒に
		"shadows":
			if sun_light: sun_light.shadow_enabled = v
		"hints":
			if hud: hud.hints_on = v
		"hud_debug":
			if hud: hud.debug_on = v or args.has("hud-debug")


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(start):   # スタート画面のあいだは、キーで何もしない
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE and settings:
			settings.set_open(not settings.is_open)
			if player: player.menu_open = settings.is_open
			return
		if e.physical_keycode == KEY_BACKSPACE:   # R はランタンの点け消し（player.gd）
			net.reset_sled()   # 通信でつないでいるときは、ホストが戻す
		elif e.physical_keycode == KEY_P and _pip_layer:
			# 右上の 360° 映像を消す／出す（消している間は描画もしない）
			pip_hidden = not pip_hidden
			_sync_pip_shown()
			settings.sync("pip", not pip_hidden)
		elif e.physical_keycode == KEY_V and pip_mat:
			pip_mode = (pip_mode + 1) % 3
			pip_mat.set_shader_parameter("mode", pip_mode)
			_layout_pip()
