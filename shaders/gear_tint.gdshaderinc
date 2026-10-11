// Colours a greyscale piece of gear (a worn cut, cape, gloves, shield or weapon kind) in its
// item colour, keeping its light and shade: its typical grey shows as the colour itself, darker
// greys run down to a deep shade of it (outlines stay dark) and paler ones up to a light tint
// of it, so dark colours keep their highlights and light ones their shading. Works in sRGB.

// The grey the gear art is mostly drawn in (sRGB, 0-1; paperdoll_layers.lift puts its middle
// grey here): it shows as the item colour.
const float GEAR_MID = 0.78;
// How dark the darkest grey turns (share of the colour) and how pale the palest (towards white).
const float GEAR_DEEP = 0.12;
const float GEAR_LIGHT = 0.35;

vec3 gear_tint(vec3 grey, vec3 colour) {
	float g = dot(grey, vec3(0.299, 0.587, 0.114));
	if (g < GEAR_MID) {
		return colour * mix(GEAR_DEEP, 1.0, g / GEAR_MID);
	}
	return mix(colour, mix(colour, vec3(1.0), GEAR_LIGHT), (g - GEAR_MID) / (1.0 - GEAR_MID));
}
