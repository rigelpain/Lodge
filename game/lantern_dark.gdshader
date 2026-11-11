// 黒いランタン（lantern.gd の is_black）の、持ち主を中心にした暗がりの球。
// 暗さは絶対（代表「黒ランタンは相対的な暗さでなく絶対的な暗さにしてほしい」）: 球の芯では、うしろに見えている物の明るさを cap より上に
// させない（焚き火のそばでも昼でも、同じ暗さ）。明るさ（いちばん明るい成分 L）は cap * L / (L + cap) に縮める（暗い所の差は少し残る。色合いはそのまま）。
// 混ぜ具合は、球の中で見えている所（視線の、球に入ってから物に当たるまで）が芯にいちばん近づく所の、芯からの距離 r で決める:
// r が inner * R より内なら 1（暗さそのもの）、縁 R へ向かってなめらかに 0。球の中のどこを見ても、芯の近くは同じ暗さ
// カメラが球の中にいても効くよう、裏の面を描き、奥行きは深さの絵（DEPTH_TEXTURE）で自分で見る
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

uniform float radius = 3.0;           // 球の半径 (m)
uniform float strength = 1.0;         // 芯を通る視線での効き（0〜1。1 で芯は cap の暗さそのもの）
uniform float cap = 0.035;            // 芯での明るさの上限（明るさ。夜の雪の数分の一）
uniform float level = 1.0;            // 点け消し・揺らぎ（0〜1）
uniform float inner = 0.55;           // この割合の半径までは、暗さそのもの
uniform vec3 ink : source_color = vec3(0.02, 0.02, 0.05);   // 墨の色（少し藍）
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

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
	float tc = clamp(-b, t0, t1);         // 見えている所で、芯にいちばん近い所
	float r = length(o + d * tc);
	float w = 1.0 - smoothstep(inner * radius, radius, r);
	vec3 bg = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float lum = max(max(bg.r, max(bg.g, bg.b)), 1e-4);   // いちばん明るい成分（鮮やかな青や赤も、明るさの上限に入れる）
	vec3 dark = bg * (cap / (lum + cap)) + ink * cap;   // 明るさを cap * L / (L + cap) に縮め、墨を少し
	ALBEDO = dark;
	ALPHA = strength * level * w;
}
