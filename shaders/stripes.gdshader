// Hazard stripes behind the WARNING banner (repeating -45deg, 26px bands, 3px red rules).
shader_type canvas_item;
uniform vec2 rect_size = vec2(844.0, 82.0);
void fragment() {
	vec2 px = UV * rect_size;
	float s = mod(px.x + px.y, 52.0) < 26.0 ? 1.0 : 0.0;
	vec4 c = mix(vec4(0.078, 0.0, 0.0, 0.85), vec4(0.784, 0.078, 0.078, 0.85), s);
	if (px.y < 3.0 || px.y > rect_size.y - 3.0) c = vec4(1.0, 0.231, 0.188, 1.0);
	COLOR = c;
}
