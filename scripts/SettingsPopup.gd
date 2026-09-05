extends PopupBase

## 설정 팝업. 메인 화면 오른쪽 위 톱니바퀴에서 연다.
##
## 판 위로 SETTINGS 아트가 걸터앉고, 판 안은 점선으로 세 칸이다:
##   소리 조절(SFX / MUSIC) — 일시정지 팝업과 같은 슬라이더를 쓴다
##   계정         — 동그란 자리 + 상태 글자 + LOGIN 크림 버튼
##   약관         — Privacy Policy / Terms of Service, 밑줄 + 오른쪽 ">"
##
## 닫기 버튼은 따로 두지 않았다. 판 바깥을 누르면 닫힌다 — 설정은 되돌릴 것이
## 없는 화면이라 "확인/취소"가 필요 없고, 버튼 하나를 아끼는 편이 깔끔하다.

signal close_pressed
signal login_pressed
signal logout_pressed
signal remove_ads_pressed
signal contact_pressed
signal about_pressed
signal privacy_pressed
signal terms_pressed
signal sfx_volume_changed(value: float)
signal music_volume_changed(value: float)
signal boost_side_changed(on_left: bool)
## 언어 토글. true 면 한국어.
signal language_changed(korean: bool)

# 2172px 짜리 원본을 그대로 GPU 밉맵에 맡겨 줄이면 테두리에 계단이 남는다.
# _load_icon_from 은 알파를 곱한 채 Lanczos 로 미리 줄이고 여백까지 둘러 주므로
# (트로피·리본과 같은 길) 그 길로 읽는다. 아트를 바꾸면 다시 구워야 한다 —
# tools/bake_popup_art.gd.
const TITLE_FILE := "res://assets/ui_assets/popup/settings_popup.png"
const TITLE_TEXTURE_HEIGHT := 240
# 제목 아트가 판 위로 얼마나 걸터앉는가 — 부활 팝업의 OOPS와 같은 방식.
const TITLE_WIDTH_FRAC := 0.68    # 판 너비 대비 — 오른쪽 위 닫기 버튼 자리를 비워 둔다
const TITLE_OVERHANG := 0.55      # 자기 높이 중 판 위로 나가는 비율

# 계정 줄: [동그란 자리] [상태 글자] ......... [LOGIN 버튼]
# 줄 높이는 판 "너비" 기준이다. 높이 기준으로 두면 판을 세로로 키울 때
# 줄들도 같이 커져서 아무리 키워도 계속 넘친다.
const ACCOUNT_ROW_HEIGHT_FRAC := 0.155   # 판 너비 대비
const AVATAR_DIAMETER_FRAC := 0.86       # 줄 높이 대비
const AVATAR_FILL := Color(0.86, 0.83, 0.75, 1.0)
const AVATAR_EDGE := Color(0.72, 0.68, 0.59, 1.0)
const AVATAR_EDGE_PX := 2.0
const AVATAR_GLYPH := Color(0.62, 0.59, 0.52, 1.0)   # 사람 모양 자리표시
const ACCOUNT_GAP_FRAC := 0.025          # 판 너비 대비 — 동그라미와 글자 사이
const ACCOUNT_TEXT_SIZE_FRAC := 0.050    # 판 너비 대비
const ACCOUNT_TEXT_COLOR := Color(0.55, 0.55, 0.58, 1.0)   # 회색
const ACCOUNT_TEXT_MIN_SIZE := 11
const LOGGED_OUT_TEXT := "Not logged in"
const LOGGED_IN_FORMAT := "Logged in as %s"
const LOGIN_TEXT := "LOGIN"
const LOGOUT_TEXT := "LOGOUT"
const LOGIN_WIDTH_FRAC := 0.26           # 판 너비 대비
const ACCOUNT_BUTTON_GAP_FRAC := 0.030   # 판 너비 대비 — 글자와 버튼 사이
const LOGIN_HEIGHT_FRAC := 0.122         # 판 너비 대비
const LOGIN_TEXTURE_WIDTH := 105         # 9-slice 텍스처 폭 — _build_content 주석 참고

# 약관 줄: 글자에 밑줄, 줄 오른쪽 끝에 ">".
# 광고 제거 — 계정 줄 바로 아래의 골드 버튼. primary=true 면 흰 글자에
# 네이비 테두리가 붙는다(RESUME/PLAY AGAIN 과 같은 꾸밈).
const REMOVE_ADS_TEXT := "REMOVE ADS"
const REMOVE_ADS_ICON := "res://assets/ui_assets/popup/icon_noads.png"
# 아이콘 텍스처는 그릴 크기보다 넉넉히 구워 둔다 — 작게 구워 놓고 늘리면
# 가장자리가 뭉갠다. _load_icon_from 이 둘레에 투명 여백까지 둘러 주므로
# 실루엣이 텍스처 가장자리에 닿아 잘려 보이는 일도 없다.
const REMOVE_ADS_ICON_HEIGHT := 128
# 글자 높이에 맞춘다 — _place 의 기본값은 글자의 1.18 배라 그 역수를 준다.
const REMOVE_ADS_ICON_SCALE := 1.15
const REMOVE_ADS_HEIGHT_FRAC := 0.215    # 판 너비 대비
const REMOVE_ADS_WIDTH_FRAC := 0.92      # 안쪽 폭 대비
# 위아래 점선과의 간격은 따로 크게 잡는다 — 버튼이 커서 점선에 붙으면 답답하다.
const REMOVE_ADS_GAP_FRAC := 0.048       # 판 너비 대비
# 일시정지의 RESUME, 게임오버의 PLAY AGAIN 과 같은 그림으로 보이게 하려면
# 9-slice 텍스처 크기가 같아야 한다 — 테두리 굵기가 버튼 크기가 아니라
# 텍스처 크기에 비례해서 그려지기 때문이다(작게 구우면 테두리도 얇아진다).
# 그래서 기본값(BUTTON_TEXTURE_WIDTH)을 쓰고, 버튼 높이도 RESUME 과
# 비슷하게 잡는다.
const REMOVE_ADS_TEXTURE_WIDTH := BUTTON_TEXTURE_WIDTH

const LINK_TEXTS := ["Privacy Policy", "Terms of Service", "Contact / Feedback", "About"]
# 아이콘 시트에 편지 그림이 없어서 직접 그린다 — 봉투 사각형 + 뚜껑 선 둘.
const LINK_MAIL_INDEX := 2               # 편지 아이콘이 붙는 줄
const LINK_MAIL_GAP_FRAC := 0.45         # 글자 크기 대비 글자-아이콘 간격
const LINK_MAIL_HEIGHT_FRAC := 0.72      # 글자 크기 대비 아이콘 높이
const LINK_MAIL_LINE_PX := 1.3
const LINK_TEXT_SIZE_FRAC := 0.048       # 판 너비 대비
const LINK_COLOR := Color(0.24, 0.28, 0.36, 1.0)
const LINK_UNDERLINE_PX := 1.4
const LINK_UNDERLINE_DROP := 0.30        # 글자 크기 대비 베이스라인 아래로
const LINK_ROW_HEIGHT_FRAC := 0.118      # 판 너비 대비
# 약관 두 줄은 한 묶음으로 읽혀야 하니 사이를 좁게, 그 아래 버전은 별개라
# 넓게 띄운다. 나머지 간격들은 남는 공간을 고르게 나눠 가진다.
const LINK_GAP_FRAC := 0.010             # 판 너비 대비 — 약관 줄 사이
const VERSION_GAP_FRAC := 0.094          # 판 너비 대비 — 약관과 버전 사이
const LINK_CHEVRON := ">"
const LINK_CHEVRON_COLOR := Color(0.62, 0.62, 0.66, 1.0)
# 아직 주소가 없는 줄. 흐리게 그려 "지금은 눌러도 소용없다"를 보인다 —
# _link_enabled 참고.
const LINK_DISABLED_DIM := 0.38

# 판 맨 아래 가운데의 버전 표시. 문자열은 project.godot 에서 읽는다 —
# _read_version_text 참고.
const VERSION_SIZE_FRAC := 0.044       # 판 너비 대비
const VERSION_COLOR := Color(0.62, 0.62, 0.66, 1.0)

# 가속 버튼을 어느 쪽 아래 구석에 둘지. 같은 자리를 두고 "편하다"와 "너무
# 불편하다"로 갈린다는 피드백이 있어서 고를 수 있게 했다.
#
# 두 갈래 토글로 그린다(_make_side_toggle). 처음에는 금색 버튼 두 개였는데
# 트랙 절반 폭이 GOLD_CORNER(88px) 의 두 배에 못 미쳐 나인패치 모서리가 서로
# 파고들며 테두리가 깨졌다.
const BOOST_ROW_LABEL := "BOOST"
const BOOST_OPTION_TEXTS := ["LEFT", "RIGHT"]

# 언어 줄. 두 칸의 글자는 번역하지 않는다 — 지금 언어가 무엇이든 두 선택지가
# 자기 언어로 적혀 있어야 고를 수 있다. 잘못 눌러 못 읽는 언어로 바뀌었을 때
# 되돌아올 길이 이것뿐이기도 하다.
const LANGUAGE_ROW_LABEL := "LANGUAGE"
const LANGUAGE_OPTION_TEXTS := ["ENG", "KOR"]
const BOOST_ROW_HEIGHT_FRAC := 0.105    # 판 너비 대비

var _title: TextureRect
var _sliders: Control
var _sfx_slider: HSlider
var _music_slider: HSlider
var _boost_row: Control          # "BOOST" 이름표 + LEFT/RIGHT 두 칸
var _language_row: Control       # "LANGUAGE" 이름표 + ENG/KOR 두 칸
var _language_toggle: Control
var _korean := false
var _boost_toggle: Control
var _boost_on_left := false
var _divider_top: Control
var _divider_account: Control    # 계정 줄과 광고 제거 사이
var _divider_bottom: Control
var _account: Control
var _login: Button
var _remove_ads: Button
var _links: Array[Button] = []
var _sfx_icon: Texture2D
var _music_icon: Texture2D
var _avatar: Texture2D          # 로그인하면 Main이 넣어 준다
# 번역을 거쳐야 해서 선언이 아니라 _build_content 에서 채운다 — 상수를 그대로
# 넣어 두면 로그인 전 화면만 영어로 남는다.
var _account_text: String = ""
var _logged_in := false
var _cancel: Button
var _version: Control
# 그릴 때마다 설정을 뒤질 이유가 없다 — 프로젝트 설정은 실행 중에 안 바뀐다.
var _version_text: String = ""


func panel_size_frac() -> Vector2:
	# 담을 것이 늘어난 만큼 세로로 키운다. 줄 높이는 너비 기준이라 여기를
	# 키우면 줄이 아니라 줄 사이 여백이 늘어난다. 0.86 이었는데 언어 줄이
	# 하나 붙으면서 맨 아래 버전 표시가 판 밖으로 밀려 나갔다.
	return Vector2(0.90, 0.92)


func panel_texture_width() -> int:
	return 450


func panel_center_y_frac() -> float:
	# 제목이 판 위로 튀어나오므로 판을 살짝 내려 머리 공간을 만든다.
	return 0.53


func _build_content() -> void:
	# 다시 지을 때(rebuild) 자식은 모두 지워진 뒤다 — 비우지 않으면 배치가
	# 이미 사라진 노드를 짚는다.
	_links.clear()
	_account_text = tr(LOGGED_OUT_TEXT)
	# 소리 조절 — 일시정지 팝업과 같은 슬라이더.
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

	_boost_row = Control.new()
	_boost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_row.draw.connect(_draw_boost_row)
	add_child(_boost_row)
	# 값은 "왼쪽인가"인데 토글은 "두 번째 칸인가"를 다루므로, 오른쪽이 두 번째다.
	_boost_toggle = _make_side_toggle([tr(BOOST_OPTION_TEXTS[0]), tr(BOOST_OPTION_TEXTS[1])], not _boost_on_left,
		func(on_second: bool) -> void:
			_boost_on_left = not on_second
			boost_side_changed.emit(_boost_on_left))
	add_child(_boost_toggle)

	_language_row = Control.new()
	_language_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_language_row.draw.connect(_draw_language_row)
	add_child(_language_row)
	_language_toggle = _make_side_toggle(LANGUAGE_OPTION_TEXTS, _korean,
		func(on_second: bool) -> void:
			_korean = on_second
			language_changed.emit(_korean))
	add_child(_language_toggle)

	_divider_top = _make_divider()
	_divider_account = _make_divider()
	_divider_bottom = _make_divider()

	# 계정 줄. 동그란 자리와 글자는 이 노드가 직접 그리고, 버튼만 진짜 노드다.
	_account = Control.new()
	_account.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_account.draw.connect(_draw_account)
	add_child(_account)
	# 텍스처 폭을 기본값(197)으로 두면 9-slice 모서리가 41px 이 되는데, 이
	# 버튼은 50px 밖에 안 높아서 위아래 모서리가 서로 겹쳐 테두리가 뭉갠다.
	# 크림 아트는 1939x613 에 모서리 202 라, 모서리는 늘 텍스처 높이의 33% 다 —
	# 즉 텍스처 높이가 버튼 높이의 1.5 배를 넘으면 안 된다. 105 면 텍스처가
	# 210x66, 모서리 22 로 50px 버튼 안에 넉넉히 들어온다.
	_login = _make_button(CREAM_FILE, CREAM_CORNER, tr(LOGIN_TEXT), null, false,
		CREAM_GRADIENT, LOGIN_TEXTURE_WIDTH)
	# 같은 버튼이 상태에 따라 로그인/로그아웃 둘 다 맡는다.
	_login.pressed.connect(func(): (logout_pressed if _logged_in else login_pressed).emit())
	add_child(_login)

	_remove_ads = _make_button(GOLD_FILE, GOLD_CORNER, tr(REMOVE_ADS_TEXT),
		_load_icon_from(REMOVE_ADS_ICON, Vector2i(1, 1), 0, REMOVE_ADS_ICON_HEIGHT),
		true, Vector2.ZERO, REMOVE_ADS_TEXTURE_WIDTH)
	_remove_ads.pressed.connect(func(): remove_ads_pressed.emit())
	add_child(_remove_ads)

	# 약관 두 줄. 글자와 밑줄, 오른쪽 ">"는 버튼 위에 직접 그린다 —
	# 줄 전체가 누르는 자리가 되어야 손가락으로 집기 편하다.
	for i in range(LINK_TEXTS.size()):
		var link := Button.new()
		link.flat = true
		link.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
			link.add_theme_stylebox_override(slot, empty)
		link.draw.connect(_draw_link.bind(link, i))
		link.pressed.connect(_on_link_pressed.bind(i))
		# 그리는 것은 그대로 두고 노드째 흐리게 한다 — 글자·밑줄·아이콘·꺾쇠가
		# 각각 다른 색이라, 색마다 흐린 짝을 두면 넷을 따로 관리하게 된다.
		# 여기서 한 번만 정하면 된다: 주소는 상수라 실행 중에 바뀌지 않는다.
		# (_draw_link 안에서 modulate 를 건드리면 그 프레임에는 반영되지 않는다.)
		link.modulate.a = 1.0 if _link_enabled(i) else LINK_DISABLED_DIM
		add_child(link)
		_links.append(link)

	# 판 맨 아래 가운데 버전.
	_version_text = _read_version_text()
	_version = Control.new()
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_version.draw.connect(_draw_version)
	add_child(_version)

	_cancel = _make_close_button(func(): close_pressed.emit())

	# 제목은 판보다 위에 그려져야 하므로 마지막에 붙인다.
	_title = TextureRect.new()
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_title.texture = _load_icon_from(TITLE_FILE, Vector2i(1, 1), 0, TITLE_TEXTURE_HEIGHT)
	add_child(_title)


func _make_divider() -> Control:
	var d := Control.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(_draw_dotted_divider.bind(d))
	add_child(d)
	return d


# 판 안쪽을 위에서부터: SFX → MUSIC → 점선 → 계정 → 점선 → 약관 두 줄.
# 남는 세로 공간을 사이사이에 고르게 나눈다.
func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var inner_x: float = inner.position.x
	var inner_w: float = inner.size.x
	var top: float = inner.position.y
	var bottom: float = inner.end.y

	# 제목은 판 위쪽 테두리에 걸친다.
	if _title.texture != null:
		var tw: float = pw * TITLE_WIDTH_FRAC
		var th: float = tw * (float(_title.texture.get_height()) / float(_title.texture.get_width()))
		_title.size = Vector2(tw, th)
		_title.position = Vector2(
			_panel_rect.position.x + (pw - tw) * 0.5,
			_panel_rect.position.y - th * TITLE_OVERHANG)

	var slider_font: int = int(round(pw * SLIDER_LABEL_FRAC))
	var slider_h: float = pw * SLIDER_LABEL_FRAC * 1.1 + SLIDER_TRACK_HEIGHT + 6.0
	var divider_h: float = DIVIDER_DOT_RADIUS * 2.0
	var account_h: float = pw * ACCOUNT_ROW_HEIGHT_FRAC
	var link_h: float = pw * LINK_ROW_HEIGHT_FRAC

	var version_h: float = pw * VERSION_SIZE_FRAC * 1.6
	var remove_h: float = pw * REMOVE_ADS_HEIGHT_FRAC
	var link_gap: float = pw * LINK_GAP_FRAC
	var version_gap: float = pw * VERSION_GAP_FRAC
	var link_count: int = LINK_TEXTS.size()
	var remove_gap: float = pw * REMOVE_ADS_GAP_FRAC
	# 따로 정한 간격(광고 제거 버튼 위아래 + 약관 줄 사이 + 약관-버전)을 뺀
	# 나머지를 남은 간격들이 고르게 나눈다.
	var boost_row_h: float = pw * BOOST_ROW_HEIGHT_FRAC
	var used: float = slider_h * 2.0 + boost_row_h * 2.0 + divider_h * 3.0 + account_h + remove_h \
		+ link_h * link_count + version_h + link_gap * (link_count - 1) + version_gap \
		+ remove_gap * 2.0
	# 같은 모양의 줄이 둘이다 — 가속 버튼 좌/우와 언어. 하나만 세면 판이 한
	# 줄만큼 모자라고, 넘친 만큼이 맨 아래 버전 표시부터 밖으로 나간다.
	# 고르게 나눌 간격 일곱: 슬라이더 사이 / 슬라이더-가속 / 가속-언어 /
	# 언어-점선 / 점선-계정 / 계정-점선 / 점선-첫 약관.
	var gap: float = maxf(6.0, (bottom - top - used) / 7.0)

	var y := top
	_sliders.position = Vector2(inner_x, y)
	_sliders.size = Vector2(inner_w, slider_h * 2.0 + gap)
	_sliders.set_meta("gap", gap)
	_sliders.set_meta("row_h", slider_h)
	var track_x: float = minf(maxf(
			_slider_label_column(slider_font, [tr("SFX"), tr("MUSIC")]),
			_row_label_column(slider_font, [tr(BOOST_ROW_LABEL), tr(LANGUAGE_ROW_LABEL)])),
		inner_w * 0.55)
	var track_w: float = inner_w - track_x
	# 손잡이가 트랙 양끝에서 반쯤 걸치므로 그만큼 안쪽으로.
	var knob_pad: float = SLIDER_KNOB_SIZE * 0.5
	for i in range(2):
		var s: HSlider = _sfx_slider if i == 0 else _music_slider
		s.position = Vector2(track_x + knob_pad,
			i * (slider_h + gap) + slider_h * 0.5 - SLIDER_KNOB_SIZE * 0.5)
		s.size = Vector2(maxf(10.0, track_w - knob_pad * 2.0), SLIDER_KNOB_SIZE)
	_sliders.queue_redraw()
	y += slider_h * 2.0 + gap + gap

	# 가속 버튼 줄. 이름표는 슬라이더와 같은 칸에 세우고(track_x), 두 칸은
	# 트랙이 차지하던 폭을 반씩 나눠 쓴다 — 그래야 SFX/MUSIC 과 세로선이 맞는다.
	_boost_row.position = Vector2(inner_x, y)
	_boost_row.size = Vector2(inner_w, boost_row_h)
	_boost_row.queue_redraw()
	# 토글은 트랙과 같은 폭·같은 왼쪽 끝. 높이는 알약이 뭉툭해지지 않게 상한을 둔다.
	var toggle_h: float = minf(boost_row_h, TOGGLE_HEIGHT)
	_boost_toggle.position = Vector2(inner_x + track_x, y + (boost_row_h - toggle_h) * 0.5)
	_boost_toggle.size = Vector2(track_w, toggle_h)
	_boost_toggle.queue_redraw()
	y += boost_row_h + gap

	# 언어 줄은 가속 줄과 같은 모양이다 — 이름표는 같은 칸에, 두 칸은 같은 폭.
	_language_row.position = Vector2(inner_x, y)
	_language_row.size = Vector2(inner_w, boost_row_h)
	_language_row.queue_redraw()
	_language_toggle.position = Vector2(inner_x + track_x, y + (boost_row_h - toggle_h) * 0.5)
	_language_toggle.size = Vector2(track_w, toggle_h)
	_language_toggle.queue_redraw()
	y += boost_row_h + gap

	_divider_top.position = Vector2(inner_x, y)
	_divider_top.size = Vector2(inner_w, divider_h)
	_divider_top.queue_redraw()
	y += divider_h + gap

	var login_w: float = pw * LOGIN_WIDTH_FRAC
	var login_h: float = pw * LOGIN_HEIGHT_FRAC
	_account.position = Vector2(inner_x, y)
	_account.size = Vector2(inner_w - login_w - pw * ACCOUNT_BUTTON_GAP_FRAC, account_h)
	_account.queue_redraw()
	_place(_login, inner_x + inner_w - login_w, y + (account_h - login_h) * 0.5, login_w, login_h)
	y += account_h + gap

	_divider_account.position = Vector2(inner_x, y)
	_divider_account.size = Vector2(inner_w, divider_h)
	_divider_account.queue_redraw()
	y += divider_h + remove_gap

	var remove_w: float = inner_w * REMOVE_ADS_WIDTH_FRAC
	_place(_remove_ads, inner_x + (inner_w - remove_w) * 0.5, y, remove_w, remove_h,
		REMOVE_ADS_ICON_SCALE, BUTTON_CONTENT_FIT, 0.0, GOLD_CONTENT_DY)
	y += remove_h + remove_gap

	_divider_bottom.position = Vector2(inner_x, y)
	_divider_bottom.size = Vector2(inner_w, divider_h)
	_divider_bottom.queue_redraw()
	y += divider_h + gap

	for i in range(_links.size()):
		_links[i].position = Vector2(inner_x, y)
		_links[i].size = Vector2(inner_w, link_h)
		_links[i].queue_redraw()
		# 약관 줄끼리는 좁게, 마지막 줄과 버전 사이는 넓게.
		y += link_h + (version_gap if i == _links.size() - 1 else link_gap)

	_version.position = Vector2(inner_x, y)
	_version.size = Vector2(inner_w, version_h)
	_version.queue_redraw()

	_place_close_button(_cancel)


## 팝업을 열 때 Main이 현재 볼륨을 넣어 준다. value_changed를 잠시 끊어,
## 값을 세팅하는 것만으로 신호가 되돌아가 저장이 일어나지 않게 한다.
func set_volumes(sfx: float, music: float) -> void:
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(clampf(sfx, 0.0, 1.0))
	if _music_slider != null:
		_music_slider.set_value_no_signal(clampf(music, 0.0, 1.0))


## 계정 줄의 내용. 로그인하면 동그라미가 프로필 사진으로, 글자가
## "Logged in as [닉네임]"으로, 버튼이 LOGOUT 으로 바뀐다.
## 아직 인증이 붙지 않아 기본은 "로그인 안 됨"이다.
func set_account(avatar: Texture2D, display_name: String, logged_in: bool) -> void:
	_avatar = avatar
	_logged_in = logged_in
	_account_text = (tr(LOGGED_IN_FORMAT) % display_name) if logged_in else tr(LOGGED_OUT_TEXT)
	if _login != null:
		var caption: Label = _login.get_node_or_null("Caption")
		if caption != null:
			caption.text = tr(LOGOUT_TEXT) if logged_in else tr(LOGIN_TEXT)
		# 글자 길이가 바뀌었으니 버튼 안쪽 배치를 다시 맞춘다.
		_layout()
	if _account != null:
		_account.queue_redraw()


func _draw_sliders() -> void:
	_draw_slider_labels(_sliders,
		[[tr("SFX"), _sfx_icon], [tr("MUSIC"), _music_icon]],
		int(round(_panel_rect.size.x * SLIDER_LABEL_FRAC)),
		_sliders.get_meta("row_h", 30.0), _sliders.get_meta("gap", 8.0))


# 슬라이더와 같은 이름표 그리기를 한 줄짜리로 재사용한다 — 아이콘이 없으니
# 글자만 나가고, 세로 중심 계산이 같아 SFX/MUSIC 과 줄이 맞는다.
func _draw_language_row() -> void:
	_draw_slider_labels(_language_row, [[tr(LANGUAGE_ROW_LABEL), null]],
		int(round(_panel_rect.size.x * SLIDER_LABEL_FRAC)), _language_row.size.y, 0.0)


func _draw_boost_row() -> void:
	_draw_slider_labels(_boost_row, [[tr(BOOST_ROW_LABEL), null]],
		int(round(_panel_rect.size.x * SLIDER_LABEL_FRAC)), _boost_row.size.y, 0.0)


## 어느 쪽이 켜져 있는지 표시만 바꾼다 — 신호는 보내지 않는다. Main 이 저장된
## 값을 넣어 줄 때와, 사용자가 눌렀을 때 둘 다 여기를 지난다.
## Main 이 저장된 값을 넣어 준다. 토글만 맞추고 신호는 안 쏜다 — 쏘면
## 값을 되돌리는 것이 다시 바꾸라는 요청으로 돌아온다.
func set_language(korean: bool) -> void:
	_korean = korean
	if _language_toggle != null:
		_set_side_toggle(_language_toggle, korean)


func set_boost_side(on_left: bool) -> void:
	_boost_on_left = on_left
	_set_side_toggle(_boost_toggle, not on_left)


# 동그란 프로필 자리 + 상태 글자. 그림이 아직 없으면 사람 모양 자리표시를 그린다.
func _draw_account() -> void:
	var h: float = _account.size.y
	var d: float = h * AVATAR_DIAMETER_FRAC
	var centre := Vector2(d * 0.5, h * 0.5)
	if _avatar != null:
		# 사진을 동그랗게 오려 넣는다. draw_texture_rect 는 네모로만 그려서,
		# 원 모양 다각형에 UV 를 물려 그린다.
		var steps := 48
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in range(steps):
			var a: float = TAU * i / steps
			var dir := Vector2(cos(a), sin(a))
			pts.append(centre + dir * d * 0.5)
			uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
		_account.draw_colored_polygon(pts, Color(1, 1, 1, 1), uvs, _avatar)
		_account.draw_arc(centre, d * 0.5 - AVATAR_EDGE_PX * 0.5, 0.0, TAU, 48,
			AVATAR_EDGE, AVATAR_EDGE_PX, true)
	else:
		_account.draw_circle(centre, d * 0.5, AVATAR_FILL)
		_account.draw_arc(centre, d * 0.5 - AVATAR_EDGE_PX * 0.5, 0.0, TAU, 48,
			AVATAR_EDGE, AVATAR_EDGE_PX, true)
		# 사람 모양: 머리 동그라미 + 어깨 호.
		_account.draw_circle(centre + Vector2(0.0, -d * 0.13), d * 0.16, AVATAR_GLYPH)
		_account.draw_arc(centre + Vector2(0.0, d * 0.34), d * 0.27, PI, TAU, 32,
			AVATAR_GLYPH, d * 0.13, true)
	var x: float = d + _panel_rect.size.x * ACCOUNT_GAP_FRAC
	# 남는 폭에 맞춰 줄인다 — 로그인하면 이름이 들어올 자리라, 길이가
	# 얼마가 되든 LOGIN 버튼을 밀거나 잘리지 않아야 한다.
	var room: float = maxf(10.0, _account.size.x - x)
	var font_size: int = int(round(_panel_rect.size.x * ACCOUNT_TEXT_SIZE_FRAC))
	while font_size > ACCOUNT_TEXT_MIN_SIZE \
			and _font_bold.get_string_size(_account_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		font_size -= 1
	_account.draw_string(_font_bold, Vector2(x, h * 0.5 + font_size * 0.36),
		_account_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ACCOUNT_TEXT_COLOR)


# 버전은 project.godot 의 application/config/version 한 곳에서만 나온다. APK 의
# versionName 도 (익스포트 프리셋의 version/name 을 비워 두면) 같은 설정을
# 물려받으므로, 버전을 올릴 때 고칠 곳이 하나다.
#
# 예전에는 이 줄이 "Version 1.0.0" 리터럴이었다. 그렇게 두면 버전을 올려도 이
# 줄만 옛 번호를 계속 말하는데, 빌드도 통과하고 화면도 멀쩡해 보인다 — 이미
# 고친 버그를 옛 번호와 함께 제보받고 나서야 알게 되는 종류다.
func _read_version_text() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if v.is_empty():
		# 그럴듯한 거짓말을 그리느니 비어 있는 것을 보인다.
		push_warning("application/config/version is empty — the settings popup has no version to show.")
		return tr("Version %s") % "?"
	return tr("Version %s") % v


# 판 맨 아래 가운데의 버전 표시.
func _draw_version() -> void:
	var font_size: int = int(round(_panel_rect.size.x * VERSION_SIZE_FRAC))
	var w: float = _font_bold.get_string_size(_version_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_version.draw_string(_font_bold,
		Vector2((_version.size.x - w) * 0.5, _version.size.y * 0.5 + font_size * 0.36),
		_version_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, VERSION_COLOR)


# 약관 한 줄: 왼쪽에 밑줄 친 글자, 오른쪽 끝에 ">".
func _draw_link(link: Button, index: int) -> void:
	var font_size: int = int(round(_panel_rect.size.x * LINK_TEXT_SIZE_FRAC))
	var text: String = tr(LINK_TEXTS[index])
	var baseline: float = link.size.y * 0.5 + font_size * 0.36
	link.draw_string(_font_bold, Vector2(0.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LINK_COLOR)
	var text_w: float = _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var uy: float = baseline + font_size * LINK_UNDERLINE_DROP
	link.draw_line(Vector2(0.0, uy), Vector2(text_w, uy), LINK_COLOR, LINK_UNDERLINE_PX, true)
	if index == LINK_MAIL_INDEX:
		_draw_mail(link, text_w + font_size * LINK_MAIL_GAP_FRAC,
			link.size.y * 0.5, font_size * LINK_MAIL_HEIGHT_FRAC)
	var chev_w: float = _font_bold.get_string_size(LINK_CHEVRON, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	link.draw_string(_font_bold, Vector2(link.size.x - chev_w, baseline), LINK_CHEVRON,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LINK_CHEVRON_COLOR)


# 봉투 아이콘. 아이콘 시트에 편지 그림이 없어서 선으로 직접 그린다 —
# 이 크기(12px 남짓)에서는 사각형 하나와 뚜껑 선 둘이면 편지로 읽힌다.
func _draw_mail(ctrl: Control, x: float, centre_y: float, h: float) -> void:
	var w: float = h * 1.45
	var r := Rect2(x, centre_y - h * 0.5, w, h)
	ctrl.draw_rect(r, LINK_CHEVRON_COLOR, false, LINK_MAIL_LINE_PX, true)
	ctrl.draw_line(r.position, r.position + Vector2(w * 0.5, h * 0.55),
		LINK_CHEVRON_COLOR, LINK_MAIL_LINE_PX, true)
	ctrl.draw_line(r.position + Vector2(w, 0.0), r.position + Vector2(w * 0.5, h * 0.55),
		LINK_CHEVRON_COLOR, LINK_MAIL_LINE_PX, true)


# 약관 줄을 눌렀을 때 어느 신호를 보낼지.
# 이 줄이 지금 눌러서 뜻이 있는가.
#
# 앞의 세 줄은 앱 밖으로 나가는데, 그 주소가 아직 scripts/ExternalLinks.gd 에
# 비어 있다. 눌러도 아무 일이 안 일어나는 링크를 멀쩡한 얼굴로 두면 고장으로
# 읽히므로, 주소가 없으면 흐리게 그리고 누름도 받지 않는다. About 은 앱 안의
# 팝업이라 언제나 열린다.
func _link_enabled(index: int) -> bool:
	match index:
		0: return ExternalLinks.is_set(ExternalLinks.PRIVACY_POLICY_URL)
		1: return ExternalLinks.is_set(ExternalLinks.TERMS_OF_SERVICE_URL)
		2: return ExternalLinks.is_set(ExternalLinks.CONTACT_EMAIL)
		_: return true


func _on_link_pressed(index: int) -> void:
	if not _link_enabled(index):
		return
	match index:
		0: privacy_pressed.emit()
		1: terms_pressed.emit()
		2: contact_pressed.emit()
		_: about_pressed.emit()


# 판 바깥을 누르면 닫는다.
func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed and not _panel_rect.has_point(event.position):
		close_pressed.emit()
