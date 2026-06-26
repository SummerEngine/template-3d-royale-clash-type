shader_type spatial;
// Cheap animated moat water. A few scrolling sine ripples shift the colour between a
// deep and a shallow blue and add a faint moving glint. Pure GPU, no textures, no
// per-frame CPU — negligible cost on the small moat mesh.

uniform vec4 shallow : source_color = vec4(0.20, 0.55, 0.90, 1.0);
uniform vec4 deep : source_color = vec4(0.09, 0.32, 0.62, 1.0);
uniform float flow_speed = 0.5;
uniform float ripple_scale = 0.8;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * flow_speed;
	float r = sin(v_world.x * ripple_scale + t)
			+ sin(v_world.z * ripple_scale * 1.3 - t * 1.2)
			+ sin((v_world.x + v_world.z) * ripple_scale * 0.6 + t * 0.7);
	float w = clamp(r * 0.18 + 0.5, 0.0, 1.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, w);
	METALLIC = 0.2;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
