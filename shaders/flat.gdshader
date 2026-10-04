// Flat-shaded, vertex-coloured models (aircraft, ships, bridge, missiles).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
#include "res://shaders/lighting.gdshaderinc"

uniform float roughness = 0.55;
uniform float metallic = 0.35;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = flat_normal(VERTEX, INV_VIEW_MATRIX);
	vec3 c = shade(COLOR.rgb, n, wpos, CAMERA_POSITION_WORLD, roughness, metallic);
	ALBEDO = apply_fog(c, length(CAMERA_POSITION_WORLD - wpos));
}
