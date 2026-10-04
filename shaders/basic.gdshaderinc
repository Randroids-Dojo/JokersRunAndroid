// Port of three.js MeshBasicMaterial as the web build uses it: colour x map x instance
// colour, optional tone mapping, display-space output.
#include "res://shaders/tone.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform bool tone_mapped = false;
uniform bool use_fog = false;
global uniform vec3 fog_color;
global uniform float fog_density;
varying float vdist;

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 t = texture(tex, UV);
	// `color` is decoded to linear by source_color; texels and vertex colours are linear-multiplied.
	vec3 lin = color.rgb * srgb_decode(t.rgb) * COLOR.rgb;
	vec3 c = tone_mapped ? to_display(lin) : srgb_encode(lin);
	if (use_fog) {
		float f = 1.0 - exp(-pow(fog_density * vdist, 2.0));
		c = mix(c, srgb_encode(fog_color), clamp(f, 0.0, 1.0));
	}
	ALBEDO = c;
	ALPHA = color.a * t.a * COLOR.a;
}
