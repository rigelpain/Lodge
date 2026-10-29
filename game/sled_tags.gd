extends RefCounted
## ソリの名札（タグ）。ソリ 1 台に 1 枚、柄の違うタグが付く。文字は使わない。
##   柄: 形（角を切った紙・丸い角・ピンキングばさみのぎざぎざ・切符・燕尾の旗・波の縁・六角）× 紙やフェルトの色 ×
##       縁の縫い目の糸 × 吊るす糸 × 判子（雪の結晶・星・もみの木・ハート・水玉・しま・手袋・なし）
##   広げたソリ: 手すりの前の結び目から、小さなタグを糸で吊るす（sled_tag.gd）
##   畳んだソリ: 包みにも同じタグを付け、タグの窓に広げた姿をくるくる回して見せる（turntable。12 コマで回る）
##   画面の左下の札（hud.gd）: 最後に触ったソリのタグの柄で描く
## 柄の番号はソリの tag（sled.gd）。最初のソリは 0（いままでの札と同じ紙のタグ）、縫ったソリは craft.gd が順に配る。

const Icons := preload("res://hud_icons.gd")
const Doll := preload("res://doll.gd")

const DESIGNS := [
	{"shape": "cut", "paper": Color(0.96, 0.93, 0.86), "edge": Color(0.20, 0.25, 0.42), "string": Color(0.80, 0.24, 0.20), "motif": "none", "ink": Color(0.80, 0.24, 0.20)},
	{"shape": "round", "paper": Color(0.86, 0.72, 0.52), "edge": Color(0.45, 0.30, 0.18), "string": Color(0.95, 0.92, 0.84), "motif": "snow", "ink": Color(0.97, 0.97, 1.0)},
	{"shape": "pinked", "paper": Color(0.80, 0.88, 0.95), "edge": Color(0.24, 0.32, 0.55), "string": Color(0.88, 0.66, 0.20), "motif": "star", "ink": Color(0.88, 0.66, 0.20)},
	{"shape": "ticket", "paper": Color(0.97, 0.88, 0.80), "edge": Color(0.72, 0.30, 0.24), "string": Color(0.30, 0.42, 0.32), "motif": "pine", "ink": Color(0.25, 0.45, 0.30)},
	{"shape": "flag", "paper": Color(0.30, 0.38, 0.62), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.95, 0.92, 0.84), "motif": "dots", "ink": Color(0.95, 0.92, 0.84)},
	{"shape": "scallop", "paper": Color(0.95, 0.80, 0.82), "edge": Color(0.62, 0.28, 0.38), "string": Color(0.62, 0.28, 0.38), "motif": "heart", "ink": Color(0.80, 0.24, 0.30)},
	{"shape": "hex", "paper": Color(0.88, 0.84, 0.50), "edge": Color(0.40, 0.32, 0.16), "string": Color(0.20, 0.25, 0.42), "motif": "mitten", "ink": Color(0.72, 0.30, 0.24)},
	{"shape": "round", "paper": Color(0.36, 0.42, 0.33), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.86, 0.74, 0.48), "motif": "stripe", "ink": Color(0.86, 0.74, 0.48)},
	{"shape": "pinked", "paper": Color(0.96, 0.93, 0.86), "edge": Color(0.36, 0.42, 0.33), "string": Color(0.36, 0.42, 0.33), "motif": "pine", "ink": Color(0.36, 0.42, 0.33)},
	{"shape": "ticket", "paper": Color(0.47, 0.30, 0.45), "edge": Color(0.95, 0.85, 0.60), "string": Color(0.95, 0.85, 0.60), "motif": "snow", "ink": Color(0.95, 0.92, 0.84)},
	{"shape": "flag", "paper": Color(0.80, 0.24, 0.20), "edge": Color(0.98, 0.96, 0.92), "string": Color(0.20, 0.25, 0.42), "motif": "star", "ink": Color(0.98, 0.96, 0.92)},
	{"shape": "scallop", "paper": Color(0.80, 0.90, 0.86), "edge": Color(0.25, 0.45, 0.42), "string": Color(0.80, 0.24, 0.20), "motif": "dots", "ink": Color(0.25, 0.45, 0.42)},
	{"shape": "cut", "paper": Color(0.55, 0.38, 0.22), "edge": Color(0.95, 0.92, 0.84), "string": Color(0.95, 0.92, 0.84), "motif": "mitten", "ink": Color(0.95, 0.92, 0.84)},
]

const TEX_SIZE := Vector2i(192, 128)   # 吊るすタグの絵
const TURN_SIZE := Vector2i(160, 160)  # 回る図
const TURN_STEP := 2                   # 何コマごとに回すか（12 コマ／秒の 2 コマ = 6 回／秒）
const TURN_DEG := 15.0                 # 1 回に回す角度

static var _holder: Node
static var _tags := {}                 # 柄の番号 → ViewportTexture
static var _turns := {}                # "kind|fabric" → Turntable


static func count() -> int:
	return DESIGNS.size()


static func design(i: int) -> Dictionary:
	return DESIGNS[posmod(i, DESIGNS.size())]


# ---- 形 ------------------------------------------------------------------------------

## タグの輪郭（rect の中。左に穴のある向き）
static func outline(r: Rect2, shape: String) -> PackedVector2Array:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var c := minf(h * 0.28, 26.0)
	match shape:
		"round":
			return Icons.rr(x, y, w, h, h * 0.22)
		"pinked":   # ぎざぎざの縁
			var p := PackedVector2Array()
			var n := int(w / 9.0)
			for i in n + 1:
				p.append(Vector2(x + w * i / n, y + (0.0 if i % 2 == 0 else 4.0)))
			var m := int(h / 9.0)
			for i in m + 1:
				p.append(Vector2(x + w - (0.0 if i % 2 == 0 else 4.0), y + h * i / m))
			for i in n + 1:
				p.append(Vector2(x + w - w * i / n, y + h - (0.0 if i % 2 == 0 else 4.0)))
			for i in m + 1:
				p.append(Vector2(x + (0.0 if i % 2 == 0 else 4.0), y + h - h * i / m))
			return p
		"ticket":   # 両端に半円の切り欠き
			var p := PackedVector2Array([Vector2(x, y), Vector2(x + w, y)])
			for i in 9:
				var a := -PI / 2 + PI * i / 8.0
				p.append(Vector2(x + w, y + h / 2) + Vector2(-cos(a), sin(a)) * h * 0.16)
			p.append(Vector2(x + w, y + h))
			p.append(Vector2(x, y + h))
			for i in 9:
				var a := PI / 2 - PI * i / 8.0
				p.append(Vector2(x, y + h / 2) + Vector2(cos(a), sin(a)) * h * 0.16)
			return p
		"flag":     # 燕尾の旗
			return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w - h * 0.3, y + h / 2), Vector2(x + w, y + h), Vector2(x, y + h)])
		"scallop":  # 波の縁
			var p := PackedVector2Array()
			var inner := Rect2(x + 6, y + 6, w - 12, h - 12)
			var per := Icons.rr(inner.position.x, inner.position.y, inner.size.x, inner.size.y, inner.size.y * 0.3)
			var tot := 0.0
			for i in per.size():
				tot += per[i].distance_to(per[(i + 1) % per.size()])
			var n := int(tot / 7.0)
			var ctr := inner.get_center()
			for i in n:
				var q := _along(per, tot * i / n)
				var out := (q - ctr).normalized()
				p.append(q + out * (6.0 if i % 2 == 0 else 2.0))
			return p
		"hex":
			return PackedVector2Array([Vector2(x + c, y), Vector2(x + w - c * 0.6, y), Vector2(x + w, y + h / 2), Vector2(x + w - c * 0.6, y + h),
					Vector2(x + c, y + h), Vector2(x, y + h / 2)])
	return PackedVector2Array([Vector2(x + c, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x + c, y + h), Vector2(x, y + h - c), Vector2(x, y + c)])


static func _along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / maxf(l, 0.001))
		d -= l
	return pts[0]


## タグを描く（画面の px の rect）。穴と糸の輪も。stamp で右下に判子
static func draw_tag(ci: CanvasItem, r: Rect2, idx: int, a := 1.0, stamp := true) -> void:
	var d := design(idx)
	Icons._o = Vector2.ZERO
	Icons._s = 1.0
	var pts := outline(r, d.shape)
	Icons.patch(ci, pts, d.paper, a, false)
	var inset := Geometry2D.offset_polygon(pts, -minf(5.0, r.size.y * 0.05))
	if inset.size() > 0:
		Icons.dashes(ci, inset[0], Color(d.edge, 0.7), maxf(1.2, r.size.y * 0.009), maxf(5.0, r.size.y * 0.035), maxf(3.5, r.size.y * 0.025), a, true)
	var c := minf(r.size.y * 0.28, 26.0)
	var hole := r.position + Vector2(c * 0.62 + (4.0 if d.shape == "ticket" else 0.0) + (r.size.y * 0.18 if d.shape == "ticket" else 0.0), r.size.y / 2.0)
	var hr := maxf(r.size.y * 0.038, 3.0)
	ci.draw_circle(hole, hr * 1.5, Color(Icons.PAPER_EDGE, a))
	ci.draw_circle(hole, hr, Color(0.35, 0.30, 0.28, 0.85 * a))
	var loop := PackedVector2Array()
	for i in 16:
		var t := i / 15.0
		loop.append(hole + Vector2(-t * c * 0.85, sin(t * PI) * -c * 0.38 - t * c * 0.23))
	Icons.thread(ci, loop, d.string, maxf(1.6, r.size.y * 0.012), a)
	if stamp and d.motif != "none":
		var s := minf(r.size.y * 0.30, 40.0)
		motif(ci, d.motif, r.end - Vector2(s * 0.8, s * 0.8), s, d.ink, a)


## 判子の絵（center、大きさ size px）
static func motif(ci: CanvasItem, name: String, center: Vector2, size: float, col: Color, a := 1.0) -> void:
	Icons._o = center
	Icons._s = size / 64.0
	match name:
		"snow":
			for k in 3:
				var dir := Vector2.from_angle(PI / 3 * k)
				Icons.thread(ci, PackedVector2Array([-dir * 24, dir * 24]), col, 3.0, a)
				for e in [-1.0, 1.0]:
					var tip: Vector2 = dir * 14.0 * e
					var side: Vector2 = Vector2(-dir.y, dir.x)
					Icons.thread(ci, PackedVector2Array([tip + (side - dir * e) * 6.0, tip, tip + (-side - dir * e) * 6.0]), col, 2.2, a)
		"star":
			var p := PackedVector2Array()
			for i in 10:
				p.append(Vector2.from_angle(-PI / 2 + PI / 5 * i) * (26.0 if i % 2 == 0 else 11.0))
			Icons.patch(ci, p, col, a, false)
		"pine":
			Icons.patch(ci, PackedVector2Array([Vector2(0, -28), Vector2(18, 0), Vector2(8, 0), Vector2(22, 18), Vector2(-22, 18), Vector2(-8, 0), Vector2(-18, 0)]), col, a, false)
			Icons.patch(ci, Icons.rr(-4, 18, 8, 9, 2), Icons.WOOD, a, false)
		"heart":
			var p := PackedVector2Array()
			for i in 24:
				var t := TAU * i / 24.0
				p.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 1.4)
			Icons.patch(ci, p, col, a, false)
		"dots":
			for q in [Vector2(-14, -12), Vector2(10, -16), Vector2(-4, 4), Vector2(16, 10), Vector2(-16, 18)]:
				Icons.patch(ci, Icons.circ(q, 7.0, 12), col, a, false)
		"stripe":
			for i in 4:
				Icons.thread(ci, PackedVector2Array([Vector2(-24, -18 + i * 12), Vector2(24, -24 + i * 12)]), col, 4.0, a)
		"mitten":
			Icons.mitten(ci, Vector2.ZERO, 0.2, col, a, true, 2.0)


# ---- 3D に貼る絵 ------------------------------------------------------------------------

static func _root() -> Node:
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = "SledTagTextures"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_holder)
	return _holder


## 吊るすタグの絵（柄ごとに 1 枚を描いて使い回す）
static func texture(idx: int) -> Texture2D:
	idx = posmod(idx, DESIGNS.size())
	if not _tags.has(idx):
		var vp := SubViewport.new()
		vp.size = TEX_SIZE
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var c := TagFace.new()
		c.idx = idx
		c.size = Vector2(TEX_SIZE)
		vp.add_child(c)
		_root().add_child.call_deferred(vp)
		_tags[idx] = vp.get_texture()
	return _tags[idx]


## 畳んだソリの、広げた姿がくるくる回る図（大きさと布の色ごとに 1 つを使い回す）
static func turntable(kind: String, fabric: String) -> Texture2D:
	var key := kind + "|" + fabric
	if not _turns.has(key):
		var t := Turntable.new()
		t.kind = kind
		t.fabric = fabric
		_root().add_child.call_deferred(t)
		_turns[key] = t
	return (_turns[key] as Turntable).get_texture()


class TagFace extends Control:
	var idx := 0

	func _draw() -> void:
		var pad := Vector2(10, 12)
		preload("res://sled_tags.gd").draw_tag(self, Rect2(pad + Vector2(14, 0), size - pad * 2 - Vector2(14, 0)), idx, 1.0)


## 広げた姿を小さな世界に置いて、斜め上から撮る。12 コマに合わせて 15° ずつ回す（人形と同じコマ撮り）
class Turntable extends SubViewport:
	var kind := "mid"
	var fabric := ""
	var _model: Node3D
	var _frame := -1

	func _init() -> void:
		size = preload("res://sled_tags.gd").TURN_SIZE
		own_world_3d = true
		transparent_bg = true
		render_target_update_mode = SubViewport.UPDATE_ALWAYS

	func _ready() -> void:
		var Sled := preload("res://sled.gd")
		var k: Dictionary = Sled.KINDS.get(kind, Sled.KINDS["mid"])
		var glb := "res://props/sled_%s.glb" % kind
		_model = Node3D.new()
		add_child(_model)
		if ResourceLoader.exists(glb):
			var look := preload("res://props.gd").make(glb)
			preload("res://fabrics.gd").tint(look, kind, fabric)
			_model.add_child(look)
		var L: float = maxf(k.box.z, k.box.x)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = L * 1.25
		cam.position = Vector3(0, L * 0.9, L * 1.3)
		add_child(cam)
		cam.look_at(Vector3(0, k.box.y * 0.5, 0))
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -30, 0)
		sun.light_energy = 1.4
		add_child(sun)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.88, 0.95)
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)

	func _process(_dt: float) -> void:
		var fi := preload("res://doll.gd").frame_index() / preload("res://sled_tags.gd").TURN_STEP
		if fi == _frame or _model == null:
			return
		_frame = fi
		_model.rotation.y = deg_to_rad(preload("res://sled_tags.gd").TURN_DEG * fi)


# ---- 3D のタグ（吊るす） -------------------------------------------------------------------

## 畳んだソリの包みの面に、名札を平らに貼る（吊るすと包みに隠れるので）。parent の +Y の面に載せ、絵の下は +Z。
## 左右の端を紙テープで留め、窓に広げた姿がくるくる回る。面に埋もれないよう少し浮かせる。w は名札の幅 (m)
static func patch_on(parent: Node3D, top: float, idx: int, w: float, turn: Texture2D, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "TagPatch"
	root.position = Vector3(0, top + 0.003, 0)
	parent.add_child(root)
	var h := w * TEX_SIZE.y / TEX_SIZE.x
	var face := _flat(root, Vector2(w, h), texture(idx), false, layers)
	face.position.y = 0.0
	if turn:   # 窓（右寄り）
		var win := _flat(root, Vector2.ONE * h * 0.74, turn, true, layers)
		win.position = Vector3(w * 0.2, 0.0015, 0.0)
	# 紙テープ: 左上と右下の角に斜めに
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.93, 0.86, 0.68, 0.85)
	tape.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tape.roughness = 0.9
	for s in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w * 0.3, 0.001, h * 0.22)
		t.mesh = bm
		t.material_override = tape
		t.layers = layers
		t.position = Vector3(s * w * 0.46, 0.003, -s * h * 0.42)
		t.rotation.y = 0.6
		root.add_child(t)
	return root


static func _flat(parent: Node3D, sz: Vector2, tex: Texture2D, unshaded: bool, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.layers = layers
	mi.rotation.x = -PI / 2   # 面は +Y、絵の上は -Z
	parent.add_child(mi)
	return mi


## 畳んだソリの包みの絵に、名札を貼った形で描く（持ち物の列・売り台。3D の patch_on と同じ並び）。c と w は画面の px
static func draw_on_packet(ci: CanvasItem, c: Vector2, w: float, idx: int, turn: Texture2D, a := 1.0) -> void:
	var h := w * TEX_SIZE.y / TEX_SIZE.x * 0.82
	var r := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
	draw_tag(ci, r, idx, a, false)
	var tw := h * 0.74
	ci.draw_texture_rect(turn, Rect2(Vector2(c.x + w * 0.2 - tw / 2.0, c.y - tw / 2.0), Vector2(tw, tw)), false, Color(1, 1, 1, a))
	for s in [-1.0, 1.0]:
		var tc := c + Vector2(s * w * 0.46, -s * h * 0.42)
		var tape := Icons.xf(Icons.rr(-w * 0.15, -h * 0.11, w * 0.3, h * 0.22, 1.0), -0.6, tc, 1.0)
		Icons._o = Vector2.ZERO
		Icons._s = 1.0
		ci.draw_colored_polygon(tape, Color(0.93, 0.86, 0.68, 0.85 * a))


## 小さなタグを parent の at から糸で吊るす。turn があれば、タグの窓に回る図も貼る（畳んだソリ）。layers は映す層
static func hang(parent: Node3D, at: Vector3, idx: int, w := 0.16, turn: Texture2D = null, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Tag"
	root.position = at
	parent.add_child(root)
	var drop := w * 0.45
	var string := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.003
	cm.bottom_radius = 0.003
	cm.height = drop
	string.mesh = cm
	string.position.y = -drop / 2.0
	var sm := StandardMaterial3D.new()
	sm.albedo_color = design(idx).string
	string.material_override = sm
	string.layers = layers
	root.add_child(string)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, w * TEX_SIZE.y / TEX_SIZE.x)
	face.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(idx)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	face.material_override = m
	face.layers = layers
	# 穴（絵の左）を糸の先に合わせ、紙を縦に吊るす
	face.position = Vector3(0, -drop - q.size.x * 0.42, 0)
	face.rotation.z = -PI / 2
	root.add_child(face)
	if turn:
		var win := MeshInstance3D.new()
		var wq := QuadMesh.new()
		wq.size = Vector2.ONE * q.size.y * 0.78
		win.mesh = wq
		var wm := StandardMaterial3D.new()
		wm.albedo_texture = turn
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		win.material_override = wm
		win.layers = layers
		win.position = face.position + Vector3(0, -q.size.x * 0.08, 0.002)
		root.add_child(win)
	return root
