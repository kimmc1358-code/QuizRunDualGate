class_name ArtSlot
extends RefCounted

## Placeholder art. On 2026-11-26 every 1.x image under assets/ was deleted —
## title, mode select, the play-screen HUD and the popups are all being
## redrawn for 2.0 — and each place that loaded one now goes through here.
## A file that exists is loaded as before; a missing one comes back as a box
## with an X across it, at the size the old art had, so that every layout
## that sizes itself off its art keeps the proportions it was built with.
##
## So the paths in the screens' constants are slots now. Drop new art at one
## and it is used on the next run, with no code change; delete its row in
## SIZES once nothing should fall back for it. A path with no row comes back
## as a 256px square and says so once.
##
## A sheet (an icon grid, a character's animation frames) gets one box per
## cell, inset so the slicers that follow ink to a cell's edge stop inside it.

const FILL := Color(0.36, 0.42, 0.56, 0.55)
# Light blue rather than white: PopupBase._strip_white_background takes near-
# white, colourless pixels touching the edge for a background and deletes them.
const EDGE := Color(0.72, 0.84, 1.0, 0.95)
const CROSS := Color(0.72, 0.84, 1.0, 0.5)
## Art that is stretched into a panel, a button or a bar gets a solid frame
## and no X. An X stretched across a popup ran through every line of text in
## it, and a see-through panel let the screen behind read through the words.
# Mid grey: the dark text laid on these was coloured for the old cream panels,
# and the buttons' white words need some contrast too.
const FRAME_FILL := Color(0.66, 0.70, 0.78, 0.97)
const FRAMES := [
	"res://assets/ui_assets/popup/popup_panel.png",
	"res://assets/ui_assets/popup/button_gold_v2.png",
	"res://assets/ui_assets/popup/button_cream_v4.png",
	"res://assets/ui_assets/popup/best_box.png",
	"res://assets/ui_assets/popup/popup_best.png",
	"res://assets/synty_ui/score_bar.png",
	"res://assets/synty_ui/quiz_box.png",
	"res://assets/synty_ui/side_slot.png",
	"res://assets/synty_ui/gauge.png",
	"res://assets/synty_ui/weapon_back.png",
	"res://assets/synty_ui/card_frame.png",
	"res://assets/synty_ui/card_frame_on.png",
	"res://assets/synty_ui/play_button.png",
	"res://assets/synty_ui/explain_bar.png",
]
## Each cell's box is inset this share of the cell, leaving a transparent gap.
const CELL_INSET := 0.06
const DEFAULT_SIZE := Vector2i(256, 256)

## Size of the art each slot used to hold. Per-mode folders share one row:
## <mode> stands for sky, jungle, ocean or dream (see _key).
const SIZES := {
	# title — the JANIJU logo (title/logo.png) is real art and was restored
	"res://assets/synty_ui/title_star.png": Vector2i(315, 428),
	"res://assets/synty_ui/title_wreath.png": Vector2i(431, 338),
	"res://assets/synty_ui/title_bar.png": Vector2i(707, 38),
	# mode select
	"res://assets/ui_assets/main/title_main_v2.png": Vector2i(1774, 887),
	"res://assets/ui_assets/main/icon_sheet.png": Vector2i(1536, 1024),
	# play-screen HUD: the Synty UI kit, built by tools/build_ui_kit.gd (gitignored)
	"res://assets/synty_ui/score_bar.png": Vector2i(500, 117),
	"res://assets/synty_ui/quiz_box.png": Vector2i(548, 128),
	"res://assets/synty_ui/pause.png": Vector2i(117, 117),
	"res://assets/synty_ui/side_slot.png": Vector2i(127, 128),
	"res://assets/synty_ui/gauge.png": Vector2i(216, 36),
	"res://assets/synty_ui/weapon_back.png": Vector2i(294, 68),
	"res://assets/synty_ui/best_icon.png": Vector2i(50, 50),
	"res://assets/synty_ui/card_frame.png": Vector2i(692, 338),
	"res://assets/synty_ui/card_frame_on.png": Vector2i(692, 338),
	"res://assets/synty_ui/play_button.png": Vector2i(410, 194),
	"res://assets/synty_ui/explain_bar.png": Vector2i(428, 104),
	"res://assets/synty_ui/icon_person.png": Vector2i(58, 90),
	"res://assets/synty_ui/icon_settings.png": Vector2i(81, 90),
	"res://assets/synty_ui/icon_trophy.png": Vector2i(90, 90),
	"res://assets/synty_ui/icon_upgrade.png": Vector2i(49, 90),
	"res://assets/synty_ui/icon_hangar.png": Vector2i(132, 90),
	"res://assets/synty_ui/icon_lock.png": Vector2i(72, 90),
	"res://assets/synty_ui/icon_stardust.png": Vector2i(55, 63),
	"res://assets/ui_assets/<mode>/Ready_v3.png": Vector2i(532, 240),
	"res://assets/ui_assets/<mode>/Start_v3.png": Vector2i(532, 240),
	# popups
	"res://assets/ui_assets/popup/popup_panel.png": Vector2i(1024, 1536),
	"res://assets/ui_assets/popup/button_gold_v2.png": Vector2i(848, 244),
	"res://assets/ui_assets/popup/button_cream_v4.png": Vector2i(2041, 771),
	"res://assets/ui_assets/popup/button_cancel.png": Vector2i(1278, 1230),
	"res://assets/ui_assets/popup/best_box.png": Vector2i(2172, 724),
	"res://assets/ui_assets/popup/popup_best.png": Vector2i(2172, 724),
	"res://assets/ui_assets/popup/settings_popup.png": Vector2i(2172, 724),
	"res://assets/ui_assets/popup/oops_popup.png": Vector2i(920, 334),
	"res://assets/ui_assets/popup/tryagain_popup.png": Vector2i(1369, 338),
	"res://assets/ui_assets/popup/icon_popup.png": Vector2i(1983, 793),
	"res://assets/ui_assets/popup/icon_popup_2.png": Vector2i(1774, 887),
	"res://assets/ui_assets/popup/icon_crown.png": Vector2i(1536, 1024),
	"res://assets/ui_assets/popup/icon_fire.png": Vector2i(1254, 1254),
	"res://assets/ui_assets/popup/icon_google.png": Vector2i(240, 240),
	"res://assets/ui_assets/popup/icon_information.png": Vector2i(1254, 1254),
	"res://assets/ui_assets/popup/icon_noads.png": Vector2i(1263, 1245),
	"res://assets/ui_assets/popup/icon_trophy.png": Vector2i(1374, 1145),
	# characters: the animation sheets and the two faces
	"res://assets/characters/bird_v2/bird_fly.png": Vector2i(512, 512),
	"res://assets/characters/dragon_green/dragon_fly.png": Vector2i(512, 512),
	"res://assets/characters/shark_blue/shark_swim.png": Vector2i(512, 512),
	"res://assets/characters/unicorn_dream/unicorn_run.png": Vector2i(768, 512),
	"res://assets/characters/<char>/<face>.png": Vector2i(256, 256),
}

## Sheets: how many cells across and down. Matches the grids their callers
## slice with (PopupBase.ICON_GRID / POPUP_ICON_GRID / STATUS_ICON_GRID,
## Main.MODE_CHARACTER_SHEET_GRID).
const GRIDS := {
	"res://assets/ui_assets/main/icon_sheet.png": Vector2i(5, 3),
	"res://assets/ui_assets/popup/icon_popup.png": Vector2i(3, 1),
	"res://assets/ui_assets/popup/icon_popup_2.png": Vector2i(2, 1),
	"res://assets/characters/bird_v2/bird_fly.png": Vector2i(2, 2),
	"res://assets/characters/dragon_green/dragon_fly.png": Vector2i(2, 2),
	"res://assets/characters/shark_blue/shark_swim.png": Vector2i(2, 2),
	"res://assets/characters/unicorn_dream/unicorn_run.png": Vector2i(3, 2),
}

static var _textures := {}
static var _warned := {}


## The art at `path`, or its placeholder.
static func texture(path: String) -> Texture2D:
	# Held here, real files included: a texture loaded inside a _draw and
	# referenced by nothing else is freed as soon as the draw returns, and the
	# canvas then draws a white box where it was (the HUD frames did, the
	# first time they were read straight from the draw code).
	if _textures.has(path):
		return _textures[path]
	if ResourceLoader.exists(path):
		_textures[path] = load(path)
		return _textures[path]
	if not _textures.has(path):
		var img := image(path)
		img.generate_mipmaps()
		_textures[path] = ImageTexture.create_from_image(img)
	return _textures[path]


## The art at `path` as an RGBA8 Image, or its placeholder — for the loaders
## that cut, trim or resize what they read.
static func image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var img: Image = (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		return img
	var key := _key(path)
	var size: Vector2i = SIZES.get(key, DEFAULT_SIZE)
	if not SIZES.has(key) and not _warned.has(path):
		_warned[path] = true
		push_warning("ArtSlot: no size recorded for %s — drawing a %dpx square" % [path, DEFAULT_SIZE.x])
	return box(size, GRIDS.get(key, Vector2i.ONE), FRAMES.has(key))


## A placeholder of `size`, one box per cell of `grid`; `frame` for art that
## is stretched into a panel or button (see FRAMES).
static func box(size: Vector2i, grid := Vector2i.ONE, frame := false) -> Image:
	var img := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cw := float(size.x) / grid.x
	var ch := float(size.y) / grid.y
	for row in grid.y:
		for col in grid.x:
			var inset := Vector2(cw, ch) * (CELL_INSET if grid != Vector2i.ONE else 0.0)
			var r := Rect2i(Vector2i(Vector2(col * cw, row * ch) + inset),
				Vector2i(Vector2(cw, ch) - inset * 2.0))
			_draw_box(img, r, frame)
	return img


static func _draw_box(img: Image, r: Rect2i, frame: bool) -> void:
	if r.size.x < 2 or r.size.y < 2:
		return
	img.fill_rect(r, FRAME_FILL if frame else FILL)
	var t: int = clampi(int(minf(r.size.x, r.size.y) * 0.03), 2, 12)
	img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, t)), EDGE)
	img.fill_rect(Rect2i(Vector2i(r.position.x, r.end.y - t), Vector2i(r.size.x, t)), EDGE)
	img.fill_rect(Rect2i(r.position, Vector2i(t, r.size.y)), EDGE)
	img.fill_rect(Rect2i(Vector2i(r.end.x - t, r.position.y), Vector2i(t, r.size.y)), EDGE)
	if frame:
		return
	# The X: what marks a box as "a picture goes here" rather than a panel.
	var steps: int = maxi(r.size.x, r.size.y)
	var half: int = maxi(1, t / 2)
	for i in steps:
		var f := float(i) / steps
		var x := r.position.x + int(f * (r.size.x - 1))
		var y1 := r.position.y + int(f * (r.size.y - 1))
		var y2 := r.end.y - 1 - int(f * (r.size.y - 1))
		img.fill_rect(Rect2i(x - half, y1 - half, half * 2, half * 2), CROSS)
		img.fill_rect(Rect2i(x - half, y2 - half, half * 2, half * 2), CROSS)


## Per-mode and per-character folders share a row in SIZES.
static func _key(path: String) -> String:
	for m in ["sky", "jungle", "ocean", "dream"]:
		if path.begins_with("res://assets/ui_assets/%s/" % m):
			return path.replace("/%s/" % m, "/<mode>/")
	if path.begins_with("res://assets/characters/") and (path.ends_with("_happy.png") or path.ends_with("_sad.png")):
		return "res://assets/characters/<char>/<face>.png"
	return path
