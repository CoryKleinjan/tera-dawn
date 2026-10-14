shader_type spatial;
// A layer of the dressed hero (hair, face, gear) in the 3D stage: like a shaded, soft-edged,
// smoothly filtered Sprite3D (TDStage.style_sprite), drawn as paperdoll_stage.gdshaderinc says.
render_mode cull_disabled, specular_disabled, depth_prepass_alpha;

#include "res://shaders/paperdoll_piece.gdshaderinc"
#include "res://shaders/paperdoll_stage.gdshaderinc"

// The layer's strip (its frames are regions of it). Not repeated: art touching a frame's
// bottom edge would otherwise wrap to its top as a thin line over his head.
uniform sampler2D strip : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 c = strip_texel(strip, UV);
	c *= COLOR;
	ALPHA = c.a * fist_cut(UV) * hair_cut_at(UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
