// Sky gradient, sun glow, horizon haze and the storm band, drawn on a camera-centred dome
// just inside the far plane like the web build's sky mesh (no radiance cubemap to update on
// mobile GPUs). It writes no depth, so everything nearer draws over it.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/tone.gdshaderinc"

uniform vec3 zenith;
uniform vec3 horizon;
uniform vec3 fog_col;
uniform vec3 sun_dir;
uniform vec3 sun_col;
uniform float flash = 0.0;
uniform vec3 storm_dir;
varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	float y = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.5));
	col = mix(col, fog_col * 0.92, 1.0 - smoothstep(-0.08, 0.0, y));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_col * (pow(s, 1500.0) * 25.0 + pow(s, 40.0) * 0.35 + pow(s, 6.0) * 0.12);
	col = mix(col, fog_col, exp(-abs(y) * 16.0) * 0.55);
	float st = max(dot(normalize(vec3(d.x, 0.0, d.z)), storm_dir), 0.0);
	float band = smoothstep(0.6, 0.98, st) * exp(-max(y, 0.0) * 9.0);
	col = mix(col, vec3(0.25, 0.28, 0.33), band * 0.55);
	col += vec3(0.6, 0.65, 0.8) * flash * band;
	ALBEDO = to_display(col);
}
