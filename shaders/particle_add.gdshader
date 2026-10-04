// Additive billboard particles (fire, sparks, flashes). Fog fades them like the web build.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
global uniform float fog_density;
varying float vdist;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float a = texture(tex, UV).a * COLOR.a;
	float f = 1.0 - exp(-pow(fog_density * vdist, 2.0));
	ALBEDO = COLOR.rgb * a * (1.0 - f);
	ALPHA = 1.0;
}
