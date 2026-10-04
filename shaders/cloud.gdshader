// Billboard cloud puffs drawn through a MultiMesh. INSTANCE_CUSTOM = (size, shade, rotation, alpha).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
#include "res://shaders/tone.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 light_col;
uniform vec3 shadow_col;
uniform float flash = 0.0;
uniform float near_fade = 1.0;
uniform float fog_mul = 1.0;
uniform vec3 fog_tint;
global uniform float fog_density;
varying float shade;
varying float alpha;
varying float vdist;

void vertex() {
	vec4 mv = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float c = cos(INSTANCE_CUSTOM.z);
	float s = sin(INSTANCE_CUSTOM.z);
	vec2 q = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c) * INSTANCE_CUSTOM.x;
	mv.xy += q;
	vdist = -mv.z;
	shade = INSTANCE_CUSTOM.y;
	alpha = INSTANCE_CUSTOM.w;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	vec4 t = texture(tex, UV);
	float a = t.a * alpha;
	if (near_fade > 0.5) a *= smoothstep(40.0, 320.0, vdist);
	if (a < 0.01) discard;
	vec3 col = mix(shadow_col, light_col, clamp(shade * 0.7 + t.r * 0.5, 0.0, 1.0));
	col += vec3(0.75, 0.8, 1.0) * flash * t.r;
	float f = 1.0 - exp(-pow(fog_density * fog_mul * vdist, 2.0));
	ALBEDO = to_display(mix(col, fog_tint, clamp(f, 0.0, 1.0)));
	ALPHA = a;
}
