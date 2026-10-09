// Dresses the painted hero (see Paperdoll): every pixel belongs to a region of his body
// (hero_regions.png, red channel = region * 16), and each region can be recoloured or hidden.

uniform sampler2D regions : filter_nearest;
// One column per region. Row 0: the colour to show it in, alpha = how much (0 keeps the
// hero's own colours). Row 1: red 1 hides it (gear not worn). Row 2: its typical colour in
// the art, so recolouring keeps light and shade.
uniform sampler2D look_data : filter_nearest;

vec4 dress(vec4 src, vec2 uv) {
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
#ifdef LINEAR_COLOR
	// the 3D stage samples the hero in linear colour; the look's colours are sRGB
	t.rgb = pow(t.rgb, vec3(2.2));
	ref = pow(ref, vec3(2.2));
#endif
	// (capped, so shine on dark art doesn't turn white on light colours)
	float shade = min(dot(src.rgb, luma) / max(dot(ref, luma), 0.05), 1.4);
	vec3 recoloured = clamp(t.rgb * shade, 0.0, 1.0);
	return vec4(mix(src.rgb, recoloured, t.a), src.a);
}
