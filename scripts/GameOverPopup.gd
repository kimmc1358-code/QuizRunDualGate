extends PopupBase

## 게임오버 팝업.
##
## 부활 제안을 거절하면 이게 뜬다. 판 위로 "TRY AGAIN!" 아트가 걸터앉고,
## 판 안은 위에서부터 신기록 리본 → 로그인 유도 → 점수 → 최대 콤보 →
## 버튼들 순서다.
##
## 판·버튼·글로우는 PopupBase가 맡는다. 여기에는 이 팝업만의 내용과
## 배치만 있다.
##
## 신기록이냐 아니냐로 맨 윗줄만 갈라진다. 신기록이면 트로피와 리본,
## 아니면 넘어야 할 기록을 적은 판. 나머지 줄은 그대로다 — 두 화면이 아주
## 달라 보이면 "졌다"는 느낌이 화면 전환으로까지 번진다.
##
## 로그인 여부는 가운데 안내 상자와 왼쪽 크림 버튼만 바꾼다. 로그인했으면
## "순위표에 올라갔다"는 확인, 아니면 로그인 유도다. 네 가지 조합이지만
## 화면은 한 벌이고 두 곳만 갈린다.

signal play_again_pressed
signal login_pressed
signal leaderboard_pressed
signal share_pressed
signal home_pressed

const TRYAGAIN_FILE := "tryagain_popup.png"
# TRY AGAIN 아트가 판 위로 얼마나 걸터앉는가 — OOPS와 같은 방식.
const TRYAGAIN_WIDTH_FRAC := 0.82   # 판 너비 대비
const TRYAGAIN_OVERHANG := 0.58     # 자기 높이 중 판 위로 나가는 비율

# ---- 맨 윗줄: 리본 위에 트로피와 캐릭터가 올라탄다 ----
# 리본은 판 테두리에 닿을 만큼 넓게 편다. 트로피와 캐릭터는 그 양 끝에
# 겹쳐 놓는다 — 옆에 나란히 세우면 리본이 그만큼 좁아진다.
const RIBBON_FILE := "res://assets/ui_assets/popup/popup_best.png"
const RIBBON_WIDTH_FRAC := 0.95     # 판 너비 대비 — 리본 끝이 판 테두리에 살짝 걸친다
const RIBBON_TEXTURE_HEIGHT := 320  # 미리 줄여 둘 높이(px)
const BEST_TEXT := "NEW BEST!"
# 글자는 트로피와 캐릭터 사이에 남는 폭에 맞춰 줄인다. 리본 높이만 보고
# 정하면 양 끝 그림에 물린다.
const BEST_TEXT_MAX_FRAC := 0.44    # 리본 높이 대비 상한
const BEST_TEXT_MIN := 12
const BEST_TEXT_SIDE_PAD := 4.0     # 양 끝 그림과 글자 사이 최소 간격
# 글자는 리본 띠의 휨을 그대로 따라간다.
#
# 띠는 양 끝보다 가운데가 위로 휘어 있어서, 곧게 쓴 글자를 얹으면 가운데는
# 띠 위로 뜨고 양 끝은 띠 아래로 빠진다. 그래서 아트를 세로로 훑어 띠의
# 중심선을 재 두고(_measure_ribbon_curve), 글자를 한 자씩 그 선 위에 얹으며
# 그 지점의 기울기만큼 돌린다. 리본 그림이 바뀌어도 저절로 따라간다.
const RIBBON_CURVE_SAMPLES := 65    # 중심선을 몇 군데서 잴지
const BEST_TEXT_Y_NUDGE := 0.02     # 리본 높이 대비 미세 조정(양수면 아래로)

const TROPHY_FILE := "res://assets/ui_assets/popup/icon_trophy.png"
const TROPHY_HEIGHT_FRAC := 0.62    # 리본 높이 대비 — 위아래로 살짝 넘친다
const TROPHY_TEXTURE_HEIGHT := 260
# 트로피가 밑동을 축으로 좌우로 갸웃거린다. 캐릭터는 위아래로 움직이므로
# 서로 다른 결로 움직여야 둘이 같이 흔들리는 것처럼 보이지 않는다.
const TROPHY_SWAY_PERIOD := 1.7     # 한 번 갔다 오는 데 걸리는 초
const TROPHY_SWAY_DEGREES := 5.5    # 좌우로 기우는 각도
const TROPHY_PIVOT_FRAC := 0.86     # 트로피 높이 중 회전축이 오는 위치(밑동)

# 캐릭터는 게임 화면에서 그리던 크기 그대로. Main이 넘겨 준다.
const CHARACTER_FALLBACK_SIZE := 100.0

# 트로피와 캐릭터는 리본 양 끝에서 같은 거리에 둔다. 둘의 폭이 달라서
# "중심 위치"로 잡으면 바깥 여백이 어긋나므로, 바깥쪽 모서리를 기준으로
# 잡는다.
#
# 리본 텍스처에는 둘레에 투명 여백이 들어 있어(PopupBase의 ICON_PAD_FRAC),
# 그려지는 사각형은 눈에 보이는 리본보다 조금 크다. 이 값은 그 여백만큼이라,
# 트로피와 캐릭터의 바깥쪽 모서리가 리본의 실제 끝과 나란히 선다.
const EDGE_INSET_FRAC := 0.012      # 리본 너비 대비
const CHARACTER_BOB_PERIOD := 2.2
const CHARACTER_BOB_AMPLITUDE := 5.0

# ---- 정보 상자 두 개 ----
# 한 줄짜리 둥근 상자. 로그인 유도는 하늘색, 최대 콤보는 부활 팝업의 안내
# 상자와 같은 크림색 — 같은 모양이되 성격이 다르다는 걸 색으로 가른다.
const LOGIN_BOX_COLOR := Color(0.72, 0.87, 0.97, 1.0)
const COMBO_BOX_COLOR := Color(0.93, 0.90, 0.82, 1.0)
const BOX_RADIUS := 14
const LOGIN_BOX_HEIGHT_FRAC := 0.058   # 판 높이 대비
const COMBO_BOX_HEIGHT_FRAC := 0.082   # 성적이라 조금 두툼하게
const BOX_PAD := 14.0               # 상자 안쪽 좌우 여백
const BOX_ICON_HEIGHT_FRAC := 1.55  # 글자 크기 대비 아이콘 높이
const BOX_ICON_GAP_FRAC := 0.62     # 글자 크기 대비 아이콘-글자 간격
const LOGIN_TEXT_FRAC := 0.043      # 판 너비 대비 — 안내 문구라 작게
const BOX_TEXT_MIN := 9             # 더 줄이면 읽히지 않는다
const COMBO_TEXT_FRAC := 0.057      # 판 너비 대비 — 성적이라 조금 크게

# icon_popup_2.png는 2칸짜리 — 왼쪽이 초록 체크, 오른쪽이 파란 자물쇠.
const STATUS_ICON_SHEET := "res://assets/ui_assets/popup/icon_popup_2.png"
const STATUS_ICON_GRID := Vector2i(2, 1)
const ICON_CHECK := 0
const ICON_LOCK := 1
# 안내 상자는 세 얼굴을 가진다.
#
#   로그인 전       파랑 + 자물쇠  — 순위표에 들어오라는 권유
#   기록 갱신       연두 + 체크    — 이 판이 순위표에 올라갔다
#   기록 미달성     연두 + 체크    — 내 기록은 이미 순위표에 있다
#   부활한 판       크림 + 느낌표  — 순위표는 첫 실수 지점에서 멈췄다
#
# 미달성일 때 "Saved to Leaderboard"라고 하면 안 된다. 순위표는 사람마다
# 최고 기록 한 줄만 두므로, 기록을 못 넘긴 판은 순위표를 바꾸지 않는다.
# 그렇게 적어 두면 순위표에 가 본 게이머는 방금 점수를 찾지 못한다.
const LOGIN_BOX_TEXT := "Login to join the Leaderboard!"
const SAVED_BOX_TEXT := "Saved to Leaderboard"
const STANDING_BOX_TEXT := "Your best is on the Leaderboard"
# 부활한 판에도 "안 셌다"가 아니라 "여기까지 셌다"라고 적는다.
const REVIVED_BOX_FORMAT := "Leaderboard kept your score at %s"
const SAVED_BOX_COLOR := Color(0.76, 0.92, 0.72, 1.0)   # 연두 — 잠김(파랑)과 대비되는 "됐다"
const REVIVED_BOX_COLOR := Color(0.93, 0.90, 0.82, 1.0) # 크림 — 좋지도 나쁘지도 않은 알림
const INFO_ICON_FILE := "res://assets/ui_assets/popup/icon_information.png"

# ---- 신기록이 아닐 때의 맨 윗줄 ----
# 리본 대신 "넘어야 할 숫자"를 적은 판을 가운데에 놓는다. 빈자리를 메우는 게
# 아니라, 다시하기 버튼을 누를 이유를 그 자리에 두는 것이다.
#
# 캐릭터는 이쪽에 나오지 않는다. 기록을 못 넘겼다고 우는 얼굴을 띄우면
# 판을 나무라는 화면이 된다.
const CROWN_FILE := "res://assets/ui_assets/popup/icon_crown.png"
# 배지 바탕은 전용 아트를 9-slice로 늘려 쓴다. 실루엣이 2148x555(약 3.9:1)로
# 배지 비율과 거의 같아서, 다른 9-slice들처럼 폭에 맞춰 줄여도 모서리 곡률이
# 그려진 대로 나온다.
const BEST_BOX_FILE := "best_box.png"
const BEST_BOX_CORNER := 91            # 원본의 모서리 곡률 반경(px)
const BEST_BOX_TEXTURE_WIDTH := 340    # 미리 줄여 둘 폭(논리 px). 가장 넓은 배지보다 조금 크게
const BEST_PLATE_HEIGHT_FRAC := 0.105  # 판 높이 대비 — 안내 상자들보다 두툼하게
# 판은 내용에 맞춰 폭이 정해지는 배지다. 좌우로 길게 늘이면 아래 안내
# 상자들과 구분이 안 되고, 한 줄짜리 정보에 비해 너무 크다.
const BEST_PLATE_PAD := 30.0           # 내용 양옆 여백
const BEST_PLATE_LABEL := "BEST"
const BEST_PLATE_TEXT_FRAC := 0.075    # 판 너비 대비 — 라벨과 숫자 모두
const BEST_PLATE_ICON_FRAC := 1.28     # 글자 크기 대비 왕관 높이
const BEST_PLATE_ICON_GAP_FRAC := 0.40

# 얼마나 모자랐는지 알려주는 한 줄. 아깝게 놓쳤을 때만 띄운다 — 최고 기록이
# 5,000인데 40점 내고 "4,960 남았다"가 뜨면 격려가 아니라 조롱이다.
const GAP_LINE_MIN_RATIO := 0.80       # 기록의 이 비율을 넘겼을 때만
const GAP_LINE_FORMAT := "%s to beat your best"
const GAP_LINE_FRAC := 0.048           # 판 너비 대비
const GAP_LINE_TOP := 6.0              # 점수 줄과의 간격

const FIRE_FILE := "res://assets/ui_assets/popup/icon_fire.png"
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
const PLAY_ICON_SCALE := 1.15
const PAIR_BUTTON_HEIGHT_FRAC := 0.082   # LOGIN WITH GOOGLE / SHARE
const PAIR_GAP_FRAC := 0.035             # 두 버튼 사이(판 너비 대비)
const PAIR_LABEL_FIT := 0.92
const HOME_BUTTON_HEIGHT_FRAC := 0.082
# 크림 버튼 셋의 아이콘은 같은 크기여야 한다. 글자 길이가 제각각이라
# (SHARE / HOME은 여유롭고 LOGIN WITH GOOGLE은 줄어든다) 아이콘을 글자
# 크기에 맡기면 셋의 크기가 어긋난다. 버튼 높이에서 직접 뽑는다.
const CREAM_ICON_HEIGHT_FRAC := 0.52     # 버튼 높이 대비
# 골드와 크림 사이는 다른 줄 간격보다 좁게 — 셋이 한 덩어리로 읽힌다.
const BUTTON_BLOCK_GAP := 8.0
# 골드 버튼 위아래로 똑같이 띄우는 간격. 주 동작 버튼이 콤보 상자와 크림
# 버튼 사이 한가운데에 놓이게 한다.
const PLAY_BUTTON_GAP := 14.0

const GOOGLE_FILE := "res://assets/ui_assets/popup/icon_google.png"
# 두 줄로 나눈다. 한 줄로 쓰면 옆 SHARE 버튼과 같은 폭에 스무 자를 욱여넣게
# 되어 글자가 지나치게 작아진다. 라벨은 가운데 정렬이라 GOOGLE이 저절로
# 윗줄 한가운데에 선다.
const GOOGLE_TEXT := "LOGIN WITH
GOOGLE"
# 로그인한 뒤에는 같은 버튼이 순위표로 가는 버튼이 된다.
const LEADERBOARD_TEXT := "LEADERBOARD"
const SHARE_TEXT := "SHARE"
const ICON_TROPHY := 3              # icon_sheet 윗줄 오른쪽에서 두 번째
const ICON_SHARE := 4               # icon_sheet 윗줄 가장 오른쪽

var _tryagain: TextureRect
var _character: TextureRect
var _top_row: Control
var _login_box: Control
var _score_row: Control
var _combo_box: Control
var _play_button: Button
var _google_button: Button
var _share_button: Button
var _home_button: Button

var _ribbon: Texture2D
var _trophy: Texture2D
var _lock: Texture2D
var _check: Texture2D
var _info: Texture2D
var _google_icon: Texture2D
var _trophy_icon: Texture2D
var _fire: Texture2D

# 레이아웃이 잡아 준 캐릭터의 제자리. 흔들림은 여기서부터 위아래로만 더한다 —
# 매 프레임 position을 직접 누적하면 조금씩 떠내려간다.
var _character_rest_y := 0.0
var _character_size := CHARACTER_FALLBACK_SIZE
var _score := 0
var _max_combo := 0
var _best := 0
var _is_new_record := true
var _logged_in := false
var _revived := false
var _leaderboard_score := 0
var _crown: Texture2D
var _best_plate: NinePatchRect
var _best_plate_rect := Rect2()
var _best_plate_font := 0
var _gap_line_font := 0

# 맨 윗줄 치수 — _layout_content가 재서 담아 두고 _draw_top_row가 쓴다.
var _ribbon_rect := Rect2()
# 리본 띠의 세로 중심선. 텍스처 높이 대비 비율을 가로로 균등하게 재 둔다.
var _ribbon_curve := PackedFloat32Array()
var _trophy_rect := Rect2()
var _best_font := 0
var _login_font := 0
var _combo_font := 0
var _score_label_font := 0
var _score_value_font := 0


# 캐릭터를 제자리에서 아주 조금 띄웠다 내린다. 글로우는 부모가 계속 돌려야
# 하므로 super를 먼저 부른다.
func _process(delta: float) -> void:
	super._process(delta)
	if not visible or _character == null:
		return
	_character.position.y = _character_rest_y + sin(
		_elapsed / CHARACTER_BOB_PERIOD * TAU) * CHARACTER_BOB_AMPLITUDE
	# 트로피가 흔들리므로 맨 윗줄은 매 프레임 다시 그려야 한다.
	if _top_row != null:
		_top_row.queue_redraw()


func panel_size_frac() -> Vector2:
	# 담을 것이 일곱 줄이라 팝업 중 가장 크다. 그래도 화면 끝까지 넓히지는
	# 않는다 — 판 둘레의 글로우가 퍼질 자리(약 22px)가 남아야 한다.
	return Vector2(0.90, 0.82)


func panel_center_y_frac() -> float:
	# TRY AGAIN이 판 위로 튀어나오므로 판을 살짝 내려 머리 공간을 만든다.
	return 0.54


func panel_texture_width() -> int:
	return 470


## 리본 위의 신기록 문구. 여섯 군데에서 쓰이는데 전부 같은 문자열이어야 한다 —
## 글자를 하나씩 휘어 그리는 코드가 섞여 있어, 한 군데라도 다른 문자열을 재면
## 글자 수와 그리는 자리가 어긋난다.
func _best_label() -> String:
	return tr(BEST_TEXT)


func _build_content() -> void:
	_ribbon = _load_icon_from(RIBBON_FILE, Vector2i(1, 1), 0, RIBBON_TEXTURE_HEIGHT)
	_measure_ribbon_curve()
	_trophy = _load_icon_from(TROPHY_FILE, Vector2i(1, 1), 0, TROPHY_TEXTURE_HEIGHT)
	_lock = _load_icon_from(STATUS_ICON_SHEET, STATUS_ICON_GRID, ICON_LOCK)
	_check = _load_icon_from(STATUS_ICON_SHEET, STATUS_ICON_GRID, ICON_CHECK)
	_info = _load_icon_from(INFO_ICON_FILE, Vector2i(1, 1), 0)
	_google_icon = _load_icon_from(GOOGLE_FILE, Vector2i(1, 1), 0)
	_trophy_icon = _load_icon(ICON_TROPHY)
	_fire = _load_icon_from(FIRE_FILE, Vector2i(1, 1), 0)
	_crown = _load_icon_from(CROWN_FILE, Vector2i(1, 1), 0)

	# 배지 바탕. _top_row보다 먼저 붙여야 왕관과 글자 아래에 깔린다.
	_best_plate = _nine_patch(BEST_BOX_FILE, BEST_BOX_CORNER,
		int(BEST_BOX_TEXTURE_WIDTH * UI_SUPERSAMPLE))
	_best_plate.visible = false
	add_child(_best_plate)

	# 리본·트로피·NEW BEST!는 서로 겹치는 한 덩어리라 하나의 캔버스에 직접
	# 그린다. 노드로 쪼개면 겹침 순서를 맞추기가 오히려 번거롭다.
	_top_row = Control.new()
	_top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_row.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_top_row.draw.connect(_draw_top_row)
	add_child(_top_row)

	# 캐릭터만 노드로 둔다 — 혼자 위아래로 흔들리기 때문이다.
	_character = TextureRect.new()
	_character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_character)

	_login_box = Control.new()
	_login_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_login_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_login_box.draw.connect(_draw_login_box)
	add_child(_login_box)

	_score_row = Control.new()
	_score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_row.draw.connect(_draw_score_row)
	add_child(_score_row)

	_combo_box = Control.new()
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_combo_box.draw.connect(_draw_combo_box)
	add_child(_combo_box)

	_play_button = _make_button(GOLD_FILE, GOLD_CORNER, tr(PLAY_BUTTON_TEXT),
		_load_popup_icon(POPUP_ICON_RESTART), true)
	_play_button.pressed.connect(func(): play_again_pressed.emit())
	add_child(_play_button)

	_google_button = _make_button(CREAM_FILE, CREAM_CORNER, GOOGLE_TEXT,
		_google_icon, false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_google_button.pressed.connect(_on_google_button_pressed)
	add_child(_google_button)

	_share_button = _make_button(CREAM_FILE, CREAM_CORNER, tr(SHARE_TEXT),
		_load_icon(ICON_SHARE), false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_share_button.pressed.connect(func(): share_pressed.emit())
	add_child(_share_button)

	_home_button = _make_button(CREAM_FILE, CREAM_CORNER, tr("HOME"),
		_load_icon(ICON_HOME), false, CREAM_GRADIENT, CREAM_TEXTURE_WIDTH)
	_home_button.pressed.connect(func(): home_pressed.emit())
	add_child(_home_button)

	# TRY AGAIN은 판보다 위에 그려져야 하므로 마지막에 붙인다.
	_tryagain = TextureRect.new()
	_tryagain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tryagain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tryagain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tryagain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tryagain.texture = _load_tryagain()
	add_child(_tryagain)


# TRY AGAIN 아트도 알파 없이 흰 배경으로 저장되어 있다
# (_strip_white_background 참고). 배경을 지우면 실루엣 둘레가 알파 0 아니면
# 1인 딱딱한 경계라, 줄여 그릴 때 계단이 진다 — _smoothed가 1px 경사를 만든다.
func _load_tryagain() -> Texture2D:
	var path: String = ART_DIR + TRYAGAIN_FILE
	if not ResourceLoader.exists(path):
		push_warning("TRY AGAIN 아트 없음: %s" % path)
		return null
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	_strip_white_background(img)
	img.generate_mipmaps()
	return _smoothed(ImageTexture.create_from_image(img))


## 이번 판의 결과를 Main이 넣어 준다.
##
## face는 신기록이면 happy, 아니면 sad 표정이다. Main이 골라 넘긴다 —
## 팝업은 어느 모드인지 모른다.
##
## logged_in은 가운데 안내 상자와 왼쪽 크림 버튼을 바꾼다.
##
## leaderboard_score는 첫 실수 전까지 도달한 점수다. score보다 낮으면
## 광고를 보고 이어 뛴 판이라는 뜻이라, 안내 상자가 그걸 알려 준다.
##
## draw_size는 게임 화면에서 이 캐릭터를 그리던 크기(논리 px)다. 팝업도 같은
## 좌표계라 그대로 쓰면 크기가 정확히 일치한다.
func set_result(face: Texture2D, draw_size: float, score: int, max_combo: int,
		best: int, is_new_record: bool, logged_in: bool, leaderboard_score: int) -> void:
	if _character != null:
		# 아트의 알파 경계가 딱딱해서 그대로 크게 띄우면 계단이 보인다.
		_character.texture = _smoothed(face)
	if draw_size > 0.0:
		_character_size = draw_size
	_score = score
	_max_combo = max_combo
	_best = best
	_is_new_record = is_new_record
	_logged_in = logged_in
	_leaderboard_score = leaderboard_score
	# 순위표에 남은 점수가 최종 점수보다 낮다면 광고를 보고 이어 뛴 판이다.
	_revived = leaderboard_score < score
	# 왼쪽 크림 버튼은 로그인 여부로 얼굴을 바꾼다. 글자 길이가 달라지므로
	# _layout()이 크기를 다시 재도록 그 전에 갈아끼운다.
	var caption: Label = _google_button.get_node("Caption")
	caption.text = tr(LEADERBOARD_TEXT) if logged_in else GOOGLE_TEXT
	var icon: TextureRect = _google_button.get_node("Icon")
	icon.texture = _trophy_icon if logged_in else _google_icon
	_layout()


# 위에서부터: 리본줄 → 로그인 상자 → 점수 → 콤보 상자 → PLAY AGAIN →
# (LOGIN WITH GOOGLE | SHARE) → HOME. 남는 세로 공간을 줄 사이에 고르게
# 나눠, 화면 비율이 달라져도 아래위가 붙거나 벌어지지 않는다.
func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var top: float = inner.position.y
	var bottom: float = inner.end.y

	# 버튼과 상자가 함께 쓰는 넓은 폭. 판 안쪽 여백보다 좌우로 조금 더 나간다.
	var wide_w: float = pw * WIDE_FRAC
	var wide_x: float = _panel_rect.position.x + (pw - wide_w) * 0.5

	_login_font = int(round(pw * LOGIN_TEXT_FRAC))
	_combo_font = int(round(pw * COMBO_TEXT_FRAC))
	_score_label_font = int(round(pw * SCORE_LABEL_FRAC))
	_score_value_font = int(round(pw * SCORE_VALUE_FRAC))

	# 맨 윗줄: 리본이 판 폭을 거의 다 쓰고, 트로피와 캐릭터가 그 위에 올라탄다.
	# 둘 다 리본보다 크므로 줄 높이는 그중 가장 큰 것이 정한다.
	var ribbon_w: float = pw * RIBBON_WIDTH_FRAC
	var ribbon_h: float = ribbon_w
	if _ribbon != null:
		ribbon_h = ribbon_w * (float(_ribbon.get_height()) / float(_ribbon.get_width()))
	var trophy_h: float = ribbon_h * TROPHY_HEIGHT_FRAC
	# 신기록이 아니면 리본도 캐릭터도 없으므로 배지 하나 높이면 된다.
	var top_row_h: float = maxf(ribbon_h, maxf(trophy_h, _character_size))
	if not _is_new_record:
		top_row_h = ph * BEST_PLATE_HEIGHT_FRAC

	var login_h: float = ph * LOGIN_BOX_HEIGHT_FRAC
	var combo_h: float = ph * COMBO_BOX_HEIGHT_FRAC
	_gap_line_font = int(round(pw * GAP_LINE_FRAC))
	var score_h: float = _score_value_font * 1.3
	if _gap_line_text() != "":
		score_h += GAP_LINE_TOP + _gap_line_font * 1.25
	var play_h: float = ph * PLAY_BUTTON_HEIGHT_FRAC
	var pair_h: float = ph * PAIR_BUTTON_HEIGHT_FRAC
	var home_h: float = ph * HOME_BUTTON_HEIGHT_FRAC

	# 골드 버튼 둘레(위아래)와 크림 두 줄 사이는 고정 간격이고, 남는 공간은
	# 위쪽 네 줄이 나눠 갖는다 — 간격 셋.
	var used: float = top_row_h + login_h + combo_h + score_h + play_h + pair_h + home_h
	var fixed: float = PLAY_BUTTON_GAP * 2.0 + BUTTON_BLOCK_GAP
	var gap: float = maxf(4.0, (bottom - top - used - fixed) / 3.0)

	var y := top

	# --- 맨 윗줄 ---
	_top_row.position = Vector2(_panel_rect.position.x + (pw - ribbon_w) * 0.5, y)
	_top_row.size = Vector2(ribbon_w, top_row_h)
	_ribbon_rect = Rect2(0.0, (top_row_h - ribbon_h) * 0.5, ribbon_w, ribbon_h)

	# 바깥쪽 모서리를 리본 양 끝에서 같은 거리에 놓는다 — 폭이 달라도
	# 좌우 여백이 정확히 같아진다.
	var edge: float = ribbon_w * EDGE_INSET_FRAC
	var trophy_w: float = trophy_h
	if _trophy != null:
		trophy_w = trophy_h * (float(_trophy.get_width()) / float(_trophy.get_height()))
	_trophy_rect = Rect2(edge, (top_row_h - trophy_h) * 0.5, trophy_w, trophy_h)

	var char_w: float = _character_size
	if _character.texture != null:
		char_w = _character_size * (float(_character.texture.get_width())
			/ float(_character.texture.get_height()))
	var char_left: float = ribbon_w - edge - char_w

	# 신기록이 아니면 리본 자리에 BEST 배지가 들어가고 캐릭터는 나오지 않는다.
	_character.visible = _is_new_record
	_best_plate.visible = not _is_new_record
	if not _is_new_record:
		_best_plate_font = int(round(pw * BEST_PLATE_TEXT_FRAC))
		var plate_w: float = minf(ribbon_w,
			_best_plate_group_width(_best_plate_font) + BEST_PLATE_PAD * 2.0)
		_best_plate_rect = Rect2(
			(ribbon_w - plate_w) * 0.5, 0.0, plate_w, top_row_h)
		# 바탕 노드는 _top_row가 아니라 팝업에 직접 붙어 있으므로 화면 좌표로.
		_best_plate.position = _best_plate_rect.position + Vector2(
			_panel_rect.position.x + (pw - ribbon_w) * 0.5, y)
		# 크게 만들고 되돌린다 — UI_SUPERSAMPLE 주석 참고.
		_best_plate.size = _best_plate_rect.size * UI_SUPERSAMPLE
		_best_plate.scale = Vector2.ONE / UI_SUPERSAMPLE
	_character.size = Vector2(char_w, _character_size)
	_character_rest_y = y + (top_row_h - _character_size) * 0.5
	_character.position = Vector2(_top_row.position.x + char_left, _character_rest_y)

	# NEW BEST!는 트로피와 캐릭터 사이에 남는 폭에 맞춰 줄인다.
	var text_room: float = char_left - _trophy_rect.end.x - BEST_TEXT_SIDE_PAD * 2.0
	_best_font = int(round(ribbon_h * BEST_TEXT_MAX_FRAC))
	while _best_font > BEST_TEXT_MIN and _font_heavy.get_string_size(
			_best_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, _best_font).x > text_room:
		_best_font -= 1
	_top_row.queue_redraw()
	y += top_row_h + gap

	# --- 로그인 유도 상자 ---
	_login_box.position = Vector2(wide_x, y)
	_login_box.size = Vector2(wide_w, login_h)
	_login_box.queue_redraw()
	y += login_h + gap

	# --- 점수 ---
	_score_row.position = Vector2(wide_x, y)
	_score_row.size = Vector2(wide_w, score_h)
	_score_row.queue_redraw()
	y += score_h + gap

	# --- 최대 콤보 상자 ---
	_combo_box.position = Vector2(wide_x, y)
	_combo_box.size = Vector2(wide_w, combo_h)
	_combo_box.queue_redraw()
	y += combo_h + PLAY_BUTTON_GAP

	# --- 버튼들 ---
	_place(_play_button, wide_x, y, wide_w, play_h, PLAY_ICON_SCALE,
		BUTTON_CONTENT_FIT, 0.0, GOLD_CONTENT_DY)
	y += play_h + PLAY_BUTTON_GAP

	# 두 버튼은 같은 크기로 좌우에 나란히. 아이콘 높이는 셋 다 같은 값으로
	# 못박는다 — 이유는 CREAM_ICON_HEIGHT_FRAC 주석 참고.
	var cream_icon: float = pair_h * CREAM_ICON_HEIGHT_FRAC
	var pair_gap: float = pw * PAIR_GAP_FRAC
	var pair_w: float = (wide_w - pair_gap) * 0.5
	_place(_google_button, wide_x, y, pair_w, pair_h, 1.0, PAIR_LABEL_FIT, cream_icon)
	_place(_share_button, wide_x + pair_w + pair_gap, y, pair_w, pair_h, 1.0, PAIR_LABEL_FIT, cream_icon)
	y += pair_h + BUTTON_BLOCK_GAP

	_place(_home_button, wide_x, y, wide_w, home_h, 1.0, BUTTON_CONTENT_FIT, cream_icon)

	# TRY AGAIN은 판 위쪽 테두리에 걸친다.
	if _tryagain.texture != null:
		var tw: float = pw * TRYAGAIN_WIDTH_FRAC
		var th: float = tw * (float(_tryagain.texture.get_height())
			/ float(_tryagain.texture.get_width()))
		_tryagain.size = Vector2(tw, th)
		_tryagain.position = Vector2(
			_panel_rect.position.x + (pw - tw) * 0.5,
			_panel_rect.position.y - th * TRYAGAIN_OVERHANG)


# 리본 아트를 세로로 훑어 띠의 중심선을 재 둔다. 각 표본은 그 세로줄에서
# 불투명한 구간의 한가운데를 텍스처 높이 대비 비율로 나타낸다.
#
# 리본은 양 끝이 뾰족한 꼬리라 거기서는 띠가 아니라 꼬리를 재게 되지만,
# 글자는 가운데 부분에만 놓이므로 문제되지 않는다.
func _measure_ribbon_curve() -> void:
	_ribbon_curve = PackedFloat32Array()
	if _ribbon == null:
		return
	var img: Image = _ribbon.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	var w := img.get_width()
	var h := img.get_height()
	for i in range(RIBBON_CURVE_SAMPLES):
		var x: int = int(round(float(i) / float(RIBBON_CURVE_SAMPLES - 1) * (w - 1)))
		var top := -1
		var bot := -1
		for y in range(h):
			if img.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bot = y
		_ribbon_curve.append(0.5 if top < 0 else (top + bot) * 0.5 / h)


# 리본 가로 위치 u(0~1)에서 띠 중심선의 높이(리본 높이 대비 비율).
func _curve_at(u: float) -> float:
	if _ribbon_curve.is_empty():
		return 0.5
	var t: float = clampf(u, 0.0, 1.0) * (_ribbon_curve.size() - 1)
	var i: int = int(floor(t))
	if i >= _ribbon_curve.size() - 1:
		return _ribbon_curve[_ribbon_curve.size() - 1]
	return lerpf(_ribbon_curve[i], _ribbon_curve[i + 1], t - i)


# 리본 → 그 위의 NEW BEST! → 왼쪽 끝에 올라탄 트로피 순서로 겹쳐 그린다.
# (캐릭터는 따로 흔들려야 해서 별도 노드다.)
func _draw_top_row() -> void:
	if not _is_new_record:
		_draw_best_plate()
		return
	if _ribbon != null:
		_top_row.draw_texture_rect(_ribbon, _ribbon_rect, false)
	_draw_best_text()
	_draw_trophy()


# 신기록이 아닐 때의 맨 윗줄: 왕관 + BEST + 넘어야 할 숫자.
#
# 왕관과 글자를 한 덩어리로 묶어 판 가운데에 놓는다. 왼쪽에 붙이면 넓은
# 판의 오른쪽이 통째로 비어 보인다.
func _draw_best_plate() -> void:
	# 바탕(_best_plate)은 9-slice 노드라 여기서는 내용만 그린다.
	var fs := _best_plate_font
	var value := _group(_best)
	var label_w: float = _font_bold.get_string_size(
		BEST_PLATE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_h: float = fs * BEST_PLATE_ICON_FRAC
	var icon_w := 0.0
	var icon_gap := 0.0
	if _crown != null:
		icon_w = icon_h * (float(_crown.get_width()) / float(_crown.get_height()))
		icon_gap = fs * BEST_PLATE_ICON_GAP_FRAC
	var text_gap: float = fs * 0.42
	var group_w: float = _best_plate_group_width(fs)
	var x: float = _best_plate_rect.position.x + (_best_plate_rect.size.x - group_w) * 0.5
	var centre_y: float = _best_plate_rect.position.y + _best_plate_rect.size.y * 0.5
	if _crown != null:
		_top_row.draw_texture_rect(_crown,
			Rect2(x, centre_y - icon_h * 0.5, icon_w, icon_h), false)
		x += icon_w + icon_gap
	# draw_string은 베이스라인 기준이라 대문자 높이의 절반만큼 내린다.
	var baseline: float = centre_y + fs * 0.35
	_top_row.draw_string(_font_bold, Vector2(x, baseline),
		BEST_PLATE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	_top_row.draw_string(_font_heavy, Vector2(x + label_w + text_gap, baseline),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


# 왕관 + BEST + 숫자를 합친 폭. 배지 크기를 정할 때와 그릴 때가 같은
# 값을 써야 내용이 가운데에 정확히 선다.
func _best_plate_group_width(fs: int) -> float:
	var w: float = _font_bold.get_string_size(
		BEST_PLATE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	w += fs * 0.42
	w += _font_heavy.get_string_size(
		_group(_best), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if _crown != null:
		var icon_h: float = fs * BEST_PLATE_ICON_FRAC
		w += icon_h * (float(_crown.get_width()) / float(_crown.get_height()))
		w += fs * BEST_PLATE_ICON_GAP_FRAC
	return w


# 기록까지 얼마나 모자랐는지. 아깝게 놓쳤을 때만 문구를 돌려주고, 아니면
# 빈 문자열이다 — 부르는 쪽은 이걸로 줄이 있는지 없는지 판단한다.
func _gap_line_text() -> String:
	if _is_new_record or _best <= 0 or _score >= _best:
		return ""
	if float(_score) < float(_best) * GAP_LINE_MIN_RATIO:
		return ""
	return GAP_LINE_FORMAT % _group(_best - _score)


# NEW BEST!를 리본의 휨을 따라 한 자씩 얹는다.
#
# 글자마다 제 위치의 중심선 높이로 내리고, 그 지점의 기울기만큼 돌린다.
# 한 자씩 그리지만 자리는 누적 문자열 폭으로 잡으므로 커닝은 그대로 살아 있다.
func _draw_best_text() -> void:
	if _best_font <= 0:
		return
	var ci := _top_row.get_canvas_item()
	var full_w: float = _font_heavy.get_string_size(
		_best_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, _best_font).x
	var start_x: float = _ribbon_rect.position.x + (_ribbon_rect.size.x - full_w) * 0.5
	# 기울기를 잴 때 쓸 아주 작은 가로 간격.
	var du: float = 1.0 / float(RIBBON_CURVE_SAMPLES - 1) * 0.5
	var prev_w := 0.0
	for i in range(_best_label().length()):
		var next_w: float = _font_heavy.get_string_size(
			_best_label().substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, _best_font).x
		var advance: float = next_w - prev_w
		var cx: float = start_x + (prev_w + next_w) * 0.5
		prev_w = next_w
		if _best_label()[i] == " ":
			continue
		var u: float = (cx - _ribbon_rect.position.x) / _ribbon_rect.size.x
		# 띠 중심 + 대문자 높이의 절반 = 베이스라인. draw_char는 베이스라인
		# 기준으로 그린다.
		var centre: float = (_curve_at(u) + BEST_TEXT_Y_NUDGE) * _ribbon_rect.size.y
		var baseline := Vector2(cx, _ribbon_rect.position.y + centre + _best_font * 0.35)
		# 화면 기울기 = 세로 변화량 / 가로 변화량. 둘 다 실제 픽셀로 환산한다.
		var dy: float = (_curve_at(u + du) - _curve_at(u - du)) * _ribbon_rect.size.y
		var dx: float = du * 2.0 * _ribbon_rect.size.x
		var angle: float = atan2(dy, dx)
		_top_row.draw_set_transform_matrix(Transform2D(angle, baseline))
		_font_heavy.draw_char(ci, Vector2(-advance * 0.5, 0.0),
			_best_label().unicode_at(i), _best_font, INK)
	_top_row.draw_set_transform_matrix(Transform2D.IDENTITY)


# 트로피가 밑동을 축으로 좌우로 갸웃거린다.
func _draw_trophy() -> void:
	if _trophy == null:
		return
	var angle: float = deg_to_rad(TROPHY_SWAY_DEGREES) * sin(
		_elapsed / TROPHY_SWAY_PERIOD * TAU)
	var pivot := Vector2(
		_trophy_rect.position.x + _trophy_rect.size.x * 0.5,
		_trophy_rect.position.y + _trophy_rect.size.y * TROPHY_PIVOT_FRAC)
	_top_row.draw_set_transform_matrix(Transform2D(angle, pivot))
	_top_row.draw_texture_rect(_trophy,
		Rect2(_trophy_rect.position - pivot, _trophy_rect.size), false)
	_top_row.draw_set_transform_matrix(Transform2D.IDENTITY)


# 둥근 상자 하나. 두 상자가 같은 함수를 쓰므로 모양이 어긋날 일이 없다.
func _draw_box(node: Control, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(BOX_RADIUS)
	style.anti_aliasing = true
	node.draw_style_box(style, Rect2(Vector2.ZERO, node.size))


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
	node.draw_string(_font_bold, Vector2(x, centre_y + font_size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


# 아이콘 + 간격 + 글자를 합친 폭.
func _box_row_width(icon: Texture2D, text: String, font_size: int) -> float:
	var w: float = _font_bold.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if icon != null:
		var ih: float = font_size * BOX_ICON_HEIGHT_FRAC
		w += ih * (float(icon.get_width()) / float(icon.get_height()))
		w += font_size * BOX_ICON_GAP_FRAC
	return w


# 자물쇠 + 문구를 한 덩어리로 묶어 상자 가운데에 놓는다.
func _draw_login_box() -> void:
	var colour := LOGIN_BOX_COLOR
	var icon := _lock
	var text := tr(LOGIN_BOX_TEXT)
	if _logged_in and _revived:
		# 로그인 전에는 부활 여부를 말해 봐야 소용이 없다 — 애초에 올라갈
		# 순위표가 없으니, 로그인 권유를 그대로 두는 편이 쓸모 있다.
		colour = REVIVED_BOX_COLOR
		icon = _info
		text = REVIVED_BOX_FORMAT % _group(_leaderboard_score)
	elif _logged_in:
		colour = SAVED_BOX_COLOR
		icon = _check
		text = tr(SAVED_BOX_TEXT) if _is_new_record else tr(STANDING_BOX_TEXT)
	_draw_box(_login_box, colour)
	# 상태마다 문구 길이가 꽤 다르다("Saved to Leaderboard"는 스무 자,
	# 부활 안내는 마흔 자가 넘는다). 상자에 들어올 때까지 글자를 줄인다.
	var fs := _login_font
	var room: float = _login_box.size.x - BOX_PAD * 2.0
	while fs > BOX_TEXT_MIN and _box_row_width(icon, text, fs) > room:
		fs -= 1
	var group_w: float = _box_row_width(icon, text, fs)
	_draw_box_row(_login_box, icon, text, fs,
		(_login_box.size.x - group_w) * 0.5)


# 왼쪽 크림 버튼은 상태에 따라 뜻이 다르므로 신호도 따로 보낸다.
func _on_google_button_pressed() -> void:
	if _logged_in:
		leaderboard_pressed.emit()
	else:
		login_pressed.emit()


# 왼쪽에 불꽃 + MAX COMBO, 오른쪽 끝에 값. 값을 라벨 바로 뒤에 붙이면 넓은
# 상자의 오른쪽이 통째로 비어 보인다.
func _draw_combo_box() -> void:
	_draw_box(_combo_box, COMBO_BOX_COLOR)
	_draw_box_row(_combo_box, _fire, tr(COMBO_LABEL), _combo_font, BOX_PAD)
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
	var label_w: float = _font_bold.get_string_size(
		tr(SCORE_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, _score_label_font).x
	var value := _group(_score)
	var value_w: float = _font_heavy.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _score_value_font).x
	var gap: float = _score_label_font * SCORE_GAP_FRAC
	var x: float = (_score_row.size.x - (label_w + gap + value_w)) * 0.5
	# 아랫줄이 붙으면 점수 줄은 그 몫을 뺀 위쪽 공간의 한가운데에 놓인다.
	var top_h: float = _score_row.size.y
	if extra != "":
		top_h -= GAP_LINE_TOP + _gap_line_font * 1.25
	var baseline: float = top_h * 0.5 + _score_value_font * 0.35
	_score_row.draw_string(_font_bold, Vector2(x, baseline),
		tr(SCORE_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, _score_label_font, INK)
	_score_row.draw_string(_font_heavy, Vector2(x + label_w + gap, baseline),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, _score_value_font, INK)
	if extra == "":
		return
	var ew: float = _font_bold.get_string_size(
		extra, HORIZONTAL_ALIGNMENT_LEFT, -1, _gap_line_font).x
	_score_row.draw_string(_font_bold,
		Vector2((_score_row.size.x - ew) * 0.5,
			top_h + GAP_LINE_TOP + _gap_line_font),
		extra, HORIZONTAL_ALIGNMENT_LEFT, -1, _gap_line_font, INK)
