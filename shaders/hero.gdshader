shader_type spatial;
// The one way the hero is painted. Every part of him (body, hair, gear, held pieces), in the
// world and in the menus (PaperdollView), is drawn with this shader and nothing else; only the
// light differs (the map's in the world, a near-white one in the menus). Each part sets just
// the cut-outs it needs: the body its hat's head cut, a hair layer its hat's hair cut, a held
// piece its fist cut.
render_mode cull_disabled, specular_disabled, depth_prepass_alpha;

// How he is drawn in the 3D stage:
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

// Dresses the hero's body (see Paperdoll), drawn in its painted colours. Under a hat, the hat
// shape's head cut strip (headcut_<shape>.png, laid out like the body strip) cuts away what
// would poke out of it.

uniform bool has_head_cut = false;
uniform sampler2D head_cut : filter_linear;

vec4 dress(vec4 src, vec2 uv) {
	vec4 c = src;
	if (has_head_cut) {
		c.a *= 1.0 - texture(head_cut, uv).a;
	}
	return c;
}

// A piece of the dressed hero (Paperdoll.Piece: a weapon, shield or hat placed on him each
// frame): a weapon's fingers-over-the-grip cut. The piece's pixel at `uv` is found on the body
// frame from its pose, and is cut away where the fist mask strip (fist_<kind>.png, a frame of
// FRAME_SIZE per body frame) has his fingers. Paperdoll.Layer.apply_pose sets the pose.

uniform bool has_fist = false;
uniform bool fist_on = false;
uniform sampler2D fist : filter_linear;
uniform vec2 frame_size = vec2(256.0, 208.0);
uniform float frame = 0.0;
uniform vec2 at = vec2(0.0);
uniform vec2 anchor = vec2(0.0);
uniform float turn = 0.0;
uniform float grow = 1.0;
uniform vec2 picture_size = vec2(1.0);
// A hair layer under a hat: the hat's hair cut strip (haircut_<hat>.png, laid out like the
// hair strip), white where his hair is hidden so none pokes out of the hat's top or sides.
uniform bool has_hair_cut = false;
uniform sampler2D hair_cut : filter_linear;

// 1.0 where the piece shows at texture coordinate `uv`, 0.0 where his fingers cover it.
float fist_cut(vec2 uv) {
	if (!has_fist || !fist_on) {
		return 1.0;
	}
	vec2 p = (uv * picture_size - anchor) * grow;
	vec2 f = at + vec2(p.x * cos(turn) - p.y * sin(turn), p.x * sin(turn) + p.y * cos(turn));
	if (f.x < 0.0 || f.y < 0.0 || f.x >= frame_size.x || f.y >= frame_size.y) {
		return 1.0;
	}
	vec2 strip = vec2(float(textureSize(fist, 0).x), frame_size.y);
	return 1.0 - texture(fist, vec2((frame * frame_size.x + f.x) / strip.x, f.y / strip.y)).a;
}

// 1.0 where a hair layer shows at strip coordinate `uv`, 0.0 where its hat hides it.
float hair_cut_at(vec2 uv) {
	return has_hair_cut ? 1.0 - texture(hair_cut, uv).a : 1.0;
}

// The part's strip (its frames are regions of it). Not repeated: art touching a frame's
// bottom edge would otherwise wrap to its top as a thin line over his head.
uniform sampler2D strip : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 c = dress(strip_texel(strip, UV), UV) * COLOR;
	ALPHA = c.a * fist_cut(UV) * hair_cut_at(UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
