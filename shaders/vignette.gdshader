// Red damage vignette (radial, transparent centre).
shader_type canvas_item;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 1.0);
	float r = length(d) / 0.7071;
	float a = smoothstep(0.55, 1.0, r);
	COLOR = vec4(0.67, 0.0, 0.0, a * 0.75);
}
