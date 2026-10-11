// A piece of the dressed hero (Paperdoll.Piece: a weapon, shield or hat placed on him each
// frame): a weapon's fingers-over-the-grip cut. The piece's pixel at `uv` is found on the body
// frame from its pose, and is cut away where the fist mask strip (fist_<kind>.png, a frame of
// FRAME_SIZE per body frame) has his fingers. Paperdoll.Layer.apply_pose sets the pose.

uniform bool has_fist = false;
uniform bool fist_on = false;
uniform sampler2D fist : filter_nearest;
uniform vec2 frame_size = vec2(256.0, 208.0);
uniform float frame = 0.0;
uniform vec2 at = vec2(0.0);
uniform vec2 anchor = vec2(0.0);
uniform float turn = 0.0;
uniform float grow = 1.0;
uniform vec2 picture_size = vec2(1.0);

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
