extends SceneTree
## こたつの布団（kotatsu_futon.gd）の確かめ: どの席に座っても、座った人の席の前の布団だけがめくれるか。
##   Godot --path game --resolution 960x540 -s res://tools/kotatsu_futon_check.gd -- --bots=0 --lodge-bots=0 --no-sound [--kinds=musha,golem,...]
## 1 卓のこたつで次を順に確かめ、めくれる席の組を出す。違えば NG を出して終わりのコードを 1 にする。
##   1 人ずつ: 8 席のそれぞれに 1 人座る → その席だけ
##   隣どうし: 長い辺の隣り合う席に 2 人 → その 2 席だけ
##   立つ: 人形を立たせる → どの席もめくれない
## 席の番号は組の目印 sit_0〜7（0〜2 と 3〜5 が長い辺、6・7 が短い辺）
## 通信: 2 つの画面で、本物のあなたが隣どうしに座って立つ。どちらの画面でも、めくれる席とめくれ方（席・お腹の前・膝の高さ）を出す。
##   Godot --path game --resolution 960x540 -s res://tools/kotatsu_futon_check.gd -- --host --port=24697 --spawn=inside --bots=0 --lodge-bots=0 --no-sound
##   Godot --path game --resolution 960x540 -s res://tools/kotatsu_futon_check.gd -- --join=127.0.0.1 --port=24697 --spawn=inside --bots=0 --lodge-bots=0 --no-sound

const Doll := preload("res://doll.gd")
const PAIRS := [[0, 1], [1, 2], [3, 4], [4, 5]]

var args := {}
var main: Node3D
var ng := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _run() -> void:
	await create_timer(3.0).timeout
	var seats = main.get("seats")
	while seats == null or seats.seats.is_empty():
		await process_frame
		seats = main.get("seats")
	if not (args.has("host") or args.has("join")):
		for c in main.get_children():   # ゲームの人（あなた・仲間）は数えない
			if c.get("doll") != null:
				c.visible = false
	var kset := main.find_child("KotatsuFuton", true, false).get_parent() as Node3D
	var futon = kset.get_node("KotatsuFuton")
	# 組の目印 sit_<番号> → 席（seats.gd の並びは別なので、目印にいちばん近い席）
	var seat_of := {}
	for k in 8:
		var mark := kset.find_child("sit_%d" % k, true, false) as Node3D
		var best := -1
		var best_d := INF
		for i in seats.seats.size():
			if seats.seat(i).kind == "zabuton":
				var d: float = seats.seat(i).pos.distance_to(mark.global_position)
				if d < best_d:
					best_d = d
					best = i
		seat_of[k] = seats.seat(best)
		var next := kset.find_child("sit_%d" % ((k + 1) % 8), true, false) as Node3D
		print("sit_%d: 腰の所から目印まで %.2f m、次の目印まで %.2f m" % [k, best_d, (seat_of[k].pos as Vector3).distance_to(next.global_position)])
	if args.has("host") or args.has("join"):
		await _net(futon, seat_of)
		return
	var kinds: Array = Array(String(args.kinds).split(",")) if args.has("kinds") else Doll.KINDS
	# 1 人ずつ（どの人形でも同じ）
	for kind in kinds:
		for k in 8:
			var ds := [_sit(seat_of[k], kind)]
			await create_timer(0.35).timeout
			_expect(futon, [k], "%s が sit_%d に" % [kind, k])
			_leave(ds)
			await create_timer(0.2).timeout
			_expect(futon, [], "%s が sit_%d から立つ" % [kind, k])
	# 隣どうし
	for p in PAIRS:
		var ds := []
		for k in p:
			ds.append(_sit(seat_of[k], kinds[0]))
		await create_timer(0.35).timeout
		_expect(futon, p, "隣どうし sit_%d と sit_%d に" % p)
		_stand(ds[0])
		await create_timer(0.35).timeout
		_expect(futon, [p[1]], "sit_%d だけ立つ" % p[0])
		_leave(ds)
		await create_timer(0.2).timeout
		_expect(futon, [], "2 人とも立つ")
	print("KOTATSU_FUTON_CHECK %s（違い %d 件）" % ["OK" if ng == 0 else "NG", ng])
	quit(0 if ng == 0 else 1)


## ホストが sit_1 に座る → つなぐ側が sit_2 に座る → つなぐ側が立つ → ホストが立つ。相手の人形が座った・立ったのを見てから、この画面で確かめて次へ
func _net(futon: Node, seat_of: Dictionary) -> void:
	var host := args.has("host")
	var t := 0.0
	while main.net.remotes.is_empty() and t < 30.0:
		await create_timer(0.25).timeout
		t += 0.25
	print("相手が%s" % ("見えた" if not main.net.remotes.is_empty() else "来なかった"))
	await create_timer(2.0).timeout
	var st: Dictionary = seat_of[1 if host else 2]
	for step in [[true, true, [1]], [false, true, [1, 2]], [false, false, [1]], [true, false, []]]:   # [ホストの番か, 座るか, ねらい]
		if step[0] == host:
			if step[1]:
				main.player.global_position = st.stand + Vector3.UP * 0.05
				main.seats.send({"kind": "sit", "who": main.player.id, "seat": main.seats.seats.find(st)})
			else:
				main.player.stand_up()
		else:
			t = 0.0
			var other: Node3D = main.net.remotes.values()[0].doll
			while (other.lap_line.size() > 0) != step[1] and t < 20.0:
				await create_timer(0.1).timeout
				t += 0.1
		await create_timer(1.5).timeout
		_expect(futon, step[2], "段 %s" % [step[2]])
		var lap: PackedVector4Array = futon._mats[0].get_shader_parameter("seat_lap")
		for k in lap.size():
			if lap[k].w > 0.0:
				print("  %s: 席 %.3f お腹の前 %.3f 膝 %.3f" % [futon._seats[k].mark.name, lap[k].x, lap[k].y, lap[k].z])
		await create_timer(2.5).timeout
	print("KOTATSU_FUTON_CHECK %s（違い %d 件）" % ["OK" if ng == 0 else "NG", ng])
	quit(0 if ng == 0 else 1)


func _sit(st: Dictionary, kind: String) -> Node3D:
	var host := Node3D.new()
	root.add_child(host)
	var d := Doll.new()
	d.kind = kind
	host.add_child(d)
	d.act = Doll.Act.SIT
	d.sit_stage = 2
	host.global_position = st.pos
	d.facing = st.face
	d.set("_yaw", atan2(-st.face.x, -st.face.z))
	d.seat_drop = st.pos.y - st.floor
	d.seat_edge = st.get("edge", 0.2)
	d.seat_soft = true
	d.set("_next_breath", 100000)
	return d


func _stand(d: Node3D) -> void:
	d.act = Doll.Act.WALK
	d.sit_stage = 0
	d.seat_soft = false


func _leave(ds: Array) -> void:
	for d in ds:
		d.get_parent().queue_free()


func _expect(futon: Node, want: Array, what: String) -> void:
	var lap: PackedVector4Array = futon._mats[0].get_shader_parameter("seat_lap")
	var got := []
	for k in lap.size():
		if lap[k].w > 0.0:
			got.append(futon._seats[k].mark.name.trim_prefix("sit_").to_int())
	got.sort()
	var ok: bool = got == want
	if not ok:
		ng += 1
	print("%s %s: めくれた席 %s（ねらい %s）" % ["ok" if ok else "NG", what, got, want])
