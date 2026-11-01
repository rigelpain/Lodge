shader_type spatial;
// 透明なビニール（塩化ビニールの窓）: 正面からはほとんど透けて、浅い角度ほど白く曇る。
// 薄い膜のしわ（ノイズを凹凸に）が光をやわらかく拾い、しわの筋だけ少し白い。つるつるのガラスにしない（cook_motion.gd）
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.95, 0.97, 0.98, 1.0);
uniform float clear = 0.04;          // 正面から見た濃さ
uniform float haze = 0.42;           // 浅い角度で見た白い曇り
uniform float crease = 0.1;          // しわの筋の白さ
uniform float scale = 0.9;           // しわの細かさ（1 m あたり）
uniform sampler2D wrinkle : hint_normal, filter_linear_mipmap, repeat_enable;   // しわの凹凸
uniform sampler2D lines : filter_linear_mipmap, repeat_enable;                  // しわの筋（ノイズの等高線）

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 uv = lp.xy * scale;
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float n = texture(lines, uv).r;
	float line = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
	ALBEDO = tint.rgb;
	NORMAL_MAP = texture(wrinkle, uv).rgb;
	NORMAL_MAP_DEPTH = 0.5;
	ROUGHNESS = 0.38;
	SPECULAR = 0.45;
	ALPHA = clamp(clear + haze * f + crease * line, 0.0, 0.85);
}
