class_name TitleArt
extends RefCounted

## The WARP ✦ GATE emblem: a gold star on a wreath with the two words either
## side, after the Synty INTERFACE Sci-Fi Menus pack's banner. Drawn by the
## title screen (Main._draw_splash) at full size and by the mode select at a
## smaller one; one copy, so the two cannot drift apart.
##
## The art is the Synty UI kit's (tools/build_ui_kit.gd, gitignored). Without
## it the crest is an ArtSlot placeholder and the words use the fallback font.

const STAR_PATH := "res://assets/synty_ui/title_star.png"
const WREATH_PATH := "res://assets/synty_ui/title_wreath.png"
const FONT_PATH := "res://assets/synty_ui/fonts/ZenDots-Regular.ttf"
# A, chosen 2026-11-27: the screen leads with WARP GATE, the part of the game
# the name is about; QUIZ RUN, the store name kept for the listing, is the
# title screen's gold subtitle (Main.TITLE_SUBTITLE).
const WORDS := ["WARP", "GATE"]
const LETTER := Color(0.88, 0.97, 1.0)
const RIM := Color(0.35, 0.86, 1.0)
const GLOW := Color(0.30, 0.75, 1.0, 0.16)
const GLOW_RADII := [5.0, 9.0]
const CREST_GLOW_RINGS := 10

static var _font: Font


## Zen Dots, or `fallback` without the kit.
static func font(fallback: Font) -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
		# Zen Dots has no Hangul. Chained to the game's own face, a Korean
		# mode name falls through to the game's Hangul face (AppFont) rather
		# than to a thin system gothic.
		if fallback != null and _font is FontFile:
			(_font as FontFile).fallbacks = [fallback]
	return _font if _font != null else fallback


## The crest centred on `mid`, `star_h` tall, and WORDS either side of it,
## each fitted into the room between the crest and the screen edge (`width`
## wide, `margin` kept clear) but never above `max_size`. `scale` turns the
## line widths and glow radii, which are in 480-wide pixels, into this size.
## Returns the font size the words came out at.
static func draw_emblem(ci: CanvasItem, mid: Vector2, star_h: float, wreath_h: float,
		width: float, margin: float, max_size: int, face: Font, scale: float) -> int:
	for i in CREST_GLOW_RINGS:
		var t: float = float(i + 1) / CREST_GLOW_RINGS
		ci.draw_circle(mid, star_h * 0.5 * t, Color(RIM, 0.05 * (1.0 - t) + 0.015))
	var wreath := ArtSlot.texture(WREATH_PATH)
	var ww: float = wreath_h * wreath.get_width() / wreath.get_height()
	ci.draw_texture_rect(wreath, Rect2(mid - Vector2(ww, wreath_h) * 0.5, Vector2(ww, wreath_h)), false)
	var star := ArtSlot.texture(STAR_PATH)
	var sw: float = star_h * star.get_width() / star.get_height()
	ci.draw_texture_rect(star, Rect2(mid - Vector2(sw, star_h) * 0.5, Vector2(sw, star_h)), false)

	var side_w: float = width * 0.5 - ww * 0.5 - margin
	var size := max_size
	for word: String in WORDS:
		while size > 10 and face.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > side_w:
			size -= 1
	var left_w: float = face.get_string_size(WORDS[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base_y: float = mid.y + size * 0.36
	draw_word(ci, face, WORDS[0], Vector2(mid.x - ww * 0.5 - left_w, base_y), size, scale)
	draw_word(ci, face, WORDS[1], Vector2(mid.x + ww * 0.5, base_y), size, scale)
	return size


## One word: a soft cyan glow, a bright rim, pale letters.
static func draw_word(ci: CanvasItem, face: Font, word: String, pos: Vector2, size: int, scale: float) -> void:
	var rim_px: int = maxi(2, int(round(4.0 * scale * size / 44.0)))
	for r: float in GLOW_RADII:
		for i in 8:
			var o := Vector2.from_angle(i * TAU / 8.0) * r * scale * size / 44.0
			ci.draw_string_outline(face, pos + o, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim_px, GLOW)
	ci.draw_string_outline(face, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim_px, RIM)
	ci.draw_string(face, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LETTER)
