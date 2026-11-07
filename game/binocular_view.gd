extends CanvasLayer
## のぞいているときの画面の窓（player.gd の peek）: 濃いフェルトの覆いに丸い穴が 2 つ、縁は白糸のなみ縫い。字は使わない。
## テラスの台は時間が来ると穴がすぼんで閉じる。残りは、覆いの下の縫い目の長さで見せる（ほどけて短くなる）。
## 重いことはしない: 画面いっぱいの 1 枚のシェーダーだけ

const SHADER := """
shader_type canvas_item;
uniform float aspect = 1.78;
uniform float open = 1.0;     // 穴の開き（0 閉じている … 1 開いている）
uniform float left = -1.0;    // 残りの縫い目（0〜1。負なら出さない）

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = 0.40 * open;
	float sep = 0.255;
	float d1 = length(p - vec2(-sep, 0.0));
	float d2 = length(p - vec2(sep, 0.0));
	float d = min(d1, d2);
	float cover = smoothstep(r - 0.006, r + 0.002, d);
	// 濃いフェルトの毛羽
	vec2 q = floor(p * 520.0);
	float fib = hash(q) * 0.05 + hash(floor(p * 170.0)) * 0.035;
	vec3 felt = vec3(0.075, 0.08, 0.10) + fib;
	// 縁のなみ縫い（2 つの穴の外まわりだけ）
	float sr = r + 0.024;
	float a1 = atan(p.y, p.x + sep);
	float a2 = atan(p.y, p.x - sep);
	float s1 = step(abs(d1 - sr), 0.0042) * step(0.42, fract(a1 * 19.0 / 3.14159)) * step(sr, d2);
	float s2 = step(abs(d2 - sr), 0.0042) * step(0.42, fract(a2 * 19.0 / 3.14159)) * step(sr, d1);
	float stitch = max(s1, s2) * step(0.2, open);
	felt = mix(felt, vec3(0.90, 0.87, 0.78), stitch);
	// 残りの縫い目: 覆いの下の真ん中から両へ
	if (left >= 0.0 && abs(p.y - 0.455) < 0.0065 && abs(p.x) < 0.42 * left) {
		felt = mix(felt, vec3(0.90, 0.87, 0.78), step(0.38, fract(p.x * 24.0)));
	}
	// 穴の内の縁を少し暗く（筒の中をのぞいている）
	float inner = smoothstep(r - 0.075, r, d) * 0.45;
	COLOR = vec4(felt * cover, max(cover, inner));
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 40    # 手形の輪や持ち物の列より上（のぞいている間、HUD は隠す）
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	visible = false


## 毎コマ: open は穴の開き、left は残りの割合（負なら縫い目を出さない）
func show_view(open: float, left: float) -> void:
	visible = true
	var s := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", s.x / maxf(s.y, 1.0))
	_mat.set_shader_parameter("open", open)
	_mat.set_shader_parameter("left", left)
