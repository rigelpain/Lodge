extends CanvasLayer
## 工房の画面: 持ち物の列と、売り子の売り台。文字は使わない（絵は craft_icons.gd と hud_icons.gd）。手に持つ物の名前の札だけは例外。
##   持ち物は手持ち 6 ＋ かばん 6 の決まった場所（craft.gd の HAND_SLOTS・SLOTS。空いた場所はそのまま空いている）。
##   持ち物の列（画面の下のまんなか）: 左端が素手（手袋）、続けて手持ちの 6 マス（空いたマスは縫い目だけ）。手に持っている物は
##     少し持ち上がり、赤い糸で囲む。持ち替えたとき、列の上に名前の紙の札を 2 秒ほど出す。
##     右に財布（木のボタンを数だけ積む。ボタンがなければ出さず、列はマスのすぐ右で終わる）。ホイールで手に持つ物を替える（player.gd）。
##     遊んでいるあいだはいつも出しておく（2026-11-01 代表「常時手持ちインベントリ表示」）
##   売り台（おじさんに F）: 上の段に型紙 4 枚、下の段に布 6 色。どれも絵と、値段のボタンの数。
##     品物を押して選び、右の買うボタン（ボタン → 手袋）で買う。足りない品物は薄く、買えないときは買うボタンが震える。
##     閉じるのは右上の × の縫い目か、F か Esc
##     左上の札で棚を替える: 型紙と布・滑りあとの柄（stitches.gd。2026-11-06 代表「滑り後のステッチをソリ屋で買ってインベントリでソリごとに設定できるようにして欲しい」）。
##     柄は持ち物の場所を使わず、人ごとに一度買えばよい
##   ミシンの画面（ミシンの前で F か T）: 上に型紙の枠と布の枠、その右にできるソリ（広げた姿がくるくる回る）と縫うボタン。
##     下に自分の持ち物が 2 段（手持ち・かばん）で並び、押すと型紙は型紙の枠、布は布の枠に入る（枠を押すと外す）。開いたときは、手に持っている物か
##     最初の型紙・布が入っている。足りない枠は破線の空き枠で、おじさん（売り台の絵）を指す矢印が出る。
##     縫うボタンで、型紙と布をいっしょに使って 7 つの場面が始まる（片方だけ使われることはない）
##   装備の画面（I）: 左の上に自分の名前（打って替える）とキャラの色（12 色から押して選ぶ）。HUD の札の人の形の色と、頭の上の名前になる
##     （2026-10-31 代表「プレイヤー名はインベントリでじぶんできめれるように」）。その下に、いま装備している米袋（広げた姿がくるくる
##     回る）を帯に下げて見せる。右の上の段に、持っている米袋（標準のクラフト紙と、縫った色違い）が並び、装備しているものに赤い糸の印。
##     押すと装備が入れ替わる（N でそれが出る）。米袋に名札は付けない。
##     まんなかの段は名札: 左に大きく、右に部品（形・紙の色・縁の糸・吊るす糸・判子）の見本の列。名札の下に、どの名札を替えるかの札の列:
##     いつもの柄（針の印。これから縫うソリに付く）・自分のソリ（回る姿）・畳んだソリ・名札入れの外した名札。
##     押した札の名札だけが替わる（名札はソリごと。いつもの柄と名前と色は保存して、次に起動しても同じ）。
##     名札の段の 5 つ目の札は滑りあとの柄: 下の札でソリ（米袋・置いてある自分のソリ・畳んだ自分のソリ）を選び、右の棚で柄を押す。替えられるのは持ち主だけ。
##     6 つ目の札は大玉の縫い目の柄（ball_stitches.gd。2026-11-09 代表「雪玉のステッチも売って欲しい」）: 右の棚のはじめが手袋の柄（はめている手袋の
##     段の標準）、続けて山師の棚で売る柄。押すと、これから置く自分の大玉と、もう置いてある自分の大玉の柄が替わる。左に大きく、その柄の玉。
##     縫い合わせの形と糸の色は、玉を固めた手袋の段のまま。買っていない柄は薄く、木のボタンの印（山師の棚で買う）
##     右の下に、手持ち（上の段）とかばん（下の段, 緑のフェルトの巾着）。引きずって入れ替える（行き先に物があれば入れ替わる）。
##     押して離すと上に小窓: できあがった料理なら食べる（おにぎり）、どれでも捨てる（編みかご）。装備の種類は craft.gd の GEARS（米袋とランタン。服は段を足す）。閉じるのは ×、I、Esc
##     左の下は持っているランタン（木の手提げ・提灯）。押すと帯の左に提げ替え、提げているのをもう一度押すと外す（R で点ける・消す）
##     右上（× の下）は持っている雪玉ころがしの手袋（山師の棚で買ったもの。gloves.gd）。押すとはめ、はめているのをもう一度押すと外す
##   財布が増えたとき（craft.gd の earn。雪に縫い留められたボタンを取った・滑った）: ボタンが画面を飛んで財布へ入り、
##     財布がぽんと跳ねる。雪のボタンを切って取った分は、3D のボタンが体（胸）に飛び込み終えた次のコマに、体の画面の位置から
##     飛び出す（一人称では胸は画面の下の外なので、画面の下の縁から。snow_buttons.gd の into_body。2026-11-02 代表「ボタンが体に
##     入って、体からインベントリHUDに入るようにしてほしい」）。そのときに小さく「ぷつ」。財布まで 12 fps のコマで飛ぶ（FLY_FRAMES）。財布に着くたびに、素材ごとの取得音（audio.gd の coin。木コッ・真鍮チン・白蝶貝シャラン・螺鈿）。
##     飛ぶボタンは、増えた分を段ごとに分けた 1 枚ずつ（真鍮・白蝶貝・螺鈿は光る）。滑ってもらった分は、速さの表示の糸の上に
##     縫い込まれたボタンが、上から順にぽんぽんと続けて飛ぶ
##   財布は段ごとの山（左から木・真鍮・白蝶貝・螺鈿。価値の低い順）。両替はひとりでに（木が 10 枚になると真鍮 1 枚）
## 出来事は craft.gd へ送る（いまはすぐ配られる。通信ではホストが確かめる）。

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Craft := preload("res://craft.gd")
const Fabrics := preload("res://fabrics.gd")
const Stitches := preload("res://stitches.gd")
const BallStitches := preload("res://ball_stitches.gd")
const Gloves := preload("res://gloves.gd")
const Doll := preload("res://doll.gd")
const PersonIcon := preload("res://person_icon.gd")
const ABOVE_HOOP := 72.0   # 刺繍枠（自分の小窓）の上の縁から、I・N・R の札の下までの間（1080 で px）。上のねじ（30 px ほど）と、
                            # 枠の右上に縫う体の調子のバッジ（badges.gd）を避ける（2026-11-01 代表「インベントリボタンを少し上に上げて干渉しないように」）

var main: Node3D
var craft: Node
var player: Node3D
var shop_open := false
var machine_open := false
var gear_open := false
var _gear_rects: Array = []  # 装備の画面の、持っている米袋の札
var _lamp_rects: Array = []  # 装備の画面の、持っているランタンの札
var _lamp_hover := -1
var _glove_rects: Array = [] # 装備の画面の、持っている手袋の札（右上。gloves.gd）
var _glove_hover := -1
var _opt_rects: Array = []   # 装備の画面の、名札の部品の見本 [Rect2, 部品, 番号]（部品 "_page" はページの札、"_dice" はおまかせ）
var tag_page := 0            # 装備の画面で開いている、名札の部品のページ（sled_tags.gd の PAGES）
var tag_edit := {}           # 装備の画面で替えている名札: {}（いつもの柄）か {id}（置いてある自分のソリ）・{slot}（畳んだソリ）・{loose}（名札入れ）
var _edit_rects: Array = []  # 装備の画面の、替える名札を選ぶ札 [Rect2, tag_edit の値]
var _color_rects: Array = [] # 装備の画面の、キャラの色の見本 [Rect2, 番号]
var name_edit: LineEdit      # 装備の画面の、名前を打つ欄
var _name_rect := Rect2()
var _opt_hover := -1         # 指している見本（_opt_rects の番号）
var _pick := {"pattern": -1, "fabric": -1}   # ミシンの画面で枠に入れた持ち物の番号
var _bag_rects: Array = []   # ミシンの画面の持ち物の札（持ち物の場所の番号順。空いた場所は Rect2()）
var _inv_rects: Array = []   # 装備の画面の、手持ちとかばんのマス（場所の番号順）
var _drag := {}              # 装備の画面で引きずっている持ち物 {from, start, at, moved}
var _inv_menu := -1          # 装備の画面で押した持ち物の場所（食べる・捨てるの小窓を出している）。-1 は出していない
var _menu_rects: Array = []  # その小窓のボタン [Rect2, "eat" / "trash"]
var _name_t := 0.0           # 手に持つ物の名前の札を出しておく残りの秒
var _name_key := ""          # 名前の札を出した物（持ち替えたら出し直す）
const NAME_T := 2.0          # 持ち替えたとき、名前の札を出しておく秒（最後の 0.4 秒で消える）
var _slot_rects := {}        # "pattern" / "fabric" → 枠
var _sew_rect := Rect2()
var _view: View
var _sel := -1               # 売り台で選んでいる品物（_goods の番号）
var _hover := -1
var _hover_btn := ""         # "buy" "close"
var _shake := 0.0
var _pop := {}               # 持ち物の番号 → 跳ねの残り
var _coin_pop := 0.0
var _balls := -1             # 前に見た雪玉の数（増えた・減ったで弾ませる）
var _ball_pop := 0.0
var _ball_dir := 0           # 増えた (1)・減った (-1)
var _flies: Array = []       # 財布へ飛んでいるボタン 1 枚ずつ {from（画面の px）, t（0→1）, look（段）, v（値打ち）, sewn（速さの表示の糸の上の番号。なければ -1）,
                             #   f0・body（体から飛び出すコマと、その体。12 fps のコマで進む）}
var _pending := 0            # 飛んでいて、まだ財布に描かない値打ち（木のボタンの何個分）
var _tier_at := {}           # 段 → 財布のその段の山の、次の 1 枚が載る所（画面の px。描くときに決まる）
var _batches := {}           # 滑った分（spool）の一まとまり → {left: まだ飛んでいる数, count, brass}。全部入ったら締めくくりの「ちゃりん」
var _next_batch := 1
var _shine_t := 0.0          # お金のボタンの光の時計
var _wallet_at := Vector2.ZERO   # 財布の、次のボタンが載る所（画面の px。描くときに決まる）
const FLY_T := 0.75          # 財布まで飛ぶ秒
const FLY_FRAMES := 9        # 体から財布まで飛ぶコマ（12 fps。FLY_T と同じ長さ）
var _bar_a := 0.0
var _goods: Array = []       # 売る品物の並び
var shop_page := 0           # 売り台の開いている棚。0: 型紙と布、1: 滑りあとの柄
var _stitch_goods: Array = []   # 売っている滑りあとの柄の名前
var _tab_rects: Array = []   # 棚の札の場所
var stitch_edit := {}        # 装備の画面で柄を替えているソリ: {sack}（米袋）・{id}（置いてある自分のソリ）・{slot}（畳んだソリ）
var _rects: Array = []       # 品物の札の場所（画面の px）
var _buy_rect := Rect2()
var _close_rect := Rect2()


func _ready() -> void:
	layer = 4
	for k in Craft.PATTERNS:
		_goods.append({"kind": "pattern", "sled": k})
	for f in Fabrics.ORDER:
		_goods.append({"kind": "fabric", "fabric": f})
	_stitch_goods = Stitches.for_sale()
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	name_edit = LineEdit.new()   # 名前を打つ欄（紙のラベルの見た目。装備の画面のときだけ出す）
	name_edit.visible = false
	name_edit.max_length = Craft.NAME_MAX
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.context_menu_enabled = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Icons.PAPER
	sb.border_color = Icons.PAPER_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for st in ["normal", "focus", "read_only"]:
		name_edit.add_theme_stylebox_override(st, sb)
	name_edit.add_theme_color_override("font_color", Icons.THREAD)
	name_edit.add_theme_color_override("caret_color", Icons.RED)
	name_edit.text_submitted.connect(func(_t): name_edit.release_focus())
	name_edit.focus_exited.connect(_send_name)
	add_child(name_edit)
	if craft:
		craft.happened.connect(_on_craft)


func ui() -> float:
	return Icons.ui_scale(_view.size.y)   # 画面の高さ × 設定の「HUD の大きさ」


func _who() -> int:
	return int(player.get("id")) if player else -1


## 雪合戦で戦っているあいだ: 持ち物のマスと雪玉のストックだけを残す（main.gd の set_duel_focus）
func _focus() -> bool:
	return main != null and main.get("duel_focus") == true


func _open_panel() -> void:
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)


func _close_panel() -> void:
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)


func open_shop() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	shop_open = true
	shop_page = 0
	_sel = -1
	_open_panel()
	var sk = main.get("shopkeeper")
	if sk:
		sk.shop_open = true
		sk.greet()


func close_shop() -> void:
	if not shop_open:
		return
	shop_open = false
	_close_panel()
	var sk = main.get("shopkeeper")
	if sk:
		sk.shop_open = false


## 選んでいる品物を買う
func buy() -> bool:
	if _sel < 0:
		_shake = 1.0
		return false
	var ok: bool
	if shop_page == 1:
		ok = craft.send({"kind": "stitch_buy", "who": _who(), "stitch": _stitch_goods[_sel]})
	else:
		ok = craft.send({"kind": "buy", "who": _who(), "item": _goods[_sel].duplicate()})
	if not ok:
		_shake = 1.0
	return ok


## 売り台で選んでいる品物の値段（選んでいなければ 0）
func sel_price() -> int:
	if _sel < 0:
		return 0
	return Stitches.price(_stitch_goods[_sel]) if shop_page == 1 else Craft.price(_goods[_sel])


## 売り台で選んでいる品物を、いま買えるか
func sel_ready() -> bool:
	if _sel < 0 or sel_price() > craft.wallet(_who()):
		return false
	if shop_page == 1:
		return not _stitch_goods[_sel] in craft.stitch_owned.get(_who(), [])
	return craft.free_slot(_who()) >= 0 or _goods[_sel].kind == "peg" and craft._peg_stack(_who()) >= 0


## 柄を替えられるソリの並び [stitch_edit の値, 絵 {sled, fabric, folded?}, いまの柄の名前]: 持っている米袋・置いてある自分のソリ・畳んだ自分のソリ
func stitch_targets() -> Array:
	var who := _who()
	var out: Array = []
	var sacks: Array = craft.sacks.get(who, [])
	for i in sacks.size():
		out.append([{"sack": i}, {"sled": "sack", "fabric": sacks[i].get("fabric", "")}, _stitch_of("sack", sacks[i].get("stitch", ""))])
	for id in craft.sleds:
		var s = craft.sleds[id]
		if is_instance_valid(s) and int(s.owner_id) == who:
			out.append([{"id": id}, {"sled": s.kind, "fabric": s.fabric}, s.stitch_kind()])
	var b: Array = craft.bag(who)
	for i in b.size():
		if b[i].get("kind") == "folded" and preload("res://sled_tags.gd").has_tag(b[i].get("tag", -1)):
			out.append([{"slot": i}, {"sled": b[i].sled, "fabric": b[i].fabric, "folded": true}, _stitch_of(b[i].sled, b[i].get("stitch", ""))])
	return out


func _stitch_of(kind: String, override: String) -> String:
	return override if Stitches.has(override) else String(preload("res://sled.gd").KINDS.get(kind, {}).get("stitch", "running"))


## いま柄を替えているソリの [stitch_edit の値, 絵, 柄]。先がなくなっていれば、装備している米袋に戻す
func stitch_target() -> Array:
	var list := stitch_targets()
	for t in list:
		if t[0] == stitch_edit:
			return t
	stitch_edit = {"sack": craft.gear_index(_who(), "sack")}
	for t in list:
		if t[0] == stitch_edit:
			return t
	return list[0] if not list.is_empty() else [{}, {}, ""]


## 名札の段の、大玉の縫い目の柄のページの番号（滑りあとの柄の次）
func ball_page() -> int:
	return preload("res://sled_tags.gd").PAGES.size() + 1


## 自分の大玉に縫う柄を選ぶ（"" は手袋の段の標準。確かめ用の入口も兼ねる）
func set_ball_stitch(nm: String) -> bool:
	if not craft.ball_can_use(_who(), nm):
		_shake = 1.0
		return false
	return craft.send({"kind": "ball_stitch_set", "who": _who(), "stitch": nm})


## いま替えているソリの柄を替える（確かめ用の入口も兼ねる）
func set_stitch(nm: String) -> bool:
	var key: Dictionary = stitch_target()[0]
	if key.is_empty() or not craft.stitch_can_use(_who(), nm):
		_shake = 1.0
		return false
	var ev := {"kind": "sled_stitch", "who": _who(), "stitch": nm}
	ev.merge(key)
	return craft.send(ev)


func _on_craft(ev: Dictionary) -> void:
	if ev.get("who", -1) != _who():
		return
	match ev.kind:
		"stitch_buy":
			_coin_pop = 1.0
			var sk = main.get("shopkeeper")
			if sk:
				sk.sold()
			if player.has_method("save_tag"):
				player.save_tag()
		"sled_stitch":
			if ev.has("sack") and player.has_method("save_tag"):
				player.save_tag()
		"ball_stitch_buy", "ball_stitch_set":   # 大玉の縫い目の柄（買った柄と選んだ柄は、次に起動しても同じ。ball_stitches.gd）
			if ev.kind == "ball_stitch_buy":
				_coin_pop = 1.0
			if player.has_method("save_tag"):
				player.save_tag()
		"equip":   # はめた手袋は、次に起動しても同じ（gloves.gd）
			if ev.get("gear", "") == "gloves" and player.has_method("save_tag"):
				player.save_tag()
		"earn":
			# 3D のボタンがぽんと跳ね上がったところ（少しあと、少し上）から飛び出す
			var at: Variant = ev.get("at", Vector3.INF)
			if at is Vector3 and at != Vector3.INF:
				at += Vector3.UP * 1.4
			var spool: bool = ev.get("from", "") == "spool"
			var from := _screen_of(at)
			var hud = main.get("hud") if main else null
			var on_spool: bool = spool and hud and hud.get("_reel") != null and (hud._reel > 0.0 or hud._spd_a > 0.1)
			if on_spool:   # 速さの表示の糸巻きから（糸の上に見つからないボタン）
				from = preload("res://speedo.gd").layout(hud.speedo_box_now(), 0.0).c
			var list: Array = ev.get("pieces", []).duplicate() if ev.has("pieces") else Craft.pieces(int(ev.n))
			if on_spool:
				var extra: int = int(ev.n) - hud.sewn_value()
				if extra >= 0 and extra < 10:
					list = hud.sewn_looks()   # 糸の上のボタン（両替したあと）を、上から順に
					for i in extra:   # 持ち越した端数が木 1 個になった分は、糸巻きから
						list.append("wood")
				else:
					list = Craft.pieces(int(ev.n))   # 糸の上と合わないときは、段ごとに分けて糸巻きから
			if list.size() > 24:   # 多すぎるときは大きい段だけ飛ばし、残りはまとめて財布へ
				list = list.slice(0, 24)
			# 雪のボタンを切って取った分: 3D のボタンが体に入り終えたら、体から飛び出す（同じボタンが二つに見えないように）
			var sb = main.get("snow_buttons") if main and not spool else null
			var into: Dictionary = sb.into_body(int(ev.btn), ev.at) if sb and ev.has("btn") and ev.get("at") is Vector3 else {}
			var flown := 0
			var gap := 0.065   # 続けて入る間: 財布でチャリチャリ…と連なる（audio.gd の coin）
			var batch := 0
			if spool:
				batch = _next_batch
				_next_batch += 1
				_batches[batch] = {"left": list.size(), "count": list.size(), "brass": "brass" in list}
			for k in list.size():
				var v: int = {"raden": 1000, "pearl": 100, "brass": 10, "wood": 1}[list[k]]
				flown += v
				var si: int = hud.sewn_claim(list[k]) if on_spool else -1
				var fl := {"from": from, "t": -0.45 - k * gap, "look": list[k], "v": v, "sewn": si, "step": k, "batch": batch}
				if not into.is_empty():   # 1 コマずつずらして、体から続けて
					fl.f0 = int(into.frame) + k
					fl.body = into.body
					fl.t = -1.0
				_flies.append(fl)
			_pending += flown
		"buy", "fold":
			if int(ev.slot) >= 0:
				_pop[int(ev.slot)] = 1.0
			elif ev.kind == "buy" and player.has_method("save_tag"):   # 雪玉ころがしの手袋は装備なので持ち物の場所に入らない（slot -1）。次に起動しても同じ
				player.save_tag()
			_coin_pop = 1.0 if ev.kind == "buy" else _coin_pop
			if ev.kind == "buy" and ev.item.get("kind", "") in ["pattern", "fabric"]:   # 山男の棚の品物は、山男がうなずく（mountain_man.gd）
				var sk = main.get("shopkeeper")
				if sk:
					sk.sold()


## ミシンの画面を開く。手に持っている物か、最初の型紙・布を枠に入れておく
## 世界の点が画面のどこに見えるか。見えなければ、画面の上の方のまんなかから
func _screen_of(p: Variant) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if p is Vector3 and p != Vector3.INF and cam and not cam.is_position_behind(p):
		var at := cam.unproject_position(p)
		if Rect2(Vector2.ZERO, _view.size).grow(-24.0).has_point(at):
			return at
	return Vector2(_view.size.x * 0.5, _view.size.y * 0.3)


## 体の胸が画面のどこに見えるか。画面の外（一人称では胸は画面の下の外、うしろ）なら、そちらの向きの画面の縁から
func _screen_edge(p: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var r := Rect2(Vector2.ZERO, _view.size).grow(-24.0)
	var c := r.get_center()
	if cam == null:
		return Vector2(c.x, r.end.y)
	var lp := cam.global_transform.affine_inverse() * p
	var d := Vector2(lp.x, -lp.y)
	if lp.z < -0.05:
		var at := cam.unproject_position(p)
		if r.has_point(at):
			return at
		d = at - c
	if d.length() < 0.001:
		d = Vector2.DOWN
	var k := minf(r.size.x * 0.5 / maxf(absf(d.x), 0.001), r.size.y * 0.5 / maxf(absf(d.y), 0.001))
	return c + d * k


func open_machine() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	machine_open = true
	_pick = {"pattern": -1, "fabric": -1}
	var bag: Array = craft.bag(_who())
	var held: int = craft.hands.get(_who(), -1)
	for kind in ["pattern", "fabric"]:
		if held >= 0 and held < bag.size() and bag[held].get("kind", "") == kind:
			_pick[kind] = held
			continue
		for i in bag.size():
			if bag[i].get("kind", "") == kind:
				_pick[kind] = i
				break
	_open_panel()


func close_machine() -> void:
	if not machine_open:
		return
	machine_open = false
	_close_panel()


## 持ち物の i 番を枠に入れる（同じ物なら外す）
func pick(i: int) -> void:
	var bag: Array = craft.bag(_who())
	if i < 0 or i >= bag.size() or not bag[i].get("kind", "") in ["pattern", "fabric"]:
		_shake = 1.0
		return
	var kind: String = bag[i].kind
	_pick[kind] = -1 if _pick[kind] == i else i


## 縫う: 枠の型紙と布をいっしょに使って、ミシンを動かす。そろっていなければ縫うボタンが震える
func sew() -> bool:
	var bag: Array = craft.bag(_who())
	var ps: int = _pick.pattern
	var fs: int = _pick.fabric
	if ps < 0 or fs < 0 or ps >= bag.size() or fs >= bag.size():
		_shake = 1.0
		return false
	var ok: bool = craft.send({"kind": "sew", "who": _who(), "pattern": bag[ps].duplicate(), "fabric": bag[fs].duplicate(),
			"pattern_slot": ps, "fabric_slot": fs})
	if ok:
		close_machine()
	else:
		_shake = 1.0
	return ok


## 装備の画面の手持ちとかばん: 引きずって入れ替える（行き先に物があれば入れ替わる）。押して離すと、食べる・捨てるの小窓。
## 小窓のボタンは離したときに効く（食べ始めの左ボタンの離しで、食べるのが止まらないように）。扱った入力なら true
func _inv_input(e: InputEvent) -> bool:
	var at_slot := func(p: Vector2) -> int:
		for i in _inv_rects.size():
			if (_inv_rects[i] as Rect2).has_point(p):
				return i
		return -1
	if e is InputEventMouseMotion and not _drag.is_empty():
		_drag.at = e.position
		if not _drag.moved and e.position.distance_to(_drag.start) > 8.0:
			_drag.moved = true
			_inv_menu = -1
		return true
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		return false
	var who := _who()
	var b: Array = craft.bag(who)
	if e.pressed:
		for m in _menu_rects:
			if (m[0] as Rect2).has_point(e.position):
				return true   # 小窓のボタン: 離したときに
		var i: int = at_slot.call(e.position)
		if i >= 0 and i < b.size() and not b[i].is_empty():
			_drag = {"from": i, "start": e.position, "at": e.position, "moved": false}
			return true
		if _inv_menu >= 0:
			_inv_menu = -1   # 小窓の外を押した: 閉じる
			return i >= 0
		return i >= 0
	# 離した
	for m in _menu_rects:
		if (m[0] as Rect2).has_point(e.position) and _inv_menu >= 0:
			var slot := _inv_menu
			_inv_menu = -1
			if m[1] == "trash":
				craft.send({"kind": "drop", "who": who, "slot": slot})
			elif m[1] == "eat":
				eat_slot(slot)
			return true
	if _drag.is_empty():
		return false
	var from: int = _drag.from
	var moved: bool = _drag.moved
	_drag = {}
	if moved:
		var to: int = at_slot.call(e.position)
		if to >= 0 and to != from:
			craft.send({"kind": "move", "who": who, "from": from, "to": to})
	else:
		_inv_menu = -1 if _inv_menu == from else from
	return true


## 持ち物の slot 番の料理を食べる: かばんにあれば手持ち（空き、なければ手に持っている所）へ出し、手に持って画面を閉じ、食べ始める
func eat_slot(slot: int) -> void:
	var who := _who()
	var b: Array = craft.bag(who)
	var to := slot
	if slot >= Craft.HAND_SLOTS:
		to = -1
		for i in Craft.HAND_SLOTS:
			if b[i].is_empty():
				to = i
				break
		if to < 0:
			to = maxi(craft.hands.get(who, -1), 0)
		if not craft.send({"kind": "move", "who": who, "from": slot, "to": to}):
			return
	craft.send({"kind": "hand", "who": who, "slot": to})
	close_gear()
	if player.has_method("eat_held"):
		player.eat_held()


## 装備の画面を開く
func open_gear() -> void:
	if shop_open or machine_open or gear_open or player == null:
		return
	gear_open = true
	tag_edit = {}
	_drag = {}
	_inv_menu = -1
	name_edit.text = craft.name_of(_who())
	_open_panel()


func close_gear() -> void:
	if not gear_open:
		return
	if name_edit.has_focus():
		name_edit.release_focus()   # 打った名前を決める
	gear_open = false
	name_edit.visible = false
	_close_panel()


## 名前を決める（打つ欄から離れた・Enter）。空なら前の名前のまま
func _send_name() -> void:
	if craft == null or name_edit.text.strip_edges() == "":
		name_edit.text = craft.name_of(_who()) if craft else ""
		return
	set_profile(name_edit.text, int(craft.colors.get(_who(), 0)))


## 名前とキャラの色を決める（確かめ用の入口も兼ねる）。保存もする
func set_profile(nm: String, color: int) -> bool:
	var ok: bool = craft.send({"kind": "profile", "who": _who(), "name": nm, "color": color})
	if ok and player.has_method("save_tag"):
		player.save_tag()
	if ok:
		name_edit.text = craft.name_of(_who())
	return ok


## 替えている名札の柄（tag_edit の先がなくなっていれば、いつもの柄に戻す）
func edit_design() -> Dictionary:
	var who := _who()
	var Tags := preload("res://sled_tags.gd")
	if tag_edit.has("id"):
		var s = craft.sleds.get(int(tag_edit.id))
		if s != null and is_instance_valid(s) and int(s.owner_id) == who and s.tag is Dictionary:
			return s.tag
	elif tag_edit.has("slot"):
		var b: Array = craft.bag(who)
		var i := int(tag_edit.slot)
		if i >= 0 and i < b.size() and b[i].get("tag", -1) is Dictionary:
			return b[i].tag
	elif tag_edit.has("loose"):
		var lt: Array = craft.loose_tags.get(who, [])
		var i := int(tag_edit.loose)
		if i >= 0 and i < lt.size() and lt[i] is Dictionary:
			return lt[i]
	tag_edit = {}
	var d = craft.tag_designs.get(who, {})
	return d if d is Dictionary else Tags.default_design(who)


## 替えられる名札の並び [tag_edit の値, 名札, 絵（{} / {sled, fabric}）]: いつもの柄・置いてある自分のソリ・畳んだソリ・名札入れ
func edit_targets() -> Array:
	var who := _who()
	var out: Array = [[{}, craft.tag_designs.get(who, {}), {}]]
	for id in craft.sleds:
		var s = craft.sleds[id]
		if is_instance_valid(s) and int(s.owner_id) == who and s.kind != "sack" and s.tag is Dictionary:
			out.append([{"id": id}, s.tag, {"sled": s.kind, "fabric": s.fabric}])
	var b: Array = craft.bag(who)
	for i in b.size():
		if b[i].get("kind") == "folded" and b[i].get("sled") != "sack" and b[i].get("tag", -1) is Dictionary:
			out.append([{"slot": i}, b[i].tag, {"sled": b[i].sled, "fabric": b[i].fabric, "folded": true}])
	var lt: Array = craft.loose_tags.get(who, [])
	for i in lt.size():
		out.append([{"loose": i}, lt[i], {"loose": true}])
	return out


## 種類 gear の持っている物の i 番を装備する（確かめ用の入口も兼ねる）。ランタンは -1 で外す
func equip(i: int, gear := "sack") -> bool:
	return craft.send({"kind": "equip", "who": _who(), "gear": gear, "index": i})


## 自分の名札の部品を替える（確かめ用の入口も兼ねる）。保存もする。まだ手に入れていない部品は選べない
func set_tag_part(part: String, i: int, save := true) -> bool:
	if not craft.tag_can_use(_who(), part, i):
		_shake = 0.4
		return false
	var d: Dictionary = edit_design().duplicate()
	d[part] = i
	return _send_tag(d, save)


## おまかせ: 使える部品から選び直す。地と模様の色は、見分けられるほど離す
func shuffle_tag(save := true) -> bool:
	var Tags := preload("res://sled_tags.gd")
	var d := {}
	for part in Tags.PARTS:
		var ok := []
		for i in Tags.part_count(part):
			if craft.tag_can_use(_who(), part, i):
				ok.append(i)
		d[part] = ok.pick_random()
	var paper: Color = Tags.PAPERS[d.paper]
	var far := []
	for i in Tags.part_count("accent"):
		if craft.tag_can_use(_who(), "accent", i) and absf(Tags.PAPERS[i].get_luminance() - paper.get_luminance()) > 0.15:
			far.append(i)
	if not far.is_empty():
		d["accent"] = far.pick_random()
	return _send_tag(d, save)


## 替えている名札（tag_edit）に柄を送る。いつもの柄なら保存もする
func _send_tag(d: Dictionary, save: bool) -> bool:
	edit_design()   # 先がなくなっていれば、いつもの柄に戻す
	if not tag_edit.is_empty():
		var ev := {"kind": "sled_tag", "who": _who(), "design": d}
		ev.merge(tag_edit)
		return craft.send(ev)
	var ok: bool = craft.send({"kind": "tag_design", "who": _who(), "design": d})
	if ok and save and player.has_method("save_tag"):
		player.save_tag()
	return ok


func _gear_input(e: InputEvent) -> void:
	if name_edit.has_focus():   # 名前を打っているあいだは、キーは打つ欄へ（Esc で打つのをやめる）
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
			name_edit.release_focus()
			get_viewport().set_input_as_handled()
			return
		if e is InputEventKey:
			return
	if e is InputEventMouseButton and e.pressed and _name_rect.has_point(e.position):
		return   # 名前の欄を押した: 打つ欄に任せる
	if e is InputEventMouseButton and e.pressed and name_edit.has_focus():
		name_edit.release_focus()
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_I]:
		close_gear()
		get_viewport().set_input_as_handled()
	elif _inv_input(e):
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = -1
		for i in _gear_rects.size():
			if (_gear_rects[i] as Rect2).has_point(e.position):
				_hover = i
		_lamp_hover = -1
		for i in _lamp_rects.size():
			if (_lamp_rects[i] as Rect2).has_point(e.position):
				_lamp_hover = i
		_glove_hover = -1
		for i in _glove_rects.size():
			if (_glove_rects[i] as Rect2).has_point(e.position):
				_glove_hover = i
		_hover_btn = "close" if _close_rect.has_point(e.position) else ""
		_opt_hover = -1
		for i in _opt_rects.size():
			if (_opt_rects[i][0] as Rect2).has_point(e.position):
				_opt_hover = i
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_gear()
			return
		for i in _gear_rects.size():
			if (_gear_rects[i] as Rect2).has_point(e.position):
				equip(i)
				return
		for i in _lamp_rects.size():
			if (_lamp_rects[i] as Rect2).has_point(e.position):
				equip(-1 if i == craft.gear_index(_who(), "lantern") else i, "lantern")   # 提げているのを押すと外す
				return
		for i in _glove_rects.size():
			if (_glove_rects[i] as Rect2).has_point(e.position):
				equip(-1 if i == craft.gear_index(_who(), "gloves") else i, "gloves")   # はめているのを押すと外す
				return
		for c in _color_rects:
			if (c[0] as Rect2).has_point(e.position):
				set_profile(craft.name_of(_who()), c[1])
				return
		for t in _edit_rects:
			if (t[0] as Rect2).has_point(e.position):
				if tag_page == preload("res://sled_tags.gd").PAGES.size():
					stitch_edit = t[1]
				else:
					tag_edit = t[1]
				return
		for o in _opt_rects:
			if (o[0] as Rect2).has_point(e.position):
				match o[1]:
					"_page":
						tag_page = o[2]
						_opt_hover = -1
					"_dice":
						shuffle_tag()
					"_stitch":
						set_stitch(o[2])
					"_ball":
						set_ball_stitch(o[2])
					_:
						set_tag_part(o[1], o[2])
				return


func _input(e: InputEvent) -> void:
	if gear_open:
		_gear_input(e)
		return
	if machine_open:
		_machine_input(e)
		return
	if not shop_open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_F]:
		close_shop()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
		_hover_btn = "buy" if _buy_rect.has_point(e.position) else ("close" if _close_rect.has_point(e.position) else "")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_shop()
		elif _buy_rect.has_point(e.position):
			buy()
		else:
			for k in _tab_rects.size():
				if (_tab_rects[k] as Rect2).has_point(e.position) and k != shop_page:
					shop_page = k
					_sel = -1
					_hover = -1
					return
			var i := _hit(e.position)
			if i >= 0:
				_sel = i


func _machine_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_F, KEY_T]:
		close_machine()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = -1
		for i in _bag_rects.size():
			if (_bag_rects[i] as Rect2).has_point(e.position):
				_hover = i
		_hover_btn = "sew" if _sew_rect.has_point(e.position) else ("close" if _close_rect.has_point(e.position) else "")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close_machine()
		elif _sew_rect.has_point(e.position):
			sew()
		else:
			for kind in _slot_rects:
				if (_slot_rects[kind] as Rect2).has_point(e.position):
					_pick[kind] = -1
					return
			for i in _bag_rects.size():
				if (_bag_rects[i] as Rect2).has_point(e.position):
					pick(i)
					return


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(p):
			return i
	return -1


## 確かめ用: 品物を選ぶ（tools/shop_shots.gd）
func select(i: int) -> void:
	_sel = i


func _process(dt: float) -> void:
	if craft == null or player == null:
		return
	_bar_a = move_toward(_bar_a, 1.0, dt * 4.0)   # 持ち物の列はいつも出しておく（始めにふわっと出す）
	var held_it: Dictionary = craft.held(_who())
	var key := "" if held_it.is_empty() else "%d %s" % [craft.hands.get(_who(), -1), held_it]
	if key != _name_key:
		_name_key = key
		_name_t = NAME_T if key != "" else 0.0
	_name_t = maxf(0.0, _name_t - dt)
	_shake = maxf(0.0, _shake - dt * 2.5)
	_coin_pop = maxf(0.0, _coin_pop - dt * 2.5)
	var nb: int = player.ball_count() if player.has_method("ball_count") else 0
	if _balls >= 0 and nb != _balls:
		_ball_pop = 1.0
		_ball_dir = signi(nb - _balls)
	_balls = nb
	_ball_pop = maxf(0.0, _ball_pop - dt * 2.5)
	var hud = main.get("hud") if main else null
	for f in _flies.duplicate():
		var was: float = f.t
		if f.has("f0"):
			f.t = float(Doll.frame_index() - int(f.f0)) / FLY_FRAMES
		else:
			f.t += dt / FLY_T
		var audio = main.get_node_or_null("Audio") if main else null
		if was < 0.0 and f.t >= 0.0 and f.has("body"):   # 体に入ったボタンが、体から飛び出す（ぷつ）
			var sb = main.get("snow_buttons") if main else null
			f.from = _screen_edge(sb.chest_of(f.body)) if sb and is_instance_valid(f.body) else f.from
			if audio:
				audio.coin_off()
		if was < 0.0 and f.t >= 0.0 and int(f.get("sewn", -1)) >= 0 and hud:   # 糸の上のボタンが、ぽんと外れて飛び出す（ぷつ）
			f.from = hud.sewn_screen(int(f.sewn))
			hud.sewn_off(int(f.sewn))
			if audio:
				audio.coin_off()
		if f.t >= 1.0:   # 財布に入った: ぽんと跳ねて、素材の音（続くほど少し上がる）
			_flies.erase(f)
			_pending -= int(f.v)
			_coin_pop = 1.0
			if audio:
				audio.coin(String(f.look), int(f.get("step", 0)))
			var bt: Dictionary = _batches.get(int(f.get("batch", 0)), {})
			if not bt.is_empty():
				bt.left -= 1
				if bt.left <= 0:   # 滑った分が全部入った: 締めくくりの「ちゃりん」
					_batches.erase(int(f.batch))
					_coin_pop = 1.0
					if audio:
						audio.reward(int(bt.count), bool(bt.brass))
	_shine_t += dt
	for k in _pop.keys():
		_pop[k] = maxf(0.0, _pop[k] - dt * 2.5)
	name_edit.visible = gear_open and _name_rect.size.x > 0.0
	if name_edit.visible:
		name_edit.position = _name_rect.position
		name_edit.size = _name_rect.size
		name_edit.add_theme_font_size_override("font_size", maxi(10, int(_name_rect.size.y * 0.55)))
	var vst := _view_stamp()
	if vst != _view_stamp_last:
		_view_stamp_last = vst
		_view.queue_redraw()


var _view_stamp_last := []
var _shine_k := -1
var _shine_due := 0
var _shine_tick := 0

## 持ち物の列・お金・I N R の札・雪玉の中身の印。これが変わったときだけ描き直す（hud.gd の _view_stamp と同じ考え）。
## 毎コマ描くと M2 で 1 コマ 4〜5 ms かかり、本体の CPU を使い切って熱で遅くなる原因になっていた（2026-11-05 測定）。
## 画面を開いているあいだ・飛んでいるボタン・跳ね・名前の札の出入りは毎コマ。
## 真鍮より上のボタンは光るので 12 コマ／秒。人形が動くコマ（いちばん重いコマ）と重ならないよう 2 コマあとに描く。
## 印に入れ忘れた変化があっても、0.25 秒で追いつく
func _view_stamp() -> Array:
	var moving := shop_open or machine_open or gear_open or not _flies.is_empty() or _bar_a < 1.0 \
			or _shake > 0.0 or _coin_pop > 0.0 or _ball_pop > 0.0 or _name_t > 0.0
	for k in _pop:
		if _pop[k] > 0.0:
			moving = true
			break
	if moving:
		return [Engine.get_process_frames()]
	var who := _who()
	var coins: int = craft.wallet(who)
	var s := [_view.size, Icons.tuck, Icons.user_scale, _focus(), craft.hands.get(who, -1), craft.bag(who).hash(), coins, _pending, _balls,
			craft.sacks.get(who, []).hash(), craft.sack_sel.get(who, 0), craft.lantern(who).hash(), craft.lamp_on(who),
			Time.get_ticks_msec() / 250]
	var sc = main.get("self_cam") if main else null
	if sc and is_instance_valid(sc) and sc.get("_frame") != null:
		s.append_array([(sc._frame as Control).get_global_rect(), sc.get("hidden")])
	if coins >= 10:
		var k := Doll.frame_index()
		if k != _shine_k:
			_shine_k = k
			_shine_due = 2
		if _shine_due > 0:
			_shine_due -= 1
			if _shine_due == 0:
				_shine_tick += 1
		s.append(_shine_tick)
	return s


class View extends Control:
	var ui: Node

	func _draw() -> void:
		var u: float = ui.ui()
		if ui.shop_open:
			_draw_shop(u)
		if ui.machine_open:
			_draw_machine(u)
		if ui.gear_open:
			_draw_gear_screen(u)
		if ui._bar_a > 0.01:   # 操作のための表示なので、風では揺らさない（2026-10-29 代表）
			_draw_bar(u, ui._bar_a)
		if not ui._focus():
			_draw_flies(u)
			_draw_gear(u)
		_draw_balls(u)

	## 帯の装備の札（2026-10-29 代表「米袋は刺繍小窓の上においてほしい」）: 右下の刺繍の小窓の真上に、左から
	##   装備の画面（I・背負いかばん）、米袋（N。持っている米袋の数だけ点、選んでいるのは赤。出していれば破線の形）、
	##   ランタン（R。点いていれば光の輪。外していれば破線の形）。小窓を消していれば、画面の右下の隅に
	func _draw_gear(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var list: Array = craft.sacks.get(who, [])
		if list.is_empty() or ui.shop_open or ui.machine_open or ui.gear_open:
			return
		var cw := 70.0 * u
		var ch := 78.0 * u
		var gap := 10.0 * u
		var total := cw * 3.0 + gap * 2.0
		var cx := size.x - 18.0 * u - total / 2.0
		var bottom := size.y - 18.0 * u
		var sc = ui.main.get("self_cam") if ui.main else null
		if sc and is_instance_valid(sc) and not sc.get("hidden") and sc.get("_frame"):
			var fr: Control = sc._frame
			cx = minf(fr.position.x + fr.size.x / 2.0, size.x - 12.0 * u - total / 2.0)
			bottom = fr.position.y - ABOVE_HOOP * u   # 刺繍枠の上のねじと、右上のバッジ（badges.gd）の上
		var off := Icons.tuck_off(Rect2(cx - total / 2.0, bottom - ch, total, ch), size)   # 何もしないでいると画面の外へ（hud.gd の _update_tuck）
		cx += off.x
		bottom += off.y
		var spec: Dictionary = craft.sack(who)
		var lamp: Dictionary = craft.lantern(who)
		var cards := [["I", "gear"], ["N", "sack"], ["R", "lamp"]]
		for i in cards.size():
			var r := Rect2(cx - total / 2.0 + i * (cw + gap), bottom - ch, cw, ch)
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, cw, ch, 12.0 * u), Icons.PAPER, 0.88, true, Icons.PAPER_EDGE)
			var ic := r.get_center() + Vector2(4.0 * u, 2.0 * u)
			CraftIcons._at(ic, 58.0 * u)
			match cards[i][1]:
				"gear":
					CraftIcons.backpack(self, Vector2.ZERO, 1.0, 1.0)
				"sack":
					CraftIcons.rice_sack(self, Vector2.ZERO, 1.0, CraftIcons.sack_body(spec), CraftIcons.sack_band(spec), 1.0, craft.sack_sled(who) != null)
					Icons.screen()
					for k in list.size():
						var dp := Vector2(ic.x - (list.size() - 1) * 4.5 * u + k * 9.0 * u, r.end.y - 7.0 * u)
						draw_circle(dp, 2.8 * u, Color(Icons.RED if k == int(craft.sack_sel.get(who, 0)) else Icons.PAPER_EDGE, 1.0))
				"lamp":
					CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamp.get("look", "box"), craft.lamp_on(who), 1.0, lamp.is_empty())
			Icons.keycap(self, cards[i][0], r.position + Vector2(13.0 * u, 13.0 * u), 22.0 * u, 1.0)

	## 雪玉の数: I・N・R の札の上の、藍のフェルトのリボン。結び玉から縫い針まで赤い糸で縫ってあり、持っている数だけ綿の雪玉が糸に通る。
	## 玉のない所（5 つまでの空き）は、なみ縫いの目だけ。文字・数字なし。0 個のときは出さない。増えると新しい玉がぽんと弾み、
	## 減ると抜けた玉が上へ浮いて消える（2026-10-31 代表「三人称でもわかるように、雪玉ストック数の HUD がほしい」。
	## はじめの粒の札は「ダサい」と言われ、アートコンセプトから出した 3 案から代表が選んだ。design/hud.md）
	func _draw_balls(u: float) -> void:
		var n: int = ui._balls
		var gone: bool = ui._ball_dir < 0 and ui._ball_pop > 0.0   # 減った直後は、抜けた玉が消えるまで出しておく
		if (n <= 0 and not gone) or ui.shop_open or ui.machine_open or ui.gear_open:
			return
		var cw := 70.0 * u
		var gap := 10.0 * u
		var total := cw * 3.0 + gap * 2.0
		var cx := size.x - 18.0 * u - total / 2.0
		var bottom := size.y - 18.0 * u
		var sc = ui.main.get("self_cam") if ui.main else null
		if sc and is_instance_valid(sc) and not sc.get("hidden") and sc.get("_frame"):
			var fr: Control = sc._frame
			cx = minf(fr.position.x + fr.size.x / 2.0, size.x - 12.0 * u - total / 2.0)
			bottom = fr.position.y - ABOVE_HOOP * u
		var h := 46.0 * u
		var x0 := cx - total / 2.0
		var y := bottom - 78.0 * u - 10.0 * u - 8.0 * u - h / 2.0   # I・N・R の札の上
		if ui._focus():
			y = bottom - h / 2.0   # 雪合戦のあいだは札も刺繍枠もよけるので、右下の隅へ下ろす
		var off := Icons.tuck_off(Rect2(x0, y - h / 2.0, total + 10.0 * u, h), size)   # 何もしないでいると画面の外へ（針の先まで）
		x0 += off.x
		y += off.y
		var navy := Doll.STOCK_NAVY   # 人形の袖のストックと同じ藍のフェルト（白い雪の上でも、白い雪玉が映える）
		var hemp := Color(0.70, 0.57, 0.38)
		var red := Doll.STOCK_RED
		var holes := Color(navy.darkened(0.5), 0.8)
		Icons.screen()
		Icons.patch(self, Icons.rr(x0, y - h / 2.0, total, h, 10.0 * u), navy, 1.0, true, hemp)
		var step := 34.0 * u
		var bx := x0 + 30.0 * u
		var eye := Vector2(x0 + total - 44.0 * u, y)
		# 結び玉から、玉の並びの手前まで
		draw_circle(Vector2(x0 + 12.0 * u, y), 4.0 * u, red.darkened(0.2))
		Icons.thread(self, PackedVector2Array([Vector2(x0 + 12.0 * u, y), Vector2(bx - 8.0 * u, y)]), red, 2.6 * u)
		# 空き: なみ縫いの目と、両端の針穴
		for i in range(n, 5):
			var c := Vector2(bx + step * i, y)
			Icons.thread(self, PackedVector2Array([c + Vector2(-8.0 * u, 0), c + Vector2(8.0 * u, 0)]), red, 2.6 * u)
			for e in [-1.0, 1.0]:
				draw_circle(c + Vector2(e * 13.0 * u, 0), 1.3 * u, holes)
		# 最後の玉から針の穴まで
		var last := bx + step * 4.0 + 14.0 * u
		Icons.thread(self, PackedVector2Array([Vector2(last, y), eye]), red, 2.6 * u)
		# 糸に通った雪玉（糸は玉の中を通る）
		for i in mini(n, 5):
			var c := Vector2(bx + step * i, y)
			Icons.thread(self, PackedVector2Array([c + Vector2(-17.0 * u, 0), c + Vector2(17.0 * u, 0)]), red, 2.6 * u)
			var pp := sin(ui._ball_pop * PI) if ui._ball_dir > 0 and i == n - 1 else 0.0
			Icons.cotton(self, c - Vector2(0, 7.0 * u * pp), 14.0 * u * (1.0 + 0.2 * pp), i + 1)
		if gone and n < 5:
			var t: float = 1.0 - ui._ball_pop
			Icons.cotton(self, Vector2(bx + step * n, y - 16.0 * u * t), 14.0 * u * (1.0 - 0.3 * t), n + 1, 1.0 - t)
		# 縫い針（右へ、少し上向き。先はリボンの縁から外へ）
		var rot := -0.18
		var nd := PackedVector2Array([Vector2(-4, -2.4), Vector2(30, -1.4), Vector2(44, 0), Vector2(30, 1.4), Vector2(-4, 2.4), Vector2(-6, 0)])
		for k in nd.size():
			nd[k] *= u
		draw_colored_polygon(Icons.xf(nd, rot, eye + Vector2(1.2, 2.4) * u), Color(Icons.SHADOW, 0.35))
		draw_colored_polygon(Icons.xf(nd, rot, eye), Color(0.80, 0.82, 0.86))
		draw_line(eye + Vector2(-2, -1.0).rotated(rot) * u, eye + Vector2(36, -0.4).rotated(rot) * u, Color(1, 1, 1, 0.9), 1.0 * u, true)
		draw_colored_polygon(Icons.xf(Icons.ell(Vector2.ZERO, 2.8 * u, 0.9 * u, 10), rot, eye), Color(0.30, 0.32, 0.38))   # 針の穴

	## 持ち物の列: 素手と、手持ちの 6 マス（空いたマスは縫い目だけ）。かばんの物は装備の画面で。
	## マスは画面のまんなかにそろえ、財布はその右に足す（ボタンが増えてもマスは動かない）。紙の左右の余白はそろえる
	func _draw_bar(u: float, a: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var bag: Array = craft.bag(who)
		var held: int = craft.hands.get(who, -1)
		var cell := 58.0 * u   # 7 マスでも 1280×720 で左下の札・右下の刺繍枠とぶつからない大きさ
		var gap := 6.0 * u
		var n := Craft.HAND_SLOTS + 1
		var coins: int = craft.wallet(who) - ui._pending
		var cells_w := n * cell + (n - 1) * gap
		var focus: bool = ui._focus()
		var purse: bool = not focus and (coins > 0 or not ui._flies.is_empty())   # ボタンがなければ財布の場所を取らない（飛んでくるあいだは出す）
		var w := cells_w + (gap * 2.0 + _coins_w(coins, 9.0 * u) if purse else 0.0)
		var x0 := size.x / 2.0 - cells_w / 2.0
		var y := size.y - 20.0 * u - cell
		var off := Icons.tuck_off(Rect2(x0 - 56.0 * u, y - 60.0 * u, w + 68.0 * u, cell + 70.0 * u), size)   # 何もしないでいると画面の外へ（名前の札まで）
		x0 += off.x
		y += off.y
		Icons.screen()
		Icons.patch(self, Icons.rr(x0 - 12.0 * u, y - 10.0 * u, w + 24.0 * u, cell + 20.0 * u, 16.0 * u), Icons.PAPER, 0.85 * a, false)
		if craft.has_hand_items(who) and not focus:   # 持ち替えの案内: Z（と、ホイール・二本指スクロール）
			Icons.keycap(self, "Z", Vector2(x0 - 44.0 * u, y + cell * 0.32), 30.0 * u, a)
			Icons.icon(self, "mouse_wheel", Vector2(x0 - 44.0 * u, y + cell * 0.86), 34.0 * u, a)
		for i in n:
			var slot := i - 1
			var r := Rect2(x0 + i * (cell + gap), y, cell, cell)
			var on := slot == held
			var pop: float = ui._pop.get(slot, 0.0)
			if slot >= 0 and (slot >= bag.size() or bag[slot].is_empty()):   # 空いたマス: 縫い目だけ
				Icons.screen()
				Icons.dashes(self, Icons.rr(r.position.x + 4.0 * u, r.position.y + 4.0 * u, cell - 8.0 * u, cell - 8.0 * u, 9.0 * u), Icons.PAPER_EDGE, 2.0 * u, 5.0 * u, 4.0 * u, 0.9 * a, true)
				continue
			if on:
				r.position.y -= 8.0 * u
			Icons.screen()
			Icons.patch(self, Icons.rr(r.position.x, r.position.y, cell, cell, 10.0 * u), Icons.CAP, a, true, Icons.PAPER_EDGE)
			var c := r.get_center()
			var sz := cell * 0.82 * (1.0 + 0.3 * sin(pop * PI))
			if slot < 0:
				Icons.icon(self, "hand", c, sz * 0.8, a, Icons.RED)
			else:
				CraftIcons.item(self, bag[slot], c, sz, a)
			if on:
				Icons.screen()
				Icons.dashes(self, Icons.rr(r.position.x - 3.0 * u, r.position.y - 3.0 * u, cell + 6.0 * u, cell + 6.0 * u, 12.0 * u), Icons.RED, 2.4 * u, 6.0 * u, 3.5 * u, a, true)
				Icons.chevron(self, Vector2(c.x, r.position.y - 12.0 * u), 14.0 * u, Icons.RED, a, PI / 2, 2.6 * u)
		# 財布: ボタンを数だけ、山に積む
		if purse:
			_coins(x0 + cells_w + gap * 2.0, y + cell - 4.0 * u, coins, 9.0 * u * (1.0 + 0.25 * sin(ui._coin_pop * PI)), a)
		# 手に持っている物の名前: 持ち替えたとき、列のまんなかの上に紙の札で少しのあいだ（左下の札とぶつからない所）。
		# ゲームの中に文字を出さない決まりの例外（2026-11-01 代表「手に持ってる物の名前をインベントリHUDの上に小さく表示」）
		var it: Dictionary = craft.held(who)
		if not it.is_empty() and ui._name_t > 0.0:
			_name_tag(CraftIcons.item_name(it), Vector2(x0 + cells_w / 2.0, y - 18.0 * u), u, a * clampf(ui._name_t / 0.4, 0.0, 1.0))

	## 装備の画面の右下: 手持ち（上の段, 6 マス）と、かばん（下の段, 6 マス。口を紐で絞ったフェルトの巾着の上）。
	## 引きずって入れ替える。押すと、食べる・捨てるの小窓（_draw_inv_menu）
	func _draw_hand_and_bag(u: float, bag: Array, x0: float, y0: float) -> void:
		var cell := 72.0 * u
		var gap := 8.0 * u
		var row := cell + 6.0 * u
		var held: int = ui.craft.hands.get(ui._who(), -1)
		var from: int = ui._drag.get("from", -1) if ui._drag.get("moved", false) else -1
		var rects: Array = []
		for k in 2:
			var y := y0 + 26.0 * u + k * (row + 6.0 * u)
			var gx := x0 + 110.0 * u
			Icons.screen()
			if k == 1:
				var bw := Craft.HAND_SLOTS * cell + (Craft.HAND_SLOTS - 1) * gap + 20.0 * u
				Icons.patch(self, Icons.rr(gx - 10.0 * u, y - 6.0 * u, bw, cell + 12.0 * u, 14.0 * u), Color(0.30, 0.38, 0.30), 0.95, true, Icons.CAP)
				Icons.thread(self, PackedVector2Array([Vector2(gx - 4.0 * u, y - 6.0 * u), Vector2(gx + bw - 16.0 * u, y - 6.0 * u)]), Icons.WOOD, 3.0 * u, 1.0)
			Icons.icon(self, "hand" if k == 0 else "gear", Vector2(gx - 36.0 * u, y + cell / 2.0), 40.0 * u, 1.0)
			for i in Craft.HAND_SLOTS:
				var slot := k * Craft.HAND_SLOTS + i
				var r := Rect2(gx + i * (cell + gap), y, cell, cell)
				rects.append(r)
				var over: bool = from >= 0 and slot != from and r.has_point(ui._drag.at)
				Icons.screen()
				if slot >= bag.size() or bag[slot].is_empty() or slot == from:   # 空いたマス（引きずっている物の元の場所も）
					Icons.dashes(self, Icons.rr(r.position.x + 3.0 * u, r.position.y + 3.0 * u, cell - 6.0 * u, cell - 6.0 * u, 9.0 * u), Icons.RED if over else Icons.CAP, 2.0 * u, 5.0 * u, 4.0 * u, 1.0 if over else 0.6, true)
					continue
				Icons.patch(self, Icons.rr(r.position.x, r.position.y, cell, cell, 10.0 * u), Icons.CAP, 0.95, true, Icons.PAPER_EDGE)
				CraftIcons.item(self, bag[slot], r.get_center(), cell * 0.82, 1.0)
				if slot == held or over or slot == ui._inv_menu:
					Icons.screen()
					Icons.dashes(self, Icons.rr(r.position.x - 3.0 * u, r.position.y - 3.0 * u, cell + 6.0 * u, cell + 6.0 * u, 12.0 * u), Icons.RED, 2.4 * u, 6.0 * u, 3.5 * u, 1.0 if slot != held or over else 0.7, true)
		ui._inv_rects = rects
		_draw_inv_menu(u, bag)
		if from >= 0 and from < bag.size() and not bag[from].is_empty():   # 引きずっている物は、指の先に
			Icons.screen()
			Icons.patch(self, Icons.rr(ui._drag.at.x - cell / 2.0, ui._drag.at.y - cell / 2.0, cell, cell, 10.0 * u), Icons.CAP, 0.9, true, Icons.PAPER_EDGE)
			CraftIcons.item(self, bag[from], ui._drag.at, cell * 0.9, 1.0)

	## 押した持ち物の上の小窓: できあがった料理なら食べる、どれでも捨てる（編みかご）
	func _draw_inv_menu(u: float, bag: Array) -> void:
		ui._menu_rects = []
		var i: int = ui._inv_menu
		if i < 0 or i >= ui._inv_rects.size() or i >= bag.size() or bag[i].is_empty():
			return
		var acts: Array = (["eat"] if preload("res://food.gd").done(bag[i]) else []) + ["trash"]
		var bs := 56.0 * u
		var pad := 8.0 * u
		var cr: Rect2 = ui._inv_rects[i]
		var w := acts.size() * bs + (acts.size() + 1) * pad
		var h := bs + pad * 2.0
		var x := clampf(cr.get_center().x - w / 2.0, 8.0 * u, size.x - w - 8.0 * u)
		var y := cr.position.y - h - 10.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(x, y, w, h, 12.0 * u), Icons.PAPER, 1.0, true, Icons.PAPER_EDGE)
		Icons.patch(self, PackedVector2Array([Vector2(cr.get_center().x - 8.0 * u, y + h - 1.0), Vector2(cr.get_center().x + 8.0 * u, y + h - 1.0), Vector2(cr.get_center().x, y + h + 9.0 * u)]), Icons.PAPER, 1.0, false)
		for k in acts.size():
			var br := Rect2(x + pad + k * (bs + pad), y + pad, bs, bs)
			var hot := br.has_point(get_local_mouse_position())
			Icons.screen()
			Icons.patch(self, Icons.rr(br.position.x, br.position.y, bs, bs, 10.0 * u), Icons.CAP.darkened(0.06 if hot else 0.0), 1.0, true, Icons.RED if hot else Icons.PAPER_EDGE)
			Icons.icon(self, acts[k], br.get_center(), bs * (0.86 if hot else 0.8), 1.0)
			ui._menu_rects.append([br, acts[k]])

	## 名前の紙の札（下の縁のまんなかを at に）。字は藍の糸の刺繍の字
	func _name_tag(nm: String, at: Vector2, u: float, a: float) -> void:
		if nm == "" or a <= 0.01:
			return
		var fs := 18.0 * u
		var font: Font = Icons._bold_font()
		var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x
		var w := tw + 24.0 * u
		var h := fs + 14.0 * u
		var x := clampf(at.x - w / 2.0, 8.0 * u, size.x - w - 8.0 * u)
		Icons.screen()
		Icons.patch(self, Icons.rr(x, at.y - h, w, h, 6.0 * u), Icons.PAPER, a, true, Icons.PAPER_EDGE)
		Icons.stitched_text(self, nm, Vector2(x + 12.0 * u, at.y - h / 2.0), fs, Color(Icons.THREAD, a))

	## 財布のボタンを、左 x0・下 y から、段ごとの山に積んで描く（左から木・真鍮・白蝶貝・螺鈿。価値の低い順。どの段も 9 枚までなので 1 山。
	## 螺鈿だけは 10 枚ごとに山を足す）。木の山は 0 枚でも場所を取る（飛んでくるボタンの行き先）。
	## 段ごとの次の 1 枚が載る所を ui._tier_at に、木の山のそれを ui._wallet_at に入れる
	func _coins(x0: float, y: float, coins: int, cr: float, a: float) -> void:
		var sp := Craft.split(coins)
		var col := 0
		var dy := cr * 0.55
		var order: Array = Craft.MONEY.duplicate()
		order.reverse()   # 価値の低い順に左から
		for m in order:
			var look: String = m[1]
			var c: int = sp[look]
			if c == 0 and look != "wood":
				ui._tier_at[look] = Vector2(x0 + col * cr * 2.3 + cr, y - cr)
				continue
			for i in c + 1:
				var p := Vector2(x0 + (col + i / 10) * cr * 2.3 + cr, y - cr - (i % 10) * dy)
				if i == c:
					ui._tier_at[look] = p
					break
				Icons._o = p
				Icons._s = 1.0
				CraftIcons.money(self, Vector2.ZERO, cr, look, a, ui._shine_t + i * 0.7)
			col += maxi(1, ceili(c / 10.0))
		ui._wallet_at = ui._tier_at.get("wood", Vector2(x0, y))

	func _coins_w(coins: int, cr: float) -> float:
		var sp := Craft.split(coins)
		var cols := 0
		for m in Craft.MONEY:
			var c: int = sp[m[1]]
			if c > 0 or m[1] == "wood":
				cols += maxi(1, ceili(c / 10.0))
		return cols * cr * 2.3

	## 財布へ飛んでいるボタン: 取った所から弧を描いて財布の次の場所へ
	func _draw_flies(u: float) -> void:
		for f in ui._flies:
			if f.t < 0.0:
				continue
			var t: float = clampf(f.t, 0.0, 1.0)
			var e := t * t * (3.0 - 2.0 * t)
			var to: Vector2 = ui._tier_at.get(f.look, ui._wallet_at)
			var p: Vector2 = (f.from as Vector2).lerp(to, e) + Vector2(0, -sin(t * PI) * 110.0 * u)
			var r := lerpf(24.0, 12.0, e) * u * (1.0 + 0.25 * sin(minf(t * 4.0, 1.0) * PI))   # 出た瞬間にぽんとふくらむ
			Icons._o = p
			Icons._s = 1.0
			CraftIcons.money(self, Vector2.ZERO, r, f.look, 1.0, ui._shine_t)

	## 売り台
	func _draw_shop(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var coins: int = craft.wallet(who)
		var full: bool = craft.free_slot(who) < 0
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.36, 0.42, 0.33), 0.98, false)
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		var rects: Array = []
		var area_w := w * 0.74
		_draw_shop_tabs(u, r)
		for i in (ui._goods.size() if ui.shop_page == 0 else 0):
			var it: Dictionary = ui._goods[i]
			var pattern: bool = it.kind != "fabric"   # 上の段: 型紙と焚き火セット。下の段: 布
			var top_n: int = ui._goods.size() - Fabrics.ORDER.size()
			var idx: int = i if pattern else i - top_n
			var per: int = top_n if pattern else Fabrics.ORDER.size()
			var cw := (area_w - 40.0 * u) / per - 14.0 * u
			var ch := (250.0 if pattern else 200.0) * u
			var cx := r.position.x + 30.0 * u + idx * (cw + 14.0 * u)
			var cy := r.position.y + (40.0 if pattern else 320.0) * u
			var card := Rect2(cx, cy, cw, ch)
			var price := Craft.price(it)
			var can: bool = price <= coins and (not full or it.kind == "peg" and craft._peg_stack(who) >= 0)   # ペグは持っている束に足せる
			var sel: bool = ui._sel == i
			var hov: bool = ui._hover == i
			if sel or hov:
				card.position.y -= (8.0 if sel else 4.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 14.0 * u), Icons.CAP, 1.0 if can else 0.55, true, Icons.PAPER_EDGE)
			var a := 1.0 if can else 0.4
			var isz := minf(cw, ch * 0.7) * 0.92
			CraftIcons.item(self, it, card.position + Vector2(cw / 2.0, ch * 0.4), isz, a)
			CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch * 0.84), price, 11.0 * u, a)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 16.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		if ui.shop_page == 1:
			rects = _draw_stitch_shelf(u, r, area_w)
		ui._rects = rects
		# 右: 財布と買うボタン
		var rx := r.position.x + area_w + 20.0 * u
		var rw := w - area_w - 50.0 * u
		Icons.screen()
		Icons.patch(self, Icons.rr(rx, r.position.y + 40.0 * u, rw, 250.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
		var cr := 13.0 * u * (1.0 + 0.2 * sin(ui._coin_pop * PI))
		var ww := _coins_w(coins, cr)
		_coins(rx + rw / 2.0 - ww / 2.0, r.position.y + 250.0 * u, coins, cr, 1.0)
		if ui._sel >= 0:   # 選んだ品物の値段のぶんを、上に赤い糸で示す
			var need: int = ui.sel_price()
			var short := need > coins
			CraftIcons.price(self, Vector2(rx + rw / 2.0, r.position.y + 80.0 * u), need, 11.0 * u, 1.0, Icons.RED if short else CraftIcons.COIN)
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(rx + rw / 2.0 + shake, r.position.y + 420.0 * u)
		ui._buy_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var ready: bool = ui.sel_ready()
		var big := 1.06 if ui._hover_btn == "buy" else 1.0
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if ready else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		Icons._o = bc
		Icons._s = bs / 64.0 * big
		CraftIcons.coin(self, Vector2(-12, -2), 9.0, 1.0)
		Icons.arrow(self, Vector2(-1, -2), Vector2(9, -2), Icons.CAP, 1.0, 2.2)
		Icons.mitten(self, Vector2(17, 0), 0.4, Icons.CAP, 1.0, true, 0.9)
		# 右上: 閉じる（× の縫い目）
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)

	## 装備の画面の右上（閉じる × の下）: 持っている雪玉ころがしの手袋（gloves.gd）。押すとはめ、はめているのをもう一度押すと外す。
	## はめていると、しゃがんで F を押し続けて大玉を置け、大玉を押せる。持っていなければ、破線の空き札に薄い手袋（山師の棚で買うと入る）
	func _draw_gloves_row(u: float, r: Rect2) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var list: Array = craft.gear_list(who, "gloves")
		var on: int = craft.gear_index(who, "gloves")
		var gw := 92.0 * u
		var gh := 104.0 * u
		var gap := 10.0 * u
		var n := maxi(list.size(), 1)
		var y := r.position.y + 78.0 * u
		var x := r.end.x - 30.0 * u - n * gw - (n - 1) * gap
		var rects: Array = []
		if list.is_empty():
			Icons.screen()
			Icons.dashes(self, Icons.rr(x, y, gw, gh, 12.0 * u), Icons.CAP, 2.5 * u, 8.0 * u, 5.0 * u, 0.6, true)
			CraftIcons._at(Vector2(x + gw / 2.0, y + gh / 2.0), gw * 0.9)
			preload("res://gloves.gd").icon(self, "gloves", 0.3)
		for i in list.size():
			var card := Rect2(x + i * (gw + gap), y, gw, gh)
			var picked := i == on
			if picked or ui._glove_hover == i:
				card.position.y -= (8.0 if picked else 4.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, gw, gh, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			CraftIcons._at(card.get_center(), gw * 0.95)
			preload("res://gloves.gd").icon(self, String(list[i].get("grade", "gloves")), 1.0)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, gw + 8 * u, gh + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)
		ui._glove_rects = rects

	## 売り台の棚の札（左の上の外）。型紙の絵と、ジグザグの絵
	func _draw_shop_tabs(u: float, r: Rect2) -> void:
		var tabs: Array = []
		for k in 2:
			var on: bool = ui.shop_page == k
			var tw := 86.0 * u
			var th := 50.0 * u
			var tr := Rect2(r.position.x + 30.0 * u + k * (tw + 8.0 * u), r.position.y - th + (6.0 if on else 12.0) * u, tw, th)
			tabs.append(tr)
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, tw, th, 10.0 * u), Icons.CAP if on else Icons.PAPER_EDGE, 1.0, on, Icons.PAPER_EDGE)
			if k == 0:
				CraftIcons.item(self, {"kind": "pattern", "sled": "mid"}, tr.get_center() - Vector2(0, 2) * u, th * 0.8, 1.0 if on else 0.6)
			else:
				Stitches.draw_swatch(self, "cross", Rect2(tr.get_center() - Vector2(th, th) * 0.45, Vector2(th, th) * 0.9), Icons.RED, 1.0 if on else 0.6)
			if on:
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 2.0 * u, tr.position.y - 2.0 * u, tw + 4.0 * u, th + 4.0 * u, 11.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
		ui._tab_rects = tabs

	## 滑りあとの柄の棚: 7 列。安い順。雪の色の札に、柄と値段。買った柄は値段の代わりに赤い糸の印
	func _draw_stitch_shelf(u: float, r: Rect2, area_w: float) -> Array:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var coins: int = craft.wallet(who)
		var rects: Array = []
		var cols := 7
		var gap := 10.0 * u
		var cw := (area_w - 40.0 * u - gap * (cols - 1)) / cols
		var ch := 158.0 * u
		var names: Array = ui._stitch_goods
		for i in names.size():
			var nm: String = names[i]
			var card := Rect2(r.position.x + 30.0 * u + (i % cols) * (cw + gap), r.position.y + 34.0 * u + (i / cols) * (ch + gap), cw, ch)
			var sel: bool = ui._sel == i
			var hov: bool = ui._hover == i
			if sel or hov:
				card.position.y -= (6.0 if sel else 3.0) * u
			rects.append(card)
			var owned: bool = nm in craft.stitch_owned.get(who, [])
			var price: int = Stitches.price(nm)
			var can: bool = owned or price <= coins
			var a := 1.0 if can else 0.45
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u), Icons.CAP, 1.0 if can else 0.6, true, Icons.PAPER_EDGE)
			var snow := Rect2(card.position + Vector2(5.0, 5.0) * u, Vector2(cw - 10.0 * u, ch - 52.0 * u))
			draw_rect(snow, Color(0.82, 0.86, 0.94, a))
			Stitches.draw_swatch(self, nm, snow, Color("D2553A"), a)
			if owned:
				Icons.screen()
				Icons.icon(self, "needle", card.position + Vector2(cw / 2.0, ch - 24.0 * u), 26.0 * u, 1.0)
			else:
				CraftIcons.price(self, card.position + Vector2(cw / 2.0, ch - 24.0 * u), price, 8.0 * u, a)
			if sel:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 3 * u, card.position.y - 3 * u, cw + 6 * u, ch + 6 * u, 13.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		var named: int = ui._hover if ui._hover >= 0 and ui._hover < names.size() else ui._sel
		if named >= 0 and named < names.size():
			_name_tag(Stitches.ja(names[named]), Vector2(r.position.x + area_w / 2.0, r.end.y - 26.0 * u), u, 1.0)
		return rects

	## 装備の画面の、滑りあとの柄の棚（名札の 5 つ目のページ）。持っていない柄は薄く、木のボタンの印（ソリ屋で買う）
	func _draw_stitch_page(u: float, x: float, y: float, right: float, opts: Array) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var t: Array = ui.stitch_target()
		var names: Array = Stitches.standard() + Stitches.for_sale()
		var cols := 8
		var gap := 5.0 * u
		var cw := (right - x - gap * (cols - 1)) / cols
		var ch := 64.0 * u
		var named := -1
		for i in names.size():
			var nm: String = names[i]
			var sr := Rect2(x + (i % cols) * (cw + gap), y + (i / cols) * (ch + gap), cw, ch)
			var can: bool = craft.stitch_can_use(who, nm)
			Icons.screen()
			draw_rect(sr, Color(0.82, 0.86, 0.94, 1.0 if can else 0.35))
			Stitches.draw_swatch(self, nm, sr, _target_color(t), 1.0 if can else 0.35)
			if not can:
				var bc := Vector2(sr.end.x - 8.0 * u, sr.end.y - 8.0 * u)
				Icons.screen()
				draw_circle(bc, 6.5 * u, Icons.WOOD)
				draw_arc(bc, 4.8 * u, 0.0, TAU, 14, Icons.WOOD.darkened(0.3), 1.0 * u, true)
				draw_circle(bc + Vector2(-1.6, 0) * u, 1.0 * u, Color(0.25, 0.16, 0.10))
				draw_circle(bc + Vector2(1.6, 0) * u, 1.0 * u, Color(0.25, 0.16, 0.10))
			if nm == t[2]:
				Icons.screen()
				Icons.dashes(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 2.0 * u, sr.size.x + 4.0 * u, sr.size.y + 4.0 * u, 6.0 * u), Icons.RED, 2.6 * u, 5.0 * u, 3.0 * u, 1.0, true)
			if ui._opt_hover == opts.size():
				named = i
			opts.append([sr, "_stitch", nm])
		if named >= 0:
			_name_tag(Stitches.ja(names[named]), Vector2((x + right) / 2.0, y - 12.0 * u), u, 1.0)

	## 装備の画面の、大玉の縫い目の柄の棚（名札の 6 つ目のページ）。はじめが手袋の柄（段の標準）、続けて売っている柄。
	## 糸はいまはめている手袋の色（はめていなければ毛糸）。買っていない柄は薄く、木のボタンの印（山師の棚で買う）
	func _draw_ball_page(u: float, x: float, y: float, right: float, opts: Array) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var grade := _my_grade()
		var names: Array = [""] + BallStitches.for_sale()
		var mine: String = craft.ball_stitch_of(who)
		var cols := 6
		var gap := 6.0 * u
		var cw := (right - x - gap * (cols - 1)) / cols
		var ch := 66.0 * u
		for i in names.size():
			var nm: String = names[i]
			var sr := Rect2(x + (i % cols) * (cw + gap), y + (i / cols) * (ch + gap), cw, ch)
			var can: bool = craft.ball_can_use(who, nm)
			Icons.screen()
			Icons.patch(self, Icons.rr(sr.position.x, sr.position.y, sr.size.x, sr.size.y, 8.0 * u), Icons.CAP, 1.0 if can else 0.5, false)
			var bs := minf(sr.size.x, sr.size.y) * 0.96
			var br := Rect2(sr.get_center() - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
			BallStitches.draw_ball(self, BallStitches.pattern_of(nm, grade), grade, br, 1.0 if can else 0.4)
			if nm == "":   # 手袋の柄: 右下に小さな手袋
				Icons._o = sr.end - Vector2(12.0, 12.0) * u
				Icons._s = u * 0.32
				Gloves.icon(self, grade, 1.0)
			if not can:
				var bc := Vector2(sr.end.x - 8.0 * u, sr.end.y - 8.0 * u)
				Icons.screen()
				draw_circle(bc, 6.5 * u, Icons.WOOD)
				draw_arc(bc, 4.8 * u, 0.0, TAU, 14, Icons.WOOD.darkened(0.3), 1.0 * u, true)
				draw_circle(bc + Vector2(-1.6, 0) * u, 1.0 * u, Color(0.25, 0.16, 0.10))
				draw_circle(bc + Vector2(1.6, 0) * u, 1.0 * u, Color(0.25, 0.16, 0.10))
			if nm == mine:
				Icons.screen()
				Icons.dashes(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 2.0 * u, sr.size.x + 4.0 * u, sr.size.y + 4.0 * u, 8.0 * u), Icons.RED, 2.6 * u, 5.0 * u, 3.0 * u, 1.0, true)
			elif ui._opt_hover == opts.size():
				Icons.screen()
				Icons.dashes(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 2.0 * u, sr.size.x + 4.0 * u, sr.size.y + 4.0 * u, 8.0 * u), Icons.CAP, 2.0 * u, 5.0 * u, 3.0 * u, 0.8, true)
			opts.append([sr, "_ball", nm])

	## はめている手袋の段（はめていなければ毛糸）。大玉の柄の絵の糸の色と縫い合わせ
	func _my_grade() -> String:
		var g: String = ui.craft.glove_grade(ui._who())
		return g if g != "" else "gloves"

	## 柄を替えているソリの糸の色
	func _target_color(t: Array) -> Color:
		var look: Dictionary = t[1]
		if String(look.get("fabric", "")) != "":
			return Fabrics.color(look.fabric)
		return preload("res://sled.gd").KINDS.get(look.get("sled", "mid"), {}).get("color", Color("D2553A"))

	## ミシンの画面
	func _draw_machine(u: float) -> void:
		var craft: Node = ui.craft
		var bag: Array = craft.bag(ui._who())
		var w := 1040.0 * u
		var h := 600.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.20, 0.25, 0.46), 0.98, false)   # ミシンの紺のフェルト
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		# 上の段: 型紙の枠 ＋ 布の枠 → できるソリ、縫うボタン
		var cw := 190.0 * u
		var ch := 230.0 * u
		var top := r.position.y + 40.0 * u
		var shop_ic := Vector2.ZERO
		var slots := {}
		for k in 2:
			var kind: String = ["pattern", "fabric"][k]
			var cr := Rect2(r.position.x + 40.0 * u + k * (cw + 70.0 * u), top, cw, ch)
			slots[kind] = cr
			var i: int = ui._pick[kind]
			Icons.screen()
			if i >= 0 and i < bag.size():
				Icons.patch(self, Icons.rr(cr.position.x, cr.position.y, cw, ch, 14.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
				CraftIcons.item(self, bag[i], cr.get_center(), cw * 0.8, 1.0)
			else:
				# 空き枠: 破線と薄い絵。持ち物に無ければ、おじさん（売り台）を指す矢印
				Icons.dashes(self, Icons.rr(cr.position.x, cr.position.y, cw, ch, 14.0 * u), Icons.CAP, 3.0 * u, 9.0 * u, 6.0 * u, 0.9, true)
				CraftIcons.item(self, {"kind": kind, "sled": "mid", "fabric": "cream"}, cr.get_center(), cw * 0.7, 0.25)
				var have := false
				for it in bag:
					have = have or it.kind == kind
				if not have:
					var ic := Vector2(cr.get_center().x, cr.end.y + 84.0 * u)
					Icons._o = Vector2.ZERO
					Icons._s = 1.0
					Icons.arrow(self, Vector2(cr.get_center().x, cr.end.y + 6.0 * u), ic - Vector2(0, 46.0 * u), Icons.MUSTARD, 1.0, 4.0 * u)
					Icons.patch(self, Icons.circ(ic, 44.0 * u, 24), Icons.PAPER, 1.0, true, Icons.PAPER_EDGE)
					Icons.icon(self, "shopkeeper", ic + Vector2(-12.0 * u, 0), 62.0 * u, 1.0)
					Icons.icon(self, "shop", ic + Vector2(20.0 * u, 8.0 * u), 40.0 * u, 1.0)
					shop_ic = ic
			if k == 0:   # ＋ の縫い目
				var pc := Vector2(cr.end.x + 35.0 * u, cr.get_center().y)
				Icons._o = pc
				Icons._s = u
				Icons.thread(self, PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]), Icons.CAP, 4.0, 1.0)
				Icons.thread(self, PackedVector2Array([Vector2(0, -14), Vector2(0, 14)]), Icons.CAP, 4.0, 1.0)
		ui._slot_rects = slots
		# できるソリ: 型紙と布がそろうと、広げた姿が布の色でくるくる回る
		var res := Rect2((slots["fabric"] as Rect2).end.x + 70.0 * u, top, 230.0 * u, ch)
		Icons.screen()
		Icons.chevron(self, Vector2(res.position.x - 36.0 * u, res.get_center().y), 26.0 * u, Icons.CAP, 1.0, 0.0, 4.0 * u)
		var ps: int = ui._pick.pattern
		var fs: int = ui._pick.fabric
		var ready := ps >= 0 and fs >= 0 and ps < bag.size() and fs < bag.size()
		if ready:
			Icons.patch(self, Icons.rr(res.position.x, res.position.y, res.size.x, res.size.y, 14.0 * u), Color(0.86, 0.90, 0.97), 1.0, true, Icons.PAPER_EDGE)
			var tw := res.size.x * 0.92
			draw_texture_rect(preload("res://sled_tags.gd").turntable(bag[ps].sled, bag[fs].fabric),
					Rect2(res.get_center() - Vector2(tw, tw) / 2.0, Vector2(tw, tw)), false)
		else:
			Icons.dashes(self, Icons.rr(res.position.x, res.position.y, res.size.x, res.size.y, 14.0 * u), Icons.CAP, 3.0 * u, 9.0 * u, 6.0 * u, 0.5, true)
		# 縫うボタン（針と赤い糸）
		var shake: float = sin(ui._shake * 40.0) * 10.0 * u * ui._shake
		var bs := 150.0 * u
		var bc := Vector2(r.end.x - 40.0 * u - bs / 2.0 + shake, res.get_center().y)
		ui._sew_rect = Rect2(bc - Vector2(bs, bs) / 2.0, Vector2(bs, bs))
		var big := 1.06 if ui._hover_btn == "sew" else 1.0
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, bs * 0.5 * big, 28), Icons.RED if ready else Icons.RED.lerp(Icons.PAPER_EDGE, 0.6), 1.0, true, Icons.CAP)
		Icons.patch(self, Icons.circ(bc, bs * 0.36 * big, 24), Icons.CAP, 1.0, false)
		Icons.icon(self, "needle", bc, bs * 0.62 * big, 1.0)
		# 下の 2 段: 自分の持ち物（上が手持ち、下がかばん。どちらの型紙・布でも縫える）
		var rects: Array = []
		var bw := 84.0 * u
		var bh := 84.0 * u
		var x0 := r.position.x + 90.0 * u
		var by0 := r.end.y - 34.0 * u - 2.0 * bh - 12.0 * u
		for k in 2:
			Icons.screen()
			Icons.icon(self, "hand" if k == 0 else "gear", Vector2(x0 - 40.0 * u, by0 + k * (bh + 12.0 * u) + bh / 2.0), 38.0 * u, 1.0)
		for i in bag.size():
			var it: Dictionary = bag[i]
			var col := i % Craft.HAND_SLOTS
			var by := by0 + (i / Craft.HAND_SLOTS) * (bh + 12.0 * u)
			if it.is_empty():
				rects.append(Rect2())
				Icons.screen()
				Icons.dashes(self, Icons.rr(x0 + col * (bw + 12.0 * u) + 3.0 * u, by + 3.0 * u, bw - 6.0 * u, bh - 6.0 * u, 10.0 * u), Icons.CAP, 2.0 * u, 5.0 * u, 4.0 * u, 0.45, true)
				continue
			var usable: bool = it.kind in ["pattern", "fabric"]
			var picked: bool = ui._pick.get(it.kind, -1) == i
			var card := Rect2(x0 + col * (bw + 12.0 * u), by - (6.0 * u if picked else (3.0 * u if ui._hover == i else 0.0)), bw, bh)
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, bw, card.size.y, 12.0 * u), Icons.CAP, 1.0 if usable else 0.55, true, Icons.PAPER_EDGE)
			CraftIcons.item(self, it, card.get_center(), bw * 0.82, 1.0 if usable else 0.35)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, bw + 8 * u, card.size.y + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
		ui._bag_rects = rects
		# 右上: 閉じる
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)

	## どの名札を替えるかの札の列: いつもの柄（針の印。これから縫うソリに付く）・自分のソリ（回る姿）・畳んだソリ（包み）・
	## 名札入れの外した名札。どれも下に小さく、その名札。替えている札に赤い糸の印
	func _draw_edit_row(u: float, r: Rect2) -> void:
		var Tags := preload("res://sled_tags.gd")
		var stitch_page: bool = ui.tag_page == Tags.PAGES.size()
		var list: Array = ui.stitch_targets() if stitch_page else ui.edit_targets()
		var gap := 6.0 * u
		var cw := minf(62.0 * u, (r.size.x - gap * (list.size() - 1)) / maxf(list.size(), 1))
		var rects: Array = []
		for i in list.size():
			var key: Dictionary = list[i][0]
			var look: Dictionary = list[i][1] if stitch_page else list[i][2]
			var card := Rect2(r.position.x + i * (cw + gap), r.position.y, cw, r.size.y)
			var picked: bool = key == (ui.stitch_target()[0] if stitch_page else ui.tag_edit)
			if picked:
				card.position.y -= 6.0 * u
			rects.append([card, key])
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, card.size.y, 9.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var top := Rect2(card.position + Vector2(2.0, 2.0) * u, Vector2(cw - 4.0 * u, card.size.y * 0.58))
			if look.has("sled"):   # 自分のソリ・畳んだソリ: 広げた姿がくるくる回る（畳んだソリは包みの色の角を付ける）
				var tw := minf(top.size.x, top.size.y * 1.3)
				draw_texture_rect(Tags.turntable(look.sled, look.get("fabric", "")), Rect2(top.get_center() - Vector2(tw, tw) / 2.0, Vector2(tw, tw)), false)
				if look.get("folded", false):
					Icons.screen()
					Icons.patch(self, Icons.xf(Icons.rr(-5, -5, 10, 10, 2), PI / 4, top.position + Vector2(9, 9) * u, u), preload("res://fabrics.gd").color(look.get("fabric", "red")), 1.0, false)
			elif look.has("loose"):   # 名札入れ: 名札だけ（下に大きめに）
				pass
			else:   # いつもの柄: 針の印（これから縫うソリ）
				Icons.icon(self, "needle", top.get_center(), top.size.y * 1.05, 1.0)
			var th := card.size.y * (0.62 if look.has("loose") else 0.34)
			if stitch_page:   # 下に、そのソリのいまの柄
				var sn := Rect2(card.position.x + 4.0 * u, card.end.y - th - 4.0 * u, cw - 8.0 * u, th)
				draw_rect(sn, Color(0.82, 0.86, 0.94))
				Stitches.draw_swatch(self, list[i][2], sn, _target_color(list[i]))
			else:
				Tags.draw_tag(self, Rect2(card.position.x + 4.0 * u, card.end.y - th - 4.0 * u, cw - 8.0 * u, th), list[i][1], 1.0, false)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 3 * u, card.position.y - 3 * u, cw + 6 * u, card.size.y + 6 * u, 11.0 * u), Icons.RED, 2.6 * u, 6.0 * u, 3.5 * u, 1.0, true)
		ui._edit_rects = rects

	## 装備の画面
	func _draw_gear_screen(u: float) -> void:
		var craft: Node = ui.craft
		var who: int = ui._who()
		var w := 1040.0 * u
		var h := 690.0 * u
		var r := Rect2(size.x / 2.0 - w / 2.0, size.y * 0.44 - h / 2.0, w, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.08, 0.16, 0.25))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 22.0 * u), Color(0.42, 0.30, 0.22), 0.98, false)   # 革の色のフェルト
		Icons.dashes(self, Icons.rr(r.position.x + 10 * u, r.position.y + 10 * u, w - 20 * u, h - 20 * u, 16.0 * u), Icons.CAP, 2.0 * u, 8.0 * u, 5.0 * u, 0.8, true)
		var Tags := preload("res://sled_tags.gd")
		var list: Array = craft.gear_list(who, "sack")
		var on: int = craft.gear_index(who, "sack")
		# 左: 装備している米袋。帯に下げ、広げた姿がくるくる回る
		var lw := 280.0 * u
		var lr := Rect2(r.position.x + 30.0 * u, r.position.y + 40.0 * u, lw, h - 80.0 * u)
		Icons.patch(self, Icons.rr(lr.position.x, lr.position.y, lw, lr.size.y, 16.0 * u), Icons.PAPER, 0.96, true, Icons.PAPER_EDGE)
		# 左の上: 自分の名前（打って替える）とキャラの色（押して選ぶ）。左に、その色の人の形
		var mycol: Color = craft.color_of(who)
		PersonIcon.draw(self, Vector2(lr.position.x + 30.0 * u, lr.position.y + 50.0 * u), 36.0 * u, mycol)
		ui._name_rect = Rect2(lr.position.x + 52.0 * u, lr.position.y + 16.0 * u, lw - 66.0 * u, 34.0 * u)
		var crects: Array = []
		var cs := (lw - 28.0 * u) / Craft.COLORS.size()
		for i in Craft.COLORS.size():
			var cc := Vector2(lr.position.x + 14.0 * u + cs * (i + 0.5), lr.position.y + 70.0 * u)
			draw_circle(cc, cs * 0.40, Craft.COLORS[i])
			draw_arc(cc, cs * 0.40, 0.0, TAU, 18, Craft.COLORS[i].darkened(0.4), 1.2 * u, true)
			if i == int(craft.colors.get(who, -1)):
				Icons.screen()
				Icons.dashes(self, Icons.circ(cc, cs * 0.52, 18), Icons.RED, 2.0 * u, 3.5 * u, 2.5 * u, 1.0, true)
			crects.append([Rect2(cc - Vector2(cs, cs) / 2.0, Vector2(cs, cs)), i])
		ui._color_rects = crects
		Icons.screen()
		Icons.thread(self, PackedVector2Array([Vector2(lr.position.x + 18.0 * u, lr.position.y + 88.0 * u), Vector2(lr.end.x - 18.0 * u, lr.position.y + 88.0 * u)]), Icons.PAPER_EDGE, 1.5 * u, 0.8)
		var py := 84.0 * u   # 名前と色の分だけ、帯から下を下げる
		Icons.patch(self, Icons.rr(lr.position.x + 14.0 * u, lr.position.y + py + 24.0 * u, lw - 28.0 * u, 16.0 * u, 6.0 * u), Icons.WOOD.darkened(0.2), 1.0, true, Icons.CAP)   # 帯
		var lamps: Array = craft.gear_list(who, "lantern")
		var lamp_on: int = craft.gear_index(who, "lantern")
		if on >= 0 and on < list.size():   # 帯の右に米袋、左にランタンを下げる（人形と同じ側）
			var spec: Dictionary = list[on]
			CraftIcons._at(Vector2(lr.position.x + lw * 0.7, lr.position.y + py + 82.0 * u), 64.0 * u * 1.3)
			Icons.thread(self, PackedVector2Array([Vector2(0, -36), Vector2(0, -22)]), Icons.WOOD, 2.0, 1.0)
			CraftIcons.rice_sack(self, Vector2.ZERO, 1.0, CraftIcons.sack_body(spec), CraftIcons.sack_band(spec), 1.0)
			var tw := lw * 0.6
			draw_texture_rect(Tags.turntable("sack", spec.get("fabric", "")), Rect2(Vector2(lr.position.x + lw * 0.62 - tw / 2.0, lr.position.y + py + 128.0 * u), Vector2(tw, tw)), false)
			Icons.keycap(self, "N", Vector2(lr.position.x + 36.0 * u, lr.position.y + py + 214.0 * u), 30.0 * u, 1.0)
		if lamp_on >= 0 and lamp_on < lamps.size():
			CraftIcons._at(Vector2(lr.position.x + lw * 0.28, lr.position.y + py + 84.0 * u), 64.0 * u * 1.3)
			Icons.thread(self, PackedVector2Array([Vector2(0, -36), Vector2(0, -28)]), Icons.WOOD, 2.0, 1.0)
			CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamps[lamp_on].get("look", "box"), craft.lamp_on(who), 1.0)
		# 左の下: 持っているランタン。押すと提げ替え、提げているのをもう一度押すと外す（R で点ける・消す）
		var lrects: Array = []
		# 札は 2 枚なら大きく、ランタン掛けで買い足して増えたら列を増やして小さくする（10 枚で 5 列 2 段）
		var lcols := clampi(ceili(lamps.size() / 2.0), 2, 5)
		var lrows := maxi(1, ceili(lamps.size() / float(lcols)))
		var lgap := (12.0 if lcols == 2 else 6.0) * u
		var lcw := minf(104.0 * u, (lw - 48.0 * u - (lcols - 1) * lgap) / lcols)
		var lch := minf(minf(128.0 * u, lcw * 1.23), (150.0 * u - (lrows - 1) * lgap) / lrows)
		var ly := lr.position.y + py + 316.0 * u
		var lx := lr.position.x + (lw - lcols * lcw - (lcols - 1) * lgap) / 2.0
		Icons.screen()
		Icons.thread(self, PackedVector2Array([Vector2(lr.position.x + 18.0 * u, ly - 18.0 * u), Vector2(lr.end.x - 18.0 * u, ly - 18.0 * u)]), Icons.PAPER_EDGE, 1.5 * u, 0.8)
		for i in lamps.size():
			var card := Rect2(lx + (i % lcols) * (lcw + lgap), ly + (i / lcols) * (lch + lgap), lcw, lch)
			var picked := i == lamp_on
			if picked or ui._lamp_hover == i:
				card.position.y -= (8.0 if picked else 4.0) * u
			lrects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, lcw, lch, minf(12.0 * u, lcw * 0.12)), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			CraftIcons._at(card.get_center(), minf(lcw, lch * 0.8) * 0.95)
			CraftIcons.lantern(self, Vector2.ZERO, 1.0, lamps[i].get("look", "box"), picked and craft.lamp_on(who), 1.0)
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, lcw + 8 * u, lch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)
		ui._lamp_rects = lrects
		Icons.keycap(self, "R", Vector2(lr.get_center().x, lr.end.y - 30.0 * u), 30.0 * u, 1.0)
		# 右上: 持っている米袋
		var x0 := lr.end.x + 30.0 * u
		var cw := 128.0 * u
		var ch := 150.0 * u
		var rects: Array = []
		Icons.screen()
		Icons.icon(self, "sack", Vector2(x0 + 26.0 * u, r.position.y + 60.0 * u), 44.0 * u, 1.0)   # 段の印: 米袋
		for i in list.size():
			var spec: Dictionary = list[i]
			var col := i % 5
			var row := i / 5
			var card := Rect2(x0 + 56.0 * u + col * (cw + 12.0 * u), r.position.y + 40.0 * u + row * (ch + 12.0 * u), cw, ch)
			var picked := i == on
			if picked or ui._hover == i:
				card.position.y -= (8.0 if picked else 4.0) * u
			rects.append(card)
			Icons.screen()
			Icons.patch(self, Icons.rr(card.position.x, card.position.y, cw, ch, 12.0 * u), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var tw := cw * 0.98
			draw_texture_rect(Tags.turntable("sack", spec.get("fabric", "")), Rect2(Vector2(card.get_center().x - tw / 2.0, card.get_center().y - tw / 2.0), Vector2(tw, tw)), false)   # 米袋に名札は付けない
			if picked:
				Icons.screen()
				Icons.dashes(self, Icons.rr(card.position.x - 4 * u, card.position.y - 4 * u, cw + 8 * u, ch + 8 * u, 14.0 * u), Icons.RED, 3.0 * u, 7.0 * u, 4.0 * u, 1.0, true)
				Icons.chevron(self, Vector2(card.get_center().x, card.position.y - 14.0 * u), 18.0 * u, Icons.RED, 1.0, PI / 2, 3.0 * u)
		ui._gear_rects = rects
		_draw_gloves_row(u, r)
		# まんなか: 替えている名札（左に大きく）と、部品の見本（押すと替わる）。部品は 4 ページ（形と素材・模様・縁と糸・飾りと判子）。
		# 名札の下に、どの名札を替えるかの札の列（いつもの柄・自分のソリ・畳んだソリ・名札入れ）
		var mine: Dictionary = ui.edit_design()
		var ty := r.position.y + 218.0 * u
		var stitch_page: bool = ui.tag_page == Tags.PAGES.size()
		var ball_page: bool = ui.tag_page == ui.ball_page()
		if ball_page:   # 自分の大玉の柄を大きく（はめている手袋の段で）
			var big_r := Rect2(x0 + 50.0 * u, ty + 20.0 * u, 210.0 * u, 190.0 * u)
			var g := _my_grade()
			BallStitches.draw_ball(self, BallStitches.pattern_of(craft.ball_stitch_of(who), g), g, big_r)
		elif stitch_page:   # 替えているソリの柄を大きく
			var big_r := Rect2(x0 + 50.0 * u, ty + 26.0 * u, 210.0 * u, 170.0 * u)
			var tgt: Array = ui.stitch_target()
			draw_rect(big_r, Color(0.82, 0.86, 0.94))
			Stitches.draw_swatch(self, tgt[2], big_r, _target_color(tgt))
			_name_tag(Stitches.ja(tgt[2]), Vector2(big_r.get_center().x, big_r.position.y + 2.0 * u), u, 1.0)
		else:
			Tags.draw_tag(self, Rect2(x0 + 50.0 * u, ty + 26.0 * u, 210.0 * u, 128.0 * u), mine, 1.0, true)
		var opts: Array = []
		var ox := x0 + 286.0 * u
		var sw := 25.0 * u
		# おまかせ（さいころ）: 名札の下
		var dc := Vector2(x0 + 155.0 * u, (ty + 196.0 * u) if not stitch_page and not ball_page else -1000.0)
		var ds := 40.0 * u * (1.08 if ui._opt_hover >= 0 and ui._opt_hover < ui._opt_rects.size() and ui._opt_rects[ui._opt_hover][1] == "_dice" else 1.0)
		Icons.screen()
		Icons.patch(self, Icons.rr(dc.x - ds / 2.0, dc.y - ds / 2.0, ds, ds, ds * 0.22), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
		for q in [Vector2(-1, -1), Vector2(1, 1), Vector2(0, 0), Vector2(1, -1), Vector2(-1, 1)]:
			draw_circle(dc + q * ds * 0.24, ds * 0.08, Icons.RED)
		opts.append([Rect2(dc - Vector2(ds, ds) / 2.0, Vector2(ds, ds)), "_dice", 0])
		# ページの札
		var page: int = clampi(ui.tag_page, 0, ui.ball_page())
		var looks := [["shape", int(mine.get("shape", 0))], ["pattern", maxi(int(mine.get("pattern", 0)), 3) if int(mine.get("pattern", 0)) == 0 else int(mine.get("pattern", 0))],
			["stitch", 3 if int(mine.get("stitch", 0)) == 1 else int(mine.get("stitch", 0))], ["motif", 2 if int(mine.get("motif", 0)) == 0 else int(mine.get("motif", 0))]]
		for k in Tags.PAGES.size():
			var tr := Rect2(ox + k * 54.0 * u, ty - (6.0 * u if k == page else 0.0), 48.0 * u, 38.0 * u)
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, tr.size.x, tr.size.y, 9.0 * u), Icons.CAP if k == page else Icons.PAPER_EDGE, 1.0 if k == page else 0.75, k == page, Icons.PAPER_EDGE)
			Tags.swatch(self, looks[k][0], looks[k][1], tr.get_center(), 26.0 * u, mine, 1.0 if k == page else 0.6)
			if k == page:
				Icons.screen()
				Icons.dashes(self, Icons.rr(tr.position.x - 2.0 * u, tr.position.y - 2.0 * u, tr.size.x + 4.0 * u, tr.size.y + 4.0 * u, 10.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
			opts.append([tr, "_page", k])
		# 5 つ目の札: 滑りあとの柄
		var str_r := Rect2(ox + Tags.PAGES.size() * 54.0 * u, ty - (6.0 * u if stitch_page else 0.0), 48.0 * u, 38.0 * u)
		Icons.screen()
		Icons.patch(self, Icons.rr(str_r.position.x, str_r.position.y, str_r.size.x, str_r.size.y, 9.0 * u), Icons.CAP if stitch_page else Icons.PAPER_EDGE, 1.0 if stitch_page else 0.75, stitch_page, Icons.PAPER_EDGE)
		Stitches.draw_swatch(self, "cross", str_r.grow(-3.0 * u), Icons.RED, 1.0 if stitch_page else 0.6)
		if stitch_page:
			Icons.screen()
			Icons.dashes(self, Icons.rr(str_r.position.x - 2.0 * u, str_r.position.y - 2.0 * u, str_r.size.x + 4.0 * u, str_r.size.y + 4.0 * u, 10.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
		opts.append([str_r, "_page", Tags.PAGES.size()])
		# 6 つ目の札: 大玉の縫い目の柄（菊かがりの玉）
		var bal_r := Rect2(ox + ui.ball_page() * 54.0 * u, ty - (6.0 * u if ball_page else 0.0), 48.0 * u, 38.0 * u)
		Icons.screen()
		Icons.patch(self, Icons.rr(bal_r.position.x, bal_r.position.y, bal_r.size.x, bal_r.size.y, 9.0 * u), Icons.CAP if ball_page else Icons.PAPER_EDGE, 1.0 if ball_page else 0.75, ball_page, Icons.PAPER_EDGE)
		BallStitches.draw_ball(self, "kiku", _my_grade(), bal_r.grow(-2.0 * u), 1.0 if ball_page else 0.6)
		if ball_page:
			Icons.screen()
			Icons.dashes(self, Icons.rr(bal_r.position.x - 2.0 * u, bal_r.position.y - 2.0 * u, bal_r.size.x + 4.0 * u, bal_r.size.y + 4.0 * u, 10.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
		opts.append([bal_r, "_page", ui.ball_page()])
		# 部品の見本。まだ手に入れていない部品は薄く、木のボタンの印（あとで手に入る）
		var per := maxi(1, int((r.end.x - 26.0 * u - ox) / (sw + 5.0 * u)))
		var oy := ty + 50.0 * u
		if stitch_page:
			_draw_stitch_page(u, ox, oy, r.end.x - 26.0 * u, opts)
		elif ball_page:
			_draw_ball_page(u, ox, oy, r.end.x - 26.0 * u, opts)
		for part in ([] if stitch_page or ball_page else Tags.PAGES[page]):
			var n := Tags.part_count(part)
			for i in n:
				var sr := Rect2(ox + (i % per) * (sw + 5.0 * u), oy + (i / per) * (sw + 9.0 * u), sw + 2.0 * u, sw + 6.0 * u)
				var c := sr.get_center()
				var can: bool = craft.tag_can_use(who, part, i)
				if ui._opt_hover == opts.size():
					Icons.screen()
					Icons.patch(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 1.0 * u, sr.size.x + 4.0 * u, sr.size.y + 2.0 * u, 6.0 * u), Icons.CAP, 0.7, false)
				Tags.swatch(self, part, i, c, sw, mine, 1.0 if can else 0.35)
				if not can:
					var bc := Vector2(sr.end.x - 3.0 * u, sr.end.y - 4.0 * u)
					Icons.screen()
					draw_circle(bc, 5.5 * u, Icons.WOOD)
					draw_arc(bc, 4.0 * u, 0.0, TAU, 14, Icons.WOOD.darkened(0.3), 1.0 * u, true)
					draw_circle(bc + Vector2(-1.4, 0) * u, 0.9 * u, Color(0.25, 0.16, 0.10))
					draw_circle(bc + Vector2(1.4, 0) * u, 0.9 * u, Color(0.25, 0.16, 0.10))
				if int(mine.get(part, -1)) == i:
					Icons.screen()
					Icons.dashes(self, Icons.rr(sr.position.x - 2.0 * u, sr.position.y - 1.0 * u, sr.size.x + 4.0 * u, sr.size.y + 2.0 * u, 6.0 * u), Icons.RED, 2.4 * u, 5.0 * u, 3.0 * u, 1.0, true)
				opts.append([sr, part, i])
			oy += ceili(float(n) / per) * (sw + 9.0 * u) + 8.0 * u
		ui._opt_rects = opts
		if ball_page:   # 大玉の柄は人ごと（替えるソリを選ぶ札はない）
			ui._edit_rects = []
		else:
			_draw_edit_row(u, Rect2(x0, ty + 226.0 * u, 272.0 * u, 76.0 * u))
		# 右下: 手持ちとかばん（引きずって入れ替える。押すと食べる・捨てる）
		_draw_hand_and_bag(u, craft.bag(who), x0 + 4.0 * u, r.end.y - 30.0 * u - 2 * 82.0 * u - 10.0 * u)
		# 右上: 閉じる
		var xs := 46.0 * u
		var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
		ui._close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
		Icons.screen()
		Icons.patch(self, Icons.circ(xc, xs * 0.5 * (1.08 if ui._hover_btn == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
		Icons._o = xc
		Icons._s = xs / 64.0
		Icons.thread(self, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
		Icons.thread(self, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)
