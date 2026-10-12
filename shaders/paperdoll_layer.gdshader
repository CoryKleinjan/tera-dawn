shader_type spatial;
// A layer of the dressed hero (hair, face, gear) in the 3D stage: like a shaded, soft-edged,
// smoothly filtered Sprite3D (TDStage.style_sprite), drawn as paperdoll_stage.gdshaderinc says.
render_mode cull_disabled, specular_disabled, depth_prepass_alpha;

#include "res://shaders/gear_tint.gdshaderinc"
#include "res://shaders/paperdoll_piece.gdshaderinc"
#include "res://shaders/paperdoll_stage.gdshaderinc"
#include "res://shaders/paperdoll_stride.gdshaderinc"

// The layer's strip (its frames are regions of it). Not repeated: art touching a frame's
// bottom edge would otherwise wrap to its top as a thin line over his head.
uniform sampler2D strip : source_color, filter_linear_mipmap, repeat_disable;
// Its colour (sRGB): multiplied in, or with `gear` the item colour gear_tint() shades it in.
uniform vec4 tint = vec4(1.0);
uniform bool gear = false;

void fragment() {
	// the strip is sampled in linear colour; `tint` is sRGB, as in the menus
	vec3 back, front;
	stride_from(UV, vec2(textureSize(strip, 0)), back, front);
	vec4 c = stride_over(strip_texel(strip, front.xy) * front.z, strip_texel(strip, back.xy) * back.z);
	if (gear) {
		// shade it in sRGB, then back
		c.rgb = pow(gear_tint(pow(c.rgb, vec3(1.0 / 2.2)), tint.rgb), vec3(2.2));
	} else {
		// the same as multiplying in sRGB
		c.rgb *= pow(tint.rgb, vec3(2.2));
	}
	c *= COLOR;
	ALPHA = c.a * tint.a * fist_cut(UV) * hair_cut_at(UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
