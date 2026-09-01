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

# 슬라이더와 점선 구분선은 PopupBase 가 들고 있다 — 설정 팝업과 같은 것을 쓴다.

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
	var track_x: float = minf(_slider_label_column(slider_font, ["SFX", "MUSIC"]), inner_w * 0.55)
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
	_draw_slider_labels(_sliders,
		[["SFX", _sfx_icon], ["MUSIC", _music_icon]],
		int(round(_panel_rect.size.x * SLIDER_LABEL_FRAC)),
		_sliders.get_meta("row_h", 30.0), _sliders.get_meta("gap", 8.0))


# 판을 가로지르는 점선. 위쪽 조작과 아래쪽 나가기를 갈라 준다.
func _draw_divider() -> void:
	_draw_dotted_divider(_divider)

