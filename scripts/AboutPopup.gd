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
# 사라진다. 배경을 깔지 않고, 글자 둘레에 어두운 테두리를 둘러 배경과
# 구분되게 한다 — _outlined_logo 참고.
const LOGO_FILE := "res://assets/ui_assets/title/logo.png"
const LOGO_WIDTH_FRAC := 0.92          # 판 안쪽 폭 대비 로고 폭
const LOGO_PAD_FRAC := 0.02            # 로고 높이 대비 위아래 여백
# 테두리는 미리 구운 텍스처 위에서 두른다. 두께는 그 텍스처 폭 대비.
const LOGO_BAKE_WIDTH := 520
const LOGO_OUTLINE_FRAC := 0.005
const LOGO_OUTLINE_COLOR := Color(0.05, 0.07, 0.12, 1.0)

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
const PAD_AFTER_LOGO := 0.006
const PAD_AFTER_INTRO := 0.018
const PAD_AFTER_SECTION := 0.012
const PAD_BETWEEN_ROWS := 0.008
const PAD_AROUND_DIVIDER := 0.030
const PAD_BEFORE_FOOTER := 0.030

var _cancel: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _logo_texture: Texture2D
var _rows: Array[Control] = []      # 폭이 바뀔 때 다시 재야 하는 것들


func panel_size_frac() -> Vector2:
	# 설정 팝업과 같은 크기 — 위에 겹쳐 뜨므로 더 작으면 뒤가 비어져 나온다.
	return Vector2(0.90, 0.86)


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
		_logo_texture = _outlined_logo(load(LOGO_FILE))
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


# 로고 글자 둘레에 어두운 테두리를 둘러 크림색 판 위에서도 읽히게 만든다.
#
# 원본은 흰 글자 + 파란 J 라 배경이 밝으면 흰 부분이 사라진다. 알파를 사방으로
# 부풀려(가로 최대 -> 세로 최대, 두 번에 나눠서 싸게) 테두리 층을 만들고 그
# 위에 원본을 얹는다. 부풀리기 전에 그릴 크기 가까이로 줄여 둔다 — 원본이
# 2000px 이 넘어 그대로 두면 계산이 무겁고, 두께도 화면에서 실보다 얇아진다.
func _outlined_logo(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	# 픽셀 단위 작업이라 0.6초쯤 걸린다 — 팝업 아트와 같은 캐시에 넣어 두고
	# 런타임에는 읽기만 한다(tools/bake_popup_art.gd).
	var key := "logo_outline|%s|%d|%.4f" % [tex.resource_path, LOGO_BAKE_WIDTH, LOGO_OUTLINE_FRAC]
	var cached := _baked(key)
	if not cached.is_empty():
		return cached["texture"]
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	if img.get_width() > LOGO_BAKE_WIDTH:
		var h: int = int(round(img.get_height() * float(LOGO_BAKE_WIDTH) / img.get_width()))
		img.premultiply_alpha()
		img.resize(LOGO_BAKE_WIDTH, h, Image.INTERPOLATE_LANCZOS)
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0:
					img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))

	var w := img.get_width()
	var h2 := img.get_height()
	var r: int = maxi(1, int(round(w * LOGO_OUTLINE_FRAC)))
	# 테두리가 텍스처 밖으로 나가지 않게 사방에 여백을 두른 캔버스에서 작업한다.
	var pw := w + r * 2
	var ph := h2 + r * 2
	var src := PackedFloat32Array()
	src.resize(pw * ph)
	for y in range(h2):
		for x in range(w):
			src[(y + r) * pw + (x + r)] = img.get_pixel(x, y).a
	# 가로로 최대값, 그다음 세로로 최대값 — 사각 커널이지만 이 두께에서는
	# 원형과 차이가 눈에 띄지 않고 훨씬 싸다.
	var mid := PackedFloat32Array()
	mid.resize(pw * ph)
	for y in range(ph):
		for x in range(pw):
			var m := 0.0
			for d in range(-r, r + 1):
				var nx := x + d
				if nx >= 0 and nx < pw:
					m = maxf(m, src[y * pw + nx])
			mid[y * pw + x] = m
	var grown := PackedFloat32Array()
	grown.resize(pw * ph)
	for y in range(ph):
		for x in range(pw):
			var m := 0.0
			for d in range(-r, r + 1):
				var ny := y + d
				if ny >= 0 and ny < ph:
					m = maxf(m, mid[ny * pw + x])
			grown[y * pw + x] = m
	# 최대값 필터는 사각 커널이라 바깥 모서리가 각진다. 작은 상자 흐림을
	# 한 번 걸어 둥글리고 계단도 없앤다(가로 -> 세로, 역시 두 번에 나눠서).
	var br: int = maxi(1, int(round(r * 0.6)))
	var blurred := PackedFloat32Array()
	blurred.resize(pw * ph)
	for y in range(ph):
		for x in range(pw):
			var sum := 0.0
			var cnt := 0
			for d in range(-br, br + 1):
				var nx := x + d
				if nx >= 0 and nx < pw:
					sum += grown[y * pw + nx]
					cnt += 1
			blurred[y * pw + x] = sum / cnt
	for y in range(ph):
		for x in range(pw):
			var sum := 0.0
			var cnt := 0
			for d in range(-br, br + 1):
				var ny := y + d
				if ny >= 0 and ny < ph:
					sum += blurred[ny * pw + x]
					cnt += 1
			grown[y * pw + x] = sum / cnt

	var out := Image.create_empty(pw, ph, false, Image.FORMAT_RGBA8)
	for y in range(ph):
		for x in range(pw):
			var oa: float = grown[y * pw + x]
			var col := Color(LOGO_OUTLINE_COLOR.r, LOGO_OUTLINE_COLOR.g, LOGO_OUTLINE_COLOR.b, oa)
			var sx := x - r
			var sy := y - r
			if sx >= 0 and sy >= 0 and sx < w and sy < h2:
				var top: Color = img.get_pixel(sx, sy)
				if top.a > 0.0:
					# 원본을 테두리 위에 알파 합성.
					var a: float = top.a + oa * (1.0 - top.a)
					col = Color(
						(top.r * top.a + col.r * oa * (1.0 - top.a)) / a,
						(top.g * top.a + col.g * oa * (1.0 - top.a)) / a,
						(top.b * top.a + col.b * oa * (1.0 - top.a)) / a, a)
			out.set_pixel(x, y, col)
	_bake_store(key, out, 0)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


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
			var lw: float = w * LOGO_WIDTH_FRAC
			var lh: float = lw * float(_logo_texture.get_height()) / float(_logo_texture.get_width())
			return lh * (1.0 + LOGO_PAD_FRAC * 2.0)
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
			var lw: float = w * LOGO_WIDTH_FRAC
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
