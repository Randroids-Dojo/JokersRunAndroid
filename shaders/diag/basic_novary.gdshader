shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
void fragment() { ALBEDO = color.rgb; ALPHA = color.a; }
