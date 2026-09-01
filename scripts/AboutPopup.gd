extends PopupBase

## About 팝업. 설정 팝업의 About 줄에서 연다.
##
## 다른 팝업과 달리 내용이 세로로 길어질 수 있어서, 판 안쪽을 통째로
## ScrollContainer 로 채우고 그 안에 VBoxContainer 로 쌓는다. 화면이 짧으면
## 스크롤되고, 넉넉하면 그냥 다 보인다.
##
## 줄 종류가 몇 가지라 각각 작은 Control 로 만들고 draw 에서 직접 그린다 —
## 라벨/값/점선 잇기처럼 Label 로는 표현이 번거로운 배치가 섞여 있어서다.

signal close_pressed

# 로고는 검은 배경용으로 그려져 있어(글자가 흰색) 크림색 판 위에 그냥 얹으면
# 사라진다. 그래서 어두운 받침을 깔고 그 위에 올린다 — 브랜드 블록처럼 읽힌다.
const LOGO_FILE := "res://assets/ui_assets/title/logo.png"
const LOGO_WIDTH_FRAC := 0.62          # 받침 폭 대비 로고 폭
const LOGO_PLATE_WIDTH_FRAC := 0.92    # 판 안쪽 폭 대비 받침 폭
const LOGO_PLATE_PAD := 0.22           # 로고 높이 대비 받침 위아래 여백
const LOGO_PLATE_COLOR := Color(0.055, 0.090, 0.160, 1.0)
const LOGO_PLATE_RADIUS := 14

const INTRO_TEXT := "JANIJU STUDIO is an independent husband-and-wife game studio, crafting casual mobile games with heart, one gate at a time."
const INTRO_SIZE_FRAC := 0.048         # 판 너비 대비
const INTRO_COLOR := Color(0.55, 0.55, 0.58, 1.0)

# 섹션 제목은 금색 밑줄로 강조한다.
const SECTION_SIZE_FRAC := 0.056
const SECTION_COLOR := Color(0.055, 0.180, 0.435, 1.0)
const SECTION_RULE_COLOR := Color(1.0, 0.78, 0.22, 1.0)
const SECTION_RULE_PX := 3.0
const SECTION_RULE_DROP := 0.34        # 글자 크기 대비 베이스라인 아래로

# TEAM: 작은 회색 라벨 위, 굵은 네이비 이름 아래.
const TEAM := [
	["Game Design & Direction", "Min Cheol Kim"],
	["Concept & Art Direction", "Sol Ji Kang"],
	["Development Support", "Claude Code"],
]
const TEAM_LABEL_SIZE_FRAC := 0.040
const TEAM_LABEL_COLOR := Color(0.58, 0.58, 0.62, 1.0)
const TEAM_NAME_SIZE_FRAC := 0.058
const TEAM_NAME_COLOR := Color(0.055, 0.180, 0.435, 1.0)

# MADE WITH: 왼쪽 회색 라벨 ...점선... 오른쪽 네이비 값.
const MADE_WITH := [
	["Game Engine", "Godot Engine"],
	["Art & Image Generation", "PixelLab, Ludo.ai"],
	["Image Editing", "Photopea"],
	["Typography", "Fredoka"],
	["Music", "Suno, Audjust"],
	["Sound Effects", "ElevenLabs"],
]
const ENTRY_SIZE_FRAC := 0.044
const ENTRY_LABEL_COLOR := Color(0.58, 0.58, 0.62, 1.0)
const ENTRY_VALUE_COLOR := Color(0.055, 0.180, 0.435, 1.0)
const ENTRY_LEADER_COLOR := Color(0.80, 0.75, 0.63, 1.0)
const ENTRY_LEADER_DOT := 1.3          # 점 반지름
const ENTRY_LEADER_STEP := 7.0         # 점 사이 간격
const ENTRY_LEADER_PAD := 8.0          # 글자와 점선 사이
const ENTRY_MIN_SIZE := 10             # 라벨과 값이 한 줄에 안 들어가면 여기까지 줄인다

const FOOTER_LINES := ["Thank you for playing!", "© 2026 JANIJU STUDIO"]
const FOOTER_SIZE_FRAC := 0.042
const FOOTER_COLOR := Color(0.58, 0.58, 0.62, 1.0)

# 세로 여백들 — 모두 판 높이 대비.
const PAD_AFTER_LOGO := 0.028
const PAD_AFTER_INTRO := 0.040
const PAD_AFTER_SECTION := 0.018
const PAD_BETWEEN_ROWS := 0.014
const PAD_AROUND_DIVIDER := 0.030
const PAD_BEFORE_FOOTER := 0.030

var _cancel: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _logo_texture: Texture2D
var _logo_plate: StyleBoxFlat
var _rows: Array[Control] = []      # 폭이 바뀔 때 다시 재야 하는 것들


func panel_size_frac() -> Vector2:
	return Vector2(0.90, 0.78)


func panel_texture_width() -> int:
	return 450


func panel_center_y_frac() -> float:
	return 0.52


func _build_content() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	add_child(_scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	_scroll.add_child(_body)

	if ResourceLoader.exists(LOGO_FILE):
		_logo_texture = load(LOGO_FILE)
	_add_row("logo", [])
	_spacer(PAD_AFTER_LOGO)

	_add_row("intro", [])
	_spacer(PAD_AFTER_INTRO)

	_add_row("section", ["TEAM"])
	_spacer(PAD_AFTER_SECTION)
	for pair in TEAM:
		_add_row("team", pair)
		_spacer(PAD_BETWEEN_ROWS)

	_spacer(PAD_AROUND_DIVIDER)
	_add_row("divider", [])
	_spacer(PAD_AROUND_DIVIDER)

	_add_row("section", ["MADE WITH"])
	_spacer(PAD_AFTER_SECTION)
	for pair in MADE_WITH:
		_add_row("entry", pair)
		_spacer(PAD_BETWEEN_ROWS)

	_spacer(PAD_AROUND_DIVIDER)
	_add_row("divider", [])
	_spacer(PAD_BEFORE_FOOTER)

	for line in FOOTER_LINES:
		_add_row("footer", [line])
		_spacer(PAD_BETWEEN_ROWS)

	_cancel = _make_close_button(func(): close_pressed.emit())


# 한 줄을 만들어 VBox 에 붙인다. 종류와 내용은 메타로 들고 다니고, 그리기는
# _draw_row 하나가 종류를 보고 나눠 맡는다.
func _add_row(kind: String, data: Array) -> void:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("kind", kind)
	row.set_meta("data", data)
	row.draw.connect(_draw_row.bind(row))
	_body.add_child(row)
	_rows.append(row)


func _spacer(frac: float) -> void:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_meta("pad", frac)
	_body.add_child(s)
	_rows.append(s)


func _layout_content(inner: Rect2) -> void:
	_scroll.position = inner.position
	_scroll.size = inner.size
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var w: float = inner.size.x
	# 세로 스크롤 막대가 뜨면 그만큼 좁아지므로, 글자를 그 폭으로 잰다.
	_body.custom_minimum_size.x = w

	_place_close_button(_cancel)

	for row in _rows:
		if row.has_meta("pad"):
			row.custom_minimum_size = Vector2(w, ph * float(row.get_meta("pad")))
			continue
		row.custom_minimum_size = Vector2(w, _row_height(row, pw, w))
		row.queue_redraw()


# 줄 높이. 소개글만 여러 줄로 접히므로 실제로 재고, 나머지는 글자 크기에서 나온다.
func _row_height(row: Control, pw: float, w: float) -> float:
	match str(row.get_meta("kind")):
		"intro":
			var size: int = int(round(pw * INTRO_SIZE_FRAC))
			var h: float = _font_bold.get_multiline_string_size(
				INTRO_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w, size).y
			return h + size * 0.5
		"logo":
			if _logo_texture == null:
				return 0.0
			var lw: float = w * LOGO_PLATE_WIDTH_FRAC * LOGO_WIDTH_FRAC
			var lh: float = lw * float(_logo_texture.get_height()) / float(_logo_texture.get_width())
			return lh * (1.0 + LOGO_PLATE_PAD * 2.0)
		"section":
			return pw * SECTION_SIZE_FRAC * 1.9
		"team":
			return pw * (TEAM_LABEL_SIZE_FRAC + TEAM_NAME_SIZE_FRAC) * 1.45
		"entry":
			return pw * ENTRY_SIZE_FRAC * 1.7
		"divider":
			return DIVIDER_DOT_RADIUS * 2.0
		_:
			return pw * FOOTER_SIZE_FRAC * 1.5


func _draw_row(row: Control) -> void:
	var pw: float = _panel_rect.size.x
	var w: float = row.size.x
	var data: Array = row.get_meta("data", [])
	match str(row.get_meta("kind")):
		"logo":
			if _logo_texture == null:
				return
			if _logo_plate == null:
				_logo_plate = StyleBoxFlat.new()
				_logo_plate.bg_color = LOGO_PLATE_COLOR
				_logo_plate.set_corner_radius_all(LOGO_PLATE_RADIUS)
				_logo_plate.anti_aliasing = true
			var plate_w: float = w * LOGO_PLATE_WIDTH_FRAC
			row.draw_style_box(_logo_plate,
				Rect2((w - plate_w) * 0.5, 0.0, plate_w, row.size.y))
			var lw: float = plate_w * LOGO_WIDTH_FRAC
			var lh: float = lw * float(_logo_texture.get_height()) / float(_logo_texture.get_width())
			row.draw_texture_rect(_logo_texture,
				Rect2((w - lw) * 0.5, (row.size.y - lh) * 0.5, lw, lh), false)
		"intro":
			var size: int = int(round(pw * INTRO_SIZE_FRAC))
			row.draw_multiline_string(_font_bold, Vector2(0.0, size),
				INTRO_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w, size, -1, INTRO_COLOR)
		"section":
			var size: int = int(round(pw * SECTION_SIZE_FRAC))
			var text: String = data[0]
			var baseline: float = size
			row.draw_string(_font_heavy, Vector2(0.0, baseline), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, SECTION_COLOR)
			var tw: float = _font_heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var ry: float = baseline + size * SECTION_RULE_DROP
			row.draw_line(Vector2(0.0, ry), Vector2(tw, ry),
				SECTION_RULE_COLOR, SECTION_RULE_PX, true)
		"team":
			var lsize: int = int(round(pw * TEAM_LABEL_SIZE_FRAC))
			var nsize: int = int(round(pw * TEAM_NAME_SIZE_FRAC))
			row.draw_string(_font_bold, Vector2(0.0, lsize), data[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsize, TEAM_LABEL_COLOR)
			row.draw_string(_font_heavy, Vector2(0.0, lsize * 1.45 + nsize), data[1],
				HORIZONTAL_ALIGNMENT_LEFT, -1, nsize, TEAM_NAME_COLOR)
		"entry":
			# 라벨과 값이 한 줄에 안 들어가면 줄인다 — "Art & Image Generation"
			# 처럼 긴 라벨이 값과 겹치는 것을 막는다.
			var size: int = int(round(pw * ENTRY_SIZE_FRAC))
			while size > ENTRY_MIN_SIZE and \
					_font_bold.get_string_size(data[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
					+ _font_heavy.get_string_size(data[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
					+ ENTRY_LEADER_PAD * 2.0 + ENTRY_LEADER_STEP * 3.0 > w:
				size -= 1
			var baseline: float = row.size.y * 0.5 + size * 0.36
			row.draw_string(_font_bold, Vector2(0.0, baseline), data[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, ENTRY_LABEL_COLOR)
			var vw: float = _font_heavy.get_string_size(data[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			row.draw_string(_font_heavy, Vector2(w - vw, baseline), data[1],
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, ENTRY_VALUE_COLOR)
			# 라벨 끝에서 값 시작까지 점선으로 잇는다.
			var lw: float = _font_bold.get_string_size(data[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var from: float = lw + ENTRY_LEADER_PAD
			var to: float = w - vw - ENTRY_LEADER_PAD
			var dy: float = baseline - size * 0.18
			var x: float = from
			while x < to:
				row.draw_circle(Vector2(x, dy), ENTRY_LEADER_DOT, ENTRY_LEADER_COLOR)
				x += ENTRY_LEADER_STEP
		"divider":
			_draw_dotted_divider(row)
		_:
			var size: int = int(round(pw * FOOTER_SIZE_FRAC))
			var tw: float = _font_bold.get_string_size(data[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			row.draw_string(_font_bold, Vector2((w - tw) * 0.5, row.size.y * 0.5 + size * 0.36),
				data[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, FOOTER_COLOR)

# 판 바깥을 누르면 닫는다 — 설정 팝업과 같다.
func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed and not _panel_rect.has_point(event.position):
		close_pressed.emit()
