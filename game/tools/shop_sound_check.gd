extends SceneTree
## お金を払う所ごとに、買った人の前で買い、鳴った音を数で出す（買い物の完了音の確かめ。2026-11-09）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/shop_sound_check.gd -- --bots=0 --no-pip
## 施設ごとに、買った人を店の前（店と同じ側: ロッジの中か外か）に立たせて出来事を送り、そのあと WAIT 秒のあいだに
## 新しくできた音の口を全部見張る。1 行に 1 つの音:
##   名前・バス・始まり（買ってからの秒）・終わり（finished が来たか / 途中で消えたか）・聞く所からの距離・
##   聞こえる大きさの見積もり（音の口の dB + 距離の減り + バスの道の dB。600 Hz より低いこもりがあれば印）
## 最後に施設ごとに「完了音（店の音: pay_/till_/wrap_、または purchase の音）が鳴ったか・最後まで鳴ったか・いちばん大きい音の dB」を表で出す

const WAIT := 2.6

var main: Node3D
var audio: Node
var craft: Node
var p: CharacterBody3D
var _recs: Array = []      # {node, name, bus, start, end, freed, dist, est, muffle}
var _t_case := 0.0
var _watch := false
var _rows: Array = []


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	node_added.connect(_on_added)
	_run.call_deferred()


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


func _wait(sec: float) -> void:
	var until := _now() + sec
	while _now() < until:
		await physics_frame
		_poll()


func _on_added(n: Node) -> void:
	if not _watch or not (n is AudioStreamPlayer or n is AudioStreamPlayer3D):
		return
	var r := {"node": n, "name": "", "bus": "", "start": -1.0, "end": -1.0, "freed": -1.0, "dist": 0.0, "est": -INF, "muffle": 0.0, "pos": Vector3.INF}
	_recs.append(r)
	n.finished.connect(func() -> void:
		if r.end < 0.0:
			r.end = _now() - _t_case)
	n.tree_exiting.connect(func() -> void:
		if r.freed < 0.0:
			r.freed = _now() - _t_case)


func _poll() -> void:
	for r in _recs:
		var n = r.node
		if not is_instance_valid(n) or r.start >= 0.0:
			continue
		if n.playing:
			r.start = _now() - _t_case
			r.name = _name_of(n.stream)
			r.bus = String(n.bus)
			var est := _estimate(n)
			r.dist = est[0]
			r.est = est[1]
			r.muffle = est[2]
			if n is AudioStreamPlayer3D:
				r.pos = n.global_position


func _name_of(s: AudioStream) -> String:
	for k in audio._streams:
		if audio._streams[k] == s:
			return String(k)
	return "?"


## 聞く所（Godot の 3D の音は、いまのカメラの所で聞く）
func _ear() -> Vector3:
	var cam := main.get_viewport().get_camera_3d()
	return cam.global_position if cam else audio._listener()


## [距離, 聞こえる大きさの見積もり dB, いちばん低いこもりの Hz（なければ 0）]
func _estimate(n: Node) -> Array:
	var db: float = n.volume_db
	var dist := 0.0
	if n is AudioStreamPlayer3D:
		var lis: Vector3 = _ear()
		dist = lis.distance_to(n.global_position)
		if n.max_distance > 0.0 and dist > n.max_distance:
			return [dist, -INF, 0.0]
		var r := maxf(dist / n.unit_size, 0.0001)
		match n.attenuation_model:
			AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE:
				db += linear_to_db(1.0 / r)
			AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE:
				db += linear_to_db(1.0 / (r * r))
			AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC:
				db += -20.0 * log(r) / log(10.0)
		db = minf(db, n.max_db)
	var muffle := 0.0
	var bus := String(n.bus)
	var guard := 0
	while bus != "" and guard < 8:
		guard += 1
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			break
		db += AudioServer.get_bus_volume_db(i)
		for k in AudioServer.get_bus_effect_count(i):
			var e := AudioServer.get_bus_effect(i, k)
			if e is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(i, k):
				var c: float = (e as AudioEffectLowPassFilter).cutoff_hz
				muffle = c if muffle == 0.0 else minf(muffle, c)
		bus = String(AudioServer.get_bus_send(i)) if bus != "Master" else ""
	return [dist, db, muffle]


## 店の前に立たせる。at は店の節。ロッジの座標で 4 方へずらして、店と同じ側（中か外か）でいちばん近い所
func _stand_near(at: Node3D) -> void:
	var lodge: Node3D = main.get_node("Lodge")
	var l := lodge.to_local(at.global_position)
	var zone: int = audio.zone_at(lodge, at.global_position)
	var best := Vector3.INF
	for off in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(2.0, 0, 0), Vector3(0, 0, 2.0), Vector3(-2.0, 0, 0), Vector3(0, 0, -2.0)]:
		var g := lodge.to_global(l + off)
		if audio.zone_at(lodge, g + Vector3.UP * 0.3) == zone:
			best = g
			break
	if best == Vector3.INF:
		best = lodge.to_global(l + Vector3(1.4, 0, 0))
	if zone == 0 and l.y < 3.0:   # 外の雪の上
		best.y = maxf(best.y, main.height(best.x, best.z)) + 0.15
	else:
		best.y += 0.15
	p.global_position = best
	p.velocity = Vector3.ZERO
	print("   立つ所: %s（%s）店まで %.1f m" % [best, ["外", "風除室", "中"][audio.zone_at(lodge, best + Vector3.UP * 0.3)], best.distance_to(at.global_position)])


func _case(label: String, at: Node3D, send: Callable) -> void:
	print("\n== ", label)
	if at == null:
		print("   店が見つからない")
		_rows.append([label, "店なし", "", ""])
		return
	_stand_near(at)
	await _wait(0.6)
	_recs.clear()
	_watch = true
	_t_case = _now()
	var ok = send.call()
	print("   送った: ", ok, "  人 ", p.global_position, "  カメラ ", _ear(), "  店 ", at.global_position)
	await _wait(WAIT)
	_watch = false
	var shop_sound := false
	var whole := true
	var loud := -INF
	for r in _recs:
		if r.start < 0.0:
			continue
		var shop: bool = String(r.name).begins_with("pay_") or String(r.name).begins_with("till_") or String(r.name).begins_with("wrap_") \
				or String(r.name).begins_with("button_") or String(r.name).begins_with("brass") or String(r.name).begins_with("pearl")
		var cut: bool = r.freed >= 0.0 and r.end < 0.0
		if r.pos != Vector3.INF and not _at_counter(r.pos):
			shop = false   # 店の台の上で鳴っていない音（ミシンなど、ほかの音）
		if shop:
			shop_sound = true
			loud = maxf(loud, r.est)
			if cut:
				whole = false
		print("   %5.2f s %s %-18s %-10s 距離 %5.1f m  見積 %6.1f dB%s  %s" % [r.start, "★" if shop else " ", r.name, r.bus, r.dist, r.est,
				"  こもり %d Hz" % int(r.muffle) if r.muffle > 0.0 and r.muffle < 2000.0 else "",
				"途中で消えた" if cut else ("終わり %.2f s" % r.end if r.end >= 0.0 else "まだ鳴っている")])
	_rows.append([label, "鳴った" if shop_sound else "鳴らない", ("最後まで" if whole else "途中で切れた") if shop_sound else "-",
			"%.1f dB" % loud if shop_sound else "-"])


## 買った音が鳴る所（直す前も後も、店の節の 0.95 m 上）か
func _at_counter(pos: Vector3) -> bool:
	var lodge: Node3D = main.get_node("Lodge")
	var spots: Array = main.binocular_stands.duplicate()
	for nm in ["Bandai_counter_patch", "Bandai_counter_indigo", "PaperLady", "MountainMan", "SledBook", "DyeVat"]:
		var c := lodge.find_child(nm, true, false) as Node3D
		if c:
			spots.append(c)
	for c in spots:
		if pos.distance_to(c.global_position + Vector3.UP * 0.95) < 0.3:
			return true
	return false


func _run() -> void:
	for i in 20:
		await process_frame
	p = main.player
	audio = main.get_node_or_null("Audio")
	craft = main.craft
	if p == null or audio == null or craft == null:
		print("あなた・音・工房のどれかがない（--no-player・--no-sound を付けない）")
		quit(1)
		return
	var me: int = p.id
	craft.wallets[me] = 5000
	main.emotes._set_balls(me, 20)
	await _wait(0.5)
	# ソリ屋（外の下屋のおじいさん）: 布・型紙・滑りあとの柄
	await _case("ソリ屋で布を買う", main.shopkeeper, func(): return craft.send({"kind": "buy", "who": me, "item": {"kind": "fabric", "fabric": "red"}}))
	await _case("ソリ屋で滑りあとの柄を買う", main.shopkeeper, func(): return craft.send({"kind": "stitch_buy", "who": me, "stitch": _a_stitch(me)}))
	# 見本帳（外の立てかけ台の横）: 柄を買う・米袋を染める
	await _case("見本帳で滑りあとの柄を買う", main.sled_book, func(): return craft.send({"kind": "stitch_buy", "who": me, "stitch": _a_stitch(me)}))
	await _case("見本帳で米袋を染める", main.sled_book, func():
		return craft.send({"kind": "sled_dye", "who": me, "color": preload("res://fabrics.gd").dyed_name(Color(0.2, 0.5, 0.8)), "sack": 0}))
	# 山師（1 階）: 道具・ミニオン
	await _case("山師で焚き火セットを買う", main.mountain_man, func(): return craft.send({"kind": "buy", "who": me, "item": preload("res://campfire.gd").ITEM.duplicate()}))
	await _case("山師でミニオンを買う", main.mountain_man, func():
		var Pals := preload("res://pals.gd")
		for k in Pals.PET:
			if Pals.price(k) > 0 and not craft.pal_owned(me, k):
				return craft.send({"kind": "pal_buy", "who": me, "key": k})
		return false)
	# 紙細工屋さん（1 階のテント）: 小物・提灯
	await _case("紙細工屋さんで小物を買う", main.paper_lady, func():
		var Pals := preload("res://pals.gd")
		for k in Pals.PERCH_ORDER:
			if Pals.price(k) > 0 and not craft.pal_owned(me, k):
				return craft.send({"kind": "pal_buy", "who": me, "key": k})
		return false)
	await _case("紙細工屋さんで提灯を買う", main.paper_lady, func():
		var Lantern := preload("res://lantern.gd")
		for k in Lantern.LOOKS:
			if Lantern.price(k) > 0 and craft.lantern_index(me, k) < 0:
				return craft.send({"kind": "lantern_buy", "who": me, "look": k})
		return false)
	# 人台の桶（1 階）: 服を染める
	await _case("染台で服を染める", main.dye_vat, func():
		var k: String = craft.dolls.get(me, "")
		var n: int = preload("res://outfit.gd").cloth_count(k)
		var cols := []
		for i in n:
			cols.append(Color(0.8, 0.2 + 0.05 * i, 0.3))
		return craft.send({"kind": "dye", "who": me, "doll": k, "colors": craft.dye_colors(k, cols)}))
	# 雪だるまの番台（食堂）: ペレットを雪玉で買う
	var sh = main.get("snowman_shop")
	await _case("雪だるまの番台でペレットを買う", sh.counter if sh else null, func():
		return craft.send({"kind": "food_buy", "who": me, "item": preload("res://food.gd").item("onigiri")}))
	# 双眼鏡台（テラス）: 木のボタン 1 枚で払う・雪玉 1 個で払う。のぞくとカメラが台へ移るので最後に
	main.emotes._set_balls(me, 0)
	var st: Node3D = main.binocular_stands[0] if main.binocular_stands.size() > 0 else null
	await _case("双眼鏡台（ボタンで払う）", st, func(): return craft.send({"kind": "scope_on", "who": me, "stand": 0}))
	var st2: Node3D = main.binocular_stands[1] if main.binocular_stands.size() > 1 else null
	p.peek_stop()
	await _wait(0.5)
	main.emotes._set_balls(me, 3)
	await _case("双眼鏡台（雪玉で払う）", st2, func(): return craft.send({"kind": "scope_on", "who": me, "stand": 1}))
	print("\n== 表（施設 / 完了音 / 最後まで / いちばん大きい音の見積もり）")
	for r in _rows:
		print("   %-24s %-6s %-8s %s" % r)
	quit(0)


func _a_stitch(me: int) -> String:
	var Stitches := preload("res://stitches.gd")
	for nm in Stitches.LIST:
		if Stitches.price(nm) > 0 and not nm in craft.stitch_owned.get(me, []):
			return nm
	return ""
