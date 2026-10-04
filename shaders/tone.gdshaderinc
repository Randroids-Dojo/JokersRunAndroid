// Display-referred output, exactly like the web build: three.js ACESFilmic tone mapping
// (exposure 1.05) and sRGB encoding happen per material, so blending happens on display
// values as in the browser. The environment runs a linear tonemapper plus an inverse-sRGB
// colour-correction LUT, which makes the final pass an identity on these values.
const float TONE_EXPOSURE = 1.05;

vec3 aces_three(vec3 c) {
	const mat3 ACES_IN = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
	const mat3 ACES_OUT = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
	c *= TONE_EXPOSURE / 0.6;
	c = ACES_IN * c;
	vec3 a = c * (c + 0.0245786) - 0.000090537;
	vec3 b = c * (0.983729 * c + 0.4329510) + 0.238081;
	return clamp(ACES_OUT * (a / b), 0.0, 1.0);
}

vec3 srgb_encode(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(pow(c, vec3(0.41666)) * 1.055 - vec3(0.055), c * 12.92, vec3(lessThanEqual(c, vec3(0.0031308))));
}

vec3 srgb_decode(vec3 c) {
	return mix(pow(c * 0.9478673 + vec3(0.0521327), vec3(2.4)), c * 0.0773994, vec3(lessThanEqual(c, vec3(0.04045))));
}

// Scene-linear colour -> what the browser would put on screen.
vec3 to_display(vec3 lin) {
	return srgb_encode(aces_three(lin));
}
