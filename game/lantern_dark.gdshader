// 黒いランタン（lantern.gd の is_black）の、持ち主を中心にした暗がりの球。
// 球の中を通る視線の長さに応じて、うしろに見えている物を墨の色へ寄せる（掛け算で暗くするので、色みはずれない）。
// 濃さは球の芯ほど濃く（1 - (r/R)^2）、縁では 0。球の中にある物（人形・雪・木）は、その手前までの長さで暗くなる。
// カメラが球の中にいても効くよう、裏の面を描き、奥行きは深さの絵（DEPTH_TEXTURE）で自分で見る
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

uniform float radius = 3.0;           // 球の半径 (m)
uniform float strength = 0.85;        // 芯を通る視線での濃さ（0〜1）
uniform float level = 1.0;            // 点け消し・揺らぎ（0〜1）
uniform vec3 ink : source_color = vec3(0.02, 0.02, 0.05);   // 墨の色（少し藍）
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	vec3 d = normalize(VERTEX);
	vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 o = -center;                 // 球の芯から見たカメラ
	float b = dot(o, d);
	float c0 = dot(o, o);
	float disc = b * b - (c0 - radius * radius);
	if (disc <= 0.0) {
		discard;
	}
	float sq = sqrt(disc);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_t = length(v.xyz / v.w);
	float t0 = max(-b - sq, 0.0);
	float t1 = min(-b + sq, scene_t);
	if (t1 <= t0) {
		discard;
	}
	// 濃さ (1 - |p|^2 / R^2) を視線に沿って足す。|p|^2 = c0 + 2 b t + t^2
	float r2 = radius * radius;
	float f1 = t1 - (c0 * t1 + b * t1 * t1 + t1 * t1 * t1 / 3.0) / r2;
	float f0 = t0 - (c0 * t0 + b * t0 * t0 + t0 * t0 * t0 / 3.0) / r2;
	float x = clamp((f1 - f0) / (radius * 4.0 / 3.0), 0.0, 1.0);   // 芯を通って向こうの縁までで 1
	ALBEDO = ink;
	ALPHA = strength * level * (1.0 - exp(-3.0 * x)) / (1.0 - exp(-3.0));
}
