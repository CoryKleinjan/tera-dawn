// How the dressed hero and his layers are drawn in the 3D stage (paperdoll_sprite.gdshader,
// paperdoll_layer.gdshader), so he looks like his picture in the menus (PaperdollView):
// - His strips are cut at twice the detail he shows at, and at his size (HeroBody.SCALE) and
//   the camera's zoom one strip pixel shows at only about 0.6-0.7 screen pixels. They're
//   sampled from mipmaps (each strip's .import has mipmaps on) so his outline and painted
//   texture shrink smoothly instead of skipping pixels into stair steps and broken lines.
// - Edges blend over what's behind (depth_prepass_alpha, like the other characters'
//   ALPHA_CUT_OPAQUE_PREPASS) instead of being cut on/off; PaperdollSprite gives each layer
//   its own render priority so their soft edges stack in the right order, over the scenery.

// Leans toward the sharper mipmap: the blend between levels is meant for 3D surfaces at a
// slant, and on a sprite facing the camera it softens him more than shrinking does.
const float STRIP_LOD_BIAS = -0.5;

vec4 strip_texel(sampler2D strip, vec2 uv) {
	return texture(strip, uv, STRIP_LOD_BIAS);
}
