extends SceneTree
## 雪合戦の決着の舞台（duel_stage.gd）を、人形の全種類で並べて撮る。世界は読まない。窓を出す:
##   Godot --path game --resolution 1680x960 -s res://tools/duel_stage_sheet.gd -- --dir=/path/shots
## 段は人形、列は 胴上げ（上がる所・てっぺん）・ジタバタ・肩すくめ

const Stage := preload("res://duel_stage.gd")
const Doll := preload("res://doll.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.82, 0.86, 0.92)
	bg.size = root.size
	root.add_child(bg)
	var dir := String(args.get("dir", "/tmp/stage"))
	DirAccess.make_dir_recursive_absolute(dir)
	if args.has("record"):
		await _record(dir)
		quit()
		return
	var kinds: Array = Doll.KINDS
	var cell := float(root.size.y) / 4.0
	var i := 0
	for kind in kinds:
		var col := i % 2 * 4
		var row := i / 2
		for j in 4:
			var s := Stage.new()
			s.result = ["win", "lose", "draw", "draw"][j]
			s.mine = {"kind": kind}
			if j == 3:
				s.theirs = {"kind": kinds[(i + 2) % kinds.size()]}
			root.add_child(s)
			s.place(Vector2((col + j + 0.5) * cell, (row + 0.5) * cell), cell * 0.92, 1.0)
		i += 1
	await create_timer(1.0).timeout
	for n in 6:
		await create_timer(0.17).timeout
		root.get_texture().get_image().save_png(dir.path_join("stage_%d.png" % n))
	print("撮った")
	quit()


## --record=kasa,robo: 人形ごとに 1 段で、勝ち・負け・引き分けを 12 コマ／秒で 45 コマ撮る（rec_000.png…）
func _record(dir: String) -> void:
	var list: PackedStringArray = String(args.record).split(",")
	var cell := float(root.size.x) / 3.0
	for row in list.size():
		for j in 3:
			var s := Stage.new()
			s.result = ["win", "lose", "draw"][j]
			s.mine = {"kind": list[row]}
			s.mitten_col = Doll.STOCK_NAVY
			if j == 2:
				s.theirs = {"kind": list[(row + 1) % list.size()]}
			root.add_child(s)
			s.place(Vector2((j + 0.5) * cell, (row + 0.5) * cell), cell * 0.94, 1.0)
	await create_timer(0.5).timeout
	var shots := []
	var last := Doll.frame_index()
	while shots.size() < 45:
		await process_frame
		var k := Doll.frame_index()
		if k != last:
			last = k
			await process_frame
			shots.append(root.get_texture().get_image())
	for n in shots.size():
		shots[n].save_png(dir.path_join("rec_%03d.png" % n))
	print("撮った %d コマ" % shots.size())
