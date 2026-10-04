shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
varying float vdist;
void vertex() { vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz); }
void fragment() { ALBEDO = color.rgb * clamp(vdist, 0.0, 1.0); }
