extends PopupBase

## 부활 제안 팝업. 게이트를 놓치면 게임오버 화면보다 먼저 이게 뜬다.
##
## 판 위로 "OOPS!" 아트가 걸터앉는다 — 판 안에 넣으면 그냥 제목이지만,
## 위로 튀어나오면 사고가 난 순간의 반응처럼 읽힌다.
##
## 판·버튼·글로우는 PopupBase가 맡는다. 여기에는 이 팝업만의 내용과
## 배치만 있다.

signal watch_ad_pressed
signal decline_pressed

const OOPS_FILE := "oops_popup.png"
# OOPS 아트가 판 위로 얼마나 걸터앉는가. 판 너비 대비 크기와, 자기 높이의
# 몇 할이 판 위로 나가는지.
const OOPS_WIDTH_FRAC := 0.86     # 판 너비 대비
const OOPS_OVERHANG := 0.55       # 자기 높이 중 판 위로 나가는 비율

# 캐릭터는 게임 화면에서 그려지던 크기 그대로 띄운다. Main이 넘겨 주지
# 않으면 이 값을 쓴다 (PLAYER_VISUAL_SIZE와 같은 수).
const SAD_FALLBACK_SIZE := 100.0
# 캐릭터가 제자리에서 아주 조금 떠오르내린다. 판이 멈춰 있어도 화면이 죽지
# 않고, 시선이 자연스럽게 캐릭터로 간다.
const SAD_BOB_PERIOD := 2.2       # 한 번 오르내리는 데 걸리는 초
const SAD_BOB_AMPLITUDE := 5.0    # 위아래로 흔들리는 폭(px)
const PROMPT_TEXT := "Continue your run?"
const PROMPT_SIZE_FRAC := 0.075   # 판 너비 대비

# 광고 버튼과 안내 상자는 다른 내용보다 좌우로 넓게 쓴다. 문구가 스무 자가
# 넘어서, 판 안쪽 여백에 맞추면 글자가 너무 작아진다.
const WIDE_FRAC := 0.86           # 판 너비 대비

const AD_BUTTON_TEXT := "WATCH AD TO CONTINUE"
# 아이콘이 들어갈 자리를 감안해 다른 팝업의 주 버튼보다 두툼하게 잡는다.
const AD_BUTTON_HEIGHT_FRAC := 0.185
# 광고 아이콘은 글자보다 크게. 문구가 길어 글자가 줄어드는 버튼이라, 아이콘
# 크기를 글자에 그대로 맡기면 두툼한 버튼 안에서 아이콘만 작아 보인다.
const AD_ICON_SCALE := 1.85
# 좌우 여백을 기본보다 좁혀 글자를 키운다. 모서리 곡률만 피하면 된다.
const AD_LABEL_FIT := 0.95

# 안내 상자 — 왼쪽 위에 아이콘, 그 오른쪽에 굵은 한 줄, 아래에 작은 설명.
const NOTE_BG_COLOR := Color(0.93, 0.90, 0.82, 1.0)
const NOTE_RADIUS := 12
const NOTE_PAD := 14.0            # 상자 안쪽 여백
const NOTE_ICON_FILE := "res://assets/ui_assets/popup/icon_information.png"
const NOTE_ICON_SCALE := 1.35     # 굵은 줄 글자 크기 대비 아이콘 높이
const NOTE_ICON_GAP_FRAC := 0.40  # 글자 크기 대비 아이콘-글자 간격
# 굵은 줄은 반드시 한 줄에 들어가야 한다. 이 크기에서 시작해 아이콘까지
# 합친 폭이 상자에 맞을 때까지 줄인다.
const NOTE_STRONG_MAX_FRAC := 0.068   # 판 너비 대비 상한
const NOTE_FONT_MIN := 9
const NOTE_BODY_RATIO := 0.78     # 굵은 줄 대비 아랫줄 크기
const NOTE_STRONG_TEXT := "Personal best is always saved"
# 이어 뛰어도 순위표는 지금 점수에서 멈춘다. "안 센다"가 아니라 "여기까지
# 센다"라고 적는다 — 이미 정직하게 번 점수는 그대로 인정되기 때문이다.
const NOTE_BODY_FORMAT := "Your Leaderboard score stays at %s."
const NOTE_LINE_GAP := 7.0

# 거절 링크 — 버튼이 아니라 글자로 두어, 광고 버튼과 무게를 확실히 벌린다.
const DECLINE_TEXT := "No thanks, end run"
const DECLINE_SIZE_FRAC := 0.055
const DECLINE_UNDERLINE_PX := 2.0

var _oops: TextureRect
var _sad: TextureRect
var _prompt: Label
var _ad_button: Button
var _note: Control
var _decline: Button
var _note_icon: Texture2D
# 안내 상자의 치수는 _measure_note가 한 번에 계산해 여기에 담아 둔다.
# _draw_note는 그린 값을 다시 재지 않고 이걸 그대로 쓴다.
var _note_strong_fs := 0
var _note_body_fs := 0
var _note_icon_size := Vector2.ZERO
var _note_text_x := 0.0
var _note_line_h := 0.0
# 게임 화면에서 캐릭터를 그리던 크기. Main이 모드를 불러올 때 넘겨 준다.
var _sad_draw_size := SAD_FALLBACK_SIZE
# 레이아웃이 잡아 준 캐릭터의 제자리. 흔들림은 여기서부터 위아래로만 더한다 —
# 매 프레임 position을 직접 누적하면 조금씩 떠내려간다.
var _sad_rest_y := 0.0
# 이어 뛰어도 순위표에 남는 점수. Main이 넣어 준다.
var _leaderboard_score := 0
var _logged_in := false


# 캐릭터를 제자리에서 아주 조금 띄웠다 내린다. 글로우는 부모가 계속 돌려야
# 하므로 super를 먼저 부른다.
func _process(delta: float) -> void:
	super._process(delta)
	if not visible or _sad == null:
		return
	_sad.position.y = _sad_rest_y + sin(_elapsed / SAD_BOB_PERIOD * TAU) * SAD_BOB_AMPLITUDE


func panel_size_frac() -> Vector2:
	# 일시정지 팝업보다 크게 — 담을 것이 많고, 판이 끝난 순간이라 화면을 더
	# 차지해도 방해가 아니라 주목이 된다.
	return Vector2(0.95, 0.70)


## 판이 넓어진 만큼 텍스처도 넉넉히 — 표시 폭보다 작게 줄여 두면 9-slice가
## 도로 확대되면서 테두리가 흐려진다.
func panel_texture_width() -> int:
	return 470


func panel_center_y_frac() -> float:
	# OOPS가 판 위로 튀어나오므로 판을 살짝 내려 머리 공간을 만든다.
	return 0.52


func _build_content() -> void:
	_sad = TextureRect.new()
	_sad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sad.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sad)

	_prompt = _make_label(PROMPT_TEXT, _font_bold)
	add_child(_prompt)

	_ad_button = _make_button(GOLD_FILE, GOLD_CORNER, AD_BUTTON_TEXT, _load_popup_icon(POPUP_ICON_AD), true)
	_ad_button.pressed.connect(func(): watch_ad_pressed.emit())
	add_child(_ad_button)

	_note_icon = _load_icon_from(NOTE_ICON_FILE, Vector2i(1, 1), 0)
	_note = Control.new()
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.draw.connect(_draw_note)
	add_child(_note)

	# 링크처럼 보이지만 실제로는 버튼 — 탭 영역이 글자만큼은 되어야 한다.
	_decline = Button.new()
	_decline.flat = true
	_decline.focus_mode = Control.FOCUS_NONE
	_decline.pressed.connect(func(): decline_pressed.emit())
	var caption := _make_label(DECLINE_TEXT, _font_bold)
	caption.name = "Caption"
	_decline.add_child(caption)
	var underline := Control.new()
	underline.name = "Underline"
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underline.draw.connect(_draw_underline)
	_decline.add_child(underline)
	add_child(_decline)

	# OOPS는 판보다 위에 그려져야 하므로 마지막에 붙인다.
	_oops = TextureRect.new()
	_oops.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_oops.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_oops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oops.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_oops.texture = _load_oops()
	add_child(_oops)


# OOPS 아트도 알파 없이 흰 배경으로 저장되어 있다 (_strip_white_background 참고).
func _load_oops() -> Texture2D:
	var path: String = ART_DIR + OOPS_FILE
	if not ResourceLoader.exists(path):
		push_warning("OOPS 아트 없음: %s" % path)
		return null
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	_strip_white_background(img)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 이어 뛰어도 순위표에 남는 점수 — 지금까지 번 점수다.
##
## 로그인하지 않았으면 순위표 자체가 없으므로 그 줄은 띄우지 않는다.
func set_leaderboard_score(value: int, logged_in: bool) -> void:
	_leaderboard_score = value
	_logged_in = logged_in
	_layout()


# 안내 상자 아랫줄. 점수가 들어가므로 상수가 아니라 그때그때 만든다.
# 로그인 전에는 빈 문자열 — 순위표에 올라간 적이 없는 사람에게 "당신의
# 순위표 점수"를 말해 봐야 무슨 소린지 알 수 없다. 상자는 굵은 한 줄만
# 남는다.
func _note_body_text() -> String:
	if not _logged_in:
		return ""
	return NOTE_BODY_FORMAT % _group(_leaderboard_score)


## 모드마다 다른 sad 표정을 Main이 넣어 준다.
##
## draw_size는 게임 화면에서 이 캐릭터를 그리던 크기(논리 px)다. 팝업도
## 같은 좌표계라 그대로 쓰면 크기가 정확히 일치한다. 모드마다 다르므로
## (드림 모드 유니콘은 1.2배) 팝업이 스스로 정하지 않고 받아 온다.
func set_character(texture: Texture2D, draw_size := 0.0) -> void:
	if _sad == null:
		return
	# 아트의 알파 경계가 딱딱해서 그대로 크게 띄우면 계단이 보인다.
	_sad.texture = _smoothed(texture)
	if draw_size > 0.0:
		_sad_draw_size = draw_size
	_layout()


# 위에서부터: 캐릭터 → 문구 → 광고 버튼 → 안내 상자 → 거절 링크.
# 거절 링크는 판 맨 아래에 붙이고, 나머지가 남는 공간을 나눠 갖는다.
func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var inner_x: float = inner.position.x
	var inner_w: float = inner.size.x
	var top: float = inner.position.y
	var bottom: float = inner.end.y

	# OOPS는 판 위쪽 테두리에 걸친다.
	if _oops.texture != null:
		var ow: float = pw * OOPS_WIDTH_FRAC
		var oh: float = ow * (float(_oops.texture.get_height()) / float(_oops.texture.get_width()))
		_oops.size = Vector2(ow, oh)
		_oops.position = Vector2(
			_panel_rect.position.x + (pw - ow) * 0.5,
			_panel_rect.position.y - oh * OOPS_OVERHANG)

	# 게임 화면과 같은 크기로. 판 비율에 맞춰 늘리지 않는다.
	var sad_h: float = _sad_draw_size
	var prompt_h: float = pw * PROMPT_SIZE_FRAC * 1.4
	var button_h: float = ph * AD_BUTTON_HEIGHT_FRAC
	# 광고 버튼과 안내 상자만 쓰는 넓은 폭.
	var wide_w: float = pw * WIDE_FRAC
	var wide_x: float = _panel_rect.position.x + (pw - wide_w) * 0.5
	var note_h: float = _measure_note(wide_w)
	var decline_h: float = pw * DECLINE_SIZE_FRAC * 1.6

	var used: float = sad_h + prompt_h + button_h + note_h + decline_h
	var gap: float = maxf(4.0, (bottom - top - used) / 4.0)

	var y := top
	# OOPS가 위를 덮으므로 캐릭터는 그 아래로 충분히 내려 둔다.
	var sad_w: float = sad_h
	if _sad.texture != null:
		sad_w = sad_h * (float(_sad.texture.get_width()) / float(_sad.texture.get_height()))
	_sad.size = Vector2(sad_w, sad_h)
	_sad_rest_y = y
	_sad.position = Vector2(inner_x + (inner_w - sad_w) * 0.5, y)
	y += sad_h + gap

	_prompt.position = Vector2(inner_x, y)
	_prompt.size = Vector2(inner_w, prompt_h)
	_prompt.add_theme_font_size_override("font_size", int(round(pw * PROMPT_SIZE_FRAC)))
	y += prompt_h + gap

	# 문구가 스무 자가 넘지만 _place가 아이콘까지 묶어 폭에 맞게 줄여 준다.
	_place(_ad_button, wide_x, y, wide_w, button_h, AD_ICON_SCALE, AD_LABEL_FIT,
		0.0, GOLD_CONTENT_DY)
	y += button_h + gap

	_note.position = Vector2(wide_x, y)
	_note.size = Vector2(wide_w, note_h)
	_note.queue_redraw()
	y += note_h + gap

	var dec_font: int = int(round(pw * DECLINE_SIZE_FRAC))
	var dec_w: float = _font_bold.get_string_size(DECLINE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, dec_font).x
	_decline.position = Vector2(inner_x + (inner_w - dec_w) * 0.5, bottom - decline_h)
	_decline.size = Vector2(dec_w, decline_h)
	var caption: Label = _decline.get_node("Caption")
	caption.position = Vector2.ZERO
	caption.size = Vector2(dec_w, decline_h)
	caption.add_theme_font_size_override("font_size", dec_font)
	var underline: Control = _decline.get_node("Underline")
	underline.position = Vector2.ZERO
	underline.size = Vector2(dec_w, decline_h)
	underline.set_meta("font_size", dec_font)
	underline.queue_redraw()


# 안내 상자의 높이. 두 줄이 각자 몇 줄로 접히는지까지 재야 상자가 글자를
# 자르지 않는다.
# 안내 상자의 치수를 한 번에 정하고 전체 높이를 돌려준다.
#
# 굵은 줄은 반드시 한 줄에 들어가야 한다는 것이 이 상자의 유일한 제약이다.
# 아이콘 크기도 그 글자 크기를 따라가므로, 아이콘까지 합친 폭이 상자에 맞을
# 때까지 글자를 한 단계씩 줄인다 — 버튼에서 쓰는 방식과 같다.
func _measure_note(width: float) -> float:
	var avail: float = width - NOTE_PAD * 2.0
	var aspect := 1.0
	if _note_icon != null:
		aspect = float(_note_icon.get_width()) / float(_note_icon.get_height())

	var fs: int = int(round(_panel_rect.size.x * NOTE_STRONG_MAX_FRAC))
	var icon_w := 0.0
	var gap := 0.0
	while true:
		icon_w = 0.0
		gap = 0.0
		if _note_icon != null:
			icon_w = fs * NOTE_ICON_SCALE * aspect
			gap = fs * NOTE_ICON_GAP_FRAC
		var strong_w: float = _font_bold.get_string_size(
			NOTE_STRONG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if fs <= NOTE_FONT_MIN or icon_w + gap + strong_w <= avail:
			break
		fs -= 1

	_note_strong_fs = fs
	_note_body_fs = maxi(NOTE_FONT_MIN, int(round(fs * NOTE_BODY_RATIO)))
	_note_icon_size = Vector2(icon_w, fs * NOTE_ICON_SCALE)
	_note_text_x = NOTE_PAD + icon_w + gap
	# 첫 줄이 차지하는 높이 — 아이콘이 글자보다 크므로 둘 중 큰 쪽.
	_note_line_h = maxf(fs * 1.25, _note_icon_size.y)

	if _note_body_text() == "":
		return NOTE_PAD * 2.0 + _note_line_h
	var body_h: float = _font_bold.get_multiline_string_size(
		_note_body_text(), HORIZONTAL_ALIGNMENT_LEFT,
		width - NOTE_PAD - _note_text_x, _note_body_fs).y
	return NOTE_PAD * 2.0 + _note_line_h + NOTE_LINE_GAP + body_h


# 왼쪽 위에 아이콘, 그 오른쪽에 굵은 한 줄, 그 아래에 작은 설명.
# 설명은 굵은 줄과 같은 x에서 시작한다 — 아이콘 아래로 흘려보내면 아이콘이
# 첫 줄에만 붙은 표시처럼 보여서, 상자 전체가 한 덩어리로 읽히지 않는다.
func _draw_note() -> void:
	var w: float = _note.size.x
	var h: float = _note.size.y
	var style := StyleBoxFlat.new()
	style.bg_color = NOTE_BG_COLOR
	style.set_corner_radius_all(NOTE_RADIUS)
	style.anti_aliasing = true
	_note.draw_style_box(style, Rect2(Vector2.ZERO, Vector2(w, h)))

	var line_mid: float = NOTE_PAD + _note_line_h * 0.5
	if _note_icon != null:
		_note.draw_texture_rect(_note_icon, Rect2(
			Vector2(NOTE_PAD, line_mid - _note_icon_size.y * 0.5), _note_icon_size), false)
	# draw_string은 베이스라인 기준이라, 대문자 높이의 절반만큼 내려야
	# 글자 가운데가 아이콘 가운데와 맞는다.
	_note.draw_string(_font_bold, Vector2(_note_text_x, line_mid + _note_strong_fs * 0.35),
		NOTE_STRONG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _note_strong_fs, INK)
	var body := _note_body_text()
	if body == "":
		return
	_note.draw_multiline_string(_font_bold,
		Vector2(_note_text_x, NOTE_PAD + _note_line_h + NOTE_LINE_GAP + _note_body_fs),
		body, HORIZONTAL_ALIGNMENT_LEFT,
		w - NOTE_PAD - _note_text_x, _note_body_fs, -1, INK)


func _draw_underline() -> void:
	var underline: Control = _decline.get_node("Underline")
	var font_size: int = underline.get_meta("font_size", 14)
	var w: float = underline.size.x
	var h: float = underline.size.y
	# 글자 아래로 살짝 띄운다 — 디센더에 닿으면 지저분해 보인다.
	var y: float = h * 0.5 + font_size * 0.46
	underline.draw_rect(Rect2(Vector2(0.0, y), Vector2(w, DECLINE_UNDERLINE_PX)), INK)
