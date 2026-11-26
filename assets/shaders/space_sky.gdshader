shader_type spatial;
render_mode unshaded, cull_disabled;
// The backdrop behind everything (SpaceRun._build_sky). It is the front face
// of Synty's skybox, which was painted to meet its neighbouring cube faces,
// not itself, so scrolling it down as the ship flies on brought a hard line
// into view once the picture's top edge came round.
//
// Each pixel mixes the picture with itself shifted by half its height. Near
// the picture's own top and bottom edges the shifted copy is shown, and it is
// seamless there because that is its middle; around the middle the picture
// itself is shown, which is where the shifted copy has its seam. The two
// cross-fade in between, where the nebula is soft enough to take a blend.
// Done here rather than baked into sky.png so that the kit built on another
// machine needs no rebuild.

uniform sampler2D sky : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.25);
// Grows as the ship flies; the picture slides down by this many heights.
uniform float scroll = 0.0;
// Where in |y - middle| (0 at the middle, 1 at the edges) the cross-fade
// starts and ends. Wider shows more doubled stars; narrower, a visible fade.
uniform float blend_from = 0.2;
uniform float blend_to = 0.8;

void fragment() {
	vec2 uv = vec2(UV.x, UV.y + scroll);
	float edge = abs(fract(uv.y) - 0.5) * 2.0;
	float w = smoothstep(blend_from, blend_to, edge);
	vec3 own = texture(sky, uv).rgb;
	vec3 shifted = texture(sky, uv + vec2(0.0, 0.5)).rgb;
	ALBEDO = mix(own, shifted, w) * tint;
}
