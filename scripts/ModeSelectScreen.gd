extends Control

## Main menu / mode picker.
##
## Everything here is placeholder blocking-out: grey boxes where art will go,
## each labelled with what it is meant to become. Only the mode cards and
## START do anything; the rest log "[미구현]" so a tap is visibly registered
## without pretending to work.
##
## Built in code rather than as scene nodes on purpose. The layout is still
## being decided (see CardLayout — the cards read as one row or a 2x2 grid),
## and containers re-flow it for free, which matters because this project's
## viewport is a fixed 480 wide but a height that varies with the device
## (854 on 16:9, up to ~1066 on 20:9 — see window/stretch/aspect = "expand").

signal start_pressed(mode: int)

# Mirrors Main.gd's Mode enum; DREAM is the hidden fourth slot.
const MODE_SKY := 0
const MODE_JUNGLE := 1
const MODE_OCEAN := 2
const MODE_HIDDEN := 3

enum CardLayout { ROW, GRID }

## GRID (2x2) is the shipping layout — ROW fits all four on one line, but at
## 107px each the labels crowd and there is no room for the character art.
@export var card_layout: CardLayout = CardLayout.GRID

const FONT_PATH := "res://assets/fonts/Fredoka.ttf"

const CARDS := [
	{
		"mode": MODE_SKY,
		"title": "SKY",
		"quiz": "국기",
		"desc": "Read the country name, fly through the matching gate!",
		"locked": false,
	},
	{
		"mode": MODE_JUNGLE,
		"title": "JUNGLE",
		"quiz": "연산",
		"desc": "Solve the equation, fly through the correct gate!",
		"locked": false,
	},
	{
		"mode": MODE_OCEAN,
		"title": "OCEAN",
		"quiz": "스트룹",
		"desc": "Find the matching color, swim through the gate!",
		"locked": false,
	},
	{
		"mode": MODE_HIDDEN,
		"title": "?",
		"quiz": "???",
		"desc": "Clear all 3 modes to unlock a hidden mode!",
		"locked": true,
	},
]

const COLOR_PLACEHOLDER := Color(0.62, 0.63, 0.66, 1.0)
const COLOR_PLACEHOLDER_DARK := Color(0.48, 0.49, 0.53, 1.0)
const COLOR_CARD_BG := Color(0.72, 0.73, 0.76, 1.0)
const COLOR_CARD_LOCKED := Color(0.55, 0.56, 0.60, 1.0)
const COLOR_SELECT_BORDER := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_START := Color(0.20, 0.62, 0.30, 1.0)
const COLOR_START_DISABLED := Color(0.50, 0.51, 0.54, 1.0)
const COLOR_LABEL := Color(0.13, 0.14, 0.17, 1.0)
const COLOR_LABEL_DIM := Color(0.32, 0.33, 0.37, 1.0)

var selected_index: int = 0

var _font: Font
var _card_buttons: Array[Button] = []
var _desc_label: Label
var _start_button: Button


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_build()
	_select(0)


# ---------------------------------------------------------------- building

func _build() -> void:
	for child in get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_build_top_bar())
	column.add_child(_make_label("QuizRun: Dual Gate", 30, COLOR_LABEL, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_build_cards())

	_desc_label = _make_label("", 14, COLOR_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(0, 42)
	column.add_child(_desc_label)

	# Pushes the action buttons to the bottom of whatever height the device
	# gives us, instead of letting them float mid-screen on a tall phone.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var leaderboard := _make_button("LEADERBOARD  (미구현)", 15, COLOR_PLACEHOLDER_DARK, 40)
	leaderboard.pressed.connect(_on_unimplemented.bind("리더보드"))
	column.add_child(leaderboard)

	_start_button = _make_button("START", 26, COLOR_START, 64)
	_start_button.pressed.connect(_on_start_pressed)
	column.add_child(_start_button)

	var remove_ads := _make_button("Remove Ads", 12, Color(0, 0, 0, 0), 24)
	remove_ads.add_theme_color_override("font_color", COLOR_LABEL_DIM)
	remove_ads.pressed.connect(_on_unimplemented.bind("Remove Ads"))
	column.add_child(remove_ads)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 46)

	var profile := _make_button("👤\n로그인", 11, COLOR_PLACEHOLDER, 46)
	profile.custom_minimum_size = Vector2(58, 46)
	profile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	profile.pressed.connect(_on_unimplemented.bind("로그인/프로필"))
	bar.add_child(profile)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)

	var settings := _make_button("⚙\n설정", 11, COLOR_PLACEHOLDER, 46)
	settings.custom_minimum_size = Vector2(58, 46)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_END
	settings.pressed.connect(_on_unimplemented.bind("설정"))
	bar.add_child(settings)

	return bar


func _build_cards() -> Control:
	_card_buttons.clear()
	var holder: Control
	var card_height: int
	if card_layout == CardLayout.GRID:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		holder = grid
		card_height = 168
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		holder = row
		card_height = 150

	for i in range(CARDS.size()):
		var card := _make_card(i, card_height)
		holder.add_child(card)
		_card_buttons.append(card)
	return holder


func _make_card(index: int, card_height: int) -> Button:
	var data: Dictionary = CARDS[index]
	var locked: bool = data["locked"]

	var card := Button.new()
	card.custom_minimum_size = Vector2(0, card_height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.text = ""
	card.pressed.connect(_select.bind(index))
	_style_card(card, false, locked)

	# Contents are display-only; the Button underneath takes every click.
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.offset_top = 6
	inner.offset_bottom = -6
	inner.add_theme_constant_override("separation", 3)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)

	# Where the animated character will live once the art exists.
	var art := PanelContainer.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = COLOR_PLACEHOLDER_DARK if not locked else Color(0.42, 0.43, 0.47, 1.0)
	art_style.set_corner_radius_all(4)
	art.add_theme_stylebox_override("panel", art_style)
	var art_label := _make_label(
		"?" if locked else "캐릭터\n애니메이션\n자리",
		20 if locked else 9,
		Color(0.93, 0.94, 0.96, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)
	art_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(art_label)
	inner.add_child(art)

	inner.add_child(_make_label(data["title"], 14, COLOR_LABEL, HORIZONTAL_ALIGNMENT_CENTER))
	inner.add_child(_make_label(data["quiz"], 10, COLOR_LABEL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	if locked:
		inner.add_child(_make_label("🔒 LOCKED", 9, COLOR_LABEL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		inner.add_child(_make_label("BEST: 0", 10, COLOR_LABEL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _style_card(card: Button, selected: bool, locked: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_LOCKED if locked else COLOR_CARD_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(3 if selected else 1)
	style.border_color = COLOR_SELECT_BORDER if selected else Color(0.40, 0.41, 0.45, 1.0)
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, style)


# ---------------------------------------------------------------- helpers

func _make_label(text: String, size: int, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, size: int, bg: Color, height: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", size)
	if _font != null:
		button.add_theme_font_override("font", _font)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	return button


func _set_button_bg(button: Button, bg: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, style)


# ---------------------------------------------------------------- behaviour

func _select(index: int) -> void:
	selected_index = index
	for i in range(_card_buttons.size()):
		_style_card(_card_buttons[i], i == index, CARDS[i]["locked"])
	_desc_label.text = CARDS[index]["desc"]

	# The hidden slot stays locked as far as the player is concerned. Running
	# from the editor or a debug export is the one exception: the fourth mode
	# is still being built and needs a way in, so START stays live there and
	# says so. An exported release build can never reach it.
	var locked: bool = CARDS[index]["locked"]
	var debug_unlock: bool = locked and OS.is_debug_build()
	_start_button.disabled = locked and not debug_unlock
	_start_button.text = "START (DEBUG)" if debug_unlock else "START"
	_set_button_bg(_start_button, COLOR_START_DISABLED if _start_button.disabled else COLOR_START)


func _on_start_pressed() -> void:
	var data: Dictionary = CARDS[selected_index]
	if data["locked"] and not OS.is_debug_build():
		return
	start_pressed.emit(data["mode"])


func _on_unimplemented(what: String) -> void:
	print("[미구현] ", what)
