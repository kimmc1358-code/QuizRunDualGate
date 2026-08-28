extends PopupBase

## 일시정지 팝업.
##
## 화면을 다 덮지 않고 가운데에 판 하나만 띄운다 — 뒤로 게임이 비쳐야
## "잠깐 멈춘 것"으로 읽히고, 전체를 가리면 화면이 전환된 느낌이 든다.
##
## 판·버튼·아이콘·글로우는 전부 PopupBase가 맡는다. 여기에는 이 팝업만의
## 내용(제목, 버튼 셋, 소리 조절, 구분선)과 그 배치만 있다.

signal resume_pressed
signal restart_pressed
signal home_pressed
signal sfx_volume_changed(value: float)
signal music_volume_changed(value: float)

const TITLE_TEXT := "PAUSED"
const TITLE_SIZE_FRAC := 0.105        # 판 너비 대비 글자 크기
# RESUME이 주 동작이라 가장 크다. 나머지 둘은 한 단계 작게 두어, 크기만으로도
# 무엇이 기본 선택인지 읽히게 한다.
const PRIMARY_HEIGHT_FRAC := 0.178    # 판 높이 대비 RESUME 높이
const SECONDARY_HEIGHT_FRAC := 0.118  # RESTART / HOME
const SECONDARY_WIDTH_FRAC := 0.88

const SLIDER_LABEL_FRAC := 0.062
const SLIDER_TRACK_HEIGHT := 12.0
const SLIDER_TRACK_COLOR := Color(0.84, 0.80, 0.70, 1.0)   # 빈 구간
const SLIDER_FILL_COLOR := Color(1.0, 0.78, 0.22, 1.0)     # 채워진 구간 — 판의 골드와 같은 계열
const SLIDER_TRACK_RADIUS := 6
const SLIDER_KNOB_SIZE := 26        # 손잡이 지름(px). 손가락으로 잡을 만한 크기
const SLIDER_KNOB_FILL := Color(1.0, 0.99, 0.96, 1.0)
const SLIDER_KNOB_EDGE := Color(0.055, 0.180, 0.435, 1.0)  # 테두리 네이비와 동일
const SLIDER_KNOB_EDGE_PX := 3.0
const SLIDER_ICON_GAP_FRAC := 0.34  # 글자 크기 대비 아이콘-글자 간격

# 구분선: 판을 가로지르는 점선. 위쪽(조작)과 아래쪽(나가기)을 나눈다.
const DIVIDER_DOTS := 22
const DIVIDER_DOT_RADIUS := 2.6
const DIVIDER_COLOR := Color(0.80, 0.75, 0.63, 1.0)   # 진한 크림

var _title: Label
var _resume: Button
var _restart: Button
var _home: Button
var _sliders: Control
var _sfx_slider: HSlider
var _music_slider: HSlider
var _divider: Control
var _sfx_icon: Texture2D
var _music_icon: Texture2D


func _build_content() -> void:
	_title = _make_label(TITLE_TEXT, _font_heavy)
	add_child(_title)

	_resume = _make_button(GOLD_FILE, GOLD_CORNER, "RESUME", _load_popup_icon(POPUP_ICON_PLAY), true)
	_resume.pressed.connect(func(): resume_pressed.emit())
	add_child(_resume)

	_restart = _make_button(CREAM_FILE, CREAM_CORNER, "RESTART", _load_icon(ICON_RESTART), false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_restart.pressed.connect(func(): restart_pressed.emit())
	add_child(_restart)

	# 소리 조절 두 줄. 이름표와 아이콘은 이 노드가 직접 그리고, 트랙과 손잡이는
	# HSlider가 맡는다 — 드래그·탭·키보드 입력을 직접 짤 이유가 없다.
	_sliders = Control.new()
	_sliders.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sliders.draw.connect(_draw_sliders)
	add_child(_sliders)
	_sfx_icon = _load_icon(ICON_SPEAKER)
	_music_icon = _load_icon(ICON_NOTE)
	_sfx_slider = _make_slider()
	_sfx_slider.value_changed.connect(func(v: float): sfx_volume_changed.emit(v))
	_sliders.add_child(_sfx_slider)
	_music_slider = _make_slider()
	_music_slider.value_changed.connect(func(v: float): music_volume_changed.emit(v))
	_sliders.add_child(_music_slider)

	_divider = Control.new()
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.draw.connect(_draw_divider)
	add_child(_divider)

	_home = _make_button(CREAM_FILE, CREAM_CORNER, "HOME", _load_icon(ICON_HOME), false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_home.pressed.connect(func(): home_pressed.emit())
	add_child(_home)


# 판 안쪽을 위에서부터 차례로 쌓는다: 제목 → RESUME → RESTART → SFX →
# MUSIC → 구분선 → HOME. 남는 세로 공간을 항목 사이에 고르게 나눠, 화면
# 비율이 달라져도 아래위가 붙거나 벌어지지 않는다.
func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var inner_x: float = inner.position.x
	var inner_w: float = inner.size.x
	var top: float = inner.position.y
	var bottom: float = inner.end.y

	var primary_h: float = ph * PRIMARY_HEIGHT_FRAC
	var secondary_h: float = ph * SECONDARY_HEIGHT_FRAC
	var secondary_w: float = inner_w * SECONDARY_WIDTH_FRAC
	var title_h: float = pw * TITLE_SIZE_FRAC * 1.25
	var slider_h: float = pw * SLIDER_LABEL_FRAC * 1.1 + SLIDER_TRACK_HEIGHT + 6.0
	var divider_h: float = DIVIDER_DOT_RADIUS * 2.0

	# 항목 7개(제목, 버튼3, 슬라이더2, 구분선)의 높이 합을 뺀 나머지를
	# 사이 간격 6개로 나눈다.
	var used: float = title_h + primary_h + secondary_h * 2.0 + slider_h * 2.0 + divider_h
	var gap: float = maxf(6.0, (bottom - top - used) / 6.0)

	var y := top
	_title.position = Vector2(inner_x, y)
	_title.size = Vector2(inner_w, title_h)
	_title.add_theme_font_size_override("font_size", int(round(pw * TITLE_SIZE_FRAC)))
	y += title_h + gap

	# 보조 버튼은 좁으므로 안쪽 폭 안에서 가운데로 맞춘다.
	var sec_x: float = inner_x + (inner_w - secondary_w) * 0.5
	_place(_resume, inner_x, y, inner_w, primary_h, 1.0,
		BUTTON_CONTENT_FIT, 0.0, GOLD_CONTENT_DY)
	y += primary_h + gap
	_place(_restart, sec_x, y, secondary_w, secondary_h)
	y += secondary_h + gap

	_sliders.position = Vector2(inner_x, y)
	_sliders.size = Vector2(inner_w, slider_h * 2.0 + gap)
	_sliders.set_meta("gap", gap)
	_sliders.set_meta("row_h", slider_h)
	# 트랙은 이름표 칸 오른쪽부터. 칸 너비는 고정 비율이 아니라 실제로 재서
	# 정한다 — MUSIC이 SFX보다 길어서 비율로 잡으면 긴 쪽이 트랙에 물린다.
	var slider_font: int = int(round(pw * SLIDER_LABEL_FRAC))
	var label_col := 0.0
	for text in ["SFX", "MUSIC"]:
		label_col = maxf(label_col, _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, slider_font).x)
	# 아이콘(글자 높이와 같은 정사각형 가정) + 간격 + 글자 + 트랙까지 숨돌릴 틈
	label_col += slider_font * (1.0 + SLIDER_ICON_GAP_FRAC) + slider_font * 0.5
	var track_x: float = minf(label_col, inner_w * 0.55)
	var track_w: float = inner_w - track_x
	# 손잡이가 트랙 양끝에서 반쯤 걸치므로, 그만큼 안쪽으로 넣어 판 밖으로
	# 삐져나가지 않게 한다.
	var knob_pad: float = SLIDER_KNOB_SIZE * 0.5
	for i in range(2):
		var s: HSlider = _sfx_slider if i == 0 else _music_slider
		s.position = Vector2(track_x + knob_pad, i * (slider_h + gap) + slider_h * 0.5 - SLIDER_KNOB_SIZE * 0.5)
		s.size = Vector2(maxf(10.0, track_w - knob_pad * 2.0), SLIDER_KNOB_SIZE)
	_sliders.queue_redraw()
	y += slider_h * 2.0 + gap + gap

	_divider.position = Vector2(inner_x, y)
	_divider.size = Vector2(inner_w, divider_h)
	_divider.queue_redraw()
	y += divider_h + gap

	_place(_home, sec_x, y, secondary_w, secondary_h)


# 팝업을 열 때 Main이 현재 볼륨을 넣어 준다. value_changed를 잠시 끊어,
# 값을 세팅하는 것만으로 신호가 되돌아가 저장이 일어나지 않게 한다.
func set_volumes(sfx: float, music: float) -> void:
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(clampf(sfx, 0.0, 1.0))
	if _music_slider != null:
		_music_slider.set_value_no_signal(clampf(music, 0.0, 1.0))


# 두 줄의 왼쪽 칸: 아이콘 + 이름표. 트랙과 손잡이는 HSlider가 그린다.
# 아이콘과 글자를 같은 높이로 맞춰 한 줄로 읽히게 한다.
func _draw_sliders() -> void:
	var font_size: int = int(round(_panel_rect.size.x * SLIDER_LABEL_FRAC))
	var row_h: float = _sliders.get_meta("row_h", 30.0)
	var gap: float = _sliders.get_meta("gap", 8.0)
	var rows := [["SFX", _sfx_icon], ["MUSIC", _music_icon]]
	for i in range(rows.size()):
		var text: String = rows[i][0]
		var icon: Texture2D = rows[i][1]
		# 줄의 세로 중심 — 트랙과 같은 높이에 놓아 나란히 보이게.
		var centre_y: float = i * (row_h + gap) + row_h * 0.5
		var x := 0.0
		if icon != null:
			# 아이콘 높이를 글자 크기에 맞춘다.
			var ih: float = font_size
			var iw: float = ih * (float(icon.get_width()) / float(icon.get_height()))
			_sliders.draw_texture_rect(icon,
				Rect2(Vector2(x, centre_y - ih * 0.5), Vector2(iw, ih)), false, INK)
			x += iw + font_size * SLIDER_ICON_GAP_FRAC
		# draw_string은 베이스라인 기준이라, 대문자 높이의 절반만큼 내려야
		# 글자 가운데가 아이콘 가운데와 맞는다.
		_sliders.draw_string(_font_bold, Vector2(x, centre_y + font_size * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


# 판을 가로지르는 점선. 위쪽 조작과 아래쪽 나가기를 갈라 준다.
func _draw_divider() -> void:
	var w: float = _divider.size.x
	var y: float = _divider.size.y * 0.5
	var step: float = w / float(maxi(1, DIVIDER_DOTS - 1))
	for i in range(DIVIDER_DOTS):
		_divider.draw_circle(Vector2(i * step, y), DIVIDER_DOT_RADIUS, DIVIDER_COLOR)


# 팔레트에 맞춘 HSlider. 트랙·채움·손잡이를 전부 갈아끼워 기본 회색 테마가
# 남지 않게 한다.
func _make_slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_filter = Control.MOUSE_FILTER_STOP

	var track := StyleBoxFlat.new()
	track.bg_color = SLIDER_TRACK_COLOR
	track.set_corner_radius_all(SLIDER_TRACK_RADIUS)
	track.content_margin_top = SLIDER_TRACK_HEIGHT * 0.5
	track.content_margin_bottom = SLIDER_TRACK_HEIGHT * 0.5
	track.anti_aliasing = true
	s.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = SLIDER_FILL_COLOR
	fill.set_corner_radius_all(SLIDER_TRACK_RADIUS)
	fill.content_margin_top = SLIDER_TRACK_HEIGHT * 0.5
	fill.content_margin_bottom = SLIDER_TRACK_HEIGHT * 0.5
	fill.anti_aliasing = true
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)

	var knob := _make_knob()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	return s


# 손잡이 텍스처를 코드로 그린다. 크림 채움 + 네이비 테두리, 가장자리는
# 픽셀 단위로 부드럽게 — 팝업의 다른 테두리와 같은 결을 내기 위해서다.
func _make_knob() -> Texture2D:
	var ss := 2                       # 2배로 그린 뒤 줄여 가장자리를 더 곱게
	var d: int = SLIDER_KNOB_SIZE * ss
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r: float = d * 0.5
	var edge: float = SLIDER_KNOB_EDGE_PX * ss
	for y in range(d):
		for x in range(d):
			var dist: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if dist > r:
				continue
			# 바깥 1px은 알파로 흐려 계단을 없앤다.
			var a: float = clampf(r - dist, 0.0, 1.0)
			var c: Color = SLIDER_KNOB_EDGE if dist > r - edge else SLIDER_KNOB_FILL
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	img.resize(SLIDER_KNOB_SIZE, SLIDER_KNOB_SIZE, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
