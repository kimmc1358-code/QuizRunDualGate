extends Control

## Main menu / mode picker, built from the painted art in
## assets/ui_assets/main/.
##
## Laid out in code rather than as scene nodes because the viewport is a
## fixed 480 wide but a height that varies with the device — 854 on 16:9, up
## to ~1066 on 20:9, since the project stretches with aspect "expand". Every
## piece is sized from its own aspect ratio against the screen width, and the
## leftover height is shared out between them, so the column stays put at the
## top and bottom on any phone instead of drifting or overflowing.
##
## Only the cards and START act. The leaderboard logs "[미구현]" so a tap is
## visibly registered rather than silently ignored.

signal start_pressed(mode: int)

# Mirrors Main.gd's Mode enum. The mode-select sheet's quadrants are read in
# reading order, so top-left is SKY and the fourth is the hidden slot.
const MODE_SKY := 0
const MODE_JUNGLE := 1
const MODE_OCEAN := 2
const MODE_HIDDEN := 3
const CARD_MODES := [MODE_SKY, MODE_JUNGLE, MODE_OCEAN, MODE_HIDDEN]
# Which quadrant of the sheet each slot draws. The sheet reads blue, green,
# cyan, pink; the left column is flipped so the mint card sits on top, which
# is why this is a mapping rather than a straight 0,1,2,3.
const CARD_SHEET_SLOT := [2, 1, 0, 3]

# Characters shown on the cards, in slot order. The fourth is the hidden
# mode and has no art yet — an empty path leaves that card blank.
const CARD_CHARACTER_SHEET := [
	"res://assets/characters/bird_v2/bird_fly.png",
	"res://assets/characters/dragon_green/dragon_fly.png",
	"res://assets/characters/shark_blue/shark_swim.png",
	"",
]
const CARD_CHARACTER_GRID := Vector2i(2, 2)
const CARD_CHARACTER_FPS := 8.0
# Measured off each sheet the same way Main.gd's MODE_DRAW_OFFSET_FLY is,
# and scaled to whatever size the card draws the sprite at.
const CARD_CHARACTER_OFFSET := [Vector2(0.4, 2.5), Vector2(-2.0, 0.7), Vector2(0.0, 0.0), Vector2.ZERO]
const CARD_CHARACTER_REFERENCE := 100.0  # the offsets above are in this space

# Space inside a card, as fractions of its height: a name across the top, the
# character in the middle, the best score along the bottom.
const CARD_NAME_HEIGHT_FRAC := 0.17
const CARD_BEST_HEIGHT_FRAC := 0.15
const CARD_ART_HEIGHT_FRAC := 0.58
const CARD_TEXT_INSET_FRAC := 0.06     # of card height, kept clear of the border
const CARD_NAMES := ["FLAG MODE", "MATH MODE", "STROOP MODE", "?"]
# Sized so the longest name fits its card, then used for all of them, so the
# titles do not step up and down from card to card.
const CARD_NAME_WIDTH_FRAC := 0.90     # of the card's inner width
const CARD_NAME_MAX_SIZE := 22
const CARD_NAME_MIN_SIZE := 9
const CARD_NAME_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const CARD_NAME_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
const CARD_NAME_OUTLINE_FRAC := 0.18   # of the font size
# The title sits on its own rounded plate. Its width is taken from the
# longest name — STROOP MODE — and then used on every card, so the plates
# line up as a set rather than each hugging its own text.
const CARD_NAME_PLATE_COLOR := Color(0.16, 0.17, 0.20, 0.55)
const CARD_NAME_PLATE_RADIUS := 6
const CARD_NAME_PLATE_PAD_FRAC := 0.32   # of the plate's height, at each end

# Best score sits in its own rounded white plate, with the number padded to a
# fixed five digits so the plate never resizes as a score grows.
const CARD_BEST_DIGITS := 5
const CARD_BEST_PLATE_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const CARD_BEST_PLATE_RADIUS := 6
const CARD_BEST_PLATE_WIDTH_FRAC := 0.86   # of the card's inner width
const CARD_BEST_COLOR := Color(0.18, 0.26, 0.38, 1.0)
# The plate holds three things in a row — crown, the word BEST, the number —
# centred as a group. The number is styled like the card titles rather than
# like the word beside it, so the score is what the eye lands on.
# 게임 화면 HUD 와 같은 왕관을 쓴다. ART_DIR 바깥이라 전체 경로로 준다.
const CARD_BEST_CROWN_FILE := "res://assets/ui_assets/popup/icon_crown.png"
const CARD_BEST_CROWN_HEIGHT_FRAC := 0.78   # of the plate's height
# 잘라 낸 그림 둘레에 두르는 투명 여백(그림 크기 대비)과 미리 줄여 둘 높이.
const TRIM_INK_PAD_FRAC := 0.06
const TRIM_INK_BAKE_H := 128
const CARD_BEST_ROW_SEPARATION_FRAC := 0.22 # of the plate's height, between items
const CARD_SCORE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const CARD_SCORE_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
# Extra px between the BEST digits. Fredoka sets figures tight, and at this
# size the five zeros run together into one block; a single pixel is enough
# to read them as separate digits without the number looking spaced out.
const CARD_SCORE_TRACKING := 1
# 속색과 같은 검정 테두리라 "테두리"로 보이지 않고 글자가 그만큼 굵어진다.
# Fredoka 는 wght 700 이 끝이라, 더 굵게 하려면 이 방법밖에 없다.
const CARD_SCORE_OUTLINE_FRAC := 0.16

# Fredoka is variable on a wght axis (300-700). Main.gd uses 600 for text and
# 700 for the score digits; the same two weights are used here.
const FONT_WEIGHT_BOLD := 600
const FONT_WEIGHT_HEAVY := 700

# One line each, sized so the longest of them fits — every mode then reads at
# the same size, which a per-string fit would not give.
const CARD_EXPLAIN := [
	"Find the flag that matches the country!",
	"Solve the math problem and find the answer!",
	"Choose the COLOR, not the word!",
	"Clear all 3 modes to unlock a hidden mode!",
]
# The explain bar's ends are round, and their radius is a large fraction of
# its height. Nine-slice cannot shorten a shape like that: it draws corners
# at native size, so the caps would either overlap or, stretched, turn into
# ellipses.
#
# Drawn in three horizontal pieces instead. Each cap is scaled uniformly, so
# it keeps its shape at any height, and only the middle — flat horizontal
# bands — is stretched across the gap. Height is then free to change without
# distorting anything, and the border thickness scales with it, which is what
# keeps it reading as the same bar rather than a thinner one with a heavy
# outline.
#
# The cap width and the art's own bounds are measured off the file rather
# than written down. The bar has already been swapped once — from a pill in
# a tight canvas to a rounded rectangle sitting in a lot of transparent
# padding — and fixed numbers would have quietly drawn that padding as if it
# were the bar.
const EXPLAIN_HEIGHT_SCALE := 0.80      # squash against the height its width would imply
const EXPLAIN_TEXT_WIDTH_FRAC := 0.86   # of the bar, keeping the text off its border
const EXPLAIN_TEXT_MAX_SIZE := 20
const EXPLAIN_TEXT_MIN_SIZE := 9
const EXPLAIN_TEXT_COLOR := Color(0.12, 0.18, 0.30, 1.0)

# The selected card is picked out with a rounded outline tracing the card's
# own edge. Measured off the sheet: the card's white border is 13px and its
# corner radius about 70px, on art drawn at roughly 0.275 — so a little over
# 3.5px and 19px on screen. The outline is drawn slightly thicker than the
# border it sits on, with a drop shadow and an inner highlight for relief.
const SELECT_BORDER_SCALE := 1.85       # multiple of the card's own border thickness
# A halo outside the ring, drawn as a few rounded outlines stepping outward
# and fading as they go. They are spaced far closer than they are wide, so
# they overlap into a continuous gradient instead of reading as separate
# outlines — which is what a handful of widely spaced rings looked like.
# Godot's box shadow only offsets in one direction,
# so it cannot wrap a shape evenly; concentric rings can.
const SELECT_GLOW_COLOR := Color(1.0, 0.84, 0.22, 0.17)
const SELECT_GLOW_RINGS := 10
const SELECT_GLOW_SPREAD := 1.5         # how far out the halo reaches, in border widths
const SELECT_CARD_BORDER_NATIVE := 13.0
const SELECT_CORNER_NATIVE := 70.0
const SELECT_SHEET_WIDTH_NATIVE := 706.0
const SELECT_SHADOW_SIZE := 7
const SELECT_SHADOW_OFFSET := Vector2(0, 3)
const SELECT_SHADOW_COLOR := Color(0.35, 0.22, 0.0, 0.55)
const SELECT_HIGHLIGHT_COLOR := Color(1.0, 0.97, 0.72, 0.9)
# The card art fades out along its bottom edge, so the opaque bounds the ring
# is placed on stop just short of where the card looks like it ends. Nudged
# down to close that gap.
const SELECT_BOTTOM_EXTEND_FRAC := 0.022   # of the card's height

# START gets the same halo treatment as the selected card. Its plate is a
# rounded rectangle of radius 120 in a 1024-wide source, measured the same
# way the card's was.
const START_CORNER_NATIVE := 120.0
const START_SHEET_WIDTH_NATIVE := 1024.0
const START_GLOW_COLOR := Color(1.0, 0.88, 0.35, 0.16)
const START_GLOW_RINGS := 10
const START_GLOW_BORDER := 5.0        # ring thickness in screen pixels
const START_GLOW_SPREAD := 2.2        # how far out the halo reaches, in ring widths

# The chosen card's character drifts, so the selection reads as alive even
# before the flap cycle registers.
const CARD_BOB_AMPLITUDE_FRAC := 0.045  # of the art area's height
const CARD_BOB_PERIOD := 1.5

const ART_DIR := "res://assets/ui_assets/main/"
const BACKGROUND_FILE := "background_main.png"
const TITLE_FILE := "title_main_v2.png"
const CARD_SHEET_FILE := "modeselect_main.png"
const EXPLAIN_FILE := "explain_box.png"
const LEADERBOARD_FILE := "leaderboard_v2.png"
const START_FILE := "start_main.png"

# Icon sheet, 5 across and 3 down. The icons are dark navy on transparent —
# invisible against a dark backdrop, which is only a preview problem: on the
# gold leaderboard plate they read clearly. Reading order, so the trophy on
# the top row's fourth column is index 3.
const ICON_SHEET_FILE := "icon_sheet.png"
const ICON_SHEET_GRID := Vector2i(5, 3)
const ICON_TROPHY_INDEX := 3
# Each icon sits in a lot of empty cell, so it is trimmed to its own art
# before placing — otherwise the padding, not the trophy, gets centred.
const TROPHY_HEIGHT_FRAC := 0.52      # of the leaderboard button's height
const TROPHY_LEFT_FRAC := 0.09        # of the button's width, from its left edge

# Label on the leaderboard plate, styled like START's. It is centred in the
# space left of it by the trophy rather than on the whole plate, so the icon
# and the word read as one balanced group instead of the word sitting off to
# one side of centre.
const LEADERBOARD_LABEL := "LEADERBOARD"
const LEADERBOARD_LABEL_HEIGHT_FRAC := 0.40   # of the plate's height
const LEADERBOARD_LABEL_MIN_SIZE := 8
const LEADERBOARD_LABEL_PAD_FRAC := 0.05      # of the plate's width, kept off its right edge

# Tap cues. Loaded only if present and played only if loaded, the same
# defensive shape as the sounds in Main.gd — removing a file leaves a silent
# button rather than a crash.
const SFX_DIR := "res://assets/audio/"
const SFX_SELECT_FILE := "modeselection.wav"
const SFX_START_FILE := "start_main.wav"

# The START art is a blank plate, so the word is drawn on top of it.
const FONT_PATH := "res://assets/fonts/Fredoka.ttf"
const START_LABEL := "START"
const START_LABEL_HEIGHT_FRAC := 0.44   # of the button's height
const START_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const START_LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
const START_LABEL_OUTLINE_SIZE_FRAC := 0.16  # of the font size

# Press feedback, matching the pause/mute buttons in Main.gd: a quick squash
# in, then a springy return that slightly overshoots.
const PRESS_SCALE := 0.94
const PRESS_ANIM_DURATION := 0.08

# The card sheet was exported without an alpha channel, so its four cards sit
# on flat black, and the white border meets that black through a single
# anti-aliased pixel — measured at around brightness 80 where the border
# itself is 250+.
#
# Simply thresholding leaves that pixel fully opaque and dark, which is the
# black rim it produced around every card. It is really a premultiplied
# blend: a pixel covering the backdrop by k reads as border * k, so the
# coverage is its brightness and the true colour is that brightness divided
# back out.
#
# Applying that everywhere would make the card bodies translucent, since a
# pastel fill is not full brightness either. So it is applied only to pixels
# that actually touch the backdrop — the rim — and everything else stays
# opaque with its colour untouched. A histogram of the sheet backs the
# thresholds up: 0-31 is the backdrop, 192-255 the art, and barely a
# thousand pixels lie between.
const KEY_FLOOR := 10      # at or below: backdrop
const KEY_SOLID := 192     # at or above: art, left alone

# Widths as a fraction of the screen; each piece's height follows from its
# own aspect ratio.
const TITLE_WIDTH_FRAC := 0.70
const CARDS_WIDTH_FRAC := 0.84
const CARD_GAP_FRAC := 0.030      # of screen width, between the two columns
# The explain bar takes its width from the cards rather than a fraction of
# its own, so its ends line up exactly with the outer edges of the left and
# right columns however the cards are sized.
const LEADERBOARD_WIDTH_FRAC := 0.52
const START_WIDTH_FRAC := 0.72

# Ad removal — the text is a placeholder for a purchase that does not exist
# yet, so it logs like the leaderboard does. Underlined to read as a link
# rather than as a caption; Label has no underline, so it is drawn.
const REMOVE_ADS_TEXT := "Remove Ads"
const REMOVE_ADS_FONT_FRAC := 0.022    # of screen height
const REMOVE_ADS_BLOCK_FRAC := 0.040   # of screen height, the tappable band
const REMOVE_ADS_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const REMOVE_ADS_UNDERLINE_GAP := 2.0
const REMOVE_ADS_UNDERLINE_WIDTH := 1.5
const TOP_MARGIN_FRAC := 0.035    # of screen height
const BOTTOM_MARGIN_FRAC := 0.035
const MAX_GAP_FRAC := 0.055       # cap, so a tall screen spreads rather than sprawls
# Extra clearance above the explain bar. The selected card carries a glow
# that reaches past its edge, and at the plain gap the bottom row of cards
# was touching the bar.
const EXPLAIN_TOP_EXTRA_FRAC := 0.020   # of screen height

# Selection has to be readable even though the cards carry no state of their
# own: a bright rounded outline is drawn over the chosen one.
const SELECT_COLOR := Color(1.0, 0.86, 0.20, 1.0)
const SELECT_WIDTH := 4.0
const SELECT_INSET := 3.0
const SELECT_CORNER_RADIUS := 18.0

var selected_index: int = 0

var _background: TextureRect
var _title: TextureRect
var _explain: Control
var _explain_texture: Texture2D
var _start_glow: Control
var _start_bounds := Rect2(0, 0, 1, 1)
var _explain_src := Rect2(0, 0, 1, 1)   # the bar's art within its file, in pixels
var _explain_cap := 1.0                 # corner radius in those same pixels
var _cards: Array[TextureButton] = []
var _leaderboard: TextureButton
var _start: TextureButton
var _select_overlay: Control
var _sfx_select: AudioStreamPlayer
var _sfx_start: AudioStreamPlayer
var _start_label: Label
var _remove_ads: Button
var _remove_ads_rule: Control
var _card_characters: Array = []   # one Array[Texture2D] of flight frames per slot
var _card_art: Array[TextureRect] = []
var _card_name: Array[Label] = []
var _card_best: Array[Label] = []
var _card_anim_elapsed: float = 0.0
var _card_art_rest_y: Array[float] = []      # where the layout put each sprite, before the bob
var _card_art_bounds: Array[Rect2] = []      # each card cell's opaque box, normalised
var _explain_label: Label
var _card_best_plate: Array[Panel] = []
var _card_name_plate: Array[Panel] = []
var _card_best_row: Array[HBoxContainer] = []
var _card_crown: Array[TextureRect] = []
var _card_score: Array[Label] = []
var _crown_texture: Texture2D
var _font_bold: Font
var _font_heavy: Font
var _trophy: TextureRect
var _leaderboard_bounds := Rect2(0, 0, 1, 1)
var _leaderboard_label: Label


func _ready() -> void:
	_load_fonts()
	_sfx_select = _make_sfx(SFX_SELECT_FILE)
	_sfx_start = _make_sfx(SFX_START_FILE)
	_build()
	# Straight to _select, not _on_card_pressed: this is the opening state,
	# not a tap, and should not make a sound.
	_select(0)
	resized.connect(_layout)


# Two weights off the one variable font. The axis is keyed by its integer
# OpenType tag rather than the string "wght" — a string key is silently
# ignored, which is the same trap Main.gd documents.
func _load_fonts() -> void:
	if not ResourceLoader.exists(FONT_PATH):
		return
	var base: Font = load(FONT_PATH)
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_font_bold = _weighted(base, wght, FONT_WEIGHT_BOLD)
	_font_heavy = _weighted(base, wght, FONT_WEIGHT_HEAVY)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


# Same face with extra space between glyphs. Wrapping rather than mutating,
# because the base is shared with several other labels that must not shift.
func _tracked(base: Font, extra_px: int) -> Font:
	if extra_px == 0:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = extra_px
	return fv


func _make_sfx(file_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	var path: String = SFX_DIR + file_name
	if ResourceLoader.exists(path):
		player.stream = load(path)
	else:
		push_warning("main menu: missing %s" % path)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _process(delta: float) -> void:
	# Only the chosen card animates; the rest hold their first frame, so the
	# selection reads as "this one is alive" without needing another cue.
	if not visible:
		return
	_card_anim_elapsed += delta
	for i in range(_card_art.size()):
		var frames: Array = _card_characters[i]
		if frames.is_empty():
			continue
		var frame: int = 0
		var bob := 0.0
		if i == selected_index:
			frame = int(_card_anim_elapsed * CARD_CHARACTER_FPS) % frames.size()
			bob = sin(_card_anim_elapsed / CARD_BOB_PERIOD * TAU) \
				* _card_art[i].size.y * CARD_BOB_AMPLITUDE_FRAC
		_card_art[i].texture = frames[frame]
		# Offset from the resting position the layout gave it, so a re-layout
		# does not accumulate the drift.
		_card_art[i].position.y = _card_art_rest_y[i] + bob


# ---------------------------------------------------------------- art loading

# The project draws with nearest filtering, which is right for the pixel-art
# sprites but wrong here: this art is smooth and painted at 3-4x the size it
# appears at, and nearest minification just samples every third pixel, which
# is what shreds the rounded borders. These nodes opt into linear filtering
# with mipmaps instead (the .import files for assets/ui_assets/main carry
# mipmaps/generate=true so the levels exist to sample).
func _use_smooth_filter(control: CanvasItem) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _load_art(file_name: String) -> Texture2D:
	# 다른 폴더의 파일은 전체 경로로 준다.
	var path: String = file_name if file_name.begins_with("res://") else ART_DIR + file_name
	if not ResourceLoader.exists(path):
		push_warning("main menu: missing %s" % path)
		return null
	return load(path)


# Cuts the sheet into equal cells in reading order and lifts each off its
# black backdrop. Done here rather than as four pre-cut files so the sheet
# stays the only asset to manage — the same reasoning as _slice_spritesheet
# in Main.gd.
func _slice_cards(cols: int, rows: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var texture := _load_art(CARD_SHEET_FILE)
	if texture == null:
		return out
	var sheet: Image = texture.get_image()
	if sheet == null:
		return out
	sheet.convert(Image.FORMAT_RGBA8)
	var cell_w: int = sheet.get_width() / cols
	var cell_h: int = sheet.get_height() / rows
	_card_art_bounds.clear()
	for row in range(rows):
		for col in range(cols):
			var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
			var keyed: Image = _key_black(cell)
			# Recorded while the alpha is to hand: the cards do not all sit at
			# the same place in their cell, and the selection outline needs to
			# follow each one's actual edge.
			_card_art_bounds.append(_opaque_bounds(keyed))
			out.append(ImageTexture.create_from_image(keyed))
	# Reordered to match the slots, so index i is the card shown at slot i.
	var ordered: Array[Rect2] = []
	for slot in CARD_SHEET_SLOT:
		ordered.append(_card_art_bounds[slot] if slot < _card_art_bounds.size() else Rect2(0, 0, 1, 1))
	_card_art_bounds = ordered
	return out


# The opaque box of an image, as fractions of its size.
func _opaque_bounds(image: Image) -> Rect2:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var data: PackedByteArray = image.get_data()
	var x0: int = w
	var x1: int = -1
	var y0: int = h
	var y1: int = -1
	for y in range(h):
		for x in range(w):
			if data[(y * w + x) * 4 + 3] > 24:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 < 0:
		return Rect2(0, 0, 1, 1)
	return Rect2(float(x0) / w, float(y0) / h, float(x1 - x0 + 1) / w, float(y1 - y0 + 1) / h)


# True when any of the four neighbours is backdrop, which is what marks a
# pixel as sitting on the card's anti-aliased rim rather than inside it.
func _touches_backdrop(data: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var n: int = (ny * w + nx) * 4
		if maxi(data[n], maxi(data[n + 1], data[n + 2])) <= KEY_FLOOR:
			return true
	return false


func _key_black(image: Image) -> Image:
	# Works on the raw buffer rather than get_pixel/set_pixel: a card is about
	# 400k pixels, and four of them through per-pixel calls is a visible stall
	# on the way into the menu.
	# The sheet is imported with mipmaps, and a region cut from it carries
	# them too — get_data() would then hand back every level concatenated,
	# which does not match the width x height x 4 that create_from_data below
	# expects. Drop them and rebuild from the keyed result instead, so the
	# levels are generated from the transparency rather than around it.
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var data: PackedByteArray = image.get_data()

	# Pass 1 decides alpha and notes which pixels need their colour divided
	# back out. It cannot do the division inline: the rim test reads its
	# neighbours' colours, and rewriting them as it goes would feed the test
	# values it had already changed.
	var rim: PackedInt32Array = PackedInt32Array()
	for y in range(h):
		for x in range(w):
			var i: int = (y * w + x) * 4
			var brightest: int = maxi(data[i], maxi(data[i + 1], data[i + 2]))
			if brightest <= KEY_FLOOR:
				data[i + 3] = 0
				continue
			if brightest >= KEY_SOLID:
				continue
			if _touches_backdrop(data, w, h, x, y):
				data[i + 3] = brightest
				rim.append(i)

	# Pass 2: undo the premultiply, so a rim pixel carries the border's own
	# colour at partial coverage instead of a colour already mixed with black.
	for i in rim:
		var coverage: float = data[i + 3] / 255.0
		if coverage <= 0.0:
			continue
		for c in range(3):
			data[i + c] = mini(255, int(round(data[i + c] / coverage)))

	var keyed := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	# Built here rather than by the importer, so the linear-with-mipmaps filter
	# above has levels to fall back on when the card is drawn at a third size.
	keyed.generate_mipmaps()
	return keyed


# ---------------------------------------------------------------- building

func _build() -> void:
	for child in get_children():
		# The cue players are not part of the layout and must survive a
		# rebuild — they are created before this runs.
		if child is AudioStreamPlayer:
			continue
		child.queue_free()
	_cards.clear()

	_background = TextureRect.new()
	_background.texture = _load_art(BACKGROUND_FILE)
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Without this a TextureRect reports its texture size as its minimum, and
	# the layout below cannot shrink it — the title would draw at 1056 wide
	# and simply clip.
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_background)
	add_child(_background)

	_title = _make_image(_load_art(TITLE_FILE))
	add_child(_title)

	var card_textures := _slice_cards(2, 2)
	_card_characters.clear()
	_card_art.clear()
	_card_art_rest_y.clear()
	_card_name.clear()
	_card_best.clear()
	_card_best_plate.clear()
	_card_name_plate.clear()
	_card_best_row.clear()
	_card_crown.clear()
	_card_score.clear()
	_crown_texture = _load_trimmed(CARD_BEST_CROWN_FILE)
	for i in range(CARD_MODES.size()):
		var slot: int = CARD_SHEET_SLOT[i]
		var card := TextureButton.new()
		card.texture_normal = card_textures[slot] if slot < card_textures.size() else null
		card.ignore_texture_size = true
		card.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		card.focus_mode = Control.FOCUS_NONE
		_use_smooth_filter(card)
		card.pressed.connect(_on_card_pressed.bind(i))
		add_child(card)
		_cards.append(card)

		# Contents ride inside the card so the press animation scales them
		# along with it; none of them take clicks.
		_card_characters.append(_slice_character(CARD_CHARACTER_SHEET[i]))
		var art := TextureRect.new()
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_smooth_filter(art)
		card.add_child(art)
		_card_art.append(art)
		_card_art_rest_y.append(0.0)

		var name_plate := Panel.new()
		name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_style := StyleBoxFlat.new()
		name_style.bg_color = CARD_NAME_PLATE_COLOR
		name_style.set_corner_radius_all(CARD_NAME_PLATE_RADIUS)
		name_style.anti_aliasing = true
		name_plate.add_theme_stylebox_override("panel", name_style)
		card.add_child(name_plate)
		_card_name_plate.append(name_plate)

		var name_label := _add_card_text(name_plate, CARD_NAMES[i], CARD_NAME_COLOR)
		name_label.add_theme_color_override("font_outline_color", CARD_NAME_OUTLINE)
		if _font_heavy != null:
			name_label.add_theme_font_override("font", _font_heavy)
		_card_name.append(name_label)

		# White plate behind the score, with the label riding inside it.
		var plate := Panel.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate_style := StyleBoxFlat.new()
		plate_style.bg_color = CARD_BEST_PLATE_COLOR
		plate_style.set_corner_radius_all(CARD_BEST_PLATE_RADIUS)
		plate_style.anti_aliasing = true
		plate.add_theme_stylebox_override("panel", plate_style)
		card.add_child(plate)
		_card_best_plate.append(plate)

		# A row so the three pieces stay centred as a group however wide the
		# number's font ends up.
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(row)
		_card_best_row.append(row)

		var crown := TextureRect.new()
		crown.texture = _crown_texture
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_smooth_filter(crown)
		row.add_child(crown)
		_card_crown.append(crown)

		var best_label := _add_card_text(row, "BEST", CARD_BEST_COLOR)
		if _font_bold != null:
			best_label.add_theme_font_override("font", _font_bold)
		_card_best.append(best_label)

		var score_label := _add_card_text(row, "0".repeat(CARD_BEST_DIGITS), CARD_SCORE_COLOR)
		score_label.add_theme_color_override("font_outline_color", CARD_SCORE_OUTLINE)
		if _font_heavy != null:
			# Its own face rather than _font_heavy directly: the extra
			# tracking is for the digits only, and _font_heavy is shared with
			# the card name, START and the leaderboard label.
			score_label.add_theme_font_override("font", _tracked(_font_heavy, CARD_SCORE_TRACKING))
		_card_score.append(score_label)

	# Drawn after the cards so the outline lands on top of the chosen one.
	_select_overlay = Control.new()
	_select_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_overlay.draw.connect(_draw_selection)
	add_child(_select_overlay)

	# Not a TextureRect: the bar is drawn in three pieces so its height can be
	# set independently of its width — see _draw_explain_bar.
	_explain_texture = _load_art(EXPLAIN_FILE)
	_measure_explain_art()
	_explain = Control.new()
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_explain)
	_explain.draw.connect(_draw_explain_bar)
	add_child(_explain)
	_explain_label = Label.new()
	_explain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_explain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		_explain_label.add_theme_font_override("font", _font_bold if _font_bold != null else load(FONT_PATH))
	_explain_label.add_theme_color_override("font_color", EXPLAIN_TEXT_COLOR)
	_explain.add_child(_explain_label)

	_leaderboard = _make_button(_load_art(LEADERBOARD_FILE))
	_leaderboard.pressed.connect(_on_unimplemented.bind("리더보드"))
	add_child(_leaderboard)
	# The plate does not fill its texture — there is transparent padding around
	# it — so the icon is placed against the art's measured bounds rather than
	# the button rect, which would hang it off the bottom edge.
	_leaderboard_bounds = _texture_bounds(_leaderboard.texture_normal)
	_trophy = TextureRect.new()
	_trophy.texture = _load_icon(ICON_TROPHY_INDEX)
	_trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_trophy)
	_leaderboard.add_child(_trophy)

	_leaderboard_label = Label.new()
	_leaderboard_label.text = LEADERBOARD_LABEL
	_leaderboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_leaderboard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_heavy != null:
		_leaderboard_label.add_theme_font_override("font", _font_heavy)
	_leaderboard_label.add_theme_color_override("font_color", START_LABEL_COLOR)
	_leaderboard_label.add_theme_color_override("font_outline_color", START_LABEL_OUTLINE)
	_leaderboard.add_child(_leaderboard_label)

	# Added before the button so it draws underneath — children render in
	# order, and a halo on top would sit over the plate.
	_start_glow = Control.new()
	_start_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_glow.draw.connect(_draw_start_glow)
	add_child(_start_glow)

	_start = _make_button(_load_art(START_FILE))
	_start.pressed.connect(_on_start_pressed)
	add_child(_start)
	_start_bounds = _texture_bounds(_start.texture_normal)

	# A child of the button, so the press animation below scales the word
	# along with the plate instead of leaving it floating still.
	_start_label = Label.new()
	_start_label.text = START_LABEL
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		_start_label.add_theme_font_override("font", _font_heavy if _font_heavy != null else load(FONT_PATH))
	_start_label.add_theme_color_override("font_color", START_LABEL_COLOR)
	_start_label.add_theme_color_override("font_outline_color", START_LABEL_OUTLINE)
	_start.add_child(_start_label)

	_remove_ads = Button.new()
	_remove_ads.text = REMOVE_ADS_TEXT
	_remove_ads.flat = true
	_remove_ads.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(FONT_PATH):
		_remove_ads.add_theme_font_override("font", load(FONT_PATH))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_remove_ads.add_theme_color_override(state, REMOVE_ADS_COLOR)
	_remove_ads.pressed.connect(_on_unimplemented.bind("Remove Ads"))
	add_child(_remove_ads)
	# Its own child so the rule sits under the text and moves with it.
	_remove_ads_rule = Control.new()
	_remove_ads_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remove_ads_rule.draw.connect(_draw_remove_ads_rule)
	_remove_ads.add_child(_remove_ads_rule)

	# Every button gets the same press feedback.
	for button in [_start, _leaderboard] + _cards:
		button.button_down.connect(_animate_press.bind(button))
		button.button_up.connect(_animate_release.bind(button))

	_layout()


func _add_card_text(card: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_color_override("font_color", color)
	card.add_child(label)
	return label


# The opaque box of a texture, as fractions of its size — art rarely fills
# its own canvas, and anything positioned against it needs the real bounds.
func _texture_bounds(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2(0, 0, 1, 1)
	var image: Image = texture.get_image()
	if image == null:
		return Rect2(0, 0, 1, 1)
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	return _opaque_bounds(image)


# A whole file, cropped to its art. The crown is generated pixel art and
# carries empty margin around the shape; centring the untrimmed image would
# centre that margin instead.
func _load_trimmed(file_name: String) -> Texture2D:
	var texture := _load_art(file_name)
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var bounds: Rect2 = _opaque_bounds(image)
	var trimmed: Image = image.get_region(Rect2i(
		int(bounds.position.x * w), int(bounds.position.y * h),
		maxi(1, int(bounds.size.x * w)), maxi(1, int(bounds.size.y * h))))
	# 505px 짜리 왕관이 14px 로 그려진다. 그 축소를 GPU 밉맵 체인에 통째로
	# 맡기면 홀수 크기에서 마지막 열이 버려져 오른쪽이 깎여 보인다. 미리
	# 짝수 크기로 줄여 굽고 투명 여백을 둘러 가장자리가 흐려질 자리를 만든다.
	trimmed = _bake_small(trimmed)
	var ink := trimmed.get_size()
	var pad: int = maxi(4, int(round(maxi(ink.x, ink.y) * TRIM_INK_PAD_FRAC)))
	var pw: int = ink.x + pad * 2
	var ph: int = ink.y + pad * 2
	pw += pw % 2
	ph += ph % 2
	var padded := Image.create_empty(pw, ph, false, Image.FORMAT_RGBA8)
	# 여백의 RGB 는 검정이 아니라 실루엣 테두리 색 — 검정이면 줄일 때
	# 그 색이 끌려 들어와 가장자리가 어두워진다.
	padded.fill(Color(_edge_color(trimmed), 0.0))
	padded.blit_rect(trimmed, Rect2i(Vector2i.ZERO, ink), Vector2i(pad, pad))
	padded.generate_mipmaps()
	var texture_out := ImageTexture.create_from_image(padded)
	# 크기를 정할 때 여백을 빼고 실제 그림에 맞출 수 있도록 남겨 둔다.
	texture_out.set_meta("ink_frac", Vector2(float(ink.x) / pw, float(ink.y) / ph))
	return texture_out


# 그릴 크기에 가깝게 미리 줄인다. 알파를 곱한 채로 줄여야 투명한 쪽 RGB 가
# 끌려 들어오지 않는다.
func _bake_small(image: Image) -> Image:
	if image.get_height() <= TRIM_INK_BAKE_H:
		return image
	var w: int = maxi(2, int(round(image.get_width() * float(TRIM_INK_BAKE_H) / float(image.get_height()))))
	var out := image.duplicate() as Image
	out.premultiply_alpha()
	out.resize(w + w % 2, TRIM_INK_BAKE_H, Image.INTERPOLATE_LANCZOS)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
	return out


# 실루엣 가장자리(알파가 반쯤 있는 픽셀)의 평균 색.
func _edge_color(image: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c: Color = image.get_pixel(x, y)
			if c.a > 0.35 and c.a < 0.95:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	if n == 0:
		return Color(0, 0, 0)
	return Color(r / n, g / n, b / n)


# One icon out of the sheet, trimmed to its own art. The cells carry a lot of
# empty space around each glyph, and centring the untrimmed cell would centre
# that padding instead of the icon.
func _load_icon(index: int) -> Texture2D:
	var texture := _load_art(ICON_SHEET_FILE)
	if texture == null:
		return null
	var sheet: Image = texture.get_image()
	if sheet == null:
		return null
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.clear_mipmaps()
	var cell_w: int = sheet.get_width() / ICON_SHEET_GRID.x
	var cell_h: int = sheet.get_height() / ICON_SHEET_GRID.y
	var col: int = index % ICON_SHEET_GRID.x
	var row: int = index / ICON_SHEET_GRID.x
	var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
	var bounds: Rect2 = _opaque_bounds(cell)
	var trimmed: Image = cell.get_region(Rect2i(
		int(bounds.position.x * cell_w), int(bounds.position.y * cell_h),
		maxi(1, int(bounds.size.x * cell_w)), maxi(1, int(bounds.size.y * cell_h))))
	trimmed.generate_mipmaps()
	return ImageTexture.create_from_image(trimmed)


# The character sheets are the same 2x2 grids the game plays, so the cards
# show the real animation rather than a separate still.
func _slice_character(path: String) -> Array:
	var frames: Array = []
	if path == "" or not ResourceLoader.exists(path):
		return frames
	var texture: Texture2D = load(path)
	var sheet: Image = texture.get_image()
	if sheet == null:
		return frames
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.clear_mipmaps()
	var cell_w: int = sheet.get_width() / CARD_CHARACTER_GRID.x
	var cell_h: int = sheet.get_height() / CARD_CHARACTER_GRID.y
	for row in range(CARD_CHARACTER_GRID.y):
		for col in range(CARD_CHARACTER_GRID.x):
			var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
			# The card draws a 256px frame at about 89, so it needs mip levels
			# for the same reason the menu art does — see _use_smooth_filter.
			cell.generate_mipmaps()
			frames.append(ImageTexture.create_from_image(cell))
	return frames


func _make_image(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(rect)
	return rect


func _make_button(texture: Texture2D) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	_use_smooth_filter(button)
	return button


# ---------------------------------------------------------------- layout

func _aspect(control: Control) -> float:
	var texture: Texture2D
	if control is TextureRect:
		texture = (control as TextureRect).texture
	elif control is TextureButton:
		texture = (control as TextureButton).texture_normal
	if texture == null or texture.get_height() == 0:
		return 4.0  # harmless stand-in so a missing file cannot divide by zero
	return float(texture.get_width()) / float(texture.get_height())


func _layout() -> void:
	if _title == null or _start == null:
		return
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var title_w: float = view.x * TITLE_WIDTH_FRAC
	var title_h: float = title_w / _aspect(_title)
	var cards_w: float = view.x * CARDS_WIDTH_FRAC
	var card_gap: float = view.x * CARD_GAP_FRAC
	var card_w: float = (cards_w - card_gap) * 0.5
	var card_h: float = card_w / (_aspect(_cards[0]) if not _cards.is_empty() else 1.27)
	var cards_h: float = card_h * 2.0 + card_gap
	# Matched to the cards block, so the bar's ends sit exactly under the outer
	# edges of the left and right columns.
	var explain_w: float = cards_w
	# Height comes from the art's own proportions, then squashed — the three-
	# piece draw below keeps the caps circular at whatever height results.
	# Proportions come from the art itself, not its canvas — the current file
	# carries a lot of transparent padding, and using the canvas would make
	# the bar far too tall for the shape actually drawn in it.
	var explain_native: Vector2 = _explain_src.size
	var explain_h: float = explain_w * (explain_native.y / explain_native.x) * EXPLAIN_HEIGHT_SCALE
	var leaderboard_w: float = view.x * LEADERBOARD_WIDTH_FRAC
	var leaderboard_h: float = leaderboard_w / _aspect(_leaderboard)
	var start_w: float = view.x * START_WIDTH_FRAC
	var start_h: float = start_w / _aspect(_start)

	# Share whatever height is left between the five blocks, capped so a tall
	# screen does not scatter them; anything beyond the cap stays at the
	# bottom rather than stretching the column.
	var remove_ads_h: float = view.y * REMOVE_ADS_BLOCK_FRAC

	# Six blocks, so five gaps between them. The cards need more clearance
	# than the rest: the selected one wears a glow that reaches past its edge,
	# and at the plain gap it landed on the explain bar below.
	var explain_clearance: float = view.y * EXPLAIN_TOP_EXTRA_FRAC
	var content_h: float = title_h + cards_h + explain_h + leaderboard_h + start_h + remove_ads_h
	var top: float = view.y * TOP_MARGIN_FRAC
	var bottom: float = view.y * BOTTOM_MARGIN_FRAC
	var gap: float = clampf(
		(view.y - top - bottom - content_h - explain_clearance) / 5.0, 0.0, view.y * MAX_GAP_FRAC)

	var y: float = top
	_place(_title, title_w, title_h, y)
	y += title_h + gap

	var cards_left: float = (view.x - cards_w) * 0.5
	for i in range(_cards.size()):
		var col: int = i % 2
		var row: int = i / 2
		_cards[i].position = Vector2(cards_left + col * (card_w + card_gap), y + row * (card_h + card_gap))
		_cards[i].size = Vector2(card_w, card_h)
		_layout_card_contents(i, card_w, card_h)
	_select_overlay.position = Vector2.ZERO
	_select_overlay.size = view
	_select_overlay.queue_redraw()
	y += cards_h + gap + explain_clearance

	_place(_explain, explain_w, explain_h, y)
	if _explain_label != null:
		_explain_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_explain_label.offset_left = 0.0
		_explain_label.offset_top = 0.0
		_explain_label.offset_right = 0.0
		_explain_label.offset_bottom = 0.0
		_explain.queue_redraw()
		_explain_label.add_theme_font_size_override(
			"font_size", _fit_explain_size(explain_w * EXPLAIN_TEXT_WIDTH_FRAC))
	# From here the column is laid out from the bottom up — Remove Ads sits on
	# the bottom margin, START above it — so the leaderboard can then be
	# centred in whatever is left between the explain bar and START, rather
	# than following the explain bar at a fixed gap and leaving the space
	# below it uneven.
	var explain_bottom: float = y + explain_h
	var remove_ads_y: float = view.y - bottom - remove_ads_h
	var start_y: float = remove_ads_y - gap - start_h
	var leaderboard_y: float = explain_bottom + (start_y - explain_bottom - leaderboard_h) * 0.5

	_place(_leaderboard, leaderboard_w, leaderboard_h, leaderboard_y)
	if _trophy != null:
		var plate_pos := Vector2(
			_leaderboard_bounds.position.x * leaderboard_w,
			_leaderboard_bounds.position.y * leaderboard_h)
		var plate_size := Vector2(
			_leaderboard_bounds.size.x * leaderboard_w,
			_leaderboard_bounds.size.y * leaderboard_h)
		var trophy_h: float = plate_size.y * TROPHY_HEIGHT_FRAC
		_trophy.size = Vector2(trophy_h, trophy_h)
		_trophy.position = plate_pos + Vector2(
			plate_size.x * TROPHY_LEFT_FRAC,
			(plate_size.y - trophy_h) * 0.5)

		if _leaderboard_label != null:
			# From the trophy's right edge to the plate's right padding.
			var text_left: float = _trophy.position.x + trophy_h
			var text_right: float = plate_pos.x + plate_size.x * (1.0 - LEADERBOARD_LABEL_PAD_FRAC)
			_leaderboard_label.position = Vector2(text_left, plate_pos.y)
			_leaderboard_label.size = Vector2(maxf(1.0, text_right - text_left), plate_size.y)
			var wanted: int = int(round(plate_size.y * LEADERBOARD_LABEL_HEIGHT_FRAC))
			var size: int = _fit_text_size(
				_leaderboard_label, LEADERBOARD_LABEL, _leaderboard_label.size.x, wanted)
			_leaderboard_label.add_theme_font_size_override("font_size", size)
			_leaderboard_label.add_theme_constant_override(
				"outline_size", maxi(1, int(round(size * START_LABEL_OUTLINE_SIZE_FRAC))))
	# START and Remove Ads use the bottom-up positions computed above.
	_place(_start, start_w, start_h, start_y)
	# The plate is scaled on press, so the label is anchored to fill it and
	# rides along rather than being positioned in screen space.
	if _start_label != null:
		_start_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_start_label.offset_left = 0.0
		_start_label.offset_top = 0.0
		_start_label.offset_right = 0.0
		_start_label.offset_bottom = 0.0
		var font_size: int = int(round(start_h * START_LABEL_HEIGHT_FRAC))
		_start_label.add_theme_font_size_override("font_size", font_size)
		_start_glow.position = Vector2.ZERO
		_start_glow.size = view
		_start_glow.queue_redraw()
		_start_label.add_theme_constant_override(
			"outline_size", int(round(font_size * START_LABEL_OUTLINE_SIZE_FRAC)))

	if _remove_ads != null:
		_remove_ads.add_theme_font_size_override(
			"font_size", int(round(view.y * REMOVE_ADS_FONT_FRAC)))
		_place(_remove_ads, start_w, remove_ads_h, remove_ads_y)
		_remove_ads_rule.set_anchors_preset(Control.PRESET_FULL_RECT)
		_remove_ads_rule.offset_left = 0.0
		_remove_ads_rule.offset_top = 0.0
		_remove_ads_rule.offset_right = 0.0
		_remove_ads_rule.offset_bottom = 0.0
		_remove_ads_rule.queue_redraw()

	# Scaling happens about the middle, not the top-left corner.
	for button in [_start, _leaderboard] + _cards:
		button.pivot_offset = button.size * 0.5


# Name across the top, character in the middle, best score along the bottom.
# Positions are relative to the card, so they scale with the press animation.
func _layout_card_contents(index: int, card_w: float, card_h: float) -> void:
	if index >= _card_art.size():
		return
	# Against the card's own art, not the button rect. The four cards sit at
	# slightly different offsets inside their cells — up to about 2px once
	# drawn — so laying contents out on the button would put the title and
	# the score plate in a visibly different spot on each card.
	var bounds: Rect2 = _card_art_bounds[index] if index < _card_art_bounds.size() else Rect2(0, 0, 1, 1)
	var origin := Vector2(bounds.position.x * card_w, bounds.position.y * card_h)
	var art_w_total: float = bounds.size.x * card_w
	var art_h_total: float = bounds.size.y * card_h

	var inset: float = art_h_total * CARD_TEXT_INSET_FRAC
	var inner_w: float = art_w_total - inset * 2.0
	var name_h: float = art_h_total * CARD_NAME_HEIGHT_FRAC
	var best_h: float = art_h_total * CARD_BEST_HEIGHT_FRAC
	var art_h: float = art_h_total * CARD_ART_HEIGHT_FRAC

	var name_size: int = _fit_card_name_size(inner_w * CARD_NAME_WIDTH_FRAC, name_h)
	var outline_size: int = maxi(1, int(round(name_size * CARD_NAME_OUTLINE_FRAC)))
	_card_name[index].add_theme_font_size_override("font_size", name_size)
	_card_name[index].add_theme_constant_override("outline_size", outline_size)

	# One width for every card, from the longest name at the size just fitted.
	# The outline spreads the glyphs on both sides, so it counts toward the
	# room the text needs inside the plate.
	var widest := 0.0
	var name_font: Font = _card_name[index].get_theme_font("font")
	if name_font != null:
		for text in CARD_NAMES:
			widest = maxf(widest, name_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, name_size).x)
	var plate_pad: float = name_h * CARD_NAME_PLATE_PAD_FRAC
	var name_plate_w: float = minf(inner_w, widest + outline_size * 2.0 + plate_pad * 2.0)
	_card_name_plate[index].position = origin + Vector2((art_w_total - name_plate_w) * 0.5, inset)
	_card_name_plate[index].size = Vector2(name_plate_w, name_h)
	_card_name[index].set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_name[index].offset_left = 0.0
	_card_name[index].offset_top = 0.0
	_card_name[index].offset_right = 0.0
	_card_name[index].offset_bottom = 0.0

	_card_art[index].position = origin + Vector2(inset, inset + name_h)
	_card_art_rest_y[index] = _card_art[index].position.y
	_card_art[index].size = Vector2(inner_w, art_h)

	var plate_w: float = inner_w * CARD_BEST_PLATE_WIDTH_FRAC
	_card_best_plate[index].position = origin + Vector2(
		(art_w_total - plate_w) * 0.5, art_h_total - inset - best_h)
	_card_best_plate[index].size = Vector2(plate_w, best_h)
	var score_size: int = int(round(best_h * 0.62))
	_card_best[index].add_theme_font_size_override("font_size", score_size)
	_card_score[index].add_theme_font_size_override("font_size", score_size)
	_card_score[index].add_theme_constant_override(
		"outline_size", int(round(score_size * CARD_SCORE_OUTLINE_FRAC)))

	# 높이를 기준으로 잡고 가로는 그림 비율대로. 정사각으로 두면 가로로 넓은
	# 왕관이 그 안에 눕혀지면서 요청한 높이보다 낮게 나온다.
	var crown_h: float = best_h * CARD_BEST_CROWN_HEIGHT_FRAC
	var crown_ratio := 1.0
	var crown_ink := Vector2.ONE
	if _crown_texture != null and _crown_texture.get_height() > 0:
		crown_ratio = float(_crown_texture.get_width()) / float(_crown_texture.get_height())
		crown_ink = _crown_texture.get_meta("ink_frac", Vector2.ONE)
	# CARD_BEST_CROWN_HEIGHT_FRAC 은 "눈에 보이는 왕관" 기준이다. 텍스처에
	# 두른 투명 여백만큼 상자를 키우고, 가로는 그림 비율대로 잡는다 — 정사각에
	# 넣으면 가로로 넓은 왕관이 그 안에 눕혀져 요청한 높이보다 낮게 나온다.
	var box_h: float = crown_h / maxf(crown_ink.y, 0.01)
	_card_crown[index].custom_minimum_size = Vector2(box_h * crown_ratio, box_h)
	_card_best_row[index].add_theme_constant_override(
		"separation", int(round(best_h * CARD_BEST_ROW_SEPARATION_FRAC)))
	_card_best_row[index].set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_best_row[index].offset_left = 0.0
	_card_best_row[index].offset_top = 0.0
	_card_best_row[index].offset_right = 0.0
	_card_best_row[index].offset_bottom = 0.0


# Starts from the size the layout would like and steps down only if the text
# would overrun the width it has been given.
func _fit_text_size(label: Label, text: String, max_width: float, wanted: int) -> int:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return wanted
	var size: int = wanted
	while size > LEADERBOARD_LABEL_MIN_SIZE:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x <= max_width:
			break
		size -= 1
	return size


# The largest size at which every card name fits its card — width and height
# both — so all four render at one size and none spills over its border.
func _fit_card_name_size(max_width: float, max_height: float) -> int:
	if _card_name.is_empty():
		return CARD_NAME_MIN_SIZE
	var font: Font = _card_name[0].get_theme_font("font")
	if font == null:
		return CARD_NAME_MIN_SIZE
	var size: int = CARD_NAME_MAX_SIZE
	while size > CARD_NAME_MIN_SIZE:
		var widest := 0.0
		var tallest := 0.0
		for text in CARD_NAMES:
			var measured: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
			widest = maxf(widest, measured.x)
			tallest = maxf(tallest, measured.y)
		# The outline grows the glyphs on every side, so it counts toward the
		# space the name actually needs.
		var outline: float = size * CARD_NAME_OUTLINE_FRAC * 2.0
		if widest + outline <= max_width and tallest + outline <= max_height:
			break
		size -= 1
	return size


# The largest size at which *every* description still fits on one line, so
# they all render at the same size instead of each shrinking to its own fit.
func _fit_explain_size(max_width: float) -> int:
	var font: Font = _explain_label.get_theme_font("font")
	if font == null:
		return EXPLAIN_TEXT_MIN_SIZE
	var size: int = EXPLAIN_TEXT_MAX_SIZE
	while size > EXPLAIN_TEXT_MIN_SIZE:
		var widest := 0.0
		for text in CARD_EXPLAIN:
			widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x)
		if widest <= max_width:
			break
		size -= 1
	return size


func _place(control: Control, w: float, h: float, y: float) -> void:
	control.position = Vector2((size.x - w) * 0.5, y)
	control.size = Vector2(w, h)


# Godot's Label and Button have no underline, so the rule is measured off the
# text and drawn under it — which also keeps it exactly as wide as the words.
# Same concentric-ring halo as the selected card, around START's plate.
func _draw_start_glow() -> void:
	if _start == null:
		return
	var plate := Rect2(
		_start.position + Vector2(
			_start_bounds.position.x * _start.size.x,
			_start_bounds.position.y * _start.size.y),
		Vector2(_start_bounds.size.x * _start.size.x, _start_bounds.size.y * _start.size.y))
	# The halo lives on its own node, so it does not inherit the button's
	# press scale the way a child would — without this it stayed full size
	# while the button shrank under it, and the button looked like it was
	# sinking out of its own glow. Reproduce the button's transform by hand:
	# scale about its pivot, which _layout parks at the button's centre.
	var press: float = _start.scale.x
	if not is_equal_approx(press, 1.0):
		var pivot: Vector2 = _start.position + _start.pivot_offset
		plate = Rect2(pivot + (plate.position - pivot) * press, plate.size * press)
	var radius: int = int(round(START_CORNER_NATIVE * (_start.size.x / START_SHEET_WIDTH_NATIVE) * press))
	for i in range(START_GLOW_RINGS):
		var t: float = float(i + 1) / float(START_GLOW_RINGS)
		# Spread scales too, so the halo tightens with the button instead of
		# hanging at its resting width around a smaller plate.
		var grow: float = START_GLOW_BORDER * START_GLOW_SPREAD * t * press
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(radius + int(round(grow)))
		glow.set_border_width_all(maxi(1, int(round(START_GLOW_BORDER))))
		glow.border_color = Color(
			START_GLOW_COLOR.r, START_GLOW_COLOR.g, START_GLOW_COLOR.b,
			START_GLOW_COLOR.a * (1.0 - t * 0.75))
		glow.anti_aliasing = true
		_start_glow.draw_style_box(glow, plate.grow(grow))


# Measures the bar in its file: where the art actually sits, and how deep the
# left edge runs before it stops curving inward. That depth is the corner
# radius, and so also how wide a slice has to be to contain a whole cap.
func _measure_explain_art() -> void:
	_explain_src = Rect2(0, 0, 1, 1)
	_explain_cap = 1.0
	if _explain_texture == null:
		return
	var image: Image = _explain_texture.get_image()
	if image == null:
		return
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var bounds: Rect2 = _opaque_bounds(image)
	_explain_src = Rect2(
		round(bounds.position.x * w), round(bounds.position.y * h),
		maxf(1.0, round(bounds.size.x * w)), maxf(1.0, round(bounds.size.y * h)))

	var data: PackedByteArray = image.get_data()
	var left: int = int(_explain_src.position.x)
	var top: int = int(_explain_src.position.y)
	var art_h: int = int(_explain_src.size.y)
	var art_w: int = int(_explain_src.size.x)
	for row in range(art_h):
		var y: int = top + row
		var inset: int = art_w
		for col in range(art_w):
			if data[(y * w + left + col) * 4 + 3] > 24:
				inset = col
				break
		if inset <= 0:
			# First row whose edge has straightened out — the curve above it
			# is the corner, and its depth is the radius.
			_explain_cap = maxf(1.0, float(row))
			return
	_explain_cap = _explain_src.size.y * 0.5


func _draw_explain_bar() -> void:
	if _explain_texture == null or _explain_src.size.x <= 0.0:
		return
	var box: Vector2 = _explain.size
	var src: Rect2 = _explain_src
	# Caps keep the art's own proportions at this height; the middle takes
	# whatever width is left. A bar narrower than two caps would have them
	# overlap, so they are clamped to half each.
	var scale: float = box.y / src.size.y
	var cap: float = minf(_explain_cap * scale, box.x * 0.5)
	var cap_src: float = minf(_explain_cap, src.size.x * 0.5)
	_explain.draw_texture_rect_region(
		_explain_texture, Rect2(0, 0, cap, box.y),
		Rect2(src.position, Vector2(cap_src, src.size.y)))
	_explain.draw_texture_rect_region(
		_explain_texture, Rect2(box.x - cap, 0, cap, box.y),
		Rect2(Vector2(src.position.x + src.size.x - cap_src, src.position.y),
			Vector2(cap_src, src.size.y)))
	var middle: float = box.x - cap * 2.0
	if middle > 0.0:
		_explain.draw_texture_rect_region(
			_explain_texture, Rect2(cap, 0, middle, box.y),
			Rect2(Vector2(src.position.x + cap_src, src.position.y),
				Vector2(src.size.x - cap_src * 2.0, src.size.y)))


func _draw_remove_ads_rule() -> void:
	if _remove_ads == null:
		return
	var font: Font = _remove_ads.get_theme_font("font")
	if font == null:
		return
	var font_size: int = _remove_ads.get_theme_font_size("font_size")
	var text_size: Vector2 = font.get_string_size(REMOVE_ADS_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var centre: Vector2 = _remove_ads.size * 0.5
	# The baseline sits below the visual middle by roughly a quarter of the
	# line box, the same approximation the text drawing elsewhere uses.
	var baseline_y: float = centre.y + text_size.y * 0.25 + REMOVE_ADS_UNDERLINE_GAP
	var half: float = text_size.x * 0.5
	_remove_ads_rule.draw_line(
		Vector2(centre.x - half, baseline_y),
		Vector2(centre.x + half, baseline_y),
		REMOVE_ADS_COLOR, REMOVE_ADS_UNDERLINE_WIDTH)


func _draw_selection() -> void:
	if selected_index < 0 or selected_index >= _cards.size():
		return
	var card: TextureButton = _cards[selected_index]
	# The cards do not all sit at the same offset inside their cell, so the
	# outline is placed on the card's measured opaque bounds rather than on
	# the button rect — otherwise it would float off one card and cut into
	# another.
	var bounds: Rect2 = _card_art_bounds[selected_index] if selected_index < _card_art_bounds.size() else Rect2(0, 0, 1, 1)
	var rect := Rect2(
		card.position + Vector2(bounds.position.x * card.size.x, bounds.position.y * card.size.y),
		Vector2(bounds.size.x * card.size.x, bounds.size.y * card.size.y))
	rect.size.y += card.size.y * SELECT_BOTTOM_EXTEND_FRAC

	# Card geometry measured on the sheet, converted to this card's scale.
	var art_scale: float = card.size.x / SELECT_SHEET_WIDTH_NATIVE
	var border: float = maxf(2.0, SELECT_CARD_BORDER_NATIVE * art_scale * SELECT_BORDER_SCALE)
	var radius: int = int(round(SELECT_CORNER_NATIVE * art_scale))

	# Halo first, so the solid ring lands on top of it. Each pass sits a
	# little further out and a little fainter, which reads as a glow.
	for i in range(SELECT_GLOW_RINGS):
		var t: float = float(i + 1) / float(SELECT_GLOW_RINGS)
		var grow: float = border * SELECT_GLOW_SPREAD * t
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(radius + int(round(grow)))
		glow.set_border_width_all(maxi(1, int(round(border))))
		glow.border_color = Color(
			SELECT_GLOW_COLOR.r, SELECT_GLOW_COLOR.g, SELECT_GLOW_COLOR.b,
			SELECT_GLOW_COLOR.a * (1.0 - t * 0.75))
		glow.anti_aliasing = true
		_select_overlay.draw_style_box(glow, rect.grow(grow))

	# Outer ring: the gold border plus a soft drop shadow, which is what
	# lifts the chosen card off the page.
	var outer := StyleBoxFlat.new()
	outer.draw_center = false
	outer.set_corner_radius_all(radius)
	outer.set_border_width_all(int(round(border)))
	outer.border_color = SELECT_COLOR
	outer.shadow_color = SELECT_SHADOW_COLOR
	outer.shadow_size = SELECT_SHADOW_SIZE
	outer.shadow_offset = SELECT_SHADOW_OFFSET
	outer.anti_aliasing = true
	_select_overlay.draw_style_box(outer, rect)

	# A thin brighter line just inside it reads as the lit top face of a
	# bevel, so the ring looks rounded rather than painted flat.
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.set_corner_radius_all(maxi(1, radius - int(border)))
	inner.set_border_width_all(1)
	inner.border_color = SELECT_HIGHLIGHT_COLOR
	inner.anti_aliasing = true
	_select_overlay.draw_style_box(inner, rect.grow(-border))


# ---------------------------------------------------------------- behaviour

func _animate_press(button: Control) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * PRESS_SCALE, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_follow_with_glow(tween, button)


func _animate_release(button: Control) -> void:
	# TRANS_BACK overshoots slightly on the way home, which is what makes the
	# button feel like it springs rather than merely returning.
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_follow_with_glow(tween, button)


# START's halo is a sibling node, so nothing repaints it when the button's
# scale animates — it would hold its old shape until the next layout pass.
# Drive a redraw alongside the scale tween so the two move together. The
# overshoot at the end of a release is included, which is the point: the
# halo springs with the button rather than snapping after it.
func _follow_with_glow(tween: Tween, button: Control) -> void:
	if button != _start or _start_glow == null:
		return
	tween.parallel().tween_method(
		func(_t: float) -> void: _start_glow.queue_redraw(),
		0.0, 1.0, PRESS_ANIM_DURATION)


## Fills each card's BEST plate. The array is indexed by mode, and the
## cards are built in CARD_MODES order, so index i belongs to CARD_MODES[i].
##
## Digits are zero-padded to CARD_BEST_DIGITS so the plates all stay the
## same width — a record that grows a digit must not reflow the card.
func set_best_scores(values: PackedInt32Array) -> void:
	for i in range(_card_score.size()):
		var mode: int = CARD_MODES[i]
		var value: int = values[mode] if mode < values.size() else 0
		_card_score[i].text = "%0*d" % [CARD_BEST_DIGITS, value]


func _on_card_pressed(index: int) -> void:
	# The cue fires on every tap, including one on the already-selected card:
	# it is feedback for the press, not for the selection changing.
	_play(_sfx_select)
	_select(index)


func _select(index: int) -> void:
	selected_index = index
	if _explain_label != null and index < CARD_EXPLAIN.size():
		_explain_label.text = CARD_EXPLAIN[index]
	if _select_overlay != null:
		_select_overlay.queue_redraw()


func _on_start_pressed() -> void:
	if selected_index < 0 or selected_index >= CARD_MODES.size():
		return
	var mode: int = CARD_MODES[selected_index]
	# Started before the mode is handed over: emitting swaps the screen and
	# crossfades the music, and the cue should be underway before that.
	_play(_sfx_start)
	# The fourth slot is the mode still being built. It is reachable while
	# developing — running from the editor or a debug export — and refused in
	# a release build, where it is meant to read as locked.
	if mode == MODE_HIDDEN and not OS.is_debug_build():
		print("[미구현] 히든 모드")
		return
	start_pressed.emit(mode)


func _on_unimplemented(what: String) -> void:
	print("[미구현] ", what)
