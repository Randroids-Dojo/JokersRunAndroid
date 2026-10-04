// Alpha-blended billboard particles (smoke, spray, dust).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
global uniform vec3 fog_color;
global uniform float fog_density;
varying float vdist;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 t = texture(tex, UV);
	float f = 1.0 - exp(-pow(fog_density * vdist, 2.0));
	ALBEDO = mix(COLOR.rgb, fog_color, clamp(f, 0.0, 1.0));
	ALPHA = t.a * COLOR.a;
}
