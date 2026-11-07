extends CanvasLayer
## 夜目の双眼鏡の暗視（binoculars.gd の GRADES の night）。のぞいている間だけ、この人の画面だけに効く。通信には乗らない（環境と舞う雪は画面ごとの物）。
## 見え方は白糸の刺繍（2026-11-08 代表が 3 案から選んだ。design/binoculars/10-night-looks.jpg）: 濃い藍の布に、物の輪郭を白糸で縫い、明るい所は斜めのサテン縫いで埋める。
## 実際の暗視から汲み取ったのは、単色・粒の粗さ・丸い視野。緑の画面にはしない。
## 効かせ方: 霧を薄くし、舞う雪を隠し、夜は露出を上げる。やめると元の値へ戻す。
## 天気ができたら: のぞいている間に霧を変えないか、ここの _fog を読み直すこと（いまは始めた時の値へ戻す）。
## 重いことはしない: 画面の絵を読む 1 枚のシェーダーだけ（新しいカメラや描き直しはしない）

const FOG_K := 0.2              # 霧の濃さの倍率。遠くまで見える
const FOG_MAX := 0.0004         # 霧の濃さの上限。吹雪の濃い霧でも、遠くの山の稜線まで届く
const NIGHT_EXPOSURE := 5.0     # 真夜中の露出の倍率。昼は 1 倍へ（daycycle.gd の daylight）

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
vec3 col(vec2 uv) { return texture(screen_texture, uv).rgb; }
void fragment() {
	vec2 e = SCREEN_PIXEL_SIZE * 1.6;
	vec3 dx = col(SCREEN_UV + vec2(e.x, 0)) - col(SCREEN_UV - vec2(e.x, 0));
	vec3 dy = col(SCREEN_UV + vec2(0, e.y)) - col(SCREEN_UV - vec2(0, e.y));
	// 輪郭は色の差で拾う。明るさが同じ空と雪（昼の稜線）も分かれる
	float edge = clamp((length(dx) + length(dy)) * 5.0, 0.0, 1.0);
	float L = pow(clamp(dot(col(SCREEN_UV), vec3(0.3, 0.59, 0.11)), 0.0, 1.0), 0.8);
	vec2 px = FRAGCOORD.xy;
	float hatch = step(0.5, fract((px.x + px.y) / 5.0));          // 斜めのサテン縫い
	float dash = step(0.3, fract((px.x - px.y) / 9.0));
	float fill = smoothstep(0.1, 0.95, L);
	vec3 cloth = vec3(0.05, 0.07, 0.14) + (fract(sin(dot(floor(px / 2.0), vec2(12.9, 78.2))) * 43758.5) * 0.025);
	vec3 thread = vec3(0.96, 0.93, 0.82);
	vec3 c = mix(cloth, mix(vec3(0.20, 0.30, 0.46), thread, fill), hatch * dash * smoothstep(0.08, 0.3, L) * (0.45 + 0.55 * fill));
	c = mix(c, thread, smoothstep(0.25, 0.7, edge));
	COLOR = vec4(c, 1.0);
}
"""

var _env: Environment
var _snow: GPUParticles3D
var _on := false
var _fog := 0.0
var _exposure := 1.0
var _snow_shown := true


func _ready() -> void:
	layer = 39    # のぞく窓（binocular_view.gd の 40）のすぐ下
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	visible = false


func begin(main: Node) -> void:
	if _on:
		return
	for n in main.find_children("*", "WorldEnvironment", true, false):
		_env = (n as WorldEnvironment).environment
		break
	_snow = main.get("snowfall")
	if _env:
		_fog = _env.fog_density
		_exposure = _env.tonemap_exposure
		_env.fog_density = minf(_fog * FOG_K, FOG_MAX)
	if _snow:
		_snow_shown = _snow.visible
		_snow.visible = false
	_on = true
	visible = true
	step()


## 毎コマ: 時刻に合わせて露出を変える
func step() -> void:
	if not _on or _env == null:
		return
	var dc := get_node_or_null("/root/DayCycle")
	var day: float = dc.daylight() if dc else 1.0
	_env.tonemap_exposure = _exposure * lerpf(NIGHT_EXPOSURE, 1.0, day)


func end() -> void:
	if not _on:
		return
	_on = false
	visible = false
	if _env:
		_env.fog_density = _fog
		_env.tonemap_exposure = _exposure
	if _snow:
		_snow.visible = _snow_shown
