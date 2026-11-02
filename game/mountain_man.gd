extends Node3D
## 山の道具（焚き火セット・ペグ）を売る山男（2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」）。
## 姿はラフの C「狼の毛皮の山男」（person/ideas/yamaotoko。代表が 3 案から選んだ。ボードの白い和紙の狼と、折り紙の着物の人から）:
## 藍の和紙を折った長い上着、クリームの紙の衿を左前に重ね、赤い毛糸の帯。白い和紙の狼の頭を頭巾にかぶり、毛皮を背中へ垂らし、
## 前足の毛皮を肩から胸へ。顔は折り紙の多面体に、黒い糸の閉じた目。
## 形は人形と同じ作り（2026-11-02 代表「山師がアートコンセプトに沿ってない気がする。キャラの要素は良いんだけど」）:
## person/ideas/yamaotoko/roughs.py --export で、紙と糸の素材で組み、骨を入れ、色と凹凸とくぼみの陰を焼いた game/person/yamaotoko.glb。
## 上着は青海波を刷った藍の和紙（裏と縁は白）、裾・衿・頭巾の縁に生成りの糸のなみ縫い、帯は前で結んで垂らす。足もとに青いやわらかい影
## 置き場所はロッジの 1 階の、大きなミシンの奥（main.gd の MOUNTAIN_MAN）。
## 後ろに伏せて休む白いヤク、横（rack_side の側）に品物を積んだソリの屋台、その先に山師が育てているミニオンの柵と遊び場
## （ミニオンも山師から買う。売り場の「連れ」の札）。どれも焼いた glb（下の SET）。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   息をするように体がわずかにふくらむ。ときどき見回す
##   気づく 人が近づくと顔を向け、左手を挙げて小さく振る。近くに何人かいれば、いちばん近い人を見る（オンラインのほかの人も）
##   売る   売り場（mountain_ui.gd）が開くと、棚の側の手で棚を示す。だれかが買うと（ほかの人の買い物でも）その人を向いてうなずき、手を差し出す
## F で話しかける（player.gd の mountain_near）。

const Doll := preload("res://doll.gd")
const Goods := preload("res://mountain_goods.gd")
const Pals := preload("res://pals.gd")

const MODEL := "res://person/yamaotoko.glb"
const SCALE := 1.3           # ラフ（1.33 m）から、ゲームの人と並ぶ大きさへ（おじいさんと同じくらい）
const FOOT_SHADOW := 0.42    # 足もとの影の半径（ラフの大きさのまま。人形の FOOT_SHADOW と同じ考え）
const NOTICE_R := 4.0        # この距離に人が来ると気づく (m)
const TALK_R := 2.4          # F で話しかけられる距離 (m)
## 山師のまわり（2026-11-02 代表「山師の後ろにこういう白いヤク置いてほしい」「棚スカスカすぎだし素っ気なさすぎ」
## 「動物たちの柵と遊び場みたいなのも狭すぎ小さすぎ」。person/ideas/yamaotoko/corner.py で組んで焼いた glb。どれも山師の座標で作ってある）:
##   ヤク     後ろで伏せて休む白いヤク（毛糸の房の毛、フェルトの角、赤い鞍掛けと鐙）
##   出店     左手のソリの屋台（代表が「背負子と茣蓙」と比べて選んだ）: 赤いフェルトを敷いたソリの台、赤と生成りの縞の日よけ、
##            焚き火セット・桶に立てたペグ・縄の輪・かんじき・提灯
##   柵       出店の先の、ミニオンの柵と遊び場（4 × 3.2 m）: 敷物 2 枚、フェルトのトンネル、切り株と坂、毛糸玉、薪かごの寝床、水桶と餌の器。
##            入口は客の側。中にも入れる（当たりは柵だけ）
const SET := ["res://person/yama_yak.glb", "res://person/yama_stall.glb", "res://person/yama_pen.glb"]
const SET_SCALE := 1.15      # 組んだ寸法（山師 1.33 m）から。山師ほど大きくはせず、柵が西の壁に届かない大きさ
## 当たり（組んだ寸法の、山師の座標。前は -Z、左手は -X）: [大きさ, まんなか]
const SET_BOXES := [
	[Vector3(2.0, 0.9, 1.1), Vector3(0.35, 0.45, 1.8)],     # ヤク（体は左右＝南北に長い）
	[Vector3(2.5, 1.2, 1.2), Vector3(-1.8, 0.6, -0.05)],    # 出店
	[Vector3(4.0, 0.62, 0.08), Vector3(-5.3, 0.31, 2.7)],   # 柵の奥（西）
	[Vector3(0.08, 0.62, 3.2), Vector3(-7.3, 0.31, 1.1)],   # 柵の北
	[Vector3(0.08, 0.62, 3.2), Vector3(-3.3, 0.31, 1.1)],   # 柵の南（出店の側）
	[Vector3(1.6, 0.62, 0.08), Vector3(-6.5, 0.31, -0.5)],  # 柵の前（入口の北）
	[Vector3(1.6, 0.62, 0.08), Vector3(-4.1, 0.31, -0.5)],  # 柵の前（入口の南）
]
## 柵の中のミニオン: [名前, 所（組んだ寸法の、山師の座標）, 向き, 姿]。売り物から。子狐はかごの寝床で寝ている
const PEN_PETS := [["kit", Vector3(-6.7, 0.16, 0.15), 0.4, "sleep"], ["chiyo_fox", Vector3(-6.2, 0.14, -0.05), -0.6, "sleep"],
	["frog", Vector3(-6.5, 0.34, 2.1), 0.3, "sit"], ["rabbit", Vector3(-5.0, 0.0, 0.7), 0.6, "walk"],
	["yarn", Vector3(-4.6, 0.0, 1.0), -0.5, "walk"], ["pony", Vector3(-5.7, 0.0, 1.4), 0.2, "sit"], ["peacock", Vector3(-4.3, 0.0, 2.0), -0.3, "walk"]]
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、柵のミニオンを置く

var main: Node               # main.gd（人と craft を探す）
var craft: Node
var shop_open := false       # 売り場が開いている（mountain_ui.gd が入れる）
var rack_side := 1.0         # 棚を置く側（1 右手、-1 左手。main.gd が入れる）
var _model: Node3D           # yamaotoko.glb
var _skel: Skeleton3D
var _frame := -1
var _k := 0
var _noticed := false
var _wave_from := -100
var _show_from := -100       # 棚を示し始めたコマ
var _nod_from := -100
var _look_next := 24
var _look_yaw := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _buyer: Node3D           # いま見ている買った人（少しのあいだ）
var _buyer_until := -1
var _rng := RandomNumberGenerator.new()
var _set: Node3D             # ヤク・出店・柵（rack_side が右手なら左右を映す）
var _pen_loaded := false
var _pen_heads: Array = []   # 柵のミニオンの首（12 コマでときどき振る）
var _check_t := 0.0


func _ready() -> void:
	_rng.seed = 33
	_model = (load(MODEL) as PackedScene).instantiate()
	_model.name = "Doll"
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_make_foot_shadow()
	var col := StaticBody3D.new()   # ぶつかる体（上着の裾くらいの筒）
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.3 * SCALE
	cy.height = 1.3 * SCALE
	cs.shape = cy
	cs.position.y = 0.65 * SCALE
	col.add_child(cs)
	add_child(col)
	_make_set()
	if craft:
		craft.happened.connect(_on_craft)


## 骨を、骨の座標の空間（前は -Z、右は +X）の回転 e（オイラー角）で、付け根を軸に回す。親の骨は休みの姿のままとする
func _pose(bone: String, e: Vector3) -> void:
	var i := _skel.find_bone(bone)
	if i < 0:
		return
	var gr := _skel.get_bone_global_rest(i).basis.orthonormalized()
	var lr := _skel.get_bone_rest(i).basis.orthonormalized()
	_skel.set_bone_pose_rotation(i, (lr * (gr.inverse() * Basis.from_euler(e) * gr)).get_rotation_quaternion())


## 足もとに、やわらかい丸い影（人形と同じ: 雪の影と同じ青み。doll.gd の _make_foot_shadow）
func _make_foot_shadow() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.85, 1.0])
	g.colors = PackedColorArray([Color(0.08, 0.1, 0.2, 0.85), Color(0.08, 0.1, 0.2, 0.75), Color(0.08, 0.1, 0.2, 0.3), Color(0.08, 0.1, 0.2, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var d := Decal.new()
	var r := FOOT_SHADOW * SCALE
	d.size = Vector3(r * 2.0, 0.36, r * 2.0)
	d.texture_albedo = tex
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = Vector3(0, 0.02, 0)
	add_child(d)


# ---- ヤク・出店・柵 ----------------------------------------------------------------------

func _make_set() -> void:
	_set = Node3D.new()
	_set.name = "Set"
	_set.scale = Vector3(-rack_side, 1.0, 1.0) * SET_SCALE   # 組んだ形は出店が左手（-X）。右手に置くときは映す
	add_child(_set)
	for path in SET:
		_set.add_child((load(path) as PackedScene).instantiate())
	var body := StaticBody3D.new()
	for b in SET_BOXES:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (b[0] as Vector3).abs()
		cs.shape = box
		cs.position = b[1]
		body.add_child(cs)
	_set.add_child(body)


## 柵のミニオンを置く（あなたが近づいてから一度だけ。ミニオンの形を読むのは重いので）
func _load_pen() -> void:
	_pen_loaded = true
	for e in PEN_PETS:
		var n: Node3D = Pals.scene(e[0]).instantiate()
		Pals.paint(n)
		for c in n.get_children():
			(c as Node3D).visible = Pals.part_name(c) == e[3]
			if Pals.part_name(c) == e[3]:
				var h := c.find_child("head*", false, false)
				if h:
					_pen_heads.append(h)
		n.position = (e[1] as Vector3) * Vector3(-rack_side, 1.0, 1.0) * SET_SCALE
		n.rotation.y = PI + float(e[2])   # 正面（+Z）を客の側（-Z）へ
		add_child(n)


# ---- 動き（12 コマ／秒）----------------------------------------------------------------

## いちばん近い人（あなたとオンラインのほかの人。いなければ null）
func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := NOTICE_R
	var people: Array = []
	if main and main.get("player"):
		people.append(main.player)
	var net = main.get_node_or_null("Net") if main else null
	if net and net.get("remotes") != null:
		people.append_array(net.remotes.values())
	for p in people:
		if p is Node3D and is_instance_valid(p):
			var d: float = (p as Node3D).global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = p
	return best


func _process(dt: float) -> void:
	_check_t -= dt
	if not _pen_loaded and _check_t <= 0.0:
		_check_t = 0.5
		var you: Node3D = main.get("player") if main else null
		if you == null or you.global_position.distance_to(global_position) < NEAR_LOAD:
			_load_pen()
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	for i in _pen_heads.size():   # 柵のミニオンが、ときどき首を振る（品物ごとに違う間合い。2 階の売り台と同じ）
		var k := (fi + i * 13) % 50
		(_pen_heads[i] as Node3D).rotation = Vector3(0.0, 0.5 * sin(float((fi + i * 13) / 50) * 2.1) if k < 30 else 0.0, 0.25 if k > 44 else 0.0)
	var you := _buyer if _buyer and is_instance_valid(_buyer) and _k < _buyer_until else _nearest()
	var near := you != null
	if near and not _noticed:
		_wave_from = _k
	_noticed = near
	var want_yaw := _look_yaw
	var want_pitch := 0.0
	if near:
		var d := to_local(you.global_position + Vector3.UP * 1.3)
		want_yaw = clampf(atan2(-d.x, -d.z), -1.1, 1.1)
		want_pitch = clampf(atan2(d.y - 1.0 * SCALE, Vector2(d.x, d.z).length()) * 0.6, -0.3, 0.3)
	elif _k >= _look_next:
		_look_next = _k + _rng.randi_range(36, 80)
		_look_yaw = _rng.randf_range(-0.6, 0.6) if _rng.randf() < 0.7 else 0.0
	_head_yaw = lerpf(_head_yaw, want_yaw, 0.35)
	_head_pitch = lerpf(_head_pitch, want_pitch, 0.35)
	var nod := 0.0
	var n := _k - _nod_from
	if n >= 0 and n < 8:
		nod = [0.1, 0.25, 0.3, 0.2, 0.08, 0.18, 0.06, 0.0][n]
	_pose("head", Vector3(-_head_pitch - nod, _head_yaw, 0.03 * sin(_k * 0.19)))
	# 息: 2 秒で一回、体がわずかにふくらむ（4 コマずつの段で）
	var br := 0.5 + 0.5 * sin(TAU * float(_k / 4 * 4) / 24.0)
	_model.scale = Vector3(1.0 + 0.008 * br, 1.0 + 0.012 * br, 1.0 + 0.008 * br) * SCALE
	# 左腕: 振る。右腕: 棚を示す・買った人へ差し出す
	var w := _k - _wave_from
	if w >= 0 and w < 20:
		var up: float = [0.6, 1.4, 2.0, 2.2][mini(w, 3)] if w < 16 else [1.4, 0.7, 0.3, 0.0][w - 16]
		var sway := 0.0 if w < 4 or w >= 16 else (0.3 if (w / 2) % 2 == 0 else -0.15)
		_pose("upper_arm.L", Vector3(-0.2, 0, -up - sway))
	else:
		_pose("upper_arm.L", Vector3(0, 0, -0.03 * sin(_k * 0.3)))
	var p := _k - _show_from
	if p >= 0 and p < 24:   # 棚の側の腕を、棚へ振って示す（右手の側は +X）
		var out: float = [0.4, 0.9, 1.2, 1.3][mini(p, 3)] if p < 20 else [0.9, 0.5, 0.2, 0.0][p - 20]
		_pose("upper_arm.R" if rack_side > 0.0 else "upper_arm.L", Vector3(-0.6 * out, 0.9 * out * rack_side, 0))
		if rack_side < 0.0:
			_pose("upper_arm.R", Vector3(0, 0, 0.03 * sin(_k * 0.27)))
	elif n >= 0 and n < 10:   # 買った人へ差し出す
		var o: float = [0.3, 0.7, 0.9, 0.9, 0.9, 0.8, 0.6, 0.4, 0.2, 0.0][n]
		_pose("upper_arm.R", Vector3(-o, 0, 0))
	else:
		_pose("upper_arm.R", Vector3(0, 0, 0.03 * sin(_k * 0.27)))


## 売り場が開いた: 棚を示す
func greet() -> void:
	_show_from = _k + 1


## 売れた: 買った人を向いてうなずき、手を差し出す
func sold(buyer: Node3D) -> void:
	_nod_from = _k + 3
	if buyer:
		_buyer = buyer
		_buyer_until = _k + 30


## だれかが山男の棚の品物か、柵のミニオンを買った（通信では全員の画面に届く）
func _on_craft(ev: Dictionary) -> void:
	var tool: bool = ev.get("kind", "") == "buy" and Goods.has(ev.get("item", {}).get("kind", ""))
	var pet: bool = ev.get("kind", "") == "pal_buy" and Pals.slot_of(String(ev.get("key", ""))) == "pet"
	if not tool and not pet:
		return
	sold(_person(int(ev.get("who", -1))))


## 人の番号から、その人の体（あなたか、オンラインのほかの人）
func _person(who: int) -> Node3D:
	if main and main.get("player") and int(main.player.get("id")) == who:
		return main.player
	var net = main.get_node_or_null("Net") if main else null
	if net and net.get("remotes") != null:
		for r in net.remotes.values():
			if is_instance_valid(r) and int(r.get("id")) == who:
				return r
	return null


## 話しかけられる所にいるか
func can_talk(who: Node3D) -> bool:
	var d := to_local(who.global_position)
	return Vector2(d.x, d.z).length() < TALK_R and absf(d.y) < 1.6
