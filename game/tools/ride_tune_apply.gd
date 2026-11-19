extends SceneTree
## 乗り心地の調整の画面（ride_tune_ui.gd）でコピーした JSON を、本番の既定として sled.gd・flung.gd・player.gd の static var に書き戻す。
## 一覧（ride_tune.gd の ITEMS）にある値だけを、`static var 名前 := 値` の行の値の所だけ書き換える（注釈はそのまま。変えた値の注釈は手で合わせる）。
##   $G --headless --path game -s res://tools/ride_tune_apply.gd -- res://tools/ride_tune.json
## --dry を付けると、書き換えずに変わる行だけ表示する

const Tune := preload("res://ride_tune.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var dry := false
	for a in args:
		if a == "--dry":
			dry = true
		else:
			path = a
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	if not data is Dictionary:
		push_error("JSON を読めない: " + path)
		quit(1)
		return
	var n := 0
	for file in Tune.FILES:
		var src_path: String = Tune.FILES[file].resource_path
		var lines := FileAccess.get_file_as_string(src_path).split("\n")
		var changed := false
		for i in lines.size():
			var line: String = lines[i]
			if not line.begins_with("static var "):
				continue
			var name := line.substr(11).get_slice(" ", 0)
			var mine := Tune.items().filter(func(it): return it[0] == file and it[1] == name)
			if mine.is_empty():
				continue
			var out := _rewrite(line, mine, data)
			if out != line:
				print("%s:%d\n  - %s\n  + %s" % [src_path.get_file(), i + 1, line.strip_edges(), out.strip_edges()])
				lines[i] = out
				changed = true
				n += 1
		if changed and not dry:
			var f := FileAccess.open(src_path, FileAccess.WRITE)
			f.store_string("\n".join(lines))
			f.close()
	print("変えた行: %d%s" % [n, "（--dry なので書き換えていない）" if dry else ""])
	quit()


## 1 行の値の所を、JSON の値で書き換える。行は `static var 名前 := 値   # 注釈`
func _rewrite(line: String, mine: Array, data: Dictionary) -> String:
	var head := line.get_slice(":=", 0) + ":= "
	var rest := line.substr(head.length())
	var cut := _literal_end(rest)
	var lit := rest.substr(0, cut)
	var tail := rest.substr(cut)
	var it0: Array = mine[0]
	match it0[2]:
		"":
			var x = Tune.pick(data, it0)
			if x == null or is_equal_approx(x, str_to_var(lit)):
				return line
			lit = _num(x)
		"x", "y":
			var v: Vector2 = str_to_var(lit)
			var w := v
			for it in mine:
				var x = Tune.pick(data, it)
				if x != null:
					w[it[2]] = x
			if w.is_equal_approx(v):
				return line
			lit = "Vector2(%s, %s)" % [_num(w.x), _num(w.y)]
		_:
			var d: Dictionary = str_to_var(lit)
			for it in mine:
				var x = Tune.pick(data, it)
				if x == null or is_equal_approx(x, float(d[it[2]])):
					continue
				var re := RegEx.create_from_string("(\"%s\"\\s*:\\s*)[-0-9.eE]+" % it[2])
				lit = re.sub(lit, "${1}" + _num(x))
	return head + lit + tail


## 値の書き方の終わり（注釈の # の前の空白まで）。括弧の中の , や空白は値のうち
func _literal_end(s: String) -> int:
	var depth := 0
	for i in s.length():
		var c := s[i]
		if c in "({[":
			depth += 1
		elif c in ")}]":
			depth -= 1
		elif depth == 0 and (c == " " or c == "\t" or c == "#"):
			return i
	return s.length()


## 小数点のある数に（`:=` で float のまま推論させる。70 と書くと int になる）
func _num(x: float) -> String:
	var t := String.num(x, 5)
	if not ("." in t or "e" in t):
		t += ".0"
	return t
