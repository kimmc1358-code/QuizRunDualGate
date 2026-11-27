extends Control
## The mode select — 2.0's main menu (2026-11-27).
##
## Built over the live space world (Main draws it underneath), from the
## Synty UI kit (tools/build_ui_kit.gd, gitignored; ArtSlot placeholders
## without it), in the same frames as the play-screen HUD so the menu and the
## game read as one set:
##
##   [login]      [stardust]      [settings]
##                WARP ✦ GATE
##   [           QUIZ RUN            ]   the main mode, large
##   [   BATTLE    ]  [    DAILY     ]
##   [  what the chosen mode is  ]
##   [             PLAY              ]
##   [hangar]   [upgrade]   [leaderboard]
##                Remove Ads
##
## There is no banner ad (dropped 2026-11-27), so nothing is reserved at the
## bottom.
##
## The modes and their rules are in CLAUDE.md ("Modes and meta progression").
## BATTLE and DAILY, the hangar and the upgrades are decided but not built,
## so they show locked and COMING SOON.
##
## Laid out in code because the viewport is 480 wide but its height follows
## the phone (854 at 16:9, ~1067 at 20:9): the blocks keep their sizes and the
## leftover height is shared between the gaps, so nothing drifts or spills.

signal start_pressed(mode: int)
signal login_pressed
signal settings_pressed
# 고른 카드의 모드를 실어 보낸다 — 어느 순위표를 열지는 그 모드가 정한다.
signal leaderboard_pressed(mode: int)
signal remove_ads_pressed

# ---- the modes ----
const MODE_QUIZ := 0
const MODE_BATTLE := 1
const MODE_DAILY := 2
const CARD_MODES := [MODE_QUIZ, MODE_BATTLE, MODE_DAILY]
const CARD_NAMES := ["QUIZ RUN", "BATTLE", "DAILY"]
## Which modes can be played yet. A locked card can be chosen to read what
## it will be, but PLAY does nothing for it.
const CARD_READY := [true, false, false]
const CARD_EXPLAIN := [
	"Fly through the right gates to power up and earn stardust!",
	"Your upgraded ship against enemies and bosses. No quiz.",
	"One quiz run a day, the same for everyone. Bonus stardust!",
]
const COMING_SOON := "COMING SOON"
const EXPLAIN_FONT := 15.0
const EXPLAIN_FONT_MIN := 11.0
const PLAY_TEXT := "PLAY"
const STARDUST_TEXT := "STARDUST"
const BEST_TEXT := "BEST"
const HANGAR_TEXT := "Hangar"
const UPGRADE_TEXT := "Upgrade"
const LEADERBOARD_TEXT := "Leaderboard"
const REMOVE_ADS_TEXT := "Remove Ads"

# The BEST line on the cards.
const CARD_BEST_COLOR := Color(0.99, 0.80, 0.22, 1.0)
const CARD_BEST_OUTLINE := Color(0.06, 0.06, 0.09, 1.0)

# ---- art (the Synty UI kit) ----
const KIT := "res://assets/synty_ui/"
const CARD_FRAME_PATH := KIT + "card_frame.png"
const CARD_FRAME_MARGIN := 80.0          # baked px
# The selected card's face is lit from inside (2026-11-27) instead of a cyan
# ring around the card: the same frame baked with a see-through cyan face,
# then scanlines and a band of light sweeping down it. CARD_FACE_INSET is
# where the face sits in the baked frame (left, top, right, bottom, in its
# pixels), measured off card_frame.png; the lines stop there so they do not
# run over the metal.
const CARD_FRAME_ON_PATH := KIT + "card_frame_on.png"
const CARD_FACE_INSET := [40.0, 50.0, 36.0, 38.0]
const SCANLINE_STEP := 3.0               # px at 480 wide
const SCANLINE := Color(0.55, 0.95, 1.0, 0.07)
const SWEEP := Color(0.60, 0.97, 1.0, 0.16)
const SWEEP_H := 0.22                    # share of the face's height
const SWEEP_PERIOD := 2.6                # s, top to bottom
const BUTTON_FRAME_PATH := KIT + "side_slot.png"
const BUTTON_FRAME_MARGIN := 34.0
# The menu's own PLAY button and explain bar (2026-11-27): the question box
# and score bar they used to borrow made the menu read as the play screen.
const PLAY_FRAME_PATH := KIT + "play_button.png"
const PLAY_FRAME_CAP := 62.0             # baked px: the V-notched ends
const EXPLAIN_FRAME_PATH := KIT + "explain_bar.png"
const EXPLAIN_FRAME_CAP := 40.0
const PLAY_TEXT_COLOR := Color(1.0, 0.98, 0.92)
const PLAY_TEXT_RIM := Color(0.36, 0.12, 0.02)
# PLAY answers a press (2026-11-27). Held, the button sinks a little and its
# yellow face warms up; let go, the face flashes and a ghost of the frame
# swells off it. Nothing else on this screen is the way into a run, so it is
# the one button that gets a show. The run starts once the flash has peaked:
# emitting at once swapped the screen in the same frame and the effect was
# never seen. Both glows are drawn additively by _play_fx, so they light the
# art instead of painting a flat colour over it.
const PLAY_FACE_SRC := Rect2(87, 67, 233, 60)   # the yellow core in play_button.png, measured
const PLAY_FACE_GROW := 1.45             # the glow spills past the core onto the face's darker edge
const PLAY_HELD_SCALE := 0.95
const PLAY_HELD_GLOW := 0.45             # face glow while held, 0..1
const PLAY_GLOW_COLOR := Color(1.0, 0.78, 0.30)
const PLAY_LAUNCH_TIME := 0.28           # s from release to the run starting
const PLAY_GHOST_GROW := 0.30            # the ghost frame ends this much larger
const PLAY_GHOST_COLOR := Color(1.0, 0.88, 0.55)   # paler than the glow: at the glow's orange the ghost read as a brown smudge on the dark sky
const PLAY_EASE_RATE := 18.0             # 1/s, how fast the held glow follows the finger
const BAR_FRAME_PATH := KIT + "score_bar.png"
const BAR_FRAME_CAP := 60.0
const PERSON_ICON := KIT + "icon_person.png"
const SETTINGS_ICON := KIT + "icon_settings.png"
const TROPHY_ICON := KIT + "icon_trophy.png"
const UPGRADE_ICON := KIT + "icon_upgrade.png"
const HANGAR_ICON := KIT + "icon_hangar.png"
const LOCK_ICON := KIT + "icon_lock.png"
const STARDUST_ICON := KIT + "icon_stardust.png"
const BEST_ICON := KIT + "best_icon.png"

# ---- layout, in px at 480 wide ----
const MARGIN := 14.0                     # screen edge -> content
const TOP_PAD := 12.0
const BOTTOM_PAD := 8.0
const TOP_BAR_H := 52.0
const EMBLEM_H := 100.0                  # star height; the words fit beside it
const EMBLEM_WREATH_H := 66.0
const EMBLEM_WORD_MAX := 42             # 36 until 2026-11-27; the owner asked for a little larger
const BIG_CARD_H := 150.0
const SMALL_CARD_H := 112.0
const CARD_GAP := 10.0                   # between the cards, both ways
const EXPLAIN_H := 46.0
const PLAY_W := 320.0
const PLAY_H := 86.0                    # 66 until 2026-11-27: it read as squat
const TOOL_SIZE := 64.0
const TOOL_LABEL_H := 18.0
const TOOL_SPACING := 110.0              # centre to centre
const REMOVE_ADS_H := 26.0
const STARDUST_W := 170.0
const STARDUST_H := 40.0
## The gaps that take the leftover height, and their bounds.
const FLEX_GAPS := 5
const MIN_GAP := 8.0
const MAX_GAP := 60.0

# ---- look ----
const DIM := Color(0.01, 0.05, 0.16, 0.42)
const NAME_COLOR := Color(0.88, 0.97, 1.0)
const NAME_RIM := Color(0.20, 0.55, 0.95)
const TEXT_COLOR := Color(0.90, 0.95, 1.0)
const SUB_TEXT := Color(0.70, 0.80, 0.95)
const STARDUST_COLOR := Color(0.55, 0.92, 1.0)
const LOCK_VEIL := Color(0.02, 0.04, 0.10, 0.62)
const LOCK_TEXT := Color(0.75, 0.82, 0.95)
const REMOVE_ADS_COLOR := Color(1.0, 1.0, 1.0, 0.85)

# ---- sound ----
const SFX_DIR := "res://assets/audio/"
const SFX_SELECT_FILE := "modeselection.wav"
const SFX_START_FILE := "start_main.wav"
const SFX_CREAM_FILE := "button_cream.wav"

var selected_index := 0
var _ads_removed := false
var _stardust := 0
var _best := PackedInt32Array()
var _built := false

var _font: Font            # body text (the game's own face)
var _title_font: Font      # names and PLAY (Zen Dots, from the kit)
var _sfx_select: AudioStreamPlayer
var _sfx_start: AudioStreamPlayer
var _sfx_cream: AudioStreamPlayer

# Rects from _layout, read by _draw.
var _r := {}
var _cards: Array[Button] = []
var _login: Button
var _setting: Button
var _play: Button
var _hangar: Button
var _upgrade: Button
var _leaderboard: Button
var _remove_ads: Button
var _explain_label: Label
var _play_fx: Control      # additive layer for PLAY's glow and ghost
var _play_held := 0.0      # 0..1, eased toward "is the finger on PLAY"
var _launch_t := -1.0      # s since PLAY was released; < 0 when idle
var _glow_tex: GradientTexture2D


# 조립은 로고가 뜬 뒤에 Main 이 ensure_built() 로 켠다. 두 번 불러도 한 번만.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_ready()


## 처음부터 다시 짓는다 — 언어가 바뀌었을 때 Main 이 부른다.
func rebuild() -> void:
	if not _built:
		return
	_build()
	_select(selected_index)
	_layout()


func _ready() -> void:
	if not _built:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = AppFont.base()
	_title_font = TitleArt.font(_font)
	for p in [CARD_FRAME_PATH, CARD_FRAME_ON_PATH, BUTTON_FRAME_PATH, PLAY_FRAME_PATH, EXPLAIN_FRAME_PATH, BAR_FRAME_PATH, PERSON_ICON, SETTINGS_ICON,
			TROPHY_ICON, UPGRADE_ICON, HANGAR_ICON, LOCK_ICON, STARDUST_ICON, BEST_ICON,
			TitleArt.STAR_PATH, TitleArt.WREATH_PATH]:
		ArtSlot.texture(p)
	_sfx_select = _make_sfx(SFX_SELECT_FILE)
	_sfx_start = _make_sfx(SFX_START_FILE)
	_sfx_cream = _make_sfx(SFX_CREAM_FILE)
	_build()
	_select(0)
	_layout()


# The sweep and PLAY's press are what move on this screen; redrawn while it is up.
func _process(delta: float) -> void:
	if not _built or not is_visible_in_tree():
		return
	if _play != null:
		var target := 1.0 if _play.get_draw_mode() == BaseButton.DRAW_PRESSED else 0.0
		_play_held = lerpf(_play_held, target, 1.0 - exp(-PLAY_EASE_RATE * delta))
	if _launch_t >= 0.0:
		_launch_t += delta
		if _launch_t >= PLAY_LAUNCH_TIME:
			_launch_t = -1.0
			_play_held = 0.0
			start_pressed.emit(CARD_MODES[selected_index])
	queue_redraw()
	if _play_fx != null:
		_play_fx.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


# ---------------------------------------------------------------- build

func _build() -> void:
	for child in get_children():
		if not child is AudioStreamPlayer:
			child.queue_free()
	_cards.clear()
	_explain_label = null
	for i in CARD_MODES.size():
		var b := _hit_button()
		b.pressed.connect(_on_card_pressed.bind(i))
		_cards.append(b)
	_login = _hit_button()
	_login.pressed.connect(func(): _play_sfx(_sfx_cream); login_pressed.emit())
	_setting = _hit_button()
	_setting.pressed.connect(func(): _play_sfx(_sfx_cream); settings_pressed.emit())
	_play = _hit_button()
	_play.pressed.connect(_on_start_pressed)
	_hangar = _hit_button()
	_hangar.pressed.connect(_on_coming_soon)
	_upgrade = _hit_button()
	_upgrade.pressed.connect(_on_coming_soon)
	_leaderboard = _hit_button()
	_leaderboard.pressed.connect(func(): _play_sfx(_sfx_cream); leaderboard_pressed.emit(CARD_MODES[selected_index]))
	_remove_ads = _hit_button()
	_remove_ads.text = tr(REMOVE_ADS_TEXT)
	_remove_ads.add_theme_font_override("font", _font)
	_remove_ads.add_theme_color_override("font_color", REMOVE_ADS_COLOR)
	_remove_ads.add_theme_color_override("font_pressed_color", REMOVE_ADS_COLOR)
	_remove_ads.add_theme_color_override("font_hover_color", REMOVE_ADS_COLOR)
	_remove_ads.visible = not _ads_removed
	_remove_ads.pressed.connect(func(): _play_sfx(_sfx_cream); remove_ads_pressed.emit())
	_play_fx = Control.new()
	_play_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_play_fx.material = add
	_play_fx.draw.connect(_draw_play_fx)
	add_child(_play_fx)
	_launch_t = -1.0
	_explain_label = Label.new()
	_explain_label.add_theme_font_override("font", _font)
	_explain_label.add_theme_color_override("font_color", TEXT_COLOR)
	_explain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain_label.max_lines_visible = 2
	_explain_label.clip_text = true
	_explain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_explain_label)


## A transparent button: the art is drawn by _draw, the button only takes the tap.
func _hit_button() -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(slot, empty)
	add_child(b)
	return b


# ---------------------------------------------------------------- layout

func _layout() -> void:
	if not _built or _play == null:
		return
	var w: float = size.x
	var h: float = size.y
	var k: float = w / 480.0
	var fixed: float = (TOP_PAD + BOTTOM_PAD + TOP_BAR_H + EMBLEM_H + BIG_CARD_H + CARD_GAP
		+ SMALL_CARD_H + CARD_GAP + EXPLAIN_H + PLAY_H + TOOL_SIZE + TOOL_LABEL_H + REMOVE_ADS_H) * k
	var gap: float = clampf((h - fixed) / FLEX_GAPS, MIN_GAP * k, MAX_GAP * k)

	var y: float = TOP_PAD * k
	var m: float = MARGIN * k
	var inner_w: float = w - m * 2.0
	_r.login = Rect2(m, y, TOP_BAR_H * k, TOP_BAR_H * k)
	_r.setting = Rect2(w - m - TOP_BAR_H * k, y, TOP_BAR_H * k, TOP_BAR_H * k)
	_r.stardust = Rect2((w - STARDUST_W * k) * 0.5, y + (TOP_BAR_H - STARDUST_H) * 0.5 * k, STARDUST_W * k, STARDUST_H * k)
	y += TOP_BAR_H * k + gap
	_r.emblem_mid = Vector2(w * 0.5, y + EMBLEM_H * 0.5 * k)
	y += EMBLEM_H * k + gap
	_r.card0 = Rect2(m, y, inner_w, BIG_CARD_H * k)
	y += BIG_CARD_H * k + CARD_GAP * k
	var half_w: float = (inner_w - CARD_GAP * k) * 0.5
	_r.card1 = Rect2(m, y, half_w, SMALL_CARD_H * k)
	_r.card2 = Rect2(m + half_w + CARD_GAP * k, y, half_w, SMALL_CARD_H * k)
	y += SMALL_CARD_H * k + CARD_GAP * k
	_r.explain = Rect2(m, y, inner_w, EXPLAIN_H * k)
	y += EXPLAIN_H * k + gap
	_r.play = Rect2((w - PLAY_W * k) * 0.5, y, PLAY_W * k, PLAY_H * k)
	y += PLAY_H * k + gap
	for i in 3:
		var cx: float = w * 0.5 + (i - 1) * TOOL_SPACING * k
		_r["tool%d" % i] = Rect2(cx - TOOL_SIZE * 0.5 * k, y, TOOL_SIZE * k, TOOL_SIZE * k)
	y += (TOOL_SIZE + TOOL_LABEL_H) * k + gap
	_r.remove_ads = Rect2(m, y, inner_w, REMOVE_ADS_H * k)

	for i in _cards.size():
		_place(_cards[i], _r["card%d" % i])
	_place(_login, _r.login)
	_place(_setting, _r.setting)
	_place(_play, _r.play)
	_place(_hangar, _r.tool0)
	_place(_upgrade, _r.tool1)
	_place(_leaderboard, _r.tool2)
	_place(_remove_ads, _r.remove_ads)
	_remove_ads.add_theme_font_size_override("font_size", int(16 * k))
	# Font size before size: an autowrapped Label measured at its first, zero
	# width wraps every word onto its own line and keeps that height (it came
	# out 597px tall and centred its text far below the bar).
	_explain_label.add_theme_font_size_override("font_size", int(EXPLAIN_FONT * k))
	_explain_label.position = _r.explain.position + Vector2(24.0, 4.0) * k
	_explain_label.size = _r.explain.size - Vector2(48.0, 8.0) * k
	_fit_explain()
	queue_redraw()


func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


## Every rect the layout produced, for the layout check.
func layout_rects() -> Dictionary:
	return _r.duplicate()


# ---------------------------------------------------------------- draw

func _draw() -> void:
	if _r.is_empty():
		return
	var k: float = size.x / 480.0
	draw_rect(Rect2(Vector2.ZERO, size), DIM)

	_draw_square_button(_r.login, PERSON_ICON, false)
	_draw_square_button(_r.setting, SETTINGS_ICON, false)
	_draw_bar(_r.stardust, BAR_FRAME_PATH, BAR_FRAME_CAP)
	var sd_icon := ArtSlot.texture(STARDUST_ICON)
	var ih: float = _r.stardust.size.y * 0.55
	var iw: float = ih * sd_icon.get_width() / sd_icon.get_height()
	draw_texture_rect(sd_icon, Rect2(_r.stardust.position + Vector2(20.0 * k, (_r.stardust.size.y - ih) * 0.5), Vector2(iw, ih)), false)
	_text_right(_font, ScoreFormat.compact(_stardust), Vector2(_r.stardust.end.x - 22.0 * k, _r.stardust.get_center().y), int(18 * k), STARDUST_COLOR)

	TitleArt.draw_emblem(self, _r.emblem_mid, EMBLEM_H * k, EMBLEM_WREATH_H * k,
		size.x, MARGIN * k, int(EMBLEM_WORD_MAX * k), _title_font, k * EMBLEM_WORD_MAX / 44.0)

	for i in CARD_MODES.size():
		_draw_card(i, _r["card%d" % i], k)

	_draw_bar(_r.explain, EXPLAIN_FRAME_PATH, EXPLAIN_FRAME_CAP)

	var ready: bool = CARD_READY[selected_index]
	var ps: float = _play_scale() if ready else 1.0
	var pc: Vector2 = _r.play.get_center()
	draw_set_transform(pc * (1.0 - ps), 0.0, Vector2(ps, ps))
	_draw_bar(_r.play, PLAY_FRAME_PATH, PLAY_FRAME_CAP, Color.WHITE if ready else Color(1, 1, 1, 0.45))
	_text_center(_title_font, tr(PLAY_TEXT) if ready else tr(COMING_SOON), pc,
		int((36 if ready else 22) * k), PLAY_TEXT_COLOR if ready else LOCK_TEXT, PLAY_TEXT_RIM if ready else NAME_RIM)
	draw_set_transform(Vector2.ZERO)

	var tools := [[_r.tool0, HANGAR_ICON, tr(HANGAR_TEXT), true], [_r.tool1, UPGRADE_ICON, tr(UPGRADE_TEXT), true],
		[_r.tool2, TROPHY_ICON, tr(LEADERBOARD_TEXT), false]]
	for t in tools:
		var rect: Rect2 = t[0]
		_draw_square_button(rect, t[1], t[3])
		_text_center(_font, t[2], Vector2(rect.get_center().x, rect.end.y + TOOL_LABEL_H * 0.6 * k),
			int(13 * k), SUB_TEXT, Color(0, 0, 0, 0))

	if _remove_ads.visible:
		var tw: float = _font.get_string_size(_remove_ads.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * k)).x
		var uy: float = _r.remove_ads.get_center().y + 10.0 * k
		draw_line(Vector2(_r.remove_ads.get_center().x - tw * 0.5, uy), Vector2(_r.remove_ads.get_center().x + tw * 0.5, uy), REMOVE_ADS_COLOR, 1.5)


func _draw_card(i: int, r: Rect2, k: float) -> void:
	var on := i == selected_index
	var tex := ArtSlot.texture(CARD_FRAME_ON_PATH if on else CARD_FRAME_PATH)
	_nine(tex, r, CARD_FRAME_MARGIN)
	if on:
		_draw_card_face(r, tex, k)
	var name: String = tr(CARD_NAMES[i])
	if i == MODE_QUIZ:
		# The main mode: its name large on the left, where stardust comes
		# from on the right, its record along the bottom.
		_text_left(_title_font, name, Vector2(r.position.x + 30.0 * k, r.position.y + 52.0 * k), int(30 * k), NAME_COLOR, NAME_RIM)
		var sd := ArtSlot.texture(STARDUST_ICON)
		var sh: float = 20.0 * k
		var sw: float = sh * sd.get_width() / sd.get_height()
		var tag_w: float = _font.get_string_size(tr(STARDUST_TEXT), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k)).x
		var tag_x: float = r.end.x - 30.0 * k - tag_w
		draw_texture_rect(sd, Rect2(tag_x - sw - 6.0 * k, r.position.y + 40.0 * k, sw, sh), false)
		_text_left(_font, tr(STARDUST_TEXT), Vector2(tag_x, r.position.y + 50.0 * k), int(14 * k), STARDUST_COLOR, Color(0, 0, 0, 0))
		var best := ArtSlot.texture(BEST_ICON)
		var by: float = r.end.y - 44.0 * k
		draw_texture_rect(best, Rect2(r.position.x + 30.0 * k, by - 12.0 * k, 24.0 * k, 24.0 * k), false)
		_text_left(_font, BEST_TEXT, Vector2(r.position.x + 62.0 * k, by), int(17 * k), CARD_BEST_COLOR, CARD_BEST_OUTLINE)
		var value: int = _best[MODE_QUIZ] if _best.size() > MODE_QUIZ else 0
		_text_left(_title_font, ScoreFormat.grouped(value) if value > 0 else "-", Vector2(r.position.x + 122.0 * k, by), int(22 * k), CARD_BEST_COLOR, CARD_BEST_OUTLINE)
	else:
		# Veil first, so the name of a mode still to come reads over it.
		# Not over the selected one, whose lit face would go dark under it;
		# its lock and COMING SOON still say it is closed.
		if not CARD_READY[i] and not on:
			draw_rect(r.grow(-12.0 * k), LOCK_VEIL)
		_text_center(_title_font, name, Vector2(r.get_center().x, r.position.y + 40.0 * k), int(20 * k), NAME_COLOR, NAME_RIM)
	if not CARD_READY[i]:
		var lock := ArtSlot.texture(LOCK_ICON)
		var lh: float = 26.0 * k
		var lw: float = lh * lock.get_width() / lock.get_height()
		draw_texture_rect(lock, Rect2(r.get_center().x - lw * 0.5, r.get_center().y - 2.0 * k, lw, lh), false, Color(1, 1, 1, 0.85))
		_text_center(_font, tr(COMING_SOON), Vector2(r.get_center().x, r.end.y - 22.0 * k), int(12 * k), LOCK_TEXT, Color(0, 0, 0, 0))


## Scanlines and the sweeping band over the selected card's face.
func _draw_card_face(r: Rect2, tex: Texture2D, k: float) -> void:
	var s: float = minf(r.size.y / tex.get_height(), r.size.x / tex.get_width() * 2.0)
	var face := Rect2(r.position + Vector2(CARD_FACE_INSET[0], CARD_FACE_INSET[1]) * s,
		r.size - Vector2(CARD_FACE_INSET[0] + CARD_FACE_INSET[2], CARD_FACE_INSET[1] + CARD_FACE_INSET[3]) * s)
	var y: float = face.position.y
	while y < face.end.y:
		draw_line(Vector2(face.position.x, y), Vector2(face.end.x, y), SCANLINE, 1.0)
		y += SCANLINE_STEP * k
	# The band enters above the face and leaves below it, clipped to it,
	# brightest in its middle.
	var t: float = fmod(Time.get_ticks_msec() / 1000.0, SWEEP_PERIOD) / SWEEP_PERIOD
	var bh: float = face.size.y * SWEEP_H
	var mid: float = face.position.y - bh + (face.size.y + bh * 2.0) * t
	var rows := 12
	for j in rows:
		var y0: float = mid - bh * 0.5 + bh * j / rows
		var y1: float = y0 + bh / rows
		var top: float = maxf(y0, face.position.y)
		var bottom: float = minf(y1, face.end.y)
		if bottom <= top:
			continue
		var a: float = 1.0 - absf((j + 0.5) / rows * 2.0 - 1.0)
		draw_rect(Rect2(face.position.x, top, face.size.x, bottom - top), Color(SWEEP, SWEEP.a * a))


func _draw_square_button(r: Rect2, icon_path: String, locked: bool) -> void:
	_nine(ArtSlot.texture(BUTTON_FRAME_PATH), r, BUTTON_FRAME_MARGIN)
	var icon := ArtSlot.texture(icon_path)
	var ih: float = r.size.y * 0.46
	var iw: float = ih * icon.get_width() / icon.get_height()
	if iw > r.size.x * 0.6:
		iw = r.size.x * 0.6
		ih = iw * icon.get_height() / icon.get_width()
	var tint := Color(1, 1, 1, 0.35) if locked else Color.WHITE
	draw_texture_rect(icon, Rect2(r.get_center() - Vector2(iw, ih) * 0.5, Vector2(iw, ih)), false, tint)
	if locked:
		var lock := ArtSlot.texture(LOCK_ICON)
		var lh: float = r.size.y * 0.30
		var lw: float = lh * lock.get_width() / lock.get_height()
		draw_texture_rect(lock, Rect2(r.end - Vector2(lw + r.size.x * 0.16, lh + r.size.y * 0.16), Vector2(lw, lh)), false)


## A frame stretched to `r` with its corners kept, `margin` in the texture's
## own pixels: drawn at the scale that maps the texture's height to r's, so
## a corner is the same share of the frame however big it is drawn.
func _nine(tex: Texture2D, r: Rect2, margin: float) -> void:
	var s: float = minf(r.size.y / tex.get_height(), r.size.x / tex.get_width() * 2.0)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	draw_set_transform(r.position, 0.0, Vector2(s, s))
	draw_style_box(sb, Rect2(Vector2.ZERO, r.size / s))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A bar with its ends kept whole and only the middle stretched — the same
## cut as Main._draw_horizontal_slice; `cap` is in the texture's pixels.
## PLAY's size: sunk while held, springing back past full size as it launches.
func _play_scale() -> float:
	var s: float = lerpf(1.0, PLAY_HELD_SCALE, _play_held)
	if _launch_t >= 0.0:
		var t: float = clampf(_launch_t / PLAY_LAUNCH_TIME, 0.0, 1.0)
		s = lerpf(PLAY_HELD_SCALE, 1.0, minf(1.0, t * 3.0)) + 0.04 * sin(PI * t)
	return s


## Where the yellow core of play_button.png lands inside a drawn PLAY rect. The
## art is three-sliced like _draw_bar does it, so x maps through the caps and
## the stretched middle separately.
func _play_face_rect(r: Rect2) -> Rect2:
	var tex := ArtSlot.texture(PLAY_FRAME_PATH)
	var tw: float = tex.get_width()
	var s: float = r.size.y / tex.get_height()
	var c: float = minf(PLAY_FRAME_CAP * s, r.size.x * 0.5)
	var mid: float = (r.size.x - c * 2.0) / maxf(1.0, tw - PLAY_FRAME_CAP * 2.0)
	var map_x := func(x: float) -> float:
		if x <= PLAY_FRAME_CAP:
			return x * c / PLAY_FRAME_CAP
		if x >= tw - PLAY_FRAME_CAP:
			return r.size.x - (tw - x) * c / PLAY_FRAME_CAP
		return c + (x - PLAY_FRAME_CAP) * mid
	var x0: float = map_x.call(PLAY_FACE_SRC.position.x)
	var x1: float = map_x.call(PLAY_FACE_SRC.end.x)
	return Rect2(r.position + Vector2(x0, PLAY_FACE_SRC.position.y * s),
		Vector2(x1 - x0, PLAY_FACE_SRC.size.y * s))


## The additive layer over PLAY: a warm glow on its face, and on launch a
## flash and a ghost of the frame swelling off it.
func _draw_play_fx() -> void:
	if _r.is_empty() or not CARD_READY[selected_index]:
		return
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_glow_tex.gradient = g
	var glow: float = PLAY_HELD_GLOW * _play_held
	var t := -1.0
	if _launch_t >= 0.0:
		t = clampf(_launch_t / PLAY_LAUNCH_TIME, 0.0, 1.0)
		# Up to full in the first fifth, then fading as the screen goes.
		glow = maxf(glow, minf(1.0, t * 5.0) * (1.0 - t * 0.6))
	var ps: float = _play_scale()
	var pc: Vector2 = _r.play.get_center()
	if glow > 0.0:
		var face := _play_face_rect(_r.play)
		var fc := face.get_center()
		var fs := face.size * PLAY_FACE_GROW * ps
		var col := PLAY_GLOW_COLOR * glow
		col.a = 1.0
		_play_fx.draw_texture_rect(_glow_tex, Rect2(pc + (fc - pc) * ps - fs * 0.5, fs), false, col)
	if t >= 0.0:
		var gs: float = 1.0 + PLAY_GHOST_GROW * t
		var a: float = 1.0 - t
		_play_fx.draw_set_transform(pc * (1.0 - gs), 0.0, Vector2(gs, gs))
		_draw_bar(_r.play, PLAY_FRAME_PATH, PLAY_FRAME_CAP, Color(PLAY_GHOST_COLOR.r * a, PLAY_GHOST_COLOR.g * a, PLAY_GHOST_COLOR.b * a, 1.0), _play_fx)
		_play_fx.draw_set_transform(Vector2.ZERO)


func _draw_bar(r: Rect2, path: String, cap: float, tint := Color.WHITE, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var tex := ArtSlot.texture(path)
	var s: float = r.size.y / tex.get_height()
	var c: float = minf(cap * s, r.size.x * 0.5)
	var tw: float = tex.get_width()
	var th: float = tex.get_height()
	ci.draw_texture_rect_region(tex, Rect2(r.position, Vector2(c, r.size.y)), Rect2(0, 0, cap, th), tint)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(r.end.x - c, r.position.y), Vector2(c, r.size.y)), Rect2(tw - cap, 0, cap, th), tint)
	if r.size.x > c * 2.0:
		ci.draw_texture_rect_region(tex, Rect2(Vector2(r.position.x + c, r.position.y), Vector2(r.size.x - c * 2.0, r.size.y)), Rect2(cap, 0, tw - cap * 2.0, th), tint)


func _text_left(f: Font, text: String, mid_left: Vector2, fs: int, col: Color, rim: Color) -> void:
	var pos := Vector2(mid_left.x, mid_left.y + fs * 0.36)
	if rim.a > 0.0:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 7), rim)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_right(f: Font, text: String, mid_right: Vector2, fs: int, col: Color) -> void:
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(mid_right.x - tw, mid_right.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_center(f: Font, text: String, centre: Vector2, fs: int, col: Color, rim: Color) -> void:
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text_left(f, text, Vector2(centre.x - tw * 0.5, centre.y), fs, col, rim)


# ---------------------------------------------------------------- input

func _on_card_pressed(index: int) -> void:
	_play_sfx(_sfx_select)
	_select(index)


func _select(index: int) -> void:
	selected_index = clampi(index, 0, CARD_MODES.size() - 1)
	if _explain_label != null:
		# No "(COMING SOON)" after a locked mode's line: the card and PLAY
		# already say it, and the suffix pushed BATTLE's line out of the bar.
		_explain_label.text = tr(CARD_EXPLAIN[selected_index])
		_fit_explain()
	queue_redraw()


## One line in the bar: the font steps down from EXPLAIN_FONT until the line
## fits, to EXPLAIN_FONT_MIN at the least. The bar has room for one line of
## 15px and not two, so a wrapped second line was simply cut off.
func _fit_explain() -> void:
	if _explain_label == null or _r.is_empty():
		return
	var k: float = size.x / 480.0
	var room: float = _r.explain.size.x - 48.0 * k
	var fs := int(EXPLAIN_FONT * k)
	while fs > int(EXPLAIN_FONT_MIN * k) and _font.get_string_size(_explain_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	_explain_label.add_theme_font_size_override("font_size", fs)


func _on_start_pressed() -> void:
	if not CARD_READY[selected_index]:
		_play_sfx(_sfx_select)
		return
	if _launch_t >= 0.0:
		return  # already launching; a second tap must not start two runs
	# The cue starts with the flash; _process hands the mode over once the
	# flash has peaked, because emitting swaps the screen.
	_play_sfx(_sfx_start)
	_launch_t = 0.0


func _on_coming_soon() -> void:
	_play_sfx(_sfx_select)
	if _explain_label != null:
		_explain_label.text = tr(COMING_SOON)


# ---------------------------------------------------------------- from Main

## Each mode's stored best, indexed by mode.
func set_best_scores(values: PackedInt32Array) -> void:
	_best = values
	queue_redraw()


## 광고 제거를 샀는가. 샀으면 아래의 "광고 제거" 줄을 숨긴다.
func set_ads_removed(removed: bool) -> void:
	_ads_removed = removed
	if _remove_ads != null:
		_remove_ads.visible = not removed
	queue_redraw()


## The stardust saved so far (Main.stardust_total), for the top bar.
func set_stardust(amount: int) -> void:
	_stardust = amount
	queue_redraw()


# ---------------------------------------------------------------- sound

func _make_sfx(file_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	var path: String = SFX_DIR + file_name
	if ResourceLoader.exists(path):
		player.stream = load(path)
	return player


func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()
