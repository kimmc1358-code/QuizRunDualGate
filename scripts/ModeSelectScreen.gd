extends Control

## Main menu / mode picker, built from the painted art in
## assets/ui_assets/main/.
##
## Laid out in code rather than as scene nodes because the viewport is a
## fixed 480 wide but a height that varies with the device — 854 on 16:9, up
## to ~1066 on 20:9, since the project stretches with aspect "expand". Every
## piece is sized from its own aspect ratio against the screen width, and the
## leftover height is shared out between them, so the column stays put at the
## top and bottom on any phone instead of drifting or overflowing.
##
## Only the cards and START act. The leaderboard logs "[미구현]" so a tap is
## visibly registered rather than silently ignored.

signal start_pressed(mode: int)
signal login_pressed
signal settings_pressed

# Mirrors Main.gd's Mode enum. The mode-select sheet's quadrants are read in
# reading order, so top-left is SKY and the fourth is the hidden slot.
const MODE_SKY := 0
const MODE_JUNGLE := 1
const MODE_OCEAN := 2
const MODE_HIDDEN := 3
const CARD_MODES := [MODE_SKY, MODE_JUNGLE, MODE_OCEAN, MODE_HIDDEN]
# Which quadrant of the sheet each slot draws. The sheet reads blue, green,
# cyan, pink; the left column is flipped so the mint card sits on top, which
# is why this is a mapping rather than a straight 0,1,2,3.
const CARD_SHEET_SLOT := [2, 1, 0, 3]

# Characters shown on the cards, in slot order. The fourth is the hidden
# mode and has no art yet — an empty path leaves that card blank.
const CARD_CHARACTER_SHEET := [
	"res://assets/characters/bird_v2/bird_fly.png",
	"res://assets/characters/dragon_green/dragon_fly.png",
	"res://assets/characters/shark_blue/shark_swim.png",
	"res://assets/characters/unicorn_dream/unicorn_run.png",
]
# 칸 나눔은 시트마다 다르다 — 유니콘만 3x2(6프레임)다. Main.gd 의
# MODE_CHARACTER_SHEET_GRID 와 같은 값을 써야 게임 안팎이 같은 동작을 보인다.
const CARD_CHARACTER_GRID := [Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(3, 2)]
const CARD_CHARACTER_FPS := 8.0
# Main.gd 의 MODE_VISUAL_SIZE_SCALE 과 같은 값. 이게 없으면 네 캐릭터가
# 카드에서 모두 같은 칸에 그려져, 게임 안에서 맞춰 둔 서로의 크기 관계가
# 깨진다 — 특히 유니콘은 게임에서 드래곤과 같은 높이로 읽히도록 1.20 배를
# 주는데, 그게 빠지면 카드에서만 눈에 띄게 작아진다.
#
# 칸 한 변을 art_h * 이 배수로 잡으면, 화면에 보이는 크기의 게임 대비 비율이
# 모드와 무관하게 art_h / PLAYER_VISUAL_SIZE.y 로 같아진다.
const CARD_CHARACTER_SCALE := [0.92, 1.0, 1.0, 1.20]
# Measured off each sheet the same way Main.gd's MODE_DRAW_OFFSET_FLY is,
# and scaled to whatever size the card draws the sprite at.

# Space inside a card, as fractions of its height: a name across the top, the
# character in the middle, the best score along the bottom.
const CARD_NAME_HEIGHT_FRAC := 0.17
const CARD_BEST_HEIGHT_FRAC := 0.15
const CARD_ART_HEIGHT_FRAC := 0.58
const CARD_TEXT_INSET_FRAC := 0.06     # of card height, kept clear of the border
const CARD_NAMES := ["FLAG MODE", "MATH MODE", "STROOP MODE", "MIX MODE"]
# Sized so the longest name fits its card, then used for all of them, so the
# titles do not step up and down from card to card.
const CARD_NAME_WIDTH_FRAC := 0.90     # of the card's inner width
const CARD_NAME_MAX_SIZE := 22
const CARD_NAME_MIN_SIZE := 9
const CARD_NAME_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const CARD_NAME_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
const CARD_NAME_OUTLINE_FRAC := 0.18   # of the font size
# The title sits on its own rounded plate. Its width is taken from the
# longest name — STROOP MODE — and then used on every card, so the plates
# line up as a set rather than each hugging its own text.
const CARD_NAME_PLATE_COLOR := Color(0.16, 0.17, 0.20, 0.55)
const CARD_NAME_PLATE_RADIUS := 6
const CARD_NAME_PLATE_PAD_FRAC := 0.32   # of the plate's height, at each end

# 최고 점수는 둥근 흰 판 위에 얹힌다. 판 너비는 카드 너비 비율(CARD_BEST_PLATE_WIDTH_FRAC)
# 로만 정해지므로 숫자가 길어져도 판은 그대로다 — 숫자를 다섯 자리로 채워
# 넣던 시절이 있었지만, 판을 붙잡고 있던 것은 그 자리 채우기가 아니라
# 이 비율이었다. 표기는 ScoreFormat.compact 를 따른다.
const CARD_BEST_PLATE_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const CARD_BEST_PLATE_RADIUS := 6
const CARD_BEST_PLATE_WIDTH_FRAC := 0.86   # of the card's inner width
# "BEST" 글자는 게임 화면 상단의 BEST 와 같은 노랑 + 검정 테두리다. 같은 것을
# 가리키는 두 자리라 같아 보여야 한다 — 예전에는 여기만 남색 민글자였다.
#
# 값은 Main.gd 의 BEST_LABEL_FILL / SCORE_TEXT_OUTLINE 과 같아야 하고,
# tools/check_score_format.gd 가 두 값이 갈라지지 않았는지 본다. 여기서
# Main 을 참조할 수는 없다 — 이 화면은 Main 을 모르는 쪽이다.
const CARD_BEST_COLOR := Color(0.99, 0.80, 0.22, 1.0)
const CARD_BEST_OUTLINE := Color(0.06, 0.06, 0.09, 1.0)
const CARD_BEST_OUTLINE_FRAC := 0.16   # 글자 크기 대비 — 옆 숫자와 같은 굵기
# The plate holds three things in a row — crown, the word BEST, the number —
# centred as a group. The number is styled like the card titles rather than
# like the word beside it, so the score is what the eye lands on.
# 게임 화면 HUD 와 같은 왕관을 쓴다. ART_DIR 바깥이라 전체 경로로 준다.
const CARD_BEST_CROWN_FILE := "res://assets/ui_assets/popup/icon_crown.png"
const CARD_BEST_CROWN_HEIGHT_FRAC := 0.78   # of the plate's height
# 잘라 낸 그림 둘레에 두르는 투명 여백(그림 크기 대비)과 미리 줄여 둘 높이.
const TRIM_INK_PAD_FRAC := 0.06
const TRIM_INK_BAKE_H := 128
const CARD_BEST_ROW_SEPARATION_FRAC := 0.22 # of the plate's height, between items
const CARD_SCORE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const CARD_SCORE_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
# Extra px between the BEST digits. Fredoka sets figures tight, and at this
# size the five zeros run together into one block; a single pixel is enough
# to read them as separate digits without the number looking spaced out.
const CARD_SCORE_TRACKING := 1
# 속색과 같은 검정 테두리라 "테두리"로 보이지 않고 글자가 그만큼 굵어진다.
# Fredoka 는 wght 700 이 끝이라, 더 굵게 하려면 이 방법밖에 없다.
const CARD_SCORE_OUTLINE_FRAC := 0.16

# Fredoka is variable on a wght axis (300-700). Main.gd uses 600 for text and
# 700 for the score digits; the same two weights are used here.
const FONT_WEIGHT_BOLD := 600
const FONT_WEIGHT_HEAVY := 700

# One line each, sized so the longest of them fits — every mode then reads at
# the same size, which a per-string fit would not give.
#
# 네 번째 줄은 MIX 가 잠겨 있을 때의 안내다. 열려 있으면
# CARD_EXPLAIN_HIDDEN_OPEN 이 대신 나간다 — hidden_mode_open 을 볼 것.
const CARD_EXPLAIN := [
	"Find the flag that matches the country!",
	"Solve the math problem and find the answer!",
	"Choose the COLOR, not the word!",
	"",   # 히든 모드는 잠금 상태에 따라 두 문장이다 — 아래 두 상수를 볼 것
]
const CARD_EXPLAIN_HIDDEN_OPEN := "All three quizzes, one after another!"
# 잠겼을 때. 조건과 함께 어디까지 왔는지도 보인다 — 조건만 적으면 이미 두
# 모드를 채운 사람과 하나도 안 한 사람에게 같은 문장이 나가고, 얼마나 남았는지
# 알 방법이 게임 안에 없다. 인자는 (게이트 수, 채운 모드, 필요한 모드).
const CARD_EXPLAIN_HIDDEN_LOCKED := "Pass %d gates in every mode to unlock!  %d/%d"

## 히든 모드(MIX)가 열려 있는지. Main 이 저장된 진행도를 보고 정해서
## set_hidden_progress 로 넘긴다 — 이 화면은 세이브 파일을 모른다.
##
## 기본값이 false 인 것이 맞다. 진행도가 아직 안 넘어온 순간(부팅 중 한두
## 프레임)에 열린 것으로 그렸다가 잠기면, 열렸던 것이 도로 잠긴 것처럼 보인다.
##
## 카드 설명문도 이 값을 따라간다. 둘을 따로 두면 반드시 어긋난다: 잠긴 채로
## "세 퀴즈가 번갈아 나온다"고 적으면 눌러도 안 되는 카드를 광고하는 꼴이고,
## 열린 채로 "게이트를 더 지나면 열린다"고 적으면 이미 열린 것을 못 연 것처럼
## 안내한다. tools/check_mode_card_check.gd 가 두 상태 모두에서 짝이 맞는지
## 본다.
@export var hidden_mode_open: bool = false
# 잠금 안내에 들어가는 숫자. Main 의 HIDDEN_UNLOCK_GATES 와 모드 수가 그대로
# 넘어온다 — 여기에 같은 값을 또 적어 두면 한쪽만 고쳤을 때 안내문이 거짓말을
# 한다.
var hidden_gates_needed: int = 10
var hidden_modes_cleared: int = 0
var hidden_modes_required: int = 3
# The explain bar's ends are round, and their radius is a large fraction of
# its height. Nine-slice cannot shorten a shape like that: it draws corners
# at native size, so the caps would either overlap or, stretched, turn into
# ellipses.
#
# Drawn in three horizontal pieces instead. Each cap is scaled uniformly, so
# it keeps its shape at any height, and only the middle — flat horizontal
# bands — is stretched across the gap. Height is then free to change without
# distorting anything, and the border thickness scales with it, which is what
# keeps it reading as the same bar rather than a thinner one with a heavy
# outline.
#
# The cap width and the art's own bounds are measured off the file rather
# than written down. The bar has already been swapped once — from a pill in
# a tight canvas to a rounded rectangle sitting in a lot of transparent
# padding — and fixed numbers would have quietly drawn that padding as if it
# were the bar.
const EXPLAIN_HEIGHT_SCALE := 0.80      # squash against the height its width would imply
const EXPLAIN_TEXT_WIDTH_FRAC := 0.86   # of the bar, keeping the text off its border
const EXPLAIN_TEXT_MAX_SIZE := 20
const EXPLAIN_TEXT_MIN_SIZE := 9
const EXPLAIN_TEXT_COLOR := Color(0.12, 0.18, 0.30, 1.0)

# 선택된 카드는 테두리가 아니라 "들려 있음"으로 표시한다: 살짝 커지고,
# 그림자가 깊어지고, 왼쪽 위 구석에 초록 체크가 붙는다.
#
# 예전에는 카드 가장자리를 따라 도는 노란 링과 그 바깥의 후광이었다. 링은
# 카드 아트가 이미 가지고 있는 흰 테두리 바로 위에 앉는데, 네 카드의 아트가
# 셀 안에서 조금씩 다른 자리에 있어서(_card_art_bounds) 어느 카드를 고르냐에
# 따라 테두리가 두꺼워 보이거나 어긋나 보였다.
const CARD_SELECTED_SCALE := 1.05
const CARD_SELECT_ANIM := 0.12          # seconds, 크기가 옮겨 가는 시간

# 그림자는 카드 뒤에 따로 그린다(_card_shadow_overlay). TextureButton 에는
# 그림자가 없고, 카드 아트에 구워 넣으면 선택에 따라 깊어질 수가 없다.
# 고른 카드에만 그린다 — 안 고른 카드까지 바뀌는 것은 요청이 아니었고,
# 하나만 떠 있는 편이 "이게 골라졌다"를 더 분명히 말한다.
const SELECT_CORNER_NATIVE := 70.0
const SELECT_SHEET_WIDTH_NATIVE := 706.0
# 처음에 14 / (0,7) / 0.62 로 잡았다가 화면에서 보고 낮췄다. 카드가 105% 로
# 커지는 것과 체크가 이미 "골랐다"를 말하고 있어서, 그 위에 짙은 그림자까지
# 얹으니 카드가 들린 게 아니라 화면에서 떨어져 나온 것처럼 보였다.
const SELECT_SHADOW_SIZE := 9
const SELECT_SHADOW_OFFSET := Vector2(0, 4)
const SELECT_SHADOW_COLOR := Color(0.16, 0.10, 0.02, 0.34)
# The card art fades out along its bottom edge, so the opaque bounds the
# shadow is placed on stop just short of where the card looks like it ends.
# Nudged down to close that gap.
const SELECT_BOTTOM_EXTEND_FRAC := 0.022   # of the card's height

# 고른 카드의 왼쪽 위 구석에 붙는 초록 체크. tools/slice_popup_icons_2.ps1 이
# icon_popup_2.png 에서 잘라 낸다.
#
# 그 구석이 비어 있는 것은 우연이 아니라 배치의 결과다: 이름판은 가운데
# 정렬이라 양옆에 여백이 남고(_layout_card 의 name_plate_w), 캐릭터는 이름
# 줄 아래에서 시작한다. 그래도 카드마다 이름 길이와 캐릭터 배율(유니콘 1.20)이
# 달라 여백이 같지 않으므로, 네 카드 전부에서 글자와 캐릭터를 안 가리는지는
# tools/check_mode_card_check.gd 가 실제 사각형으로 확인한다.
const CARD_CHECK_FILE := "res://assets/ui_assets/popup/icon_check.png"
const CARD_CHECK_SIZE_FRAC := 0.19      # of the card art's width
const CARD_CHECK_MARGIN_FRAC := 0.015   # of the card art's width, in from the corner

# 잠긴 히든 모드 카드의 자물쇠. 체크와 같은 시트에서 나온 같은 크기의 동그란
# 아이콘이라 크기·여백 상수를 공유한다.
#
# 오른쪽 위 구석에 붙는다. 체크의 반대쪽인데, 이유는 대칭이 예뻐서가 아니라
# 잠긴 카드도 고를 수 있기 때문이다 — 고르면 왼쪽 위에 체크가 붙으므로 같은
# 구석에 두면 둘이 겹친다. 이름판이 가운데 정렬이라 양쪽 구석의 크기는 같고,
# 따라서 자물쇠는 체크와 같은 크기로 들어간다.
#
# 잠금은 설명 바의 문구로도 알 수 있지만, 그건 카드를 눌러 봐야 읽힌다.
# 누르기 전에 보이는 표시가 하나는 있어야 한다.
const CARD_LOCK_FILE := "res://assets/ui_assets/popup/icon_lock.png"

# START gets the same halo treatment as the selected card. Its plate is a
# rounded rectangle of radius 120 in a 1024-wide source, measured the same
# way the card's was.
const START_CORNER_NATIVE := 120.0
const START_SHEET_WIDTH_NATIVE := 1024.0
const START_GLOW_COLOR := Color(1.0, 0.88, 0.35, 0.16)
const START_GLOW_RINGS := 10
const START_GLOW_BORDER := 5.0        # ring thickness in screen pixels
const START_GLOW_SPREAD := 2.2        # how far out the halo reaches, in ring widths

# The chosen card's character drifts, so the selection reads as alive even
# before the flap cycle registers.
const CARD_BOB_AMPLITUDE_FRAC := 0.045  # of the art area's height
# bob 한 주기 = 날갯짓 몇 바퀴. 고정 초로 두면 안 된다 — 날갯짓 한 바퀴는
# 프레임 수에 달려 있어서(8 FPS 기준 4장이면 0.5초, 유니콘은 5장이라 0.625초),
# bob 을 1.5초로 못박으면 4장짜리는 정확히 3바퀴에 맞물리지만 유니콘만
# 2.4바퀴로 어긋난다. 그러면 날갯짓이 매번 bob 의 다른 지점에서 일어나
# 유니콘 카드만 툭툭 튀는 것처럼 보인다. 바퀴 수로 잡으면 다 맞물린다.
const CARD_BOB_LOOPS := 3.0

const ART_DIR := "res://assets/ui_assets/main/"
const BACKGROUND_FILE := "background_main.png"
const TITLE_FILE := "title_main_v2.png"
const CARD_SHEET_FILE := "modeselect_main.png"
const EXPLAIN_FILE := "explain_box.png"
const LEADERBOARD_FILE := "leaderboard_v2.png"
const START_FILE := "start_main.png"

# Icon sheet, 5 across and 3 down. The icons are dark navy on transparent —
# invisible against a dark backdrop, which is only a preview problem: on the
# gold leaderboard plate they read clearly. Reading order, so the trophy on
# the top row's fourth column is index 3.
const ICON_SHEET_FILE := "icon_sheet.png"
const ICON_SHEET_GRID := Vector2i(5, 3)
const ICON_TROPHY_INDEX := 3
# Each icon sits in a lot of empty cell, so it is trimmed to its own art
# before placing — otherwise the padding, not the trophy, gets centred.
const TROPHY_HEIGHT_FRAC := 0.52      # of the leaderboard button's height
const TROPHY_LEFT_FRAC := 0.09        # of the button's width, from its left edge

# Label on the leaderboard plate, styled like START's. It is centred in the
# space left of it by the trophy rather than on the whole plate, so the icon
# and the word read as one balanced group instead of the word sitting off to
# one side of centre.
const LEADERBOARD_LABEL := "LEADERBOARD"
const LEADERBOARD_LABEL_HEIGHT_FRAC := 0.40   # of the plate's height
const LEADERBOARD_LABEL_MIN_SIZE := 8
const LEADERBOARD_LABEL_PAD_FRAC := 0.05      # of the plate's width, kept off its right edge

# Tap cues. Loaded only if present and played only if loaded, the same
# defensive shape as the sounds in Main.gd — removing a file leaves a silent
# button rather than a crash.
const SFX_DIR := "res://assets/audio/"
const SFX_SELECT_FILE := "modeselection.wav"
const SFX_START_FILE := "start_main.wav"
# 팝업의 크림 버튼과 같은 소리 — 위쪽 구석 버튼 둘이 쓴다.
const SFX_CREAM_FILE := "button_cream.wav"

# The START art is a blank plate, so the word is drawn on top of it.
const FONT_PATH := "res://assets/fonts/Fredoka.ttf"
const START_LABEL := "START"
const START_LABEL_HEIGHT_FRAC := 0.44   # of the button's height
const START_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const START_LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)
const START_LABEL_OUTLINE_SIZE_FRAC := 0.16  # of the font size

# Press feedback, matching the pause/mute buttons in Main.gd: a quick squash
# in, then a springy return that slightly overshoots.
const PRESS_SCALE := 0.94
const PRESS_ANIM_DURATION := 0.08

# The card sheet was exported without an alpha channel, so its four cards sit
# on flat black, and the white border meets that black through a single
# anti-aliased pixel — measured at around brightness 80 where the border
# itself is 250+.
#
# Simply thresholding leaves that pixel fully opaque and dark, which is the
# black rim it produced around every card. It is really a premultiplied
# blend: a pixel covering the backdrop by k reads as border * k, so the
# coverage is its brightness and the true colour is that brightness divided
# back out.
#
# Applying that everywhere would make the card bodies translucent, since a
# pastel fill is not full brightness either. So it is applied only to pixels
# that actually touch the backdrop — the rim — and everything else stays
# opaque with its colour untouched. A histogram of the sheet backs the
# thresholds up: 0-31 is the backdrop, 192-255 the art, and barely a
# thousand pixels lie between.
const KEY_FLOOR := 10      # at or below: backdrop
const KEY_SOLID := 192     # at or above: art, left alone

# Widths as a fraction of the screen; each piece's height follows from its
# own aspect ratio.
const TITLE_WIDTH_FRAC := 0.70
# 화면 맨 위 두 구석의 작은 버튼 — 왼쪽 로그인, 오른쪽 설정.
# tools/slice_login_setting.gd 가 한 시트에서 잘라 낸 것이라 둘의 캔버스가
# 같고, 그래서 같은 크기로 그려진다.
const LOGIN_FILE := "login.png"
const SETTING_FILE := "setting.png"
const TOP_ICON_HEIGHT_FRAC := 0.055   # of screen height
const TOP_ICON_MARGIN_X_FRAC := 0.030 # of screen width
const TOP_ICON_MARGIN_Y_FRAC := 0.022 # of screen height
const CARDS_WIDTH_FRAC := 0.84
const CARD_GAP_FRAC := 0.030      # of screen width, between the two columns
# 카드는 아트가 그려진 비율보다 세로로 늘려 그린다. 폭과 카드 사이 간격은
# 그대로다.
#
# 늘어난 몫은 블록 사이 간격에서 나온다 — 이 화면에 놀고 있는 세로는 없다.
# 남는 높이는 전부 간격으로 가고 MAX_GAP_FRAC 상한에도 안 닿기 때문에(21:9
# 에서도 49px 대 상한 62px), "안 쓰는 자리를 가져온다"는 방법은 한 픽셀도 못
# 얻는다. 재 봤다.
#
# 그래서 간격을 줄여 가며 늘리되, CARD_GROW_MIN_GAP_FRAC 밑으로는 안 내려간다.
# 화면이 짧을수록 덜 늘어나고, 16:9 는 원래 간격이 1.9px 뿐이라 그대로다 —
# 거기서 억지로 늘리면 제목과 카드가 서로 파고든다.
const CARD_HEIGHT_SCALE := 1.18
const CARD_GROW_MIN_GAP_FRAC := 0.014   # of screen height
# The explain bar takes its width from the cards rather than a fraction of
# its own, so its ends line up exactly with the outer edges of the left and
# right columns however the cards are sized.
const LEADERBOARD_WIDTH_FRAC := 0.52
const START_WIDTH_FRAC := 0.72

# Ad removal — the text is a placeholder for a purchase that does not exist
# yet, so it logs like the leaderboard does. Underlined to read as a link
# rather than as a caption; Label has no underline, so it is drawn.
const REMOVE_ADS_TEXT := "Remove Ads"
const REMOVE_ADS_FONT_FRAC := 0.022    # of screen height
const REMOVE_ADS_BLOCK_FRAC := 0.040   # of screen height, the tappable band
const REMOVE_ADS_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const REMOVE_ADS_UNDERLINE_GAP := 2.0
const REMOVE_ADS_UNDERLINE_WIDTH := 1.5
# ---- 하단 배너 자리 ----
#
# AdMob 배너는 Godot 뷰포트 밖에 얹히는 안드로이드 View 라, 화면이 그만큼
# 아래를 비워 주지 않으면 그냥 덮는다. 여기서 비우는 것은 "배너가 앉을 자리"
# 뿐이고, 배너 자체를 그리지는 않는다 — 플러그인이 붙으면 실제 배너 높이를
# set_banner_reserve 로 넘겨 주면 된다.
#
# 픽셀 단위이고 게임 좌표다. 플러그인이 주는 값은 기기 픽셀이므로
# (480 / 실제 화면 폭) 을 곱해 넘겨야 한다 — 뷰포트 폭은 480 으로 고정이고
# 기기 폭은 제각각이라, 그대로 넘기면 기기마다 어긋난다.
#
# 넣고도 최소 간격이 남는 화면에서만 실제로 비운다. 실측(480 폭 기준)으로
# 겹치기 직전까지 쓸 수 있는 높이가 16:9 에서 11px, 18:9 에서 118px,
# 20:9 에서 225px 다. 50dp 배너가 20:9 에서 약 67 게임 px 이니 긴 화면은
# 넉넉하고 16:9 는 애초에 자리가 없다. 억지로 비우면 START 가 카드를 덮는다.
@export var banner_reserve_px: float = 0.0
# 배너를 비우고도 블록 사이에 남아야 할 최소 간격, 화면 픽셀.
#
# 화면 높이 비율이 아니라 절대값이다. 처음에 0.012 로 잡았더니 18:9 에서
# 11.5px 을 요구했는데, 정작 이 화면은 배너 없이도 16:9 에서 1.8px 간격으로
# 돈다 — 기준이 게임이 이미 굴러가는 상태보다 엄격했고, 자리가 118px 이나
# 남는 18:9 가 거부됐다. 여기서 막고 싶은 것은 "빽빽함"이 아니라 겹침이므로,
# 0 을 조금 넘는 값이면 된다.
const BANNER_MIN_GAP_PX := 6.0

const TOP_MARGIN_FRAC := 0.035    # of screen height
const BOTTOM_MARGIN_FRAC := 0.035
const MAX_GAP_FRAC := 0.055       # cap, so a tall screen spreads rather than sprawls

var selected_index: int = 0

var _background: TextureRect
var _title: TextureRect
var _explain: Control
var _explain_texture: Texture2D
var _start_glow: Control
var _start_bounds := Rect2(0, 0, 1, 1)
var _explain_src := Rect2(0, 0, 1, 1)   # the bar's art within its file, in pixels
var _explain_cap := 1.0                 # corner radius in those same pixels
var _cards: Array[TextureButton] = []
var _login: TextureButton
var _setting: TextureButton
var _leaderboard: TextureButton
var _start: TextureButton
var _select_overlay: Control
var _card_shadow_overlay: Control       # 카드 뒤 — 고른 카드의 그림자
var _check_texture: Texture2D
var _lock_texture: Texture2D
# 카드마다 scale 트윈 하나 — _tween_scale 이 소유자다.
var _card_scale_tweens: Array[Tween] = []
var _sfx_select: AudioStreamPlayer
var _sfx_start: AudioStreamPlayer
var _sfx_cream: AudioStreamPlayer
var _start_label: Label
var _remove_ads: Button
var _remove_ads_rule: Control
var _card_characters: Array = []   # one Array[Texture2D] of flight frames per slot
var _card_art: Array[TextureRect] = []
var _card_name: Array[Label] = []
var _card_best: Array[Label] = []
var _card_anim_elapsed: float = 0.0
var _card_art_rest_y: Array[float] = []      # where the layout put each sprite, before the bob
var _card_art_bounds: Array[Rect2] = []      # each card cell's opaque box, normalised
var _explain_label: Label
var _card_best_plate: Array[Panel] = []
var _card_name_plate: Array[Panel] = []
var _card_best_row: Array[HBoxContainer] = []
var _card_crown: Array[TextureRect] = []
var _card_score: Array[Label] = []
var _crown_texture: Texture2D
var _font_bold: Font
var _font_heavy: Font
var _trophy: TextureRect
var _leaderboard_bounds := Rect2(0, 0, 1, 1)
var _leaderboard_label: Label
# 직전 배치에서 실제로 비운 배너 높이. 요청한 값과 다를 수 있다 — 자리가
# 없으면 0 이다. banner_applied_px 로 읽는다.
var _banner_applied := 0.0


# 조립이 끝났는가. Main 이 로고가 뜬 뒤에 ensure_built() 로 켠다.
var _built := false


# 카드 아트 자르기/굽기는 1초 가까이 걸린다. 첫 프레임을 붙잡지 않도록
# 로고 화면 뒤로 미룬다. 두 번 불러도 한 번만 돈다.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_ready()


func _ready() -> void:
	if not _built:
		return
	_load_fonts()
	_sfx_select = _make_sfx(SFX_SELECT_FILE)
	_sfx_start = _make_sfx(SFX_START_FILE)
	_sfx_cream = _make_sfx(SFX_CREAM_FILE)
	_build()
	# Straight to _select, not _on_card_pressed: this is the opening state,
	# not a tap, and should not make a sound — and for the same reason it
	# snaps to the selected size instead of growing into it.
	_select(0, false)
	resized.connect(_layout)


# Two weights off the one variable font. The axis is keyed by its integer
# OpenType tag rather than the string "wght" — a string key is silently
# ignored, which is the same trap Main.gd documents.
func _load_fonts() -> void:
	if not ResourceLoader.exists(FONT_PATH):
		return
	var base: Font = load(FONT_PATH)
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_font_bold = _weighted(base, wght, FONT_WEIGHT_BOLD)
	_font_heavy = _weighted(base, wght, FONT_WEIGHT_HEAVY)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


# Same face with extra space between glyphs. Wrapping rather than mutating,
# because the base is shared with several other labels that must not shift.
func _tracked(base: Font, extra_px: int) -> Font:
	if extra_px == 0:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = extra_px
	return fv


func _make_sfx(file_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	var path: String = SFX_DIR + file_name
	if ResourceLoader.exists(path):
		player.stream = load(path)
	else:
		push_warning("main menu: missing %s" % path)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _process(delta: float) -> void:
	# Only the chosen card animates; the rest hold their first frame, so the
	# selection reads as "this one is alive" without needing another cue.
	if not visible:
		return
	_card_anim_elapsed += delta
	for i in range(_card_art.size()):
		var frames: Array = _card_characters[i]
		if frames.is_empty():
			continue
		var frame: int = 0
		var bob := 0.0
		if i == selected_index:
			frame = int(_card_anim_elapsed * CARD_CHARACTER_FPS) % frames.size()
			var period: float = frames.size() / CARD_CHARACTER_FPS * CARD_BOB_LOOPS
			bob = sin(_card_anim_elapsed / period * TAU) \
				* _card_art[i].size.y * CARD_BOB_AMPLITUDE_FRAC
		_card_art[i].texture = frames[frame]
		# Offset from the resting position the layout gave it, so a re-layout
		# does not accumulate the drift.
		_card_art[i].position.y = _card_art_rest_y[i] + bob


# ---------------------------------------------------------------- art loading

# The project draws with nearest filtering, which is right for the pixel-art
# sprites but wrong here: this art is smooth and painted at 3-4x the size it
# appears at, and nearest minification just samples every third pixel, which
# is what shreds the rounded borders. These nodes opt into linear filtering
# with mipmaps instead (the .import files for assets/ui_assets/main carry
# mipmaps/generate=true so the levels exist to sample).
func _use_smooth_filter(control: CanvasItem) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _load_art(file_name: String) -> Texture2D:
	# 다른 폴더의 파일은 전체 경로로 준다.
	var path: String = file_name if file_name.begins_with("res://") else ART_DIR + file_name
	if not ResourceLoader.exists(path):
		push_warning("main menu: missing %s" % path)
		return null
	return load(path)


# Cuts the sheet into equal cells in reading order and lifts each off its
# black backdrop. Done here rather than as four pre-cut files so the sheet
# stays the only asset to manage — the same reasoning as _slice_spritesheet
# in Main.gd.
func _slice_cards(cols: int, rows: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var texture := _load_art(CARD_SHEET_FILE)
	if texture == null:
		return out
	var sheet: Image = texture.get_image()
	if sheet == null:
		return out
	sheet.convert(Image.FORMAT_RGBA8)
	var cell_w: int = sheet.get_width() / cols
	var cell_h: int = sheet.get_height() / rows
	_card_art_bounds.clear()
	for row in range(rows):
		for col in range(cols):
			var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
			var keyed: Image = _key_black(cell)
			# Recorded while the alpha is to hand: the cards do not all sit at
			# the same place in their cell, and the selection outline needs to
			# follow each one's actual edge.
			_card_art_bounds.append(_opaque_bounds(keyed))
			out.append(ImageTexture.create_from_image(keyed))
	# Reordered to match the slots, so index i is the card shown at slot i.
	var ordered: Array[Rect2] = []
	for slot in CARD_SHEET_SLOT:
		ordered.append(_card_art_bounds[slot] if slot < _card_art_bounds.size() else Rect2(0, 0, 1, 1))
	_card_art_bounds = ordered
	return out


# The opaque box of an image, as fractions of its size.
func _opaque_bounds(image: Image) -> Rect2:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var data: PackedByteArray = image.get_data()
	var x0: int = w
	var x1: int = -1
	var y0: int = h
	var y1: int = -1
	for y in range(h):
		for x in range(w):
			if data[(y * w + x) * 4 + 3] > 24:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 < 0:
		return Rect2(0, 0, 1, 1)
	return Rect2(float(x0) / w, float(y0) / h, float(x1 - x0 + 1) / w, float(y1 - y0 + 1) / h)


# True when any of the four neighbours is backdrop, which is what marks a
# pixel as sitting on the card's anti-aliased rim rather than inside it.
func _touches_backdrop(data: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var n: int = (ny * w + nx) * 4
		if maxi(data[n], maxi(data[n + 1], data[n + 2])) <= KEY_FLOOR:
			return true
	return false


func _key_black(image: Image) -> Image:
	# Works on the raw buffer rather than get_pixel/set_pixel: a card is about
	# 400k pixels, and four of them through per-pixel calls is a visible stall
	# on the way into the menu.
	# The sheet is imported with mipmaps, and a region cut from it carries
	# them too — get_data() would then hand back every level concatenated,
	# which does not match the width x height x 4 that create_from_data below
	# expects. Drop them and rebuild from the keyed result instead, so the
	# levels are generated from the transparency rather than around it.
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var data: PackedByteArray = image.get_data()

	# Pass 1 decides alpha and notes which pixels need their colour divided
	# back out. It cannot do the division inline: the rim test reads its
	# neighbours' colours, and rewriting them as it goes would feed the test
	# values it had already changed.
	var rim: PackedInt32Array = PackedInt32Array()
	for y in range(h):
		for x in range(w):
			var i: int = (y * w + x) * 4
			var brightest: int = maxi(data[i], maxi(data[i + 1], data[i + 2]))
			if brightest <= KEY_FLOOR:
				data[i + 3] = 0
				continue
			if brightest >= KEY_SOLID:
				continue
			if _touches_backdrop(data, w, h, x, y):
				data[i + 3] = brightest
				rim.append(i)

	# Pass 2: undo the premultiply, so a rim pixel carries the border's own
	# colour at partial coverage instead of a colour already mixed with black.
	for i in rim:
		var coverage: float = data[i + 3] / 255.0
		if coverage <= 0.0:
			continue
		for c in range(3):
			data[i + c] = mini(255, int(round(data[i + c] / coverage)))

	var keyed := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	# Built here rather than by the importer, so the linear-with-mipmaps filter
	# above has levels to fall back on when the card is drawn at a third size.
	keyed.generate_mipmaps()
	return keyed


# ---------------------------------------------------------------- building

func _build() -> void:
	for child in get_children():
		# The cue players are not part of the layout and must survive a
		# rebuild — they are created before this runs.
		if child is AudioStreamPlayer:
			continue
		child.queue_free()
	_cards.clear()

	_background = TextureRect.new()
	_background.texture = _load_art(BACKGROUND_FILE)
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Without this a TextureRect reports its texture size as its minimum, and
	# the layout below cannot shrink it — the title would draw at 1056 wide
	# and simply clip.
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_background)
	add_child(_background)

	_title = _make_image(_load_art(TITLE_FILE))
	add_child(_title)

	# 카드보다 먼저 붙는다 — 그림자는 카드 뒤에 있어야 한다. 체크를 그리는
	# _select_overlay 는 반대로 카드 뒤에 붙으면 안 되므로 카드 다음에 붙는다.
	_card_shadow_overlay = Control.new()
	_card_shadow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_shadow_overlay.draw.connect(_draw_card_shadow)
	add_child(_card_shadow_overlay)

	var card_textures := _slice_cards(2, 2)
	_card_characters.clear()
	_card_art.clear()
	_card_art_rest_y.clear()
	_card_name.clear()
	_card_best.clear()
	_card_best_plate.clear()
	_card_name_plate.clear()
	_card_best_row.clear()
	_card_crown.clear()
	_card_score.clear()
	_crown_texture = _load_trimmed(CARD_BEST_CROWN_FILE)
	# 이미 원형으로 잘려 나온 파일이라 _load_trimmed 로 또 다듬지 않는다 —
	# 잘라 둔 투명 여백까지 걷어내면 원의 안티에일리어싱된 테두리가 텍스처
	# 가장자리에 붙어 한쪽이 납작해 보인다(slice_popup_icons_2.ps1 의 Margin).
	_check_texture = _load_art(CARD_CHECK_FILE)
	_lock_texture = _load_art(CARD_LOCK_FILE)
	for i in range(CARD_MODES.size()):
		var slot: int = CARD_SHEET_SLOT[i]
		var card := TextureButton.new()
		card.texture_normal = card_textures[slot] if slot < card_textures.size() else null
		card.ignore_texture_size = true
		# 칸을 아트 비율보다 세로로 늘리므로(CARD_HEIGHT_SCALE) 아트도 같이
		# 늘어나야 한다. KEEP_ASPECT_CENTERED 로 두면 그림은 예전 크기 그대로
		# 가운데 뜨고 눌리는 범위만 커져서, 카드가 커진 것이 아니라 빈 데를
		# 눌러도 반응하는 것이 된다. _layout_card_contents 도 아트가 칸을 꽉
		# 채운다고 보고 이름판·점수판을 놓는다.
		card.stretch_mode = TextureButton.STRETCH_SCALE
		card.focus_mode = Control.FOCUS_NONE
		_use_smooth_filter(card)
		card.pressed.connect(_on_card_pressed.bind(i))
		add_child(card)
		_cards.append(card)

		# Contents ride inside the card so the press animation scales them
		# along with it; none of them take clicks.
		_card_characters.append(_slice_character(CARD_CHARACTER_SHEET[i], CARD_CHARACTER_GRID[i]))
		var art := TextureRect.new()
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_smooth_filter(art)
		card.add_child(art)
		_card_art.append(art)
		_card_art_rest_y.append(0.0)

		var name_plate := Panel.new()
		name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_style := StyleBoxFlat.new()
		name_style.bg_color = CARD_NAME_PLATE_COLOR
		name_style.set_corner_radius_all(CARD_NAME_PLATE_RADIUS)
		name_style.anti_aliasing = true
		name_plate.add_theme_stylebox_override("panel", name_style)
		card.add_child(name_plate)
		_card_name_plate.append(name_plate)

		var name_label := _add_card_text(name_plate, CARD_NAMES[i], CARD_NAME_COLOR)
		name_label.add_theme_color_override("font_outline_color", CARD_NAME_OUTLINE)
		if _font_heavy != null:
			name_label.add_theme_font_override("font", _font_heavy)
		_card_name.append(name_label)

		# White plate behind the score, with the label riding inside it.
		var plate := Panel.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate_style := StyleBoxFlat.new()
		plate_style.bg_color = CARD_BEST_PLATE_COLOR
		plate_style.set_corner_radius_all(CARD_BEST_PLATE_RADIUS)
		plate_style.anti_aliasing = true
		plate.add_theme_stylebox_override("panel", plate_style)
		card.add_child(plate)
		_card_best_plate.append(plate)

		# A row so the three pieces stay centred as a group however wide the
		# number's font ends up.
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(row)
		_card_best_row.append(row)

		var crown := TextureRect.new()
		crown.texture = _crown_texture
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_smooth_filter(crown)
		row.add_child(crown)
		_card_crown.append(crown)

		var best_label := _add_card_text(row, "BEST", CARD_BEST_COLOR)
		best_label.add_theme_color_override("font_outline_color", CARD_BEST_OUTLINE)
		if _font_bold != null:
			best_label.add_theme_font_override("font", _font_bold)
		_card_best.append(best_label)

		# set_best_scores 가 곧바로 덮어쓴다. 기록이 아직 없는 카드의 값이기도 하다.
		var score_label := _add_card_text(row, "0", CARD_SCORE_COLOR)
		score_label.add_theme_color_override("font_outline_color", CARD_SCORE_OUTLINE)
		if _font_heavy != null:
			# Its own face rather than _font_heavy directly: the extra
			# tracking is for the digits only, and _font_heavy is shared with
			# the card name, START and the leaderboard label.
			score_label.add_theme_font_override("font", _tracked(_font_heavy, CARD_SCORE_TRACKING))
		_card_score.append(score_label)

	# Drawn after the cards so the check lands on top of the chosen one.
	#
	# 필터를 반드시 걸어야 한다. 프로젝트 기본값이 Nearest 라(project.godot 의
	# default_texture_filter=0) 그냥 두면 128px 로 구운 체크를 26px 로 점
	# 샘플링해서, 동그란 테두리가 계단처럼 씹힌다.
	_select_overlay = Control.new()
	_select_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_select_overlay)
	_select_overlay.draw.connect(_draw_selection)
	add_child(_select_overlay)

	# Not a TextureRect: the bar is drawn in three pieces so its height can be
	# set independently of its width — see _draw_explain_bar.
	_explain_texture = _load_art(EXPLAIN_FILE)
	_measure_explain_art()
	_explain = Control.new()
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_explain)
	_explain.draw.connect(_draw_explain_bar)
	add_child(_explain)
	_explain_label = Label.new()
	_explain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_explain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		_explain_label.add_theme_font_override("font", _font_bold if _font_bold != null else load(FONT_PATH))
	_explain_label.add_theme_color_override("font_color", EXPLAIN_TEXT_COLOR)
	_explain.add_child(_explain_label)

	_login = _make_button(_load_art(LOGIN_FILE))
	_login.pressed.connect(func(): _play(_sfx_cream); login_pressed.emit())
	add_child(_login)
	_setting = _make_button(_load_art(SETTING_FILE))
	_setting.pressed.connect(func(): _play(_sfx_cream); settings_pressed.emit())
	add_child(_setting)

	_leaderboard = _make_button(_load_art(LEADERBOARD_FILE))
	_leaderboard.pressed.connect(_on_unimplemented.bind("리더보드"))
	add_child(_leaderboard)
	# The plate does not fill its texture — there is transparent padding around
	# it — so the icon is placed against the art's measured bounds rather than
	# the button rect, which would hang it off the bottom edge.
	_leaderboard_bounds = _texture_bounds(_leaderboard.texture_normal)
	_trophy = TextureRect.new()
	_trophy.texture = _load_icon(ICON_TROPHY_INDEX)
	_trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(_trophy)
	_leaderboard.add_child(_trophy)

	_leaderboard_label = Label.new()
	_leaderboard_label.text = LEADERBOARD_LABEL
	_leaderboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_leaderboard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_heavy != null:
		_leaderboard_label.add_theme_font_override("font", _font_heavy)
	_leaderboard_label.add_theme_color_override("font_color", START_LABEL_COLOR)
	_leaderboard_label.add_theme_color_override("font_outline_color", START_LABEL_OUTLINE)
	_leaderboard.add_child(_leaderboard_label)

	# Added before the button so it draws underneath — children render in
	# order, and a halo on top would sit over the plate.
	_start_glow = Control.new()
	_start_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_glow.draw.connect(_draw_start_glow)
	add_child(_start_glow)

	_start = _make_button(_load_art(START_FILE))
	_start.pressed.connect(_on_start_pressed)
	add_child(_start)
	_start_bounds = _texture_bounds(_start.texture_normal)

	# A child of the button, so the press animation below scales the word
	# along with the plate instead of leaving it floating still.
	_start_label = Label.new()
	_start_label.text = START_LABEL
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		_start_label.add_theme_font_override("font", _font_heavy if _font_heavy != null else load(FONT_PATH))
	_start_label.add_theme_color_override("font_color", START_LABEL_COLOR)
	_start_label.add_theme_color_override("font_outline_color", START_LABEL_OUTLINE)
	_start.add_child(_start_label)

	_remove_ads = Button.new()
	_remove_ads.text = REMOVE_ADS_TEXT
	_remove_ads.flat = true
	_remove_ads.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(FONT_PATH):
		_remove_ads.add_theme_font_override("font", load(FONT_PATH))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_remove_ads.add_theme_color_override(state, REMOVE_ADS_COLOR)
	_remove_ads.pressed.connect(_on_unimplemented.bind("Remove Ads"))
	add_child(_remove_ads)
	# Its own child so the rule sits under the text and moves with it.
	_remove_ads_rule = Control.new()
	_remove_ads_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remove_ads_rule.draw.connect(_draw_remove_ads_rule)
	_remove_ads.add_child(_remove_ads_rule)

	# Every button gets the same press feedback.
	for button in [_start, _leaderboard, _login, _setting] + _cards:
		button.button_down.connect(_animate_press.bind(button))
		button.button_up.connect(_animate_release.bind(button))

	_layout()


func _add_card_text(card: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_color_override("font_color", color)
	card.add_child(label)
	return label


# The opaque box of a texture, as fractions of its size — art rarely fills
# its own canvas, and anything positioned against it needs the real bounds.
func _texture_bounds(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2(0, 0, 1, 1)
	var image: Image = texture.get_image()
	if image == null:
		return Rect2(0, 0, 1, 1)
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	return _opaque_bounds(image)


# A whole file, cropped to its art. The crown is generated pixel art and
# carries empty margin around the shape; centring the untrimmed image would
# centre that margin instead.
func _load_trimmed(file_name: String) -> Texture2D:
	var texture := _load_art(file_name)
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var bounds: Rect2 = _opaque_bounds(image)
	var trimmed: Image = image.get_region(Rect2i(
		int(bounds.position.x * w), int(bounds.position.y * h),
		maxi(1, int(bounds.size.x * w)), maxi(1, int(bounds.size.y * h))))
	# 505px 짜리 왕관이 14px 로 그려진다. 그 축소를 GPU 밉맵 체인에 통째로
	# 맡기면 홀수 크기에서 마지막 열이 버려져 오른쪽이 깎여 보인다. 미리
	# 짝수 크기로 줄여 굽고 투명 여백을 둘러 가장자리가 흐려질 자리를 만든다.
	trimmed = _bake_small(trimmed)
	var ink := trimmed.get_size()
	var pad: int = maxi(4, int(round(maxi(ink.x, ink.y) * TRIM_INK_PAD_FRAC)))
	var pw: int = ink.x + pad * 2
	var ph: int = ink.y + pad * 2
	pw += pw % 2
	ph += ph % 2
	var padded := Image.create_empty(pw, ph, false, Image.FORMAT_RGBA8)
	# 여백의 RGB 는 검정이 아니라 실루엣 테두리 색 — 검정이면 줄일 때
	# 그 색이 끌려 들어와 가장자리가 어두워진다.
	padded.fill(Color(_edge_color(trimmed), 0.0))
	padded.blit_rect(trimmed, Rect2i(Vector2i.ZERO, ink), Vector2i(pad, pad))
	padded.generate_mipmaps()
	var texture_out := ImageTexture.create_from_image(padded)
	# 크기를 정할 때 여백을 빼고 실제 그림에 맞출 수 있도록 남겨 둔다.
	texture_out.set_meta("ink_frac", Vector2(float(ink.x) / pw, float(ink.y) / ph))
	return texture_out


# 그릴 크기에 가깝게 미리 줄인다. 알파를 곱한 채로 줄여야 투명한 쪽 RGB 가
# 끌려 들어오지 않는다.
func _bake_small(image: Image) -> Image:
	if image.get_height() <= TRIM_INK_BAKE_H:
		return image
	var w: int = maxi(2, int(round(image.get_width() * float(TRIM_INK_BAKE_H) / float(image.get_height()))))
	var out := image.duplicate() as Image
	out.premultiply_alpha()
	out.resize(w + w % 2, TRIM_INK_BAKE_H, Image.INTERPOLATE_LANCZOS)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
	return out


# 실루엣 가장자리(알파가 반쯤 있는 픽셀)의 평균 색.
func _edge_color(image: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c: Color = image.get_pixel(x, y)
			if c.a > 0.35 and c.a < 0.95:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	if n == 0:
		return Color(0, 0, 0)
	return Color(r / n, g / n, b / n)


# One icon out of the sheet, trimmed to its own art. The cells carry a lot of
# empty space around each glyph, and centring the untrimmed cell would centre
# that padding instead of the icon.
func _load_icon(index: int) -> Texture2D:
	var texture := _load_art(ICON_SHEET_FILE)
	if texture == null:
		return null
	var sheet: Image = texture.get_image()
	if sheet == null:
		return null
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.clear_mipmaps()
	var cell_w: int = sheet.get_width() / ICON_SHEET_GRID.x
	var cell_h: int = sheet.get_height() / ICON_SHEET_GRID.y
	var col: int = index % ICON_SHEET_GRID.x
	var row: int = index / ICON_SHEET_GRID.x
	var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
	var bounds: Rect2 = _opaque_bounds(cell)
	var trimmed: Image = cell.get_region(Rect2i(
		int(bounds.position.x * cell_w), int(bounds.position.y * cell_h),
		maxi(1, int(bounds.size.x * cell_w)), maxi(1, int(bounds.size.y * cell_h))))
	trimmed.generate_mipmaps()
	return ImageTexture.create_from_image(trimmed)


# The character sheets are the same 2x2 grids the game plays, so the cards
# show the real animation rather than a separate still.
func _slice_character(path: String, grid: Vector2i) -> Array:
	var frames: Array = []
	if path == "" or not ResourceLoader.exists(path):
		return frames
	var texture: Texture2D = load(path)
	var sheet: Image = texture.get_image()
	if sheet == null:
		return frames
	sheet.convert(Image.FORMAT_RGBA8)
	sheet.clear_mipmaps()
	var cell_w: int = sheet.get_width() / grid.x
	var cell_h: int = sheet.get_height() / grid.y
	for row in range(grid.y):
		for col in range(grid.x):
			var cell: Image = sheet.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
			# 칸 수가 프레임 수와 딱 맞아떨어지지 않는 시트가 있다 — 유니콘의
			# 달리기는 3x2 칸에 5프레임이라 마지막 칸이 비어 있다. 그대로 넣으면
			# 한 바퀴에 한 번 캐릭터가 사라져 깜빡인다. Main.gd 의
			# _slice_spritesheet 도 같은 이유로 빈 칸을 건너뛴다.
			if cell.is_invisible():
				continue
			# The card draws a 256px frame at about 89, so it needs mip levels
			# for the same reason the menu art does — see _use_smooth_filter.
			cell.generate_mipmaps()
			frames.append(ImageTexture.create_from_image(cell))
	return frames


func _make_image(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_smooth_filter(rect)
	return rect


func _make_button(texture: Texture2D) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	_use_smooth_filter(button)
	return button


# ---------------------------------------------------------------- layout

func _aspect(control: Control) -> float:
	var texture: Texture2D
	if control is TextureRect:
		texture = (control as TextureRect).texture
	elif control is TextureButton:
		texture = (control as TextureButton).texture_normal
	if texture == null or texture.get_height() == 0:
		return 4.0  # harmless stand-in so a missing file cannot divide by zero
	return float(texture.get_width()) / float(texture.get_height())


func _layout() -> void:
	if _title == null or _start == null:
		return
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var title_w: float = view.x * TITLE_WIDTH_FRAC
	var title_h: float = title_w / _aspect(_title)
	var cards_w: float = view.x * CARDS_WIDTH_FRAC
	var card_gap: float = view.x * CARD_GAP_FRAC
	var card_w: float = (cards_w - card_gap) * 0.5
	var card_h: float = card_w / (_aspect(_cards[0]) if not _cards.is_empty() else 1.27)
	var cards_h: float = card_h * 2.0 + card_gap
	# Matched to the cards block, so the bar's ends sit exactly under the outer
	# edges of the left and right columns.
	var explain_w: float = cards_w
	# Height comes from the art's own proportions, then squashed — the three-
	# piece draw below keeps the caps circular at whatever height results.
	# Proportions come from the art itself, not its canvas — the current file
	# carries a lot of transparent padding, and using the canvas would make
	# the bar far too tall for the shape actually drawn in it.
	var explain_native: Vector2 = _explain_src.size
	var explain_h: float = explain_w * (explain_native.y / explain_native.x) * EXPLAIN_HEIGHT_SCALE
	var leaderboard_w: float = view.x * LEADERBOARD_WIDTH_FRAC
	var leaderboard_h: float = leaderboard_w / _aspect(_leaderboard)
	var start_w: float = view.x * START_WIDTH_FRAC
	var start_h: float = start_w / _aspect(_start)

	# Share whatever height is left between the five blocks, capped so a tall
	# screen does not scatter them; anything beyond the cap stays at the
	# bottom rather than stretching the column.
	var remove_ads_h: float = view.y * REMOVE_ADS_BLOCK_FRAC

	# 설명 바는 카드에 붙는다 — 카드끼리의 세로 간격을 그대로 쓴다. 넷과 한
	# 덩어리로 읽혀야 하는 것이지 따로 떠 있을 것이 아니다.
	#
	# 예전에는 여기에 EXPLAIN_TOP_EXTRA_FRAC 을 더 얹었다. 선택된 카드가 테두리
	# 밖으로 번지는 후광을 쓰던 시절, 그게 설명 바에 닿아서 띄운 것이다. 선택
	# 표시가 확대+그림자+체크로 바뀌면서 후광은 사라졌는데 이 여백만 남아,
	# 20:9 에서 카드 간격 14px 대 카드-설명 60px 으로 벌어져 있었다.
	var board_gap: float = card_gap
	var content_h: float = title_h + cards_h + explain_h + leaderboard_h + start_h + remove_ads_h
	var top: float = view.y * TOP_MARGIN_FRAC
	var bottom: float = view.y * BOTTOM_MARGIN_FRAC
	# 남는 세로를 다섯 몫으로 나눈다: 제목 위 / 제목-카드 / 설명-리더보드 /
	# 리더보드-START / START-광고제거. 카드-설명은 board_gap 으로 고정이라 이
	# 나눗셈에 끼지 않는다.
	#
	# "제목 위"가 한 몫을 받는 것이 이번에 달라진 점이다. 예전에는 남는 세로가
	# 전부 블록 사이로만 갔고 위쪽 여백은 TOP_MARGIN_FRAC 에 묶여 있어서, 화면이
	# 길수록 제목·카드는 위에 붙고 리더보드 둘레만 휑했다.
	# 배너 자리는 전부 비우거나 아예 안 비운다. 절반만 비우면 배너가 그만큼
	# START 를 덮는데, 그건 안 비운 것보다 나쁘다 — 화면은 좁아졌는데 가려지기까지
	# 한다. 그래서 넣고도 최소 간격이 남을 때만 받아들이고, 아니면 0 을 돌려
	# 부르는 쪽이 배너를 아예 띄우지 않게 한다.
	_banner_applied = 0.0
	if banner_reserve_px > 0.0:
		var gap_with_banner: float = (view.y - top - (bottom + banner_reserve_px)
			- content_h - board_gap) / 5.0
		if gap_with_banner >= BANNER_MIN_GAP_PX:
			_banner_applied = banner_reserve_px
	bottom += _banner_applied

	# ---- 카드 세로 늘리기 ----
	# 배너 판정이 끝난 뒤다. 배너는 카드보다 우선이라, 배너를 받아들인 화면에서는
	# 그만큼 덜 늘어난다 — 순서를 뒤집으면 늘어난 카드가 배너 자리를 먹고 배너가
	# 거절당한다.
	var gap_now: float = clampf(
		(view.y - top - bottom - content_h - board_gap) / 5.0, 0.0, view.y * MAX_GAP_FRAC)
	var grow_budget: float = maxf(0.0,
		(gap_now - view.y * CARD_GROW_MIN_GAP_FRAC) * 5.0)
	# 늘리기 전 높이. 카드 안의 이름판·점수판·글자 크기가 이 값을 기준으로
	# 잡히므로, 카드가 커져도 그것들은 안 부푼다 — _layout_card_contents 참고.
	var card_base_h: float = card_h
	var grow: float = minf(card_h * 2.0 * (CARD_HEIGHT_SCALE - 1.0), grow_budget)
	if grow > 0.0:
		card_h += grow * 0.5
		cards_h += grow
		content_h += grow

	var gap: float = clampf(
		(view.y - top - bottom - content_h - board_gap) / 5.0, 0.0, view.y * MAX_GAP_FRAC)

	var y: float = top + gap
	# 두 구석 버튼은 세로 흐름에 끼지 않는다 — 화면 맨 위에 그대로 붙인다.
	if _login != null and _setting != null:
		var icon: float = view.y * TOP_ICON_HEIGHT_FRAC
		var mx: float = view.x * TOP_ICON_MARGIN_X_FRAC
		var my: float = view.y * TOP_ICON_MARGIN_Y_FRAC
		_login.position = Vector2(mx, my)
		_login.size = Vector2(icon, icon)
		_setting.position = Vector2(view.x - mx - icon, my)
		_setting.size = Vector2(icon, icon)

	_place(_title, title_w, title_h, y)
	y += title_h + gap

	var cards_left: float = (view.x - cards_w) * 0.5
	for i in range(_cards.size()):
		var col: int = i % 2
		var row: int = i / 2
		_cards[i].position = Vector2(cards_left + col * (card_w + card_gap), y + row * (card_h + card_gap))
		_cards[i].size = Vector2(card_w, card_h)
		_layout_card_contents(i, card_w, card_h, card_base_h)
	_select_overlay.position = Vector2.ZERO
	_select_overlay.size = view
	_select_overlay.queue_redraw()
	_card_shadow_overlay.position = Vector2.ZERO
	_card_shadow_overlay.size = view
	_card_shadow_overlay.queue_redraw()
	y += cards_h + board_gap

	_place(_explain, explain_w, explain_h, y)
	if _explain_label != null:
		_explain_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_explain_label.offset_left = 0.0
		_explain_label.offset_top = 0.0
		_explain_label.offset_right = 0.0
		_explain_label.offset_bottom = 0.0
		_explain.queue_redraw()
		_explain_label.add_theme_font_size_override(
			"font_size", _fit_explain_size(explain_w * EXPLAIN_TEXT_WIDTH_FRAC))
	# From here the column is laid out from the bottom up — Remove Ads sits on
	# the bottom margin, START above it — so the leaderboard can then be
	# centred in whatever is left between the explain bar and START, rather
	# than following the explain bar at a fixed gap and leaving the space
	# below it uneven.
	var explain_bottom: float = y + explain_h
	var remove_ads_y: float = view.y - bottom - remove_ads_h
	var start_y: float = remove_ads_y - gap - start_h
	var leaderboard_y: float = explain_bottom + (start_y - explain_bottom - leaderboard_h) * 0.5

	_place(_leaderboard, leaderboard_w, leaderboard_h, leaderboard_y)
	if _trophy != null:
		var plate_pos := Vector2(
			_leaderboard_bounds.position.x * leaderboard_w,
			_leaderboard_bounds.position.y * leaderboard_h)
		var plate_size := Vector2(
			_leaderboard_bounds.size.x * leaderboard_w,
			_leaderboard_bounds.size.y * leaderboard_h)
		var trophy_h: float = plate_size.y * TROPHY_HEIGHT_FRAC
		_trophy.size = Vector2(trophy_h, trophy_h)
		_trophy.position = plate_pos + Vector2(
			plate_size.x * TROPHY_LEFT_FRAC,
			(plate_size.y - trophy_h) * 0.5)

		if _leaderboard_label != null:
			# From the trophy's right edge to the plate's right padding.
			var text_left: float = _trophy.position.x + trophy_h
			var text_right: float = plate_pos.x + plate_size.x * (1.0 - LEADERBOARD_LABEL_PAD_FRAC)
			_leaderboard_label.position = Vector2(text_left, plate_pos.y)
			_leaderboard_label.size = Vector2(maxf(1.0, text_right - text_left), plate_size.y)
			var wanted: int = int(round(plate_size.y * LEADERBOARD_LABEL_HEIGHT_FRAC))
			var size: int = _fit_text_size(
				_leaderboard_label, LEADERBOARD_LABEL, _leaderboard_label.size.x, wanted)
			_leaderboard_label.add_theme_font_size_override("font_size", size)
			_leaderboard_label.add_theme_constant_override(
				"outline_size", maxi(1, int(round(size * START_LABEL_OUTLINE_SIZE_FRAC))))
	# START and Remove Ads use the bottom-up positions computed above.
	_place(_start, start_w, start_h, start_y)
	# The plate is scaled on press, so the label is anchored to fill it and
	# rides along rather than being positioned in screen space.
	if _start_label != null:
		_start_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_start_label.offset_left = 0.0
		_start_label.offset_top = 0.0
		_start_label.offset_right = 0.0
		_start_label.offset_bottom = 0.0
		var font_size: int = int(round(start_h * START_LABEL_HEIGHT_FRAC))
		_start_label.add_theme_font_size_override("font_size", font_size)
		_start_glow.position = Vector2.ZERO
		_start_glow.size = view
		_start_glow.queue_redraw()
		_start_label.add_theme_constant_override(
			"outline_size", int(round(font_size * START_LABEL_OUTLINE_SIZE_FRAC)))

	if _remove_ads != null:
		_remove_ads.add_theme_font_size_override(
			"font_size", int(round(view.y * REMOVE_ADS_FONT_FRAC)))
		_place(_remove_ads, start_w, remove_ads_h, remove_ads_y)
		_remove_ads_rule.set_anchors_preset(Control.PRESET_FULL_RECT)
		_remove_ads_rule.offset_left = 0.0
		_remove_ads_rule.offset_top = 0.0
		_remove_ads_rule.offset_right = 0.0
		_remove_ads_rule.offset_bottom = 0.0
		_remove_ads_rule.queue_redraw()

	# Scaling happens about the middle, not the top-left corner.
	for button in [_start, _leaderboard] + _cards:
		button.pivot_offset = button.size * 0.5


# Name across the top, character in the middle, best score along the bottom.
# Positions are relative to the card, so they scale with the press animation.
func _layout_card_contents(index: int, card_w: float, card_h: float, base_h: float) -> void:
	if index >= _card_art.size():
		return
	# Against the card's own art, not the button rect. The four cards sit at
	# slightly different offsets inside their cells — up to about 2px once
	# drawn — so laying contents out on the button would put the title and
	# the score plate in a visibly different spot on each card.
	var bounds: Rect2 = _card_art_bounds[index] if index < _card_art_bounds.size() else Rect2(0, 0, 1, 1)
	var origin := Vector2(bounds.position.x * card_w, bounds.position.y * card_h)
	var art_w_total: float = bounds.size.x * card_w
	var art_h_total: float = bounds.size.y * card_h

	# 이름판·점수판·여백은 **늘리기 전** 높이로 잡는다. 늘어난 몫은 전부
	# 캐릭터 자리로 간다.
	#
	# 전부 art_h_total 비율로 두었더니 카드를 세로로 키우는 순간 판과 글자까지
	# 같이 부풀었다. 그중 점수판이 특히 나빴는데, 여백(inset)도 높이 비율이라
	# 같이 커지면서 가로를 먹어 세로 22.8 -> 26.9, 가로 149.9 -> 147.1 이 됐다.
	# 커진 것이 아니라 눌린 것이고, 그렇게 보였다.
	var base_total: float = bounds.size.y * base_h
	var inset: float = base_total * CARD_TEXT_INSET_FRAC
	var inner_w: float = art_w_total - inset * 2.0
	var name_h: float = base_total * CARD_NAME_HEIGHT_FRAC
	var best_h: float = base_total * CARD_BEST_HEIGHT_FRAC
	# 늘어난 높이는 여기로만 들어온다. 캐릭터는 정사각 스프라이트라 커져도
	# 찌그러지지 않는 유일한 요소이기도 하다.
	var art_h: float = base_total * CARD_ART_HEIGHT_FRAC + (art_h_total - base_total)

	var name_size: int = _fit_card_name_size(inner_w * CARD_NAME_WIDTH_FRAC, name_h)
	var outline_size: int = maxi(1, int(round(name_size * CARD_NAME_OUTLINE_FRAC)))
	_card_name[index].add_theme_font_size_override("font_size", name_size)
	_card_name[index].add_theme_constant_override("outline_size", outline_size)

	# One width for every card, from the longest name at the size just fitted.
	# The outline spreads the glyphs on both sides, so it counts toward the
	# room the text needs inside the plate.
	var widest := 0.0
	var name_font: Font = _card_name[index].get_theme_font("font")
	if name_font != null:
		for text in CARD_NAMES:
			widest = maxf(widest, name_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, name_size).x)
	var plate_pad: float = name_h * CARD_NAME_PLATE_PAD_FRAC
	var name_plate_w: float = minf(inner_w, widest + outline_size * 2.0 + plate_pad * 2.0)
	_card_name_plate[index].position = origin + Vector2((art_w_total - name_plate_w) * 0.5, inset)
	_card_name_plate[index].size = Vector2(name_plate_w, name_h)
	_card_name[index].set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_name[index].offset_left = 0.0
	_card_name[index].offset_top = 0.0
	_card_name[index].offset_right = 0.0
	_card_name[index].offset_bottom = 0.0

	# 칸은 정사각형이다 — 스프라이트 시트가 256x256 이라, 게임 쪽과 같은
	# "칸 한 변" 개념으로 맞춰야 크기가 비교된다. 세로로 넘치는 몫은 투명
	# 여백이라(유니콘 1.20 배면 칸이 art_h 를 넘는다) 이름/점수 판을 가리지 않는다.
	# 캐릭터도 늘리기 전 높이 기준이다. 늘어난 만큼 키워 봤더니 20:9 에서
	# 유니콘의 그림이 111 -> 145px 로 퍼지면서 왼쪽 위 초록 체크를 덮었다.
	# 체크가 캐릭터를 가리면 안 된다는 조건이 카드마다 여유가 다른 조건이라,
	# 캐릭터 크기를 화면 비율에 맡기면 어느 비율에서 깨지는지 알 수 없다.
	# 늘어난 높이는 캐릭터 위아래 여백으로 간다.
	var char_side: float = base_total * CARD_ART_HEIGHT_FRAC * CARD_CHARACTER_SCALE[index]
	_card_art[index].size = Vector2(char_side, char_side)
	_card_art[index].position = origin + Vector2(
		inset + (inner_w - char_side) * 0.5,
		inset + name_h + (art_h - char_side) * 0.5)
	_card_art_rest_y[index] = _card_art[index].position.y

	var plate_w: float = inner_w * CARD_BEST_PLATE_WIDTH_FRAC
	_card_best_plate[index].position = origin + Vector2(
		(art_w_total - plate_w) * 0.5, art_h_total - inset - best_h)
	_card_best_plate[index].size = Vector2(plate_w, best_h)
	var score_size: int = int(round(best_h * 0.62))
	_card_best[index].add_theme_font_size_override("font_size", score_size)
	_card_best[index].add_theme_constant_override(
		"outline_size", int(round(score_size * CARD_BEST_OUTLINE_FRAC)))
	_card_score[index].add_theme_font_size_override("font_size", score_size)
	_card_score[index].add_theme_constant_override(
		"outline_size", int(round(score_size * CARD_SCORE_OUTLINE_FRAC)))

	# 높이를 기준으로 잡고 가로는 그림 비율대로. 정사각으로 두면 가로로 넓은
	# 왕관이 그 안에 눕혀지면서 요청한 높이보다 낮게 나온다.
	var crown_h: float = best_h * CARD_BEST_CROWN_HEIGHT_FRAC
	var crown_ratio := 1.0
	var crown_ink := Vector2.ONE
	if _crown_texture != null and _crown_texture.get_height() > 0:
		crown_ratio = float(_crown_texture.get_width()) / float(_crown_texture.get_height())
		crown_ink = _crown_texture.get_meta("ink_frac", Vector2.ONE)
	# CARD_BEST_CROWN_HEIGHT_FRAC 은 "눈에 보이는 왕관" 기준이다. 텍스처에
	# 두른 투명 여백만큼 상자를 키우고, 가로는 그림 비율대로 잡는다 — 정사각에
	# 넣으면 가로로 넓은 왕관이 그 안에 눕혀져 요청한 높이보다 낮게 나온다.
	var box_h: float = crown_h / maxf(crown_ink.y, 0.01)
	_card_crown[index].custom_minimum_size = Vector2(box_h * crown_ratio, box_h)
	_card_best_row[index].add_theme_constant_override(
		"separation", int(round(best_h * CARD_BEST_ROW_SEPARATION_FRAC)))
	_card_best_row[index].set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_best_row[index].offset_left = 0.0
	_card_best_row[index].offset_top = 0.0
	_card_best_row[index].offset_right = 0.0
	_card_best_row[index].offset_bottom = 0.0


# Starts from the size the layout would like and steps down only if the text
# would overrun the width it has been given.
func _fit_text_size(label: Label, text: String, max_width: float, wanted: int) -> int:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return wanted
	var size: int = wanted
	while size > LEADERBOARD_LABEL_MIN_SIZE:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x <= max_width:
			break
		size -= 1
	return size


# The largest size at which every card name fits its card — width and height
# both — so all four render at one size and none spills over its border.
func _fit_card_name_size(max_width: float, max_height: float) -> int:
	if _card_name.is_empty():
		return CARD_NAME_MIN_SIZE
	var font: Font = _card_name[0].get_theme_font("font")
	if font == null:
		return CARD_NAME_MIN_SIZE
	var size: int = CARD_NAME_MAX_SIZE
	while size > CARD_NAME_MIN_SIZE:
		var widest := 0.0
		var tallest := 0.0
		for text in CARD_NAMES:
			var measured: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
			widest = maxf(widest, measured.x)
			tallest = maxf(tallest, measured.y)
		# The outline grows the glyphs on every side, so it counts toward the
		# space the name actually needs.
		var outline: float = size * CARD_NAME_OUTLINE_FRAC * 2.0
		if widest + outline <= max_width and tallest + outline <= max_height:
			break
		size -= 1
	return size


# The largest size at which *every* description still fits on one line, so
# they all render at the same size instead of each shrinking to its own fit.
# 이 카드에 지금 나갈 설명문. 히든 모드는 잠금 상태에 따라 두 가지다.
func _explain_text(index: int) -> String:
	if index < 0 or index >= CARD_EXPLAIN.size():
		return ""
	if CARD_MODES[index] != MODE_HIDDEN:
		return CARD_EXPLAIN[index]
	if hidden_mode_open:
		return CARD_EXPLAIN_HIDDEN_OPEN
	return _hidden_locked_text(hidden_modes_cleared)


func _hidden_locked_text(cleared: int) -> String:
	return CARD_EXPLAIN_HIDDEN_LOCKED % [
		hidden_gates_needed, cleared, hidden_modes_required]


# 나갈 수 있는 모든 문구. 지금 안 쓰는 쪽까지 재야 한다 — 해금되는 순간 다른
# 문구가 곧바로 이 자리에 들어오는데, 그때 글자 크기를 다시 잡을 계기가 없어서
# 그 한 판에서만 문장이 잘린다.
#
# 잠금 안내는 진행도가 박혀 있으므로 0/3 부터 전부 재야 한다. 자릿수가 같아
# 폭도 같을 것 같지만, 폰트가 고정폭이 아니라 실제로 다르다.
func _explain_candidates() -> Array:
	var out: Array = []
	for i in range(CARD_MODES.size()):
		if CARD_MODES[i] != MODE_HIDDEN and i < CARD_EXPLAIN.size():
			out.append(CARD_EXPLAIN[i])
	out.append(CARD_EXPLAIN_HIDDEN_OPEN)
	for n in range(hidden_modes_required + 1):
		out.append(_hidden_locked_text(n))
	return out


func _fit_explain_size(max_width: float) -> int:
	var font: Font = _explain_label.get_theme_font("font")
	if font == null:
		return EXPLAIN_TEXT_MIN_SIZE
	var size: int = EXPLAIN_TEXT_MAX_SIZE
	while size > EXPLAIN_TEXT_MIN_SIZE:
		var widest := 0.0
		for text in _explain_candidates():
			widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x)
		if widest <= max_width:
			break
		size -= 1
	return size


func _place(control: Control, w: float, h: float, y: float) -> void:
	control.position = Vector2((size.x - w) * 0.5, y)
	control.size = Vector2(w, h)


# Godot's Label and Button have no underline, so the rule is measured off the
# text and drawn under it — which also keeps it exactly as wide as the words.
# Same concentric-ring halo as the selected card, around START's plate.
func _draw_start_glow() -> void:
	if _start == null:
		return
	var plate := Rect2(
		_start.position + Vector2(
			_start_bounds.position.x * _start.size.x,
			_start_bounds.position.y * _start.size.y),
		Vector2(_start_bounds.size.x * _start.size.x, _start_bounds.size.y * _start.size.y))
	# The halo lives on its own node, so it does not inherit the button's
	# press scale the way a child would — without this it stayed full size
	# while the button shrank under it, and the button looked like it was
	# sinking out of its own glow. Reproduce the button's transform by hand:
	# scale about its pivot, which _layout parks at the button's centre.
	var press: float = _start.scale.x
	if not is_equal_approx(press, 1.0):
		var pivot: Vector2 = _start.position + _start.pivot_offset
		plate = Rect2(pivot + (plate.position - pivot) * press, plate.size * press)
	var radius: int = int(round(START_CORNER_NATIVE * (_start.size.x / START_SHEET_WIDTH_NATIVE) * press))
	for i in range(START_GLOW_RINGS):
		var t: float = float(i + 1) / float(START_GLOW_RINGS)
		# Spread scales too, so the halo tightens with the button instead of
		# hanging at its resting width around a smaller plate.
		var grow: float = START_GLOW_BORDER * START_GLOW_SPREAD * t * press
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(radius + int(round(grow)))
		glow.set_border_width_all(maxi(1, int(round(START_GLOW_BORDER))))
		glow.border_color = Color(
			START_GLOW_COLOR.r, START_GLOW_COLOR.g, START_GLOW_COLOR.b,
			START_GLOW_COLOR.a * (1.0 - t * 0.75))
		glow.anti_aliasing = true
		_start_glow.draw_style_box(glow, plate.grow(grow))


# Measures the bar in its file: where the art actually sits, and how deep the
# left edge runs before it stops curving inward. That depth is the corner
# radius, and so also how wide a slice has to be to contain a whole cap.
func _measure_explain_art() -> void:
	_explain_src = Rect2(0, 0, 1, 1)
	_explain_cap = 1.0
	if _explain_texture == null:
		return
	var image: Image = _explain_texture.get_image()
	if image == null:
		return
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var bounds: Rect2 = _opaque_bounds(image)
	_explain_src = Rect2(
		round(bounds.position.x * w), round(bounds.position.y * h),
		maxf(1.0, round(bounds.size.x * w)), maxf(1.0, round(bounds.size.y * h)))

	var data: PackedByteArray = image.get_data()
	var left: int = int(_explain_src.position.x)
	var top: int = int(_explain_src.position.y)
	var art_h: int = int(_explain_src.size.y)
	var art_w: int = int(_explain_src.size.x)
	for row in range(art_h):
		var y: int = top + row
		var inset: int = art_w
		for col in range(art_w):
			if data[(y * w + left + col) * 4 + 3] > 24:
				inset = col
				break
		if inset <= 0:
			# First row whose edge has straightened out — the curve above it
			# is the corner, and its depth is the radius.
			_explain_cap = maxf(1.0, float(row))
			return
	_explain_cap = _explain_src.size.y * 0.5


func _draw_explain_bar() -> void:
	if _explain_texture == null or _explain_src.size.x <= 0.0:
		return
	var box: Vector2 = _explain.size
	var src: Rect2 = _explain_src
	# Caps keep the art's own proportions at this height; the middle takes
	# whatever width is left. A bar narrower than two caps would have them
	# overlap, so they are clamped to half each.
	var scale: float = box.y / src.size.y
	var cap: float = minf(_explain_cap * scale, box.x * 0.5)
	var cap_src: float = minf(_explain_cap, src.size.x * 0.5)
	_explain.draw_texture_rect_region(
		_explain_texture, Rect2(0, 0, cap, box.y),
		Rect2(src.position, Vector2(cap_src, src.size.y)))
	_explain.draw_texture_rect_region(
		_explain_texture, Rect2(box.x - cap, 0, cap, box.y),
		Rect2(Vector2(src.position.x + src.size.x - cap_src, src.position.y),
			Vector2(cap_src, src.size.y)))
	var middle: float = box.x - cap * 2.0
	if middle > 0.0:
		_explain.draw_texture_rect_region(
			_explain_texture, Rect2(cap, 0, middle, box.y),
			Rect2(Vector2(src.position.x + cap_src, src.position.y),
				Vector2(src.size.x - cap_src * 2.0, src.size.y)))


func _draw_remove_ads_rule() -> void:
	if _remove_ads == null:
		return
	var font: Font = _remove_ads.get_theme_font("font")
	if font == null:
		return
	var font_size: int = _remove_ads.get_theme_font_size("font_size")
	var text_size: Vector2 = font.get_string_size(REMOVE_ADS_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var centre: Vector2 = _remove_ads.size * 0.5
	# The baseline sits below the visual middle by roughly a quarter of the
	# line box, the same approximation the text drawing elsewhere uses.
	var baseline_y: float = centre.y + text_size.y * 0.25 + REMOVE_ADS_UNDERLINE_GAP
	var half: float = text_size.x * 0.5
	_remove_ads_rule.draw_line(
		Vector2(centre.x - half, baseline_y),
		Vector2(centre.x + half, baseline_y),
		REMOVE_ADS_COLOR, REMOVE_ADS_UNDERLINE_WIDTH)


# 고른 카드가 화면에서 실제로 차지하는 사각형. 카드들이 셀 안에서 조금씩 다른
# 자리에 있으므로(_card_art_bounds) 버튼 사각형이 아니라 아트의 불투명 경계를
# 쓴다 — 버튼으로 잡으면 그림자가 어느 카드에서는 떠 보이고 어느 카드에서는
# 파고든다. scale 이 걸려 있으면 그만큼 가운데에서 키운다.
func _selected_card_rect() -> Rect2:
	return _card_rect(selected_index)


# 한 카드가 실제로 그려지는 사각형. 고른 카드만이 아니라 아무 카드나 — 잠금
# 표시는 고르지 않은 카드에도 붙어야 해서 일반화했다.
func _card_rect(index: int) -> Rect2:
	if index < 0 or index >= _cards.size():
		return Rect2()
	var card: TextureButton = _cards[index]
	var bounds: Rect2 = _card_art_bounds[index] if index < _card_art_bounds.size() else Rect2(0, 0, 1, 1)
	var rect := Rect2(
		card.position + Vector2(bounds.position.x * card.size.x, bounds.position.y * card.size.y),
		Vector2(bounds.size.x * card.size.x, bounds.size.y * card.size.y))
	rect.size.y += card.size.y * SELECT_BOTTOM_EXTEND_FRAC
	# pivot_offset 이 카드 한가운데라 scale 은 그 점을 중심으로 커진다.
	var pivot: Vector2 = card.position + card.pivot_offset
	rect.position = pivot + (rect.position - pivot) * card.scale.x
	rect.size *= card.scale.x
	return rect


func _card_corner_radius() -> int:
	if selected_index < 0 or selected_index >= _cards.size():
		return 0
	var card: TextureButton = _cards[selected_index]
	var art_scale: float = card.size.x * card.scale.x / SELECT_SHEET_WIDTH_NATIVE
	return int(round(SELECT_CORNER_NATIVE * art_scale))


# 카드 뒤. 고른 카드 하나에만 그림자를 깐다.
func _draw_card_shadow() -> void:
	var rect: Rect2 = _selected_card_rect()
	if rect.size.x <= 0.0:
		return
	# 배경은 투명하고 그림자만 남는다 — StyleBoxFlat 은 그림자를 상자 모양
	# 바깥으로 따로 칠하므로, 속을 비워도 그림자는 그려진다. 카드가 이 위에
	# 통째로 덮이니 속을 칠할 이유도 없다.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.set_corner_radius_all(_card_corner_radius())
	box.shadow_color = SELECT_SHADOW_COLOR
	box.shadow_size = SELECT_SHADOW_SIZE
	box.shadow_offset = SELECT_SHADOW_OFFSET
	box.anti_aliasing = true
	_card_shadow_overlay.draw_style_box(box, rect)


# 카드 위. 왼쪽 위 구석의 초록 체크.
func _draw_selection() -> void:
	if _check_texture != null:
		var rect: Rect2 = _selected_card_rect()
		if rect.size.x > 0.0:
			_select_overlay.draw_texture_rect(
				_check_texture, _check_rect(selected_index, rect), false)
	var lock: Rect2 = _lock_draw_rect()
	if _lock_texture != null and lock.size.x > 0.0:
		_select_overlay.draw_texture_rect(_lock_texture, lock, false)


# 자식은 부모의 scale 로 그려지지만 size 는 로컬 그대로다. 그린 자리를 보려면
# 전역 변환을 통과시켜야 한다 — global_position 과 size 를 그냥 붙이면 카드가
# 105% 일 때 판이 실제보다 작게 잡힌다.
func _drawn_rect(node: Control) -> Rect2:
	return node.get_global_transform() * Rect2(Vector2.ZERO, node.size)


# 체크가 놓일 자리. 체커가 같은 답을 봐야 하므로 함수로 빼 둔다 — 여기에
# 계산을 복사해 두면 배치가 바뀌어도 체커는 옛 자리를 검사하며 통과한다.
func _check_rect(index: int, card_rect: Rect2) -> Rect2:
	var margin: float = card_rect.size.x * CARD_CHECK_MARGIN_FRAC
	var side: float = card_rect.size.x * CARD_CHECK_SIZE_FRAC
	if index < 0 or index >= _card_name_plate.size():
		return Rect2(card_rect.position + Vector2(margin, margin), Vector2(side, side))
	# 이름판은 가운데 정렬이라 그 왼쪽 위에 빈 구석이 남고, 체크는 그 구석
	# '안'에 들어가야 한다. 구석의 크기는 고정이 아니다 — 판은 네 이름 중
	# 가장 긴 것에 맞춰 한 번에 정해지므로, 이름이 하나라도 길어지면 판이
	# 넓어지고 구석이 줄어든다. 그래서 CARD_CHECK_SIZE_FRAC 은 상한일 뿐이고
	# 실제 크기는 구석에서 나온다.
	#
	# 비율만 믿었을 때는 38px 짜리가 32px 짜리 구석에 들어가 네 카드 모두
	# 이름을 물었다. 480x854 에서 이 구석은 약 32x39 라, 여기 들어갈 수 있는
	# 가장 큰 체크가 26px 다 — 카드 폭의 13%. 더 키우려면 이름판을 좁히거나
	# 체크를 카드 밖으로 걸치게 해야 하고, 둘 다 이 요청의 범위 밖이다.
	var plate: Rect2 = _drawn_rect(_card_name_plate[index])
	var box := Rect2(
		card_rect.position + Vector2(margin, margin),
		Vector2(plate.position.x - margin - (card_rect.position.x + margin),
			plate.end.y - (card_rect.position.y + margin)))
	side = minf(side, minf(maxf(0.0, box.size.x), maxf(0.0, box.size.y)))
	# 남는 구석 한가운데. 어느 쪽으로도 치우치지 않으니 이름이 길어져 구석이
	# 줄어도 겹치는 쪽이 생기지 않는다.
	return Rect2(box.position + (box.size - Vector2(side, side)) * 0.5, Vector2(side, side))


# 자물쇠를 지금 그릴 자리, 안 그릴 상황이면 빈 사각형.
#
# "그릴지 말지"까지 여기서 답한다. _draw_selection 은 이 값이 비었는지만 보므로
# 판단이 한 군데에만 있고, 체커가 그 판단을 그대로 부를 수 있다 — 그리는 쪽에
# if 를 두면 체커는 그 if 를 못 보고, 해금된 뒤에도 자물쇠가 남는 회귀를
# 사각형 검사만으로는 잡을 수 없다. 고른 카드인지는 상관없다: 잠긴 것은
# 고르든 말든 잠긴 것이고, 누르기 전에 보여야 뜻이 있다.
func _lock_draw_rect() -> Rect2:
	if hidden_mode_open:
		return Rect2()
	var index: int = CARD_MODES.find(MODE_HIDDEN)
	if index < 0:
		return Rect2()
	var card_rect: Rect2 = _card_rect(index)
	if card_rect.size.x <= 0.0:
		return Rect2()
	return _lock_rect(index, card_rect)


# 자물쇠가 놓일 자리 — 체크를 좌우로 뒤집은 것. 이름판 오른쪽에 남는 구석을
# 쓰며, 크기 결정도 같은 이유로 구석에서 나온다(_check_rect 의 설명 참고).
# 체커가 같은 답을 봐야 하므로 여기도 함수다.
func _lock_rect(index: int, card_rect: Rect2) -> Rect2:
	var margin: float = card_rect.size.x * CARD_CHECK_MARGIN_FRAC
	var side: float = card_rect.size.x * CARD_CHECK_SIZE_FRAC
	if index < 0 or index >= _card_name_plate.size():
		return Rect2(
			Vector2(card_rect.end.x - margin - side, card_rect.position.y + margin),
			Vector2(side, side))
	var plate: Rect2 = _drawn_rect(_card_name_plate[index])
	var left: float = plate.end.x + margin
	var box := Rect2(
		Vector2(left, card_rect.position.y + margin),
		Vector2(card_rect.end.x - margin - left,
			plate.end.y - (card_rect.position.y + margin)))
	side = minf(side, minf(maxf(0.0, box.size.x), maxf(0.0, box.size.y)))
	return Rect2(box.position + (box.size - Vector2(side, side)) * 0.5, Vector2(side, side))


# ---------------------------------------------------------------- behaviour

# 버튼이 눌리지 않았을 때 있어야 할 크기. 고른 카드만 크다.
#
# 누름 애니메이션이 Vector2.ONE 으로 돌아가면 안 되는 이유가 이것이다 —
# 고른 카드를 한 번 더 누르면 105% 가 100% 로 풀려 버리고, 다시 커질 계기가
# 없다. 두 크기는 곱해서 쓴다.
func _rest_scale(button: Control) -> Vector2:
	var i: int = _cards.find(button)
	if i < 0:
		return Vector2.ONE
	return Vector2.ONE * (CARD_SELECTED_SCALE if i == selected_index else 1.0)


# 한 버튼의 scale 을 움직이는 트윈은 언제나 하나뿐이다.
#
# 누름, 놓음, 선택 이동이 전부 같은 속성을 건드리는데, 카드를 탭하면 셋이 거의
# 동시에 일어난다: button_up 이 옛 크기로 되돌리는 트윈을 걸고, 바로 뒤에 오는
# pressed 가 새 크기로 가는 트윈을 건다. 이전 것을 죽이지 않으면 두 트윈이 같은
# 값을 서로 다른 목표로 밀며 카드가 떤다.
func _tween_scale(button: Control, want: Vector2, seconds: float, trans: int) -> void:
	var idx: int = _cards.find(button)
	if idx >= 0:
		while _card_scale_tweens.size() <= idx:
			_card_scale_tweens.append(null)
		var old: Tween = _card_scale_tweens[idx]
		if old != null and old.is_valid():
			old.kill()
	var tween := create_tween()
	tween.tween_property(button, "scale", want, seconds) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	if idx >= 0:
		_card_scale_tweens[idx] = tween
	_follow_with_glow(tween, button, seconds)


func _animate_press(button: Control) -> void:
	_tween_scale(button, _rest_scale(button) * PRESS_SCALE, PRESS_ANIM_DURATION, Tween.TRANS_SINE)


func _animate_release(button: Control) -> void:
	# TRANS_BACK overshoots slightly on the way home, which is what makes the
	# button feel like it springs rather than merely returning.
	_tween_scale(button, _rest_scale(button), PRESS_ANIM_DURATION, Tween.TRANS_BACK)


# START's halo is a sibling node, so nothing repaints it when the button's
# scale animates — it would hold its old shape until the next layout pass.
# Drive a redraw alongside the scale tween so the two move together. The
# overshoot at the end of a release is included, which is the point: the
# halo springs with the button rather than snapping after it.
func _follow_with_glow(tween: Tween, button: Control, seconds: float = PRESS_ANIM_DURATION) -> void:
	# 카드의 그림자와 체크도 같은 문제를 가진다. 둘은 형제 노드에 그려지므로
	# 카드가 커지는 동안 아무도 다시 그려 주지 않아, 트윈이 끝날 때까지 옛
	# 크기의 그림자가 새 크기의 카드 밑에 어긋난 채 남는다.
	if _cards.has(button):
		tween.parallel().tween_method(
			func(_t: float) -> void: _redraw_selection(), 0.0, 1.0, seconds)
		return
	if button != _start or _start_glow == null:
		return
	tween.parallel().tween_method(
		func(_t: float) -> void: _start_glow.queue_redraw(), 0.0, 1.0, seconds)


## Fills each card's BEST plate. The array is indexed by mode, and the
## cards are built in CARD_MODES order, so index i belongs to CARD_MODES[i].
##
## 숫자는 ScoreFormat.compact 로 줄여 쓴다. 판 자체는 카드 너비 비율로
## 잡히므로(plate_w) 글자 길이와 무관하게 고정이고, 왕관+"BEST"+숫자 줄만
## 그 안에서 가운데로 다시 모인다.
func set_best_scores(values: PackedInt32Array) -> void:
	for i in range(_card_score.size()):
		var mode: int = CARD_MODES[i]
		var value: int = values[mode] if mode < values.size() else 0
		_card_score[i].text = ScoreFormat.compact(value)


## 히든 모드 해금 진행도. Main 이 저장된 값에서 뽑아 넘긴다.
##
## 잠금 여부를 따로 받지 않고 여기서 계산한다. 진행도와 잠금을 둘 다 받으면
## 서로 어긋난 조합("3/3 인데 잠김")을 넘길 수 있게 되는데, 그런 상태는 화면을
## 봐도 어느 쪽이 틀렸는지 알 수 없다.
func set_hidden_progress(cleared: int, required: int, gates_needed: int) -> void:
	hidden_modes_required = maxi(1, required)
	hidden_modes_cleared = clampi(cleared, 0, hidden_modes_required)
	hidden_gates_needed = maxi(1, gates_needed)
	hidden_mode_open = hidden_modes_cleared >= hidden_modes_required
	# 글자 크기는 나갈 수 있는 문구 전체에서 한 번에 정해지고, 그 목록이 방금
	# 바뀌었다. 다시 배치해야 새 문구가 잘리지 않는다.
	_layout()
	if _explain_label != null:
		_explain_label.text = _explain_text(selected_index)


func _on_card_pressed(index: int) -> void:
	# The cue fires on every tap, including one on the already-selected card:
	# it is feedback for the press, not for the selection changing.
	_play(_sfx_select)
	_select(index)


func _select(index: int, animate: bool = true) -> void:
	selected_index = index
	if _explain_label != null and index < CARD_EXPLAIN.size():
		_explain_label.text = _explain_text(index)
	for i in range(_cards.size()):
		var card: TextureButton = _cards[i]
		var want: Vector2 = _rest_scale(card)
		if card.scale.is_equal_approx(want):
			continue
		if animate:
			_tween_scale(card, want, CARD_SELECT_ANIM, Tween.TRANS_SINE)
		else:
			# 첫 화면. 여는 상태는 이미 그 크기여야지, 커지는 게 보이면
			# 사용자가 고르지도 않은 것을 고른 것처럼 연출된다.
			card.scale = want
	_redraw_selection()


# 그림자와 체크는 카드 크기를 따라가므로 늘 함께 다시 그린다.
func _redraw_selection() -> void:
	if _select_overlay != null:
		_select_overlay.queue_redraw()
	if _card_shadow_overlay != null:
		_card_shadow_overlay.queue_redraw()


func _on_start_pressed() -> void:
	if selected_index < 0 or selected_index >= CARD_MODES.size():
		return
	var mode: int = CARD_MODES[selected_index]
	# Started before the mode is handed over: emitting swaps the screen and
	# crossfades the music, and the cue should be underway before that.
	_play(_sfx_start)
	# The fourth slot is the hidden mode. It opens once every other mode has
	# been played far enough — Main owns that record and hands the answer over
	# through set_hidden_progress.
	#
	# 디버그 빌드에서는 조건과 상관없이 열린다. 매번 30 게이트를 지나야 MIX 를
	# 한 번 볼 수 있으면 그 모드를 손볼 때마다 그 값을 치러야 한다. 릴리스
	# 빌드에는 이 예외가 없으므로 실제 잠김은 릴리스로 내보내 눌러 봐야 한다.
	if mode == MODE_HIDDEN and not hidden_mode_open and not OS.is_debug_build():
		print("[잠김] 히든 모드 — %d/%d 모드에서 %d 게이트씩" % [
			hidden_modes_cleared, hidden_modes_required, hidden_gates_needed])
		return
	start_pressed.emit(mode)


func _on_unimplemented(what: String) -> void:
	print("[미구현] ", what)


## 하단에 비워 둘 배너 높이(게임 픽셀)를 정하고 다시 배치한다.
##
## 돌려주는 값은 **실제로 비운 높이**다. 화면이 짧아 자리가 안 나면 0 을
## 돌려주므로, 부르는 쪽은 그때 배너를 띄우지 않아야 한다. 요청한 만큼
## 비웠는지 되묻지 않고 돌려받은 값을 그대로 믿으면 된다.
func set_banner_reserve(px: float) -> float:
	banner_reserve_px = maxf(0.0, px)
	_layout()
	return _banner_applied


## 직전 배치에서 실제로 비운 높이.
func banner_applied_px() -> float:
	return _banner_applied
