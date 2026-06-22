shader_type canvas_item;
// Removes the near-white background baked into generated button art by making
// bright, low-saturation pixels transparent. Wood/gold/stone (saturated or dark)
// are preserved; only white/near-white background is keyed out.

uniform float white_cut : hint_range(0.0, 1.0) = 0.86; // brightness above which a pixel counts as "white"
uniform float sat_max : hint_range(0.0, 1.0) = 0.10;    // max saturation still considered background
uniform float softness : hint_range(0.0, 0.3) = 0.04;   // edge feather

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float mn = min(c.r, min(c.g, c.b));
	float mx = max(c.r, max(c.g, c.b));
	float sat = mx - mn;
	float bright_mask = smoothstep(white_cut - softness, white_cut + softness, mn);
	float sat_mask = 1.0 - smoothstep(sat_max, sat_max + 0.05, sat); // 1 when low-saturation
	float cut = bright_mask * sat_mask;
	c.a *= (1.0 - cut);
	// Don't reference the MODULATE built-in here: it isn't valid in a canvas_item
	// fragment() in this build, and isn't needed — Godot auto-applies the node's
	// modulate after fragment() as long as MODULATE goes untouched, so hover/press
	// tints still reach the button art.
	COLOR = c;
}
