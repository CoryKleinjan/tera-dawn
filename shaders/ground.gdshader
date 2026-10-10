shader_type spatial;
// The floor block's top: its biome texture with slow cloud shadows drifting across it
// (BiomeDef.cloud_shadows). UVs are in tiles (TerrainBuilder.TILE_UNITS).
render_mode specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clouds : filter_linear, repeat_enable;
uniform float cloud_strength = 0.0;
uniform vec2 cloud_drift = vec2(0.012, 0.004);
// how many floor tiles one cloud texture spans
uniform float cloud_scale = 6.0;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float n = texture(clouds, UV / cloud_scale + cloud_drift * TIME).r;
	c *= 1.0 - cloud_strength * smoothstep(0.48, 0.68, n);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
