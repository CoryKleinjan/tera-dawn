// Dresses the hero's body (see Paperdoll): every pixel belongs to a region of it
// (hero_regions.png, red channel = region * 16: skin, chest, shorts, feet), and each region
// can be recoloured or hidden. Under a helm drawn smaller than his head, the helm's head cut
// strip (headcut_<helm>.png, laid out like the body strip) cuts away what pokes out of it.

uniform sampler2D regions : filter_nearest;
// One column per region. Row 0: the colour to show it in, alpha = how much (0 keeps the
// hero's own colours). Row 1: red 1 hides it (gear not worn). Row 2: its typical colour in
// the art, so recolouring keeps light and shade.
uniform sampler2D look_data : filter_nearest;
uniform bool has_head_cut = false;
uniform sampler2D head_cut : filter_nearest;

vec4 dress_region(vec4 src, vec2 uv) {
	int r = clamp(int(round(texture(regions, uv).r * 255.0 / 16.0)), 0, 10);
	if (texelFetch(look_data, ivec2(r, 1), 0).r > 0.5) {
		return vec4(0.0);
	}
	vec4 t = texelFetch(look_data, ivec2(r, 0), 0);
	if (t.a <= 0.0) {
		return src;
	}
	vec3 luma = vec3(0.299, 0.587, 0.114);
	vec3 ref = texelFetch(look_data, ivec2(r, 2), 0).rgb;
	// the hero is sampled in linear colour; the look's colours are sRGB
	t.rgb = pow(t.rgb, vec3(2.2));
	ref = pow(ref, vec3(2.2));
	// (capped, so shine on dark art doesn't turn white on light colours)
	float shade = min(dot(src.rgb, luma) / max(dot(ref, luma), 0.05), 1.4);
	vec3 recoloured = clamp(t.rgb * shade, 0.0, 1.0);
	return vec4(mix(src.rgb, recoloured, t.a), src.a);
}

vec4 dress(vec4 src, vec2 uv) {
	vec4 c = dress_region(src, uv);
	if (has_head_cut) {
		c.a *= 1.0 - texture(head_cut, uv).a;
	}
	return c;
}
