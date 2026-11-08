extends RefCounted
## 山をめぐる仲間（CPU）の、ロッジへの寄り道（bot.gd の visit。2026-11-09 代表「ロッジで休憩したり買い物したりいろんなオブジェクトを使う挙動も
## 追加してほしい。MAXまで濡れたら帰ってきたり、2階でゆっくりしたりもしてほしい」）。
## 次の山を選ぶときに、ときどき（bot.gd の visit_odds）ロッジへ寄る。水のゲージ（damp.gd）がいっぱい（HI）になったら、
## 歩いて向かっている山をやめて、必ず帰ってくる（滑っている途中なら、滑り終えてから）。
## 寄り道ですること（1 階の物を先に、2 階の物をあとに。2〜3 個。濡れて帰ってきたときは乾かすのが先）:
##   dry       暖炉のまわりの席（空いていなければ 1 階のどこかの席）で、水が 0 になるまで座る（ロッジの中で乾く。damp.gd）
##   rest      1 階の席（食堂の椅子・窓辺の丸椅子・暖炉のまわり）に座って休む
##   kotatsu   内階段で 2 階へ上がり、こたつの座布団でゆっくりする
##   lantern   紙細工屋さんでランタンを買う。pal  同じ売り台で頭・肩の小物かミニオンを買う（お金が足りなければ眺めるだけ）
##   wardrobe  人台で人形を替える。dye  染め桶で服を染める。mirror  大きな鏡を見る。book  布の見本帳を眺める。shop・mountain  売り子の棚を眺める
## 座る・立つ・買う・着替える・染めるは、人と同じ出来事（seats.gd の sit・stand、craft.gd の lantern_buy・pal_buy・doll・dye）。
## 座りに行く所からは、ロッジでくつろぐ仲間と同じ動き（bot.gd の _lounge）。
## 見本帳と型紙・布の売り子の棚は、西の壁の外の下屋にあるので、中へ入る前（ロッジの外 = 0 階）に寄る。
## 道（ロッジの座標）: 風除室の前 OUT → 風除室 → 食堂の入口 IN。2 階へは内階段の上り口 FOOT → 踊り場 → 2 階 TOP → HUB2。
## 1 階の中は点へまっすぐ歩き、近づけなければ当たりを調べて回り込む（bot.gd の _steer_to）。階段はまっすぐ。2 階は畳の小上がりへ段を上がり、
## こたつは少しずつ向きを振ってよける（bot.gd の _detour）。点に WARP_T 秒近づけなければ、その点へ体を移す（詰まって止まらない。数は warps）

const Damp := preload("res://damp.gd")
const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")
const Doll := preload("res://doll.gd")

const FL1 := 0.45            # 1 階の床（ロッジの座標の高さ。lodge/dims.py の FL1）
const LAND := 3.18           # 内階段の踊り場
const FL2 := 6.1             # 2 階の床
const OUT := Vector3(-13.4, 0.0, 28.0)      # 風除室の前の広場（高さは地面）
const V_OUT := Vector3(-13.4, FL1, 19.0)    # 風除室の外の戸の前
const V_MID := Vector3(-13.4, FL1, 15.0)    # 風除室のまんなか
const IN := Vector3(-13.4, FL1, 11.0)       # 食堂の入口（内の自動ドアの内）
const BELOW := Vector3(18.0, FL1, -1.0)     # 内階段の上り口の手前（食堂の北の通り）
const FOOT := Vector3(18.0, FL1, -5.5)      # 1 本目の上り口
const LAND1 := Vector3(18.0, LAND, -11.0)   # 踊り場（1 本目の上）
const LAND2 := Vector3(20.5, LAND, -11.0)   # 踊り場（2 本目の下）
const TOP := Vector3(20.5, FL2, -4.5)       # 2 本目を上がりきった 2 階の床
const HUB2 := Vector3(17.5, FL2, -2.0)      # 2 階の階段の前（ここから畳の小上がりへ）

const WALLS := Vector2(21.8, 12.7)     # 1 階の壁の内（ロッジの座標の x, z の半分の幅）。この外の物は外から寄る
const COOL := Vector2(120.0, 300.0)   # 寄り道してから、次に寄り道を考えるまで (s)
const WET_LOOK := 1.0        # 濡れきったかを見直す間 (s)
const WARP_T := 8.0          # 点へ近づけないでいるのがこれだけ続いたら、その点へ体を移す (s)
const SEAT_NEAR := 2.5       # 座る席のそばまでは道を探して歩き、そこからはくつろぐ仲間の歩き方 (m)
const DRY_MAX := 300.0       # 乾かす長さの上限 (s)
const REST_T := Vector2(20.0, 45.0)     # 1 階の席で休む長さ (s)
const KOTATSU_T := Vector2(40.0, 90.0)  # こたつでゆっくりする長さ (s)
const LOOK_T := Vector2(4.0, 9.0)       # 物を眺める・使う長さ (s)
const HEARTH := ["sofa", "rocker", "beanbag"]
const REST_KINDS := ["chair", "stool", "bench", "sofa", "rocker", "beanbag"]
const POOL := ["rest", "kotatsu", "lantern", "pal", "wardrobe", "dye", "mirror", "book", "shop", "mountain"]

var b                        # 仲間（bot.gd）
var inside := false          # 寄り道の途中（ロッジの前に着いてから、外へ出るまで。下屋の物に寄っているときも）
var leaving := false         # 外へ出る道を歩いている
var reason := ""             # "wet" 濡れきって帰ってきた、"rest" 気まぐれ
var level := 0               # いる階（0 ロッジの外・1・2）
var plan: Array = []         # これからすること [{kind, floor（階）, ...}]
var task := {}               # いましていること
var route: Array = []        # 歩く点 [{at（世界）, mode: nav・line・stair, near}]
var cool := 0.0              # 次に寄り道を考えるまで (s)
var warps := 0               # 確かめ用: 点へ体を移した回数
var visits := 0              # 確かめ用: 寄り道した回数
var done: Array = []         # 確かめ用: したこと（最近の 20 個）[名前]
var _best := INF
var _stall := 0.0
var _wet_t := 0.0


func _init(bot) -> void:
	b = bot
	cool = randf_range(20.0, 90.0)   # はじめから一斉に入らないように


func _lodge() -> Node3D:
	return b.get_parent().get_node_or_null("Lodge")


func water() -> float:
	var dm = b.get_parent().get_node_or_null("Damp")
	return dm.water_of(b.id) if dm and b.id >= 0 else 0.0


func wet() -> bool:
	return water() >= Damp.HI - 0.5


## 寄り道の途中（歩いて向かっているときも）。ほかの仲間の雪合戦・ソリ運びに誘われない
func busy() -> bool:
	return inside or b._area == "lodge"


## 毎コマ（bot.gd の _physics_process。山をめぐる仲間だけ）。歩いて山へ向かっている途中で濡れきったら、やめて帰る
func tick(dt: float) -> void:
	cool = maxf(0.0, cool - dt)
	_wet_t -= dt
	if _wet_t > 0.0 or inside:
		return
	_wet_t = WET_LOOK
	if b._area in b.ROAM_AREAS and b.state != b.State.RIDE and b._team.is_empty() and b._help_t <= 0.0 \
			and b.handle == Vector3.INF and wet():
		b._roam_done()
		b._roam_rest = 0.5


## 次の山を選ぶ前に（bot.gd の _roam_walk）: 寄り道するなら、ロッジの前へ歩き出して true
func want() -> bool:
	var lodge := _lodge()
	if lodge == null or b.seats == null:
		return false
	var soaked := wet()
	if not soaked and (cool > 0.0 or randf() > b.visit_odds):
		return false
	reason = "wet" if soaked else "rest"
	var o := _out_point()
	b._area = "lodge"
	b._route = [Vector2(o.x, o.z)]
	b._wp_best = INF
	b._wp_t = 0.0
	b._nav_clear()
	return true


func _out_point() -> Vector3:
	var o := _lodge().to_global(OUT)
	o.y = b.get_parent().height(o.x, o.z)
	return o


## ロッジの前に着いた（bot.gd の _roam_walk）: 風除室を通って中へ。することを決める
func enter() -> void:
	inside = true
	leaving = false
	level = 0
	visits += 1
	b.far = false
	b._ghost = false
	b._col.disabled = false
	b._nav_clear()
	route = []
	plan = _plan()
	task = {}
	_reset_walk()


## ロッジの座標の点を、歩く点に
func _p(local: Vector3, mode: String, near := 0.5) -> Dictionary:
	return {"at": _lodge().to_global(local), "mode": mode, "near": near}


func _plan() -> Array:
	var out: Array = []
	if reason == "wet":
		out.append({"kind": "seat", "what": "dry", "floor": 1})
	var pool := POOL.duplicate()
	pool.shuffle()
	var n := (randi_range(0, 1) if reason == "wet" else randi_range(2, 3)) + out.size()
	for k in pool:
		if out.size() >= n:
			break
		var t := _task_of(k)
		if not t.is_empty():
			out.append(t)
	# 外（下屋）→ 1 階 → 2 階の順（階段の上り下りは 1 往復まで）。濡れて帰ってきたら、乾かすのがいちばん先で、外のことは帰りがけに
	var order := [1, 2, 0] if reason == "wet" else [0, 1, 2]
	var sorted: Array = out.filter(func(t): return t.get("what") == "dry")
	for lv in order:
		sorted += out.filter(func(t): return t.floor == lv and t.get("what") != "dry")
	return sorted


func _task_of(k: String) -> Dictionary:
	var w = b.get_parent()
	match k:
		"rest":
			return {"kind": "seat", "what": "rest", "floor": 1}
		"kotatsu":
			return {"kind": "seat", "what": "kotatsu", "floor": 2}
		"lantern", "pal":
			return _spot(k, w.get("paper_lady"), Vector3(0.6, 0.1, 2.2), Vector3(0.6, 0.0, 0.0))
		"wardrobe":
			return _spot(k, w.get("wardrobe"), Vector3(0, 0.1, 2.6), Vector3.ZERO)
		"dye":
			return _spot(k, w.get("dye_vat"), Vector3(0, 0.1, 2.6), Vector3.ZERO)
		"mirror":
			return _spot(k, w.get("mirror"), Vector3(0, 0.1, 3.2), Vector3.ZERO)
		"book":
			return _spot(k, w.get("sled_book"), Vector3(0, 0.1, 2.6), Vector3.ZERO)
		"shop":
			return _spot(k, w.get("shopkeeper"), Vector3(0, 0.1, -1.9), Vector3.ZERO)
		"mountain":
			return _spot(k, w.get("mountain_man"), Vector3(0, 0.1, -1.9), Vector3.ZERO)
	return {}


## 物の前に立つこと。立つ所と見る所は、人が F で使うときと同じ（main.gd の --spawn の所）
func _spot(k: String, node, stand: Vector3, look: Vector3) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var at: Vector3 = node.to_global(stand)
	var l: Vector3 = _lodge().to_local(at)
	if l.y > FL2 + 2.0:
		return {}
	var lv := 2 if l.y > LAND else (1 if absf(l.x) < WALLS.x and absf(l.z) < WALLS.y else 0)
	return {"kind": "spot", "what": k, "at": at, "look": node.to_global(look) + Vector3.UP * 1.0, "floor": lv}


## 寄り道の 1 コマ（bot.gd の _physics_process。inside のあいだ）
func step(dt: float) -> void:
	b.far = false
	if b.lounge:   # 座りに行く・座っている（ロッジでくつろぐ仲間と同じ動き。立ちきったら seat_done）
		b._lounge(dt)
		return
	if not route.is_empty():
		if _walk(route[0], dt):
			route.pop_front()
			_reset_walk()
		return
	if leaving:
		_finish()
		return
	if task.is_empty():
		if plan.is_empty():
			_go_out()
			b._settle_walk(Vector3.ZERO, dt)
			return
		task = plan.pop_front()
		if task.floor != level:
			route = _between(level, task.floor)
			level = task.floor
		b._settle_walk(Vector3.ZERO, dt)
		return
	if task.kind == "seat":
		_seat_step(dt)
	else:
		_spot_step(dt)


## 階から階への道（0 外・1・2）: 外と 1 階は風除室を通り、1 階と 2 階は内階段を通る
func _between(from: int, to: int) -> Array:
	if from == to:
		return []
	if from == 0:
		return [{"at": _out_point(), "mode": "nav", "near": 1.0}, _p(V_OUT, "line"), _p(V_MID, "line"), _p(IN, "line")] + _between(1, to)
	if to == 0:
		return _between(from, 1) + [_p(IN, "nav"), _p(V_MID, "line"), _p(V_OUT, "line"), {"at": _out_point(), "mode": "line", "near": 1.0}]
	if to == 2:
		return [_p(BELOW, "nav"), _p(FOOT, "stair"), _p(LAND1, "stair"), _p(LAND2, "stair"), _p(TOP, "stair"), _p(HUB2, "line")]
	return [_p(HUB2, "line"), _p(TOP, "stair"), _p(LAND2, "stair"), _p(LAND1, "stair"), _p(FOOT, "stair"), _p(BELOW, "stair")]


## 外へ（2 階なら階段を下りて、食堂の入口 → 風除室 → 広場）。外にいれば、そこから山めぐりへ
func _go_out() -> void:
	leaving = true
	route = _between(level, 0)
	level = 0


## 外に出た: 山めぐりへ戻る
func _finish() -> void:
	inside = false
	leaving = false
	level = 0
	task = {}
	plan = []
	cool = randf_range(COOL.x, COOL.y)
	b._roam_done()


## 点へ歩く。着いたら true。近づけないでいるのが WARP_T 続いたら、その点へ体を移して true
func _walk(p: Dictionary, dt: float) -> bool:
	var w: Vector3 = p.at
	var pos: Vector3 = b.global_position
	var gap := Vector2(pos.x, pos.z).distance_to(Vector2(w.x, w.z))
	if gap < float(p.near) and absf(pos.y - w.y) < 1.2:
		return true
	_stall += dt
	if gap < _best - 0.3:
		_best = gap
		_stall = 0.0
	if _stall > WARP_T:
		warps += 1
		b.global_position = w + Vector3.UP * 0.1
		b.velocity = Vector3.ZERO
		b.reset_physics_interpolation()
		return true
	var to := w - pos
	to.y = 0
	var dir := to.normalized()
	match String(p.mode):
		"nav":
			b._wp_t = _stall
			dir = b._steer_to(Vector2(w.x, w.z), dt)
		"line":
			dir = b._detour(dir)
	b._indoor_walk(dir, dt)
	return false


func _reset_walk() -> void:
	_best = INF
	_stall = 0.0
	b._nav_clear()


# ---------------------------------------------------------------- 座る

func _seat_step(dt: float) -> void:
	var seats = b.seats
	if not task.has("seat"):
		task["tries"] = int(task.get("tries", 0))
		var i := _pick_seat()
		if i < 0:
			_task_done()
			b._settle_walk(Vector3.ZERO, dt)
			return
		task["seat"] = i
		_reset_walk()
	var i: int = task.seat
	if seats.taken.has(i):   # 先に座られた: 選び直す
		task.erase("seat")
		task.tries += 1
		b._settle_walk(Vector3.ZERO, dt)
		return
	var st: Dictionary = seats.seat(i)
	var mode := "nav" if level == 1 else "line"
	if _walk({"at": st.stand, "mode": mode, "near": SEAT_NEAR}, dt):
		_reset_walk()
		b._lounge_to(i)   # ここからは、くつろぐ仲間と同じに歩み寄って座る
		b.lounge = true


## 座る席: 乾かすなら暖炉のまわり（空いていなければ 1 階のどこか）、休むなら 1 階の席、こたつなら 2 階の座布団。近い 8 席から気まぐれに
func _pick_seat() -> int:
	var seats = b.seats
	if int(task.get("tries", 0)) > 2:
		return -1
	var at: Vector3 = b.global_position
	var list: Array = []
	match String(task.what):
		"dry":
			list = seats.free_near(at, 8, 60.0, HEARTH)
			if list.is_empty():
				list = seats.free_near(at, 8, 60.0, REST_KINDS)
		"rest":
			list = seats.free_near(at, 8, 40.0, REST_KINDS)
		"kotatsu":
			list = seats.free_near(at, 8, 40.0, ["zabuton"])
	list = list.filter(func(j): return j != b._left)
	return list[randi() % list.size()] if not list.is_empty() else -1


## くつろぐ仲間の歩き方で席へ寄れなかった（bot.gd の _lounge が選び直すとき）。-1 ならあきらめる
func repick() -> int:
	task["tries"] = int(task.get("tries", 0)) + 1
	var i := _pick_seat()
	if i >= 0:
		task["seat"] = i
	return i


## 座った: 座っている長さ
func sit_time() -> float:
	match String(task.get("what", "")):
		"kotatsu":
			return randf_range(KOTATSU_T.x, KOTATSU_T.y)
		"dry":
			return 5.0
	return randf_range(REST_T.x, REST_T.y)


## 座り続ける（乾かしているあいだ）
func hold_seat(dt: float) -> bool:
	if String(task.get("what", "")) != "dry":
		return false
	task["sat"] = float(task.get("sat", 0.0)) + dt
	return water() > 0.0 and float(task.sat) < DRY_MAX


## 立ちきった・座れなかった（bot.gd の _lounge）
func seat_done() -> void:
	b.lounge = false
	_task_done()


func _task_done() -> void:
	if not task.is_empty():
		done.append(String(task.get("what", "")))
		if done.size() > 20:
			done.pop_front()
	task = {}
	_reset_walk()


# ---------------------------------------------------------------- 物を使う・眺める

func _spot_step(dt: float) -> void:
	var what := String(task.what)
	if not task.has("t"):
		if not task.has("claimed"):
			if _spot_taken(task.at):
				_task_done()   # ほかの仲間がその前にいる（人台・染め桶・鏡のように、立つ所が近い物も）
				b._settle_walk(Vector3.ZERO, dt)
				return
			task["claimed"] = true
		if _walk({"at": task.at, "mode": "line" if level == 2 else "nav", "near": 0.4}, dt):
			task["t"] = randf_range(LOOK_T.x, LOOK_T.y)
			_use(what)
		return
	task.t -= dt
	b._stand_look(task.look, dt)
	if task.t <= 0.0:
		_task_done()


## 物の前に着いた: 人と同じ出来事で、買う・着替える・染める（できなければ眺めるだけ）
func _use(what: String) -> void:
	var craft = b.craft
	var id: int = b.id
	var ok := false
	match what:
		"lantern":
			var looks := Lantern.LOOKS.filter(func(l): return craft.lantern_index(id, l) < 0 and Lantern.price(l) >= 0 and Lantern.price(l) <= craft.wallet(id))
			if not looks.is_empty():
				ok = craft.send({"kind": "lantern_buy", "who": id, "look": looks[randi() % looks.size()]})
		"pal":
			var keys: Array = []
			for s in Pals.SLOTS:
				keys += Pals.keys_of(s).filter(func(k): return not craft.pal_owned(id, k) and Pals.price(k) >= 0 and Pals.price(k) <= craft.wallet(id))
			if not keys.is_empty():
				ok = craft.send({"kind": "pal_buy", "who": id, "key": keys[randi() % keys.size()]})
		"wardrobe":
			var kinds := Doll.KINDS.filter(func(k): return k != b.doll.kind)
			var to: String = kinds[randi() % kinds.size()]
			ok = craft.send({"kind": "doll", "who": id, "doll": to})
			if ok and craft.outfit_of(id, to).is_empty():   # まだ染めていない人形なら、パレットから染める
				b.random_outfit(to)
		"dye":
			var cols := []
			for i in 4:
				cols.append(Color.from_hsv(randf(), randf_range(0.3, 0.8), randf_range(0.5, 0.95)).to_html(false))
			ok = craft.send({"kind": "dye", "who": id, "doll": b.doll.kind, "colors": cols})
	task["used"] = ok
	if b.hub:
		b.hub.send({"kind": "wa" if ok else "un", "who": id})


## ほかの仲間が、そばの物の前へ向かっている・立っている
func _spot_taken(at: Vector3) -> bool:
	for o in b.get_tree().get_nodes_in_group("bots"):
		if o == b or o.visit == null or not o.visit.inside:
			continue
		var t: Dictionary = o.visit.task
		if t.get("kind") == "spot" and t.has("claimed") and (t.at as Vector3).distance_to(at) < 1.5:
			return true
	return false
