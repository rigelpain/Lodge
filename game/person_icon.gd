extends RefCounted
## HUD の札に出す人の形: 丸い頭と、太い線の胴・腕・脚だけの人型（笠や服は描かない。2026-10-31 代表「人形表示は傘とか服とか
## 付けずに、シンプルな人型アイコンにキャラカラー」）。色はその人のキャラの色（装備の画面で自分で決める。craft.gd の colors）。
## 頭の上にその人の名前（装備の画面で自分で決める。craft.gd の names）。持ち主には王冠を載せる。
##   姿: stand（立つ。つかんでいるだけの人）/ push（前のめりで両手を前へ）/ pull（前のめりで片手を後ろへ。紐を引く）/ sit（座る）
##   face は顔の向き（1 は右、-1 は左）。feet は足もと（座る姿は尻）、h は立った背の高さ（px）

const PAPER := Color(0.96, 0.93, 0.86)
const INK := Color(0.16, 0.15, 0.22)
const GOLD := Color(0.96, 0.76, 0.22)


## 人の形を描く
static func draw(ci: CanvasItem, feet: Vector2, h: float, col: Color, pose := "stand", face := 1.0, a := 1.0) -> void:
	var w := maxf(h * 0.17, 2.0)          # 胴の太さ
	var lw := maxf(h * 0.12, 1.6)         # 腕と脚の太さ
	var rim := maxf(h * 0.035, 1.0)       # 縁（どの地の上でも形が浮くように、暗い縁）
	var lean := 0.0
	match pose:
		"push": lean = 0.42
		"pull": lean = 0.32
	var X := func(v: Vector2) -> Vector2:   # 足もとを支点に前へ傾け、向きで左右を返す
		return feet + Vector2(v.x * face, v.y).rotated(lean * face) * h
	var hip := Vector2(0, -0.40)
	var neck := Vector2(0, -0.70)
	var head := Vector2(0, -0.86)
	var hr := 0.13
	var limbs: Array = []   # [始め, 終わり, 太さ]
	match pose:
		"sit":
			hip = Vector2(0, -0.02)
			neck = Vector2(-0.02, -0.32)
			head = Vector2(-0.02, -0.48)
			limbs = [[hip, Vector2(0.24, -0.02), lw], [Vector2(0.24, -0.02), Vector2(0.27, 0.16), lw],
				[Vector2(0, -0.27), Vector2(0.20, -0.12), lw]]
		"push":
			limbs = [[hip, Vector2(-0.10, 0.0), lw], [hip, Vector2(0.10, 0.0), lw],
				[Vector2(0, -0.64), Vector2(0.30, -0.66), lw]]
		"pull":
			limbs = [[hip, Vector2(-0.11, 0.0), lw], [hip, Vector2(0.11, 0.0), lw],
				[Vector2(0, -0.64), Vector2(-0.24, -0.46), lw], [Vector2(0, -0.64), Vector2(0.14, -0.44), lw]]
		_:
			limbs = [[hip, Vector2(-0.07, 0.0), lw], [hip, Vector2(0.07, 0.0), lw],
				[Vector2(0, -0.64), Vector2(-0.13, -0.40), lw], [Vector2(0, -0.64), Vector2(0.13, -0.40), lw]]
	var dark := col.darkened(0.55)
	# 縁を先に太く描いてから、色を重ねる
	for pass_i in 2:
		var c := Color(dark, a) if pass_i == 0 else Color(col, a)
		var e := rim if pass_i == 0 else 0.0
		for l in limbs:
			_bar(ci, X.call(l[0]), X.call(l[1]), l[2] + e * 2.0, c)
		_bar(ci, X.call(hip), X.call(neck), w + e * 2.0, c)
		ci.draw_circle(X.call(head), hr * h + e, c)
	# 顔の向き: 頭の前の側に小さな白い点
	ci.draw_circle(X.call(head + Vector2(hr * 0.45, -hr * 0.1)), maxf(h * 0.025, 0.8), Color(PAPER, 0.85 * a))


## 頭の上の所（王冠と名前を載せる所）
static func head_top(feet: Vector2, h: float, pose := "stand", face := 1.0) -> Vector2:
	var lean := 0.0
	var top := Vector2(0, -1.0)
	match pose:
		"push": lean = 0.42
		"pull": lean = 0.32
		"sit": top = Vector2(-0.02, -0.62)
	return feet + Vector2(top.x * face, top.y).rotated(lean * face) * h


## 王冠（持ち主の印）。c は王冠の下の縁のまんなか、s は幅（px）
static func crown(ci: CanvasItem, c: Vector2, s: float, a := 1.0) -> void:
	var hh := s * 0.62
	var pts := PackedVector2Array([c + Vector2(-s / 2.0, 0), c + Vector2(s / 2.0, 0), c + Vector2(s / 2.0, -hh),
		c + Vector2(s * 0.25, -hh * 0.45), c + Vector2(0, -hh * 1.05), c + Vector2(-s * 0.25, -hh * 0.45), c + Vector2(-s / 2.0, -hh)])
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_colored_polygon(pts, Color(GOLD, a))
	ci.draw_polyline(rim, Color(GOLD.darkened(0.55), a), maxf(s * 0.08, 1.0), true)
	ci.draw_rect(Rect2(c + Vector2(-s / 2.0, -hh * 0.28), Vector2(s, hh * 0.28)), Color(GOLD.darkened(0.15), a))
	for x in [-0.5, 0.0, 0.5]:   # 先の玉
		var tip := c + Vector2(s * x, -hh * (1.05 if x == 0.0 else 1.0))
		ci.draw_circle(tip, maxf(s * 0.09, 1.0), Color(0.86, 0.24, 0.22, a))


## 名前（頭の上）。at は字の下の縁のまんなか。字は紙の縁取りに、その人の色を濃くした色
static func name_label(ci: CanvasItem, text: String, at: Vector2, px: float, col: Color, a := 1.0) -> void:
	if text == "" or px < 5.0:
		return
	var font: Font = preload("res://hud_icons.gd")._bold_font()
	var fs := maxi(6, int(round(px)))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := at + Vector2(-tw / 2.0, -font.get_descent(fs))
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 3), Color(PAPER, a))
	var ink := col.darkened(0.3)
	if ink.get_luminance() > 0.32:   # 明るい色（からし・空色など）は、字だけ濃く
		ink = col.darkened(0.6)
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, a))


## 人の形・王冠・名前をまとめて
static func person(ci: CanvasItem, feet: Vector2, h: float, col: Color, pose: String, face: float, a: float, owner: bool, who_name: String, px: float) -> void:
	draw(ci, feet, h, col, pose, face, a)
	var top := head_top(feet, h, pose, face)
	if owner:
		crown(ci, top + Vector2(0, h * 0.02), h * 0.30, a)
		top.y -= h * 0.22
	name_label(ci, who_name, top - Vector2(0, h * 0.03), px, col, a)


static func _bar(ci: CanvasItem, p: Vector2, q: Vector2, w: float, c: Color) -> void:
	ci.draw_line(p, q, c, w, true)
	ci.draw_circle(p, w / 2.0, c)
	ci.draw_circle(q, w / 2.0, c)


# ---- 3D の人型（HUD の札の回る図に乗せる。どの向きから見ても正しく見えるように、絵でなく模型にする）-----------------
# 2026-10-31 代表「タグでのソリの回転はもっとゆっくりにして人形もちゃんと全角度のイラストなりモデル形を用意してほしい」。
# 紙人形（person/）は笠と服があるので使わず（「傘とか服とか付けずに」）、丸い頭と太い円柱の胴・腕・脚だけの人型を、
# キャラの色のフェルトで作る。足もとが原点、前は -Z、背の高さは 1.5 m ほど（座る姿は原点が尻）

const PARTS3D := ["head", "body", "arm_l", "arm_r", "leg_l", "leg_r", "shin_l", "shin_r"]


## 人型の模型を作る（姿は pose_model で決める）
static func model(col: Color) -> Node3D:
	var root := Node3D.new()
	var mat := preload("res://look.gd").felt(col, 3.0)
	# 縁: 少しふくらませた裏面を濃い色で（同じ色のソリの上でも、人の形が浮いて見えるように）
	var rim := StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.cull_mode = BaseMaterial3D.CULL_FRONT
	rim.grow = true
	rim.grow_amount = 0.022
	rim.albedo_color = col.darkened(0.6)
	mat.next_pass = rim
	for n in PARTS3D:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.material_override = mat
		if n == "head":
			var sm := SphereMesh.new()
			sm.radius = 0.15
			sm.height = 0.30
			mi.mesh = sm
		else:
			mi.mesh = CapsuleMesh.new()
		root.add_child(mi)
	root.set_meta("pose", "")
	return root


## 模型の色を替える
static func tint_model(root: Node3D, col: Color) -> void:
	var m := (root.get_node("head") as MeshInstance3D).material_override as StandardMaterial3D
	if m and m.albedo_color != col:
		m.albedo_color = col
		(m.next_pass as StandardMaterial3D).albedo_color = col.darkened(0.6)


## 模型の姿: stand（立つ）/ push（前のめりで両手を前へ）/ pull（前のめりで片手を後ろへ）/ sit（座る。原点が尻）
static func pose_model(root: Node3D, pose: String) -> void:
	if root.get_meta("pose", "") == pose:
		return
	root.set_meta("pose", pose)
	var lean := 0.0
	var hip := Vector3(0, 0.78, 0)
	var neck := Vector3(0, 1.20, 0)
	var head := Vector3(0, 1.38, 0)
	var arms := [[Vector3(-0.17, 1.14, 0), Vector3(-0.22, 0.78, 0.02)], [Vector3(0.17, 1.14, 0), Vector3(0.22, 0.78, 0.02)]]
	var legs := [[Vector3(-0.09, 0.78, 0), Vector3(-0.10, 0.06, 0)], [Vector3(0.09, 0.78, 0), Vector3(0.10, 0.06, 0)]]
	var shins := []
	match pose:
		"push":
			lean = 0.45
			arms = [[Vector3(-0.17, 1.14, 0), Vector3(-0.15, 1.10, -0.46)], [Vector3(0.17, 1.14, 0), Vector3(0.15, 1.08, -0.46)]]
			legs = [[Vector3(-0.09, 0.78, 0), Vector3(-0.10, 0.06, 0.30)], [Vector3(0.09, 0.78, 0), Vector3(0.10, 0.06, -0.12)]]
		"pull":
			lean = 0.35
			arms = [[Vector3(-0.17, 1.14, 0), Vector3(-0.18, 0.86, 0.38)], [Vector3(0.17, 1.14, 0), Vector3(0.22, 0.86, -0.14)]]
			legs = [[Vector3(-0.09, 0.78, 0), Vector3(-0.10, 0.06, 0.28)], [Vector3(0.09, 0.78, 0), Vector3(0.10, 0.06, -0.14)]]
		"sit":
			hip = Vector3(0, 0.08, 0)
			neck = Vector3(0, 0.52, 0.02)
			head = Vector3(0, 0.70, 0.02)
			arms = [[Vector3(-0.17, 0.46, 0), Vector3(-0.20, 0.22, -0.26)], [Vector3(0.17, 0.46, 0), Vector3(0.20, 0.22, -0.26)]]
			legs = [[Vector3(-0.10, 0.08, 0), Vector3(-0.11, 0.06, -0.40)], [Vector3(0.10, 0.08, 0), Vector3(0.11, 0.06, -0.40)]]
			shins = [[Vector3(-0.11, 0.06, -0.40), Vector3(-0.12, -0.30, -0.46)], [Vector3(0.11, 0.06, -0.40), Vector3(0.12, -0.30, -0.46)]]
	# 前のめり: 足もとを支点に、上の体を前（-Z）へ倒す（脚は倒さない）
	var tilt := Basis(Vector3.RIGHT, -lean)
	var up := func(v: Vector3) -> Vector3: return hip + tilt * (v - hip) if v.y > hip.y - 0.001 else v
	_seg(root.get_node("body"), up.call(hip), up.call(neck), 0.14)
	(root.get_node("head") as Node3D).position = up.call(head)
	for i in 2:
		_seg(root.get_node(["arm_l", "arm_r"][i]), up.call(arms[i][0]), up.call(arms[i][1]), 0.065)
		_seg(root.get_node(["leg_l", "leg_r"][i]), legs[i][0], legs[i][1], 0.075)
		var sh: Node3D = root.get_node(["shin_l", "shin_r"][i])
		sh.visible = not shins.is_empty()
		if sh.visible:
			_seg(sh, shins[i][0], shins[i][1], 0.07)


## 円柱（両端が丸い）を a から b へ渡す
static func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var cm := mi.mesh as CapsuleMesh
	cm.radius = r
	cm.height = d.length() + r * 2.0
	var y := d.normalized() if d.length() > 0.001 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)
