// Keeps a flat upright quad's sides straight up and down on screen. The camera looks down a
// little, so in plain perspective tall things' sides lean in toward the middle of the screen;
// this moves each vertex sideways to sit right under the point at `top` (a height in the
// quad's own space) above it. Call from vertex() in a shader with skip_vertex_transform.

uniform float top = 0.5;

void upright_vertex(inout vec3 vertex, inout vec3 normal, mat4 modelview) {
	vec3 v = (modelview * vec4(vertex, 1.0)).xyz;
	vec3 t = (modelview * vec4(vertex.x, top, vertex.z, 1.0)).xyz;
	v.x = t.x * v.z / t.z;
	vertex = v;
	normal = normalize((modelview * vec4(normal, 0.0)).xyz);
}
