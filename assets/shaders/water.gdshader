shader_type canvas_item;
// Ticket 90: slow shimmer on the water. Put on the Base and Shore tile layers. Only water-coloured pixels move
// (blue clearly over red and not under green), so land, banks and foam-free pixels keep their art. No texture
// lookups beyond the tile's own, no loops. TIME is real time, so the water moves while the game is paused.
uniform float speed = 0.9;
uniform vec2 flow = vec2(0.7, 0.35);  // drift direction of the ripples (world space)
uniform float strength = 0.16;

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float water = step(0.1, c.b - c.r) * step(c.g - 0.02, c.b);
	vec2 p = floor(wpos / 2.0);  // 2 px steps keep the pixel-art look
	float t = TIME * speed;
	float a = sin(dot(p, vec2(0.23, 0.11)) - dot(flow, vec2(1.0)) * t * 1.3);
	float b = sin(dot(p, vec2(-0.09, 0.27)) - flow.x * t + 1.7);
	float band = a * b;
	float glint = smoothstep(0.55, 0.95, band);
	float dusk = smoothstep(-0.9, -0.5, band) * 0.5 - 0.25;
	vec3 lit = c.rgb + vec3(0.55, 0.75, 0.85) * glint * strength + vec3(0.0, 0.03, 0.06) * dusk * strength * 3.0;
	c.rgb = mix(c.rgb, lit, water);
	COLOR = c;
}
