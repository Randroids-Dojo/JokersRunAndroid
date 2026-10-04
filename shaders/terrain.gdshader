// Peninsula terrain: a native grid displaced from the baked height field, with the web
// build's per-vertex colouring (grass, rock, cliff, snow, sand, wet shore) and flat shading.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
#include "res://shaders/lighting.gdshaderinc"

uniform sampler2D heights : filter_nearest;
uniform vec2 grid_half;
uniform float cell;
uniform ivec2 grid_n;
varying vec3 wpos;
varying vec3 vcol;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float h_at(ivec2 c) { return texelFetch(heights, clamp(c, ivec2(0), grid_n - ivec2(1)), 0).r; }

void vertex() {
	ivec2 c = ivec2(int(round((VERTEX.x + grid_half.x) / cell)), int(round((VERTEX.z + grid_half.y) / cell)));
	float h = h_at(c);
	VERTEX.y = h;
	float hl = h_at(c - ivec2(1, 0));
	float hr = h_at(c + ivec2(1, 0));
	float hu = h_at(c - ivec2(0, 1));
	float hd = h_at(c + ivec2(0, 1));
	float slope = length(vec2(hr - hl, hd - hu)) / (2.0 * cell);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sand = lin(vec3(0.72, 0.66, 0.5));
	vec3 wet = lin(vec3(0.3, 0.32, 0.27));
	vec3 grassA = lin(vec3(0.27, 0.39, 0.19));
	vec3 grassB = lin(vec3(0.42, 0.46, 0.25));
	vec3 cliff = lin(vec3(0.56, 0.47, 0.37));
	vec3 rock = lin(vec3(0.46, 0.45, 0.44));
	vec3 snow = lin(vec3(0.92, 0.94, 0.97));
	float n = vnoise(wpos.xz / 260.0);
	vec3 col = mix(grassA, grassB, n);
	col = mix(col, rock, smoothstep(380.0, 620.0, h));
	col = mix(col, snow, smoothstep(690.0, 760.0, h) * (1.0 - smoothstep(0.9, 1.4, slope)));
	col = mix(col, h < 260.0 ? cliff : rock, smoothstep(0.55, 1.0, slope));
	col = mix(col, sand, (1.0 - smoothstep(4.0, 14.0, h)) * (1.0 - smoothstep(0.35, 0.7, slope)));
	if (h < 0.0) col = mix(col, wet, 1.0 - smoothstep(-10.0, 0.0, h));
	col *= 0.94 + 0.12 * vnoise(wpos.xz / 41.0);
	vcol = col;
}

void fragment() {
	vec3 nrm = flat_normal(VERTEX, INV_VIEW_MATRIX);
	vec3 c = shade(vcol, nrm, wpos, CAMERA_POSITION_WORLD, 0.96, 0.0);
	ALBEDO = apply_fog(c, length(CAMERA_POSITION_WORLD - wpos));
}
