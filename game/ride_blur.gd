extends Node3D
## 速いときの、画面の端の流れるぼかし（あなたの画面だけ）。
## 2026-11-14 代表「速度表現として画面周囲にブラーかけたりなんか効果つけたりすることってある？いまMAXのスピード出ててもいまいち恐怖を感じるほどではなくて」
## 描き終えた景色を、端だけ、景色が流れる向きに引きのばす。真ん中は空けて、行く先ははっきり見える。
## 流れる向きは、進む向きとカメラの向きから求める（前を見ていれば真ん中から外へ、横を見ていれば横へ流れる）。
## 自分の手・乗っているソリ・一緒に乗っている人は、あなたと一緒に動いているのでぼかさない（目からの近さで分ける。KEEP）。
## 滑るときの風の毛糸や舞う雪（透ける物）は、このあとに描かれるので、ぼけずに上に重なる。
## 強さは滑るときの風の上の段（ride_wind.gd の rush_of: 9 m/s から出て 26 m/s で満ちる）と同じで、遅いうちは何もしない。
## 重さ: 効いているあいだだけ、景色と奥行きの写しを 1 回ずつと、端の画素で TAPS 回の読み出し（3D の描画の解像度で）。
## 止まっている・遅いときは面を隠すので 0。いちばん軽い画質（ガビガビ）のあいだは出さない。
## 画面いっぱいの面を 1 枚、層 5 に置く（あなたのカメラだけが映す。右上の 360° 映像・右下の自分の姿・ほかの人には出ない）

const RideWind := preload("res://ride_wind.gd")
const LAYER := 1 << 4
const REACH := 0.14     # 引きのばす長さ。前へ進んでいるとき、画面の端で「真ん中からの距離 × これ」
const CLEAR_R := 0.24   # 真ん中の、ぼかさない半径（画面の高さに対する割合）
const EDGE_W := 0.4     # そこから外へ、この幅でぼかしが満ちる
const KEEP := Vector2(1.1, 2.4)   # 目からこの近さ (m) まではぼかさず、ここから先は全部ぼかす

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, cull_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float amount = 0.0;               // 強さ（0〜1）
uniform vec3 move = vec3(0.0, 0.0, -1.0); // 進む向き（カメラから見た向き。-z が前）
uniform float reach = 0.14;
uniform float clear_r = 0.24;
uniform float edge_w = 0.4;
uniform vec2 keep = vec2(1.1, 2.4);
const int TAPS = 10;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // 画面いっぱい
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float aspect = abs(PROJECTION_MATRIX[1][1] / PROJECTION_MATRIX[0][0]);
	float edge = smoothstep(clear_r, clear_r + edge_w, length(vec2(c.x * aspect, c.y))) * amount;
	if (edge < 0.004) {
		discard;
	}
	// この画素に映っている所（カメラから見た向きと、目からの遠さ）
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).x, 1.0);
	v.xyz /= v.w;
	edge *= smoothstep(keep.x, keep.y, -v.z);
	if (edge < 0.004) {
		discard;
	}
	// 視野の面の上の点 p の景色は、進む向き move に対して -(move.xy + p * move.z) の向きへ流れる
	vec2 p = v.xy / -v.z;
	vec2 f = -(move.xy + p * move.z);
	vec2 d = 0.5 * vec2(PROJECTION_MATRIX[0][0] * f.x, PROJECTION_MATRIX[1][1] * f.y) * reach * edge;
	// 読み出す所を画素ごとに少しずらして、段々の筋を消す（並びのそろった細かい模様。ざらつかない）
	float j = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec3 sum = texture(screen_tex, SCREEN_UV).rgb;
	float n = 1.0;
	for (int i = 0; i < TAPS; i++) {
		vec2 uv = SCREEN_UV - d * (float(i) + j) / float(TAPS);
		// 近くの物（自分の手やソリ）の色は、まわりへ引きのばさない
		float z = texture(depth_tex, uv).x;
		float far = -(INV_PROJECTION_MATRIX[2][2] * z + INV_PROJECTION_MATRIX[3][2]) / (INV_PROJECTION_MATRIX[2][3] * z + INV_PROJECTION_MATRIX[3][3]);
		float w = smoothstep(keep.x, keep.y, far);
		sum += texture(screen_tex, uv).rgb * w;
		n += w;
	}
	ALBEDO = sum / n;
	ALPHA = min(1.0, edge * 5.0);
}
"""

var player: CharacterBody3D
var strength := 1.0   # 設定「速いときに画面の端が流れてぼける」: 0〜1
var gabi := false     # いちばん軽い画質のあいだは出さない（main.gd が入れる）
var level := 0.0      # いまの強さ（0〜1。確かめ用に外から読む）
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _move := Vector3(0, 0, -1)


func setup(p: CharacterBody3D) -> void:
	player = p


func _ready() -> void:
	name = "RideBlur"
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = -100   # 透ける物のうち、いちばん先に描く（風の毛糸・舞う雪・息は、ぼけた景色の上に重なる）
	_mat.set_shader_parameter("reach", REACH)
	_mat.set_shader_parameter("clear_r", CLEAR_R)
	_mat.set_shader_parameter("edge_w", EDGE_W)
	_mat.set_shader_parameter("keep", KEEP)
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	_quad.material_override = _mat
	_quad.layers = LAYER
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0   # 画面いっぱいに描くので、置いた所で見切らない
	_quad.top_level = true
	_quad.visible = false
	add_child(_quad)


func _process(dt: float) -> void:
	if player == null:
		return
	var riding: bool = player.mode == player.Mode.RIDE and is_instance_valid(player.sled)
	var v: Vector3 = player.sled.linear_velocity if riding else Vector3.ZERO
	var speed := v.length()
	var want := RideWind.rush_of(speed) * strength if riding and not gabi else 0.0
	level = move_toward(level, want, dt * (0.8 if want > level else 2.5))
	_quad.visible = level > 0.01
	if not _quad.visible:
		return
	var cam: Camera3D = player.cam
	if speed > 0.5:
		_move = cam.global_basis.orthonormalized().inverse() * (v / speed)
	_quad.global_position = cam.global_position
	_mat.set_shader_parameter("amount", level)
	_mat.set_shader_parameter("move", _move)
