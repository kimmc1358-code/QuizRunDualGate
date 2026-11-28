extends Control
class_name PopupBase

## 팝업들의 공통 바탕.
##
## 판·버튼·아이콘을 만드는 법, 팔레트, 눌림 동작처럼 모든
## 팝업이 똑같이 쓰는 것만 모아 둔다. 각 팝업(PausePopup, GameOverPopup, …)은
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
# ---- 2.0 의 판과 버튼 (2026-11-28) ----
#
# Synty INTERFACE Sci-Fi Menus 키트에서 온다(tools/build_ui_kit.gd 가 굽고,
# 유료라 git 에 들어가지 않는다). 판은 파란 불이 든 강철 모서리
# 프레임(Frame_Box_Large_08)을 모서리 넷과 민무늬 변만 남겨 9-slice 로 잘라 둔 것,
# 버튼은 양 끝을 강철 머리로 닫은 Frame_Box_Small_08 막대이고 면 색으로만 가른다 —
# 주 버튼 주황, 보조 버튼 파랑. 좁은 버튼(LOGIN, x2)만 은빛 베벨(Frame_Box_Small_04)
# 상자다. 거쳐 온 길(Bar_Frame_02, 베벨, 아이콘 칸)은 CLAUDE.md 의 팝업 항목에 있다.
# 키트가 없으면 ArtSlot 의 회색 틀로 그려진다.
#
# 1.x 의 크림·골드 판(ART_DIR)은 2026-11-26 에 그림이 지워졌다. 이름은
# 그대로 두었다 — GOLD 는 "주 버튼", CREAM 은 "보조 버튼"으로 읽는다.
const KIT := "res://assets/synty_ui/"
const PANEL_FILE := KIT + "popup_panel.png"
# 버튼은 주·보조 모두 Frame_Box_Small_08 막대(2026-11-28, 주인): 양 끝이 나사 박힌 강철
# 머리다. 원래 그림은 오른쪽에만 머리가 있고 왼쪽은 아이콘 칸 밑에 들어가도록 가는
# 테뿐이라, 혼자 쓰면 왼쪽이 잘려 보였다 — 굽기에서 오른쪽 머리를 뒤집어 왼쪽에도
# 붙인다(build_ui_kit MIRROR_RIGHT). 면 색으로만 가른다 — 주 버튼 주황, 보조 버튼 파랑.
# 양 끝을 고정하고 가운데만 늘이며, 높이는 그림째 맞춘다(_kit_patch, "height").
const GOLD_FILE := KIT + "popup_bar_primary.png"
const CREAM_FILE := KIT + "popup_bar.png"
# 은빛 베벨(Frame_Box_Small_04) 작은 상자, 네 변 9-slice. 소리 막대의 손잡이, 그리고
# 좁은 버튼(LOGIN, 게임오버의 x2) — 막대의 양 끝 머리가 면을 거의 다 먹었다.
const BEVEL_FILE := KIT + "popup_button.png"
const BEVEL_CORNER := 22
const SMALL_GOLD_FILE := KIT + "popup_small_primary.png"
const SMALL_CREAM_FILE := BEVEL_FILE
const SMALL_CORNER := BEVEL_CORNER
const BEVEL_FACE_INSET := Vector2(15, 17)   # 베벨 그림의 면 둘레(텍스처 px)

# 9-slice 여백(텍스처 px). 판은 build_ui_kit 이 찍어 주는 값. 버튼 막대(222x104)는
# 양 끝 강철 머리가 BUTTON_BAR_LEFT/RIGHT(같은 그림을 뒤집었으니 같고, 굽기에서 가로로
# 60% 로 눌러 둔 폭이다), 위아래 테가 BUTTON_BAR_FACE_Y 다. 그림은 157x104. 키트를 다시 구우면 다시 잰다.
const PANEL_CORNER := 96
const BUTTON_BAR_LEFT := 49
const BUTTON_BAR_RIGHT := 49
const BUTTON_BAR_FACE_Y := 14
# 버튼을 만들 때 넘기는 모서리 값. 막대는 _kit_patch 가 위 셋으로 자르므로 쓰지 않지만,
# 키트가 없을 때의 자리표시 틀이 이 값으로 잘린다.
const GOLD_CORNER := BUTTON_BAR_LEFT
const CREAM_CORNER := BUTTON_BAR_LEFT
# 보조 버튼 글자와 아이콘 — 짙은 면 위의 하늘색(Label_Button 과 같은 색).
const SECONDARY_LABEL_COLOR := Color(0.55, 0.88, 1.0, 1.0)
# 판의 9-slice 는 키트가 구운 배율(화면 1px 에 2.25px)로 그린다 — 모서리가
# 구운 그대로의 크기로 나온다. 버튼은 높이에 맞춰 늘린다(_fit_patch).
const KIT_BAKE := 2.25
# 키트 버튼의 아이콘+글자가 양 끝 머리 사이에서 쓸 수 있는 몫(_place).
const KIT_BUTTON_FACE_FIT := 0.96

# 버튼 누르는 소리. 골드(주 동작)와 크림(보조)이 다른 소리를 낸다.
#
# 확장자 없이 적고 .ogg -> .wav 순으로 찾는다. 파일이 없으면 소리 없이
# 동작만 하므로, 한쪽만 넣어도 된다.
const BUTTON_SOUND_DIR := "res://assets/audio/"
const BUTTON_SOUND_EXTENSIONS := [".ogg", ".wav"]
# 금색 버튼은 팝업의 주 버튼 넷뿐이다 — RESUME, PLAY AGAIN, 결과 화면의 x2,
# REMOVE ADS. 메인 화면의 START 는 이 길을 안 지나고
# ModeSelectScreen 이 제 소리(start_main.wav)를 따로 낸다.
const GOLD_SOUND_NAME := "goldbutton_sound"
const CREAM_SOUND_NAME := "button_cream"
# 일시정지 팝업의 SFX 슬라이더가 이 소리도 함께 조절하도록 같은 버스에 태운다.
const BUTTON_SOUND_BUS := "SFX"

# 골드 버튼 안의 내용(아이콘 + 글자)을 위로 미는 거리(px).
#
# 1.x 골드 아트는 아래쪽에 입체감을 주는 두툼한 턱이 있어, 눈에 보이는 판의
# 한가운데가 사각형 한가운데보다 조금 위다. 그대로 가운데에 맞추면 글자가
# 살짝 가라앉아 보였다. 2.0 의 버튼(Frame_Box_Small_08)은 면이 위아래 가운데라
# 0 이다. 아트를 바꾸면 다시 본다 — 주 버튼들이 모두 같은 값을 쓴다.
const GOLD_CONTENT_DY := 0.0

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

const BACKDROP_COLOR := Color(0.01, 0.02, 0.06, 0.62)  # 뒤 게임이 비치도록 옅게

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
# 2.0 에서는 두 시트의 칸 번호가 키트의 흰 아이콘을 가리킨다(_load_icon).
# 재생은 키트에 맞는 것이 없어 코드로 그린다(_play_icon).
const KIT_ICONS := {
	1: "icon_restart.png",   # ICON_RESTART
	2: "icon_home.png",      # ICON_HOME
	5: "icon_sound.png",     # ICON_SPEAKER
	6: "icon_music.png",     # ICON_NOTE
}
const KIT_POPUP_ICONS := {
	1: "icon_restart.png",   # POPUP_ICON_RESTART
	2: "icon_ad.png",        # POPUP_ICON_AD
}
const ICON_GRID := Vector2i(5, 3)
const ICON_PLAY := 0            # 지금 쓰는 곳은 없다 — 시트의 목차라 자리를 지운다
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
const PRIMARY_LABEL_COLOR := Color(1.0, 0.98, 0.92, 1.0)
# 주황 버튼 위 글자의 테두리 — 메뉴 PLAY 의 PLAY_TEXT_RIM 과 같다.
const PRIMARY_LABEL_OUTLINE := Color(0.36, 0.12, 0.02, 1.0)
const PRIMARY_LABEL_OUTLINE_FRAC := 0.20   # 글자 크기 대비 외곽선 두께

# 글자는 어두운 판 위의 흰 빛 도는 하늘색. 1.x 는 크림 판에 네이비였다.
const INK := Color(0.88, 0.95, 1.0, 1.0)
# 소리 조절 슬라이더 — 일시정지 팝업과 설정 팝업이 같은 것을 쓴다.
const SLIDER_LABEL_FRAC := 0.062
# 줄 높이 = 이름표 글자 + 이만큼. 손잡이 트랙(12) + 6 이던 값을 그대로 두어
# 막대로 바뀌어도 팝업의 줄 배치는 달라지지 않는다.
const SLIDER_ROW_PAD := 18.0
# 언어 토글이 같이 쓰는 두 색 — 빈 칸과 켜진 칸.
const SLIDER_TRACK_COLOR := Color(0.10, 0.16, 0.28, 1.0)
const SLIDER_FILL_COLOR := Color(0.30, 0.82, 1.0, 1.0)
const SLIDER_ICON_GAP_FRAC := 0.34  # 글자 크기 대비 아이콘-글자 간격
# 소리 막대(KitSlider, 2026-11-28). 주인이 보낸 견본을 따랐다: 양 끝에
# 청록 불이 든 화살표 버튼(Button_Arrow_07), 그 사이 Bar_Frame_02 틀. 값을
# 적은 금속 상자가 손잡이로 막대 위를 오가고, 그 왼쪽이 채워진다. 상자는
# 보조 버튼의 은빛 테(popup_button.png)를 작게 9-slice 한 것이다 — 처음의
# Frame_Box_Small_06 은 양옆 캡까지 달려 손잡이로는 번잡했다(주인). 화살표는
# 한 칸씩(SLIDER_STEP) 올리고 내린다. 비율은 모두 막대 높이 대비이고, 구운
# slider_frame.png(290x68)에서 쟀다.
const SLIDER_FRAME_FILE := KIT + "slider_frame.png"
const SLIDER_ARROW_LEFT_FILE := KIT + "slider_arrow_left.png"
const SLIDER_ARROW_RIGHT_FILE := KIT + "slider_arrow_right.png"
const SLIDER_BAR_HEIGHT := 30.0
const SLIDER_ARROW_HEIGHT_FRAC := 1.0
# 화살표가 막대 끝 조각을 이만큼 덮는다 — 틀 끝의 작은 청록 꼭지가 화살표와
# 겹쳐 둘로 보이지 않게.
const SLIDER_ARROW_OVERLAP := 0.30
const SLIDER_CAP_FRAC := 0.40       # 틀 끝 조각 폭. 늘이지 않는 부분
const SLIDER_FACE_INSET_X := 0.30   # 틀 안쪽 면이 시작하는 곳
const SLIDER_FACE_INSET_Y := 0.19
const SLIDER_HANDLE_HEIGHT_FRAC := 1.0
const SLIDER_HANDLE_WIDTH_FRAC := 1.6    # 손잡이 폭, 막대 높이 대비 — "100" 이 들어가는 폭
const SLIDER_HANDLE_HELD := Color(1.25, 1.25, 1.25)   # 끄는 동안 손잡이를 이만큼 밝힌다
const SLIDER_FACE_COLOR := Color(0.03, 0.07, 0.16, 0.96)
# 채움은 왼쪽이 어둡고 손잡이 쪽으로 갈수록 밝은 청록 — 견본의 결.
const SLIDER_FILL_DARK := Color(0.04, 0.36, 0.56, 1.0)
const SLIDER_FILL_BRIGHT := Color(0.32, 0.88, 1.0, 1.0)
const SLIDER_FILL_SHINE := Color(1.0, 1.0, 1.0, 0.22)   # 채움 위쪽 3분의 1에 얹는 빛
const SLIDER_NUMBER_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SLIDER_NUMBER_FRAC := 0.46    # 손잡이 높이 대비 숫자 크기
const SLIDER_STEP := 0.1
const SLIDER_ARROW_FLASH := 0.22    # 화살표를 누르면 밝아졌다 꺼지는 시간
# 판을 가로지르는 점선 구분선.
const DIVIDER_DOTS := 22
const DIVIDER_DOT_RADIUS := 2.6
const DIVIDER_COLOR := Color(0.30, 0.62, 0.85, 0.55)

# 오른쪽 위 모서리의 닫기 버튼. 틀은 빈 네모라 X 는 직접 그린다.
const CANCEL_FILE := KIT + "side_slot.png"   # HUD 의 네모 슬롯과 같은 틀
const CANCEL_SIZE_FRAC := 0.125        # 판 너비 대비 지름
# 버튼 가운데를 판의 "보이는" 테두리 위에 얹는다 — 반은 안, 반은 밖.
# _panel_rect 는 아트 사각형이라 투명 여백이 있으므로, PANEL_ART_INSET_* 만큼
# 안으로 들어온 자리가 실제로 그려진 테두리다.
# 지름 대비: x 는 오른쪽 테두리에서 이만큼 왼쪽, y 는 위 테두리에서 이만큼 아래.
const CANCEL_ON_BORDER := Vector2(0.45, 0.0)
const CANCEL_X_COLOR := Color(0.88, 0.95, 1.0, 1.0)
const CANCEL_X_ARM_FRAC := 0.19        # 지름 대비 X 팔 길이(중심에서)
const CANCEL_X_WIDTH_FRAC := 0.095     # 지름 대비 선 굵기
const FONT_WEIGHT_BOLD := 600
const FONT_WEIGHT_HEAVY := 700

# 판 사각형에서 실제로 그려진 테두리까지의 거리(판 크기 대비) — 닫기 버튼을
# 테두리 위에 얹을 때 쓴다. 키트 판은 잉크까지 잘려 있어 여백이 거의 없고,
# 모서리의 강철 삼각형만 파란 선보다 조금 바깥으로 나와 있다.
#
# 판 둘레에는 하늘색(1.x 에서는 금색) 글로우가 숨쉬듯 번졌는데, 2026-11-28
# 주인의 요청으로 뺐다. 키트 판은 테두리 자체에 빛과 색이 있다.
const PANEL_ART_INSET_X := 0.012
const PANEL_ART_INSET_Y := 0.010

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

# 눌린 동안 버튼 안쪽 면이 밝아진다(2026-11-28, 주인의 요청 — 메뉴의 PLAY 처럼).
# 면 위에 더하기(ADD)로 빛을 얹어 그림의 결은 살리고 밝기만 올린다. 테두리는
# 그대로라 "면이 켜졌다"로 읽힌다. 면의 자리는 구운 그림에서 잰 안쪽 여백
# (텍스처 px)이고, 그림과 같은 배율로 화면에 옮긴다(_place).
const PRESS_GLOW_GOLD := Color(1.0, 0.80, 0.40, 0.32)
const PRESS_GLOW_CREAM := Color(0.30, 0.62, 1.0, 0.30)
const PRESS_GLOW_RADIUS := 3
const PRESS_GLOW_FADE := 0.18     # 손을 뗀 뒤 꺼지는 시간 — 켜질 때보다 느긋하게

var _font_bold: Font
var _font_heavy: Font
# 버튼 글자는 Zen Dots, 숫자와 설명은 Oxanium(한글은 Do Hyeon)(2026-11-28, 주인). 제목과 같은 글꼴이라
# 누를 것이 한눈에 갈린다. Zen Dots 에는 한글이 없어 한국어 캡션은 _font_heavy 로
# 떨어진다(TitleArt.font 의 fallbacks).
var _font_button: Font
var _backdrop: ColorRect
var _panel: NinePatchRect
var _elapsed := 0.0
# 판의 논리 크기(화면에 보이는 크기). _panel.size는 UI_SUPERSAMPLE 배로
# 부풀려져 있어 글자 크기나 배치의 기준으로 쓰면 안 된다.
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
	_font_button = TitleArt.font(_font_heavy)

	# 나머지 조립은 Main 이 로고 화면 뒤에서 ensure_built() 로 부른다 —
	# 아직 열지도 않은 팝업 때문에 첫 프레임이 늦어지지 않도록.
	if not _built:
		return
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

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
	_elapsed += delta   # 하위 팝업의 흔들림(트로피, 캐릭터)이 쓴다


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
	_fit_patch(_panel, Vector2(pw, ph))
	_panel_rect = Rect2(px, py, pw, ph)

	var pad_x: float = pw * CONTENT_SIDE_FRAC
	_layout_content(Rect2(
		px + pad_x,
		py + ph * CONTENT_TOP_FRAC,
		pw - pad_x * 2.0,
		ph - ph * (CONTENT_TOP_FRAC + CONTENT_BOTTOM_FRAC)))



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
	if file.begins_with(KIT):
		return _kit_patch(np, file, corner)
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
	var img: Image = ArtSlot.image(ART_DIR + file)
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


# 키트 그림은 이미 표시 크기 가까이로 구워져 있어 줄이지 않고 그대로 쓴다.
# 판(PANEL_FILE)과 보조 버튼(CREAM_FILE)은 네 변 모두 9-slice 로 구운 배율
# 그대로 그린다. 주 버튼은 양 끝만 고정하고 높이는 그림째 맞춘다 — 화살촉
# 머리가 위아래로 눌리지 않게.
#
# 굽기(_bake_store)는 거치지 않는다. 구운 파일은 ui_assets 아래에 남는데,
# 키트 그림은 유료라 저장소에 들어가면 안 된다.
func _kit_patch(np: NinePatchRect, file: String, corner: int) -> NinePatchRect:
	np.texture = ArtSlot.texture(file)
	if file == GOLD_FILE or file == CREAM_FILE:
		# 버튼 막대: 양 끝의 폭이 다르다 — 왼쪽 가는 테, 오른쪽 강철 머리.
		np.patch_margin_left = BUTTON_BAR_LEFT
		np.patch_margin_right = BUTTON_BAR_RIGHT
		np.patch_margin_top = 0
		np.patch_margin_bottom = 0
		np.set_meta("fit", "height")
		return np
	var whole: bool = file == PANEL_FILE or file == SMALL_GOLD_FILE or file == SMALL_CREAM_FILE
	np.patch_margin_left = corner
	np.patch_margin_right = corner
	np.patch_margin_top = corner if whole else 0
	np.patch_margin_bottom = corner if whole else 0
	np.set_meta("fit", "fixed" if whole else "height")
	return np


## NinePatchRect 를 논리 크기 size 로 놓는다. 노드는 크게 만들고 scale 로
## 되돌린다 — 텍스처 픽셀이 화면 픽셀보다 촘촘해야 또렷하다.
##   1.x 아트      UI_SUPERSAMPLE 배(_nine_patch 가 그 폭으로 줄여 둔다)
##   키트 판       KIT_BAKE 배 — 모서리가 구운 크기 그대로
##   키트 버튼     텍스처 높이에 맞춘 배율 — 양 끝 머리가 높이와 함께 준다
func _fit_patch(np: NinePatchRect, size: Vector2) -> void:
	var k: float = UI_SUPERSAMPLE
	match str(np.get_meta("fit", "")):
		"fixed":
			k = KIT_BAKE
		"height":
			if np.texture != null and size.y > 0.0:
				k = float(np.texture.get_height()) / size.y
	np.size = size * k
	np.scale = Vector2.ONE / k


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

	# 눌렸을 때 안쪽 면을 밝히는 빛. 글자와 아이콘 아래에 깔린다.
	if file in [GOLD_FILE, CREAM_FILE, SMALL_GOLD_FILE, SMALL_CREAM_FILE]:
		var glow := Control.new()
		glow.name = "Glow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.modulate.a = 0.0
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		var tint: Color = PRESS_GLOW_GOLD if file in [GOLD_FILE, SMALL_GOLD_FILE] else PRESS_GLOW_CREAM
		glow.draw.connect(func() -> void:
			glow.draw_style_box(_pill(tint, PRESS_GLOW_RADIUS), Rect2(Vector2.ZERO, glow.size)))
		button.add_child(glow)

	var label := _make_label(text, _font_button)
	label.name = "Caption"
	if primary:
		label.add_theme_color_override("font_color", PRIMARY_LABEL_COLOR)
		label.add_theme_color_override("font_outline_color", PRIMARY_LABEL_OUTLINE)
	elif file in [CREAM_FILE, SMALL_CREAM_FILE]:
		label.add_theme_color_override("font_color", SECONDARY_LABEL_COLOR)
	button.add_child(label)

	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.texture = icon
	if file in [CREAM_FILE, SMALL_CREAM_FILE]:
		icon_rect.modulate = SECONDARY_LABEL_COLOR   # 흰 아이콘을 글자와 같은 하늘색으로
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.add_child(icon_rect)

	# 어느 아트로 만든 버튼인지 남겨 둔다 — _play_button_sound가 쓴다.
	button.set_meta("sound", GOLD_SOUND_NAME if file in [GOLD_FILE, SMALL_GOLD_FILE] else CREAM_SOUND_NAME)
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
	_fit_patch(shadow, Vector2(w, h))

	var bg: NinePatchRect = button.get_node("Background")
	bg.position = Vector2.ZERO
	_fit_patch(bg, Vector2(w, h))

	# 막대의 보이는 면: 왼쪽 가는 테와 오른쪽 강철 머리 사이, 위아래 테 안쪽.
	# 텍스처 px 를 그림과 같은 배율(bg.scale)로 화면 px 에 옮긴다.
	var face := Rect2(Vector2.ZERO, Vector2(w, h))
	if str(bg.get_meta("fit", "")) == "height" and bg.texture != null:
		var k: float = bg.scale.x
		var left: float = bg.patch_margin_left * k
		var right: float = bg.patch_margin_right * k
		var fy: float = BUTTON_BAR_FACE_Y * k if bg.patch_margin_top == 0 else 0.0
		face = Rect2(left, fy, maxf(0.0, w - left - right), maxf(0.0, h - fy * 2.0))
	elif str(bg.get_meta("fit", "")) == "fixed":
		var inset: Vector2 = BEVEL_FACE_INSET * bg.scale.x
		face = Rect2(inset, Vector2(maxf(0.0, w - inset.x * 2.0), maxf(0.0, h - inset.y * 2.0)))

	var glow: Control = button.get_node_or_null("Glow")
	if glow != null:
		glow.position = face.position
		glow.size = face.size
		glow.queue_redraw()

	var label: Label = button.get_node("Caption")
	# 글꼴은 놓을 때마다 캡션 글자에서 고른다 — 캡션은 지은 뒤에도 바뀐다(x2 의
	# AD NOT READY). 재는 글꼴과 그리는 글꼴이 같아야 폭이 맞는다.
	var label_font: Font = _caption_font(label.text)
	label.add_theme_font_override("font", label_font)
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
	# 막대 버튼은 양 끝 머리가 높이에 비례해 굵고 오른쪽이 훨씬 두껍다. 버튼 폭의 몇
	# 할이 아니라 면의 폭으로 재야, 짧은 버튼에서 글자가 강철 머리에 얹히지 않는다.
	var fit_w: float = minf(w * fit, face.size.x * KIT_BUTTON_FACE_FIT)
	var fit_h: float = h * BUTTON_TEXT_FIT_H
	var text_w := 0.0
	var icon_w := 0.0
	var gap := 0.0
	while true:
		var text_size: Vector2 = label_font.get_multiline_string_size(
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
	# 면 가운데에 — 강철 머리가 오른쪽에만 있어 버튼 가운데에 두면 오른쪽으로 쏠린다.
	var start_x: float = face.position.x + (face.size.x - group_w) * 0.5
	if icon.texture != null:
		var icon_h: float = icon_px if icon_px > 0.0 else font_size * ICON_HEIGHT_FRAC * icon_scale
		icon.size = Vector2(icon_w, icon_h)
		icon.position = Vector2(start_x, (h - icon_h) * 0.5 + content_dy)
	label.position = Vector2(start_x + icon_w + gap, content_dy)
	label.size = Vector2(text_w, h)



## 짧은 대문자 이름표(SCORE, BEST, MAX COMBO, STARDUST, SFX, MUSIC, LANGUAGE)의
## 글꼴(2026-11-28, 주인). 라틴 글자만이면 버튼과 같은 Zen Dots, 한글이면 지금까지의
## 기본 글꼴의 굵은 체 — 이유는 _caption_font 와 같다. 숫자와 문장은 기본 글꼴(Oxanium)이다.
func _label_font(text: String) -> Font:
	return _font_bold if _caption_font(text) == _font_heavy else _font_button


## 버튼 캡션의 글꼴. 라틴 글자만이면 Zen Dots, 한글이 섞이면 기본 글꼴의 굵은 체
## (한글은 AppFont 의 Do Hyeon). Zen Dots 에 한글이 없어 fallbacks 로 맡기면 그
## 한글 글꼴이 아니라 기기의 가는 고딕이 나왔다 — 한국어 버튼만 힘이 빠져 보였다.
func _caption_font(text: String) -> Font:
	for i in text.length():
		if text.unicode_at(i) >= 0x1100:
			return _font_heavy
	return _font_button


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

# 메인 시트(5x3)의 한 칸 — 2.0 에서는 키트의 같은 뜻 아이콘.
func _load_icon(index: int) -> Texture2D:
	if index == ICON_PLAY:
		return _play_icon()
	if KIT_ICONS.has(index):
		return _load_icon_from(KIT + str(KIT_ICONS[index]), Vector2i.ONE, 0)
	return _load_icon_from(ICON_SHEET, ICON_GRID, index)


# 팝업 전용 시트(3x1)의 한 칸 — 2.0 에서는 키트의 같은 뜻 아이콘.
func _load_popup_icon(index: int) -> Texture2D:
	if index == POPUP_ICON_PLAY:
		return _play_icon()
	if KIT_POPUP_ICONS.has(index):
		return _load_icon_from(KIT + str(KIT_POPUP_ICONS[index]), Vector2i.ONE, 0)
	return _load_icon_from(POPUP_ICON_SHEET, POPUP_ICON_GRID, index)


# 재생 세모. 키트에는 흰 단색 재생 아이콘이 없어(금속 질감뿐) 그린다.
# 네 배로 그려 줄여서 가장자리를 부드럽게 한다.
static var _play_tex: Texture2D

func _play_icon() -> Texture2D:
	if _play_tex != null:
		return _play_tex
	var n := ICON_TEXTURE_HEIGHT * 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var pad: float = n * 0.10
	var tri := PackedVector2Array([Vector2(pad + n * 0.08, pad),
		Vector2(pad + n * 0.08, n - pad), Vector2(n - pad, n * 0.5)])
	for y in range(n):
		for x in range(n):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), tri):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	img.premultiply_alpha()
	img.resize(ICON_TEXTURE_HEIGHT, ICON_TEXTURE_HEIGHT, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(img)
	img.generate_mipmaps()
	_play_tex = ImageTexture.create_from_image(img)
	return _play_tex


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
	return ScoreFormat.grouped(value)


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
	var sheet: Image = ArtSlot.image(sheet_path)
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
	if not sheet_path.begins_with(KIT):   # 유료 키트 그림은 굽지 않는다(_kit_patch)
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


# 소리 막대 하나. 크기는 놓는 쪽이 정한다(높이 SLIDER_BAR_HEIGHT).
func _make_slider() -> KitSlider:
	var s := KitSlider.new()
	s.frame = ArtSlot.texture(SLIDER_FRAME_FILE)
	s.arrow_left = ArtSlot.texture(SLIDER_ARROW_LEFT_FILE)
	s.arrow_right = ArtSlot.texture(SLIDER_ARROW_RIGHT_FILE)
	# 손잡이는 보조 버튼과 같은 그림을 같은 셈으로 9-slice 한다: 구운 배율
	# (KIT_BAKE)로 줄여 그리므로 모서리가 버튼의 그것과 같은 크기로 나온다.
	var handle := StyleBoxTexture.new()
	handle.texture = ArtSlot.texture(BEVEL_FILE)
	handle.texture_margin_left = BEVEL_CORNER
	handle.texture_margin_right = BEVEL_CORNER
	handle.texture_margin_top = BEVEL_CORNER
	handle.texture_margin_bottom = BEVEL_CORNER
	s.handle = handle
	s.font = _font_heavy   # 숫자는 기본 글꼴(Oxanium)
	return s


## <====[99]-------> 꼴의 0~1 막대. 값은 HSlider 와 같은 뜻이라
## (value, value_changed, set_value_no_signal) 팝업 쪽은 바뀐 것이 없다.
##
## 값을 적은 금속 상자가 손잡이다. 손잡이를 잡고 끌면 잡은 자리를 놓치지
## 않고 따라오고, 막대의 다른 곳을 누르면 손잡이가 거기로 와서 그대로 끌린다.
## 양 끝 화살표는 누를 때마다 한 칸씩 움직이는 버튼이다 — HSlider 를 덮어
## 쓰지 않고 따로 짠 이유가 이것이다.
##
## 입력은 마우스만 받는다. 터치는 프로젝트가 마우스로 흉내 내 보내므로
## (emulate_mouse_from_touch), 둘 다 받으면 한 번 누른 것이 두 번 든다.
class KitSlider extends Control:
	signal value_changed(value: float)

	var value: float = 1.0
	var frame: Texture2D
	var arrow_left: Texture2D
	var arrow_right: Texture2D
	var handle: StyleBox
	var font: Font
	var _dragging := false
	# 손잡이 가운데와 누른 자리의 거리. 손잡이를 잡고 끌 때 손가락 밑에서
	# 손잡이가 튀지 않게 둔다.
	var _grab_dx := 0.0
	# 화살표의 밝기(0~1). 누르면 1 로 켜고 SLIDER_ARROW_FLASH 동안 끈다.
	var flash_left: float = 0.0:
		set(v):
			flash_left = v
			queue_redraw()
	var flash_right: float = 0.0:
		set(v):
			flash_right = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func set_value_no_signal(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

	## 화살표 하나의 폭. 그림이 없으면 정사각형 자리.
	func _arrow_w() -> float:
		var h: float = size.y * PopupBase.SLIDER_ARROW_HEIGHT_FRAC
		if arrow_left == null or arrow_left.get_height() == 0:
			return h
		return h * float(arrow_left.get_width()) / arrow_left.get_height()

	## 두 화살표 사이의 막대. 화살표가 막대 끝을 조금 덮는다.
	func _bar() -> Rect2:
		var inset: float = _arrow_w() - size.y * PopupBase.SLIDER_ARROW_OVERLAP
		return Rect2(inset, 0.0, maxf(size.y, size.x - inset * 2.0), size.y)

	## 틀 안쪽 면의 가로 구간.
	func _face() -> Vector2:
		var bar := _bar()
		var ix: float = size.y * PopupBase.SLIDER_FACE_INSET_X
		return Vector2(bar.position.x + ix, bar.end.x - ix)

	func _handle_w() -> float:
		return size.y * PopupBase.SLIDER_HANDLE_WIDTH_FRAC

	## 손잡이 가운데가 0 에서 1 까지 오가는 구간. 손잡이가 면 밖으로 안 나간다.
	func _handle_span() -> Vector2:
		var face := _face()
		var half: float = _handle_w() * 0.5
		return Vector2(face.x + half, face.y - half)

	func _handle_rect() -> Rect2:
		var span := _handle_span()
		var cx: float = lerpf(span.x, span.y, value)
		var hh: float = size.y * PopupBase.SLIDER_HANDLE_HEIGHT_FRAC
		return Rect2(cx - _handle_w() * 0.5, (size.y - hh) * 0.5, _handle_w(), hh)

	func _value_at(centre_x: float) -> float:
		var span := _handle_span()
		return (centre_x - span.x) / maxf(1.0, span.y - span.x)

	func _set_from_user(v: float) -> void:
		v = clampf(snappedf(v, 0.01), 0.0, 1.0)
		if is_equal_approx(v, value):
			return
		value = v
		queue_redraw()
		value_changed.emit(value)

	func _flash(prop: String) -> void:
		set(prop, 1.0)
		create_tween().tween_property(self, prop, 0.0, PopupBase.SLIDER_ARROW_FLASH)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not event.pressed:
				_dragging = false
				queue_redraw()
				return
			var x: float = event.position.x
			if x < _arrow_w():
				_set_from_user(value - PopupBase.SLIDER_STEP)
				_flash("flash_left")
			elif x > size.x - _arrow_w():
				_set_from_user(value + PopupBase.SLIDER_STEP)
				_flash("flash_right")
			else:
				_dragging = true
				var hr := _handle_rect()
				# 손잡이를 잡았으면 잡은 자리를 지키고, 아니면 손잡이를 그리로 부른다.
				_grab_dx = x - hr.get_center().x if hr.has_point(Vector2(x, hr.get_center().y)) else 0.0
				_set_from_user(_value_at(x - _grab_dx))
				queue_redraw()
		elif event is InputEventMouseMotion and _dragging:
			accept_event()
			_set_from_user(_value_at(event.position.x - _grab_dx))

	func _draw() -> void:
		var bar := _bar()
		var h: float = size.y
		var face := _face()
		var iy: float = h * PopupBase.SLIDER_FACE_INSET_Y
		var top: float = iy
		var bottom: float = h - iy
		# 1. 틀 안쪽 면. 틀 그림은 가운데가 비어 있어 바탕을 따로 깐다.
		draw_rect(Rect2(face.x - h * 0.15, top, face.y - face.x + h * 0.3, bottom - top),
			PopupBase.SLIDER_FACE_COLOR)
		# 2. 채움. 면 왼쪽 끝에서 손잡이 가운데까지, 왼쪽 어둡고 오른쪽 밝게.
		var hr := _handle_rect()
		var x1: float = hr.get_center().x
		if x1 > face.x + 0.5:
			var right_col: Color = PopupBase.SLIDER_FILL_DARK.lerp(PopupBase.SLIDER_FILL_BRIGHT, value)
			draw_polygon(PackedVector2Array([
					Vector2(face.x, top), Vector2(x1, top), Vector2(x1, bottom), Vector2(face.x, bottom)]),
				PackedColorArray([PopupBase.SLIDER_FILL_DARK, right_col, right_col, PopupBase.SLIDER_FILL_DARK]))
			draw_rect(Rect2(face.x, top, x1 - face.x, (bottom - top) / 3.0), PopupBase.SLIDER_FILL_SHINE)
		# 3. 틀. 양 끝 조각은 그대로, 가운데만 늘인다(_draw_horizontal_slice 와 같은 셈).
		if frame != null:
			var tw: float = frame.get_width()
			var th: float = frame.get_height()
			var cap: float = h * PopupBase.SLIDER_CAP_FRAC
			var tcap: float = cap * th / h
			var x0: float = bar.position.x
			draw_texture_rect_region(frame, Rect2(x0, 0, cap, h), Rect2(0, 0, tcap, th))
			draw_texture_rect_region(frame, Rect2(x0 + cap, 0, bar.size.x - cap * 2.0, h),
				Rect2(tcap, 0, tw - tcap * 2.0, th))
			draw_texture_rect_region(frame, Rect2(bar.end.x - cap, 0, cap, h), Rect2(tw - tcap, 0, tcap, th))
		# 4. 양 끝 화살표. 누르면 잠깐 밝아진다.
		var aw: float = _arrow_w()
		var ah: float = h * PopupBase.SLIDER_ARROW_HEIGHT_FRAC
		var ay: float = (h - ah) * 0.5
		if arrow_left != null:
			draw_texture_rect(arrow_left, Rect2(0, ay, aw, ah), false,
				Color.WHITE.lerp(Color(1.6, 1.6, 1.6), flash_left))
		if arrow_right != null:
			draw_texture_rect(arrow_right, Rect2(size.x - aw, ay, aw, ah), false,
				Color.WHITE.lerp(Color(1.6, 1.6, 1.6), flash_right))
		# 5. 손잡이와 값(0~100). 9-slice 는 구운 배율로 키운 자리에 그리고 줄인다.
		if handle != null:
			var k: float = PopupBase.KIT_BAKE
			draw_set_transform(hr.position, 0.0, Vector2.ONE / k)
			var tint: Color = PopupBase.SLIDER_HANDLE_HELD if _dragging else Color.WHITE
			handle.modulate_color = tint
			draw_style_box(handle, Rect2(Vector2.ZERO, hr.size * k))
			draw_set_transform(Vector2.ZERO)
		if font != null:
			var fs: int = maxi(8, int(round(hr.size.y * PopupBase.SLIDER_NUMBER_FRAC)))
			var baseline: float = hr.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
			draw_string(font, Vector2(hr.position.x, baseline), str(int(round(value * 100.0))),
				HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, fs, PopupBase.SLIDER_NUMBER_COLOR)


# 슬라이더 두 줄의 왼쪽 칸(아이콘 + 이름표)을 ctrl 위에 그린다.
# 막대는 KitSlider 자신이 그린다.
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
		ctrl.draw_string(_label_font(text), Vector2(x, centre_y + font_size * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


# 이름표 칸의 폭. 비율로 잡으면 긴 이름("MUSIC")이 트랙에 물려서, 실제로 재서 정한다.
func _slider_label_column(font_size: int, texts: Array) -> float:
	var w := 0.0
	for text in texts:
		w = maxf(w, _label_font(text).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# 아이콘(글자 높이와 같은 정사각형 가정) + 간격 + 글자 + 트랙까지 숨돌릴 틈
	return w + font_size * (1.0 + SLIDER_ICON_GAP_FRAC) + font_size * 0.5


# 아이콘 없이 칸을 통째로 쓰는 이름표(LANGUAGE)용 — 슬라이더와 같은
# 칸을 나눠 쓰므로 둘 다 재서 넓은 쪽을 골라야 한다. 슬라이더 쪽만 재면
# 이름표가 트랙 밑으로 파고든다: "LANGUAGE" 가 "MUSIC" 보다 길다.
func _row_label_column(font_size: int, texts: Array) -> float:
	var w := 0.0
	for text in texts:
		w = maxf(w, _label_font(text).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return w + font_size * 0.5


# ---- 두 갈래 토글 ----
#
# 알약 모양 트랙 위를 손잡이가 좌우로 옮겨 다니고, 두 칸에 각각 이름이 적힌다.
# 지금 쓰는 곳은 설정 팝업의 언어(ENG/KOR) 하나뿐이다.
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
const TOGGLE_OFF_TEXT := Color(0.50, 0.60, 0.72, 1.0)
const TOGGLE_ON_TEXT := Color(0.02, 0.10, 0.20, 1.0)   # 하늘색 손잡이 위라 어둡게


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
		var tw: float = _font_button.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx: float = TOGGLE_PAD + knob_w * (float(i) + 0.5)
		var lit: bool = (i == 1) == second
		t.draw_string(_font_button, Vector2(cx - tw * 0.5, h * 0.5 + fs * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TOGGLE_ON_TEXT if lit else TOGGLE_OFF_TEXT)


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
	button.set_meta("art", ArtSlot.texture(CANCEL_FILE))
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


## 판 바로 위에 크게 쓰는 제목(2026-11-28): 틀 없이 Zen Dots 글자만, 금색에
## 어두운 테두리. 1.x 의 OOPS·TRY AGAIN·SETTINGS 그림 자리에 들어간다. 그림이었던
## 말이라 영어 그대로다(CLAUDE.md, Language) — Zen Dots 에는 한글도 없다.
##
## 처음에는 키트의 머리 모양 틀에 써서 판 윗변에 반쯤 걸쳤고, 다음에는 주황
## 막대(Bar_Frame_08)에 써서 판 위에 따로 얹었다. 주인이 판과 겹치지 않게,
## 그리고 틀 없이 글자만 크게 해 달라고 했다.
const TITLE_TEXT_COLOR := Color(1.0, 0.86, 0.45, 1.0)
const TITLE_TEXT_RIM := Color(0.20, 0.08, 0.0, 1.0)
const TITLE_RIM_FRAC := 0.14       # 글자 크기 대비 테두리 두께
const TITLE_FONT_FRAC := 0.12      # 판 너비 대비 글자 크기 — 이보다 크게는 안 쓴다
# 글자 폭의 상한(판 너비 대비). 닫기 버튼(판 오른쪽 위 모서리에 반쯤 걸친)이
# 판 폭의 87% 지점부터 시작하므로, 가운데 놓인 글자가 거기 닿지 않을 만큼 —
# 0.74 에서는 SETTINGS 의 끝 글자가 테두리째 버튼에 닿았다.
const TITLE_WIDTH_FRAC := 0.66
const TITLE_GAP := 6.0             # 판 윗변과 글자 바닥 사이
const TITLE_SCREEN_MARGIN := 2.0   # 화면 위 끝과의 최소 간격

func _make_title(text: String) -> Control:
	var title := Control.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.set_meta("text", text)
	title.draw.connect(_draw_title.bind(title))
	return title


## 판 위 공간이 모자란 화면(16:9 의 설정 팝업은 판 위가 60px 남짓이다)에서는
## 그 공간에 맞춰 글자를 줄인다.
func _place_title(title: Control) -> void:
	if title == null:
		return
	var text: String = title.get_meta("text", "")
	var font: Font = TitleArt.font(_font_heavy)
	var room: float = _panel_rect.position.y - TITLE_GAP - TITLE_SCREEN_MARGIN
	var fs: int = int(round(_panel_rect.size.x * TITLE_FONT_FRAC))
	while fs > 10 and (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			> _panel_rect.size.x * TITLE_WIDTH_FRAC or font.get_ascent(fs) > room):
		fs -= 1
	title.set_meta("font_size", fs)
	var h: float = font.get_ascent(fs)
	title.size = Vector2(_panel_rect.size.x, h)
	title.position = Vector2(_panel_rect.position.x, _panel_rect.position.y - TITLE_GAP - h)
	title.queue_redraw()


func _draw_title(title: Control) -> void:
	var text: String = title.get_meta("text", "")
	var fs: int = title.get_meta("font_size", 0)
	if fs <= 0:
		return
	var font: Font = TitleArt.font(_font_heavy)
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# 바닥(기준선)을 칸 아래 끝에 — 판과의 간격이 TITLE_GAP 그대로 보인다.
	var base := Vector2((title.size.x - tw) * 0.5, title.size.y)
	title.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		maxi(2, int(round(fs * TITLE_RIM_FRAC))), TITLE_TEXT_RIM)
	title.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TITLE_TEXT_COLOR)


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
			# 한 번만 말하고 다시 찾지 않는다. 조용히 넘기면 버튼이 소리를
			# 잃었을 때, 소리를 끈 것인지 파일이 없는 것인지 화면으로는 구별할
			# 길이 없다.
			push_warning("PopupBase: %s%s(%s) 가 없다 — 이 버튼은 소리 없이 눌린다" % [
				BUTTON_SOUND_DIR, art, "/".join(BUTTON_SOUND_EXTENSIONS)])
			_button_players[art] = null
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
	var glow: CanvasItem = button.get_node_or_null("Glow")
	if glow != null:
		tween.tween_property(glow, "modulate:a", 1.0, PRESS_ANIM_DURATION) \
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
	var glow: CanvasItem = button.get_node_or_null("Glow")
	if glow != null:
		tween.tween_property(glow, "modulate:a", 0.0, PRESS_GLOW_FADE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv
