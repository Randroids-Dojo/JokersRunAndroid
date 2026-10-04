// Shared lighting: approximates three.js MeshStandardMaterial under a HemisphereLight (1.15),
// a DirectionalLight (2.6), up to three explosion point lights, and FogExp2.
#include "res://shaders/tone.gdshaderinc"
global uniform vec3 sun_dir;
global uniform vec3 sun_color;
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
global uniform vec3 fog_color;
global uniform float fog_density;
global uniform vec4 flash0;
global uniform vec4 flash1;
global uniform vec4 flash2;

vec3 flash_light(vec4 f, vec3 p, vec3 n) {
	vec3 d = f.xyz - p;
	float dist = length(d);
	float cut = pow(max(0.0, 1.0 - pow(dist / 900.0, 4.0)), 2.0);
	float att = f.w * 1000.0 * cut / max(pow(dist, 1.6), 0.01);
	return vec3(1.0, 0.36, 0.08) * att * max(dot(n, d / max(dist, 0.001)), 0.0);
}

vec3 shade(vec3 albedo, vec3 n, vec3 p, vec3 cam, float rough, float metal) {
	const float INV_PI = 0.31830988;
	vec3 diffuse = albedo * (1.0 - metal);
	vec3 amb = mix(hemi_ground, hemi_sky, n.y * 0.5 + 0.5);
	vec3 sd = normalize(sun_dir);
	float ndl = max(dot(n, sd), 0.0);
	vec3 v = normalize(cam - p);
	vec3 h = normalize(sd + v);
	float shin = max(2.0 / max(pow(rough, 4.0), 0.002) - 2.0, 1.0);
	vec3 f0 = mix(vec3(0.04), albedo, metal);
	vec3 spec = f0 * (shin + 2.0) / 8.0 * pow(max(dot(n, h), 0.0), shin) * ndl;
	vec3 lit = diffuse * INV_PI * (amb + sun_color * ndl) + sun_color * spec * INV_PI;
	vec3 fl = flash_light(flash0, p, n) + flash_light(flash1, p, n) + flash_light(flash2, p, n);
	lit += diffuse * INV_PI * fl;
	return lit;
}

// MeshStandardMaterial + FogExp2: tone map, encode, then fog in display space (three.js
// applies fog after the colour-space conversion).
vec3 apply_fog(vec3 c, float dist) {
	float f = 1.0 - exp(-pow(fog_density * dist, 2.0));
	return mix(to_display(c), srgb_encode(fog_color), clamp(f, 0.0, 1.0));
}

vec3 flat_normal(vec3 view_pos, mat4 inv_view) {
	vec3 nv = normalize(cross(dFdx(view_pos), dFdy(view_pos)));
	if (dot(nv, view_pos) > 0.0) nv = -nv;
	return normalize((inv_view * vec4(nv, 0.0)).xyz);
}
