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
