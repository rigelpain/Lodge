extends Node3D
## 厨房の巨大な調理の装置 1 台（main.gd の KITCHEN が装置ごとに 1 つ付ける）。プレイヤーが手のペレットを入れて F で調理する
## （2026-11-01 代表と決めた: 調理はプレイヤー。道は food.gd）。動きは人形と同じ 12 コマ／秒に刻む（1 拍 = 6 コマ。調理の曲は 120 BPM）。
##   入れる   手のペレットが弧を描いて装置へ飛ぶ（6 コマ）。装置のオルゴールが鳴りはじめる（装置から鳴る。sound/gen/cook.py）
##   press    プレス機: 2 拍ごとに台ごとぐっと沈んで「ぼすっ」、綿の湯気がぽん（4 秒）
##   iron     アイロン台: 「ジュー」が続き、台が小刻みに揺れ、1 拍ごとに湯気（5 秒）
##   dryer    乾燥機: 胴が回ってがたがた揺れる（揚げ物は「ぱちぱち」、麺は「ぐつぐつ」）。上の漏斗から湯気（5 秒）
##   drink    衣類スチーマー: ふたが開いてペレットがぽとん → タンクに泡がごぼごぼ → ホースのふくらみが上って頭から湯気がぷしゅっ
##            （2 回）→ 棚にカップが出る（6 秒）
##   できあがり タイマーの「チン」。仕上がった物（料理か、次の装置へ持っていく途中の物）が装置からぽんと出て、入れた人の手へ飛ぶ
##   持ち物がいっぱいなら、装置の上に置いたまま待つ（もう一度 F で受け取る）

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const Food := preload("res://food.gd")
const Look := preload("res://look.gd")

const USE_R := {"press": 2.4, "iron": 2.8, "dryer": 2.9, "drink": 2.5}   # 装置の真ん中からこの距離で使える (m)
const RUN := {"press": 48, "iron": 60, "dryer": 60, "drink": 72}        # 調理のコマ数（12 コマで 1 秒）
const FLY := 6               # 手から装置へ、装置から手へ飛ぶコマ数

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


func _ready() -> void:
	_dev = get_parent() as Node3D
	_rest = _dev.transform
	for c in _dev.find_children("*", "Node3D", true, false):
		var nm := String(c.name).get_slice(".", 0)
		if not _mark.has(nm):
			_mark[nm] = c
	_lid = _dev.find_child("Lid", true, false) as Node3D


func _m(name: String) -> Vector3:
	var n: Node3D = _mark.get(name)
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
	if who >= 0:
		return false
	return Food.next_station(p.held()) == kind


## F: 入れて調理を始める（仕上がりを待っていれば受け取る）
func use(p: Node3D) -> bool:
	var id := int(p.get("id"))
	var craft: Node = main.craft
	if not result.is_empty():
		_give()
		return true
	var hand: int = craft.hands.get(id, -1)
	var ev := {"kind": "cook", "who": id, "slot": hand, "station": kind}
	if not craft.send(ev):
		return false
	who = id
	who_node = p
	item = ev.item
	_start = _k + 1
	_vis = Props.make(Food.pellet_glb(item.dish))
	_vis.scale = Vector3.ONE * 2.0
	main.add_child(_vis)
	_vis.global_position = p.global_position + Vector3.UP * 1.1 - p.global_basis.z * 0.35
	_vis.set_meta("from", _vis.global_position)
	var hud = main.get("hud")
	if hud:
		hud.learn("cook")
	return true


func _process(_dt: float) -> void:
	var fi := Doll.frame_index()
	if fi == _frame:
		return
	_frame = fi
	_k += 1
	_step_fx()
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
	# 2 拍（12 コマ）ごとに、台ごとぐっと沈む: 沈む 2 コマ・戻りすぎ 1 コマ・戻る
	var c := r % 12
	var sq: float = [0.9, 0.86, 1.04, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][c] if r > 0 else 1.0
	_squash(Vector3(1.0 + (1.0 - sq) * 0.5, sq, 1.0 + (1.0 - sq) * 0.5))
	if c == 0 and r > 0:
		var audio = main.get_node_or_null("Audio")
		if audio:
			audio.kitchen(_dev, "cook_press", -6.0, 3)
		_puff(_m("cook") + Vector3.UP * 0.3, 0.35)
		if _vis:   # 粒は押されて平たくなっていく
			var k := minf(1.0, r / 36.0)
			_vis.scale = Vector3(2.0 + k * 0.8, 2.0 - k * 1.1, 2.0 + k * 0.8)


func _iron(r: int) -> void:
	_squash(Vector3(1.0 + (0.01 if (r / 3) % 2 == 0 else -0.005), 1.0, 1.0))
	if r % 6 == 0:
		_puff(_m("cook") + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.1, 0.1)), 0.16)


func _dryer(r: int) -> void:
	_dev.transform = _rest
	_dev.rotate_object_local(Vector3.FORWARD, [0.015, -0.012, 0.01, -0.015][(r / 2) % 4])
	_dev.position += Vector3.UP * (0.02 if (r / 3) % 2 == 0 else 0.0)
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


func _finish() -> void:
	_dev.transform = _rest
	if _lid:
		_lid.rotation.x = 0.0
	if _bulge:
		_bulge.visible = false
	for p in [_music, _loop]:
		if p and is_instance_valid(p):
			p.queue_free()
	if _vis and is_instance_valid(_vis):
		var drum = _vis.get_meta("drum", null)
		if drum and is_instance_valid(drum):
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
	_give()


## 仕上がりを入れた人の手へ（持ち物がいっぱいなら、装置の上で待つ）
func _give() -> void:
	if result.is_empty():
		return
	var craft: Node = main.craft
	if not craft.send({"kind": "cooked", "who": who, "item": result, "station": kind}):
		return
	var to := who_node.global_position + Vector3.UP * 1.1 if is_instance_valid(who_node) else _vis.global_position
	var v := _vis
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
