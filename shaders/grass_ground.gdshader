shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Stylized Clash-of-Clans turf: two bright greens broken up by soft low-frequency
// patches, a faint "manicured" diamond mow pattern, fine grain so it never looks
// flat, and a gentle edge vignette to focus the diorama. World-space XZ drives all
// variation, so it's independent of the box mesh's UVs and tiles seamlessly.

uniform vec3 grass_light : source_color = vec3(0.44, 0.79, 0.30);  // sunlit turf
uniform vec3 grass_dark  : source_color = vec3(0.22, 0.55, 0.20);  // base green
uniform vec3 grass_deep  : source_color = vec3(0.13, 0.39, 0.15);  // shadowed clumps
uniform float patch_scale = 0.06;       // low-frequency color patches
uniform float speckle_scale = 1.6;      // fine grain
uniform float diamond_scale = 0.35;     // manicured mow diamonds (~9 units)
uniform float diamond_strength = 0.04;  // how visible the mow pattern is
uniform float edge_darken = 0.28;       // vignette strength toward the map edge
uniform float map_half_size = 60.0;     // ground is 120 wide, so half is 60

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uvp = world_pos.xz;

	// Large soft patches pick between base and sunlit turf.
	float patches = fbm(uvp * patch_scale);
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.35, 0.75, patches));

	// Deepest low-frequency areas sink into shadowed clumps for depth.
	float deep = smoothstep(0.55, 0.15, patches);
	col = mix(col, grass_deep, deep * 0.5);

	// Subtle manicured diamond mow pattern (rotated checker).
	vec2 d = uvp * diamond_scale;
	float diamond = sign(sin(d.x + d.y) * sin(d.x - d.y));
	col *= 1.0 + diamond * diamond_strength;

	// Fine speckle so the turf reads as grass, not paint, up close.
	float grain = vnoise(uvp * speckle_scale);
	col *= 0.94 + 0.12 * grain;

	// Soft vignette toward the edges to keep the eye on the arena.
	float edge = length(uvp) / map_half_size;
	col *= 1.0 - edge_darken * smoothstep(0.6, 1.2, edge);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}
