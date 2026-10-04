// Ocean: analytic swell normals, fresnel sky reflection, sun glint, shoreline foam from the
// baked terrain, pixel-footprint wave fading. Port of the web ocean shader.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://shaders/tone.gdshaderinc"

uniform float time = 0.0;
uniform vec3 sun_dir;
uniform vec3 sun_col;
uniform vec3 zenith;
uniform vec3 horizon;
uniform vec3 deep;
uniform vec3 shallow_col;
uniform sampler2D land : filter_linear;
uniform vec4 land_rect;
global uniform vec3 fog_color;
global uniform float fog_density;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec2 wave(vec2 p, vec2 dir, float len, float amp, float fade, float px) {
	float k = 6.2831 / len;
	float w = sqrt(9.81 * k);
	float ph = dot(dir, p) * k - w * time;
	fade *= 1.0 - smoothstep(0.06 * len, 0.25 * len, px);
	return dir * (amp * k * cos(ph)) * fade;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 cam = CAMERA_POSITION_WORLD;
	float dist = length(cam - wpos);
	float px = length(fwidth(p));
	float f1 = 1.0 - smoothstep(900.0, 4500.0, dist);
	float f2 = 1.0 - smoothstep(120.0, 700.0, dist);
	vec2 g = vec2(0.0);
	g += wave(p, normalize(vec2(1.0, 0.25)), 210.0, 1.3, 1.0, px);
	g += wave(p, normalize(vec2(0.7, -0.6)), 117.0, 0.7, 1.0, px);
	g += wave(p, normalize(vec2(0.95, 0.55)), 61.0, 0.38, f1, px);
	g += wave(p, normalize(vec2(0.15, 1.0)), 37.0, 0.22, f1, px);
	g += wave(p, normalize(vec2(-0.6, 0.8)), 14.0, 0.08, f2, px);
	g += wave(p, normalize(vec2(0.9, -0.3)), 7.3, 0.035, f2, px);
	vec2 np = p * 0.012 + vec2(time * 0.03, -time * 0.02);
	float n1 = vnoise(np) - vnoise(np + vec2(0.37, 0.0));
	float n2 = vnoise(np) - vnoise(np + vec2(0.0, 0.37));
	g += vec2(n1, n2) * 0.35 * f1;
	g *= mix(0.55, 1.0, f1);
	vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
	vec3 V = normalize(cam - wpos);
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
	vec3 R = reflect(-V, N);
	R.y = abs(R.y);
	vec3 sky = mix(horizon, zenith, pow(clamp(R.y, 0.0, 1.0), 0.5));
	vec2 luv = (p - land_rect.xy) / land_rect.zw;
	float th = -40.0;
	if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) th = texture(land, luv).r * 255.0 / 2.0 - 40.0;
	float depth = -th;
	float sh = 1.0 - smoothstep(0.0, 30.0, depth);
	vec3 water = mix(deep, shallow_col, sh * 0.8 + 0.12);
	vec3 sd = normalize(sun_dir);
	water *= 0.55 + 0.45 * max(dot(N, sd), 0.0);
	float sdr = max(dot(R, sd), 0.0);
	float glint_fade = 1.0 - smoothstep(4.0, 40.0, px);
	float spec = pow(sdr, 900.0) * 2.6 * mix(0.25, 1.0, f1) * glint_fade + pow(sdr, 80.0) * 0.1 * mix(0.4, 1.0, glint_fade);
	vec3 col = mix(water, sky, fres * 0.85) + sun_col * spec;
	float foamN = vnoise(p * 0.07 + vec2(time * 0.15, 0.0)) * 0.6 + vnoise(p * 0.21 - time * 0.2) * 0.4;
	float foam = (1.0 - smoothstep(0.5, 7.0, depth)) * smoothstep(0.35, 0.7, foamN + (1.0 - smoothstep(0.0, 4.0, depth)) * 0.5);
	col = mix(col, vec3(0.92, 0.95, 0.97), foam * 0.85 * f2 + foam * 0.3 * (1.0 - f2));
	float fo = 1.0 - exp(-pow(fog_density * dist, 2.0));
	ALBEDO = to_display(mix(col, fog_color, clamp(fo, 0.0, 1.0)));
}
