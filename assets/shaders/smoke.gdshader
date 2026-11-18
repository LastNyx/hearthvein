shader_type canvas_item;
// Ticket 90: chimney smoke. The sprite is the static puff column (transparent padding above and below). Two copies
// of it rise and fade in turns, so the loop has no pop. Two lookups, no loops. Each sprite starts at its own point of
// the cycle (hashed from its position), so neighbouring chimneys do not puff in step.
uniform float rise = 12.0;    // pixels climbed per cycle
uniform float period = 3.2;   // seconds per cycle
uniform float sway = 1.0;     // pixels of side drift

varying float seed;

void vertex() {
	vec2 w = MODEL_MATRIX[3].xy;
	seed = fract(sin(dot(w, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float t = TIME / period + seed;
	float p1 = fract(t);
	float p2 = fract(t + 0.5);
	vec2 uv1 = UV + vec2(sin((p1 + seed) * 6.2832) * sway * px.x, p1 * rise * px.y);
	vec2 uv2 = UV + vec2(sin((p2 + seed) * 6.2832) * sway * px.x, p2 * rise * px.y);
	vec4 c1 = texture(TEXTURE, uv1);
	vec4 c2 = texture(TEXTURE, uv2);
	float a1 = c1.a * sin(p1 * 3.14159) * step(uv1.y, 1.0);
	float a2 = c2.a * sin(p2 * 3.14159) * step(uv2.y, 1.0);
	COLOR = vec4(mix(c2.rgb, c1.rgb, step(a2, a1)), max(a1, a2));
}
