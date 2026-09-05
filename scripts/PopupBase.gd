extends Control
class_name PopupBase

## 팝업들의 공통 바탕.
##
## 판·버튼·아이콘을 만드는 법, 골드 글로우, 팔레트, 눌림 동작처럼 모든
## 팝업이 똑같이 쓰는 것만 모아 둔다. 각 팝업(PausePopup, RevivePopup, …)은
## 이걸 상속해서 _build_content()에 자기 내용만 얹고 _layout_content()에서
## 배치한다.
##
## 판과 버튼은 9-slice(NinePatchRect)라 크기를 바꿔도 모서리가 뭉개지지
## 않는다. 다만 NinePatch는 모서리를 원본 픽셀 그대로 그리므로, 1024px짜리
## 원본을 380px 판에 그대로 쓰면 모서리만 거대해진다. 그래서 불러올 때
## 표시 크기로 미리 축소하고 9-slice 여백도 같은 비율로 줄인다 (_nine_patch).

const ART_DIR := "res://assets/ui_assets/popup/"
# ---- 미리 구워 둔 아트 ----
#
# _nine_patch 와 _load_icon_from 은 픽셀 단위 처리를 GDScript 로 돌린다.
# 결과는 좋지만 느려서, 팝업 셋을 만드는 데만 부팅에서 9.6초가 걸렸다
# (게임오버 팝업 혼자 6.6초). 아직 열지도 않은 화면 때문에 앱이 12초를
# 멈춰 있던 셈이다.
#
# 그래서 결과를 파일로 구워 두고 런타임에는 읽기만 한다. 계산하는 코드는
# 그대로 두어(캐시가 없으면 그대로 돈다) 아트를 바꿔도 동작은 같고,
# 다시 구우려면 tools/bake_popup_art.gd 만 돌리면 된다.
const BAKE_DIR := "res://assets/ui_assets/popup/baked/"
const BAKE_INDEX_PATH := "res://assets/ui_assets/popup/baked/index.json"
static var bake_writing := false          # 도구가 켠다. 켜지면 계산 결과를 저장.
static var _bake_index: Dictionary = {}
static var _bake_index_loaded := false
static var _bake_written: Dictionary = {}
const PANEL_FILE := "popup_panel.png"
const GOLD_FILE := "button_gold_v2.png"
const CREAM_FILE := "button_cream_v4.png"

# 각 원본의 모서리 곡률 반경(px). 알파 실루엣을 재서 얻은 값이고, 아트를
# 다시 그리면 다시 재야 한다.
const PANEL_CORNER := 121
const GOLD_CORNER := 88
const CREAM_CORNER := 202

# 버튼 누르는 소리. 골드(주 동작)와 크림(보조)이 다른 소리를 낸다.
#
# 확장자 없이 적고 .ogg -> .wav 순으로 찾는다. 파일이 없으면 소리 없이
# 동작만 하므로, 한쪽만 넣어도 된다.
const BUTTON_SOUND_DIR := "res://assets/audio/"
const BUTTON_SOUND_EXTENSIONS := [".ogg", ".wav"]
const GOLD_SOUND_NAME := "button_gold"
const CREAM_SOUND_NAME := "button_cream"
# 일시정지 팝업의 SFX 슬라이더가 이 소리도 함께 조절하도록 같은 버스에 태운다.
const BUTTON_SOUND_BUS := "SFX"

# 골드 버튼 안의 내용(아이콘 + 글자)을 위로 미는 거리(px).
#
# 골드 아트는 아래쪽에 입체감을 주는 두툼한 턱이 있어, 눈에 보이는 판의
# 한가운데가 사각형 한가운데보다 조금 위다. 그대로 가운데에 맞추면 글자가
# 살짝 가라앉아 보인다. 아트의 성질이라 골드 버튼 셋이 같은 값을 쓴다.
const GOLD_CONTENT_DY := -3.0

# 9-slice 원본을 몇 px 폭으로 줄여 둘지 (논리 px, UI_SUPERSAMPLE 배로 그린다).
#
# NinePatchRect는 모서리를 텍스처 픽셀 그대로 그린다. 그래서 화면에 보이는
# 모서리 곡률은 "원본을 얼마로 줄였나"가 정한다.
#
# 골드는 848x244로 버튼 비율(약 300x79)과 비슷해 폭 320에 맞추면 그려진
# 곡률대로 나온다. 반면 크림 v4는 1939x613으로 훨씬 정사각형에 가까워,
# 같은 폭에 맞추면 곡률이 두 배 가까이 커진다 — 63px짜리 버튼에서 위아래
# 모서리가 서로 겹칠 만큼. 그래서 크림은 세로가 버튼 높이에 맞아떨어지는
# 폭으로 줄인다. 가운데는 어차피 9-slice가 가로로 늘려 준다.
const BUTTON_TEXTURE_WIDTH := 320
const CREAM_TEXTURE_WIDTH := 197

const BACKDROP_COLOR := Color(0.04, 0.06, 0.12, 0.55)  # 뒤 게임이 비치도록 옅게

# 판 안쪽 여백 — 판 아트의 골드 테두리 두께를 감안한 값이다.
const CONTENT_SIDE_FRAC := 0.115      # 판 너비 대비 좌우 여백
const CONTENT_TOP_FRAC := 0.085       # 판 높이 대비 위 여백
const CONTENT_BOTTOM_FRAC := 0.075    # 판 높이 대비 아래 여백

const BUTTON_LABEL_FRAC := 0.42       # 버튼 높이 대비 글자 크기
# 아이콘과 글자를 합친 덩어리가 버튼 폭에서 차지할 수 있는 몫. 나머지는
# 좌우 숨돌릴 틈이다. 문구가 길면 이 폭에 맞을 때까지 글자를 줄인다.
const BUTTON_CONTENT_FIT := 0.86
const BUTTON_LABEL_MIN := 9            # 더 줄이면 읽히지 않는다
# 글자 덩어리가 버튼 높이에서 차지할 수 있는 몫. 두 줄짜리 문구가 버튼
# 위아래로 삐져나가지 않도록 폭과 함께 높이도 본다.
const BUTTON_TEXT_FIT_H := 0.80

# 아이콘은 두 시트에서 온다.
#   icon_sheet   메인 화면과 공용. 5x3 — 윗줄 0=재생 1=재시작 2=홈,
#                가운데줄 0=스피커 1=음표.
#   icon_popup   팝업 전용으로 새로 그린 것. 3x1 — 0=재생 1=재시작 2=광고.
#                같은 뜻의 아이콘이라도 이쪽이 팝업 크기에 맞게 굵고 또렷해서,
#                버튼에는 이쪽을 우선 쓴다.
const ICON_SHEET := "res://assets/ui_assets/main/icon_sheet.png"
const ICON_GRID := Vector2i(5, 3)
const ICON_PLAY := 0
const ICON_RESTART := 1
const ICON_HOME := 2
const ICON_SPEAKER := 5
const ICON_NOTE := 6

const POPUP_ICON_SHEET := "res://assets/ui_assets/popup/icon_popup.png"
const POPUP_ICON_GRID := Vector2i(3, 1)
const POPUP_ICON_PLAY := 0
const POPUP_ICON_RESTART := 1
const POPUP_ICON_AD := 2
# 글자 크기 대비 아이콘 높이. 1.0이면 오히려 작아 보인다 — 글자는 대문자
# 높이만 차지하는 반면 아이콘은 제 높이를 다 쓰기 때문이다.
const ICON_HEIGHT_FRAC := 1.18
const ICON_TEXT_GAP_FRAC := 0.42      # 글자 크기 대비 아이콘과 글자 사이 간격
# 아이콘을 미리 줄여 둘 높이(px). 시트 한 칸은 230px가 넘는데 실제로는 26px
# 안팎으로 그려져서, GPU에 9배 축소를 통째로 맡기면 얇은 획이 뭉개진다.
# 여기서 LANCZOS로 한 번 줄여 두면 GPU는 남은 3~4배만 처리하면 된다.
const ICON_TEXTURE_HEIGHT := 96
# 잘라 낸 그림 둘레에 두를 투명 여백(그림 크기 대비). 이유는
# _load_icon_from의 주석 참고.
const ICON_PAD_FRAC := 0.035

# 주 버튼 글자는 흰색에 네이비 외곽선 — 골드 판 위에서 가장 또렷하고,
# 흰 채움 + 네이비 테두리인 아이콘과 같은 옷을 입는다.
const PRIMARY_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const PRIMARY_LABEL_OUTLINE_FRAC := 0.20   # 글자 크기 대비 외곽선 두께

# 글자는 판/버튼 테두리와 같은 진한 네이비 — 화면 전체가 한 팔레트로 묶인다.
const INK := Color(0.055, 0.180, 0.435, 1.0)
# 소리 조절 슬라이더 — 일시정지 팝업과 설정 팝업이 같은 것을 쓴다.
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
# 판을 가로지르는 점선 구분선.
const DIVIDER_DOTS := 22
const DIVIDER_DOT_RADIUS := 2.6
const DIVIDER_COLOR := Color(0.80, 0.75, 0.63, 1.0)   # 진한 크림

# 오른쪽 위 모서리의 동그란 닫기 버튼. 아트는 빈 원판이라 X 는 직접 그린다.
const CANCEL_FILE := "res://assets/ui_assets/popup/button_cancel.png"
const CANCEL_TEXTURE_HEIGHT := 160
const CANCEL_SIZE_FRAC := 0.125        # 판 너비 대비 지름
# 버튼 가운데를 판의 "보이는" 테두리 위에 얹는다 — 반은 안, 반은 밖.
# _panel_rect 는 아트 사각형이라 투명 여백이 있으므로, PANEL_ART_INSET_* 만큼
# 안으로 들어온 자리가 실제로 그려진 테두리다.
# 지름 대비: x 는 오른쪽 테두리에서 이만큼 왼쪽, y 는 위 테두리에서 이만큼 아래.
const CANCEL_ON_BORDER := Vector2(0.45, 0.0)
const CANCEL_X_COLOR := Color(0.055, 0.180, 0.435, 1.0)  # 네이비
const CANCEL_X_ARM_FRAC := 0.19        # 지름 대비 X 팔 길이(중심에서)
const CANCEL_X_WIDTH_FRAC := 0.095     # 지름 대비 선 굵기
const FONT_WEIGHT_BOLD := 600
const FONT_WEIGHT_HEAVY := 700

# 판 둘레의 골드 글로우.
#
# 판 아트에는 골드 테두리 바깥으로 투명 여백이 있다(1024px 원본 기준 약 30px).
# NinePatchRect의 사각형은 그 여백까지 포함하므로, 사각형 그대로 링을 두르면
# 빛이 테두리에서 30px 떨어진 곳부터 시작해 붕 뜬다. 그래서 아래 비율만큼
# 안쪽으로 좁혀 실제 골드 테두리에 붙인다.
const PANEL_ART_INSET_X := 0.0303   # 원본 폭 대비 좌우 투명 여백
const PANEL_ART_INSET_Y := 0.0195   # 원본 높이 대비 상하 투명 여백
const GLOW_COLOR := Color(1.0, 0.82, 0.30)
const GLOW_RINGS := 48
const GLOW_BORDER := 2.0        # 링 두께 — 얇을수록 매끄럽다
# 퍼지는 거리는 GLOW_BORDER * GLOW_SPREAD. 넓힐 때는 링 개수도 같이 올려야
# 링 사이가 벌어지지 않는다 — 안 그러면 넓어지면서 줄무늬가 보인다.
const GLOW_SPREAD := 14.0
const GLOW_INSET := 3.0         # 테두리보다 이만큼 안쪽에서 시작해 빛이 테두리를 물고 나온다
const GLOW_ALPHA := 0.125      # 링 하나의 알파 — 겹쳐서 밝기를 만든다
const GLOW_FALLOFF := 2.0       # 클수록 바깥으로 빠르게 옅어진다
const GLOW_PULSE_PERIOD := 2.4  # 숨쉬듯 아주 느리게
const GLOW_PULSE_RANGE := Vector2(0.75, 1.0)

# 9-slice를 논리 해상도의 몇 배로 그릴지.
#
# 화면은 stretch_mode=canvas_items라 논리 480px이 기기 해상도(1080이면
# 2.25배)로 확대된다. 텍스처를 논리 크기로 줄여 두면 그 확대에서 도로
# 뭉개지므로, 노드를 이 배수만큼 크게 만들고 scale로 되돌린다. 화면상
# 크기는 같지만 텍스처는 배수만큼 촘촘하다.
const UI_SUPERSAMPLE := 2.0

# 크림 버튼의 세로 그라데이션. 골드는 그림에 이미 들어 있지만 크림은 평평해서,
# 불러올 때 텍스처에 직접 구워 넣는다. 픽셀을 고치는 방식이라 9-slice가
# 그대로 먹고 모서리 곡률에도 저절로 맞는다. (위 밝기, 아래 밝기) 배수.
const CREAM_GRADIENT := Vector2(1.045, 0.925)

# ---- 버튼 입체감 ----
# 그림자는 아트가 아니라 코드로 만든다. 그림 안에 그려 넣으면 9-slice와
# 충돌한다 — 그림자가 버튼 바깥으로 나가면 알파 영역이 커져 모서리 반경이
# 어긋나고, 늘릴 때 그림자만 따로 늘어난다.
const SHADOW_COLOR := Color(0.03, 0.08, 0.20, 0.34)
const SHADOW_OFFSET := 5.0          # 쉬고 있을 때 그림자가 내려간 거리
const SHADOW_PRESSED_OFFSET := 1.5  # 눌렸을 때 — 바닥에 붙으며 납작해진다

# 누를 때 줄어들기만 하면 납작해지는 느낌이라, 실제 버튼처럼 아래로 눌러
# 넣는다. 그림자가 함께 짧아져야 "가라앉았다"로 읽힌다.
const PRESS_SCALE := 0.97
const PRESS_SINK := 3.0
const PRESS_ANIM_DURATION := 0.08

var _font_bold: Font
var _font_heavy: Font
var _backdrop: ColorRect
var _glow: Control
var _panel: NinePatchRect
var _elapsed := 0.0
# 판의 논리 크기(화면에 보이는 크기). _panel.size는 UI_SUPERSAMPLE 배로
# 부풀려져 있어 글자 크기나 글로우 위치의 기준으로 쓰면 안 된다.
var _panel_rect := Rect2()
# 버튼 소리 재생기. 아트 종류(골드/크림)마다 하나씩, 팝업이 만들어질 때 한 번만.
var _button_players := {}


# 조립이 끝났는가. Main 이 로고가 뜬 뒤에 ensure_built() 로 켠다.
var _built := false


# 팝업의 무거운 조립(9-slice, 아이콘 굽기, 배치)을 여기서 한다. 두 번 불러도
# 한 번만 돈다.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_ready()


## 처음부터 다시 짓는다. 언어가 바뀌었을 때 Main 이 부른다 — 글자는 지을 때
## tr() 을 거쳐 굳고 글자 크기도 그때 맞춰지므로, 로케일만 바꿔서는 이미
## 만들어진 것들이 옛 언어로 남는다.
func rebuild() -> void:
	if not _built:
		return
	var was_visible := visible
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_built = false
	ensure_built()
	visible = was_visible
	_layout()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # 팝업 뒤로 탭이 새지 않게
	# 프로젝트 기본 필터가 Nearest다(project.godot의 default_texture_filter=0).
	# 그냥 두면 draw_texture_rect로 그리는 아이콘마다 가장자리에 계단이 진다.
	# 자식 CanvasItem의 기본값은 "부모 따라감"이라, 뿌리에서 한 번 정해 주면
	# 팝업 안 전체에 걸린다.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var base: Font = AppFont.base()
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_font_bold = _weighted(base, wght, FONT_WEIGHT_BOLD)
	_font_heavy = _weighted(base, wght, FONT_WEIGHT_HEAVY)

	# 나머지 조립은 Main 이 로고 화면 뒤에서 ensure_built() 로 부른다 —
	# 아직 열지도 않은 팝업 때문에 첫 프레임이 늦어지지 않도록.
	if not _built:
		return
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	# 글로우는 판보다 먼저 — 판 뒤에서 새어나오는 것처럼 보여야 한다.
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(_draw_glow)
	add_child(_glow)

	_panel = _nine_patch(PANEL_FILE, PANEL_CORNER, int(panel_texture_width() * UI_SUPERSAMPLE))
	add_child(_panel)

	_build_content()
	# rebuild() 가 이 함수를 다시 지나므로 이미 걸려 있을 수 있다. 그냥
	# 걸면 Godot 이 중복 연결로 오류를 낸다.
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	_glow.queue_redraw()


# ---- 하위 팝업이 채우는 자리 ----

## 판 위에 올릴 내용을 만든다. _ready에서 한 번 불린다.
func _build_content() -> void:
	pass


## 판 안쪽 영역을 받아 내용을 배치한다. 화면 크기가 바뀔 때마다 불린다.
func _layout_content(inner: Rect2) -> void:
	pass


## 판 크기(화면 대비 비율). 팝업마다 담는 내용이 달라 다르게 잡는다.
func panel_size_frac() -> Vector2:
	return Vector2(0.88, 0.62)


## 판 중심의 세로 위치(화면 대비).
func panel_center_y_frac() -> float:
	return 0.48


## 판 텍스처를 몇 px로 줄여 둘지. 판을 크게 그리는 팝업은 이 값을 올린다.
func panel_texture_width() -> int:
	return 430


# ---- 레이아웃 ----
func _layout() -> void:
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	_backdrop.position = Vector2.ZERO
	_backdrop.size = view

	var frac := panel_size_frac()
	var pw: float = view.x * frac.x
	var ph: float = view.y * frac.y
	var px: float = (view.x - pw) * 0.5
	var py: float = view.y * panel_center_y_frac() - ph * 0.5
	_panel.position = Vector2(px, py)
	# 크게 만들고 되돌린다 — UI_SUPERSAMPLE 주석 참고.
	_panel.size = Vector2(pw, ph) * UI_SUPERSAMPLE
	_panel.scale = Vector2.ONE / UI_SUPERSAMPLE
	_panel_rect = Rect2(px, py, pw, ph)
	_glow.position = Vector2.ZERO
	_glow.size = view

	var pad_x: float = pw * CONTENT_SIDE_FRAC
	_layout_content(Rect2(
		px + pad_x,
		py + ph * CONTENT_TOP_FRAC,
		pw - pad_x * 2.0,
		ph - ph * (CONTENT_TOP_FRAC + CONTENT_BOTTOM_FRAC)))


# 판 둘레의 골드 글로우. 사각 링을 바깥으로 겹쳐 그려 번짐을 흉내낸다.
func _draw_glow() -> void:
	if _panel == null:
		return
	var pulse: float = (sin(_elapsed / GLOW_PULSE_PERIOD * TAU) + 1.0) * 0.5
	var strength: float = lerpf(GLOW_PULSE_RANGE.x, GLOW_PULSE_RANGE.y, pulse)
	# 사각형을 아트의 투명 여백만큼 좁혀 실제 골드 테두리에 맞춘다.
	var inset_x: float = _panel_rect.size.x * PANEL_ART_INSET_X
	var inset_y: float = _panel_rect.size.y * PANEL_ART_INSET_Y
	var rect := Rect2(_panel_rect.position + Vector2(inset_x, inset_y),
		_panel_rect.size - Vector2(inset_x, inset_y) * 2.0)
	var radius: float = PANEL_CORNER * (_panel_rect.size.x / 1024.0)
	for i in range(GLOW_RINGS):
		var t: float = float(i) / float(GLOW_RINGS - 1)
		# 테두리 안쪽에서 시작해 바깥으로 — 빛이 테두리를 감싸고 번져 나간다.
		var grow: float = lerpf(-GLOW_INSET, GLOW_BORDER * GLOW_SPREAD, t)
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.set_corner_radius_all(maxi(0, int(round(radius + grow))))
		style.set_border_width_all(maxi(1, int(round(GLOW_BORDER))))
		style.border_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b,
			GLOW_ALPHA * pow(1.0 - t, GLOW_FALLOFF) * strength)
		style.anti_aliasing = true
		_glow.draw_style_box(style, rect.grow(grow))


# ---- 만들기 헬퍼 ----

# 위에서 아래로 밝기를 훑는다. 투명한 곳은 건드리지 않아 실루엣이 유지되고,
# 테두리도 함께 밝기가 변해 위가 들리고 아래가 앉은 것처럼 보인다.
func _bake_gradient(img: Image, top_mul: float, bottom_mul: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if h < 2:
		return
	for y in range(h):
		var mul: float = lerpf(top_mul, bottom_mul, float(y) / float(h - 1))
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			img.set_pixel(x, y, Color(
				clampf(c.r * mul, 0.0, 1.0),
				clampf(c.g * mul, 0.0, 1.0),
				clampf(c.b * mul, 0.0, 1.0), c.a))


# 원본을 target_w로 축소한 뒤 9-slice 여백을 같은 비율로 줄인 NinePatchRect.
func _nine_patch(file: String, corner: int, target_w: int, gradient := Vector2.ZERO) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var key := "np|%s|%d|%d|%.3f|%.3f" % [file, corner, target_w, gradient.x, gradient.y]
	var baked := _baked(key)
	if not baked.is_empty():
		np.texture = baked["texture"]
		var bm: int = baked["margin"]
		np.patch_margin_left = bm
		np.patch_margin_right = bm
		np.patch_margin_top = bm
		np.patch_margin_bottom = bm
		return np
	var path: String = ART_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("팝업 아트 없음: %s" % path)
		return np
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	# 그림 바깥의 여백은 잘라 낸다. 여백을 그대로 두면 NinePatchRect가 그
	# 여백까지 포함해 늘리므로, 그림이 노드 크기보다 작게 그려지고 여백이
	# 위아래로 다르면 가운데도 어긋난다.
	#
	# get_used_rect()가 아니라 _ink_rect()를 쓴다. 알파가 0만 아니면 포함하는
	# get_used_rect()는 그림에서 한참 떨어진 거의 안 보이는 픽셀까지 끌어안는데,
	# best_box는 실제 상자가 y=172~535인데도 아래로 190px이 더 붙어 잡혔다.
	# 그 텍스처를 9-slice로 늘리면 상자는 노드 위쪽 3분의 2만 차지하고, 노드
	# 한가운데에 맞춘 내용은 상자 아래로 삐져나간다.
	img.convert(Image.FORMAT_RGBA8)
	var used := _ink_rect(img)
	if used.size.x > 0 and used.size.y > 0 and used.size != img.get_size():
		img = img.get_region(used)
	var scale: float = float(target_w) / float(img.get_width())
	img.resize(target_w, int(round(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	if gradient != Vector2.ZERO:
		img.convert(Image.FORMAT_RGBA8)
		_bake_gradient(img, gradient.x, gradient.y)
	# 축소해 놓은 그림을 다시 조금 줄여 그리는 경우가 있어 밉맵과 부드러운
	# 필터를 준다. 없으면 얇은 테두리에 계단이 생긴다.
	var m: int = int(round(corner * scale))
	_bake_store(key, img, m)
	img.generate_mipmaps()
	np.texture = ImageTexture.create_from_image(img)
	np.patch_margin_left = m
	np.patch_margin_right = m
	np.patch_margin_top = m
	np.patch_margin_bottom = m
	return np


# 배경은 NinePatchRect가 그리고 Button은 투명하게 눌리는 역할만 한다.
# TextureButton은 9-slice를 지원하지 않아 그림 전체를 늘려 버리기 때문이다.
# 아이콘은 인덱스가 아니라 텍스처로 받는다 — 팝업마다 쓰는 시트가 달라서,
# 어느 시트에서 왔는지는 부르는 쪽이 정하는 편이 깔끔하다. null이면 글자만.
func _make_button(file: String, corner: int, text: String, icon: Texture2D, primary: bool, gradient := Vector2.ZERO, texture_w := BUTTON_TEXTURE_WIDTH) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = false

	# 그림자가 먼저 — 배경보다 아래에 깔린다. 같은 텍스처를 어둡게 칠한 것이라
	# 실루엣이 정확히 일치한다.
	var shadow := _nine_patch(file, corner, int(texture_w * UI_SUPERSAMPLE))
	shadow.name = "Shadow"
	shadow.modulate = SHADOW_COLOR
	button.add_child(shadow)

	var bg := _nine_patch(file, corner, int(texture_w * UI_SUPERSAMPLE), gradient)
	bg.name = "Background"
	button.add_child(bg)

	var label := _make_label(text, _font_heavy)
	label.name = "Caption"
	if primary:
		label.add_theme_color_override("font_color", PRIMARY_LABEL_COLOR)
		label.add_theme_color_override("font_outline_color", INK)
	button.add_child(label)

	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.texture = icon
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.add_child(icon_rect)

	# 어느 아트로 만든 버튼인지 남겨 둔다 — _play_button_sound가 쓴다.
	button.set_meta("sound", GOLD_SOUND_NAME if file == GOLD_FILE else CREAM_SOUND_NAME)
	button.button_down.connect(_press.bind(button))
	button.button_up.connect(_release.bind(button))
	return button


# 버튼을 놓고, 아이콘과 글자를 한 덩어리로 묶어 가운데 정렬한다. 아이콘을
# 왼쪽에 고정하고 글자만 가운데 두면 덩어리 전체는 왼쪽으로 치우쳐 보인다.
## 버튼을 놓고 그 안의 아이콘·글자를 한 덩어리로 가운데 맞춘다.
##
## icon_scale은 아이콘만 글자보다 크게 키우고 싶을 때, fit은 좌우 여백을
## 기본보다 좁혀 글자를 더 키우고 싶을 때 쓴다.
##
## content_dy는 아이콘과 글자를 통째로 위아래로 밀어 준다. 버튼 아트에 따라
## 눈에 보이는 한가운데가 사각형 한가운데와 조금 어긋날 때 쓴다.
##
## icon_px는 아이콘 높이를 픽셀로 못박는다. 나란히 놓인 버튼들은 글자 길이가
## 제각각이라 글자 크기가 달라지는데, 아이콘까지 따라 달라지면 한 줄에 놓인
## 아이콘들의 크기가 어긋난다. 버튼을 아이콘
## 때문에 일부러 두툼하게 잡은 경우(부활 팝업의 광고 버튼), 아이콘까지
## 글자 크기를 따라가면 애써 늘린 높이가 빈 공간으로 남는다.
func _place(button: Button, x: float, y: float, w: float, h: float, icon_scale := 1.0, fit := BUTTON_CONTENT_FIT, icon_px := 0.0, content_dy := 0.0) -> void:
	button.position = Vector2(x, y)
	button.size = Vector2(w, h)
	button.pivot_offset = Vector2(w, h) * 0.5
	var font_size: int = int(round(h * BUTTON_LABEL_FRAC))

	var shadow: NinePatchRect = button.get_node("Shadow")
	shadow.position = Vector2(0.0, SHADOW_OFFSET)
	shadow.size = Vector2(w, h) * UI_SUPERSAMPLE
	shadow.scale = Vector2.ONE / UI_SUPERSAMPLE

	var bg: NinePatchRect = button.get_node("Background")
	bg.position = Vector2.ZERO
	bg.size = Vector2(w, h) * UI_SUPERSAMPLE
	bg.scale = Vector2.ONE / UI_SUPERSAMPLE

	var label: Label = button.get_node("Caption")
	var icon: TextureRect = button.get_node("Icon")
	var aspect := 0.0
	if icon.texture != null:
		aspect = float(icon.texture.get_width()) / float(icon.texture.get_height())

	# 아이콘 + 간격 + 글자를 한 덩어리로 보고, 그 덩어리가 버튼 폭에 들어올
	# 때까지 글자 크기를 줄인다. "WATCH AD TO CONTINUE"처럼 긴 문구는 높이에서
	# 뽑은 기본 크기로는 버튼을 넘치는데, 덩어리째 재야 아이콘도 같이 줄어
	# 아이콘만 버튼 밖으로 삐져나가는 일이 없다.
	# 캡션은 줄바꿈(\n)을 담을 수 있으므로 여러 줄 기준으로 잰다. 한 줄짜리
	# 문구에는 한 줄로 잰 것과 같은 값이 나온다.
	var fit_w: float = w * fit
	var fit_h: float = h * BUTTON_TEXT_FIT_H
	var text_w := 0.0
	var icon_w := 0.0
	var gap := 0.0
	while true:
		var text_size: Vector2 = _font_heavy.get_multiline_string_size(
			label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		text_w = text_size.x
		icon_w = 0.0
		gap = 0.0
		if icon.texture != null:
			var ih: float = icon_px if icon_px > 0.0 else font_size * ICON_HEIGHT_FRAC * icon_scale
			icon_w = ih * aspect
			gap = font_size * ICON_TEXT_GAP_FRAC
		var fits: bool = icon_w + gap + text_w <= fit_w and text_size.y <= fit_h
		if font_size <= BUTTON_LABEL_MIN or fits:
			break
		font_size -= 1

	label.add_theme_font_size_override("font_size", font_size)
	if label.has_theme_color_override("font_outline_color"):
		label.add_theme_constant_override("outline_size", int(round(font_size * PRIMARY_LABEL_OUTLINE_FRAC)))

	var group_w: float = icon_w + gap + text_w
	var start_x: float = (w - group_w) * 0.5
	if icon.texture != null:
		var icon_h: float = icon_px if icon_px > 0.0 else font_size * ICON_HEIGHT_FRAC * icon_scale
		icon.size = Vector2(icon_w, icon_h)
		icon.position = Vector2(start_x, (h - icon_h) * 0.5 + content_dy)
	label.position = Vector2(start_x + icon_w + gap, content_dy)
	label.size = Vector2(text_w, h)



# 캐릭터 아트는 알파가 0 아니면 255뿐이라 — 반투명 경계 픽셀이 한 개도 없다 —
# 실루엣이 계단처럼 보인다. 화면은 stretch_mode=canvas_items라 256px 원본이
# 기기에서 거의 1:1로 찍히므로, GPU 필터가 대신 뭉개 줄 여지도 없다.
#
# 그래서 불러올 때 경계에만 1px 알파 경사를 만들어 준다. 두 단계로 나눈다.
#   1) 색 번짐 — 투명 픽셀은 RGB가 어둡게 저장돼 있어(용은 0.08/0.14/0.05),
#      알파만 부드럽게 하면 실루엣에 검은 테가 생긴다. 먼저 이웃 불투명
#      픽셀의 색을 투명 쪽으로 한 겹 밀어 둔다.
#   2) 알파 평활 — 경계 부근만 3x3 평균. 안쪽은 이웃이 전부 255라 그대로
#      불투명하고, 바깥도 전부 0이라 그대로 투명하다. 계단 부분만 경사가 된다.
#
# 경계 부근 픽셀만 골라 처리한다. 전체를 돌면 6만 픽셀 x 9칸이라 팝업이 뜰 때
# 눈에 띄게 걸린다.
static var _smooth_cache: Dictionary = {}

func _smoothed(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var key: String = tex.resource_path if not tex.resource_path.is_empty() else str(tex.get_instance_id())
	if _smooth_cache.has(key):
		return _smooth_cache[key]

	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	# 원본은 밉맵까지 딸려 오므로 get_data()가 w*h*4보다 길어진다. 그대로
	# create_from_data에 넘기면 크기가 안 맞아 빈 이미지가 나온다.
	img.clear_mipmaps()
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var dst := src.duplicate()

	# 경계 후보 표시: 알파가 이웃과 다른 픽셀과 그 둘레 한 겹.
	var mark := PackedByteArray()
	mark.resize(w * h)
	for y in range(h):
		for x in range(w):
			var a: int = src[(y * w + x) * 4 + 3]
			var differs := false
			if x + 1 < w and src[(y * w + x + 1) * 4 + 3] != a:
				differs = true
			elif y + 1 < h and src[((y + 1) * w + x) * 4 + 3] != a:
				differs = true
			if not differs:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h:
						mark[ny * w + nx] = 1

	# 1) 투명 쪽으로 색 한 겹 밀기.
	for i in range(w * h):
		if mark[i] == 0 or src[i * 4 + 3] > 0:
			continue
		var x := i % w
		var y := i / w
		var r := 0
		var g := 0
		var b := 0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := (ny * w + nx) * 4
				if src[j + 3] == 0:
					continue
				r += src[j]
				g += src[j + 1]
				b += src[j + 2]
				n += 1
		if n == 0:
			continue
		dst[i * 4] = r / n
		dst[i * 4 + 1] = g / n
		dst[i * 4 + 2] = b / n

	# 2) 경계 부근 알파만 3x3 평균.
	for i in range(w * h):
		if mark[i] == 0:
			continue
		var x := i % w
		var y := i / w
		var sum := 0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				sum += src[(ny * w + nx) * 4 + 3]
				n += 1
		dst[i * 4 + 3] = sum / n

	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dst)
	out.generate_mipmaps()
	var result := ImageTexture.create_from_image(out)
	_smooth_cache[key] = result
	return result

# 메인 시트(5x3)의 한 칸.
func _load_icon(index: int) -> Texture2D:
	return _load_icon_from(ICON_SHEET, ICON_GRID, index)


# 팝업 전용 시트(3x1)의 한 칸.
func _load_popup_icon(index: int) -> Texture2D:
	return _load_icon_from(POPUP_ICON_SHEET, POPUP_ICON_GRID, index)


# 시트의 한 칸을 잘라 투명 여백을 털어 낸다. 칸마다 아이콘이 차지하는
# 넓이가 달라서, 트림하지 않으면 같은 높이로 놓아도 제각각으로 보인다.
# 알파 없이 흰 배경으로 저장된 그림에서 배경을 지운다.
#
# 팝업 아트 중에는 알파 채널 없이 흰 바탕에 그려진 것이 섞여 있다
# (oops_popup, icon_information). 그대로 올리면 흰 사각형이 딸려 온다.
# 바깥에서 흘려보내며 만나는 흰 픽셀만 지우므로, 그림 안쪽에 갇힌 흰색
# (아이콘의 흰 'i' 같은)은 건드리지 않는다.
#
# 이미 투명한 그림이면 아무 일도 하지 않는다.
# 배경으로 볼 조건: 충분히 밝고, 색이 거의 없을 것.
#
# 밝기만 보면 안 된다 — 골드(1.00/0.78/0.22)의 휘도가 0.79라, 밝기 기준을
# 조금만 낮춰도 OOPS 아트의 금색을 배경으로 착각한다. 채도까지 함께 보면
# 회색 계열만 걸러지므로 기준을 낮춰도 안전하다.
#
# 기준을 낮춰야 하는 이유는 icon_information의 흰 바탕이 순백이 아니기
# 때문이다. 0.985~1.0 사이에서 흔들리고 0.89까지 떨어지는 점도 섞여 있어,
# 순백만 지우면 그 점들이 불투명한 회색 얼룩으로 남는다.
const BACKGROUND_MIN := 0.80     # 세 채널 모두 이보다 밝아야
const BACKGROUND_CHROMA := 0.10  # 채널 간 차이가 이보다 작아야

func _strip_white_background(img: Image) -> void:
	if img.get_pixel(0, 0).a < 0.5:
		return
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in range(w):
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in range(h):
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var i: int = p.y * w + p.x
		if seen[i] == 1:
			continue
		var c := img.get_pixel(p.x, p.y)
		var lo: float = minf(c.r, minf(c.g, c.b))
		var hi: float = maxf(c.r, maxf(c.g, c.b))
		if lo < BACKGROUND_MIN or hi - lo > BACKGROUND_CHROMA:
			continue
		seen[i] = 1
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))


## 1234 -> "1,234". 점수는 자릿수가 커질 수 있어, 쉼표가 있어야 한눈에
## 읽힌다. 팝업 여럿이 같은 숫자를 보여주므로 여기 둔다.
func _group(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


# 그림이 실제로 차지하는 사각형.
#
# Image.get_used_rect()는 알파가 0만 아니면 포함하는데, 시트에는 그림에서
# 한참 떨어진 곳에 거의 보이지 않는 픽셀이 몇 개씩 흩어져 있다(내보내기
# 찌꺼기로 보인다). 그대로 자르면 칸마다 빈 여백이 제각각 붙는다 — 광고
# 아이콘은 아래에 189px, 재생 아이콘은 위에 109px. 잘라 낸 텍스처를 버튼
# 가운데에 놓아도 그림은 위나 아래로 치우쳐 보이게 된다.
#
# 그래서 "한 줄에 이만큼은 모여 있어야 그림"이라는 기준으로 다시 잰다.
const INK_ALPHA := 0.2   # 이보다 옅으면 없는 셈 친다
const INK_MIN_RUN := 2   # 한 줄에 이 개수 미만이면 흩어진 찌꺼기로 본다
# 칸 경계를 넘은 그림을 따라 나갈 수 있는 최대 거리(칸 크기 대비).
# 자세한 이유는 _load_icon_from의 주석 참고.
const CELL_SPILL_MAX := 0.20

func _ink_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var top := -1
	var bottom := -1
	var left := w
	var right := -1
	for y in range(h):
		var n := 0
		var row_left := -1
		var row_right := -1
		for x in range(w):
			if img.get_pixel(x, y).a < INK_ALPHA:
				continue
			n += 1
			if row_left < 0:
				row_left = x
			row_right = x
		if n < INK_MIN_RUN:
			continue
		if top < 0:
			top = y
		bottom = y
		left = mini(left, row_left)
		right = maxi(right, row_right)
	if top < 0 or right < 0:
		return img.get_used_rect()
	# 가장자리 반투명 한 겹은 남긴다 — 잘라 내면 도로 계단이 진다.
	top = maxi(0, top - 1)
	left = maxi(0, left - 1)
	bottom = mini(h - 1, bottom + 1)
	right = mini(w - 1, right + 1)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


# target_h는 미리 줄여 둘 높이. 큰 아트(리본, 트로피)는 아이콘 기본값보다
# 크게 잡아야 기기 해상도에서 도로 늘어나지 않는다.
# 시트의 한 줄(가로 또는 세로)에 잉크가 있는지. 칸 경계를 넘은 그림을
# 따라 나갈 때, 어디서 멈출지 판단하는 데 쓴다.
func _line_has_ink(img: Image, horizontal: bool, line: int, from: int, to: int) -> bool:
	for i in range(from, to):
		var c := img.get_pixel(i, line) if horizontal else img.get_pixel(line, i)
		if c.a >= INK_ALPHA:
			return true
	return false


func _load_icon_from(sheet_path: String, grid: Vector2i, index: int, target_h := ICON_TEXTURE_HEIGHT) -> Texture2D:
	var key := "icon|%s|%d|%d|%d|%d" % [sheet_path, grid.x, grid.y, index, target_h]
	var baked := _baked(key)
	if not baked.is_empty():
		return baked["texture"]
	if not ResourceLoader.exists(sheet_path):
		push_warning("아이콘 시트 없음: %s" % sheet_path)
		return null
	var sheet: Image = (load(sheet_path) as Texture2D).get_image()
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	# 칸 경계는 반올림해서 잡는다. 시트가 칸 수로 딱 나누어떨어지지 않는
	# 경우가 있어서다 — icon_sheet는 1536x1024인데 5칸 x 3줄이라 한 칸이
	# 307.2 x 341.33px다. 정수 나눗셈으로 폭을 구해 곱하면 오차가 쌓여
	# 마지막 열과 마지막 줄의 그림이 오른쪽/아래에서 잘려 나간다.
	var col: int = index % grid.x
	var row: int = index / grid.x
	var cw: float = float(sheet.get_width()) / grid.x
	var ch: float = float(sheet.get_height()) / grid.y
	var x0: int = int(round(col * cw))
	var x1: int = int(round((col + 1) * cw))
	var y0: int = int(round(row * ch))
	var y1: int = int(round((row + 1) * ch))
	# 칸 경계를 넘어간 그림은 따라 나간다.
	#
	# 시트의 그림이 반드시 칸 안에 얌전히 들어 있지는 않다. icon_sheet는
	# 1536x1024를 5칸 x 3줄로 나누면 한 칸이 341px인데, 윗줄 그림들은 실제로
	# y=94~356에 그려져 있다 — 칸 경계를 15px 넘는다. 칸 그대로 자르면 윗줄
	# 아이콘(재생·재시작·홈·트로피·공유)의 아래쪽이 잘려 나간다.
	#
	# 그렇다고 무턱대고 넓히면 옆 칸 그림을 물고 온다(icon_popup은 그림이
	# 칸을 거의 꽉 채운다). 그래서 경계에 그림이 닿아 있을 때만, 빈 줄을
	# 만날 때까지 그 방향으로 한 줄씩 따라 나간다 — 그림 사이의 틈에서
	# 정확히 멈춘다.
	#
	# 단, 알파가 있는 시트에서만 통한다. 흰 배경으로 저장된 시트는 모든
	# 픽셀이 불투명이라 "빈 줄"이 없어서, 옆 칸에 닿을 때까지 따라 나가게
	# 된다. 그런 시트는 칸 그대로 잘라 오고 배경은 뒤에서 지운다.
	var has_alpha: bool = sheet.get_pixel(0, 0).a < 0.5
	var cap_x: int = int(round(cw * CELL_SPILL_MAX))
	var cap_y: int = int(round(ch * CELL_SPILL_MAX))
	while has_alpha and y1 < sheet.get_height() and y1 - int(round((row + 1) * ch)) < cap_y \
			and _line_has_ink(sheet, true, y1 - 1, x0, x1):
		y1 += 1
	while has_alpha and y0 > 0 and int(round(row * ch)) - y0 < cap_y \
			and _line_has_ink(sheet, true, y0, x0, x1):
		y0 -= 1
	while has_alpha and x1 < sheet.get_width() and x1 - int(round((col + 1) * cw)) < cap_x \
			and _line_has_ink(sheet, false, x1 - 1, y0, y1):
		x1 += 1
	while has_alpha and x0 > 0 and int(round(col * cw)) - x0 < cap_x \
			and _line_has_ink(sheet, false, x0, y0, y1):
		x0 -= 1
	var cell: Image = sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	# 흰 배경으로 저장된 아이콘이 섞여 있다 — 지우고 나서 잘라야 한다.
	_strip_white_background(cell)
	var used := _ink_rect(cell)
	if used.size.x > 0 and used.size.y > 0:
		cell = cell.get_region(used)
	# 잘라 낸 그림 둘레에 투명한 여백을 두른다.
	#
	# 딱 맞게 자르면 실루엣이 텍스처 가장자리에 닿는다. 그러면 가장자리
	# 픽셀은 바깥쪽으로 섞일 상대가 없어서, 곡선이 가장자리를 스치는 구간이
	# 부드럽게 사라지지 못하고 반투명한 한 줄로 남는다 — 30px쯤으로 줄여
	# 그리면 그 한 줄이 직선으로 읽혀 "오른쪽이 잘린" 것처럼 보인다.
	# 여백을 주면 그 구간이 제대로 옅어진다.
	var pad: int = maxi(2, int(round(maxf(cell.get_width(), cell.get_height()) * ICON_PAD_FRAC)))
	var padded := Image.create(cell.get_width() + pad * 2, cell.get_height() + pad * 2,
		false, Image.FORMAT_RGBA8)
	padded.fill(Color(0.0, 0.0, 0.0, 0.0))
	padded.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i(pad, pad))
	cell = padded
	# 표시 크기 가까이까지 미리 줄인다 — 이유는 ICON_TEXTURE_HEIGHT 주석 참고.
	#
	# 줄이기 전에 알파를 색에 곱해 둔다(premultiply). resize는 RGB와 알파를
	# 따로 평균 내는데, 투명 픽셀에도 색은 남아 있다 — 흰 배경을 지운 그림은
	# 투명한 흰색이 잔뜩이다. 그대로 줄이면 그 흰색이 가장자리로 섞여 들어와
	# 실루엣 둘레에 옅은 테가 진다. 미리 곱해 두면 투명한 픽셀은 색까지 0이
	# 되어 평균에 끼어들지 않는다.
	if cell.get_height() > target_h:
		var s: float = float(target_h) / float(cell.get_height())
		cell.premultiply_alpha()
		cell.resize(maxi(1, int(round(cell.get_width() * s))), target_h, Image.INTERPOLATE_LANCZOS)
		_unpremultiply(cell)
	_bake_store(key, cell, 0)
	cell.generate_mipmaps()
	return ImageTexture.create_from_image(cell)


# ---- 구운 아트 읽기/쓰기 ----

static func _bake_load_index() -> void:
	if _bake_index_loaded:
		return
	_bake_index_loaded = true
	if not FileAccess.file_exists(BAKE_INDEX_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BAKE_INDEX_PATH))
	if parsed is Dictionary:
		_bake_index = parsed


# 있으면 {"texture": Texture2D, "margin": int}, 없으면 빈 Dictionary.
func _baked(key: String) -> Dictionary:
	_bake_load_index()
	if bake_writing or not _bake_index.has(key):
		return {}
	var entry: Dictionary = _bake_index[key]
	var path: String = BAKE_DIR + str(entry.get("file", ""))
	if not ResourceLoader.exists(path):
		return {}
	return {"texture": load(path) as Texture2D, "margin": int(entry.get("margin", 0))}


func _bake_store(key: String, img: Image, margin: int) -> void:
	if not bake_writing:
		return
	# 파일 이름은 사람이 알아볼 수 있게 앞부분을 남기고, 뒤에 해시를 붙여
	# 같은 그림의 다른 크기끼리 부딪히지 않게 한다.
	var stem: String = key.replace("res://", "").replace("/", "_").replace("|", "_").replace(".", "_")
	var name: String = "%s_%s.png" % [stem.substr(0, 40), key.sha1_text().substr(0, 8)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	var flat: Image = img.duplicate() as Image
	flat.clear_mipmaps()
	flat.save_png(ProjectSettings.globalize_path(BAKE_DIR + name))
	_bake_written[key] = {"file": name, "margin": margin}


# 도구가 마지막에 부른다.
static func bake_flush() -> void:
	var file := FileAccess.open(BAKE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		printerr("index.json 을 쓸 수 없다: %s" % BAKE_INDEX_PATH)
		return
	file.store_string(JSON.stringify(_bake_written, "\t", true))
	file.close()
	# 지난번에 구웠지만 이번에는 안 쓰인 파일을 지운다. 크기 상수를 만질 때마다
	# 키가 바뀌어 새 파일이 생기므로, 치우지 않으면 죽은 그림이 쌓인다.
	var keep := {}
	for entry in _bake_written.values():
		keep[str(entry.get("file", ""))] = true
	var dir := DirAccess.open(BAKE_DIR)
	var removed := 0
	if dir != null:
		for name in dir.get_files():
			if not name.ends_with(".png") or keep.has(name):
				continue
			DirAccess.remove_absolute(ProjectSettings.globalize_path(BAKE_DIR + name))
			var meta: String = ProjectSettings.globalize_path(BAKE_DIR + name + ".import")
			if FileAccess.file_exists(meta):
				DirAccess.remove_absolute(meta)
			removed += 1
	print("구운 조각 %d개 (안 쓰는 %d개 삭제) -> %s" % [
		_bake_written.size(), removed, BAKE_INDEX_PATH])


# premultiply_alpha()를 되돌린다. 줄인 뒤에 부르므로 픽셀 수가 적어 싸다.
# LANCZOS는 경계에서 값이 살짝 넘치거나 모자랄 수 있어 범위를 다시 잡는다.
func _unpremultiply(img: Image) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var a: float = clampf(c.a, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			img.set_pixel(x, y, Color(
				clampf(c.r / a, 0.0, 1.0),
				clampf(c.g / a, 0.0, 1.0),
				clampf(c.b / a, 0.0, 1.0), a))


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
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
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


# 슬라이더 두 줄의 왼쪽 칸(아이콘 + 이름표)을 ctrl 위에 그린다.
# 트랙과 손잡이는 HSlider 자신이 그린다.
func _draw_slider_labels(ctrl: Control, rows: Array, font_size: int, row_h: float, gap: float) -> void:
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
			ctrl.draw_texture_rect(icon,
				Rect2(Vector2(x, centre_y - ih * 0.5), Vector2(iw, ih)), false, INK)
			x += iw + font_size * SLIDER_ICON_GAP_FRAC
		# draw_string은 베이스라인 기준이라, 대문자 높이의 절반만큼 내려야
		# 글자 가운데가 아이콘 가운데와 맞는다.
		ctrl.draw_string(_font_bold, Vector2(x, centre_y + font_size * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


# 이름표 칸의 폭. 비율로 잡으면 긴 이름("MUSIC")이 트랙에 물려서, 실제로 재서 정한다.
func _slider_label_column(font_size: int, texts: Array) -> float:
	var w := 0.0
	for text in texts:
		w = maxf(w, _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# 아이콘(글자 높이와 같은 정사각형 가정) + 간격 + 글자 + 트랙까지 숨돌릴 틈
	return w + font_size * (1.0 + SLIDER_ICON_GAP_FRAC) + font_size * 0.5


# 아이콘 없이 칸을 통째로 쓰는 이름표(BOOST/LANGUAGE)용 — 슬라이더와 같은
# 칸을 나눠 쓰므로 둘 다 재서 넓은 쪽을 골라야 한다. 슬라이더 쪽만 재면
# 이름표가 트랙 밑으로 파고든다: "LANGUAGE" 가 "MUSIC" 보다 길다.
func _row_label_column(font_size: int, texts: Array) -> float:
	var w := 0.0
	for text in texts:
		w = maxf(w, _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return w + font_size * 0.5


# ---- 두 갈래 토글 ----
#
# 알약 모양 트랙 위를 손잡이가 좌우로 옮겨 다니고, 두 칸에 각각 이름이 적힌다.
# 지금 쓰는 곳은 가속 버튼의 좌/우 하나뿐이지만, 설정 팝업과 일시정지 팝업
# 둘 다에서 쓰므로 여기 둔다.
#
# 처음에는 금색 버튼(_make_button) 두 개로 만들었는데 테두리가 깨졌다.
# GOLD_CORNER 가 88px 이고 나인패치는 모서리를 원본 크기로 그리므로, 버튼을
# 176px 보다 좁게 만들면 좌우 모서리가 서로 파고든다. 트랙 절반 폭에 넣으려던
# 것이라 어느 화면에서도 그보다 좁았다. 직접 그리면 그 제약이 아예 없다.
#
# 색은 슬라이더에서 그대로 가져온다 — 같은 줄에 나란히 서므로 트랙과 채움이
# 같은 색이어야 한 벌로 읽힌다.
const TOGGLE_HEIGHT := 40.0
const TOGGLE_PAD := 4.0            # 트랙 안쪽, 손잡이 둘레의 여백
const TOGGLE_LABEL_FRAC := 0.42    # 토글 높이 대비 글자 크기
const TOGGLE_OFF_TEXT := Color(0.42, 0.40, 0.36, 1.0)


## 두 갈래 토글 하나. `texts` 는 [왼쪽, 오른쪽] 이름이고, 값이 false 면 왼쪽이
## 아니라 오른쪽이 켜진 것으로 본다 — 부르는 쪽의 bool 이 "왼쪽인가"가 아니라
## 무엇이든 될 수 있게, 어느 칸이 켜졌는지는 인덱스로 다룬다.
func _make_side_toggle(texts: Array, on_second: bool, on_change: Callable) -> Control:
	var t := Control.new()
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.set_meta("texts", texts)
	t.set_meta("second", on_second)
	t.draw.connect(_draw_side_toggle.bind(t))
	t.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var want_second: bool = e.position.x > t.size.x * 0.5
			if want_second == bool(t.get_meta("second")):
				return
			_set_side_toggle(t, want_second)
			on_change.call(want_second))
	return t


## 표시만 바꾼다 — 신호는 보내지 않는다. 저장된 값을 넣어 줄 때도 여기를 지난다.
func _set_side_toggle(t: Control, on_second: bool) -> void:
	if t == null:
		return
	t.set_meta("second", on_second)
	t.queue_redraw()


func _side_toggle_value(t: Control) -> bool:
	return t != null and bool(t.get_meta("second", false))


func _draw_side_toggle(t: Control) -> void:
	var texts: Array = t.get_meta("texts", ["", ""])
	var second: bool = bool(t.get_meta("second", false))
	var h: float = t.size.y
	var w: float = t.size.x
	var r: float = h * 0.5
	# 트랙.
	t.draw_style_box(_pill(SLIDER_TRACK_COLOR, r), Rect2(Vector2.ZERO, Vector2(w, h)))
	# 손잡이 — 켜진 칸을 덮는다.
	var knob_w: float = (w - TOGGLE_PAD * 2.0) * 0.5
	var knob_x: float = TOGGLE_PAD + (knob_w if second else 0.0)
	t.draw_style_box(_pill(SLIDER_FILL_COLOR, (h - TOGGLE_PAD * 2.0) * 0.5),
		Rect2(Vector2(knob_x, TOGGLE_PAD), Vector2(knob_w, h - TOGGLE_PAD * 2.0)))
	# 이름 둘. 켜진 쪽은 진한 잉크, 꺼진 쪽은 흐리게.
	var fs: int = maxi(9, int(round(h * TOGGLE_LABEL_FRAC)))
	for i in range(2):
		var text: String = str(texts[i]) if i < texts.size() else ""
		var tw: float = _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx: float = TOGGLE_PAD + knob_w * (float(i) + 0.5)
		var lit: bool = (i == 1) == second
		t.draw_string(_font_bold, Vector2(cx - tw * 0.5, h * 0.5 + fs * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK if lit else TOGGLE_OFF_TEXT)


func _pill(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(round(radius)))
	box.anti_aliasing = true
	return box


# 판을 가로지르는 점선.
func _draw_dotted_divider(ctrl: Control) -> void:
	var w: float = ctrl.size.x
	var y: float = ctrl.size.y * 0.5
	var step: float = w / float(maxi(1, DIVIDER_DOTS - 1))
	for i in range(DIVIDER_DOTS):
		ctrl.draw_circle(Vector2(i * step, y), DIVIDER_DOT_RADIUS, DIVIDER_COLOR)


# 오른쪽 위 닫기 버튼. 누르면 넘겨준 Callable 을 부른다.
# 크림 버튼과 같은 누름 효과와 소리를 쓴다(_press/_release 가 "sound" 메타를 본다).
func _make_close_button(on_pressed: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(slot, empty)
	button.set_meta("sound", CREAM_SOUND_NAME)
	button.set_meta("art", _load_icon_from(CANCEL_FILE, Vector2i(1, 1), 0, CANCEL_TEXTURE_HEIGHT))
	button.button_down.connect(_press.bind(button))
	button.button_up.connect(_release.bind(button))
	button.draw.connect(_draw_close_button.bind(button))
	button.pressed.connect(on_pressed)
	add_child(button)
	return button


# 판 오른쪽 위 테두리에 가운데가 얹히도록 놓는다.
func _place_close_button(button: Button) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var d: float = pw * CANCEL_SIZE_FRAC
	button.size = Vector2(d, d)
	button.pivot_offset = Vector2(d, d) * 0.5
	var centre := Vector2(
		_panel_rect.end.x - pw * PANEL_ART_INSET_X - d * CANCEL_ON_BORDER.x,
		_panel_rect.position.y + ph * PANEL_ART_INSET_Y + d * CANCEL_ON_BORDER.y)
	button.position = centre - Vector2(d, d) * 0.5
	button.queue_redraw()


func _draw_close_button(button: Button) -> void:
	var d: float = button.size.x
	var art: Texture2D = button.get_meta("art", null)
	if art != null:
		button.draw_texture_rect(art, Rect2(Vector2.ZERO, Vector2(d, d)), false)
	var c := Vector2(d, d) * 0.5
	var arm: float = d * CANCEL_X_ARM_FRAC
	var w: float = d * CANCEL_X_WIDTH_FRAC
	button.draw_line(c + Vector2(-arm, -arm), c + Vector2(arm, arm), CANCEL_X_COLOR, w, true)
	button.draw_line(c + Vector2(arm, -arm), c + Vector2(-arm, arm), CANCEL_X_COLOR, w, true)


func _make_label(text: String, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", INK)
	if font != null:
		label.add_theme_font_override("font", font)
	return label


# 눌림: 살짝 줄면서 아래로 가라앉고, 동시에 그림자가 짧아진다. 셋이 함께
# 움직여야 "판에 눌러 넣었다"로 읽힌다 — 크기만 줄면 그냥 납작해진다.
# 버튼을 누르는 순간 나는 소리. 어느 아트로 만든 버튼인지는 _make_button이
# 메타로 남겨 둔다 — 버튼 모양이 곧 소리를 정한다.
#
# 재생기는 아트마다 하나씩 만들어 재사용한다. 누를 때마다 새로 만들면
# 연타할 때 노드가 쌓인다.
func _play_button_sound(button: Control) -> void:
	var art: String = button.get_meta("sound", "")
	if art == "":
		return
	if not _button_players.has(art):
		var path := ""
		for ext in BUTTON_SOUND_EXTENSIONS:
			var candidate: String = BUTTON_SOUND_DIR + art + ext
			if ResourceLoader.exists(candidate):
				path = candidate
				break
		if path == "":
			_button_players[art] = null   # 파일이 없다 — 다시 찾지 않는다
		else:
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			player.bus = BUTTON_SOUND_BUS
			add_child(player)
			_button_players[art] = player
	var p: AudioStreamPlayer = _button_players[art]
	if p != null:
		p.play()


func _press(button: Control) -> void:
	_play_button_sound(button)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE * PRESS_SCALE, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:y", button.position.y + PRESS_SINK, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var shadow: Node = button.get_node_or_null("Shadow")
	if shadow != null:
		tween.tween_property(shadow, "position:y", SHADOW_PRESSED_OFFSET, PRESS_ANIM_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _release(button: Control) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# TRANS_BACK이 살짝 튕겨 올라오며 되돌아온다.
	tween.tween_property(button, "scale", Vector2.ONE, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:y", button.position.y - PRESS_SINK, PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var shadow: Node = button.get_node_or_null("Shadow")
	if shadow != null:
		tween.tween_property(shadow, "position:y", SHADOW_OFFSET, PRESS_ANIM_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv
