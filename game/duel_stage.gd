extends Control
## 雪合戦の決着で、画面のまんなかに出す大きな刺繍枠の舞台（duel_hud.gd が出し入れする）。字を使わず、人形の動きで勝ち負けを見せる。
## （2026-11-06 代表「喜んで胴上げ、悲しんでジタバタ、引き分けはまあなんかいい感じにっていうキャラモーションを小さく表示とかでも良いですよ。
## ここまで文字をなるべく排してきたのは海外対応が文字を使うと面倒だからです」）
## 舞台はゲームの世界と別の世界（own_world_3d）で、自分の人形の写しを置く。世界の人形は動かさないので、歩く・握手する・ほかの人の画面には影響しない。
##   win  胴上げ: 仰向けの人形が宙に舞い、フェルトの手袋 2 つが放り上げる。枠の縫い目は金
##   lose ジタバタ: 仰向けで手足をばたつかせ、首を振る。枠の縫い目は藍
##   draw 2 人で向かい合って、肩をすくめて首をかしげる。枠の縫い目は麻色
## 左下の小さな丸に、時間切れは砂時計、相手が抜けたは薄い人形に × の糸（sub）。絵は 12 コマ／秒で刻む

const Icons := preload("res://hud_icons.gd")
const Doll := preload("res://doll.gd")
const SelfCam := preload("res://self_cam.gd")

const TOSS_T := 15           # 胴上げ 1 回のコマ
const TOSS_H := 0.85         # 胴上げの高さ（背の高さに対して）
const FOV := 22.0
const HOOP_IN := 0.97
const GOLD := Color(0.86, 0.66, 0.26)
const HEMP := Color(0.70, 0.57, 0.38)

var result := "win"          # win・lose・draw
var sub := ""                # time・gone
var mine := {}               # {kind, outfit}
var theirs := {}             # {kind, outfit}（draw で並べる。いなければ空）
var mitten_col := Icons.RED
var main_env: Environment
var plain_frame := false     # 下の 3 つは self_cam.gd の Frame が見る
var stitch_col := Icons.RED

var vp: SubViewport
var _frame: Control
var _view: TextureRect
var _mat: ShaderMaterial
var _over: Control
var _host: Node3D
var _doll: Node3D
var _others := []            # [host, doll]
var _start := 0
var _h := 1.3


func ui() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / 1080.0, 0.6, 2.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stitch_col = {"win": GOLD, "lose": Doll.STOCK_NAVY, "draw": HEMP}[result]
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.size = Vector2i(512, 512)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.environment = _env()
	vp.add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-25.0), 0.0)
	sun.light_energy = 1.25
	vp.add_child(sun)
	_start = Doll.frame_index() + 1
	_host = _make_host(mine, Vector3.ZERO)
	_doll = _host.get_child(0)
	_h = _doll.height()
	match result:
		"win":
			_lay(_doll, _host, 0.0)
			_doll.play({"kind": "stage_toss", "frame": _start, "len": 600})
		"lose":
			_lay(_doll, _host, 0.0)
			_doll.play({"kind": "stage_flail", "frame": _start, "len": 600})
		_:
			_doll.play({"kind": "stage_shrug", "frame": _start, "len": 600})
			if not theirs.is_empty():
				var other := _make_host(theirs, Vector3(0.42 * _h, 0.0, 0.0))
				_others = [other, other.get_child(0)]
				_h = maxf(_h, _others[1].height())
				_others[1].play({"kind": "stage_shrug", "frame": _start + 5, "len": 600})
				_host.position.x = -0.42 * _h
				_doll.facing = Vector3(0.6, 0.0, 1.0).normalized()
				_others[1].facing = Vector3(-0.6, 0.0, 1.0).normalized()
	_aim(cam)
	_frame = SelfCam.Frame.new()
	_frame.sc = self
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_view = TextureRect.new()
	_view.texture = vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.show_behind_parent = true
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SelfCam.MASK_SHADER
	_view.material = _mat
	_frame.add_child(_view)
	_frame.view = _view
	_over = Over.new()
	_over.stage = self
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)


func _env() -> Environment:
	var e: Environment = main_env.duplicate() if main_env else Environment.new()
	if e.sky:
		e.sky = e.sky.duplicate()
	e.background_mode = Environment.BG_COLOR
	e.background_color = SelfCam.LINEN
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.98, 0.95)
	e.ambient_light_energy = 0.8
	e.background_energy_multiplier = 1.25   # 右下の小窓の布に近い明るさ
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.glow_enabled = false
	e.fog_enabled = false
	e.volumetric_fog_enabled = false
	e.sdfgi_enabled = false
	return e


func _make_host(who: Dictionary, at: Vector3) -> Node3D:
	var host := Node3D.new()
	host.position = at
	vp.add_child(host)
	var d := Doll.new()
	d.kind = who.get("kind", "kasa")
	d.outfit = who.get("outfit", [])
	d.facing = Vector3.BACK
	host.add_child(d)
	d.remove_from_group("dolls")   # 世界の家具が探す人形には入れない
	d._next_breath = 1 << 40       # 舞台では白い息を吐かない（体に重なって白いかたまりに見える）
	return host


## 仰向け: 頭が画面の左、足が右、胸が上（少し手前へ向けて顔を見せる）。wobble はコマごとの傾き
func _lay(d: Node3D, host: Node3D, wobble: float) -> void:
	var r := Basis(Vector3.RIGHT, deg_to_rad(-52.0)) * Basis(Vector3.BACK, PI / 2.0 + wobble)
	var q := r.get_rotation_quaternion()
	d.spin_axis = q.get_axis()
	d.spin = q.get_angle()
	d.spin_at = host.global_position + Vector3.UP * 0.5 * _h


func _aim(cam: Camera3D) -> void:
	var span: float = _h * {"win": 2.05, "lose": 1.6, "draw": 1.8}[result]
	var dist := span / 2.0 / tan(deg_to_rad(FOV) / 2.0)
	var mid_y: float = {"win": 0.82, "lose": 0.5, "draw": 0.5}[result] * _h
	cam.position = Vector3(0.0, mid_y, dist)
	cam.look_at(Vector3(0.0, mid_y, 0.0))


## いまのコマ（0 から）
func beat() -> int:
	return Doll.frame_index() - _start


## 胴上げのいまの高さ（0〜1）
func toss_now() -> float:
	var t := fposmod(float(beat()), TOSS_T) / TOSS_T
	return 4.0 * t * (1.0 - t)


## まんなか c、直径 d で出す（duel_hud.gd が毎コマ入れる）
func place(c: Vector2, d: float, a: float) -> void:
	modulate.a = a
	_frame.size = Vector2(d, d)
	_frame.position = c - _frame.size / 2.0
	_view.position = Vector2.ZERO
	_view.size = _frame.size
	_over.size = _frame.size
	_over.position = _frame.position
	var u := ui()
	_mat.set_shader_parameter("px", d)
	_mat.set_shader_parameter("hoop_in", HOOP_IN)   # 木の輪を立体で重ねないので、布を輪の際まで張る
	_mat.set_shader_parameter("hoop_out", 1.1)
	_mat.set_shader_parameter("pitch", maxf(SelfCam.STITCH_PX * u, 2.2))
	_frame.queue_redraw()
	_over.queue_redraw()


func _process(_dt: float) -> void:
	var k := beat()
	match result:
		"win":
			_host.position.y = toss_now() * TOSS_H * _h
			_lay(_doll, _host, 0.14 * sin(k * 0.8))
		"lose":
			_host.position.y = 0.06 * _h * (1.0 if k % 3 == 0 else 0.0)
			_lay(_doll, _host, 0.14 * (1.0 if k % 4 < 2 else -1.0))
		_:
			pass


class Over extends Control:
	var stage: Control

	func _draw() -> void:
		var d := size.x
		var c := size / 2.0
		if stage.result == "win":
			var away: float = clampf(stage.toss_now() * 2.5, 0.0, 1.0)   # 人形が下りてきた所で手袋が上がり、放り上げると下がる
			var y := d * (0.25 + 0.13 * away)
			var sc := d / 64.0 * 0.62
			for side in [-1.0, 1.0]:
				Icons._o = c + Vector2(side * d * 0.17, y)
				Icons._s = sc
				Icons.mitten(self, Vector2.ZERO, side * 0.18, stage.mitten_col, 1.0, true, 1.0)
		if stage.sub != "":
			var b := c + Vector2(-d * 0.36, d * 0.36)
			var r := d * 0.105
			Icons.screen()
			Icons.patch(self, Icons.circ(b, r, 24), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			if stage.sub == "time":
				Icons._o = b
				Icons._s = r / 24.0
				Icons._hourglass(self, 1.0)
			else:
				Icons._o = b + Vector2(0, r * 0.62)
				Icons._s = r / 32.0
				Icons.doll(self, Vector2.ZERO, Icons.PAPER_EDGE, "stand", 0.8)
				Icons._o = b
				Icons._s = r / 18.0
				Icons.thread(self, PackedVector2Array([Vector2(-9, -9), Vector2(9, 9)]), Icons.RED, 3.0, 1.0)
				Icons.thread(self, PackedVector2Array([Vector2(9, -9), Vector2(-9, 9)]), Icons.RED, 3.0, 1.0)
