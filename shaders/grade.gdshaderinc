// The map's colour grade (BiomeDef "Atmosphere"): shadows are pushed toward `lift`, the colour
// is (de)saturated and multiplied by `tint`. The finishing pass (post.gdshader) grades the
// whole scene with it. TDStage sets it from the map.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 lift : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lift_amount = 0.0;
uniform float saturation = 1.0;

vec3 grade(vec3 c) {
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = mix(c, c + lift.rgb * 0.25, lift_amount * (1.0 - smoothstep(0.0, 0.6, luma)));
	return c * tint.rgb;
}
