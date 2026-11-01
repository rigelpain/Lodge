extends Node3D
## 厨房の巨大な調理の装置 1 台（main.gd の KITCHEN が装置ごとに 1 つ付ける）。プレイヤーが手のペレットを入れて F で調理する
## （2026-11-01 代表と決めた: 調理はプレイヤー。道は food.gd）。動きは人形と同じ 12 コマ／秒に刻む（1 拍 = 6 コマ。調理の曲は 120 BPM）。
##   入れる   手のペレットが弧を描いて装置へ飛ぶ（6 コマ）。装置のオルゴールが鳴りはじめる（装置から鳴る。sound/gen/cook.py）
##   press    プレス機: 2 拍ごとに上の板が下りて押さえ、台ごとぐっと沈んで「ぼすっ」、綿の湯気がぽん（4 秒）
##   iron     アイロン台: 「ジュー」が続き、アイロンが布の上へ下りて 1 拍ごとに行き来し、折り返しで湯気（5 秒）
##   dryer    乾燥機: 胴が回り、料理の中身が透明な窓ごしに回りながら踊る（揚げ物は「ぱちぱち」、麺は「ぐつぐつ」）。上の漏斗から湯気（5 秒）
##   動く部品（アイロン・上の板・胴）と中身は cook_motion.gd・cook_tumble.gd
##   drink    衣類スチーマー: ふたが開いてペレットがぽとん → タンクに泡がごぼごぼ → ホースのふくらみが上って頭から湯気がぷしゅっ
##            （2 回）→ 棚にカップが出る（6 秒）
##   できあがり タイマーの「チン」。仕上がった物（料理か、次の装置へ持っていく途中の物）が装置からぽんと出て、入れた人の手へ飛ぶ
##   持ち物がいっぱいなら、装置の上に置いたまま待つ（もう一度 F で受け取る）
## 入れる・受け取るは工房の出来事（craft.gd の cook・cooked）。調理は出来事が配られてから始まるので、通信ではどの画面の装置も
## 同じ人の調理をする。仕上がりを手に戻す cooked は、ホストの画面の装置が仕上げたときに出す（ホストが装置の仕上がりを確かめて配る）
## 乾燥機には人も入れる（2026-11-01 代表「手にペレット持ってない状態のとき F で入ってキャラ乾燥させれるようにしてほしい」）:
##   手にペレットを持たずに乾燥機の前で F。丸い戸へとび込み（6 コマ）、胴の中でぐにゃんぐにゃんに回される（dryer_flop.gd:
##   羽根に持ち上げられ、てっぺんの手前で離れてくるっと落ち、手足と頭はぶらぶら。顔は丸い戸の窓へ向く）。
##   姿は丸い戸の窓（透明なフィルム）から見える。回っているあいだに紙の水が抜けて、いちばんパリッと（−40）まで 4 秒ほど（damp.gd）。
##   乾ききって 1.5 秒以上回ったら、ひとりでに戸からとび出す（5 コマ）。もう一度 F でも出る。
##   入る・出るは「誰が」の短い出来事（craft.gd の dry_in・dry_out）。ホストが空きを確かめて全員に配るので、どの画面でも
##   同じ人が同じコマに入って回る。中に人がいるあいだは調理できず、誰かが調理しているあいだは入れない

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const Food := preload("res://food.gd")
const Look := preload("res://look.gd")
const CookMotion := preload("res://cook_motion.gd")
const DryerFlop := preload("res://dryer_flop.gd")

const USE_R := {"press": 2.4, "iron": 2.8, "dryer": 2.9, "drink": 2.5}   # 装置の真ん中からこの距離で使える (m)
const RUN := {"press": 48, "iron": 60, "dryer": 60, "drink": 72}        # 調理のコマ数（12 コマで 1 秒）
const FLY := 6               # 手から装置へ、装置から手へ飛ぶコマ数
const RIDE_IN := 6           # 乾燥機へとび込むコマ
const RIDE_MIN := 18         # 乾ききっても、これだけは回る（1.5 秒）
const RIDE_MAX := 144        # これより長くは回らない（12 秒。出る出来事が来なくても、空きに戻す）
const RIDE_OUT := 5          # 戸からとび出すコマ
const SPIN := TAU / 16.0     # 1 コマに回る角
const DOOR := 0.85           # 胴の真ん中（目印 cook）から丸い戸の面までの距離 (m)
const STAND := 2.1           # 胴の真ん中から、とび出して立つ所までの距離（前へ, m）
const HIP := 0.32            # 胴の真ん中から、丸まった人形の腰（足もと＝人形の付け根）までの下がり (m)

var main: Node
var kind := ""
var who := -1                # 調理している人の番号（-1 は空き）
var who_node: Node3D
var item := {}               # 入っている物（調理前）
var result := {}             # 仕上がった物（受け取られるまで）
var _dev: Node3D             # 装置（親）
var _rest := Transform3D()
var _frame := -1
var _k := 0
var _start := -1000          # 入れたコマ
var _vis: Node3D             # 装置の中・上に見せる物
var _music: AudioStreamPlayer3D
var _loop: AudioStreamPlayer3D
var _puffs: Array = []       # [node, 生まれたコマ, 大きさ]
var _bubbles: Array = []     # [node, 生まれたコマ, 横の位置]
var _bulge: MeshInstance3D
var _cup: Node3D
var _lid: Node3D
var _mark := {}
var rider := -1              # 乾燥機の中にいる人の番号（-1 は空き）
var rider_node: Node3D
var _ride_f := -1            # 入ったコマ（人形の時計）
var _out_f := -1             # 出ると決まったコマ（-1 はまだ）
var _ride_from := Vector3.ZERO   # 入る前に立っていた所
var _cook_until := -1        # 誰か（ほかの画面の人も）が調理しているあいだ、このコマまで入れない
var _ride_snd: Array = []
var _flop: DryerFlop         # 中の人の体の物理（入るたびに作る。dryer_flop.gd）
var _mo: CookMotion          # 動く部品（アイロン・プレス機の上の板・乾燥機の胴と中身。cook_motion.gd）


func _ready() -> void:
	_dev = get_parent() as Node3D
	_rest = _dev.transform
	for c in _dev.find_children("*", "Node3D", true, false):
		var nm := String(c.name).get_slice(".", 0)
		if not _mark.has(nm):
			_mark[nm] = c
	_lid = _dev.find_child("Lid", true, false) as Node3D
	if kind == "dryer":
		add_to_group("dryers")   # damp.gd が、中で回っている人を乾かす
		_open_window.call_deferred()
	_mo = CookMotion.new(self, _dev)
	_mo.mount.call_deferred()   # 乾燥機の窓を抜いたあと（胴の羽根を抜かない）
	var craft = main.get("craft") if main else null
	if craft:
		craft.happened.connect(_on_craft)


func _m(name: String) -> Vector3:
	var n: Node3D = _mark.get(name)
	if n == null and _mo:
		n = _mo.mark(name)   # 書き出しで名前に番号が付いた目印（cook_006 など）
	return n.global_position if n else _dev.global_position + Vector3.UP * 1.0


func busy() -> bool:
	return who >= 0 or not result.is_empty()


## 人 p がこの装置を使える所にいて、手の物を入れられるか（または、自分の仕上がりを受け取れるか）
func can_use(p: Node3D) -> bool:
	var d := p.global_position - _dev.global_position
	d.y = 0
	if d.length() > USE_R.get(kind, 2.5):
		return false
	if not result.is_empty():
		return int(p.get("id")) == who
	if who >= 0 or riding() or Doll.frame_index() < _cook_until:
		return false
	return Food.next_station(p.held()) == kind


## F: 入れて調理を始める（仕上がりを待っていれば受け取る）。出来事を出すだけで、動きは配られてから（_on_craft）
func use(p: Node3D) -> bool:
	var id := int(p.get("id"))
	var craft: Node = main.craft
	if not result.is_empty():
		return _give(false)
	var hand: int = craft.hands.get(id, -1)
	if not craft.send({"kind": "cook", "who": id, "slot": hand, "station": kind}):
		return false
	var hud = main.get("hud")
	if hud:
		hud.learn("cook")
	return true


## 工房の出来事が配られた（どの画面でも。ほかの人の調理も、ここで始まって手に渡る）
func _on_craft(ev: Dictionary) -> void:
	if ev.get("station") != kind:
		return
	match ev.kind:
		"cook":
			_begin(ev)
		"cooked":
			_hand_over(ev)


## 手のペレットが装置へ飛んで、調理が始まる
func _begin(ev: Dictionary) -> void:
	var hub = main.get("emotes")
	who = int(ev.who)
	who_node = hub.people.get(who) if hub else null
	item = ev.item
	_start = _k + 1
	_vis = Props.make(Food.pellet_glb(item.dish))
	_vis.scale = Vector3.ONE * 2.0
	main.add_child(_vis)
	if is_instance_valid(who_node):
		_vis.global_position = who_node.global_position + Vector3.UP * 1.1 - who_node.global_basis.z * 0.35
	else:
		_vis.global_position = _dest()
	_vis.set_meta("from", _vis.global_position)


func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	_step_fx()
	if rider >= 0:
		_ride_fx(fi)
	if who < 0 or not result.is_empty():
		return
	var t := _k - _start
	var dest := _dest()
	if t <= FLY and _vis:   # 手から装置へ
		var a: Vector3 = _vis.get_meta("from")
		var s := float(t) / FLY
		_vis.global_position = a.lerp(dest, s) + Vector3.UP * 0.6 * 4.0 * s * (1.0 - s)
		_vis.rotation.y += 0.5
		if t == FLY:
			_arrive()
		return
	var r := t - FLY
	match kind:
		"press":
			_press(r)
		"iron":
			_iron(r)
		"dryer":
			_dryer(r)
		"drink":
			_drink(r)
	if r >= RUN[kind]:
		_mo.rest()
		_finish()


## ペレットを置く所（装置ごと）
func _dest() -> Vector3:
	match kind:
		"drink":
			return _m("drop")
		"dryer":
			return _m("hopper") + Vector3.UP * 0.2
	return _m("cook") + Vector3.UP * 0.08


func _arrive() -> void:
	var audio = main.get_node_or_null("Audio")
	if audio == null:
		return
	audio.kitchen(_dev, "cook_pellet", -8.0, 3)
	_music = audio.kitchen(_dev, "cook_music_%s_loop" % kind, -12.0)
	match kind:
		"iron":
			_loop = audio.kitchen(_dev, "cook_sizzle_loop", -12.0)
		"dryer":
			_loop = audio.kitchen(_dev, "cook_fry_loop" if item.dish in Food.FRIED else "cook_boil_loop", -10.0)
			var drum = audio.kitchen(_dev, "cook_drum_loop", -14.0)
			if drum:
				drum.set_meta("extra", true)
				_vis.set_meta("drum", drum)


func _press(r: int) -> void:
	# 2 拍（12 コマ）ごとに、上の板が下りて閉じ、押さえて「ぼすっ」と綿の湯気、台ごとぐっと沈む。ゆっくり開いて、また下りる
	var audio = main.get_node_or_null("Audio")
	if r == 0 and audio:
		audio.kitchen(_dev, "cook_press_in", -8.0, 2)   # つめ車のレバーを引き下ろす
	var shut := _mo.press(r)
	var c := (r - CookMotion.SHUT) % 12
	var sq: float = [0.93, 0.9, 1.03, 1.0][c] if c < 4 and r >= CookMotion.SHUT else 1.0
	_squash(Vector3(1.0 + (1.0 - sq) * 0.5, sq, 1.0 + (1.0 - sq) * 0.5))
	if shut:
		if audio:
			audio.kitchen(_dev, "cook_press", -6.0, 3)
		_puff(_m("cook") + Vector3.UP * 0.3, 0.35)
		if _vis:   # 粒は押されて平たくなっていく
			var k := minf(1.0, (r + 10) / 36.0)
			_vis.scale = Vector3(2.0 + k * 0.8, 2.0 - k * 1.1, 2.0 + k * 0.8)
	if r == RUN.press - 5 and audio:
		audio.kitchen(_dev, "cook_press_done", -8.0, 2)   # たまった湯気が抜けて、レバーが戻る


func _iron(r: int) -> void:
	# アイロンが鍋敷きから布の上へ下り、当て布の上を行き来して押す。折り返しで湯気。最後に鍋敷きへ戻る（cook_motion.gd）
	var o := _mo.iron(r, RUN.iron)
	var audio = main.get_node_or_null("Audio")
	if audio and o.land:
		audio.kitchen(_dev, "cook_iron_in", -8.0, 2)     # アイロンを下ろす「ごとん」
	if audio and o.lift:
		audio.kitchen(_dev, "cook_iron_done", -8.0, 2)   # 持ち上げて、こもった湯気が「しゅわっ」
	if o.turn:
		_puff(_mo.iron_tip(), 0.18)
	if _vis and o.press > 0.0:   # 粒は押されて平たく広がっていく
		var k: float = o.press
		_vis.scale = Vector3(2.0 + k * 0.9, 2.0 - k * 1.1, 2.0 + k * 0.9)


func _dryer(r: int) -> void:
	_dev.transform = _rest
	_dev.rotate_object_local(Vector3.FORWARD, [0.008, -0.006, 0.005, -0.008][(r / 2) % 4])
	_dev.position += Vector3.UP * (0.012 if (r / 3) % 2 == 0 else 0.0)
	# 胴が回り、料理の中身が胴の中で回りながら踊る（人が入って回るときは中身なし。cook_motion.gd・cook_tumble.gd）
	_mo.dryer(r, String(item.get("dish", "")) if who >= 0 and r > 2 else "")
	if r % 12 == 0:
		_puff(_m("hopper") + Vector3.UP * 0.3, 0.38)
	if _vis and r == 2:
		_vis.visible = false   # 漏斗から胴の中へ


func _drink(r: int) -> void:
	# ふた: 0〜3 コマで開き、ペレットが落ちて、9〜12 コマで閉じる
	if _lid:
		var open: float = [0.4, 1.0, 1.5, 1.7, 1.7, 1.7, 1.7, 1.7, 1.7, 1.3, 0.8, 0.3, 0.0][r] if r < 13 else 0.0
		_lid.rotation.x = -open
	if _vis and r <= 6:
		_vis.global_position = _m("drop").lerp(_m("water"), r / 6.0)
		if r == 6:
			_vis.visible = false
			var audio = main.get_node_or_null("Audio")
			if audio:
				audio.kitchen(_dev, "cook_plop_01", -6.0)
				_loop = audio.kitchen(_dev, "cook_gurgle_loop", -10.0)
	# 泡: タンクの中を綿の粒が上る
	if r > 6 and r < 60 and r % 2 == 0:
		_bubble()
	# ホースのふくらみ: 下から上へ 16 コマで上り、頭で湯気がぷしゅっ（2 回）
	for start in [16, 38]:
		var b: int = r - start
		if b >= 0 and b <= 16:
			_bulge_at(b / 16.0)
		if b == 17:
			if _bulge:
				_bulge.visible = false
			var audio = main.get_node_or_null("Audio")
			if audio:
				audio.kitchen(_dev, "cook_puff", -6.0, 3)
			_puff(_m("head") - Vector3.UP * 0.15, 0.45, true)
	if r == 34:   # 棚にカップが出る（1 回目のぷしゅっのあと）
		_cup = Props.make(Food.dish_glb(item.dish))
		_cup.scale = Vector3.ONE * 2.2
		main.add_child(_cup)
		_cup.global_position = _m("cup")


func _squash(s: Vector3) -> void:
	_dev.transform = _rest
	_dev.scale = _rest.basis.get_scale() * s


func _bulge_at(t: float) -> void:
	var pts: Array = []
	var i := 0
	while _mark.has("hose_%d" % i):
		pts.append(_m("hose_%d" % i))
		i += 1
	if pts.size() < 2:
		return
	if _bulge == null:
		_bulge = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.32
		_bulge.mesh = sm
		_bulge.material_override = Look.felt(Color(0.72, 0.25, 0.18))
		main.add_child(_bulge)
	_bulge.visible = true
	var f := t * (pts.size() - 1)
	var k := mini(int(f), pts.size() - 2)
	_bulge.global_position = (pts[k] as Vector3).lerp(pts[k + 1], f - k)


func _bubble() -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	m.mesh = sm
	m.material_override = Look.snow()
	main.add_child(m)
	# 中の水は不透明なフェルトなので、泡は手前（食堂の側）の水の面とフィルムのあいだを上る
	var w := _m("water")
	var front: Vector3 = (_dev.get_parent() as Node3D).global_basis.z if _dev.get_parent() is Node3D else Vector3.BACK
	var side: Vector3 = front.cross(Vector3.UP).normalized()
	var a := randf_range(-1.0, 1.0)
	var off: Vector3 = (front * cos(a) + side * sin(a)).normalized() * 0.585
	m.global_position = w + off - Vector3.UP * 0.7
	_bubbles.append([m, _k, off])


## 綿の湯気のかたまり（ふくらんで上り、しぼんで消える。8 コマ）
func _puff(at: Vector3, size: float, down := false) -> void:
	var root := Node3D.new()
	main.add_child(root)
	root.global_position = at
	for i in 4:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = size * randf_range(0.5, 0.9)
		sm.height = sm.radius * 2.0
		m.mesh = sm
		m.material_override = Look.snow()
		m.position = Vector3(randf_range(-1, 1), randf_range(0, 1) * (-1.0 if down else 1.0), randf_range(-1, 1)) * size * 0.6
		root.add_child(m)
	root.scale = Vector3.ONE * 0.3
	root.set_meta("down", down)
	_puffs.append([root, _k])


func _step_fx() -> void:
	for p in _puffs.duplicate():
		var n: Node3D = p[0]
		var age: int = _k - int(p[1])
		if age > 8 or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_puffs.erase(p)
			continue
		n.scale = Vector3.ONE * [0.3, 0.7, 1.0, 1.15, 1.2, 1.1, 0.9, 0.6, 0.3][age]
		n.position += Vector3.UP * (-0.06 if n.get_meta("down") else 0.08)
	for b in _bubbles.duplicate():
		var n: Node3D = b[0]
		var age: int = _k - int(b[1])
		if age > 10 or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_bubbles.erase(b)
			continue
		n.global_position = _m("water") + b[2] - Vector3.UP * (0.7 - age * 0.07)
	# 受け取られるのを待つ仕上がりは、ゆっくり跳ねる
	if not result.is_empty() and _vis:
		_vis.position.y += 0.03 if (_k / 6) % 2 == 0 else -0.03


## 調理が仕上がる。give はできあがりの「手に戻す」を出すか（ホストの装置が先に仕上げて cooked が届いたときは出さない）
func _finish(give := true) -> void:
	_dev.transform = _rest
	if _lid:
		_lid.rotation.x = 0.0
	if _bulge:
		_bulge.visible = false
	for p in [_music, _loop]:
		if p and is_instance_valid(p):
			p.queue_free()
	if _vis and is_instance_valid(_vis):
		if _vis.has_meta("drum"):   # 音なしのときは付いていない（get_meta の既定に null を渡すと ERROR になる）
			var drum = _vis.get_meta("drum")
			if is_instance_valid(drum):
				drum.queue_free()
		_vis.queue_free()
	if _cup and is_instance_valid(_cup):
		_cup.queue_free()
	_cup = null
	var audio = main.get_node_or_null("Audio")
	if audio:
		audio.kitchen(_dev, "cook_done", -8.0, 2)
	result = item.duplicate()
	result["step"] = int(item.get("step", 0)) + 1
	item = {}
	# 仕上がった物を装置の上にぽんと出す（できあがりは料理、途中なら押されたペレット）
	var done := Food.done(result)
	_vis = Props.make(Food.dish_glb(result.dish) if done else Food.pellet_glb(result.dish))
	_vis.scale = Vector3.ONE * (2.0 if done else 2.0) * (Vector3(1.3, 0.6, 1.3) if not done and kind == "press" else Vector3.ONE)
	main.add_child(_vis)
	_vis.global_position = (_m("cup") if kind == "drink" else _dest()) + Vector3.UP * 0.15
	if give:
		_give(true)


## 仕上がりを入れた人の手へ戻す出来事を出す（ホストが装置の仕上がりを確かめて配る。持ち物がいっぱいなら断られ、装置の上で待つ）。
## auto はできあがりのとき: つなぐ側の画面では出さない（同じ仕上がりを、ホストの画面の装置が出す）
func _give(auto: bool) -> bool:
	if result.is_empty():
		return false
	return main.craft.send({"kind": "cooked", "who": who, "station": kind, "auto": auto})


## 手に戻す出来事が配られた: 仕上がりが装置から入れた人の手へ飛ぶ
func _hand_over(ev: Dictionary) -> void:
	if who >= 0 and result.is_empty():
		_finish(false)   # ホストの装置が先に仕上げた（この画面の調理は、まだ少し残っていた）
	if result.is_empty():
		return   # この画面では調理を見ていない（持ち物は craft.gd が戻している）
	var v := _vis
	if is_instance_valid(v):
		var to := who_node.global_position + Vector3.UP * 1.1 if is_instance_valid(who_node) else v.global_position
		var from := v.global_position
		var tw := create_tween()
		tw.tween_method(func(s: float) -> void:
			if is_instance_valid(v):
				v.global_position = from.lerp(to, s) + Vector3.UP * 0.5 * 4.0 * s * (1.0 - s), 0.0, 1.0, FLY / 12.0)
		tw.tween_callback(func() -> void:
			if is_instance_valid(v):
				v.queue_free())
	var audio = main.get_node_or_null("Audio")
	if audio and is_instance_valid(who_node):
		audio.kitchen(who_node, "cook_pellet", -9.0, 3)
	_vis = null
	result = {}
	who = -1
	who_node = null


# ---------------------------------------------------------------- 乾燥機に入る

## 胴の前（食堂の側、水平）
func front() -> Vector3:
	var slot := _dev.get_parent() as Node3D
	var f: Vector3 = slot.global_basis.z if slot else Vector3.BACK
	f.y = 0
	return f.normalized()


## 胴の真ん中（回る軸の上。人形はここを中心に回る）。乾燥機の目印は、書き出しで名前に番号が付いて cook_010 になっている
func drum_center() -> Vector3:
	for k in _mark:
		if String(k).begins_with("cook"):
			return (_mark[k] as Node3D).global_position
	return _dev.global_position + Vector3.UP * 1.7


## とび出して立つ所（床の上）
func stand_point() -> Vector3:
	var p := drum_center() + front() * STAND
	p.y = _dev.global_position.y
	return p


## 乾燥機の当たり（中にいる人の三人称のカメラが、胴の中から外へ出られるように外す）
func body_rid() -> RID:
	for c in _dev.get_children():
		if c is StaticBody3D:
			return (c as StaticBody3D).get_rid()
	return RID()


## 中に人がいる（出きるまで。出る出来事が来なくても、RIDE_MAX のあとは空き）
func riding() -> bool:
	if rider < 0:
		return false
	return Doll.frame_index() <= (_out_f + RIDE_OUT if _out_f >= 0 else _ride_f + RIDE_IN + RIDE_MAX + RIDE_OUT)


## 人 p が乾燥機に入れるか: 乾燥機の前（食堂の側）にいて、手にペレットを持っておらず、空いていて、誰も調理していない
func can_ride(p: Node3D) -> bool:
	if kind != "dryer" or busy() or riding() or Doll.frame_index() < _cook_until:
		return false
	var held: Dictionary = p.held() if p.has_method("held") else {}
	if held.get("kind") == "food" and not Food.done(held):
		return false   # ペレット（調理の途中の物）を持っていれば、いつもどおり調理（乾燥機の次でなければ何もしない）
	var d := p.global_position - _dev.global_position
	d.y = 0
	return d.length() <= USE_R[kind] and d.dot(front()) > 0.0


## F: 入る（出来事を出す。入るのは配られてから: begin_ride）
func ride(p: Node3D) -> bool:
	if not can_ride(p):
		return false
	return main.craft.send({"kind": "dry_in", "who": int(p.get("id"))})


## F（中で）: 出る
func leave(id: int) -> void:
	if rider == id and _out_f < 0:
		main.craft.send({"kind": "dry_out", "who": id})


## 入る出来事が配られた（craft.gd。どの画面でも同じコマ）
func begin_ride(id: int, frame: int) -> void:
	var hub = main.get("emotes")
	rider = id
	rider_node = hub.people.get(id) if hub else null
	_ride_f = frame
	_out_f = -1
	var doll = rider_node.get("doll") if is_instance_valid(rider_node) else null
	var ext: Vector3 = doll.drum_extent() if doll else Vector3(-0.1, 0.8, 0.3)   # 人形の大きさ（胴に当てる。大きければ縮める）
	_flop = DryerFlop.new(SPIN * 12.0, Vector2(HIP, 0.0), ext)   # とび込んで、胴の真ん中の下から
	_ride_from = rider_node.global_position if is_instance_valid(rider_node) else stand_point()
	if is_instance_valid(rider_node) and rider_node.has_method("enter_drum"):
		rider_node.enter_drum(self)


## 出る出来事が配られた
func end_ride(id: int, frame: int) -> void:
	if rider == id and _out_f < 0:
		_out_f = maxi(frame, _ride_f + RIDE_IN)


## 調理の出来事が配られた（craft.gd。ほかの画面の人の調理も）: 仕上がるまで入れない
func note_cook(frame: int) -> void:
	_cook_until = maxi(_cook_until, frame + FLY + RUN[kind] + 6)


## 回っているあいだ（紙の水が抜ける。damp.gd）
func drying(id: int) -> bool:
	if rider != id or not riding():
		return false
	var f := Doll.frame_index()
	return f >= _ride_f + RIDE_IN and (_out_f < 0 or f < _out_f)


## 中にいる人が、ひとりでに出るころか（その人の画面が決める）: 乾ききって RIDE_MIN 回ったか、RIDE_MAX 回った
func should_leave(water: float, crisp: float) -> bool:
	var k := Doll.frame_index() - _ride_f - RIDE_IN
	return _out_f < 0 and ((water <= crisp + 0.5 and k >= RIDE_MIN) or k >= RIDE_MAX)


## 胴の中のコマ k（とび込んだあと）の体（dryer_flop.gd）: at 付け根の世界の位置、pos は人形が spin で胴の真ん中のまわりに
## 回される前の位置（人形は pos を spin_at のまわりに spin だけ回して置くので、回したあとが at になる）
func _flop_pose(k: int) -> Dictionary:
	var s: Dictionary = _flop.at(k)
	var c := drum_center()
	var fw := front()
	var side := Basis(fw, PI / 2.0) * Vector3.DOWN
	var off: Vector3 = Vector3.DOWN * s.p.x + side * s.p.y
	return {"at": c + off, "pos": c + Basis(fw, -s.th) * off, "spin": s.th, "flop": s.flop, "land": s.land, "fit": s.fit}


## コマ f での中の人の居場所と姿勢: {pos 足もと, spin 回った角, stage 0 立つ・1 中腰・2 丸まる, face 向き, done 出きった, flop 手足の振れ,
## fit 人形の大きさの倍（胴に収まらない人形は、とび込むあいだに縮み、出るとき戻る）}
func ride_pose(f: int) -> Dictionary:
	var c := drum_center()
	var fw := front()
	var door := c + fw * DOOR
	var seat := c - Vector3.UP * HIP
	if _out_f >= 0 and f >= _out_f:
		var u := f - _out_f
		if u >= RIDE_OUT - 1:
			return {"pos": stand_point(), "spin": 0.0, "stage": 0, "face": fw, "done": u >= RIDE_OUT}
		var from: Vector3 = _flop_pose(_out_f - _ride_f - RIDE_IN).at if _flop else seat   # 胴の中で回されていた所から
		var fit: float = lerpf(_flop.fit if _flop else 1.0, 1.0, (u + 1.0) / RIDE_OUT)
		return {"pos": _hop(from, door, stand_point(), (u + 1.0) / RIDE_OUT), "spin": 0.0, "stage": 1, "face": fw, "done": false, "fit": fit}
	var k := f - _ride_f
	if k < 0:
		return {"pos": _ride_from, "spin": 0.0, "stage": 0, "face": -fw, "done": false}
	if k < RIDE_IN:
		return {"pos": _hop(_ride_from, door, seat, (k + 1.0) / RIDE_IN), "spin": 0.0, "stage": 1, "face": -fw if k < RIDE_IN - 1 else fw, "done": false,
				"fit": lerpf(1.0, _flop.fit if _flop else 1.0, (k + 1.0) / RIDE_IN)}
	if _flop == null:
		return {"pos": seat, "spin": (k - RIDE_IN) * SPIN, "stage": 2, "face": fw, "done": false}
	var fp := _flop_pose(k - RIDE_IN)
	return {"pos": fp.pos, "spin": fp.spin, "stage": 2, "face": fw, "done": false, "flop": fp.flop, "fit": fp.fit}


## a から戸の b をくぐって c へ（2 次のベジェ。戸の前で少し上へ弧を描く）
static func _hop(a: Vector3, b: Vector3, c: Vector3, s: float) -> Vector3:
	s = clampf(s, 0.0, 1.0)
	return a * (1.0 - s) * (1.0 - s) + b * 2.0 * (1.0 - s) * s + c * s * s + Vector3.UP * 0.35 * 4.0 * s * (1.0 - s)


## 中に人がいるあいだの乾燥機: 調理と同じく胴ががたがた揺れ、漏斗から湯気。とび込んだら回る音とオルゴール
func _ride_fx(f: int) -> void:
	var k := f - _ride_f
	if not riding():
		_end_fx()
		rider = -1
		rider_node = null
		return
	var out := _out_f >= 0 and f >= _out_f
	if k == RIDE_IN and _ride_snd.is_empty():
		var audio = main.get_node_or_null("Audio")
		if audio:
			for x in [["cook_drum_loop", -10.0], ["cook_music_dryer_loop", -12.0]]:
				var a = audio.kitchen(_dev, x[0], x[1])
				if a:
					_ride_snd.append(a)
	if k >= RIDE_IN and not out:
		_dryer(k - RIDE_IN)
		if _flop and _flop.at(k - RIDE_IN).land:   # 壁に落ちた「ぽすっ」
			var audio = main.get_node_or_null("Audio")
			if audio:
				audio.kitchen(_dev, "cook_press", -15.0, 3, 1.25)
	elif out:
		_end_fx()


func _end_fx() -> void:
	if who < 0:
		_dev.transform = _rest
		_mo.rest()
	for a in _ride_snd:
		if is_instance_valid(a):
			a.queue_free()
	_ride_snd.clear()


# ---------------------------------------------------------------- 乾燥機の丸い窓を抜く
# 乾燥機の glb（props/build_kitchen.py の dryer_body）は、本体のふっくらした箱の前の面が丸い戸のフィルムのすぐ裏に残っていて、
# 中の編み地の胴・羽根・粒が見えない（箱に閉じこめられている）。中に入った人が窓から見えるように、ゲームを始めたときに、
# 本体のフェルトの前の面のうち窓の内側を抜く: 窓にかかる三角を細かく割り（WIN_STEP 以下）、真ん中が窓の内側の小さな三角を捨てる。
# ぎざぎざの縁は、戸の紺の縁（太さ 0.3 m ほど）の下に隠れる。台本で穴を開けて書き出し直したら、ここは要らない

const WIN_R := 0.68          # 抜く窓の半径 (m。フィルムは 0.69、紺の縁は 0.6〜0.9)
const WIN_SHELL := 0.3       # フィルムからこれだけ奥までの面を抜く対象にする (m)
const WIN_STEP := 0.06       # 割る三角の辺の長さ (m)


func _open_window() -> void:
	var glass: MeshInstance3D = null
	for mi in _dev.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).ends_with("_glass"):
			glass = mi
	if glass == null:
		return
	var fw := front()
	var gb := glass.global_transform * glass.mesh.get_aabb()
	var gc := gb.get_center()   # フィルムの真ん中（戸の軸の上）
	for mi in _dev.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).ends_with("_felt") or not (m.mesh is ArrayMesh):
			continue
		var src := m.mesh as ArrayMesh
		var out := ArrayMesh.new()
		var changed := false
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var cut := _cut_window(arr, m.global_transform, gc, fw)
			changed = changed or cut != arr
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cut)
			out.surface_set_material(si, src.surface_get_material(si))
		if changed:
			var keep: Array = []
			for si in src.get_surface_count():
				keep.append(m.get_surface_override_material(si))
			m.mesh = out
			for si in keep.size():
				if keep[si]:
					m.set_surface_override_material(si, keep[si])


## 面の配列から、窓の内側の面を抜いた配列（抜く所がなければ、そのまま返す）
func _cut_window(arr: Array, xf: Transform3D, gc: Vector3, fw: Vector3) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
	var at := func(i: int) -> Vector3: return xf * vs[i]
	var inside := func(w: Vector3) -> bool:
		var rel := w - gc
		var t := rel.dot(fw)
		return t < 0.0 and t > -WIN_SHELL and (rel - fw * t).length() < WIN_R
	var near := func(w: Vector3) -> bool:
		var rel := w - gc
		var t := rel.dot(fw)
		return t < 0.02 and t > -WIN_SHELL - 0.02
	# 頂点ごとの値（重みをつけて混ぜる）
	var kinds := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]
	var keep_tris: Array = []    # [i0, i1, i2]
	var new_tris: Array = []     # [[i, w] x3] 頂点ごとに、もとの三角の 3 頂点の重み
	var any := false
	for t in range(0, idx.size() - 2, 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		var a: Vector3 = at.call(ia)
		var b: Vector3 = at.call(ib)
		var c: Vector3 = at.call(ic)
		# 前の面の三角で、窓にかかるもの（3 頂点とも前の殻の中にあり、窓の円に近い）
		if not (near.call(a) and near.call(b) and near.call(c)):
			keep_tris.append([ia, ib, ic])
			continue
		var center := (a + b + c) / 3.0
		var rel := center - gc
		var reach := maxf(a.distance_to(center), maxf(b.distance_to(center), c.distance_to(center)))
		if (rel - fw * rel.dot(fw)).length() > WIN_R + reach:
			keep_tris.append([ia, ib, ic])
			continue
		any = true
		# 重心座標で割っていく
		var stack := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]]
		while not stack.is_empty():
			var q: Array = stack.pop_back()
			var pa: Vector3 = a * q[0].x + b * q[0].y + c * q[0].z
			var pb: Vector3 = a * q[1].x + b * q[1].y + c * q[1].z
			var pc: Vector3 = a * q[2].x + b * q[2].y + c * q[2].z
			if maxf(pa.distance_to(pb), maxf(pb.distance_to(pc), pc.distance_to(pa))) > WIN_STEP:
				var ab: Vector3 = (q[0] + q[1]) * 0.5
				var bc: Vector3 = (q[1] + q[2]) * 0.5
				var ca: Vector3 = (q[2] + q[0]) * 0.5
				stack.append([q[0], ab, ca])
				stack.append([ab, q[1], bc])
				stack.append([ca, bc, q[2]])
				stack.append([ab, bc, ca])
				continue
			if inside.call((pa + pb + pc) / 3.0):
				continue   # 窓の内側: 捨てる
			new_tris.append([[ia, ib, ic], q])
	if not any:
		return arr
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in kinds:
		if arr[k] == null:
			continue
		var src = arr[k]
		var dst
		match k:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				dst = PackedVector3Array()
			Mesh.ARRAY_TANGENT:
				dst = PackedFloat32Array()
			Mesh.ARRAY_COLOR:
				dst = PackedColorArray()
			_:
				dst = PackedVector2Array()
		for tri in keep_tris:
			for i in tri:
				if k == Mesh.ARRAY_TANGENT:
					for j in 4:
						dst.append(src[i * 4 + j])
				else:
					dst.append(src[i])
		for nt in new_tris:
			var ii: Array = nt[0]
			for wv in nt[1]:
				var w: Vector3 = wv
				if k == Mesh.ARRAY_TANGENT:
					for j in 4:
						dst.append(src[ii[0] * 4 + j] * w.x + src[ii[1] * 4 + j] * w.y + src[ii[2] * 4 + j] * w.z)
				elif k == Mesh.ARRAY_NORMAL:
					dst.append((src[ii[0]] * w.x + src[ii[1]] * w.y + src[ii[2]] * w.z).normalized())
				else:
					dst.append(src[ii[0]] * w.x + src[ii[1]] * w.y + src[ii[2]] * w.z)
		out[k] = dst
	return out

