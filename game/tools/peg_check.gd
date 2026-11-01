extends SceneTree
## ペグ（peg.gd・sled.gd の peg_to）の確かめ。買う → 坂でずり落ちるのを見る → 刺す → 止まる → 乗って雪をかく → 押す → 抜く → 滑り出す。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/peg_check.gd -- --sled=mid --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons
##   --at=頂上からの距離（既定 18）。--sled=sack|small|mid|large。--riders=乗る人の数（既定 1。大きいソリで多く）
## 絵を撮る（画面あり）:
##   Godot --path game --resolution 1280x720 -s res://tools/peg_check.gd -- --case=shot --out=/tmp/peg --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons
##   peg_1_hand.png（手にペグ、刺す所の案内）・peg_2_tied.png（刺さったペグと結んだ紐）・peg_3_rest.png（留めたソリに座って休む）・
##   peg_4_shop.png（売り台のペグの束）・peg_5_bag.png（持ち物の列のペグの束）

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var seat = null
var side := 1
var id := -1
func let_go() -> void:
	pass
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var player: CharacterBody3D
var craft: Node
var t := 0.0
var _step := 0
var _t0 := 0.0
var _at := Vector3.ZERO
var _riders: Array = []
var _fails := 0
var _dummy: GDScript


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _ok(what: String, ok: bool) -> void:
	print(("○ " if ok else "× ") + what)
	if not ok:
		_fails += 1


## 頂上から +Z（ふもと）へ r m の雪面に、前（-Z）を頂上へ向けて置く（押して登ってきて止めた形）
func _place(r: float) -> void:
	sled.reset_to(Vector3(0, main.height(0, r) + 0.3, r))
	sled.parked = false


## 引き紐の付け根の前（頂上の向き）に人を立たせる。ペグはその人の足もとの少し前に刺さる
func _stand_front(gap: float) -> void:
	var a: Vector3 = sled.rope_root()
	var p := Vector3(a.x, 0, a.z - gap)
	p.y = main.height(p.x, p.z) + 0.05
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.rotation.y = PI   # ふもと（+Z）を向く: 刺す所はソリの付け根と自分のあいだ


func _ride(n: int) -> void:
	for i in n:
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		if sled.mount(d) != Vector3.INF:
			_riders.append(d)


func _unride() -> void:
	for d in _riders:
		sled.dismount(d)
		d.queue_free()
	_riders.clear()


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null or main.player == null or t < 2.0:
		return false
	sled = main.sled
	player = main.player
	craft = main.craft
	if args.get("case", "flow") == "shot":
		_shot()
	else:
		_flow(dt)
	if t > 120.0:
		print("時間切れ")
		quit(1)
	return false


func _next() -> void:
	_step += 1
	_t0 = t


func _flow(_dt: float) -> void:
	var id: int = player.id
	var r := float(args.get("at", "18"))
	var nr := int(args.get("riders", "1"))
	match _step:
		0:
			print("ソリ %s、頂上から %.0f m（傾き %.2f）" % [sled.kind, r, (main.height(0, r - 1) - main.height(0, r + 1)) / 2.0])
			var w0: int = craft.wallet(id)
			var ok: bool = craft.send({"kind": "buy", "who": id, "item": {"kind": "peg", "n": 3}})
			var it: Dictionary = player.held()
			_ok("買う: ペグの束 %d 本、財布 %d → %d" % [int(it.get("n", 0)), w0, craft.wallet(id)], ok and it.get("kind") == "peg" and int(it.n) == 3 and craft.wallet(id) == w0 - craft.PEG_PRICE)
			craft.send({"kind": "buy", "who": id, "item": {"kind": "peg", "n": 3}})
			_ok("買い足すと同じ束に: %d 本、持ち物の数 %d" % [int(player.held().get("n", 0)), craft.count(id)], int(player.held().get("n", 0)) == 6 and craft.count(id) == 1)
			_place(r)
			_ride(nr)
			_at = sled.global_position
			_next()
		1:   # 留めないと、乗っていても誰も押さなければ…（空なら）ずり落ちる。乗ったまま前傾で雪をかくと進む
			for d in _riders:
				sled.lean(0.0, true)
			if t - _t0 > 3.0:
				var moved := sled.global_position.distance_to(_at)
				print("  留めないで 3 秒、乗って前傾: %.2f m 動いた（速さ %.2f）" % [moved, sled.linear_velocity.length()])
				_unride()
				_place(r)
				_next()
		2:
			if t - _t0 < 0.5:
				return
			_stand_front(1.0)
			var pt: Array = player.peg_target()
			_ok("刺す所が見つかる", not pt.is_empty() and pt[0] == sled)
			var n0 := int(player.held().get("n", 0))
			if not pt.is_empty():
				print("  刺す所から付け根まで %.2f m、ソリの速さ %.2f" % [pt[1].distance_to(sled.rope_root()), sled.linear_velocity.length()])
			_ok("刺す", player.plant_peg())
			_ok("刺さって紐を結んだ（ペグ %s、束 %d → %d 本）" % [sled.peg != null, n0, int(player.held().get("n", 0))], sled.peg != null and int(player.held().get("n", 0)) == n0 - 1)
			_ok("刺したソリの紐は持てない", not sled.take_rope(player))
			_ok("刺したソリにはもう刺せない", player.peg_target().is_empty())
			_at = sled.global_position
			_next()
		3:   # 空のまま 4 秒（滑っているところに刺したなら、止まるまでの 1 秒は数えない）
			if t - _t0 < 1.0:
				_at = sled.global_position
				return
			if t - _t0 > 5.0:
				var moved := sled.global_position.distance_to(_at)
				_ok("空で留めて 4 秒: %.3f m" % moved, moved < 0.1)
				_ride(nr)
				_at = sled.global_position
				_next()
		4:   # 乗って前傾・蹴る 4 秒（休んでいる人がうっかり W を押しても滑り出さない）
			for d in _riders:
				sled.lean(0.0, true)
				sled.kick(d)
			if t - _t0 > 4.0:
				var moved := sled.global_position.distance_to(_at)
				_ok("乗って（%d 人）前傾して 4 秒: %.3f m" % [_riders.size(), moved], moved < 0.3)
				_at = sled.global_position
				_next()
		5:   # 二人（--pushers）でふもとへ押す 3 秒: 紐のたるみの分だけ動き、張ったら止まる
			var a: Vector3 = sled.rope_root()
			for k in int(args.get("pushers", "2")):
				sled.push(Vector3(0, 0, 1), sled.global_position + Vector3(0.5 * (k * 2 - 1), 0, -1.0))
			if t - _t0 > 3.0:
				var len: float = sled.peg.tie_point().distance_to(a)
				_ok("ふもとへ押して 3 秒: %.2f m 動き、紐の付け根からペグまで %.2f m（紐 %.1f m）" % [sled.global_position.distance_to(_at), len, sled.ROPE_LEN],
						len < sled.ROPE_LEN + 0.25)
				_at = sled.global_position
				_next()
		6:   # 押すのをやめて 2 秒、また止まっている
			if t - _t0 > 2.0:
				var at2 := sled.global_position
				if t - _t0 > 4.0:
					_ok("押すのをやめると止まる: 2 秒で %.3f m" % at2.distance_to(_at), at2.distance_to(_at) < 0.1)
					_next()
				else:
					_at = at2
		7:   # 乗っている人が F でペグを抜く（届く所で）、滑り出す
			_t0 = t
			var n0 := int(player.held().get("n", 0))
			_stand_front(0.3)
			player.global_position = sled.peg.global_position + Vector3(0.6, 0.05, 0)
			var pg: RigidBody3D = player.peg_near()
			_ok("そばのペグが見つかる", pg == sled)
			_ok("抜く", player.pull_peg(sled))
			_ok("抜くとペグはなくなり、束は減らない（%d 本）" % int(player.held().get("n", 0)), sled.peg == null and int(player.held().get("n", 0)) == n0)
			_at = sled.global_position
			_next()
		8:
			for d in _riders:
				sled.lean(0.0, true)
			if t - _t0 > 4.0:
				var moved := sled.global_position.distance_to(_at)
				_ok("抜いて乗ったまま前傾 4 秒で滑り出す: %.1f m" % moved, moved > 2.0)
				_ok("抜いたペグは消えた", main.find_child("PulledPeg", true, false) == null)
				_ok("紐はまた持てる", sled.take_rope(player))
				sled.release_rope(player)
				_unride()
				# 束を使い切ると持ち物から消える
				_place(r)
				_next()
		9:
			if t - _t0 < 0.5:
				return
			var slot: int = craft.hands[id]
			craft.bags[id][slot]["n"] = 1
			_stand_front(1.0)
			player.plant_peg()
			_ok("最後の 1 本を刺すと束が持ち物から消える", craft.bags[id][slot].is_empty() and player.held().is_empty())
			_ok("通信の名前: %s" % craft.sled_path(sled), craft._sled_at(craft.sled_path(sled)) == sled)
			var snap: Dictionary = craft.snapshot()
			_ok("あとから来た人へ渡す中身にペグが入る", snap.pegs.size() == 1)
			main.reset_sled()
			_ok("ふもとへ戻すとペグはなくなる", sled.peg == null)
			print("おわり（× %d）" % _fails)
			quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- 絵

var _cam: Camera3D


func _snap(name: String) -> void:
	var dir := String(args.get("out", "/tmp/peg"))
	DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_texture().get_image()
	img.save_png(dir.path_join(name))
	print("撮った: ", dir.path_join(name))


func _look(from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55.0
		_cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)
		main.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at)
	_cam.current = true


func _shot() -> void:
	var id: int = player.id
	var cu = main.get("craft_ui")
	if cu and cu.gear_open:   # 窓が手前に出たときに打ったキーで、装備の画面が開くことがある
		cu.close_gear()
	var r := float(args.get("at", "18"))
	match _step:
		0:
			craft.send({"kind": "buy", "who": id, "item": {"kind": "peg", "n": 3}})
			_place(r)
			_next()
		1:
			if t - _t0 < 1.0:
				return
			_stand_front(1.6)
			player.set_third(false)
			_next()
		2:   # 一人称で手にペグ: ソリの前の雪を見下ろす
			player.set("_pitch", -0.55)
			if t - _t0 > 1.5:
				_snap("peg_1_hand.png")
				_stand_front(1.0)
				player.plant_peg()
				_next()
		3:
			if t - _t0 > 1.5:
				var p: Vector3 = sled.peg.global_position
				player.global_position += Vector3(2.5, 0, -1.5)
				_look(p + Vector3(1.1, 0.75, -0.9), p + Vector3(0, 0.2, 0.5))
				_next()
		4:
			if t - _t0 > 1.0:
				_snap("peg_2_tied.png")
				# 座って休む: あなたが乗る（三人称で、横から）
				player.global_position = sled.global_position + sled.global_basis.x * 1.4
				player.get_on()
				player.set_third(true)
				_next()
		5:
			if t - _t0 > 2.5:
				var s := sled.global_position
				_look(s + Vector3(5.5, 2.6, -3.5), s + Vector3(0, 0.4, -1.4))
				_next()
		6:
			if t - _t0 > 1.0:
				_snap("peg_3_rest.png")
				print("乗ったまま F で抜けるペグ: %s（ペグまで %.1f m）" % [player.peg_near() == sled, sled.peg.global_position.distance_to(player.global_position)])
				_cam.current = false
				player.get_off()
				_next()
		7:
			if t - _t0 > 0.5:
				player.global_position = main.shopkeeper.global_position + main.shopkeeper.global_basis.z * -1.5
				main.craft_ui.open_shop()
				main.craft_ui.select(main.craft_ui._goods.size() - 1)
				_next()
		8:
			if t - _t0 > 1.0:
				_snap("peg_4_shop.png")
				main.craft_ui.close_shop()
				_next()
		9:
			if t - _t0 > 1.0:
				_snap("peg_5_bag.png")
				quit()
