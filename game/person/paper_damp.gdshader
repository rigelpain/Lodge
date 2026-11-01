// 紙の人形の湿り気（damp.gd）を見た目にする。焼いた人形の材質（色の絵・法線の絵・粗さ 0.9・両面）をそのまま写し、
// wet（0 乾いている 〜 1 びしょびしょ）と crisp（0 ふつう 〜 1 パリパリ）を足す。doll.gd が人形ごとに入れる。
//   湿る: 紙が水を吸って色が濃くなる。水のシミが UV の上に広がり、シミの縁は濃い輪になる（潮じみ）。
//         濡れた所は艶が出て（粗さが下がる）、後ろからの光が透ける。紙が波打ち（コックリング）、しわの陰が深くなる。
//         芯から離れた所（笠のつば・肩・袖）ほど重さで垂れ、全体が少し縮む（ふにゃっと）
//   パリッと: 乾いて色が明るく澄み、艶のない張った面になる（しわが浅い）。縁に乾いた明るさが立つ
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float crisp : hint_range(0.0, 1.0) = 0.0;
uniform float top = 1.4;          // 人形の背丈（glb の座標）。垂れる量を背丈に合わせる
uniform float seed = 0.0;         // 人ごとにシミの所を変える
uniform vec3 stain_tint = vec3(0.70, 0.74, 0.86);   // シミの色（濃く、少し青みの灰に沈む）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 3.3) * 0.15;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	// 垂れる: 体の芯（y 軸）から離れた所ほど、離れた距離の 2 乗で下がる。頭より上の笠のつばも垂れる
	float r = length(VERTEX.xz) / top;
	float droop = wet * 0.55 * top * max(r - 0.08, 0.0) * max(r - 0.08, 0.0);
	// 紙の波打ち: 細かい凸凹を法線の向きに（芯からの距離によらず）
	float cockle = (vnoise3(VERTEX * 11.0 / top + seed) - 0.5) * 0.022 * top * wet;
	VERTEX += NORMAL * cockle;
	VERTEX.y -= droop;
	VERTEX.y *= 1.0 - 0.035 * wet;   // 水を吸って、腰が抜けたように少し縮む
}

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	vec3 col = base.rgb;
	// シミ: しきい値を wet で下げると、シミが広がって全体をおおう
	vec2 sp = UV * 9.0 + vec2(seed * 3.1, seed * 1.7);
	float n = fbm(sp);
	float th = mix(1.05, 0.12, wet);
	float soak = smoothstep(th, th - 0.08, n) * step(0.001, wet);
	float rim = (1.0 - smoothstep(0.0, 0.035, abs(n - th))) * step(0.01, wet) * (1.0 - wet * 0.6);   // 潮じみの輪
	float damp = clamp(wet * 0.45 + soak * 0.75, 0.0, 1.0);   // その所の濡れ具合
	vec3 wet_col = mix(col * 0.7, col * col, 0.5) * 1.12 * stain_tint;   // 濃く、色が沈む（2 乗で彩度が少し上がる）
	col = mix(col, wet_col, damp * 0.85);
	col *= 1.0 - rim * 0.28;
	// パリッと: 濃淡が少し締まる。明るさと色はそのまま（明るくすると白く飛ぶ。2026-11-01 代表「明度上げ過ぎ、キャラが白飛びしてる」）
	vec3 crisp_col = (col - 0.5) * 1.08 + 0.5;
	col = mix(col, clamp(crisp_col, 0.0, 1.0), crisp);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.9, 0.38, damp), 0.97, crisp);
	SPECULAR = mix(0.5, 0.65, damp);
	// しわ: 濡れると深く、パリッとすると浅い。波打ちは UV の凸凹の傾きで足す
	vec3 nm = texture(normal_tex, UV).rgb;
	float e = 0.02;
	vec2 g = vec2(fbm(sp * 2.6 + vec2(e, 0.0)) - fbm(sp * 2.6 - vec2(e, 0.0)), fbm(sp * 2.6 + vec2(0.0, e)) - fbm(sp * 2.6 - vec2(0.0, e))) / (2.0 * e);
	nm.xy += g * 0.02 * wet;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0 + 1.6 * wet - 0.45 * crisp;
	// 濡れた紙は光が透ける（後ろからの光で、明るく色づく）
	BACKLIGHT = col * 0.55 * damp;
	// 張った紙の縁の明るさ（控えめに）
	RIM = 0.25 * crisp;
	RIM_TINT = 0.75;
}
