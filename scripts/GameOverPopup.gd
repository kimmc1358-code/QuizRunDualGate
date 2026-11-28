extends PopupBase

## 게임오버 팝업.
##
## 하트를 다 잃으면 곧장 이게 뜬다(부활은 2026-11-28 에 뺐다). 판 위에 GAME OVER 가 얹히고,
## 판 안은 위에서부터 NEW BEST! 또는 BEST 머리글 → 점수 → 최대 콤보 →
## 이번 판의 스타더스트(광고 보고 2배) → PLAY AGAIN → HOME 순서다.
##
## 판·버튼은 PopupBase가 맡는다. 여기에는 이 팝업만의 내용과
## 배치만 있다.
##
## 신기록이냐 아니냐로 맨 윗줄만 갈라진다. 신기록이면 반짝이는 NEW BEST!,
## 아니면 넘어야 할 기록을 적은 머리글. 나머지 줄은 그대로다 — 두 화면이 아주
## 달라 보이면 "졌다"는 느낌이 화면 전환으로까지 번진다.
##
## 로그인과 순위표 이야기는 이 화면에 없다(2026-11-28 주인의 결정). 순위표
## 안내 상자("로그인하면 순위표에 오릅니다" / "최고 기록이 순위표에 있습니다")와
## LOGIN WITH GOOGLE·LEADERBOARD·SHARE 버튼이 있었다. 기록은 여전히 판이
## 끝날 때 순위표에 올라간다(Main._finish_run).

signal play_again_pressed
signal home_pressed
signal double_pressed

# 판 위에 크게 쓰는 제목(PopupBase._make_title / _place_title). 1.x 의 TRY AGAIN
# 그림 자리다. PLAY AGAIN 버튼이 바로 아래에서 같은 말을 하므로 제목은 GAME OVER.
const TITLE_TEXT := "GAME OVER"

# ---- 맨 윗줄 ----
# 다시 그렸다(2026-11-28, 주인): 신기록이 아니면 BEST 를 적은 판(메뉴 설명 줄 틀),
# 신기록이면 주황 리본 위에 트로피와 별이 올라타 흔들렸다. 판은 눌러야 할 버튼처럼
# 보였고, 리본 밖으로 튀어나온 트로피·별은 팝업에 녹지 않았다. 이제 둘 다 틀 없이
# 판에 바로 쓴 글자다 — 결과 줄이 판 안의 층이 된 것과 같은 까닭이다.
# 줄 높이는 두 경우가 같다. 아래 줄들이 신기록 여부로 들썩이지 않게.
const TOP_ROW_FRAC := 0.17              # 판 너비 대비
const BEST_TEXT := "NEW BEST!"
# 신기록: 제목(GAME OVER)과 같은 금색·테두리의 큰 글자, 뒤에 둥근 금빛, 양옆에
# 반짝이는 작은 별 둘. 별은 BEST 판에서 쓰던 키트의 별이다.
const NEW_BEST_FONT_FRAC := 0.10        # 판 너비 대비 — 넘치면 줄인다
const NEW_BEST_FILL := Color(1.0, 0.86, 0.45, 1.0)
const NEW_BEST_RIM := Color(0.20, 0.08, 0.0, 1.0)
const NEW_BEST_RIM_FRAC := 0.12         # 글자 크기 대비
const NEW_BEST_GLOW := Color(1.0, 0.72, 0.28, 0.32)
const NEW_BEST_GLOW_SIZE := Vector2(1.35, 2.6)   # 글자 폭·크기 대비
const SPARKLE_FRAC := 0.62              # 글자 크기(줄이기 전의 NEW_BEST_FONT_FRAC) 대비 별 높이
const SPARKLE_GAP_FRAC := 0.40          # 글자 크기 대비 별과 글자 사이
const SPARKLE_PERIOD := 1.6             # 초. 두 별은 함께 반짝인다 — 반 박자 어긋나게 했더니
                                        # 한 순간에 크기·밝기가 달라 서로 다른 별로 보였다
const SPARKLE_PULSE := 0.16             # 크기가 오르내리는 몫
# 신기록이 아니면: 넘어야 할 기록을 한 줄로. 별 + BEST + 숫자를 가운데에 두고 양옆에
# 바깥으로 옅어지는 가는 선을 그어, 판에 새긴 머리글처럼 읽히게 한다.
const CROWN_FILE := KIT + "icon_star.png"
# 번역 키다 — 영어로는 BEST, 한국어로는 "최고 기록"(ui.csv). "BEST" 를 그대로 키로 쓰지
# 않는 것은 그 낱말이 HUD 와 모드 카드에서 일부러 영어로 남아 있어서다(check_translations
# 의 ENGLISH_ON_PURPOSE). 한국어를 "신기록"으로 하지 않는 것은, 이 머리글이 기록을 못
# 넘긴 판에 뜨기 때문이다 — 새로 세운 기록은 NEW BEST!(최고 기록 경신!)의 몫이다.
const BEST_PLATE_LABEL := "Best record"
# BEST 한 낱말만 노랑 — HUD 와 모드 카드의 BEST 와 같은 색이라 셋이 같은 것을 가리킨다.
const BEST_PLATE_LABEL_FILL := Color(0.99, 0.80, 0.22, 1.0)
const BEST_PLATE_TEXT_FRAC := 0.058     # 판 너비 대비 — 라벨과 숫자 모두. 0.068 에서는 양옆 선이 점처럼 짧았다
const BEST_PLATE_ICON_GAP_FRAC := 0.40  # 글자 크기 대비
const BEST_LINE_COLOR := Color(0.35, 0.65, 0.95, 0.60)
const BEST_LINE_GAP_FRAC := 0.70        # 글자 크기 대비 — 글자 덩어리와 선 사이
const BEST_LINE_PX := 1.5

# ---- 정보 상자 ----
# 한 줄짜리 결과 상자 — 판 안에 깔린 층(_draw_box).
const ROW_FILL := Color(0.0, 0.015, 0.05, 0.55)       # 판 면보다 한 단 가라앉은 유리
const ROW_EDGE := Color(0.35, 0.65, 0.95, 0.30)       # 판 테두리의 파란 불을 옅게
const ROW_RADIUS := 8
const COMBO_BOX_HEIGHT_FRAC := 0.082   # 성적이라 조금 두툼하게
const BOX_PAD := 14.0               # 상자 안쪽 좌우 여백
const BOX_ICON_HEIGHT_FRAC := 1.55  # 글자 크기 대비 아이콘 높이
const BOX_ICON_GAP_FRAC := 0.62     # 글자 크기 대비 아이콘-글자 간격
const BOX_TEXT_MIN := 9             # 더 줄이면 읽히지 않는다
const COMBO_TEXT_FRAC := 0.057      # 판 너비 대비 — 성적이라 조금 크게



# 얼마나 모자랐는지 알려주는 한 줄. 아깝게 놓쳤을 때만 띄운다 — 최고 기록이
# 5,000인데 40점 내고 "4,960 남았다"가 뜨면 격려가 아니라 조롱이다.
const GAP_LINE_MIN_RATIO := 0.80       # 기록의 이 비율을 넘겼을 때만
const GAP_LINE_FORMAT := "%s to beat your best"
const GAP_LINE_FRAC := 0.048           # 판 너비 대비
const GAP_LINE_TOP := 6.0              # 점수 줄과의 간격

# 이번 판에 번 스타더스트와, 광고를 보고 그것을 한 번 더 받는 x2 (2026-11-27,
# 2.0 의 첫 보상형 광고 자리). 상자는 최대 콤보 상자 바로 아래, 버튼은 상자
# 오른쪽 안에 든다. 광고 제거를 산 사람에게는 광고 표시 없이 x2 만 뜬다.
const DUST_LABEL := "STARDUST"
const DOUBLE_TEXT := "x2"
const NO_AD_TEXT := "AD NOT READY"
const DUST_BOX_HEIGHT_FRAC := 0.082
const DUST_BUTTON_W_FRAC := 0.26        # 상자 폭 대비; 0.40 은 한국어 "스타더스트"와 숫자를 겹치게 했고, 0.32 는 Zen Dots 의 넓은 STARDUST 를 15px 까지 줄였다
const DUST_GOLD := Color(1.0, 0.78, 0.25, 1.0)         # 2배가 된 뒤 x2 글자
const FIRE_FILE := KIT + "icon_bolt.png"
const COMBO_LABEL := "MAX COMBO"

# ---- 점수 줄 ----
# 상자 바깥에 그냥 얹는 한 줄. 상자에 넣으면 세 칸이 똑같아 보여서
# 점수가 가장 중요한 숫자라는 게 드러나지 않는다.
const SCORE_LABEL := "SCORE"
const SCORE_LABEL_FRAC := 0.062     # 판 너비 대비
const SCORE_VALUE_FRAC := 0.105     # 숫자는 훨씬 크게 — 이 화면의 주인공
const SCORE_GAP_FRAC := 0.45        # 라벨 크기 대비 라벨-숫자 간격

# ---- 버튼 ----
const WIDE_FRAC := 0.86             # 판 너비 대비 — 버튼과 상자가 함께 쓰는 폭
# 골드 아트의 9-slice 모서리는 텍스처 픽셀 그대로 그려지므로, 버튼이 얇으면
# 위아래 모서리가 서로 물려 양 끝이 뭉개진다. 모서리 여백(66px, 슈퍼샘플
# 기준)의 두 배보다 넉넉히 높아야 한다.
const PLAY_BUTTON_HEIGHT_FRAC := 0.125
const PLAY_BUTTON_TEXT := "PLAY AGAIN"
const HOME_BUTTON_HEIGHT_FRAC := 0.082
# 이 줄에는 LOGIN WITH GOOGLE(로그인 뒤 LEADERBOARD)과 SHARE 가 나란히 있었다.
# 2026-11-28 주인의 결정으로 뺐다: 결과 화면은 x2·다시 하기·홈만 남긴다.
# 로그인은 설정과 메뉴의 사람 아이콘에, 순위표는 메뉴의 트로피에 있다.
# 골드 버튼 위아래로 똑같이 띄우는 간격. 주 동작 버튼이 콤보 상자와 크림
# 버튼 사이 한가운데에 놓이게 한다.
const PLAY_BUTTON_GAP := 14.0
# 스타더스트 줄과 콤보 상자 사이 — 다른 줄 간격보다 좁게, 둘이 한 덩어리로 읽힌다.
const BUTTON_BLOCK_GAP := 8.0

var _tryagain: Control
var _top_row: Control
var _score_row: Control
var _combo_box: Control
var _dust_box: Control
var _double_button: Button
var _dust_icon: Texture2D
var _dust := 0
var _dust_offer := false
var _dust_doubled := false
var _dust_no_ad := false
var _dust_ad_free := false
var _play_button: Button
var _home_button: Button

var _fire: Texture2D
var _score := 0
var _max_combo := 0
var _best := 0
var _is_new_record := true
var _crown: Texture2D
var _best_plate_font := 0
var _gap_line_font := 0

# 맨 윗줄 글자 크기 — _layout_content가 재서 담아 두고 _draw_top_row가 쓴다.
var _best_font := 0
# NEW BEST! 양옆 별의 높이. 글자 크기가 아니라 판 너비에서 — 영어는 넓어서 글자가 줄어드는데,
# 별까지 따라 줄면 한국어 화면의 별과 크기가 달라진다.
var _sparkle_h := 0.0
var _combo_font := 0
var _score_label_font := 0
var _score_value_font := 0


# 신기록 줄의 별이 반짝이므로 그 동안만 맨 윗줄을 매 프레임 다시 그린다. 시계
# (_elapsed)는 부모가 돌리므로 super를 먼저 부른다.
func _process(delta: float) -> void:
	super._process(delta)
	if visible and _is_new_record and _top_row != null:
		_top_row.queue_redraw()


const PANEL_MAX_H := 700.0   # 논리 px — 16:9 의 0.82 와 같은 높이
# 판 윗변이 내려와야 하는 가장 높은 자리(논리 px, 화면 위에서). 판 위에 GAME OVER 가
# 서는데, 그 위로는 게임 화면의 HUD(점수판·체력 칸·문제 상자·진행 막대)가 그대로
# 보인다 — 16:9 에서 제목이 그 위에 겹쳤다(2026-11-28, 주인). HUD 는 화면 위에 붙어
# 어느 비율에서나 같은 자리라, 진행 막대 밑(캡처로 잰 160)에 제목 높이(48)와 간격을
# 더한 값이다. HUD 를 옮기면 다시 잰다.
const PANEL_TOP_MIN := 222.0
const PANEL_BOTTOM_MARGIN := 16.0   # 판을 줄일 때 화면 아래와 남기는 간격
const PANEL_CENTER_FRAC := 0.54     # 걸리는 것이 없을 때 판 가운데의 높이(화면 높이 대비)


## 판의 윗변과 높이(논리 px). 높이는 PANEL_MAX_H 에서 멈춘다 — 줄 높이는 판 너비(곧
## 화면 너비)를 따라 어느 폰에서나 같은데, 판은 화면 높이를 따라 길어진다. 안내 상자와
## 버튼 한 줄이 빠진 뒤로(2026-11-28) 20:9 에서는 빈 간격만 커다랗게 남았다.
## 그렇게 놓은 판이 PANEL_TOP_MIN 보다 위로 올라가면(16:9), 판을 그 아래로 내리고 남는
## 화면만큼으로 줄인다. 줄 높이가 판 높이를 따르므로 내용도 함께 줄어든다.
func _panel_box() -> Vector2:
	var view_h: float = size.y if size.y > 0.0 else 854.0
	var h: float = minf(view_h * 0.82, PANEL_MAX_H)
	var top: float = view_h * PANEL_CENTER_FRAC - h * 0.5
	if top < PANEL_TOP_MIN:
		top = PANEL_TOP_MIN
		h = minf(h, view_h - PANEL_BOTTOM_MARGIN - top)
	return Vector2(top, h)


func panel_size_frac() -> Vector2:
	# 화면 끝까지 넓히지는 않는다 — 판 양옆에 바깥 화면이 조금은 보여야
	# 팝업으로 읽힌다.
	var view_h: float = size.y if size.y > 0.0 else 854.0
	return Vector2(0.90, _panel_box().y / view_h)


func panel_center_y_frac() -> float:
	var view_h: float = size.y if size.y > 0.0 else 854.0
	var box := _panel_box()
	return (box.x + box.y * 0.5) / view_h


func panel_texture_width() -> int:
	return 470


## 맨 윗줄의 신기록 문구 — 영어 NEW BEST!, 한국어 "최고 기록 경신!". 한국어는 "신기록!"
## 이었는데(2026-11-28 까지), 기록을 못 넘긴 화면의 "최고 기록" 과 낱말을 맞췄다(주인).
## 재는 쪽(_layout_content)과 그리는 쪽(_draw_new_best)이 같은 문자열을 쓰도록 한 곳에 둔다.
func _best_label() -> String:
	return tr(BEST_TEXT)


func _build_content() -> void:
	_fire = _load_icon_from(FIRE_FILE, Vector2i(1, 1), 0)
	_crown = _load_icon_from(CROWN_FILE, Vector2i(1, 1), 0)

	# 맨 윗줄(BEST 머리글 또는 NEW BEST!)은 한 캔버스에 직접 그린다.
	_top_row = Control.new()
	_top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_row.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_top_row.draw.connect(_draw_top_row)
	add_child(_top_row)

	_score_row = Control.new()
	_score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_row.draw.connect(_draw_score_row)
	add_child(_score_row)

	_combo_box = Control.new()
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_combo_box.draw.connect(_draw_combo_box)
	add_child(_combo_box)

	_dust_icon = ArtSlot.texture(ArtSlot.stardust_icon_path())
	_dust_box = Control.new()
	_dust_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dust_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_dust_box.draw.connect(_draw_dust_box)
	add_child(_dust_box)
	_double_button = _make_button(SMALL_GOLD_FILE, SMALL_CORNER, DOUBLE_TEXT,
		_load_popup_icon(POPUP_ICON_AD), true)
	_double_button.pressed.connect(func(): double_pressed.emit())
	add_child(_double_button)

	_play_button = _make_button(GOLD_FILE, GOLD_CORNER, tr(PLAY_BUTTON_TEXT),
		_load_popup_icon(POPUP_ICON_RESTART), true)
	_play_button.pressed.connect(func(): play_again_pressed.emit())
	add_child(_play_button)

	_home_button = _make_button(CREAM_FILE, CREAM_CORNER, tr("HOME"),
		_load_icon(ICON_HOME), false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_home_button.pressed.connect(func(): home_pressed.emit())
	add_child(_home_button)

	# 제목은 판보다 위에 그려져야 하므로 마지막에 붙인다.
	_tryagain = _make_title(TITLE_TEXT)
	add_child(_tryagain)


## 이번 판의 결과를 Main이 넣어 준다.
func set_result(score: int, max_combo: int, best: int, is_new_record: bool) -> void:
	_score = score
	_max_combo = max_combo
	_best = best
	_is_new_record = is_new_record
	_layout()


## 이번 판에 번 스타더스트. `offer` 면 x2 버튼을 띄우고, `ad_free` 면 광고
## 표시 없이 띄운다. 판마다 set_result 와 함께 부른다.
func set_stardust(amount: int, offer: bool, ad_free: bool) -> void:
	_dust = amount
	_dust_offer = offer
	_dust_doubled = false
	_dust_no_ad = false
	_dust_ad_free = ad_free
	_apply_double_face()
	_layout()


## 2배를 받았다: 버튼이 빠지고 숫자 옆에 금색 x2 가 붙는다.
func set_stardust_doubled() -> void:
	_dust_doubled = true
	_layout()


## 띄울 광고가 없었다: 버튼이 "광고 준비 중"으로 꺼진다. 이번 판에는 다시
## 누를 수 없다 — 몇 초 뒤 광고가 들어와도, 결과 화면을 붙잡고 기다리게
## 만들 까닭이 없다.
func set_double_unavailable() -> void:
	_dust_no_ad = true
	_apply_double_face()
	_layout()


func _apply_double_face() -> void:
	if _double_button == null:
		return
	var caption: Label = _double_button.get_node("Caption")
	caption.text = tr(NO_AD_TEXT) if _dust_no_ad else DOUBLE_TEXT
	var icon: TextureRect = _double_button.get_node("Icon")
	icon.texture = null if (_dust_ad_free or _dust_no_ad) else _load_popup_icon(POPUP_ICON_AD)
	_double_button.disabled = _dust_no_ad
	_double_button.modulate = Color(1, 1, 1, 0.55) if _dust_no_ad else Color.WHITE


# 위에서부터: 리본줄 → 점수 → 콤보 상자 → 스타더스트 →
# PLAY AGAIN → HOME. 남는 세로 공간을 줄 사이에 고르게
# 나눠, 화면 비율이 달라져도 아래위가 붙거나 벌어지지 않는다.
func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var top: float = inner.position.y
	var bottom: float = inner.end.y

	# 버튼과 상자가 함께 쓰는 넓은 폭. 판 안쪽 여백보다 좌우로 조금 더 나간다.
	var wide_w: float = pw * WIDE_FRAC
	var wide_x: float = _panel_rect.position.x + (pw - wide_w) * 0.5

	_combo_font = int(round(pw * COMBO_TEXT_FRAC))
	_score_label_font = int(round(pw * SCORE_LABEL_FRAC))
	_score_value_font = int(round(pw * SCORE_VALUE_FRAC))

	# 맨 윗줄 — 신기록이든 아니든 같은 높이.
	var top_row_h: float = pw * TOP_ROW_FRAC

	var combo_h: float = ph * COMBO_BOX_HEIGHT_FRAC
	_gap_line_font = int(round(pw * GAP_LINE_FRAC))
	var score_h: float = _score_value_font * 1.3
	if _gap_line_text() != "":
		score_h += GAP_LINE_TOP + _gap_line_font * 1.25
	var play_h: float = ph * PLAY_BUTTON_HEIGHT_FRAC
	var home_h: float = ph * HOME_BUTTON_HEIGHT_FRAC
	# 스타더스트 상자는 번 것이 있을 때만. 콤보 상자 밑에 붙어 간격 몫을 안 먹는다.
	var dust_h: float = ph * DUST_BOX_HEIGHT_FRAC if _dust > 0 else 0.0

	# 골드 버튼 둘레(위아래)와 크림 두 줄 사이는 고정 간격이고, 남는 공간은
	# 위쪽 줄들이 나눠 갖는다 — 간격 둘.
	var used: float = top_row_h + combo_h + dust_h + score_h + play_h + home_h
	var fixed: float = PLAY_BUTTON_GAP * 2.0 + (BUTTON_BLOCK_GAP if dust_h > 0.0 else 0.0)
	var gap: float = maxf(4.0, (bottom - top - used - fixed) / 2.0)

	var y := top

	# --- 맨 윗줄 ---
	_top_row.position = Vector2(wide_x, y)
	_top_row.size = Vector2(wide_w, top_row_h)
	_best_plate_font = int(round(pw * BEST_PLATE_TEXT_FRAC))
	# NEW BEST! 는 양옆 별 자리를 남기고 들어갈 때까지 줄인다.
	_best_font = int(round(pw * NEW_BEST_FONT_FRAC))
	_sparkle_h = pw * NEW_BEST_FONT_FRAC * SPARKLE_FRAC
	var best_font: Font = _caption_font(_best_label())
	while _best_font > 12 and best_font.get_string_size(_best_label(), HORIZONTAL_ALIGNMENT_LEFT, -1,
			_best_font).x + (_sparkle_h + _best_font * SPARKLE_GAP_FRAC) * 2.0 > wide_w * 0.92:
		_best_font -= 1
	_top_row.queue_redraw()
	y += top_row_h + gap

	# --- 점수 ---
	_score_row.position = Vector2(wide_x, y)
	_score_row.size = Vector2(wide_w, score_h)
	_score_row.queue_redraw()
	y += score_h + gap

	# --- 최대 콤보 상자 ---
	_combo_box.position = Vector2(wide_x, y)
	_combo_box.size = Vector2(wide_w, combo_h)
	_combo_box.queue_redraw()
	y += combo_h

	# --- 스타더스트 + x2 ---
	_dust_box.visible = dust_h > 0.0
	_double_button.visible = dust_h > 0.0 and _dust_offer and not _dust_doubled
	if dust_h > 0.0:
		y += BUTTON_BLOCK_GAP
		_dust_box.position = Vector2(wide_x, y)
		_dust_box.size = Vector2(wide_w, dust_h)
		_dust_box.queue_redraw()
		if _double_button.visible:
			var bw: float = wide_w * DUST_BUTTON_W_FRAC
			var bh: float = dust_h * 0.86
			_place(_double_button, wide_x + wide_w - bw - dust_h * 0.07, y + (dust_h - bh) * 0.5, bw, bh,
				BUTTON_CONTENT_FIT, GOLD_CONTENT_DY)
		y += dust_h

	y += PLAY_BUTTON_GAP

	# --- 버튼들 ---
	_place(_play_button, wide_x, y, wide_w, play_h, BUTTON_CONTENT_FIT, GOLD_CONTENT_DY)
	y += play_h + PLAY_BUTTON_GAP

	_place(_home_button, wide_x, y, wide_w, home_h)

	_place_title(_tryagain)


# 맨 윗줄: 신기록이면 NEW BEST!, 아니면 넘어야 할 BEST 머리글.
func _draw_top_row() -> void:
	if _is_new_record:
		_draw_new_best()
	else:
		_draw_best_header()


# 별 + BEST + 숫자를 가운데에 두고, 양옆에 바깥으로 옅어지는 가는 선을 긋는다.
# 별은 버튼 아이콘처럼 글자의 대문자 높이에 맞춘다(PopupBase.ICON_CAP_*).
func _draw_best_header() -> void:
	var fs: int = _best_plate_font
	var w: float = _top_row.size.x
	var h: float = _top_row.size.y
	var label: String = tr(BEST_PLATE_LABEL)
	var label_font: Font = _label_font(label)
	var value := _group(_best)
	var label_w: float = label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var value_w: float = _big_number_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gap: float = fs * BEST_PLATE_ICON_GAP_FRAC
	var cap: float = fs * ICON_CAP_LATIN
	var icon_h: float = cap * ICON_CAP_MATCH
	var icon_w := 0.0
	if _crown != null:
		icon_w = icon_h * float(_crown.get_width()) / float(_crown.get_height())
	var group_w: float = icon_w + gap + label_w + gap + value_w
	var x: float = (w - group_w) * 0.5
	var baseline: float = h * 0.5 + cap * 0.5
	if _crown != null:
		_top_row.draw_texture_rect(_crown, Rect2(x, baseline - cap * 0.5 - icon_h * 0.5, icon_w, icon_h), false)
	x += icon_w + gap
	_top_row.draw_string(label_font, Vector2(x, baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BEST_PLATE_LABEL_FILL)
	x += label_w + gap
	_top_row.draw_string(_big_number_font(), Vector2(x, baseline), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	# 양옆 선: 글자 덩어리 쪽이 진하고 판 가장자리 쪽으로 사라진다.
	var line_gap: float = fs * BEST_LINE_GAP_FRAC
	var left_end: float = (w - group_w) * 0.5 - line_gap
	var right_start: float = (w + group_w) * 0.5 + line_gap
	var ly: float = baseline - cap * 0.5
	var clear := Color(BEST_LINE_COLOR, 0.0)
	_draw_fade_line(Vector2(0.0, ly), Vector2(left_end, ly), clear, BEST_LINE_COLOR)
	_draw_fade_line(Vector2(right_start, ly), Vector2(w, ly), BEST_LINE_COLOR, clear)


func _draw_fade_line(a: Vector2, b: Vector2, ca: Color, cb: Color) -> void:
	if b.x - a.x < 2.0:
		return
	var t: float = BEST_LINE_PX * 0.5
	_top_row.draw_polygon(PackedVector2Array([a + Vector2(0, -t), b + Vector2(0, -t), b + Vector2(0, t), a + Vector2(0, t)]),
		PackedColorArray([ca, cb, cb, ca]))


# NEW BEST!: 금빛이 뒤에서 은은히 번지고, 제목과 같은 금색·테두리 글자 양옆에서 작은
# 별 둘이 함께 반짝인다. 한국어(최고 기록 경신!)는 Zen Dots 에 한글이 없어 기본
# 글꼴의 굵은 체로 쓴다(_caption_font).
func _draw_new_best() -> void:
	var fs: int = _best_font
	var text := _best_label()
	var font: Font = _caption_font(text)
	var w: float = _top_row.size.x
	var h: float = _top_row.size.y
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cap: float = fs * (ICON_CAP_HANGUL if font != _font_button else ICON_CAP_LATIN)
	var mid := Vector2(w * 0.5, h * 0.5)
	var gs := Vector2(tw * NEW_BEST_GLOW_SIZE.x, fs * NEW_BEST_GLOW_SIZE.y)
	_top_row.draw_texture_rect(_press_glow_texture(), Rect2(mid - gs * 0.5, gs), false, NEW_BEST_GLOW)
	var base := Vector2((w - tw) * 0.5, mid.y + cap * 0.5)
	_top_row.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		maxi(2, int(round(fs * NEW_BEST_RIM_FRAC))), NEW_BEST_RIM)
	_top_row.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NEW_BEST_FILL)
	if _crown == null:
		return
	var sh: float = _sparkle_h
	var sw: float = sh * float(_crown.get_width()) / float(_crown.get_height())
	var off: float = tw * 0.5 + fs * SPARKLE_GAP_FRAC + sw * 0.5
	for i in 2:
		var phase: float = _elapsed / SPARKLE_PERIOD * TAU
		var k: float = 1.0 + SPARKLE_PULSE * sin(phase)
		var c := Vector2(mid.x + (off if i == 1 else -off), mid.y)
		var s := Vector2(sw, sh) * k
		_top_row.draw_texture_rect(_crown, Rect2(c - s * 0.5, s), false,
			Color(1, 1, 1, 0.75 + 0.25 * sin(phase)))


## 크게 혼자 서는 숫자(게임오버 점수, BEST 의 값)의 글꼴 — 제목·이름표와 같은 Zen Dots
## (2026-11-28, 주인). 화면의 주인공인 숫자라 GAME OVER, SCORE, BEST 와 한 덩어리로 읽히고,
## 메뉴 카드의 BEST 숫자도 Zen Dots 라 둘의 모양이 같다. 작은 숫자(콤보, 스타더스트,
## 안내 문구 속 숫자)는 기본 글꼴(Oxanium) 그대로 — Zen Dots 숫자는 넓고 장식이 있어
## 좁은 자리와 작은 글자에서 덜 읽힌다. Oxanium 과 나란히 그려 보고 골랐다.
func _big_number_font() -> Font:
	return _font_button


# 기록까지 얼마나 모자랐는지. 아깝게 놓쳤을 때만 문구를 돌려주고, 아니면
# 빈 문자열이다 — 부르는 쪽은 이걸로 줄이 있는지 없는지 판단한다.
func _gap_line_text() -> String:
	if _is_new_record or _best <= 0 or _score >= _best:
		return ""
	if float(_score) < float(_best) * GAP_LINE_MIN_RATIO:
		return ""
	return tr(GAP_LINE_FORMAT) % _group(_best - _score)


# 결과 줄 하나. 버튼이 아니므로 버튼의 틀을 입지 않고 판 안에 깔린 층으로 그린다
# (2026-11-28, 주인 — 버튼과 같은 틀이라 눌러질 것처럼 보였다). 두 줄이 판보다 한 단
# 가라앉은 유리판 하나를 나눠 쓰고 사이에 가는 선을 긋는다 — 성적표 한 덩어리로 읽혀
# 아래 버튼들과 갈린다. 줄마다 띠를 깔고 왼쪽에 색 막대를 세운 안과 나란히 보고 골랐다.
func _draw_box(node: Control) -> void:
	var is_combo: bool = node == _combo_box
	var dust_on: bool = _dust_box != null and _dust_box.visible
	var w: float = node.size.x
	var h: float = node.size.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_FILL
	sb.anti_aliasing = true
	# 두 줄 사이 틈(BUTTON_BLOCK_GAP)을 반씩 메워 한 판으로 잇는다.
	var half: float = BUTTON_BLOCK_GAP * 0.5
	var r := Rect2(0.0, 0.0, w, h)
	sb.border_color = ROW_EDGE
	if is_combo:
		sb.border_width_top = 1
		sb.corner_radius_top_left = ROW_RADIUS
		sb.corner_radius_top_right = ROW_RADIUS
		if dust_on:
			r.size.y += half
		else:
			sb.border_width_bottom = 1
			sb.corner_radius_bottom_left = ROW_RADIUS
			sb.corner_radius_bottom_right = ROW_RADIUS
	else:
		r.position.y -= half
		r.size.y += half
		sb.border_width_bottom = 1
		sb.corner_radius_bottom_left = ROW_RADIUS
		sb.corner_radius_bottom_right = ROW_RADIUS
	sb.border_width_left = 1
	sb.border_width_right = 1
	node.draw_style_box(sb, r)
	if not is_combo:
		node.draw_line(Vector2(BOX_PAD, -half), Vector2(w - BOX_PAD, -half), ROW_EDGE, 1.0)


# 상자 안에 아이콘 + 글자를 한 줄로 그린다. start_x부터 오른쪽으로 흐른다.
# draw_string은 베이스라인 기준이라, 대문자 높이의 절반만큼 내려야 글자
# 가운데가 아이콘 가운데와 맞는다.
func _draw_box_row(node: Control, icon: Texture2D, text: String, font_size: int, start_x: float) -> void:
	var centre_y: float = node.size.y * 0.5
	var x: float = start_x
	if icon != null:
		var ih: float = font_size * BOX_ICON_HEIGHT_FRAC
		var iw: float = ih * (float(icon.get_width()) / float(icon.get_height()))
		node.draw_texture_rect(icon, Rect2(x, centre_y - ih * 0.5, iw, ih), false)
		x += iw + font_size * BOX_ICON_GAP_FRAC
	node.draw_string(_label_font(text), Vector2(x, centre_y + font_size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


# 아이콘 + 간격 + 글자를 합친 폭.
func _box_row_width(icon: Texture2D, text: String, font_size: int) -> float:
	var w: float = _label_font(text).get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if icon != null:
		var ih: float = font_size * BOX_ICON_HEIGHT_FRAC
		w += ih * (float(icon.get_width()) / float(icon.get_height()))
		w += font_size * BOX_ICON_GAP_FRAC
	return w


# 왼쪽에 불꽃 + MAX COMBO, 오른쪽 끝에 값. 값을 라벨 바로 뒤에 붙이면 넓은
# 상자의 오른쪽이 통째로 비어 보인다.
## 스타더스트 상자: 아이콘, STARDUST, +번 것. 2배를 받았으면 금색 x2 가
## 붙고 숫자도 두 배로 적힌다.
func _draw_dust_box() -> void:
	_draw_box(_dust_box)
	var fs: int = _combo_font
	var ls: int = _row_label_size()
	_draw_box_row(_dust_box, _dust_icon, tr(DUST_LABEL), ls, BOX_PAD)
	var right: float = _dust_right()
	var y: float = _dust_box.size.y * 0.5 + fs * 0.35
	if _dust_doubled:
		var xw: float = _font_heavy.get_string_size(DOUBLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_dust_box.draw_string(_font_heavy, Vector2(right - xw, y), DOUBLE_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DUST_GOLD)
		right -= xw + BOX_PAD * 0.5
	var value := _dust_value_text()
	var vw: float = _font_heavy.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_dust_box.draw_string(_font_heavy, Vector2(right - vw, y), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


func _dust_value_text() -> String:
	return "+%s" % ScoreFormat.grouped(_dust * (2 if _dust_doubled else 1))


# 스타더스트 줄에서 글자가 쓸 수 있는 오른쪽 끝 — x2 버튼이 있으면 그 앞까지.
func _dust_right() -> float:
	if _double_button != null and _double_button.visible:
		return _double_button.position.x - _dust_box.position.x - BOX_PAD * 0.6
	return _dust_box.size.x - BOX_PAD


## 두 결과 줄의 이름표(MAX COMBO, STARDUST) 크기. 숫자는 _combo_font 그대로 두고
## 이름표만, 스타더스트 줄에서 x2 버튼이 남긴 폭에 들어갈 때까지 줄인다. 두 줄이
## 같은 값을 써서 이름표 크기가 나란하다 — 스타더스트만 줄이면 Zen Dots 로 넓어진
## STARDUST 하나만 작아져 따로 놀았다. 그리는 순서와 상관없게 매번 같은 셈을 한다.
func _row_label_size() -> int:
	var ls: int = _combo_font
	if _dust_box == null or not _dust_box.visible:
		return ls
	var fs: int = _combo_font
	var right: float = _dust_right()
	var numbers: float = _font_heavy.get_string_size(_dust_value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if _dust_doubled:
		numbers += _font_heavy.get_string_size(DOUBLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + BOX_PAD * 0.5
	var label: String = tr(DUST_LABEL)
	while ls > BOX_TEXT_MIN and BOX_PAD + _box_row_width(_dust_icon, label, ls) + BOX_PAD * 0.8 + numbers > right:
		ls -= 1
	return ls


func _draw_combo_box() -> void:
	_draw_box(_combo_box)
	_draw_box_row(_combo_box, _fire, tr(COMBO_LABEL), _row_label_size(), BOX_PAD)
	var value := "x%d" % _max_combo
	var vw: float = _font_heavy.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font).x
	_combo_box.draw_string(_font_heavy,
		Vector2(_combo_box.size.x - BOX_PAD - vw, _combo_box.size.y * 0.5 + _combo_font * 0.35),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font, INK)


# SCORE + 숫자를 한 덩어리로 묶어 가운데에 맞춘다. 숫자가 라벨보다 훨씬
# 크므로, 둘의 밑선(베이스라인)을 맞춰야 한 줄로 읽힌다.
func _draw_score_row() -> void:
	var extra := _gap_line_text()
	var label_w: float = _label_font(tr(SCORE_LABEL)).get_string_size(
		tr(SCORE_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, _score_label_font).x
	var value := _group(_score)
	var value_w: float = _big_number_font().get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _score_value_font).x
	var gap: float = _score_label_font * SCORE_GAP_FRAC
	var x: float = (_score_row.size.x - (label_w + gap + value_w)) * 0.5
	# 아랫줄이 붙으면 점수 줄은 그 몫을 뺀 위쪽 공간의 한가운데에 놓인다.
	var top_h: float = _score_row.size.y
	if extra != "":
		top_h -= GAP_LINE_TOP + _gap_line_font * 1.25
	var baseline: float = top_h * 0.5 + _score_value_font * 0.35
	_score_row.draw_string(_label_font(tr(SCORE_LABEL)), Vector2(x, baseline),
		tr(SCORE_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, _score_label_font, INK)
	_score_row.draw_string(_big_number_font(), Vector2(x + label_w + gap, baseline),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _score_value_font, INK)
	if extra == "":
		return
	var ew: float = _font_bold.get_string_size(
		extra, HORIZONTAL_ALIGNMENT_LEFT, -1, _gap_line_font).x
	_score_row.draw_string(_font_bold,
		Vector2((_score_row.size.x - ew) * 0.5,
			top_h + GAP_LINE_TOP + _gap_line_font),
		extra, HORIZONTAL_ALIGNMENT_LEFT, -1, _gap_line_font, INK)
