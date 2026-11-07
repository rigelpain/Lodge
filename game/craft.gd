extends Node
## 工房の配り役。型紙と布を買う・ミシンにセットする・縫い上がる・ソリを畳む・広げる を、
## 「誰が・何を・いつ（姿勢の時計のコマ）」の短い出来事 {kind, who, frame, ...} にして配る（emotes.gd と同じ形）。
## 中身は数・文字・Vector3 だけにして、そのまま通信に乗せられるようにする。who は人の番号（emotes.gd の join でもらう）。
##
## いまは一人の画面の中だけ: send() がすぐ frame を付けて _apply() し、みんな（持ち主・ミシン・画面）に配る。
## 通信を入れたら: send() はホストへ送るだけにし、ホストが値段・持ち物の空き・ソリの置き場を確かめてから全員に配る。
## 財布と持ち物はホストが持つ（ここの wallets と bags）。断られた出来事は配らない（send が false を返す）。
##
## 出来事:
##   buy    {item}             売り子から買う。item は {kind:"pattern", sled} か {kind:"fabric", fabric}（おじいさん）、
##                             山男の棚の品物（mountain_goods.gd の SHELF。焚き火セット・ペグ）。ev に slot が入る
##   hand   {slot}             手に持つ物を替える（-1 は素手）
##   sew    {pattern, fabric, pattern_slot, fabric_slot}  ミシンの画面で選んだ型紙と布を 1 つずつ使って縫い始める（両方いっしょに使う。ミシンが読む）
##   sewn   {sled, fabric, at, yaw, id}  ミシンが縫い上げた。広げた実寸のソリが at に出る
##   fold   {id, item}         置いてあるソリを畳んで、持ち物に入れる（畳む動きは origami.gd）。item に名札の柄 tag も入る
##   unfold {slot, item, at, yaw, up, id}  畳んだソリを手から前の床に広げて置く（up は床の傾き）
##   sack_out  {at, yaw, up, v}  装備の米袋（いま選んでいるもの）を足もとに出す（2026-10-29 代表: 米袋は装備。持ち物の列は使わない）。
##                             v は出した人の勢い（初めの速さ。走りながら出すと滑り出す）
##   sack_in   {}              出している米袋を、くるっと丸めて帯に戻す
##   tag_design {design}       自分の「いつもの柄」を決める（装備の画面）。これから縫うソリに付く名札。いまあるソリの名札は替えない
##   sled_tag {design, id | slot | loose}  ソリごとの名札の柄を替える（装備の画面）。id は置いてある自分のソリ、slot は持ち物の
##                             畳んだソリ、loose は名札入れの外した名札の番号（2026-10-31 代表「タグはソリごとにデザインできるべき」）
##   untag     {id}            自分のソリから名札を外して、持ち主をやめる（ソリの名札のそばで G を長押し）。名札は帯の名札入れに戻り、
##                             ソリは持ち主のいないソリ（名札なし）になる。だれでも乗れて、畳める
##   tag_on    {id, loose}     名札入れの名札を、持ち主のいない名札なしのソリに付けて、持ち主になる（同じく G を長押し）。
##                             ロッジのソリ（ロッジの名札が付いている）には付けられない
##   profile   {name, color}   自分の名前と、キャラの色（COLORS の番号）を決める（装備の画面）。HUD の札で、人の形の色と頭の上の名前になる
##   doll      {doll}          自分の人形（doll.gd の KINDS のどれか）を替える（2 階の衣装掛け）。みんなの画面で、その人の人形が作り直される。
##                             入った時にも今の人形で 1 度送る（通信では、あとから来た人もこれでほかの人の人形を知る）
##   dye       {doll, colors}  2 階の染め桶で、人形 doll の服を部位ごとに染める。colors は部位ごとの色 4 つ（"rrggbb"。"" はもとの色。
##                             outfit.gd の PARTS の順。前の保存の 1〜2 色は outfit.gd の upgrade で部位に直す）。染め代は別の色に染める部位の数で
##                             決まる（DYE_PRICES。ev に price が入る。もとの色に戻す脱色はただ）。色は自由に選べ、色ではなく染め代を 1 回ごとに払う（2026-11-01 代表「全部買う、染色桶をつくって、
##                             色に払うんじゃなくて染色代として払う」）。染めた色は人形ごとに残る（ほかの人形に着替えて戻っても同じ色）
##   outfit    {doll, colors}  保存してある染めた色を戻す（起動したとき。値はここでは取らない）
##   equip     {gear, index}   装備の画面（craft_ui.gd）で、その種類（gear）の持っている物から装備する物を替える。
##                             ランタンは index -1 で外す（外すと消える）
##   lamp      {on}            帯のランタンを点ける・消す（R キー。2026-10-29 代表）。提げていなければ断る
##   lantern_buy {look}        1 階のテントの紙細工屋さん（paper_lady.gd）で、形違いのランタン（lantern.gd の LOOK）を買う。
##                             買ったらすぐ帯に提げる（ev に index が入る）。通信ではほかの人の画面でも、その人のランタンが替わる
##   lantern_own {look}        持っているランタンを戻す（保存から。値は取らない。tag_unlock と同じ扱い）
##   pal_buy   {key}           頭・肩の小物（1 階のテントの紙細工屋さん paper_lady.gd）かミニオン（1 階の山師）を買う（pals.gd）。買ったらすぐ身につける（ev に slot が入る）
##   pal_own   {key}           持っている小物・ミニオンを戻す（保存から。値は取らない。tag_unlock と同じ扱い）
##   pal_wear  {slot, key}     頭（head）・肩（shoulder）・連れ（pet）に、持っている物を付ける。key が "" なら外す。
##                             みんなの画面で、その人の小物とミニオンが替わる（companions.gd）
##   food_buy  {item}          雪だるまの店でペレットを買う（item は food.gd の {kind:"food", dish, step:0}）。雪玉で払う（emotes.gd の spend）
##   cook      {slot, station} 手のペレット（料理の途中）を厨房の装置に入れる。持ち物から出て、装置が持つ（cook_station.gd）
##   bite      {slot}          手の料理をひと口食べる（3 口でなくなる。ev.ate に料理の名前が入る。食べても体の調子は変わらない。雰囲気づくりの道具）
##   cooked    {station}       装置が仕上げた物を、入れた人の持ち物に戻して手に持たせる。いっぱいなら断る（装置に残る）。
##                             ホストが装置の仕上がり（一段進んだ item）を確かめて ev に入れる。できあがりのときはホストの装置が出し（auto）、
##                             装置に残った物は入れた人が F でもう一度出す
##   dry_in    {}              手にペレットを持たずに、厨房の乾燥機に入る（空いていて、誰も調理していなければ。cook_station.gd）
##   dry_out   {}              乾燥機から出る（中の人の画面が決める: 乾ききったか、F）
##   fire_lay  {slot, at, yaw, up}  手の焚き火セット（{kind:"campfire"}。売り子のおじさんから buy で買う）を、前の雪の上に組んで火をつける
##                             （campfire.gd。組める所は player.gd の fire_spot が決める）。セットは持ち物から消える。ev に id が入る。
##                             一人ひとつ: 前に組んだ自分の焚き火が燃えていれば、そちらは消える
##   fire_out  {id}            自分の焚き火に雪をかけて消す（F）。消えた焚き火は少しして片づく
##   peg       {slot, sled, at}  手のペグの束から 1 本を、ソリ（sled は main からのパス）の前の雪の at に刺し、引き紐の先を結ぶ。
##                             ソリはそこに留まる（sled.gd の peg_to）。束の本数が 0 になれば持ち物から消える。ev.color に玉の色
##   unpeg     {sled}            ソリのペグを抜く（誰でも。抜いたペグは使い切りで消える）。ソリはまた滑れる
##   rack_in   {id, u}         自分のソリ（id）を立てかけ台（sled_rack.gd）へ戻す。ほかの人が乗っている・つかんでいる・紐を持っていても戻せて、その人たちはその場で降りる・手が離れる
##                             （2026-11-06 代表）。ペグで留めている間は断る。
##                             ソリはその場で折り紙に畳まれて消え、台に現れる。u は台の置き場（ホストが決める）。名札のないソリは対象外
##   rack_out  {id, at, yaw}   台の自分のソリを、前の雪の上へ持ち出す（ホストが空いた所を決める）
##   scope_on  {}              テラスの双眼鏡台（binocular_stand.gd）をのぞき始める。だれかがのぞいていれば断る。雪玉が 1 個あれば雪玉で、なければ木のボタン 1 枚で
##                             払う（2026-11-07 代表「双眼鏡台は木のボタン1枚か雪玉で起動してほしい」）。ev.paid に "ball" か "button" が入る。どちらもなければ断る
##   scope_off {}              双眼鏡台から離れる（のぞいている本人。時間が来たとき、F・Esc のとき。帰った人の分はホストが送る）
##   earn      {n, at}         ボタンが n 個、財布に入る（雪に縫い留められたボタンを取った。snow_buttons.gd がホストとして分けて送る）。
##                             at は取った所（画面でそこから財布へ飛ぶ）。雪合戦の対決の払い（duel.gd）も、これで勝った人へ
##   stake     {n}             雪合戦の対決の掛金 n 個を、財布から預ける（duel.gd がホストとして出す。払いは earn）
## 装備は種類ごとに「持っている物の配列」と「装備している番号」を持つ（GEARS）。いまは米袋とランタン。服や名札の柄を足すときは、
## GEARS に種類を足し、_gear_lists に持ち物の配列の入れ物を足す
## 米袋は全員が最初から 1 つ（標準）持つ。米袋の型紙と布で縫った米袋は、持ち物でなく装備の枠に入り、選ばれる
## ランタンも全員が最初から持ち、帯の左に提げている（消えた状態で始まる）。形は lantern.gd の LOOKS（{look}）。
## 木の手提げ（標準）と和紙の提灯の 2 つを最初から持つ。ほかの 8 つは番台の横のランタン掛けで売る（2026-11-01 代表）

signal happened(ev: Dictionary)

const Doll := preload("res://doll.gd")
const Sled := preload("res://sled.gd")
const Fabrics := preload("res://fabrics.gd")
const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")
const Food := preload("res://food.gd")
const MountainGoods := preload("res://mountain_goods.gd")

## お金はボタン（snow_buttons.gd）。最初に START_BUTTONS 個（木の何個分）持たせる。米袋の型紙と布はすぐ買えるが、小はまだ（少し滑って稼いでから）
const START_BUTTONS := 30
## お金のボタンの 4 段（2026-10-30 代表）。財布の中はいままでどおり「木のボタンの何個分」で持ち、見せるときに段ごとに分ける（両替はひとりでに）。
## 大きい段から: 螺鈿 1000・白蝶貝 100・真鍮 10・木 1。絵は craft_icons.gd の money、斜面のボタンは snow_buttons.gd の TIERS
const MONEY := [[1000, "raden"], [100, "pearl"], [10, "brass"], [1, "wood"]]
## 型紙の値段（木の何個分）。ソリの倍率を上げて稼ぎが増えたので上げた（2026-10-30 代表「あとお店の値段」）。
## 最初の小は、米袋で漕いで丘を 3 分ほど、大は、中に 3 人で大きな山を 6 分半・小ひとりで 11 分・米袋ひとりで 20〜50 分ほど（design/snow-buttons の表）
const PATTERN_PRICE := {"sack": 20, "small": 100, "mid": 400, "large": 1500}
const FABRIC_PRICE := 10
## ペグの名前・値段・束の本数は peg.gd（品目の定義をそこにまとめる）
const Peg := preload("res://peg.gd")
const Stitches := preload("res://stitches.gd")
## 染め代（木の何個分）。何色でも、布 1 枚でも 2 枚でも、1 回染めるごとに
## 1 回に染める部位の数ごとの染め代（0〜4 部位）。部位が多いほど高く、まとめて染めると 1 部位ぶんずつは少し安い
## （2026-11-03 代表「部位数ごとに値段を上げてほしい」）
const DYE_PRICES := [0, 15, 25, 33, 40]
const PATTERNS := ["sack", "small", "mid", "large"]
## 大きすぎて、そのまま出すと動かしにくいソリ（ミシンが中にあった頃は運び出せなかった。ミシンは外の下屋へ移したが、届け方は変えていない）。
## 縫うと、ロッジの前（main.gd の delivery_spot）に、空から包みが落ちて折り紙のように開いて出てくる
const OUT_FRONT := ["large"]
const SLOTS := 12              # 持ち物に入る数（手持ち HAND_SLOTS ＋ かばん）
const HAND_SLOTS := 6          # 手持ち: 画面の下の列に並び、ホイールで持ち替える。残りはかばん（装備の画面で入れ替える）
                               # （2026-11-01 代表「手持ちが6で、かばんにもう6つはいってるようなイメージで、計12アイテムを持ち運べる」）
const RACK_FOLD_SPEED := 2.0   # 立てかけ台へ呼ぶときの畳む動きの速回し（広げる長さの半分、約 1.3 秒で台に現れる）
const FOLD_FRAMES := 30        # 畳む動きの長さ（コマ。12 コマで 1 秒）
const UNFOLD_FRAMES := 30      # 広げる動きの長さ

var world: Node                # main.gd（ソリを置く所）
var replay := false            # つなぐ側で、ホストが確かめた出来事をなぞっている（この画面の間合いで断らない）
var wallets := {}              # 人の番号 → ボタンの数
var bags := {}                 # 人の番号 → 持ち物（SLOTS 個の場所の配列。空いた場所は {}。0〜5 が手持ち、6〜11 がかばん）
var hands := {}                # 人の番号 → 手に持つ持ち物の番号（-1 は素手）
var sleds := {}                # ソリの番号 → 縫った・広げたソリ（畳めるソリ）
var racked := {}               # ソリの番号 → 立てかけ台の置き場（sled_rack.gd の X）
var _next_sled := 1
var fires := {}                # 焚き火の番号 → 組んだ焚き火（campfire.gd）
var _next_fire := 1
const GEARS := ["sack", "lantern"]   # 装備の種類（装備の画面の並び）
var tag_designs := {}          # 人の番号 → 自分の名札（sled_tags.gd の部品の辞書）。通信では「誰が」の印として配る
var tag_owned := {}            # 人の番号 → 手に入れた「あとで手に入る」名札の部品 {部品: [番号, ...]}（最初から使える部品は書かない）
var stitch_owned := {}         # 人の番号 → 買った滑りあとの柄の名前の配列（stitches.gd。標準の柄は入れない）
var sacks := {}                # 人の番号 → 持っている米袋の配列 [{fabric}]（0 番は標準。米袋に名札は付けない）
var loose_tags := {}           # 人の番号 → 帯の名札入れの、外した名札の柄の配列（付け直せる）
var names := {}                # 人の番号 → 名前（装備の画面で決める。HUD の札で頭の上に出す）
var colors := {}               # 人の番号 → キャラの色（COLORS の番号）
var dolls := {}                # 人の番号 → 人形（doll.gd の KINDS。衣装掛けで替える）
var outfits := {}              # 人の番号 → {人形: 布ごとの色 ["rrggbb" か ""]}（染め桶で染めた服の色。染めていない人形は書かない）
var sack_sel := {}             # 人の番号 → 装備している米袋の番号（N でこれが出る）
var sack_out := {}             # 人の番号 → いま出している米袋（ソリ）
var _sack_far := {}            # 人の番号 → 持ち主が離れていた秒
var lanterns := {}             # 人の番号 → 持っているランタンの配列 [{look}]（0 番は標準）
var lantern_sel := {}          # 人の番号 → 提げているランタンの番号（-1 は外している）
var lamps := {}                # 人の番号 → ランタンが点いているか
var pals_owned := {}           # 人の番号 → 持っている頭・肩の小物とミニオンの名前の配列（pals.gd）
var pals_wear := {}            # 人の番号 → {head, shoulder, pet} 身につけている物の名前（"" は付けていない）
## キャラの色（装備の画面で選ぶ。はじめは人の番号の順に、赤・藍・からし…）。フェルトの色で、名札の窓の生成りの上で見分けられる濃さ
const COLORS := [Color(0.80, 0.24, 0.20), Color(0.24, 0.32, 0.55), Color(0.88, 0.66, 0.20), Color(0.25, 0.52, 0.34),
	Color(0.55, 0.30, 0.58), Color(0.92, 0.50, 0.22), Color(0.22, 0.58, 0.66), Color(0.84, 0.40, 0.56),
	Color(0.45, 0.30, 0.18), Color(0.40, 0.62, 0.22), Color(0.30, 0.30, 0.36), Color(0.62, 0.70, 0.86)]
## はじめの名前（人の番号の順）。装備の画面で替えられる。1 番は遊ぶ人、2 番がふつうの起動でのソリの仲間（2026-11-05 代表「CPUの名前は「ゆき」にしてほしい」）
const NAMES := ["そら", "ゆき", "こはる", "わた", "つむぎ", "もみじ", "あられ", "ひなた", "みぞれ", "こまち", "すず", "はる"]
const NAME_MAX := 10           # 名前の字の数の上限
const SACK_FAR := 30.0         # 誰も乗っていない米袋から持ち主がこれより離れて…
const SACK_FAR_T := 4.0        # …この秒たつと、ひとりでに帯に戻る


## 人を登録する（財布と持ち物を作る）
func join(who: int) -> void:
	if wallets.has(who):
		return
	wallets[who] = START_BUTTONS
	bags[who] = empty_bag()
	hands[who] = -1
	tag_designs[who] = preload("res://sled_tags.gd").default_design(who)
	tag_owned[who] = {}
	stitch_owned[who] = []
	sacks[who] = [{"fabric": ""}]   # 標準の米袋
	loose_tags[who] = []
	names[who] = NAMES[posmod(who - 1, NAMES.size())]
	colors[who] = posmod(who - 1, COLORS.size())
	sack_sel[who] = 0
	lanterns[who] = [{"look": "box"}, {"look": "paper"}]
	lantern_sel[who] = 0
	lamps[who] = false
	pals_owned[who] = Pals.START.duplicate()
	pals_wear[who] = Pals.START_WEAR.duplicate()


## 滑りあとの柄を使えるか（標準の柄か、買った柄）
func stitch_can_use(who: int, name: String) -> bool:
	return Stitches.has(name) and (Stitches.price(name) == 0 or name in stitch_owned.get(who, []))


## 名札の部品 part の i 番を使えるか（最初から使える部品か、手に入れた部品）
func tag_can_use(who: int, part: String, i: int) -> bool:
	if preload("res://sled_tags.gd").is_starter(part, i):
		return true
	return i in tag_owned.get(who, {}).get(part, [])


## 種類 gear の、持っている物の配列と、装備している番号
func gear_list(who: int, gear: String) -> Array:
	match gear:
		"sack": return sacks.get(who, [])
		"lantern": return lanterns.get(who, [])
	return []


func gear_index(who: int, gear: String) -> int:
	match gear:
		"sack": return int(sack_sel.get(who, 0))
		"lantern": return int(lantern_sel.get(who, -1))
	return -1


## その人がその小物・ミニオンを持っているか
func pal_owned(who: int, key: String) -> bool:
	return key in pals_owned.get(who, [])


## その人が slot（head・shoulder・pet）に付けている物の名前（"" は付けていない）
func pal_worn(who: int, slot: String) -> String:
	return String(pals_wear.get(who, {}).get(slot, ""))


## その人のキャラの色と名前（知らない人は灰色・名前なし）
func color_of(who: int) -> Color:
	return COLORS[posmod(int(colors[who]), COLORS.size())] if colors.has(who) else Color(0.55, 0.55, 0.58)


func doll_of(who: int) -> String:
	return String(dolls.get(who, ""))


## その人の人形 kind の服の色（布ごとの Color か null。染めていなければ空）。doll.gd の outfit に入れる形
func outfit_of(who: int, kind: String) -> Array:
	var out := []
	for h in outfits.get(who, {}).get(kind, []):
		out.append(Color(h) if String(h) != "" else null)
	return out


## 部位ごとの色の並びを、通信に乗せる形（"rrggbb" か ""。部位の数にそろえる）にする。色でない物は ""
static func dye_colors(kind: String, cols: Array) -> Array:
	var out := []
	var Outfit := preload("res://outfit.gd")
	cols = Outfit.upgrade(kind, cols)   # 前の保存（布ごとの 1〜2 色）は、部位の並びに直す
	for i in Outfit.cloth_count(kind):
		var c = cols[i] if i < cols.size() else null
		if c is String and String(c).is_valid_html_color():
			c = Color(c)
		out.append((c as Color).to_html(false) if c is Color else "")
	return out


## 染め代: cols（部位ごとの色）のうち、いまの色 old から別の色に染める部位の数で決まる。
## もとの色に戻す（脱色。""）部位は数えない（2026-11-03 代表「脱色はただに」）
## ソリの染め代: 布の多さで、服の部位の数に見立てる（DYE_PRICES の 1・1・2・4 部位ぶん）。元の色に戻すのはただ
const SLED_DYE_PARTS := {"sack": 1, "small": 1, "mid": 2, "large": 4}
const SLED_DYE_STILL := 0.5      # これより速く動いているソリは染めない (m/s)


static func sled_dye_price(kind: String) -> int:
	return DYE_PRICES[mini(int(SLED_DYE_PARTS.get(kind, 1)), DYE_PRICES.size() - 1)]


## ソリがいま染められない（人が乗っている・つかまれている・紐を持たれている・動いている）。立てかけ台のソリは止まっているのでよい。
## ペグで留めてあるだけなら染められる。安全なほうに倒して、使っているあいだは替えない
func sled_busy(s: Node3D) -> bool:
	if s == null or not is_instance_valid(s):
		return false
	if racked.has(s.get_meta("craft_id", -1)) or s.racked:
		return false
	return not s.riders.is_empty() or not s.holders.is_empty() or s.rope_holder != null or s.linear_velocity.length() > SLED_DYE_STILL


## 出してある装備の米袋のうち、米袋の i 番のもの（なければ null）
func _sack_out_at(who: int, i: int) -> Node3D:
	return sack_sled(who) if i == gear_index(who, "sack") else null


static func dye_price(cols: Array, old: Array) -> int:
	var n := 0
	for i in cols.size():
		if String(cols[i]) != "" and (i >= old.size() or cols[i] != old[i]):
			n += 1
	return DYE_PRICES[mini(n, DYE_PRICES.size() - 1)]


func name_of(who: int) -> String:
	return String(names.get(who, ""))


## 置いてあるソリの番号（_place の番号。なければ -1）
func sled_id(s: Node) -> int:
	for id in sleds:
		if sleds[id] == s:
			return id
	return -1


## いま呼び出す米袋 {fabric}
func sack(who: int) -> Dictionary:
	var list: Array = sacks.get(who, [])
	return list[clampi(sack_sel.get(who, 0), 0, list.size() - 1)] if not list.is_empty() else {}


## 帯に提げているランタン {look}（外していれば {}）
func lantern(who: int) -> Dictionary:
	var list: Array = lanterns.get(who, [])
	var i := int(lantern_sel.get(who, -1))
	return list[i] if i >= 0 and i < list.size() else {}


## 持っているランタンの中の、形 look の番号（持っていなければ -1）
func lantern_index(who: int, look: String) -> int:
	var list: Array = lanterns.get(who, [])
	for i in list.size():
		if String(list[i].get("look", "")) == look:
			return i
	return -1


## ランタンが点いているか
func lamp_on(who: int) -> bool:
	return bool(lamps.get(who, false)) and not lantern(who).is_empty()


## 出している米袋（なければ null）
func sack_sled(who: int) -> RigidBody3D:
	var s = sack_out.get(who)
	return s if s != null and is_instance_valid(s) and not s.is_queued_for_deletion() else null


func bag(who: int) -> Array:
	return bags.get(who, [])


static func empty_bag() -> Array:
	var b := []
	for i in SLOTS:
		b.append({})
	return b


## 持ち物の数（空いた場所は数えない）
func count(who: int) -> int:
	return bag(who).filter(func(it): return not it.is_empty()).size()


## 手持ち（画面の下の列）に何か入っているか
func has_hand_items(who: int) -> bool:
	var b := bag(who)
	for i in mini(HAND_SLOTS, b.size()):
		if not b[i].is_empty():
			return true
	return false


## 新しい物の入る場所: 手持ちの空き → かばんの空き。いっぱいなら -1
func free_slot(who: int) -> int:
	var b := bag(who)
	for i in b.size():
		if b[i].is_empty():
			return i
	return b.size() if b.size() < SLOTS else -1   # 短い配列（確かめ用の道具が入れた持ち物）は、後ろが空き


## 物を空いた場所に入れる。手持ちに入れば手に持つ（かばんなら手はそのまま）。入った場所（いっぱいなら -1）
func _put(who: int, item: Dictionary) -> int:
	var i := free_slot(who)
	if i < 0:
		return -1
	while bags[who].size() < SLOTS:
		bags[who].append({})
	bags[who][i] = item
	if i < HAND_SLOTS:
		hands[who] = i
	return i


## slot の場所を空ける。手に持っていたなら素手に
func _clear(who: int, slot: int) -> void:
	bags[who][slot] = {}
	if hands.get(who, -1) == slot:
		hands[who] = -1


func wallet(who: int) -> int:
	return wallets.get(who, 0)


## 手に持っている物（素手なら {}）
func held(who: int) -> Dictionary:
	var i: int = hands.get(who, -1)
	var b := bag(who)
	return b[i] if i >= 0 and i < b.size() else {}


## 畳んで持てるのは一人用のソリだけ（2026-10-29 代表）。いまは米袋
static func foldable(kind: String) -> bool:
	return Sled.KINDS.get(kind, {}).get("seats", [0, 0]).size() <= 1


## n を段ごとに分けた数 {"raden": 螺鈿の数, "pearl": …, "brass": …, "wood": …}（いちばん少ない枚数になるように）
static func split(n: int) -> Dictionary:
	var out := {}
	for m in MONEY:
		out[m[1]] = n / int(m[0])
		n = n % int(m[0])
	return out


## n を、ボタン 1 枚ずつの段の名前の並びにする（大きい段から）。13 → ["brass", "wood", "wood", "wood"]
static func pieces(n: int) -> Array:
	var out := []
	var sp := split(n)
	for m in MONEY:
		for i in int(sp[m[1]]):
			out.append(m[1])
	return out


static func price(item: Dictionary) -> int:
	if item.get("kind") == "pattern":
		return PATTERN_PRICE.get(item.get("sled", ""), 99)
	if item.get("kind") == "fabric":
		return FABRIC_PRICE
	if MountainGoods.has(item.get("kind", "")):
		return MountainGoods.price(item.kind)
	return 99


## 出来事を出す。持ち主が呼ぶ（一人ならすぐ配る。通信ではホストへ送り、ホストが確かめてから全員に配る）。断られたら false。
## つなぐ側では断られたかがすぐには分からないので true を返し、結果は配られた出来事で知る（断られたら何も起きない）。
## ミシンが縫い上げる・ボタンが入るは、ホストの画面が決める（つなぐ側の画面では送らない。見た目は続けてよいので true を返し、
## 本物はホストから届く）。調理の装置が仕上げる・米袋がひとりでに帯に戻るは auto（つなぐ側では送らず false。ホストの画面が出す）
const HOST_ONLY := ["sewn", "earn", "stake"]

func send(ev: Dictionary) -> bool:
	ev["frame"] = Doll.frame_index() + 1
	var net := _net()
	if net and net.online and not net.is_host():
		if ev.kind in HOST_ONLY:
			return true
		if ev.get("auto", false):
			return false
		net.up("craft", ev)
		return true
	return _apply(ev)


## 厨房の装置（cook_station.gd。なければ null）
func _station(kind: String) -> Node:
	for st in world.get("stations") if world and world.get("stations") != null else []:
		if st.kind == kind:
			return st
	return null


func _net() -> Node:
	return world.get_node_or_null("Net") if world else null


## いまの工房の持ち物と置いてあるソリ（あとから来た人へ、ホストが渡す）
func snapshot() -> Dictionary:
	var placed := []
	for id in sleds:
		var s: Node3D = sleds[id]
		if is_instance_valid(s):
			var one := {"id": id, "kind": s.kind, "fabric": s.fabric, "at": s.global_transform, "tag": s.tag, "owner": s.owner_id, "stitch": s.stitch_override, "base": s.base_fabric}
			if racked.has(id):
				one["rack"] = racked[id]
			placed.append(one)
	var out := {}
	for who in sack_out:
		var gs := sack_sled(who)
		if gs:
			out[who] = {"fabric": gs.fabric, "at": gs.global_transform, "stitch": gs.stitch_override, "base": gs.base_fabric}
	var lit := []
	for f in fires.values():
		if is_instance_valid(f):
			lit.append(f.snap())
	var pegs := []   # ペグで留めてあるソリ
	for s in get_tree().get_nodes_in_group("sleds") if is_inside_tree() else []:
		if is_instance_valid(s.peg):
			pegs.append({"sled": sled_path(s), "at": s.peg.global_position, "color": s.peg.color})
	return {"pegs": pegs, "wallets": wallets, "bags": bags, "hands": hands, "tag_designs": tag_designs, "tag_owned": tag_owned, "stitch_owned": stitch_owned, "sacks": sacks,
		"loose_tags": loose_tags, "names": names, "colors": colors, "dolls": dolls, "sack_sel": sack_sel, "lanterns": lanterns,
		"lantern_sel": lantern_sel, "lamps": lamps, "next_sled": _next_sled, "sleds": placed, "sack_out": out,
		"fires": lit, "next_fire": _next_fire, "scope_who": int(world.binocular_stand.who) if world and world.get("binocular_stand") else -1}


## ホストから渡された持ち物と置いてあるソリで、この画面の工房を置き換える（つないだとき）。自分の人の番号の分もホストの値になる
func load_snapshot(d: Dictionary) -> void:
	if world and world.get("binocular_stand"):
		world.binocular_stand.who = int(d.get("scope_who", -1))
	for key in ["wallets", "bags", "hands", "tag_designs", "tag_owned", "stitch_owned", "sacks", "loose_tags", "names", "colors", "dolls",
			"sack_sel", "lanterns", "lantern_sel", "lamps"]:
		var mine: Dictionary = get(key)
		mine.merge(d.get(key, {}), true)
	for s in sleds.values():
		if is_instance_valid(s):
			s.queue_free()
	sleds.clear()
	racked.clear()
	for p in d.get("sleds", []):
		_next_sled = int(p.id)
		_place(p.kind, p.fabric, Vector3.ZERO, 0.0, 0, Vector3.UP, p.tag, false, int(p.owner), String(p.get("stitch", "")), String(p.get("base", "")))
		var s: Node3D = sleds[int(p.id)]
		s.global_transform = p.at
		if p.has("rack"):
			racked[int(p.id)] = float(p.rack)
			s.rack_in.call_deferred(p.at)   # _ready のあとで（影と紐ができてから）
	_next_sled = int(d.get("next_sled", _next_sled))
	for who in d.get("sack_out", {}):
		var spec: Dictionary = d.sack_out[who]
		var gid := _place("sack", spec.fabric, Vector3.ZERO, 0.0, 0, Vector3.UP, -1, false, int(who), String(spec.get("stitch", "")), String(spec.get("base", "")))
		var gs: RigidBody3D = sleds[gid]
		sleds.erase(gid)
		_next_sled -= 1   # 装備の米袋はソリの番号を使わない（ホストでは出したときに使ったが、その番号は上の next_sled に入っている）
		gs.crafted = false
		gs.name = "Sack%d" % int(who)
		gs.set_meta("gear_of", int(who))
		gs.global_transform = spec.at
		sack_out[int(who)] = gs
	for f in fires.values():
		if is_instance_valid(f):
			f.queue_free()
	fires.clear()
	for spec in d.get("fires", []):   # 燃えている焚き火（燃えた秒のぶん進めて置く）
		_light_fire(int(spec.id), int(spec.owner), spec.at, float(spec.yaw), spec.up, float(spec.age), float(spec.get("out", -1.0)))
	_next_fire = int(d.get("next_fire", _next_fire))
	for p in d.get("pegs", []):
		var s := _sled_at(String(p.sled))
		if s:
			s.peg_to(p.at, p.color, false)


## ホストの判定
func _apply(ev: Dictionary) -> bool:
	var who: int = ev.get("who", -1)
	if not wallets.has(who) and ev.kind != "sewn":
		return false
	match ev.kind:
		"buy":
			var item: Dictionary = ev.item
			var cost := price(item)
			if MountainGoods.has(item.get("kind", "")) and not MountainGoods.sold(item.kind):
				return false   # 山男の棚で、まだ売っていない品目
			var stack := _peg_stack(who) if Peg.is_item(item) else -1
			if wallets[who] < cost or free_slot(who) < 0 and stack < 0:
				return false
			wallets[who] -= cost
			if stack >= 0:   # ペグは持っている束に足す（その束を手に持つ）
				bags[who][stack]["n"] = int(bags[who][stack].get("n", 0)) + Peg.PACK
				ev["slot"] = stack
				if stack < HAND_SLOTS:
					hands[who] = stack
			else:
				ev["slot"] = _put(who, item.duplicate())   # 買った物を手に持つ（手持ちがいっぱいなら、かばんへ）
		"hand":
			var i := int(ev.slot)
			if i >= HAND_SLOTS or (i >= 0 and (i >= bags[who].size() or bags[who][i].is_empty())):
				return false   # 手に持てるのは手持ちの物だけ
			hands[who] = maxi(i, -1)
		"move":
			# 持ち物を別の場所へ（装備の画面で引きずって。行き先に物があれば入れ替える）。手に持っていた物は、手持ちにある限り持ったまま
			var b: Array = bags[who]
			var a := int(ev.from)
			var c := int(ev.to)
			if a == c or a < 0 or c < 0 or a >= b.size() or c >= b.size() or b[a].is_empty():
				return false
			var t: Dictionary = b[a]
			b[a] = b[c]
			b[c] = t
			var h: int = hands[who]
			if h == a:
				hands[who] = c if c < HAND_SLOTS else -1
			elif h == c:
				hands[who] = a if a < HAND_SLOTS and not b[a].is_empty() else -1
		"drop":
			# 持ち物を捨てる（装備の画面のゴミ箱）
			var b: Array = bags[who]
			var i := int(ev.slot)
			if i < 0 or i >= b.size() or b[i].is_empty():
				return false
			ev["item"] = b[i].duplicate()
			_clear(who, i)
		"scope_on":
			var st = world.get("binocular_stand") if world else null
			if st == null:
				return false
			if not replay:   # つなぐ側がなぞるときは、ホストがもう確かめて払っている
				if int(st.who) >= 0 or world.get("emotes") == null:
					return false
				var pay := {"kind": "spend", "who": who, "n": 1}
				world.emotes.send(pay)
				if pay.get("ok", false):
					ev["paid"] = "ball"
				elif wallets[who] >= 1:
					ev["paid"] = "button"
				else:
					return false
			if String(ev.get("paid", "")) == "button":
				wallets[who] -= 1
			st.who = who
			var person := _person(who)
			if person:
				st.drop_fee(String(ev.get("paid", "button")), person.global_position + Vector3.UP * 1.1)
		"scope_off":
			var st = world.get("binocular_stand") if world else null
			if st == null or (int(st.who) != who and not replay):
				return false
			st.who = -1
		"food_buy":
			var dish: String = ev.item.get("dish", "")
			if not Food.MENU.has(dish) or free_slot(who) < 0 or world == null or world.get("emotes") == null:
				return false
			if not replay:   # つなぐ側がなぞるときは、ホストがもう雪玉で払っている（数はホストから届く）
				var pay := {"kind": "spend", "who": who, "n": Food.price(dish)}
				world.emotes.send(pay)
				if not pay.get("ok", false):
					return false
			ev["slot"] = _put(who, Food.item(dish))   # 買ったペレットを手に持つ
		"cook":
			var b: Array = bags[who]
			var i := int(ev.slot)
			if i < 0 or i >= b.size() or b[i].is_empty() or Food.next_station(b[i]) != ev.station:
				return false
			var st := _station(String(ev.station))
			if st and st.riding() and not replay:
				return false   # 乾燥機の中に人がいる
			ev["item"] = b[i].duplicate()
			_clear(who, i)
			if st and int(ev.get("frame", -1)) >= 0:
				st.note_cook(int(ev.frame))   # 仕上がるまで、ほかの人は乾燥機に入れない（どの画面でも）
		"dry_in":
			var st := _station("dryer")
			if st == null or (not replay and (st.riding() or st.busy() or Doll.frame_index() < st._cook_until)):
				return false
			st.begin_ride(who, int(ev.get("frame", Doll.frame_index())))
		"dry_out":
			var st := _station("dryer")
			if st == null or st.rider != who:
				return false
			st.end_ride(who, int(ev.get("frame", Doll.frame_index())))
		"bite":
			var b: Array = bags[who]
			var i := int(ev.slot)
			if i < 0 or i >= b.size() or b[i].is_empty() or not Food.done(b[i]):
				return false
			b[i]["bites"] = int(b[i].get("bites", 0)) + 1
			ev["dish"] = b[i].dish
			if int(b[i].bites) >= Food.BITES:
				ev["ate"] = b[i].dish
				_clear(who, i)
		"cooked":
			if not replay:   # 仕上がりはホストの画面の装置のもの（つなぐ側から来ても、中身は装置から取る）
				var st := _station(String(ev.get("station", "")))
				if st == null or st.result.is_empty() or st.who != who:
					return false
				ev["item"] = st.result.duplicate()
			if free_slot(who) < 0:
				return false
			ev["slot"] = _put(who, ev.item)
		"sew":
			# 型紙と布は両方そろって初めて使う（片方だけ消えることはない）
			var b: Array = bags[who]
			var ps := int(ev.pattern_slot)
			var fs := int(ev.fabric_slot)
			if ps == fs or ps < 0 or fs < 0 or ps >= b.size() or fs >= b.size() or b[ps] != ev.pattern or b[fs] != ev.fabric \
					or ev.pattern.get("kind") != "pattern" or ev.fabric.get("kind") != "fabric":
				return false
			if world and world.get("sewing") and not world.sewing.can_sew() and not replay:
				return false
			_clear(who, ps)
			_clear(who, fs)
		"sewn":
			ev["tag"] = tag_designs.get(who, 0)   # 持ち主の印: 縫った人の名札
			if ev.sled == "sack" and sacks.has(who):
				# 米袋は装備: 床には出さず、装備の枠に入れて、呼び出す米袋にする（名札は付けない）
				ev["tag"] = -1
				sacks[who].append({"fabric": ev.fabric})
				sack_sel[who] = sacks[who].size() - 1
				ev["gear"] = true
			elif ev.sled in OUT_FRONT and world and world.has_method("delivery_spot"):
				# 運び出せない大きさ: ロッジの前に、空から包みが落ちて開いて出てくる
				var spot: Transform3D = world.delivery_spot(ev.sled)
				ev["at"] = spot.origin
				ev["yaw"] = spot.basis.get_euler().y
				ev["outside"] = true
				ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, UNFOLD_FRAMES, Vector3.UP, ev.tag, true, who)
				ev["item"] = {"kind": "folded", "sled": ev.sled, "fabric": ev.fabric, "tag": ev.tag}
				_origami(ev, true, Transform3D(Basis(Vector3.UP, ev.yaw), ev.at), false)
			else:
				ev["id"] = _place(ev.sled, ev.fabric, ev.at, ev.yaw, 0, Vector3.UP, ev.tag, true, who)
		"sack_out":
			var spec := sack(who)
			if spec.is_empty() or sack_sled(who) != null:
				return false
			var gid := _place("sack", spec.fabric, ev.at, ev.yaw, 0, ev.get("up", Vector3.UP), -1, false, who, String(spec.get("stitch", "")), String(spec.get("base", "")))
			var gs: RigidBody3D = sleds[gid]
			sleds.erase(gid)   # 装備の米袋は畳むソリの数に入れない
			gs.crafted = false
			gs.name = "Sack%d" % who
			gs.set_meta("gear_of", who)
			sack_out[who] = gs
			_sack_far[who] = 0.0
			gs.linear_velocity = ev.get("v", Vector3.ZERO)
			ev["id"] = gid
			_pop(gs)
		"sack_in":
			var gs := sack_sled(who)
			if gs == null:
				return false
			for r in gs.riders.duplicate():
				if r.has_method("get_off"):
					r.get_off()
			for h in gs.holders.keys():
				if h.has_method("let_go"):
					h.let_go()
			if gs.rope_holder and gs.rope_holder.has_method("let_go"):
				gs.rope_holder.let_go()
			ev["item"] = {"kind": "folded", "sled": "sack", "fabric": gs.fabric, "tag": -1}
			_origami(ev, false, gs.global_transform, true, 3.0)   # くるっと丸めて、持ち主の帯へ飛ぶ（速回し。10 コマで、人形のしまう動き doll.gd の SACK_IN と同じ）
			sack_out.erase(who)
			if world:   # この米袋を相手にしていた人（と人形）は、もとのソリへ
				for c in world.get_children():
					if c is CharacterBody3D and c.get("sled") == gs:
						c.set("sled", world.get("sled"))
						if c.get("last_sled") == gs:
							c.set("last_sled", world.get("sled"))
						var d = c.get("doll")
						if d and d.get("sled") == gs:
							d.set("sled", world.get("sled"))
			gs.leave_trail()
			gs.queue_free()
		"stitch_buy":   # 滑りあとの柄を買う（持ち物の場所は使わない。人ごとに、一度買えばどのソリにも使える）
			var nm := String(ev.get("stitch", ""))
			if not Stitches.has(nm) or Stitches.price(nm) <= 0 or nm in stitch_owned.get(who, []) or wallets[who] < Stitches.price(nm):
				return false
			wallets[who] -= Stitches.price(nm)
			stitch_owned[who].append(nm)
		"stitch_own":   # 前に買った柄を戻す（起動したとき。値はここでは取らない。player.gd の _load_tag）
			var nm := String(ev.get("stitch", ""))
			if not Stitches.has(nm) or Stitches.price(nm) <= 0:
				return false
			if not nm in stitch_owned[who]:
				stitch_owned[who].append(nm)
		"sled_dye", "sled_dye_own":     # sled_dye_own は、前に染めた標準の米袋の色を戻す（起動したとき。値はここでは取らない。player.gd の _load_tag）。見本帳でソリを染める（color は "#RRGGBB"。"" は元の色に戻す）。持ち主だけ。相手は id（置いてある・立てかけ台のソリ）・slot（畳んだ包み）・sack（米袋）
			var hex := String(ev.get("color", ""))
			if hex != "" and not Fabrics.is_dyed(hex):
				return false
			var kind := ""
			var now := ""
			var s: Node3D = null
			var spec: Dictionary = {}
			var i := -1
			if ev.has("id"):
				s = sleds.get(int(ev.id))
				if s == null or not is_instance_valid(s) or int(s.owner_id) != who:
					return false
				kind = s.kind
				now = s.fabric
			elif ev.has("slot"):
				var b: Array = bags[who]
				i = int(ev.slot)
				if i < 0 or i >= b.size() or b[i].get("kind", "") != "folded" or not preload("res://sled_tags.gd").has_tag(b[i].get("tag", -1)):
					return false
				kind = b[i].sled
				now = String(b[i].get("fabric", ""))
			elif ev.has("sack"):
				var list: Array = sacks.get(who, [])
				i = int(ev.sack)
				if i < 0 or i >= list.size():
					return false
				kind = "sack"
				now = String(list[i].get("fabric", ""))
				s = _sack_out_at(who, i)
			else:
				return false
			if not replay and sled_busy(s):   # 乗っている・つかまれている・動いているソリは替えない
				return false
			if hex == now or (hex == "" and not Fabrics.is_dyed(now)):
				return false   # 変わらない
			if ev.kind == "sled_dye_own" and not ev.has("sack"):
				return false
			var cost := 0 if hex == "" or ev.kind == "sled_dye_own" else sled_dye_price(kind)
			if wallets[who] < cost:
				return false
			wallets[who] -= cost
			ev["price"] = cost
			if s:
				s.dye_to(hex)
			if ev.has("slot"):
				var b: Array = bags[who]
				var it: Dictionary = b[i].duplicate()
				if hex == "":
					it["fabric"] = String(it.get("base", ""))
					it.erase("base")
				else:
					if not Fabrics.is_dyed(now):
						it["base"] = now
					it["fabric"] = hex
				b[i] = it
			elif ev.has("sack"):
				var list: Array = sacks[who]
				var one: Dictionary = list[i].duplicate()
				if hex == "":
					one["fabric"] = String(one.get("base", ""))
					one.erase("base")
				else:
					if not Fabrics.is_dyed(now):
						one["base"] = now
					one["fabric"] = hex
				list[i] = one
		"sled_stitch":  # ソリの滑りあとの柄を替える。名札と同じで、持ち主だけ（ロッジのソリ・名札を外したソリは替えられない）
			var nm := String(ev.get("stitch", ""))
			if not stitch_can_use(who, nm):
				return false
			if ev.has("id"):
				var s: Node3D = sleds.get(int(ev.id))
				if s == null or not is_instance_valid(s) or int(s.owner_id) != who:
					return false
				s.set_stitch(nm)
			elif ev.has("slot"):
				var b: Array = bags[who]
				var i := int(ev.slot)
				if i < 0 or i >= b.size() or b[i].get("kind", "") != "folded" or not preload("res://sled_tags.gd").has_tag(b[i].get("tag", -1)):
					return false
				var it: Dictionary = b[i].duplicate()
				it["stitch"] = nm
				b[i] = it
			elif ev.has("sack"):
				var list: Array = sacks.get(who, [])
				var i := int(ev.sack)
				if i < 0 or i >= list.size():
					return false
				var spec: Dictionary = list[i].duplicate()
				spec["stitch"] = nm
				list[i] = spec
				var gs := sack_sled(who)
				if gs and i == gear_index(who, "sack"):   # 出している米袋にも
					gs.set_stitch(nm)
			else:
				return false
		"tag_unlock":   # あとで手に入る名札の部品を手に入れる（報酬や店から。値はここでは取らない）
			var Tags := preload("res://sled_tags.gd")
			var part := String(ev.get("part", ""))
			var i := int(ev.get("index", -1))
			if not part in Tags.PARTS or i < 0 or i >= Tags.part_count(part):
				return false
			var owned: Dictionary = tag_owned.get(who, {})
			if not owned.has(part):
				owned[part] = []
			if not i in owned[part]:
				owned[part].append(i)
			tag_owned[who] = owned
		"tag_design":
			var Tags := preload("res://sled_tags.gd")
			var old: Dictionary = tag_designs.get(who, {})
			var d: Dictionary = {}
			for part in Tags.PARTS:   # 書いていない部品は前のまま。まだ手に入れていない部品も前のまま
				var i := posmod(int(ev.design.get(part, old.get(part, Tags.DEFAULT[part]))), Tags.part_count(part))
				if not tag_can_use(who, part, i):
					i = int(old.get(part, Tags.DEFAULT[part]))
				d[part] = i
			ev["design"] = d
			tag_designs[who] = d   # いつもの柄（これから縫うソリに付く）。いまあるソリの名札はソリごと（sled_tag）
		"sled_tag":
			var d := _usable_design(who, ev.design, {})
			if ev.has("id"):
				var s: Node3D = sleds.get(int(ev.id))
				if s == null or not is_instance_valid(s) or int(s.owner_id) != who or not preload("res://sled_tags.gd").has_tag(s.tag):
					return false
				d = _usable_design(who, ev.design, s.tag if s.tag is Dictionary else {})
				s.retag(d)
			elif ev.has("slot"):
				var b: Array = bags[who]
				var i := int(ev.slot)
				if i < 0 or i >= b.size() or b[i].get("kind", "") != "folded" or b[i].get("sled") == "sack" or not preload("res://sled_tags.gd").has_tag(b[i].get("tag", -1)):
					return false
				var it: Dictionary = b[i].duplicate()
				d = _usable_design(who, ev.design, it.tag if it.tag is Dictionary else {})
				it["tag"] = d
				b[i] = it
			elif ev.has("loose"):
				var lt: Array = loose_tags.get(who, [])
				var i := int(ev.loose)
				if i < 0 or i >= lt.size():
					return false
				d = _usable_design(who, ev.design, lt[i] if lt[i] is Dictionary else {})
				lt[i] = d
			else:
				return false
			ev["design"] = d
		"untag":
			var s: Node3D = sleds.get(int(ev.get("id", -1)))
			if s == null or not is_instance_valid(s) or int(s.owner_id) != who or s.kind == "sack" or not preload("res://sled_tags.gd").has_tag(s.tag) or s.racked:
				return false   # 台のソリは名札を外せない（持ち主がいなくなると、だれも持ち出せない）
			ev["design"] = s.tag
			ev["at"] = s.tag_point()
			loose_tags[who].append(s.tag)
			s.owner_id = -1
			s.retag(-1)
			_fly_tag(ev.design, ev.at, who, null)   # 結び目がほどけ、名札が帯へ飛んで戻る
		"tag_on":
			var s: Node3D = sleds.get(int(ev.get("id", -1)))
			var lt: Array = loose_tags.get(who, [])
			var i := int(ev.get("loose", 0))
			if s == null or not is_instance_valid(s) or int(s.owner_id) >= 0 or s.kind == "sack" or preload("res://sled_tags.gd").has_tag(s.tag) \
					or i < 0 or i >= lt.size():
				return false
			ev["design"] = lt[i]
			lt.remove_at(i)
			s.owner_id = who
			s.tag = ev.design
			_fly_tag(ev.design, s.tag_point(), who, s)   # 帯から名札が飛んで、結び目に結ばれる（着いたら吊るす）
		"profile":
			var nm := String(ev.get("name", names.get(who, ""))).strip_edges().left(NAME_MAX)
			if nm == "":
				nm = NAMES[posmod(who - 1, NAMES.size())]
			ev["name"] = nm
			ev["color"] = posmod(int(ev.get("color", colors.get(who, 0))), COLORS.size())
			names[who] = nm
			colors[who] = int(ev.color)
		"equip":
			var list := gear_list(who, String(ev.get("gear", "")))
			var i := int(ev.index)
			if i >= list.size() or i < (-1 if ev.gear == "lantern" else 0):
				return false
			match ev.gear:
				"sack": sack_sel[who] = i
				"lantern":
					lantern_sel[who] = i
					if i < 0:
						lamps[who] = false
		"pal_buy":
			var key := String(ev.get("key", ""))
			var cost := Pals.price(key)
			if cost < 0 or pal_owned(who, key) or wallets[who] < cost:
				return false
			wallets[who] -= cost
			pals_owned[who].append(key)
			ev["slot"] = Pals.slot_of(key)
			pals_wear[who][ev.slot] = key   # 買ったらすぐ身につける
		"pal_own":
			var key := String(ev.get("key", ""))
			if Pals.price(key) < 0:
				return false
			if not pal_owned(who, key):
				pals_owned[who].append(key)
		"pal_wear":
			var slot := String(ev.get("slot", ""))
			var key := String(ev.get("key", ""))
			if not slot in Pals.SLOTS or key != "" and (not pal_owned(who, key) or Pals.slot_of(key) != slot):
				return false
			pals_wear[who][slot] = key
		"doll":
			if not String(ev.get("doll", "")) in Doll.KINDS:
				return false
			dolls[who] = String(ev.doll)
		"dye", "outfit":
			var k := String(ev.get("doll", ""))
			if not k in Doll.KINDS:
				return false
			var cols := dye_colors(k, ev.get("colors", []))
			var mine: Dictionary = outfits.get(who, {})
			var old: Array = mine.get(k, dye_colors(k, []))
			if ev.kind == "dye":
				var cost := dye_price(cols, old)
				if cols == old or wallets[who] < cost:   # 同じ色のままなら染めない（脱色だけなら染め代は 0）
					return false
				wallets[who] -= cost
				ev["price"] = cost
			ev["colors"] = cols
			if cols == dye_colors(k, []):
				mine.erase(k)
			else:
				mine[k] = cols
			outfits[who] = mine
		"lamp":
			if lantern(who).is_empty():
				return false
			lamps[who] = bool(ev.on)
		"lantern_buy":
			var look := String(ev.get("look", ""))
			var cost := Lantern.price(look)
			if cost < 0 or lantern_index(who, look) >= 0 or wallets[who] < cost:
				return false
			wallets[who] -= cost
			var was_lit := lamp_on(who)
			lanterns[who].append({"look": look})
			lantern_sel[who] = lanterns[who].size() - 1   # 買ったらすぐ帯に提げる（点いていれば点いたまま）
			lamps[who] = was_lit
			ev["index"] = lantern_sel[who]
		"lantern_own":
			var look := String(ev.get("look", ""))
			if Lantern.price(look) < 0:
				return false
			if lantern_index(who, look) < 0:
				lanterns[who].append({"look": look})
		"fire_lay":
			var b: Array = bags[who]
			var i := int(ev.get("slot", -1))
			if i < 0 or i >= b.size() or b[i].get("kind", "") != "campfire":
				return false
			_clear(who, i)
			for f in fires.values():   # 一人ひとつ: 前の焚き火は消える
				if is_instance_valid(f) and f.owner_id == who and f.lit():
					f.put_out()
			var fid := int(ev.id) if ev.has("id") else _next_fire   # つなぐ側は、ホストの付けた番号
			_next_fire = maxi(_next_fire, fid + 1)
			ev["id"] = fid
			_light_fire(fid, who, ev.at, float(ev.get("yaw", 0.0)), ev.get("up", Vector3.UP), 0.0)
		"fire_out":
			var f = fires.get(int(ev.get("id", -1)))
			if f == null or not is_instance_valid(f) or f.owner_id != who or not f.lit():
				return false
			f.put_out()
		"peg":
			var b: Array = bags[who]
			var i := int(ev.get("slot", -1))
			var s := _sled_at(String(ev.get("sled", "")))
			if i < 0 or i >= b.size() or not Peg.is_item(b[i]) or int(b[i].get("n", 0)) <= 0 or s == null or s.racked:
				return false
			if not replay and (s.peg != null or s.linear_velocity.length() > Peg.PLANT_SPEED or ev.at.distance_to(s.rope_root()) > s.ROPE_LEN):
				return false   # もう留めてある・滑っている・紐が届かない
			ev["color"] = color_of(who)
			if s.peg_to(ev.at, ev.color, not replay) == null:
				return false
			b[i]["n"] = int(b[i].n) - 1
			if int(b[i].n) <= 0:
				_clear(who, i)
		"unpeg":
			var s := _sled_at(String(ev.get("sled", "")))
			if s == null or s.peg == null:
				return false
			ev["at"] = s.peg.global_position
			s.unpeg()
		"earn":
			if int(ev.get("n", 0)) <= 0:
				return false
			wallets[who] += int(ev.n)
		"stake":
			if int(ev.get("n", 0)) <= 0 or wallets[who] < int(ev.n):
				return false
			wallets[who] -= int(ev.n)
		"rack_in":
			var id := int(ev.get("id", -1))
			var s: Node3D = sleds.get(id)
			var rack: Node3D = world.get("sled_rack") if world else null
			if s == null or not is_instance_valid(s) or rack == null or int(s.owner_id) != who or s.kind == "sack":
				return false
			if not replay:   # ホストが確かめる: ペグで留めていない・台の前にいる・台に空きがある
				if is_instance_valid(s.peg) or racked.has(id) or not rack.in_reach(_person(who)):
					return false
				var u: float = rack.fit(s.kind, _rack_taken())
				if is_nan(u):
					return false
				ev["u"] = u
			ev["item"] = {"kind": "folded", "sled": s.kind, "fabric": s.fabric}
			_origami(ev, false, s.global_transform, true, RACK_FOLD_SPEED)   # その場で畳まれて、台の前の持ち主のほうへ飛ぶ
			racked[id] = float(ev.u)
			s.rack_in(rack.lean_at(s.kind, float(ev.u)), UNFOLD_FRAMES / RACK_FOLD_SPEED / 12.0)
		"rack_out":
			var id := int(ev.get("id", -1))
			var s: Node3D = sleds.get(id)
			var rack: Node3D = world.get("sled_rack") if world else null
			if s == null or not is_instance_valid(s) or rack == null or int(s.owner_id) != who or not racked.has(id):
				return false
			if not replay:
				if not rack.in_reach(_person(who)):
					return false
				var spot: Transform3D = rack.out_at(s.kind, float(racked[id]), world)
				if spot.origin == Vector3.INF:
					return false   # 前がふさがっている
				ev["at"] = spot.origin
				ev["yaw"] = spot.basis.get_euler().y
			racked.erase(id)
			s.rack_out(Transform3D(_basis(float(ev.yaw), Vector3.UP), ev.at + Vector3.UP * 0.08), _make_room.bind(s))
		"fold":
			var s: Node3D = sleds.get(int(ev.id))
			if s == null or not is_instance_valid(s) or not foldable(s.kind) or free_slot(who) < 0 or not (_free(s) or replay):
				return false
			ev["item"] = {"kind": "folded", "sled": s.kind, "fabric": s.fabric, "tag": s.tag, "stitch": s.stitch_override, "base": s.base_fabric}   # 名札と柄はソリごと（外したソリは -1 のまま）
			ev["at"] = s.global_position
			ev["yaw"] = s.rotation.y
			sleds.erase(int(ev.id))
			_origami(ev, false, s.global_transform)
			s.leave_trail()
			s.queue_free()
			ev["slot"] = _put(who, ev.item)
		"unfold":
			if not _take(who, int(ev.slot), ev.item):
				return false
			var up: Vector3 = ev.get("up", Vector3.UP)
			# 名札は包みに付いていた名札。名札のない（持ち主をやめた）ソリは、広げても持ち主のいないソリのまま
			var t = ev.item.get("tag", -1)
			var Tags := preload("res://sled_tags.gd")
			ev["id"] = _place(ev.item.sled, ev.item.fabric, ev.at, ev.yaw, UNFOLD_FRAMES, up, t, true, who if Tags.has_tag(t) else -1, String(ev.item.get("stitch", "")), String(ev.item.get("base", "")))
			_origami(ev, true, Transform3D(_basis(ev.yaw, up), ev.at))
	happened.emit(ev)
	var net := _net()
	if net and net.is_host():
		net.down("craft", ev)   # ホストが確かめた出来事を、つなぐ側へ（つなぐ側も同じ順に _apply する）
	return true


## 焚き火を置く（組んでから age 秒たった姿で。out が 0 以上なら、その秒に消えたもの）
func _light_fire(id: int, who: int, at: Vector3, yaw: float, up: Vector3, age: float, out := -1.0) -> void:
	var f: Node3D = preload("res://campfire.gd").new()
	f.fire_id = id
	f.owner_id = who
	f.age = age
	f.name = "Campfire%d" % id
	f.transform = Transform3D(_basis(yaw, up), at)
	(world if world else get_parent()).add_child(f)
	if out >= 0.0:
		f.set("_out_age", out)
	fires[id] = f
	f.tree_exited.connect(func(): if fires.get(id) == f: fires.erase(id))


## 名札の柄を、手に入れた部品だけの辞書にする（書いていない部品・まだ手に入れていない部品は old のまま、old にもなければ DEFAULT）
func _usable_design(who: int, want: Dictionary, old: Dictionary) -> Dictionary:
	var Tags := preload("res://sled_tags.gd")
	var d := {}
	for part in Tags.PARTS:
		var i := posmod(int(want.get(part, old.get(part, Tags.DEFAULT[part]))), Tags.part_count(part))
		if not tag_can_use(who, part, i):
			i = int(old.get(part, Tags.DEFAULT[part]))
		d[part] = i
	return d


## 持ち物の slot 番目が item なら取り出す。手は素手に戻す
func _take(who: int, slot: int, item: Dictionary) -> bool:
	var b: Array = bags[who]
	if slot < 0 or slot >= b.size() or b[slot].is_empty() or b[slot] != item:
		return false
	_clear(who, slot)
	return true


## 畳む・広げる動き（origami.gd）を、ソリの所に置く
func _origami(ev: Dictionary, unfolding: bool, at: Transform3D, from_who := true, speed := 1.0) -> void:
	var o: Node3D = load("res://origami.gd").new()
	o.kind = ev.item.sled
	o.fabric = ev.item.fabric
	o.unfolding = unfolding
	o.start = int(ev.frame)
	o.speed = speed
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	o.who = hub.who_of(int(ev.who)) if hub and from_who else null   # いなければ、包みは空から落ちてくる
	o.name = "Origami"
	o.transform = Transform3D(at.basis.orthonormalized(), at.origin)   # 置く先（main）は原点にある
	(world if world else get_parent()).add_child(o)


## 誰も乗っていない・つかんでいない・紐を持っていない・ペグで留めていないソリだけ畳める。台に立てかけてあるソリも畳めない
func _free(s: Node3D) -> bool:
	return rack_free(s) and not s.racked


## だれも触っていなくて、ペグで留めていない（畳む・仲間が使う・立てかけ台へ先に呼ぶソリ。2026-11-04 代表: ペグで留めたソリは呼べない）
func rack_free(s: Node3D) -> bool:
	return s.riders.is_empty() and s.holders.is_empty() and s.rope_holder == null and not is_instance_valid(s.peg)


## 自分のソリのうち、台に立てかけてあるもの・だれも触っていないもの・ほかの人が触っているもの（どちらも戻せる）・ペグで留めてあって戻せないもの
## {"on": [...], "free": [...], "touched": [...], "busy": [...]}。
## 名札のないソリ（持ち主なし）とロッジのソリは対象外
func rack_list(who: int) -> Dictionary:
	var out := {"on": [], "free": [], "touched": [], "busy": []}
	for id in sleds:
		var s: Node3D = sleds[id]
		if not is_instance_valid(s) or s.is_queued_for_deletion() or int(s.owner_id) != who or s.kind == "sack":
			continue
		if racked.has(id):
			out.on.append(s)
		elif not s.racked:   # 台から降りている途中は数えない
			out["free" if rack_free(s) else "busy" if is_instance_valid(s.peg) else "touched"].append(s)
	return out


## 台に置いてある物 [[中心, 幅], ...]
func _rack_taken() -> Array:
	var out := []
	for id in racked.keys():
		var s: Node3D = sleds.get(id)
		if s == null or not is_instance_valid(s):
			racked.erase(id)
			continue
		out.append([racked[id], preload("res://sled_rack.gd").WIDTHS.get(s.kind, 2.4)])
	return out


func _person(who: int) -> Node3D:
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	return hub.who_of(who) if hub else null


## 持ち物の中の、まだ 1 束（Peg.PACK 本）を足せるペグの束の場所（なければ -1）
func _peg_stack(who: int) -> int:
	var b := bag(who)
	for i in b.size():
		if Peg.is_item(b[i]) and int(b[i].get("n", 0)) + Peg.PACK <= Peg.STACK:
			return i
	return -1


## ソリの名前（main からのパス。通信でも同じソリを指す。net.gd の sled_at と同じ）
func sled_path(s: Node) -> String:
	return String(world.get_path_to(s)) if world and s else ""


func _sled_at(path: String) -> RigidBody3D:
	if world == null or path == "":
		return null
	var s := world.get_node_or_null(NodePath(path)) as RigidBody3D
	return s if s and "peg" in s else null


## 実寸のソリを置く。wait コマのあいだは止めておく（広げる動きのあいだ）
func _place(kind: String, fabric: String, at: Vector3, yaw: float, wait: int, up := Vector3.UP, tag: Variant = 0, room := true, owner_id := -1, stitch := "", base := "") -> int:
	var id := _next_sled
	_next_sled += 1
	var s := Sled.new()
	s.kind = kind
	s.fabric = fabric
	s.crafted = true
	s.tag = tag
	s.owner_id = owner_id
	s.stitch_override = stitch
	s.base_fabric = base
	s.name = "MadeSled%d" % id
	s.transform = Transform3D(_basis(yaw, up), at + up * 0.08)   # 床に少し浮かせて置く（めり込むと床の下へ押し出される）
	if world and world.has_method("snow_lift"):
		s.snow_lift = Callable(world, "snow_lift")
		s.snow_plane = Callable(world, "snow_plane")
	(world if world else get_parent()).add_child(s)
	s.set_meta("craft_id", id)
	if wait > 0:
		s.hold_still(wait)
	sleds[id] = s
	if room:
		_make_room(s)
	return id


## 名札が、ソリの結び目と人の帯のあいだを飛ぶ（見た目だけ。12 コマで 6 コマ、少し弧を描く）。
## onto があれば帯から結び目へ飛び、着いたらそのソリに名札を吊るす。なければ結び目から帯へ飛んで消える
func _fly_tag(design, knot: Vector3, who: int, onto: Node3D) -> void:
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	var person: Node3D = hub.who_of(who) if hub else null
	var belt: Vector3 = person.global_position + Vector3.UP * 0.95 if person else knot + Vector3.UP
	var tex: Texture2D = preload("res://sled_tags.gd").texture(design)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.pixel_size = 0.2 / maxf(tex.get_width(), 1.0) if tex else 0.001
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.name = "FlyingTag"
	(world if world else get_parent()).add_child(sp)
	var a := belt if onto else knot
	var b := knot if onto else belt
	const N := 6
	for i in N + 1:
		var t := float(i) / N
		sp.global_position = a.lerp(b, t) + Vector3.UP * sin(t * PI) * 0.35
		sp.scale = Vector3.ONE * lerpf(1.0, 0.6, t if not onto else 1.0 - t)
		await get_tree().create_timer(1.0 / 12.0).timeout
		if not is_instance_valid(sp):
			return
	sp.queue_free()
	if onto and is_instance_valid(onto) and onto.tag is Dictionary and onto.tag == design:
		onto.retag(design)


## 米袋が足もとに、ぽんと出る（見た目だけ。12 コマで 4 コマ: ふくらんで、少し行き過ぎて戻る）
func _pop(s: RigidBody3D) -> void:
	var body: Node3D = s.get("_body")
	if body == null:
		return
	for k in [0.35, 1.15, 0.95, 1.0]:
		body.scale = Vector3(k, k, k)
		await get_tree().create_timer(1.0 / 12.0).timeout
		if not is_instance_valid(body):
			return


## 誰も乗っていない米袋から持ち主が遠く離れたら、ひとりでに帯に戻す（ホストの片付け）
func _physics_process(dt: float) -> void:
	if sack_out.is_empty():
		return
	var net := _net()
	if net and net.online and not net.is_host():
		return   # ひとりでに帯に戻すのは、ホストが決める
	var hub: Node = world.get_node_or_null("Emotes") if world else null
	for who in sack_out.keys():
		var gs := sack_sled(who)
		var owner: Node3D = hub.who_of(who) if hub else null
		if gs == null:
			sack_out.erase(who)
			continue
		var idle: bool = gs.riders.is_empty() and gs.holders.is_empty() and gs.rope_holder == null
		var far := owner == null or owner.global_position.distance_to(gs.global_position) > SACK_FAR
		_sack_far[who] = (_sack_far.get(who, 0.0) + dt) if idle and far else 0.0
		if _sack_far[who] > SACK_FAR_T:
			send({"kind": "sack_in", "who": who, "auto": true})


## ソリの出る所に立っている人を、ソリの横へよける（重なったまま出すと、ソリが薄い床の下へ押し出される）
func _make_room(s: RigidBody3D) -> void:
	var k: Dictionary = Sled.KINDS.get(s.kind, Sled.KINDS["mid"])
	var half := Vector2(k.box.x, k.box.z) * 0.5 + Vector2(0.45, 0.45)
	for c in s.get_parent().get_children():
		if not (c is CharacterBody3D):
			continue
		var lp := s.to_local((c as Node3D).global_position)
		if absf(lp.x) < half.x and absf(lp.z) < half.y and absf(lp.y) < 2.0:
			lp.x = half.x * (1.0 if lp.x >= 0.0 else -1.0)
			(c as Node3D).global_position = s.to_global(lp) + Vector3.UP * 0.05


## 向き yaw で、上を up（床の傾き）に合わせた向き
static func _basis(yaw: float, up: Vector3) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	if up.dot(Vector3.UP) < 0.999:
		b = Basis(Quaternion(Vector3.UP, up.normalized())) * b
	return b


## ソリの番号（畳めるソリでなければ -1）
func id_of(s: Node) -> int:
	for id in sleds:
		if sleds[id] == s:
			return id
	return -1
