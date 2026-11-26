shader_type canvas_item;
// The title screen's WARP GATE fill (Main._draw_title_subtitle_fill): glyphs
// drawn white, painted from top_color at the cap line to bottom_color at the
// baseline, like gold metal lit from above. draw_string has no gradient of
// its own. top_y and bottom_y are in the layer's own coordinates, which is
// what VERTEX is.

uniform vec4 top_color : source_color = vec4(1.0, 0.96, 0.66, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.56, 0.08, 1.0);
uniform float top_y = 0.0;
uniform float bottom_y = 1.0;

varying float y;

void vertex() {
	y = VERTEX.y;
}

void fragment() {
	float t = clamp((y - top_y) / max(bottom_y - top_y, 0.001), 0.0, 1.0);
	float a = texture(TEXTURE, UV).a * COLOR.a;
	COLOR = vec4(mix(top_color.rgb, bottom_color.rgb, t), a);
}
