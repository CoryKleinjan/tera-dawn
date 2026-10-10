// A light floor for characters standing in the 3D stage (the dressed hero and his layers):
// some of their own colour always shows, so deep shade or a dim map never turns them, dark
// skin tones above all, into a silhouette. Small enough that full light looks the same.
const float MIN_LIGHT = 0.18;

vec3 light_floor(vec3 albedo) {
	return albedo * MIN_LIGHT;
}
