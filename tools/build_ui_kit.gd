extends SceneTree

# Builds the play-screen HUD art from Synty's INTERFACE Sci-Fi Menus pack.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_ui_kit.gd -- <SourceFiles dir> [piece.png ...]
#
# <SourceFiles dir> is the unzipped INTERFACE_SciFi_Menus_SourceSprites_v1
# zip's SourceFiles/ folder. Only the sprites named in PIECES are read.
#
# **Nothing this writes may go into git.** The repository is public and
# Synty's licence allows shipping their art inside a built game, not handing
# out the source files — the same rule as the space kit (build_space_kit.py).
# The output goes to assets/synty_ui/, which .gitignore excludes. Without it
# the game still runs: every slot falls back to an ArtSlot placeholder.
#
# Each piece is a frame laid over its own "_Background" sprite tinted dark,
# so text on it reads against the space behind, then shrunk to BAKE x the
# size it is drawn at on the 480-wide screen. A phone draws the game about
# 2.25x larger than that, so baking at that factor lets the frames render
# near 1:1 there with no mipmaps; shrinking a 2048px sprite to 57px at draw
# time would alias. Alpha is premultiplied for the resize, or the transparent
# pixels' colour bleeds into the edges as a dark fringe.

const OUT := "res://assets/synty_ui/"
const BAKE := 2.25
const BACK_TINT := Color(0.04, 0.06, 0.13, 0.78)

## out file: [frame sprite, background sprite or "", drawn height at 480 wide,
## optional tint for a white icon (null for none), optional tint for the
## background in place of BACK_TINT, or with a sixth, the top and bottom of
## a gradient tint down the background]
const PIECES := {
	"score_bar.png": ["SciFiMenus/SPR_SciFiMenus_Bar_Frame_01", "SciFiMenus/SPR_SciFiMenus_Bar_Frame_01_Background", 52.0],
	"quiz_box.png": ["SciFiMenus/SPR_SciFiMenus_Button_Frame_01", "SciFiMenus/SPR_SciFiMenus_Button_Frame_01_Background", 57.0],
	"side_slot.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_07", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_07_Background", 57.0],
	"pause.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_10", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_10_Background", 52.0],
	"gauge.png": ["SciFiMenus/SPR_SciFiMenus_Bar_Frame_08", "", 16.0],
	"weapon_back.png": ["General/SPR_SciFiMenus_Menu_Item_Background_03_Blue", "", 30.0],
	"best_icon.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Trophy_01_Clean", "", 22.0, Color(1.0, 0.80, 0.25)],
	# The mode select (2026-11-27): one frame for all three mode cards, and
	# white icons for its buttons. Its square buttons reuse side_slot.png and
	# its stardust readout score_bar.png,
	# so the menu and the play screen read as one set.
	"card_frame.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_12", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_12_Background", 150.0],
	# The selected card (2026-11-27): the same frame with its face lit cyan,
	# brighter at the top and see-through so the space shows behind it, so the
	# choice shows inside the card rather than as a ring around it. The fifth
	# and sixth entries are the face's top and bottom tint; ModeSelectScreen
	# adds scanlines and a sweep over it.
	"card_frame_on.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_12", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_12_Background", 150.0, null, Color(0.14, 0.62, 0.86, 0.62), Color(0.04, 0.20, 0.42, 0.70)],
	"icon_person.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Solo_01_Clean", "", 40.0],
	"icon_settings.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Settings_01_Clean", "", 40.0],
	"icon_trophy.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Trophy_01_Clean", "", 40.0],
	"icon_upgrade.png": ["Icons_Menu/ICON_SciFiMenus_Menu_LightningBolt_01_Clean", "", 40.0],
	"icon_hangar.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Planet_02_Clean", "", 40.0],
	"icon_lock.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Lock_Closed_01_Clean", "", 40.0],
	"icon_stardust.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Currency_01_Clean", "", 28.0, Color(0.55, 0.92, 1.0)],
	# Its own explain bar (2026-11-27), not the score bar again: the menu read as
	# the play screen's HUD. Its PLAY is the popups' main button (popup_bar_primary).
	"explain_bar.png": ["SciFiMenus/SPR_SciFiMenus_Button_Frame_05", "SciFiMenus/SPR_SciFiMenus_Button_Frame_05_Background", 46.0],
	# The title screen, after the pack's own banner: a gold star on a wreath
	# between the two halves of the name, a metal bar under it.
	"title_star.png": ["Crests/SPR_SciFiMenus_Crest_Star_01_Gold", "", 190.0],
	"title_wreath.png": ["Crests/SPR_SciFiMenus_Crest_Wreath_02", "", 150.0],
	# The bar under the title: thin angled linework, picked on 2026-11-27 over
	# the heavier Bar_02 and the blue-lit Bar_09. Drawn at its own proportions
	# across the screen, so it is baked to that width.
	"title_bar.png": ["SciFiMenus/SPR_SciFiMenus_Bar_11_Bottom", "", 17.0],
	# The popups (2026-11-28). The panel is the blue-lit frame with steel
	# corner caps, its face nearly opaque so rows of text read over the
	# space; it is cut down to a nine-patch (see NINE). Every button is
	# Frame_Box_Small_08, a bar whose screwed steel block closes the right end,
	# mirrored onto the left too (MIRROR_RIGHT): its own left edge is a hairline
	# meant to sit under an icon cell, and alone it read as cut off. Three-sliced
	# at its height (PopupBase._kit_patch), and
	# only the face tells them apart: orange for the main button, blue for the
	# others. On the way, each owner's call: the main button was Bar_Frame_02
	# with cyan tips, which did not belong with the rest; then every button was
	# Frame_Box_Small_04, a thin silver bevel (still baked, as the volume bar's
	# handle); then the secondaries were the pack's Label_Button sample, an icon
	# cell (Frame_Box_Small_01) clamped over the end of this bar. The result
	# rows left the button frame for a layer drawn in code
	# (GameOverPopup._draw_box): framed like a button, they looked pressable.
	# The title is plain text over the panel (PopupBase._make_title), with no
	# plate. The owner went from this frame to the orange-bracketed Large_01 with
	# a title bar and back again the same day.
	"popup_panel.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_08", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Large_08_Background", 330.0, null, Color(0.035, 0.06, 0.13, 0.95)],
	"popup_bar_primary.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_08", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_08_Background", 46.0, null, Color(1.0, 0.72, 0.22, 1.0)],
	"popup_bar.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_08", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_08_Background", 46.0, null, Color(0.06, 0.24, 0.50, 0.97)],
	"popup_button.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_04", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_04_Background", 40.0, null, Color(0.06, 0.24, 0.50, 0.97)],
	# The small buttons (LOGIN, the game over's x2) keep the bevel: even with the
	# blocks squeezed, the bar's two steel ends left them almost no face.
	"popup_small_primary.png": ["SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_04", "SciFiMenus/SPR_SciFiMenus_Frame_Box_Small_04_Background", 40.0, null, Color(1.0, 0.72, 0.22, 1.0)],
	# The volume bars in settings and pause (2026-11-28, after a sample the owner
	# sent): Bar_Frame_02's frame alone, with the face, the fill and the handle
	# drawn in code (PopupBase.KitSlider). The handle is popup_button.png; the
	# Frame_Box_Small_06 tried first, with steel caps either side, was too busy
	# for a handle. Baked at the bar's drawn height.
	"slider_frame.png": ["SciFiMenus/SPR_SciFiMenus_Bar_Frame_02", "", 30.0],
	# The step buttons either end: Button_Arrow_07 with its cyan light layer laid
	# in its dark plate. Bar_Frame_02's own tips are too small to read as
	# buttons at 30 px. The lights are drawn for the left arrow, so the right
	# one takes them mirrored (FLIP_FRAME). The background slot is used to put
	# the arrow under its lights, untinted.
	"slider_arrow_left.png": ["SciFiMenus/SPR_SciFiMenus_Button_Arrow_07_Lights", "SciFiMenus/SPR_SciFiMenus_Button_Arrow_07_Left", 32.0, null, Color(1, 1, 1, 1)],
	"slider_arrow_right.png": ["SciFiMenus/SPR_SciFiMenus_Button_Arrow_07_Lights", "SciFiMenus/SPR_SciFiMenus_Button_Arrow_07_Right", 32.0, null, Color(1, 1, 1, 1)],
	"icon_restart.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Refresh_01_Clean", "", 48.0],
	"icon_home.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Planet_01_Clean", "", 48.0],
	"icon_ad.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Display_01_Clean", "", 48.0],
	"icon_sound.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Sound_On_01_Clean", "", 48.0],
	"icon_music.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Music_On_01_Clean", "", 48.0],
	"icon_bolt.png": ["Icons_Menu/ICON_SciFiMenus_Menu_LightningBolt_01_Clean", "", 48.0, Color(1.0, 0.72, 0.22)],
	"icon_star.png": ["Icons_Menu/ICON_SciFiMenus_Menu_Star_01_Clean", "", 64.0, Color(1.0, 0.82, 0.25)],
}
## Frames cut down to a nine-patch: out file -> [corner, as a share of the
## frame's height; where along each edge the plain stretch is sampled].
## Large_08 carries a tab in the middle of its top and bottom edges, which a
## nine-patch would smear into a bar as long as the panel. So the baked
## texture is only the four corners joined by a short plain piece of each
## edge (and of the face), and the stretch never meets a tab.
const NINE := {
	"popup_panel.png": [0.13, 0.27],
}
## Pieces closed at both ends: this share of the width, taken from the right end
## (Frame_Box_Small_08's screwed steel block, which starts 147 px into the 222
## px bar), is mirrored over the left, whose own edge is a 1-2 px line meant to
## sit under an icon cell. Then both blocks are squeezed sideways to the second
## value: at full width the two left the caption half the bar on a short button.
## Cut after the crop, before the shrink.
const MIRROR_RIGHT := {
	"popup_bar.png": [0.37, 0.6],
	"popup_bar_primary.png": [0.37, 0.6],
}
## Pieces whose frame sprite is mirrored before it is laid over the background.
const FLIP_FRAME := ["slider_arrow_right.png"]
## A few pixels of plain edge between the corners, in source pixels.
const NINE_STRIP := 16
## Copied as they are into assets/synty_ui/fonts/.
const FONTS := ["Fonts/Zen_Dots/ZenDots-Regular.ttf", "Fonts/Zen_Dots/OFL.txt"]
## The pause sign drawn onto pause.png: two bars, as fractions of the canvas.
const PAUSE_BAR := Vector2(0.11, 0.38)     # width, height
const PAUSE_GAP := 0.10                    # between the bars
const PAUSE_COLOR := Color(0.93, 0.96, 1.0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <SourceFiles dir>")
		quit(1)
		return
	var src: String = args[0].path_join("Sprites")
	# Further arguments name the pieces to bake, so trying one piece does not
	# wait on all of them; the fonts are copied only by a full build.
	var only: Array = args.slice(1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for out_name: String in PIECES:
		if not only.is_empty() and not only.has(out_name):
			continue
		var p: Array = PIECES[out_name]
		var img := _load(src, p[0])
		if img == null:
			quit(1)
			return
		if FLIP_FRAME.has(out_name):
			img.flip_x()
		if p[1] != "":
			var back := _load(src, p[1])
			if back == null:
				quit(1)
				return
			if p.size() > 5:
				_tint_vertical(back, p[4], p[5])
			else:
				_tint(back, p[4] if p.size() > 4 else BACK_TINT)
			back.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
			img = back
		if p.size() > 3 and p[3] != null:
			_tint(img, p[3])
		if out_name == "pause.png":
			_draw_pause(img)
		# Synty's canvases carry wide transparent margins — the bar frames
		# fill under half of their 2048x512 — so the frame is cropped to its
		# ink before it is sized, or it would draw at half the slot's height.
		var used := _ink_rect(img)
		if used.size.x > 0 and used.size.y > 0:
			img = img.get_region(used)
		if MIRROR_RIGHT.has(out_name):
			img = _close_both_ends(img, float(MIRROR_RIGHT[out_name][0]), float(MIRROR_RIGHT[out_name][1]))
		var h: int = int(round(float(p[2]) * BAKE))
		var w: int = int(round(img.get_width() * float(h) / img.get_height()))
		if NINE.has(out_name):
			# Scaled as if the whole frame were drawn p[2] tall, so the
			# corners come out at the size they would have had.
			var k: float = float(h) / img.get_height()
			var c: int = int(round(img.get_height() * float(NINE[out_name][0])))
			img = _nine_cut(img, c, float(NINE[out_name][1]))
			w = int(round(img.get_width() * k))
			h = int(round(img.get_height() * k))
			print("  %-16s corner %d px" % [out_name, int(round(c * k))])
		_shrink(img, w, h)
		img.save_png(ProjectSettings.globalize_path(OUT + out_name))
		print("  %-16s %4dx%-4d from %s" % [out_name, w, h, p[0].get_file()])
	# The title's face. Zen Dots is SIL OFL, so it could be committed, but it
	# travels with the rest of the kit; its licence goes with it.
	if not only.is_empty():
		print("wrote ", OUT)
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "fonts/"))
	for f in FONTS:
		var from: String = args[0].path_join(f)
		var to: String = ProjectSettings.globalize_path(OUT + "fonts/" + f.get_file())
		if DirAccess.copy_absolute(from, to) != OK:
			push_error("missing %s" % from)
			quit(1)
			return
		print("  %s" % f.get_file())
	print("wrote ", OUT)
	quit()


## Bounds of the pixels at least INK_ALPHA opaque. get_used_rect() keeps every
## pixel above zero, and these canvases carry a faint haze well past the frame.
const INK_ALPHA := 0.25
func _ink_rect(img: Image) -> Rect2i:
	var lo := Vector2i(img.get_width(), img.get_height())
	var hi := Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= INK_ALPHA:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE) if hi.x >= 0 else Rect2i()


func _load(src: String, name: String) -> Image:
	var path := src.path_join(name + ".png")
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("missing %s" % path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _tint(img: Image, tint: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a * tint.a))


## Like _tint, but blended from `top` to `bottom` down the sprite's ink, so
## the gradient spans the face and not the transparent margin around it.
func _tint_vertical(img: Image, top: Color, bottom: Color) -> void:
	var ink := _ink_rect(img)
	for y in img.get_height():
		var t: float = clampf(float(y - ink.position.y) / maxf(1.0, ink.size.y - 1), 0.0, 1.0)
		var tint: Color = top.lerp(bottom, t)
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(1.0, c.r * tint.r), minf(1.0, c.g * tint.g), minf(1.0, c.b * tint.b), c.a * tint.a))


## `img` with its right end (`share` of the width) mirrored over the left, and
## both ends squeezed sideways to `squeeze` of their width.
func _close_both_ends(img: Image, share: float, squeeze: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var cw: int = int(round(w * share))
	var right := img.get_region(Rect2i(w - cw, 0, cw, h))
	var mid := img.get_region(Rect2i(cw, 0, w - cw * 2, h))
	var cw2: int = int(round(cw * squeeze))
	right.premultiply_alpha()
	right.resize(cw2, h, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(right)
	var left := right.duplicate()
	left.flip_x()
	var out := Image.create(cw2 * 2 + mid.get_width(), h, false, Image.FORMAT_RGBA8)
	out.blit_rect(left, Rect2i(0, 0, cw2, h), Vector2i(0, 0))
	out.blit_rect(mid, Rect2i(Vector2i.ZERO, mid.get_size()), Vector2i(cw2, 0))
	out.blit_rect(right, Rect2i(0, 0, cw2, h), Vector2i(cw2 + mid.get_width(), 0))
	return out


func _unpremultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))


## The four c x c corners of `img` joined by NINE_STRIP pixels of each edge
## and of the face, taken `at` of the way along: a nine-patch with the same
## corners and a plain stretch.
func _nine_cut(img: Image, c: int, at: float) -> Image:
	var s := NINE_STRIP
	var w := img.get_width()
	var h := img.get_height()
	var px := int(w * at)
	var py := int(h * at)
	var out := Image.create(c * 2 + s, c * 2 + s, false, Image.FORMAT_RGBA8)
	var o := c + s
	out.blit_rect(img, Rect2i(0, 0, c, c), Vector2i(0, 0))
	out.blit_rect(img, Rect2i(w - c, 0, c, c), Vector2i(o, 0))
	out.blit_rect(img, Rect2i(0, h - c, c, c), Vector2i(0, o))
	out.blit_rect(img, Rect2i(w - c, h - c, c, c), Vector2i(o, o))
	out.blit_rect(img, Rect2i(px, 0, s, c), Vector2i(c, 0))
	out.blit_rect(img, Rect2i(px, h - c, s, c), Vector2i(c, o))
	out.blit_rect(img, Rect2i(0, py, c, s), Vector2i(0, c))
	out.blit_rect(img, Rect2i(w - c, py, c, s), Vector2i(o, c))
	out.blit_rect(img, Rect2i(px, py, s, s), Vector2i(c, c))
	return out


func _draw_pause(img: Image) -> void:
	var s := Vector2(img.get_size())
	var bar := Vector2i(s * PAUSE_BAR)
	var top := int((s.y - bar.y) * 0.5)
	var gap := int(s.x * PAUSE_GAP)
	var left := int((s.x - bar.x * 2 - gap) * 0.5)
	img.fill_rect(Rect2i(left, top, bar.x, bar.y), PAUSE_COLOR)
	img.fill_rect(Rect2i(left + bar.x + gap, top, bar.x, bar.y), PAUSE_COLOR)


func _shrink(img: Image, w: int, h: int) -> void:
	img.premultiply_alpha()
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
