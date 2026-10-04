shader_type spatial;
// Wingtip vapour ribbons: flat near-white with per-vertex alpha, no lighting or fog.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

void fragment() {
	ALBEDO = vec3(0.97, 0.98, 1.0);
	ALPHA = COLOR.a;
}
