shader_type spatial;
// The dressed hero standing in the 3D stage: like a shaded, alpha-cut, smoothly filtered Sprite3D (TDStage.style_sprite).
render_mode cull_disabled, specular_disabled, alpha_to_coverage;

#define LINEAR_COLOR
#include "res://shaders/paperdoll.gdshaderinc"

uniform sampler2D strip : source_color, filter_linear;

void fragment() {
	vec4 c = dress(texture(strip, UV), UV) * COLOR;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
