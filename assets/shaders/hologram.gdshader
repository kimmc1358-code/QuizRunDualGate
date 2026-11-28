shader_type spatial;
render_mode unshaded, cull_disabled;
// A hologram (StageScenery's FEVER targets in the city, 2026-11-28, owner):
// the prop's own picture, half greyed and tinted, under fine scanlines that
// roll up the screen, with a glow toward its edges. Now and then it flickers
// dim, and now and then a band of it jumps sideways for a frame, a glitch.
// Each hologram keeps its own beat (`seed`, set per node), so a swarm does
// not blink as one.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.95, 0.75);
uniform float strength = 1.5;       // over 1, so it glows
uniform float grey = 0.5;           // how far the picture is greyed before the tint
uniform float line_period = 4.0;    // px from one scanline to the next
uniform float line_speed = 40.0;    // px a second they roll up
uniform float line_dark = 0.35;     // how much the dark half of a line takes away
uniform float rim_power = 2.0;
uniform float rim_glow = 1.2;
uniform float beat = 14.0;          // glitch and flicker slots a second
uniform float glitch_odds = 0.07;   // of a slot shifting a band sideways
uniform float glitch_shift = 0.25;  // model units, at most
uniform float flicker_odds = 0.1;   // of a slot going dim
instance uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	float slot = floor(TIME * beat + seed * 37.0);
	float on = step(1.0 - glitch_odds, hash(slot + seed * 11.0));
	// One band of the model, picked by its height, jumps sideways.
	float band = floor(VERTEX.y * 3.0);
	VERTEX.x += on * (hash(slot * 1.7 + band) - 0.5) * 2.0 * glitch_shift;
}

void fragment() {
	vec3 pic = texture(albedo_tex, UV).rgb;
	float lum = dot(pic, vec3(0.3, 0.59, 0.11));
	vec3 col = mix(pic, vec3(lum), grey) * tint.rgb;
	float line = 1.0 - line_dark * step(0.5, fract((FRAGCOORD.y + TIME * line_speed) / line_period));
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), rim_power);
	float slot = floor(TIME * beat + seed * 37.0);
	float flick = 1.0 - 0.6 * step(1.0 - flicker_odds, hash(slot + seed * 5.0));
	ALBEDO = (col * line + tint.rgb * rim * rim_glow) * strength * flick;
	ALPHA = clamp(tint.a * flick * (0.7 + 0.3 * line), 0.0, 1.0);
}
