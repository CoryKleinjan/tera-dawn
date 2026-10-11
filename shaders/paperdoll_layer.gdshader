shader_type spatial;
// A layer of the dressed hero (hair, face, gear) in the 3D stage: like a shaded, alpha-cut,
// smoothly filtered Sprite3D (TDStage.style_sprite), with the characters' light floor.
render_mode cull_disabled, specular_disabled, alpha_to_coverage;

#include "res://shaders/character_light.gdshaderinc"
#include "res://shaders/gear_tint.gdshaderinc"

// The layer's strip (its frames are regions of it).
uniform sampler2D strip : source_color, filter_linear;
// Its colour (sRGB): multiplied in, or with `gear` the item colour gear_tint() shades it in.
uniform vec4 tint = vec4(1.0);
uniform bool gear = false;

void fragment() {
	vec4 c = texture(strip, UV);
	if (gear) {
		// the strip is sampled in linear colour: shade it in sRGB, then back
		c.rgb = pow(gear_tint(pow(c.rgb, vec3(1.0 / 2.2)), tint.rgb), vec3(2.2));
	} else {
		c.rgb *= tint.rgb; // as a modulate: straight onto the linear colour
	}
	c *= COLOR;
	ALPHA = c.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALBEDO = c.rgb;
	EMISSION = light_floor(c.rgb);
	ROUGHNESS = 1.0;
}
