extends Node2D

## Flag Explorer mode — Hard difficulty graybox prototype.
## No art: character/gates are plain rects, quiz text is hardcoded dummy
## country-name pairs (English, since the bundled font has no Hangul glyphs).

## Exposed so they can be tweaked live in the Inspector, mid-play, from the
## editor's remote scene tree. Current defaults are provisional playtest
## values — see README.md "튜닝 기본값" for the record and rationale.
@export_range(-500.0, -20.0, 1.0) var flap_velocity: float = -300.0
@export_range(50.0, 1500.0, 10.0) var gravity: float = 1000.0
@export_range(50.0, 1200.0, 10.0) var max_fall_speed: float = 300.0
@export_range(80.0, 800.0, 10.0) var base_gate_spacing: float = 600.0

# Caps how far apart (as a fraction of full screen height) two consecutive
# gate targets can be — stops extreme "top then straight to bottom" rolls,
# on top of whatever the raw physics reachability already allows.
@export_range(0.1, 1.0, 0.01) var max_move_ratio_early: float = 0.5   # Phase 1-2
@export_range(0.1, 1.0, 0.01) var max_move_ratio_late: float = 0.65   # Phase 3-4

## 가속 보너스 판정. 게이트 통과 순간 보너스 바에 남아 있는 비율로 배율을 정하고,
## 그 배율이 그대로 통과 점수에 곱해진다:
##   Score += (SCORE_PER_COMBO × 콤보) × (1 + 가속배율)
##
##   남은 비율 >= best_threshold -> best_multiplier
##   남은 비율 >= mid_threshold  -> mid_multiplier
##   그 아래                     -> none_multiplier
##
## 기본값은 임의의 반올림 수치가 아니라 실제로 도달 가능한 구간에서 뽑았다.
## 가속을 한 번도 안 쓰면 바는 7.3% 만 남고(게이트가 스폰되는 순간 항상 걸리는
## 통과 가속 덕에 정확히 0 은 아니다), 비행 내내 붙잡고 있으면 57.3% 가 남는다.
## 즉 채점축 전체가 7.3~57.3% 이고, 경계는 그 안에 있어야 의미가 생긴다.
##   mid  0.12 — 무가속 바닥(7.3%)보다는 위, 0.15 초짜리 짧은 탭(15.7%)보다는
##               아래. 조금이라도 의미 있게 쓰면 10점이 붙는다.
##   best 0.48 — 비행의 약 3분의 2 이상을 붙잡고 있어야 닿는다(70% 홀드 =
##               49.9%). 천장 57.3% 를 그대로 쓰면 한 프레임만 놓쳐도 떨어지므로
##               조금 낮춰 잡았다.
## tools/check_boost_bar_range.gd 가 이 수치를 다시 뽑아 검증한다 — 가속 배율,
## GATE_SPEED, base_gate_spacing 중 하나라도 바꾸면 축이 통째로 움직이므로 그
## 스크립트를 다시 돌려 경계를 옮겨야 한다.
@export_range(0.0, 1.0, 0.01) var boost_bonus_mid_threshold: float = 0.12
@export_range(0.0, 1.0, 0.01) var boost_bonus_best_threshold: float = 0.48
## 배율 0 = 보너스 없음(기본 점수 그대로), 1.0 = 기본 점수의 두 배.
@export_range(0.0, 5.0, 0.05) var boost_bonus_none_multiplier: float = 0.0
@export_range(0.0, 5.0, 0.05) var boost_bonus_mid_multiplier: float = 0.5
@export_range(0.0, 5.0, 0.05) var boost_bonus_best_multiplier: float = 1.0

# Three planned game concepts sharing this same tap/gate mechanic, picked at
# the mode-select screen (see State.MODE_SELECT/_apply_mode below): SKY (red
# bird + sky gate, flag quiz), JUNGLE (green dragon + jungle gate, math quiz
# — not built yet, flag quiz stands in), OCEAN (blue shark + ocean gate, quiz
# type undecided — flag quiz stands in).
enum Mode { SKY, JUNGLE, OCEAN, DREAM }

# DREAM (unicorn + dream world, working title) is the newest concept and its
# art is still being drawn. Every MODE_* array below therefore carries SKY's
# entry in the DREAM slot: the mode boots, plays and is selectable today,
# wearing the bird's costume, and each row gets swapped for real dream art as
# it lands. Its quiz is the flag quiz, shared with SKY — see _spawn_gate,
# where anything that is not JUNGLE or OCEAN falls through to it.
# Search MODE_ to find every row that still needs replacing.

# ---- OCEAN mode: Stroop colour quiz (see the OCEAN_* const block and
# _make_color_problem / _draw_ocean_quiz_box further down) ----
# The classic Stroop, and the only variant: a colour word painted in some
# other colour, and you name the PAINT. The answer is a colour name, matched
# exactly the way SKY matches a country code (see _spawn_gate/_resolve_gate).

# The three shapes a wrong option can take. Which one a question gets is
# rolled per question from the phase's weights below — the point being that a
# player who works out one trap still can't coast, because the next gate may
# not be running that trap at all.
#   WORD_MEANING — the word's own meaning. Read instead of look, and you take
#                  it every time. The strongest single trap available.
#   NEAREST_HUE  — the palette colour sitting closest to the answer on the
#                  hue circle. Punishes a glance instead of a look.
#   RANDOM       — neither of the above. A genuine breather: obviously wrong
#                  once you actually read it.
enum OceanDecoy { WORD_MEANING, NEAREST_HUE, RANDOM }

## Wrong-gate trap mix, one entry per phase (see phase_gate_counts).
## x = WORD_MEANING, y = NEAREST_HUE, z = RANDOM.
## Relative weights, not percentages — they need not sum to 100, so a single
## component can be nudged without rebalancing the other two. All-zero falls
## back to WORD_MEANING. Safe to edit live from the remote scene tree while
## playing; each new question re-reads this.
@export var ocean_decoy_weights_by_phase: Array[Vector3] = [
	Vector3(20.0, 10.0, 70.0),  # phase 1 — warm-up: mostly harmless decoys
	Vector3(40.0, 30.0, 30.0),  # phase 2 — traps switched on
	Vector3(45.0, 45.0, 10.0),  # phase 3 — the breather nearly gone
	Vector3(50.0, 50.0, 0.0),   # phase 4 — extreme: always one trap or the other
]

const PLAYER_SIZE := Vector2(50, 50)  # hitbox — scaled up a bit alongside PLAYER_VISUAL_SIZE below to keep matching the body size, per request
const PLAYER_VISUAL_SIZE := Vector2(100, 100)  # on-screen draw size — source art is scaled to this regardless of its own resolution
const PLAYER_X := 130.0
const DEBUG_SHOW_HITBOX := false # outlines the real collision rect over the character — turn off once done tuning PLAYER_SIZE/PLAYER_VISUAL_SIZE
const DEBUG_HITBOX_COLOR := Color(1.0, 0.0, 1.0, 1.0)  # bright magenta — doesn't occur anywhere else in the game's palette

## 판정 영역을 색으로 덮어 보여준다 (튜닝용). 게임플레이에는 영향 없음.
## 마젠타=캐릭터 히트박스, 파랑=게이트 통과 구역, 초록=중심 허용 범위.
@export var debug_show_zones: bool = false
# Two things are drawn, and they are NOT the same measurement — which is the
# whole reason this overlay exists:
#   ZONE   the gate's opening. The player's WHOLE hitbox must fit inside it.
#   SLACK  where the player's CENTRE may be and still fit — the zone inset by
#          half the hitbox. This is the band that actually gets steered, and
#          it is a good deal narrower than the opening looks.
const DEBUG_ZONE_FILL := Color(0.30, 0.60, 1.00, 0.20)      # 게이트 통과 구역
const DEBUG_ZONE_EDGE := Color(0.30, 0.60, 1.00, 0.95)
const DEBUG_SLACK_FILL := Color(0.20, 0.95, 0.45, 0.28)     # 중심 허용 범위
const DEBUG_SLACK_EDGE := Color(0.10, 0.85, 0.35, 0.95)
const DEBUG_CENTER_LINE := Color(1.0, 1.0, 1.0, 0.9)        # 구역 정중앙
const DEBUG_JUDGE_LINE := Color(1.0, 0.25, 0.25, 0.95)      # 판정이 일어나는 x
const DEBUG_LABEL_SIZE := 13

# Character display set — display/animation only, never touches
# PLAYER_SIZE/physics/collision. fly is a 2x2 spritesheet sliced at runtime
# (see _slice_spritesheet), happy and sad are single static frames. Frame
# order for the sheet is left-to-right, top-to-bottom: TL, TR, BL, BR.
# Indexed by Mode — see _apply_mode, called once at _ready() and again
# whenever the mode-select screen picks a different mode.
const MODE_CHARACTER_DIR := [
	"res://assets/characters/bird_v2/",
	"res://assets/characters/dragon_green/",
	"res://assets/characters/shark_blue/",
	"res://assets/characters/unicorn_dream/",
]
const MODE_CHARACTER_FLY_FILE := ["bird_fly.png", "dragon_fly.png", "shark_swim.png", "unicorn_run.png"]
const MODE_CHARACTER_HAPPY_FILE := ["bird_happy.png", "dragon_happy.png", "shark_happy.png", "unicorn_happy.png"]
const MODE_CHARACTER_SAD_FILE := ["bird_sad.png", "dragon_sad.png", "shark_sad.png", "unicorn_sad.png"]
# Frame layout of each mode's motion spritesheet, as (columns, rows), read
# left-to-right then top-to-bottom. The first three are 2x2 flap cycles;
# DREAM's unicorn run is a 3x2 grid holding 5 frames, so its sixth cell is
# empty — _slice_spritesheet drops fully transparent cells, which is why the
# grid can describe the sheet honestly instead of needing a frame count.
# Every mode's cell is 256x256; only the arrangement differs.
const MODE_CHARACTER_SHEET_GRID := [Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2), Vector2i(3, 2)]
const FLAP_FRAME_DURATION := 1.0 / 8.0  # 8 FPS per spec

# Measured opaque-pixel bounding-box centers (in each source PNG's own pixel
# space, out of a 256x256 canvas), converted to a PLAYER_VISUAL_SIZE-space
# draw offset via (canvas_center(128,128) - measured_center) * (100.0/256.0)
# — same technique for all three, so switching modes never makes the
# character visually jump between fly/happy/sad. Re-measure and update
# rather than guessing if any of this art is ever redrawn.
# DREAM measured off the unicorn art: run frames average (126.7, 126.9) —
# the 5 frames' own centers drift 3.5x6.0px, a run cycle's natural bob, well
# under JUNGLE's 16.5px and not worth flattening — and both faces sit at
# (126.0, 124.0).
const MODE_DRAW_OFFSET_FLY := [Vector2(0.4, 2.5), Vector2(-2.0, 0.7), Vector2(0.0, 0.0), Vector2(0.5, 0.4)]
const MODE_DRAW_OFFSET_HAPPY := [Vector2(2.0, 2.1), Vector2(-1.2, 0.6), Vector2(0.0, 0.0), Vector2(0.8, 1.6)]
const MODE_DRAW_OFFSET_SAD := [Vector2(0.4, 2.1), Vector2(-1.2, 0.6), Vector2(0.0, 0.0), Vector2(0.8, 1.6)]
# Per-mode visual-only size tweak — multiplies PLAYER_VISUAL_SIZE's draw
# scale, same as _bird_stretch_scale/_happy_pop_scale (see active_visual_size_scale).
# Never touches PLAYER_SIZE/hitbox/collision, only which mode looks a hair
# bigger or smaller on screen.
# DREAM is sized against JUNGLE, not SKY: the unicorn and the dragon are the
# two big-bodied characters and are meant to read at the same weight. Their
# proportions differ though — measured opaque bbox is 238.5x202.3 for the
# dragon against 229.0x168.2 for the unicorn, so the unicorn is the flatter
# of the two and no single number matches both axes. Matched on HEIGHT, per
# request: 1.20 puts the unicorn at 78.8px tall against the dragon's 79.0,
# and 107px wide against its 93px — the extra width is mostly mane and tail,
# which read as silhouette rather than bulk. Hitbox is untouched either way.
const MODE_VISUAL_SIZE_SCALE := [0.92, 1.0, 1.0, 1.20]

# Gate-pass "happy" reaction — visual-only (scale + a small upward draw
# offset around the bird's existing draw_set_transform center; player_y/
# PLAYER_X/PLAYER_SIZE and collision are never touched). Driven by the same
# happy_flap_elapsed timer that already exists to pick the happy texture,
# so it's automatically synced to the same moment _play_gate_success_fx
# fires the success sound/sparkles/combo popup. Combines multiplicatively
# with the existing gate-pass squash (_bird_stretch_scale) rather than
# replacing it — squash settles in ~0.15s, this pop eases out over the
# whole HAPPY_FLAP_DURATION, so they layer into one "impact then bounce"
# motion instead of visually competing.
const HAPPY_FLAP_DURATION := 0.5
const HAPPY_POP_ENVELOPE := [Vector2(0.0, 0.0), Vector2(0.24, 1.0), Vector2(1.0, 0.0)]  # peaks ~0.12s in, within the requested 0.10-0.15s
const HAPPY_POP_SCALE_PEAK := 1.12
const HAPPY_POP_BOUNCE_HEIGHT := 8.0  # px, screen-space upward draw offset at the envelope's peak

const GATE_WIDTH := 130.0
const GATE_SPEED := 130.0  # halved for testing — was 260.0
# The center wall doubles as the fixed 30-40px buffer between the top and
# bottom gates (see _gate_wall_center_y) — its own thickness IS that buffer,
# so widening it here is the whole fix; nothing else needs to change.
const WALL_THICKNESS := 36.0

# ============================================================
# Art filtering.
#
# This used to be TEXTURE_FILTER_NEAREST for everything Main draws, on the
# assumption that the art is pixel art that wants hard edges. It isn't: none
# of it is authored at 1:1. The gate rings are 512px PNGs drawn at ~220px,
# the character sheets and the flag cards (256px source at 72px) are minified
# harder still. Nearest-neighbour minification just point-samples, dropping
# most of the source pixels, which is what chews up the thin outlines and
# leaves ragged edges. Linear + mipmaps resolves them properly instead.
#
# Flip this to false to get the old hard-edged look back — that single edit
# is the whole revert, nothing else has to change. (Nearest ignores mipmaps,
# so the mipmap flags in the *.import files are harmless either way and can
# stay on.) The top HUD is filtered separately and stays smooth regardless —
# see scripts/HudCanvas.gd.
const SMOOTH_WORLD_FILTER := true

# ============================================================
# Screen layout zones (top -> bottom): HUD bar -> quiz box -> the gate zone
# (everything gameplay-visual: gates/wall/bird), starting right at the quiz
# box's real (non-transparent) bottom edge and running all the way to the
# screen's bottom edge (no reserved control zone — Hard mode is a full-
# screen-tap game).
# These are absolute pixel values, not scaled with screen height, per spec —
# see _gate_zone_top/_gate_zone_bottom, the only two places that combine
# them into the actual bounds gate spawning/clamping/drawing use.
# ============================================================
const HUD_BAR_HEIGHT := 100.0        # fallback-only: the plain bar drawn when the score box art is missing
const HUD_SIDE_MARGIN := 12.0
const HUD_BAR_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const QUIZ_BOX_MARGIN := 24.0        # left/right inset from screen edges (fallback draw only)
# Top HUD: one row of pause | score box | mute, with the quiz box directly
# under it. The row is laid out at a single shared scale so it keeps the
# proportions of the source sheet the art was cut from — the buttons stay in
# the same size relationship to the score box that they were drawn in.
#
# The scale falls out of filling the screen width (see _hud_row_scale), so
# the knobs here are the margins and gaps, not the widths. Heights follow
# from each PNG's own aspect, and the art is cropped tight to its frame, so
# the drawn rect IS what you see. _score_box_rect/_quiz_box_rect are the only
# places that turn any of this into screen rects, and _gate_zone_top starts
# the gate zone at the quiz box's bottom edge.
const SCORE_BOX_TOP := 16.0          # screen y of the top HUD row — the single knob that moves the whole HUD (buttons, quiz box and the gate zone below it all derive from it)
const HUD_ROW_SIDE_MARGIN := 6.0     # screen edge -> pause/mute button
const HUD_ROW_GAP := 4.0             # button -> score box
const QUIZ_BOX_GAP := 7.0            # score box bottom edge -> quiz box top edge
# Pause/mute are scaled so their height matches the score box's exactly,
# which is what makes the top row read as one flush band rather than three
# loosely stacked pieces. Derived from the art rather than hard-coded, so it
# still holds if the sheet is redrawn — see _hud_button_mult. This is a
# further nudge on top of that: >1 makes the buttons overhang the row.
# 버튼 높이를 퀴즈 박스 높이에 맞추는 배수.
#
# 버튼 높이 = 스코어박스 높이 x 이 값인데, 버튼을 키우면 행 배율이 줄어
# 스코어박스가 같이 작아진다. 그 되먹임까지 풀어서 얻은 값이다 — 이 값이면
# 버튼이 퀴즈 박스와 같은 57.5px가 된다.
const HUD_BUTTON_EXTRA := 0.9517
# The buttons are hung off the score box's bottom edge rather than centred on
# it. Aligning the *rects* would not do it: the slicer pads every canvas to
# make the panel interiors line up across modes, so the painted art stops
# short of the canvas bottom by a different amount in each mode and each
# piece. These are where the art actually ends, as a fraction of canvas
# height, measured off the sliced PNGs — indexed by Mode.
const MODE_SCORE_BOX_ART_BOTTOM_FRAC := [1.0, 1.0, 1.0, 1.0]
# 새 버튼 아트는 네 모드 모두 실루엣에 딱 맞게 잘라 냈으므로 보정이 없다.
const MODE_HUD_BUTTON_ART_BOTTOM_FRAC := [1.0, 1.0, 1.0, 1.0]
const HUD_BUTTON_Y_OFFSET := 0.0     # nudge both buttons down (+) or up (-) from that alignment
# Stretches the quiz box taller than its art's aspect. The box already spans
# the full screen width, so it cannot grow taller proportionally.
#
# 그래도 양 끝 장식은 안 깨진다: _draw_horizontal_slice 가 좌우 끝
# QUIZ_BOX_CAP 만큼은 세로 배율과 같은 배율로(찌그러짐 없이) 그리고, 늘어나는
# 것은 가운데 밋밋한 테두리 구간뿐이기 때문이다. 그러니 이 값을 키우면 날개/
# 잎/불가사리/꽃은 비율 그대로 커지고, 남는 폭을 가운데가 흡수한다.
#
# 1.0 = 원본 비율. 1.429 -> 화면에서 468x65.7 — 캔버스가 179 에서 184 로
# 높아진(안쪽 면 정렬용 여백) 만큼 올려, 눈에 보이는 박스 크기는 그대로다.
# The quiz TEXT does not grow with it; see QUIZ_TEXT_*_FONT_FRAC.
const QUIZ_BOX_HEIGHT_STRETCH := 1.429
# Canvas sizes the slicer produced — see tools/slice_hud_sheet_v5.gd, which
# prints them. Used for layout maths and as the aspect fallback when a
# texture is missing; the real texture's size wins when it is loaded.
const SCORE_BOX_SRC := Vector2(937.0, 135.0)
const QUIZ_BOX_SRC := Vector2(1190.0, 117.0)
const HUD_BUTTON_SRC := Vector2(117.0, 109.0)
const QUIZ_BOX_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const QUIZ_BOX_CORNER_RADIUS := 12.0
# 늘리지 않고 그대로 둘 양 끝의 폭(원본 px).
#
# 이 경계 바깥은 원본 그대로, 안쪽은 가로로만 늘어난다. 그러니 경계는
# 장식(보석 + 둥근 모서리 곡선)이 완전히 끝난 뒤에 놓여야 한다. 예전 값 60 은
# 보석 한가운데를 지나서, 보석의 왼쪽 절반만 늘어나 찌그러져 보였다.
#
# 각 모드 아트에서 "이웃한 두 열이 거의 같아지는" 지점을 재 보면 v7 시트는
# sky 126 / jungle 179 / ocean 157 / dream 139 다(881px 원본 기준). 네 모드를
# 한 값으로 덮으려면 179 이상이어야 하고, 동시에 가운데 구간(185..696)이 모든
# 모드의 균일 구간 안에 들어와야 한다.
const QUIZ_BOX_CAP := 185.0
# Blank writing area inside the quiz box art, right of the painted "QUIZ"
# label. Measured off the shared crop canvas (see MODE_QUIZ_BOX_PATH), so
# one set of fractions covers all three modes.
# 새 아트에는 "QUIZ" 라벨이 없어 글자가 박스 전체를 쓴다. 양 끝 장식만
# 피하면 되는데, 그 장식은 늘어나지 않고 고정 폭으로 그려지므로 비율도
# 박스 폭에 대한 그 폭으로 잡는다.
const QUIZ_TEXT_LEFT_FRAC := 0.055        # of width
const QUIZ_TEXT_RIGHT_FRAC := 0.945       # of width
const QUIZ_TEXT_SIDE_PAD_FRAC := 0.020    # of width — keeps text off both edges
# 슬라이서가 네 모드의 "안쪽 면" 세로 가운데를 캔버스의 한 지점(184px 중 94)에
# 모아 두었으므로, 한 값으로 네 모드가 다 맞는다. 예전 0.480 은 안쪽 면이
# 모드마다 다른 높이에 있던 시절의 절충값이었다.
const QUIZ_TEXT_CENTER_Y_FRAC := 0.5109
# The text is centred within LEFT_FRAC..RIGHT_FRAC — the writing area with
# the painted "QUIZ" pill excluded — not within the box as a whole.
# Font size is pinned to the box's WIDTH, not its height. Height would be the
# natural choice, but it would tie the text to QUIZ_BOX_HEIGHT_STRETCH —
# making the panel taller would grow the letters with it, which is exactly
# what we don't want. Width is untouched by the stretch, so the text holds
# its size no matter how tall the box gets.
#
# The ceiling comes from descenders: measured on Fredoka, cap-height strings
# ink 0.72 em above the baseline to 0.01 below, but a "Paraguay" reaches
# 0.21 em below. Centred on the ink midpoint, that puts the descender
# 0.565 em under the centre, which is what has to clear the frame.
const QUIZ_TEXT_MAX_FONT_FRAC := 0.062    # of box width
const QUIZ_TEXT_MIN_FONT_FRAC := 0.030    # of box width — floor for very long country names
# Baseline offset from the text's visual centre, as a fraction of font size.
# Measured the same way as the digits: ink midpoint of cap-height strings
# sits 0.355 em above the baseline. Centring on the cap band rather than on
# the full ink box keeps strings with descenders from jumping upward.
const QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC := 0.355
# ============================================================
# Boost bonus bar — the readout for the hold-to-accelerate button, sitting
# in its own band between the quiz box and the gate zone.
#
# It is a clock, not a progress meter. On every gate spawn it fills to 100%
# and drains at a FIXED rate over T_base — how long that gate takes to
# reach the judge line at the base scroll rate, boost excluded. Holding
# boost does not change the drain; it moves the gate to the player sooner,
# so the bar still has something left when the pass is judged. That
# leftover is the whole signal: remaining = 1 - T_actual / T_base.
#
# So MORE remaining means MORE boost, and the bands run that way: grey at
# the empty end (never touched the button), gold at the full end (held it
# for most of the flight). The reachable span is narrower than the track —
# see the boost_bonus_* exports for the measured numbers and why the
# thresholds sit where they do.
#
# The band is carved out of the gate zone (GATE_ZONE_TOP_BUFFER below,
# previously 0.0), so the playable lane is that much shorter now.
# ============================================================
const BOOST_BAR_GAP := 5.0            # quiz box bottom edge -> bar top
const BOOST_BAR_HEIGHT := 16.0        # was 10 — the track art carries a painted rim that mushed together any thinner
const BOOST_BAR_BOTTOM_GAP := 5.0     # bar bottom -> gate zone top
const BOOST_BAR_SIDE_MARGIN := 16.0   # inset from the quiz box's own left/right edges
# Painted art, cut from assets/ui_assets/boost_bar_sheet.png by
# tools/slice_boost_bar_sheet.ps1: an empty track plus one fill per tier,
# grey/yellow/orange. Both are drawn through _draw_horizontal_slice, so the
# rounded ends stay round at any width and only the middle stretches.
const BOOST_BAR_TRACK_PATH := "res://assets/ui_assets/boost_bar/track.png"
const BOOST_BAR_FILL_PATHS := [
	"res://assets/ui_assets/boost_bar/fill_none.png",  # bonus 0 — 무채색
	"res://assets/ui_assets/boost_bar/fill_mid.png",   # mid tier — 노랑
	"res://assets/ui_assets/boost_bar/fill_best.png",  # best tier — 골드/주황
]
# The art's own proportions: the track is 142px tall on the sheet and the
# fills 92px, so the rim is (142-92)/2 = 25px, or 0.176 of the track height.
# Insetting the fill by that on every side is what seats it in the well
# instead of covering the rim, at whatever height the bar is drawn.
const BOOST_BAR_FILL_INSET_FRAC := 0.176
# Kept for the judged-tier flash and the BOOST popup, which both need a
# colour rather than a texture. Named for the TIER they mean, not for where
# they sit, so flipping a threshold cannot leave a colour saying the wrong
# thing. Sampled from the fill art above.
const BOOST_BAR_ZONE_NONE_COLOR := Color(0.66, 0.68, 0.72)
const BOOST_BAR_ZONE_MID_COLOR := Color(0.98, 0.84, 0.27)
const BOOST_BAR_ZONE_BEST_COLOR := Color(1.0, 0.60, 0.13)
# Threshold ticks, drawn over the track. Dark rather than white now — the
# track's well is cream, and a white line vanished into it.
const BOOST_BAR_DIVIDER_COLOR := Color(0.09, 0.13, 0.28, 0.75)
const BOOST_BAR_DIVIDER_WIDTH := 2.0
const BOOST_BAR_FLASH_DURATION := 0.3   # highlight held after a pass is judged
const BOOST_BAR_FLASH_ALPHA := 0.85
# Was 0.0 — the quiz box sat flush on the gate zone. The boost bar needs a
# band of its own, and this is it.
const GATE_ZONE_TOP_BUFFER := BOOST_BAR_GAP + BOOST_BAR_HEIGHT + BOOST_BAR_BOTTOM_GAP

# Gate-pass speed boost: on a successful pass, GATE_SPEED is briefly
# multiplied up (all gates scroll faster for an instant, world-rush style)
# then eases back down to 1x — the "sucked through the gate" feel. This is
# real gate-movement physics, unlike the FX_* block below (which is purely
# cosmetic) — it changes where gates actually are, on purpose, per request.
# It never touches player_y/player_vel/gravity/flap input or collision math,
# and it fires from the same single-shot spot as the rest of the pass FX
# (_resolve_gate's `if passed:` branch), so it can't double-trigger.
const GATE_SPEED_BOOST_PEAK := 3.2       # multiplier on GATE_SPEED at the instant of passing
const GATE_SPEED_BOOST_HOLD := 0.06      # seconds held at full peak before it starts decaying
const GATE_SPEED_BOOST_DURATION := 0.5   # total seconds (including the hold) to ease back down to 1.0x

# ============================================================
# Hold-to-accelerate button (bottom-right).
#
# Sits alongside the tap-anywhere flap rather than replacing any part of
# it: the button is a Control with the default STOP mouse filter, so Godot
# marks a press on it as handled and _unhandled_input — where the flap
# lives — never sees it. Nothing about the flap/gravity path changes.
#
# The multiplier stacks on top of the gate-pass jolt rather than replacing
# it (see _gate_speed_multiplier), so passing a gate while holding still
# gives its kick. Release is instant: the multiplier is read fresh every
# frame off boost_button_held, there is no decay envelope.
#
# It speeds the WORLD (gates + trail), not the character's own physics —
# player_y/player_vel/gravity/flap_velocity are untouched, which is what
# keeps this from being a difficulty rebalance. The background parallax
# also stays at base rate, matching how the gate-pass jolt already
# behaves (see the GATE_SPEED comment on the parallax ratios).
# ============================================================
const BOOST_BUTTON_MULTIPLIER := 2.0   # world speed while held

# ---- Speed feel while the button is down ----
# Two layers:
#   1. the background parallax speeds up (it did NOT before — the gate-pass
#      jolt deliberately leaves the background alone, and that exclusion was
#      inherited by the hold, which made a 2x world scroll past a still sky)
#   2. the sparkle trail emits faster, so the streak behind the character
#      thickens instead of just spacing out
#
# Layer 2 rides boost_visual_blend rather than the raw bool: the world
# snapping back to 1x on release is the correct physics, but having the look
# snap with it reads as a glitch. The blend eases OUT slower than it eases in
# for the same reason.
const BOOST_VISUAL_BLEND_IN := 0.10    # seconds to reach the full boost look
const BOOST_VISUAL_BLEND_OUT := 0.20   # ...and to drop back out of it
# How much of the hold's speed-up the background takes. 1.0 = exactly as
# fast as the gates. Drop it if the far layers feel frantic; the gate-pass
# jolt is still excluded either way, so only a sustained hold moves this.
const BOOST_BG_SPEED_SHARE := 1.0
const BOOST_TRAIL_INTERVAL_SCALE := 0.5  # trail emission interval multiplier at full blend

# --- Boost glow: a coloured halo behind the character, and only while the
# button is held. Whole feature = these consts + boost_glow_elapsed +
# character_glow_texture + _draw_boost_glow + its one call in _draw() +
# assets/fx/character_glow/. Delete those to remove it.
#
# It rides boost_visual_blend like the rest of the boost look, so it fades
# in over BOOST_VISUAL_BLEND_IN and out over the slower _OUT rather than
# popping. That also means it costs nothing to be correct on the awkward
# paths: dying or pausing mid-hold clears boost_button_held, the blend eases
# to 0 on its own, and the halo goes with it — no separate teardown to
# forget (which is the bug check_boost_hold exists for).
#
# One white radial texture, tinted per mode at draw time. Generated by
# tools/bake_character_glow.ps1 rather than painted: it is a pure falloff,
# and there is no shader pass here to compute one at draw time.
const BOOST_GLOW_TEXTURE_PATH := "res://assets/fx/character_glow/glow_radial_256.png"
# Channels above 1.0 overexpose where the halo is densest, which is what
# makes it read as light rather than a translucent coloured disc. Same trick
# GATE_GLOW_TINT_COLOR uses — this project has no additive blend mode to
# reach for, since one _draw() paints the whole world.
const MODE_BOOST_GLOW_COLOR := [
	Color(1.60, 1.32, 0.30),  # SKY — yellow
	Color(0.38, 1.50, 0.45),  # JUNGLE — green
	Color(0.32, 0.80, 1.65),  # OCEAN — blue
	# DREAM — violet, and it is the one row that cannot lean on the
	# overexposure above. Its background is the only bright one: mean luma
	# 0.85 against 0.34-0.63 for the other three, so adding light to it
	# barely moves anything. The pink this started as scored 0.035 of
	# separation from that backdrop where the other modes' colours have most
	# of the value range to work with; being pink against a pale pink sky,
	# it was invisible.
	#
	# So this one separates by pulling R and G DOWN rather than by pushing
	# everything up, and only B stays over 1.0 — enough to still read as
	# light instead of a shadow. Lands at 0.083, 2.4x the pink, at hue 270
	# which is violet proper rather than the blue 262 or magenta 284 that
	# scored either side of it.
	Color(0.78, 0.18, 1.40),
]
# Size and strength are @exports rather than consts because they are the two
# that have to be settled by eye, and headless cannot see the screen: the
# overexposure above only resolves on the real canvas, so a still composite
# under-sells the halo and these want tuning in the Inspector with the game
# running. Everything else about the glow is derived.
#
# A slow breathe on top, or the halo reads as a decal stuck to the sprite.
# Deliberately gentle: this sits directly behind the thing the player is
# aiming, and anything faster competes with the flap cycle.
const BOOST_GLOW_PULSE_HZ := 1.6
const BOOST_GLOW_PULSE_ALPHA := 0.18   # +/- fraction of boost_glow_alpha
const BOOST_GLOW_PULSE_SCALE := 0.06   # +/- fraction of boost_glow_size_scale

# --- Boost burst: a one-shot flash-and-ring thrown off the character at the
# moment the button goes down. Whole feature = these consts + boost_burst_frames
# /boost_burst_elapsed + _draw_boost_burst + its call sites in
# _on_boost_pressed/_update_fx/_reset_game/_apply_mode/_draw() + the art in
# assets/fx/boost_burst/. Delete those to remove it.
#
# The counterpart to the glow: the glow says "boosting" for as long as the
# button is down, this says "just started" and is gone. So it is driven by
# its own one-shot timer rather than boost_visual_blend — a blend has no
# moment in it, and the press is the whole point.
#
# 6 frames on one row, 256px cells, one sheet per mode. Sliced at runtime by
# _slice_spritesheet like the character sheets rather than cut by a tool into
# separate files: it is an animation strip, which is the same thing those
# are, and the cell grid is regular.
const BOOST_BURST_DIR := "res://assets/fx/boost_burst/"
const BOOST_BURST_FILE_PER_MODE := ["boost_effect_sky.png", "boost_effect_jungle.png", "boost_effect_ocean.png", "boost_effect_dream.png"]
const BOOST_BURST_SHEET_GRID := Vector2i(6, 1)
# Of PLAYER_VISUAL_SIZE. The art's ring already grows and thins across its
# own frames, so nothing here animates scale — 2.1 just sizes the widest
# frame to read as bursting past a 100px character rather than sitting on it.
const BOOST_BURST_SIZE_SCALE := 2.1

@export_group("Boost Burst")
# Whole animation, seconds. 6 frames in 0.28s is ~21fps, which is the fastest
# this art can run and still be read as a ring rather than a single blink.
@export_range(0.10, 0.80, 0.01) var boost_burst_duration: float = 0.28
@export_group("")  # closes "Boost Burst"

@export_group("Boost Glow")
# Of PLAYER_VISUAL_SIZE. 2.2 puts the texture's half-alpha ring at roughly
# the character's own silhouette, so the dense part of the halo hugs the body
# and the tail spreads about half a body-width past it.
@export_range(1.2, 4.0, 0.05) var boost_glow_size_scale: float = 2.2
# At full blend, before the pulse. Raise it if the halo is too shy to read
# against a busy background; drop it if it starts hiding the character, which
# is the thing the player is actually aiming.
@export_range(0.0, 1.0, 0.01) var boost_glow_alpha: float = 0.55
@export_group("")  # closes "Boost Glow"

const BOOST_BUTTON_SIZE := 92.0        # diameter, px
const BOOST_BUTTON_MARGIN := 20.0      # inset from the screen's right/bottom edges
# Painted per-mode art, like pause/mute — this replaced a code-drawn chip
# (StyleBoxFlat circle + the word "BOOST") once the art existed. The four
# icons are the same round badge in each mode's colours, cut off one sheet
# onto a shared square canvas so this one size constant covers all four.
const MODE_BOOST_ICON_PATH := [
	"res://assets/ui_assets/sky/boost_v1.png",
	"res://assets/ui_assets/jungle/boost_v1.png",
	"res://assets/ui_assets/ocean/boost_v1.png",
	"res://assets/ui_assets/dream/boost_v1.png",
]
# 반투명하게 깐다. 게이트 구역이 화면 바닥까지 내려와서 새와 게이트가 이 버튼
# 뒤를 지나가기 때문이다 — 불투명하면 오른쪽 아래 구석이 그냥 막힌 벽이 된다.
#
# 앞의 코드로 그리던 칩은 흰 글씨의 대비 때문에 0.55 가 하한이었지만, 이제는
# 읽어야 할 글씨가 없고 그림 자체가 뭘 누르는지 말해 준다. 그래서 더 내려
# 잡아도 되지만, 너무 옅으면 배경이 밝은 DREAM 에서 버튼이 사라진다 — 0.55 는
# 그 둘 사이에서 네 모드 모두 형태가 남는 값이다.
const BOOST_BUTTON_ALPHA := 0.55
# 눌린 동안에는 거의 불투명해진다. 크기만 줄이는 pause/mute 와 달리 이 버튼은
# 평소가 반투명이라, 진해지는 쪽이 눌렸다는 신호로 훨씬 잘 보인다.
const BOOST_BUTTON_PRESSED_ALPHA := 0.92

# Gate visual: the image's hollow center is the real passage and its
# stonework is the obstacle, drawn centered on the precision zone (the
# actual pass/fail window the collision check uses) — same values the
# answer text already keys off, so frame and text stay in sync without
# needing an actual parent node yet. Passage geometry (zone/wall), judging,
# movement, and quiz logic are untouched; this only changes what gets drawn.
#
# Split into two layers, both centered on the zone, so they land exactly
# where intended: right pillar (BACK, drawn behind the player sprite so the
# bird occludes it while passing that side), left pillar (FRONT, drawn
# after the bird so it occludes the bird while passing that side). No
# nameplate box — removed after playtesting; quiz answer text is drawn at
# a fixed position above/below the wall instead (see _draw()).
#
# Ring gate art (gate_ring set): one full ring image split into a left half
# and a right half, each a 512x512 PNG with its half of the ring positioned
# on its own canvas so both halves land exactly on top of each other with
# no manual per-layer positioning (same technique the old pillar set used).
# NOTE: the same FRONT/BACK draw-order as before still applies — right half
# is drawn BEHIND the bird, left half drawn AFTER (in FRONT of) the bird, so
# passing left-to-right the bird ducks behind the right edge of the ring and
# emerges in front of the left edge, selling the "through the ring" look.
# Indexed by Mode (see _apply_mode) — each folder holds the same 3 filenames
# (gate_ring_left/right/base.png), same convention as MODE_CHARACTER_DIR.
const MODE_GATE_DIR := [
	"res://assets/gates/gate_ring/",
	"res://assets/gates/gate_ring_jungle/",
	"res://assets/gates/gate_ring_ocean/",
	"res://assets/gates/gate_ring_dream/",
]

# No glow-variant art this time (single normal image per side) — the old
# texture-swap flash is reproduced instead as a brightness tint (modulate)
# on the same texture, using the same timing shape/duration as before. See
# _gate_glow_tint / GATE_GLOW_TINT_ENVELOPE.
const GATE_GLOW_TINT_COLOR := Color(1.45, 1.55, 1.6, 1.0)  # >1 channels intentionally overexpose the ring art toward a bright white/cyan flash
const GATE_GLOW_TINT_ENVELOPE := [
	Vector2(0.0, 0.0), Vector2(0.06, 0.333), Vector2(0.12, 0.667), Vector2(0.20, 1.0),
	Vector2(0.28, 0.667), Vector2(0.36, 0.333), Vector2(0.44, 0.0),
]  # same step timing as the old GATE_GLOW_SEQUENCE/GATE_GLOW_STEP_DURATIONS, just interpolated smoothly instead of stepped between 4 discrete textures

# Ring art's own canvas size and its topmost/bottommost opaque pixels
# (measured bbox on the composited left+right halves) — the frame's actual
# outer edges, above/below the zone center. Used to keep the spawn band
# inset from the screen edges (see _gate_frame_top_overhang/
# _gate_frame_bottom_overhang) so the frame never clips off-screen.
const GATE_PILLAR_CANVAS_SIZE := 512.0
const GATE_PILLAR_TOP_LOCAL_Y := 37.0
const GATE_PILLAR_BOTTOM_LOCAL_Y := 492.0
# The ring's inner hole (the actual passable opening), same measurement
# technique — used to size the judgment zone to the new ring shape instead
# of the old pillar-frame-tuned PHASE_ZONE_MARGIN value. See
# _gate_ring_inner_zone_height.
const GATE_RING_INNER_TOP_LOCAL_Y := 128.0
const GATE_RING_INNER_BOTTOM_LOCAL_Y := 395.0
# Small forgiveness margin added on top of the ring art's own exact opening,
# split evenly top/bottom (see _gate_ring_inner_zone_height) — shared by all
# 3 modes since they all use this same ring geometry, just reskinned art.
const GATE_ZONE_HEIGHT_MARGIN_LOCAL := 20.0

# Base pedestal — a separate static image (no left/right split; it never
# occludes/is occluded by the bird, since the passable opening sits well
# above it) drawn once, first, behind everything else at each gate so the
# ring always renders in front of/on top of it. Same 512-canvas convention
# and same scale_factor as the ring textures, so it scales consistently
# with gate_visual_zone_ratio. GATE_BASE_OVERLAP_LOCAL pulls the base up a
# little from an exact edge-to-edge touch so the ring's bottom rim visibly
# rests IN the base's top platform instead of a hairline seam. See
# _gate_base_center_y_offset/_draw_gate_base.
# 어느 모드가 베이스를 쓰는가. 드림의 아치는 땅에 선 문이라 발치에 받침이
# 있어야 말이 되지만, 나머지 셋은 공중에 뜬 고리라 받침이 붙으면 오히려
# 매달린 부유물처럼 보인다. Mode 순서.
const MODE_GATE_BASE_ENABLED := [false, false, false, true]
const GATE_BASE_CANVAS_SIZE := 512.0
const GATE_BASE_TOP_LOCAL_Y := 112.0
# 링 바닥과 베이스 윗면이 얼마나 겹치는가. 모드마다 베이스 아트의 생김새가
# 달라(스카이/정글/오션은 두툼한 받침, 드림은 납작한 꽃밭 판) 같은 값으로는
# 맞지 않는다. 커질수록 베이스가 위로 올라와 기둥 발치를 더 깊이 문다.
# Mode 순서.
const GATE_BASE_OVERLAP_LOCAL := [78.0, 78.0, 78.0, 191.0]
# 베이스를 링과 별개로 줄이는 배수. 모드마다 아트의 생김새가 달라 값이
# 다르다 — 스카이/정글/오션은 링 발치를 받치는 작은 받침이지만, 드림은
# 게이트가 통째로 올라선 널찍한 꽃밭 판이라 링보다 좌우로 조금 더 나가야
# 한다. Mode 순서.
const GATE_BASE_SCALE_MULTIPLIER := [0.62, 0.62, 0.62, 0.764]
const GATE_BASE_OFFSET_X_LOCAL := 10.0  # nudges the base right of the ring's own center
# Safety margin so the FX_GATE_PUNCH_KEYFRAMES peak (+8%) can't push the
# frame's edges past the screen bounds this clamp is meant to guarantee.
const GATE_VISUAL_CLAMP_MARGIN := 1.1
#
# The frame's own display size is FIXED, not phase-scaled — it's the
# container the flag answer art and pass-through FX are built against, so
# it can't keep shrinking every phase or that art and those effects would
# never fit consistently. gate_visual_zone_ratio controls how much bigger
# the frame renders than the zone highlight inside it. The zone's own
# height is no longer a hand-tuned margin — it's derived from the ring
# art's actual inner-hole measurement (GATE_RING_INNER_TOP/BOTTOM_LOCAL_Y,
# see _gate_ring_inner_zone_height), so it automatically matches whatever
# gate_visual_zone_ratio is set to. Don't shrink this ratio too far without
# also shrinking GATE_FLAG_ICON_WIDTH/HEIGHT — the answer flag sits in the
# gap above the zone, and at some point the two start to overlap.
# Fixed sizing reference so the frame never rescales itself between phases.
const GATE_VISUAL_REFERENCE_ZONE_HEIGHT := 96.0
@export_range(1.0, 4.0, 0.05) var gate_visual_zone_ratio: float = 2.3

# Sky gradient — colors sampled from the reference
# (assets/references/sky_gradient/sky_gradient_v2.png), top -> mid -> bottom,
# drawn as two vertex-colored quads for a smooth blend.
const COLOR_SKY_TOP := Color(0.0212, 0.4322, 0.9938)
const COLOR_SKY_MID := Color(0.3670, 0.7912, 0.9892)
const COLOR_SKY_BOTTOM := Color(0.7104, 0.9909, 0.9595)
# Center divider wall — made fully transparent per request. It's still a
# real collision hazard (see _resolve_gate — touching this band is instant
# game over regardless of which lane's flag was correct), just no longer
# drawn, so it's invisible even though the top/bottom zone split still
# exists there.
const COLOR_WALL := Color(0.059, 0.008, 0.31, 0.0)
const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_TEXT_OUTLINE := Color(0.05, 0.08, 0.12, 0.85)  # keeps HUD text legible over the light sky
const COLOR_TEXT_DARK := Color(0.09, 0.12, 0.18, 1.0)  # for text drawn over the near-opaque white quiz box, where the light COLOR_TEXT would wash out
const COLOR_ZONE := Color(0.55, 0.75, 0.95, 0.55)

# Answer flag icon sits inside the gate's decorative frame, above its zone
# — positioned GATE_FLAG_GAP_ABOVE_ZONE clear of the zone's top edge (see
# _draw_gate_answer_box). Flag PNGs are all a unified 256x171 (3:2) frame
# now (see assets/flags/flags_data.json), so the display size is a rect,
# not a square — width/height match that same 3:2 ratio so the art is
# never stretched. This is the flag's fixed on-screen size — the panel
# below is what gets scaled to fit it, not the other way around.
const GATE_FLAG_ICON_WIDTH := 72.0
const GATE_FLAG_ICON_HEIGHT := 48.0
const GATE_FLAG_GAP_ABOVE_ZONE := 20.0  # extra clearance lifting the flag+panel further above the zone

# Backing panel image behind the flag (replaces the old procedural
# gold-border+corner-gem drawing). Sized so its own inner window — measured
# directly off the source PNG — matches GATE_FLAG_ICON_WIDTH/HEIGHT exactly.
# Fit by WIDTH, not height: the window's own aspect (~1.53) is a hair wider
# than the flag's fixed 1.5, and every flag is itself pre-rendered onto a
# fixed 3:2 canvas (see assets/flags/flags_data.json), so fitting by height
# left a small but visible sliver of the panel's window showing past both
# side edges on nearly every flag. Fitting by width instead makes those
# side edges flush; the tradeoff (window falling a hair short top/bottom)
# is a sub-pixel amount, not visible.
# Drawn behind the flag but AFTER the gate ring halves (see _draw()) so
# neither the panel nor the flag can ever end up hidden behind the ring.
# Indexed by Mode (see _apply_mode) — each mode's panel art has its own
# internal transparent-window position/size, measured the same way as the
# original sky panel: connected-component flood-fill from the image border
# to separate "outside" transparent area from the enclosed window cutout,
# then bbox of the largest enclosed blob (skips small incidental gaps in the
# frame's own decoration, e.g. ocean's corner-gem gap).
const MODE_GATE_FLAG_PANEL_PATH := [
	"res://assets/gates/flag_panel/panel_sky.png",
	"res://assets/gates/flag_panel/panel_jungle.png",
	"res://assets/gates/flag_panel/panel_ocean.png",
	"res://assets/gates/flag_panel/panel_dream.png",
]
# 네 패널은 색만 다른 같은 둥근 사각형이라(394x122) 치수가 하나로 통한다.
# 예전 아트는 모드마다 창 위치·크기를 따로 재야 했지만, 이제는 답 카드
# 크기에 테두리 두께만 더하면 패널 크기가 나온다.
#
# 9-slice로 그리므로(_draw_nine_patch) 패널을 어떤 크기로 늘려도 모서리
# 곡률과 테두리 두께는 그대로다. 여백은 모서리 반경(20)에 맞춘다.
const GATE_PANEL_BORDER := 7.0      # 아트에서 잰 테두리 두께(px)
# 모서리 곡률 반경(px)에 여유를 조금 더한 값.
#
# 곡선은 아트에서 x=22(= 반경 18 + 여백 4)에서 정확히 끝난다. 9-slice
# 경계를 딱 거기에 두면 모서리 조각과 변 조각이 서로 다른 배율로 같은
# 전환점을 훑게 되어, 모서리 안쪽에 1px짜리 어긋남이 남는다. 평평해진
# 구간으로 3px 밀어 두면 양쪽이 같은 픽셀에서 출발한다.
const GATE_PANEL_CORNER := 9.0
# 아트 둘레의 투명 여백(px). 실루엣이 텍스처 경계에 닿아 있으면 줄여 그릴 때
# 가장자리가 계단으로 남아서, 구울 때 여백을 둘렀다. 9-slice 모서리 여백은
# 그만큼 커야 곡선을 온전히 담고, 그리는 사각형도 그만큼 키워야 눈에 보이는
# 패널 크기가 그대로다.
const GATE_PANEL_PAD := 2.0
# 아트 픽셀을 화면에 몇 배로 그릴지. 9-slice라 이 값이 곧 화면상 테두리
# 굵기를 정한다. 1.0이면 아트 픽셀 그대로 — 모서리에 리샘플링이 없어
# 이음매가 가장 깨끗하다. 아트를 그 크기에 맞춰 구워 두었다.
const GATE_PANEL_SCALE := 1.0

# ============================================================
# Combo tier popup — an "×N" burst in the gate zone's top-right corner,
# fired on every successful pass (spawned from _resolve_gate right next to
# where `combo` itself is incremented), never a persistent HUD element.
# Entirely independent of the Phase system (gates_passed-based difficulty
# curve) — this only ever reads `combo`. Four escalating tiers, 25 combo
# wide each, capped at Tier 4 for anything >= COMBO_TIER_CAP.
# ============================================================
# Fredoka (SIL OFL, see assets/fonts/Fredoka_LICENSE.txt) — a rounded
# geometric sans that matches the painted SCORE/QUIZ/BEST labels in the HUD
# art. Replaces Mulmaru, which is a Korean face whose Latin glyphs were only
# a secondary concern; nothing the game actually renders needs Hangul (the
# quiz targets are English country names and arithmetic).
#
# It is a variable font with a wght axis (300-700, default 300 — too light
# for a HUD, so both weights below are set explicitly). The axis has to be
# keyed by its integer OpenType tag, not the string "wght": a string key is
# silently ignored and you get the 300 default back.
const COMBO_FONT_PATH := "res://assets/fonts/Fredoka.ttf"
const TEXT_FONT_WEIGHT := 600      # quiz text, combo popups, flag codes
const SCORE_FONT_WEIGHT := 700     # the score/best digits, which want more punch
const COMBO_TIER_SIZE := 25
const COMBO_TIER_CAP := 100
const COMBO_DISPLAY_MARGIN := Vector2(20.0, 16.0)  # inset from the gate zone's top-right corner

# Indexed by tier (0..3 = Tier 1..Tier 4).
const COMBO_TIER_DURATIONS := [0.3, 0.35, 0.45, 0.55]
const COMBO_TIER_FONT_SIZES := [28, 34, 40, 50]
const COMBO_TIER_PARTICLE_COUNTS := [0, 4, 9, 16]  # fed to _spawn_spark_burst's count_range
const COMBO_TIER_RISE := [10.0, 14.0, 18.0, 22.0]
const COMBO_SHAKE_DURATION := 0.12    # Tier 3+ only — much smaller/shorter than the gate-pass impact shake
const COMBO_SHAKE_PEAK_AMPLITUDE := 2.5  # px, per spec's "2~3px"
const COMBO_GLOW_DURATION := 0.6      # Tier 4 only — screen-edge glow, roughly matches that tier's popup lifetime
const COMBO_GLOW_COLOR := Color(1.0, 0.75, 0.25)  # warm gold — no existing "fever time" effect in this project to match, so this is a fresh design
const COMBO_GLOW_BAND_PX := 36.0
const COMBO_GLOW_PEAK_ALPHA := 0.22

# ============================================================
# Sky Background / Parallax Background system. Purely decorative — nothing
# here is read by collision/scoring/spawn logic, and nothing here writes to
# player_y/player_vel/gates/score/etc. Draw order (back to front, see
# _draw()): sky gradient -> distant mountains -> sparkle -> far castle ->
# mid clouds (far sub-group, then near sub-group) -> [gameplay:
# pillars/bird/zone/FX] -> HUD text. Every layer's scroll speed is
# expressed as a fraction of
# GATE_SPEED (the *base* gameplay rate — deliberately not the temporary
# gate-pass speed boost, so the background stays calm during that FX) and
# updates every frame regardless of game state, the same way the old cloud
# layer always did (menu/countdown/playing/game over all keep it
# drifting). Every pool below is a fixed-size Array (or, for the
# single-instance castle, a handful of flat vars) recycled in place
# rather than freed and reallocated, per the "no per-frame GC churn"
# requirement.
#
# NOTE: a near-cloud-sea foreground layer used to live here and was removed
# entirely per request; its unused source file has since been deleted too.
# ============================================================

# --- Layer 1: distant mountain range — the farthest landform, a slow
# horizon band anchored to the bottom of the screen. The two source strips
# are different pixel widths, so instead of one seamless tile this chains
# random strips edge-to-edge in a small pool, recycling a strip to just
# past the current rightmost edge once it fully scrolls off the left (same
# recycle-in-place approach as the mid clouds below); each recycle also
# rerolls a random horizontal flip for extra variety from just 2 source
# images. Unlike the other layers, this art already has a real soft alpha
# fade baked into its edges (painted fading to white, then keyed to
# transparency — see the asset processing notes), so it needs no extra
# alpha reduction here to read as distant/hazy. Each source PNG also fades
# to near-transparent right at its own left/right edges (it's a range
# tapering off, not a hard-cut tile), so joining two strips flush
# edge-to-edge left a visible weak/thin seam where both tapered edges met —
# MOUNTAIN_SEGMENT_OVERLAP_FRAC pulls each new segment slightly left of
# flush so the next strip's solid body covers the previous one's faint
# tail instead of both faint tails lining up bare. Each source PNG also
# has a thin transparent margin below its actual silhouette (cropped out
# of a taller reference sheet) — MOUNTAIN_BOTTOM_OVERSHOOT_FRAC pushes the
# draw position down past that margin so the silhouette's base always
# reaches the screen's bottom edge instead of leaving bare sky beneath. ---
const MOUNTAIN_TEXTURE_PATHS := [
	"res://assets/backgrounds/mountains/mountain_01.png",
	"res://assets/backgrounds/mountains/mountain_02.png",
]
const MOUNTAIN_POOL_SIZE := 3
const MOUNTAIN_HEIGHT_FRACTION := 0.16      # of view height
const MOUNTAIN_SPEED_RATIO := 0.14          # fraction of GATE_SPEED
const MOUNTAIN_ALPHA := 1.0                 # the art's own alpha fade already handles the haze
const MOUNTAIN_BOTTOM_OVERSHOOT_FRAC := 0.20  # of height_px — covers the deepest interior valley (~16%) with room to spare
const MOUNTAIN_SEGMENT_OVERLAP_FRAC := 0.5    # of height_px — hides the faint left/right taper at each strip's seam

# --- Layer 2: background sparkle ---
const BG_SPARKLE_TEXTURE_PATHS := [
	"res://assets/backgrounds/sparkle/bg_sparkle_01.png",
	"res://assets/backgrounds/sparkle/bg_sparkle_02.png",
	"res://assets/backgrounds/sparkle/bg_sparkle_03.png",
]
const BG_SPARKLE_POOL_SIZE := 5             # ~3-6 visible at once, per spec
const BG_SPARKLE_SPEED_RATIO := 0.15        # fraction of GATE_SPEED
const BG_SPARKLE_DURATION_RANGE := Vector2(1.5, 3.5)  # one full fade in -> out cycle
const BG_SPARKLE_SCALE_RANGE := Vector2(0.6, 1.2)
const BG_SPARKLE_ALPHA_RANGE := Vector2(0.25, 0.65)
const BG_SPARKLE_PULSE_CHANCE := 0.4        # fraction of sparkles that also get a subtle scale breathe
const BG_SPARKLE_PULSE_AMOUNT := 0.08
const BG_SPARKLE_Y_BAND := Vector2(0.05, 0.55)  # sky area only

# --- Layer 3: far castle — a rare landmark, not a constant fixture. Low
# alpha stands in for "hazy with distance" (no blur pass available in this
# custom-draw setup); a long cooldown between appearances keeps it rare
# rather than something the player sees every gate. Single-instance state
# (flat vars, not a pool) since only one is ever on screen at a time. ---
const CASTLE_TEXTURE_PATH := "res://assets/backgrounds/castle/castle_far_01_256.png"
const CASTLE_HEIGHT_FRACTION_RANGE := Vector2(0.24, 0.32)  # of view height — the source art already reads as distant, so this doesn't need to be tiny too
const CASTLE_Y_BAND := Vector2(0.28, 0.52)                 # sky mid/upper-mid, never dead-centered
const CASTLE_SPEED_RATIO := 0.12                           # fraction of GATE_SPEED — slower than even the far mid-clouds
const CASTLE_ALPHA_RANGE := Vector2(0.45, 0.60)            # noticeably hazier than a foreground element
const CASTLE_COOLDOWN_RANGE := Vector2(35.0, 55.0)         # seconds with no castle after one leaves — a rare sighting, not a fixture

# --- Layer 4: mid-distance clouds, split into near/far sub-groups for
# parallax depth — near clouds bigger/more opaque/faster, far clouds
# smaller/fainter ("hazier")/slower. There's no real blur available in
# this custom-draw setup (no shader pass), so lower alpha is the stand-in
# for "distant haze". Both sub-groups draw the same 3 textures. ---
const CLOUD_MID_TEXTURE_PATHS := [
	"res://assets/backgrounds/clouds_mid/cloud_mid_01.png",
	"res://assets/backgrounds/clouds_mid/cloud_mid_02.png",
	"res://assets/backgrounds/clouds_mid/cloud_mid_03.png",
]
const CLOUD_MID_NEAR_COUNT := 2
const CLOUD_MID_FAR_COUNT := 2
const CLOUD_MID_NEAR_SCALE_RANGE := Vector2(1.10, 1.50)
const CLOUD_MID_FAR_SCALE_RANGE := Vector2(0.50, 0.80)
const CLOUD_MID_NEAR_ALPHA_RANGE := Vector2(0.85, 1.00)
const CLOUD_MID_FAR_ALPHA_RANGE := Vector2(0.30, 0.50)
const CLOUD_MID_NEAR_SPEED_RATIO := 0.40    # fraction of GATE_SPEED
const CLOUD_MID_FAR_SPEED_RATIO := 0.20     # fraction of GATE_SPEED
const CLOUD_MID_Y_BAND := Vector2(0.20, 0.65)

# ============================================================
# Per-mode scrolling background (see current_mode/_apply_mode/_draw()). A
# painted scene per mode, scaled to fill the view height and tiled
# horizontally. Falls back to the old mountains/sparkle/castle/cloud_mid
# layers below for any mode without a dedicated image yet (empty path here,
# or the file just doesn't exist on disk) — see bg_texture's null-check in
# _draw()/_process().
#
# Every mode is a pair now: a far painting plus a near cut-out, drawn over
# it at a faster scroll for parallax depth. The single-image case is still
# supported and costs nothing — leave a mode's MODE_BG_NEAR_TEXTURE_PATH row
# empty and it falls back to drawing the far layer alone.
# ============================================================
const MODE_BG_TEXTURE_PATH := [
	# _blur variants — a pre-blurred copy of the same art (no runtime blur
	# shader in this custom-draw setup), so the background reads as soft/
	# out-of-focus instead of competing for detail with the gate/character.
	# tools/blur_background.ps1 bakes these and records each file's sigma.
	"res://assets/backgrounds/sky_world/background_far_blur.png",
	"res://assets/backgrounds/jungle_world/background_far_blur.png",
	"res://assets/backgrounds/ocean_world/background_far_blur.png",
	# 드림의 블러는 다른 모드보다 훨씬 약하다(시그마 1.1). 이 그림은 처음부터
	# 부드러운 파스텔이라 세게 걸면 꽃 모양만 뭉개진다.
	"res://assets/backgrounds/dream_world/background_far_blur.png",
]

# Optional near layer, index-aligned to MODE_BG_TEXTURE_PATH. "" = this mode
# has none. Drawn over its far layer at bg_near_speed_ratio, and still
# behind everything gameplay — it is a backdrop, not something the bird can
# pass behind.
#
# The art has to be a cut-out (mostly transparent), or it just hides the far
# layer and the parallax buys nothing. tools/check_bg_layers.gd asserts
# that.
const MODE_BG_NEAR_TEXTURE_PATH := [
	"res://assets/backgrounds/sky_world/background_near_blur.png",
	"res://assets/backgrounds/jungle_world/background_near_blur.png",
	"res://assets/backgrounds/ocean_world/background_near_blur.png",
	"res://assets/backgrounds/dream_world/background_near_blur.png",
]

@export_group("Sky Background")
@export_range(0.0, 2.0, 0.01) var bg_speed_ratio: float = 0.15  # fraction of GATE_SPEED
# The near layer's own rate, for modes that have one. 2.7x the far layer is
# what sells the depth; the old cloud parallax used the same spread (0.20
# far / 0.40 near) and 0.40 was the fastest anything in the background ever
# moved. Going past that starts to read as the backdrop racing the gates
# rather than sitting behind them — the gates themselves travel at 1.0.
@export_range(0.0, 2.0, 0.01) var bg_near_speed_ratio: float = 0.40
# Dims the background art so its own strong color/detail doesn't compete
# with the gate/flag/character sitting on top of it — 1.0 = full original
# brightness, lower recedes it further into the background.
@export_range(0.3, 1.0, 0.01) var bg_brightness: float = 0.95

@export_group("")  # closes "Sky Background" so every @export below lands back in the default Inspector category

# ============================================================
# Ambient background particles — small, pre-blurred sprites drawn as part
# of the background (right after the scrolling background image, still
# behind the gate/character/UI), animating continuously regardless of game
# state. One themed sprite + motion per mode: SKY twinkles in place in the
# sky, JUNGLE falls top-to-bottom with a side-to-side flutter, OCEAN rises
# bottom-to-top with a gentle sway — same per-mode-file swap convention as
# everything else, and the same "pre-blur the PNG once" trick as the
# backgrounds above (no runtime blur shader in this custom-draw setup).
# ============================================================
# All four modes' ambient art comes off one sheet,
# assets/backgrounds/ambient_sheet.png, cut by tools/slice_ambient_sheet.ps1
# — six rows: flowers and petals to DREAM, feathers to SKY, leaves to
# JUNGLE, two rows of bubbles to OCEAN. DREAM has its own art now rather
# than borrowing SKY's.
#
# The blur is baked into these files, not applied at runtime (this project
# has no blur shader — same story as the backgrounds themselves). Re-cut the
# sheet with a different -Sigma to change how soft they are.
const MODE_PARTICLE_DIR := [
	"res://assets/backgrounds/sky_world/particles/",
	"res://assets/backgrounds/jungle_world/particles/",
	"res://assets/backgrounds/ocean_world/particles/",
	"res://assets/backgrounds/dream_world/particles/",
]
const MODE_PARTICLE_PREFIX := ["feather", "leaf", "bubble", "petal"]
# Count 0 = that mode has no ambient layer. SKY is 0 on purpose: the sheet's
# feathers did not suit the scene, so its row is skipped by the slicer too
# (see $RowTargets in tools/slice_ambient_sheet.ps1) and no feather_NN.png
# exists. Its prefix/dir entries are kept so the four arrays stay indexable
# by Mode — put a count back and drop art in that folder to revive it.
const MODE_PARTICLE_COUNT := [0, 6, 7, 10]  # the loader keeps whichever of _01.._NN actually exist

# How each mode's ambient art travels. The art alone is not enough — a
# feather that falls straight down like a leaf reads wrong, and a bubble has
# to go the other way entirely.
#   DRIFT_DIAGONAL — enters top-right, leaves bottom-left, swaying
#   FALL           — enters top, leaves bottom, swaying
#   RISE           — enters bottom, leaves top, swaying
enum AmbientMotion { DRIFT_DIAGONAL, FALL, RISE }
const MODE_PARTICLE_MOTION := [
	AmbientMotion.DRIFT_DIAGONAL,  # SKY — feathers
	AmbientMotion.FALL,            # JUNGLE — leaves
	AmbientMotion.RISE,            # OCEAN — bubbles
	AmbientMotion.DRIFT_DIAGONAL,  # DREAM — flowers and petals
]
# Sideways travel for DRIFT_DIAGONAL, as a multiple of the fall speed. The
# drift is leftward, so the spawn band is widened past the right edge by the
# same ratio in _make_ambient_particle — otherwise everything would enter
# through the top and nothing through the right side.
#
# 이 값은 보이는 각도가 아니다. 화면 전체가 이미 왼쪽으로 흐르고 있어서,
# 플레이어가 "이 물체 자신의 움직임"으로 읽는 것은 배경 대비 상대 운동뿐이다.
#
# 배경 스크롤(GATE_SPEED 130 기준): 원경 0.15 -> 19.5px/s, 근경 0.40 ->
# 52px/s. 그래서 45°처럼 보이게 하려면 45°로 두면 안 된다 —
#
#   비율   실제 vx   체감 각도(원경 대비 / 근경 대비)
#   1.0     35.0        24° / -26°
#   1.5     52.5        43° /   1°
#   2.5     87.5        63° /  45°
#   3.5    122.5        71° /  64°
#
# 1.0(진짜 45°)에서 근경 대비 -26°, 즉 꽃잎이 근경 구름보다 느려서 오히려
# 오른쪽 아래로 기울어 보인다. 이게 각도를 0.55 -> 1.0 으로 올려도 여전히
# 수직으로 떨어져 보였던 이유다. 2.5 면 근경 대비 45°, 원경 대비 63° 로
# 어느 쪽을 기준으로 봐도 확실히 왼쪽 아래다.
#
# 배경 속도를 바꾸면(bg_speed_ratio / bg_near_speed_ratio) 이 값도 다시
# 잡아야 한다. 위 표는 그 계산을 되풀이하지 않도록 남긴 것이다.
#
# 이 값은 모드가 아니라 모션의 각도다. 지금 이 모션을 쓰는 건 DREAM 뿐이지만
# (SKY 는 MODE_PARTICLE_COUNT 가 0), 깃털이 되살아나도 같은 각도로 흐르는
# 것이 맞다.
const PARTICLE_DRIFT_X_RATIO := 2.5
# DRIFT_DIAGONAL gets its own, much lazier flutter than FALL does, and this
# is what actually makes the diagonal read.
#
# The sway is a sine on x, so its peak sideways speed is 2*PI*freq*amp. On
# the shared FALL values (up to 0.9 Hz at 25px) that is ~141px/s — four
# times the 35px/s the drift itself moves. The net travel was a clean 45
# degrees all along, but every instant of it was dominated by the wobble, so
# the eye tracked a petal falling straight down and shaking rather than one
# crossing the screen. Plotting eight paths over 8s showed it: a 45 degree
# envelope made of segments that are individually near-vertical.
#
# So the rule is that the flutter stays subordinate to the drift: at the top
# of these ranges 2*PI*0.3*16 = 30px/s, just under the 35px/s drift, and at
# the bottom 7.5px/s. One sway cycle now spans 117-234px of fall instead of
# 39-88px — a long, lazy waver along the diagonal instead of a tight zigzag
# that hides it.
const PARTICLE_DIAGONAL_FLUTTER_AMP_RANGE := Vector2(8.0, 16.0)
const PARTICLE_DIAGONAL_FLUTTER_FREQ_RANGE := Vector2(0.15, 0.3)
# Radians. Sprites are drawn upright on the sheet; a feather or leaf pinned
# to one angle for its whole fall looks stamped on, so each gets a random
# start angle and a slow tumble.
const PARTICLE_SPIN_RANGE := Vector2(-0.5, 0.5)
# Extra leftward push while the boost is held, px/s at full blend. Zero at
# rest, so each mode keeps exactly the direction it was given — a bubble
# still rises, a leaf still falls — and only gains the sideways rush on top
# while the button is down. This is what sells "the world is streaming past"
# for modes whose own motion is purely vertical and would otherwise just
# fall or rise a bit faster.
#
# Rides boost_visual_blend rather than the raw multiplier so the sideways
# drift eases in and out instead of the whole field jerking.
const PARTICLE_BOOST_WIND_X := 150.0

@export_group("Ambient Particles")
@export_range(0, 40, 1) var particle_count: int = 8
@export var particle_draw_size_range: Vector2 = Vector2(34.0, 58.0)  # final on-screen px, independent of the source image's own resolution
@export_range(0.0, 1.0, 0.01) var particle_alpha_max: float = 0.5  # backdrop, not decoration — this plus the baked blur is what keeps them from competing with the gate
@export_range(5.0, 120.0, 1.0) var particle_fall_speed: float = 35.0      # DRIFT_DIAGONAL + FALL — sky, jungle, dream
@export var particle_flutter_amplitude_range: Vector2 = Vector2(10.0, 25.0)  # ...their side-to-side sway width
@export var particle_flutter_freq_range: Vector2 = Vector2(0.4, 0.9)         # ...and its speed, Hz
@export_range(5.0, 120.0, 1.0) var particle_rise_speed: float = 30.0      # RISE — ocean
@export var particle_sway_amplitude_range: Vector2 = Vector2(8.0, 18.0)   # ...ocean's gentler bob
@export var particle_sway_freq_range: Vector2 = Vector2(0.3, 0.7)

@export_group("")  # closes "Ambient Particles" so every @export below lands back in the default Inspector category

# ============================================================
# Gate-pass success FX — purely cosmetic, a ~0.25s burst triggered exactly
# once per gate from _resolve_gate() (see _play_gate_success_fx), the same
# single-fire point that already exists (g.resolved is set the instant the
# player crosses the wall line — see _update_playing). Nothing in this
# block, or in _play_gate_success_fx() and the functions it calls, ever
# assigns to player_y, player_vel, gravity, flap_velocity, GATE_SPEED, or
# any zone/collision value — FX state lives entirely in its own variables
# below, and the one screen-shake exception moves this Node2D's own
# `position` (a render-only transform; UI lives in a separate CanvasLayer
# untouched by it), never the player's logical position. The bird "stretch"
# likewise only scales the drawn rect (draw_set_transform), never
# PLAYER_SIZE/player_y. successFxIntensity scales every magnitude below
# from one place; 0.0 disables the burst's added punch entirely.
# ============================================================
@export_range(0.0, 2.0, 0.05) var successFxIntensity: float = 1.0

# 1. Impact flash — a thicker white/cyan ring right at the frame's own
# outer edge, so it never paints over the bird or the center passage (no
# full-screen flash). Lengthened/thickened from the original 1-2 frame
# design so it actually reads as a hit instead of a blink.
const FX_IMPACT_FLASH_DURATION := 0.10
const FX_IMPACT_FLASH_WIDTH := 9.0
const FX_IMPACT_FLASH_MARGIN := 8.0   # ring sits this far outside the frame's own outer edge
const FX_IMPACT_FLASH_COLOR := Color(0.85, 0.98, 1.0, 1.0)

# 2. Gate visual punch — draw-time scale keyframes (time_fraction, scale)
# on the gate sprite only; the collision zone this is centered on never
# moves. 1.00 -> 1.18 -> 0.90 -> 1.00 across FX_GATE_PUNCH_DURATION —
# exaggerated further than the original 1.08/0.97 for more visible impact.
const FX_GATE_PUNCH_DURATION := 0.20
const FX_GATE_PUNCH_KEYFRAMES := [
	Vector2(0.0, 1.0),
	Vector2(0.15, 1.18),
	Vector2(0.5, 0.90),
	Vector2(1.0, 1.0),
]

# Shared per-gate-side timeline length; must stay >= FX_GATE_PUNCH_DURATION
# and GATE_GLOW_TINT_ENVELOPE's total (currently 0.44s) — this is what
# _gate_glow_tint reads elapsed time against.
const FX_GATE_TIMELINE_DURATION := 0.45

# 3. Two-layer particle burst, all pre-colored art, no runtime hue
# tinting: big sparks/immediate, then small sparks/delayed.
#
# Both layers share the one sparkle sheet the character trail draws from,
# mixed per mode by FX_BURST_COLOR_WEIGHTS_PER_MODE — so a gate pass
# throws the same starlight the character has been trailing, rather than a
# second, unrelated set of particles. The old per-concept fx_big_N /
# fx_small_N art under assets/fx/<concept>/ is no longer loaded at all.
#
# There used to be a third layer between the two: a themed object per
# concept (wings for sky, leaves for jungle, bubbles for ocean) with its
# own motion — scatter, flutter, rise-and-sway. Art and code were removed
# together; `git show <commit>:scripts/Main.gd` has the whole thing if it
# comes back.
#
# Colour mix for the two spark layers, drawn from the same four sparkle
# rows the trail uses (see the shared-sparkle block further down). Weights
# are relative and indexed to SPARKLE_COLOR_NAMES.
#
# The mode's own colour carries the burst and the other three are
# sprinkled through it, so a pass reads as that mode celebrating rather
# than a generic confetti cannon — at 7:1:1:1 that is ~70% the mode's
# colour, ~10% each of the rest. DREAM has no colour of its own to
# favour, being the rainbow already, so it weights all four the same.
#
# _apply_mode turns these into fx_burst_textures by repeating each
# colour's sprites weight-many times, so the uniform pick inside
# _spawn_spark_burst lands on this distribution with no extra logic.
const FX_BURST_COLOR_WEIGHTS_PER_MODE := [
	[7.0, 1.0, 1.0, 1.0],  # SKY — mostly gold
	[1.0, 7.0, 1.0, 1.0],  # JUNGLE — mostly green
	[1.0, 1.0, 7.0, 1.0],  # OCEAN — mostly blue
	[1.0, 1.0, 1.0, 1.0],  # DREAM — even rainbow
]
const FX_SPARK_BURST_A_COUNT_RANGE := Vector2i(6, 9)        # big, at 0ms
const FX_SPARK_BURST_B_COUNT_RANGE := Vector2i(18, 26)      # small, delayed
const FX_SPARK_BURST_B_DELAY_RANGE := Vector2(0.04, 0.06)
# Longest edge in px, NOT a multiplier. The sparkle sheet ships each shape
# at its own resolution (107px to 270px on the longest edge), so a raw
# multiplier would let the shape the RNG happened to pick decide how big
# the particle came out. _spawn_spark_burst normalises by the texture's
# longest edge instead.
const FX_SPARK_BURST_A_SIZE_RANGE := Vector2(30.0, 62.0)
const FX_SPARK_BURST_B_SIZE_RANGE := Vector2(13.0, 24.0)
const FX_SPARK_LIFETIME_RANGE := Vector2(0.20, 0.42)
const FX_SPARK_SPEED_RANGE := Vector2(70.0, 150.0)          # px/s, outward from gate center
const FX_SPARK_RING_MARGIN := 18.0  # spawn ring sits this far outside the frame's own outer edge

# 5. Speed accent — short thick streaks, fired together with spark burst B.
const FX_SPEED_LINE_COUNT_RANGE := Vector2i(4, 6)
const FX_SPEED_LINE_DURATION := 0.13
const FX_SPEED_LINE_LENGTH_RANGE := Vector2(30.0, 60.0)
const FX_SPEED_LINE_THICKNESS := 4.5
const FX_SPEED_LINE_Y_SPREAD := 0.4                 # fraction of PLAYER_VISUAL_SIZE.y either side
const FX_SPEED_LINE_CYAN := Color(0.75, 0.96, 1.0)
const FX_SPEED_LINE_WHITE := Color(1.0, 1.0, 1.0)

# ============================================================
# Character trail — a stream of tiny sparkle stars shed behind the
# character, marking the path it just flew, thickening into a burst on
# every tap.
#
# One system, not two. An earlier pass ran a separate large "tap flare"
# alongside this, and the two sparkle effects on the same input just read
# as clutter. The tap is now the same particle as the trail, only more of
# them and slightly larger — so a tap punctuates the trail instead of
# competing with it.
#
# The thing that makes this work: PLAYER_X never moves, so a particle
# parked at the character's tail would just pile into a vertical column.
# Each one instead travels left with the world at the current scroll
# speed, which is what sells it as being *left behind*. It also means a
# gate pass's speed boost stretches the trail out for free — see
# _gate_speed_boost_multiplier.
#
# While the boost button is held this stops being a wake and becomes speed
# lines instead — see the TRAIL_BOOST_STREAK_* block below.
#
# Deliberately sparse: the character is small and the quiz gate is what
# the player actually has to read, so a steady plume would just dirty the
# screen. The baseline holds 3-4 tiny particles alive at a time, and the
# only time it thickens is the instant of a tap (see _spawn_trail_burst,
# called from the flap handler) — which doubles as tactile feedback for
# the input.
#
# Art comes from assets/fx/tap/, sliced off the one sparkle sheet by
# tools/slice_tap_fx.ps1 — see TRAIL_COLORS_PER_MODE below for how the
# colour is picked. Nothing is tinted at runtime.
#
# Whole feature = these consts + trail_texture_sets/trail_particles/
# trail_spawn_timer/trail_color_cursor + _update_bird_trail/
# _spawn_trail_particle/_spawn_trail_burst/_draw_bird_trail + their four
# call sites. Delete those to remove it.
# ============================================================
const TRAIL_ENABLED_PER_MODE := [true, true, true, true]  # SKY, JUNGLE, OCEAN, DREAM
const TRAIL_SPAWN_INTERVAL := 0.19           # seconds between baseline particles — with TRAIL_LIFETIME_RANGE this keeps ~3-4 alive
const TRAIL_TAP_BURST_RANGE := Vector2i(5, 8)  # extra particles thrown off at the moment of a tap
const TRAIL_TAP_BURST_SIZE_SCALE := 1.6        # burst particles are drawn larger than the baseline ones, so the tap reads as a puff and not just "more specks"
const TRAIL_TAP_BURST_JITTER := 14.0           # px of scatter for burst particles only — wider than TRAIL_ORIGIN_JITTER so a tap spreads instead of stacking on the baseline's spawn point
const TRAIL_ORIGIN_FRAC := Vector2(-0.30, 0.10)  # spawn point as a fraction of PLAYER_VISUAL_SIZE from the character's center
const TRAIL_ORIGIN_JITTER := 6.0             # px of random scatter around that point
const TRAIL_LIFETIME_RANGE := Vector2(0.50, 0.80)
# Longest edge in px, per mode. Small on purpose (see the header).
#
# SKY, JUNGLE and OCEAN share one size. They used to differ — SKY ran
# smaller on the theory that its gold sparkles popped off blue sky while
# the other two were drawing their own colour onto a background of that
# same colour — but that was written for the old per-mode art. Measured
# against the sheet now in use, SKY’s gold on its sky (RGB distance ~191)
# and JUNGLE’s green on its dark foliage (~184) are within noise of each
# other, so there was nothing left for the split to express.
#
# DREAM is the one real exception, for two reasons that stack. Its
# background is near-white (~(207,219,230), against SKY’s ~(135,187,225))
# and every sparkle on the sheet is white-cored, so the core washes out
# and only the thin coloured rim survives — the weakest pairing on the
# board (~65). On top of that the unicorn is drawn at
# MODE_VISUAL_SIZE_SCALE 1.20, so an identically-sized particle reads
# smaller beside it.
const TRAIL_SIZE_RANGE_PER_MODE := [Vector2(7.0, 13.0), Vector2(7.0, 13.0), Vector2(7.0, 13.0), Vector2(11.0, 19.0)]
const TRAIL_DRIFT_Y_RANGE := Vector2(-10.0, 10.0)  # px/s of random vertical wander, on top of the per-mode drift below
const TRAIL_INHERIT_VEL_Y := 0.08            # how much of player_vel each particle carries off
const TRAIL_SHRINK := 0.45                   # fraction of its size a particle loses over its life
const TRAIL_ALPHA := 1.0
const TRAIL_OFFSCREEN_MARGIN := 20.0          # px past the left edge before a particle is dropped
# The art is 4-point stars, so orientation matters in a way it did not for
# the round blobs this replaced: spawn near-upright and turn slowly, or a
# particle this small just smears into a speck.
const TRAIL_ROTATION_JITTER := 0.35          # radians either side of upright at spawn
const TRAIL_SPIN_RANGE := Vector2(-0.9, 0.9) # radians/s
# Per-mode vertical drift, px/s, negative = upward. OCEAN is the reason
# this exists: bubbles that rise out of the spawn point while the world
# pushes them left read as a shark actually swimming forward. SKY drifts
# up a hair so sparkles hang; JUNGLE settles, like shaken-loose leaves.
const TRAIL_DRIFT_Y_PER_MODE := [-4.0, 7.0, -26.0, -4.0]

# --- Boost streak: while the button is held, the trail stops being a wake
# that follows the character and becomes speed lines shooting straight back
# from it.
#
# The baseline trail already rides the faster world during a boost, which
# spaces the particles out — but spacing alone did not read as speed,
# because three other things were still saying "wake". Each particle carries
# a random +/-10px/s of vertical wander plus a slice of player_vel, so the
# stream scattered; each one spawns with a random tilt and a slow spin, so
# it read as tumbling debris; and the sprite stayed a symmetric 4-point
# star, which has no direction in it at all. This block turns off all three
# and stretches the star along its travel instead.
#
# Baked per particle at spawn from boost_visual_blend (see the "streak"
# field), not read live: a particle launched during a boost should keep
# streaking after the button comes up, the same way a thrown thing keeps
# going. It also means the transition is per-particle rather than the whole
# field snapping over at once.
#
# All four now. It shipped as SKY-only to see whether it suited the art
# before committing the rest, and it does; the flags stay per-mode so one
# can be pulled back out without touching anything else, the same way
# TRAIL_ENABLED_PER_MODE is written.
#
# OCEAN is the one that changes most, and it is worth knowing why before
# judging it. Its bubbles rise at -26px/s, the strongest drift of any mode,
# so its idle trail scatters over 22.6px of height where SKY's covers 4.5.
# A streak flattens all of them to about the same 1.2-1.9px, which means
# OCEAN gives up the most character for it.
#
# DREAM draws the heaviest line: its particles are 11-19px against everyone
# else's 7-13, so at boost_streak_stretch they are 52-77px long rather than
# 32-58, and they overlap into something noticeably thicker. It also steps
# through four colours, so its streak is a rainbow rather than one hue.
const TRAIL_BOOST_STREAK_PER_MODE := [true, true, true, true]  # SKY, JUNGLE, OCEAN, DREAM
# NOT given any extra speed of its own, which was the first thing tried and
# is worth recording as a dead end. PLAYER_X is 130 on a 480-wide screen and
# the spawn point sits 30px behind that, so a streak has 100px of room
# before it is culled at the left edge — there is nowhere for a longer trail
# to go. Measured: riding the boosted world alone (260px/s) keeps a particle
# on screen 0.38s, and adding 200px/s of its own cut that to 0.26s, which
# left FEWER alive at once and a shorter line, not a longer one. The world
# scroll is already carrying them away from the character; what was missing
# was direction in the sprite, below.
# Squash across the direction of travel. Pairs with boost_streak_stretch
# below: stretched along X and thinned on Y is the whole reason a symmetric
# 4-point star can read as a speed line. Rotation and spin are killed to 0
# in step with it — a stretched star that is also tilted and turning reads
# as a spinning blade rather than a streak.
const TRAIL_BOOST_STREAK_SQUASH := 0.38
# Spawn scatter is redistributed rather than removed: collapsed on Y so the
# particles share one line, widened on X so they populate its length
# immediately instead of stacking on the spawn point and only spreading as
# they travel.
const TRAIL_BOOST_STREAK_Y_JITTER_SCALE := 0.18
const TRAIL_BOOST_STREAK_X_JITTER := 26.0
# Longer-lived — though during a boost this changes the FADE, not the
# lifespan. Position culls a streak at 0.38s, well inside even the base
# 0.5-0.8s lifetime, so what the scale actually buys is a slower alpha ramp:
# the streak is still at ~0.87 alpha when it reaches the left edge instead
# of ~0.66, which keeps the line even along its length rather than dimming
# toward the tail. A speed line wants to be uniform.
const TRAIL_BOOST_STREAK_LIFETIME_SCALE := 1.5

@export_group("Boost Streak")
# How far each particle is stretched along its travel. These are 7-13px
# sparkles, so this is what decides whether the streak reads as a bold line
# or a row of specks: at 4.5 a particle draws 32-59px long, comfortably
# longer than the ~12px gap between spawns, so they overlap into something
# continuous rather than dotted.
@export_range(1.0, 8.0, 0.1) var boost_streak_stretch: float = 4.5
# Emission multiplier while streaking, on top of the BOOST_TRAIL_INTERVAL_SCALE
# every mode already gets. Density is the other half of "continuous": with
# only 100px of room behind the character, a bolder streak has to come from
# packing that space rather than extending it.
@export_range(1.0, 4.0, 0.1) var boost_streak_density: float = 2.0
@export_group("")  # closes "Boost Streak"
# ---- Shared sparkle art ----
# One sheet, assets/fx/fx_small_N.png, feeds BOTH the trail above and the
# gate-pass burst below. Four rows, one per colour; six shapes across
# (bare 4-point stars large/medium/small, then the same three ringed with
# orbiting dots). tools/slice_tap_fx.ps1 cuts it into assets/fx/tap/.
#
# Nothing is tinted at runtime: each sparkle keeps a white-hot core inside
# a coloured rim, and a modulate over white art would flatten exactly that.
# Colour is therefore chosen by picking a different file, which is why
# every colour is loaded for every mode (sparkle_texture_sets) and the
# per-feature tables below only pick among them.
const SPARKLE_DIR := "res://assets/fx/tap/"
const SPARKLE_COLOR_NAMES := ["gold", "green", "blue", "pink"]  # row order on the sheet; every table below is indexed to match
const SPARKLE_SPRITES_PER_COLOR := 6  # tap_<colour>_1..6.png; the loader keeps whichever exist

# Trail colour per mode, matched to the character. Single-colour, so the
# streak behind the character stays legible as one thing.
#
# DREAM lists all four rows instead of one, and _spawn_trail_particle steps
# one colour per particle — carrying the cursor across spawns rather than
# re-rolling, which would repeat colours — so the unicorn trails a rainbow
# and its tap bursts come out multicoloured.
const TRAIL_COLORS_PER_MODE := [
	["gold"],                           # SKY — red bird
	["green"],                          # JUNGLE — green dragon
	["blue"],                           # OCEAN — blue shark
	["gold", "green", "blue", "pink"],  # DREAM — unicorn, all four rows as a rainbow
]

# 4. Bird visual stretch — sprite-draw scale only (draw_set_transform in
# _draw()); player_y/player_vel/PLAYER_SIZE are never touched. Pushed
# further from 1:1 and held slightly longer for a more obvious squash.
const FX_STRETCH_DURATION := 0.15
const FX_STRETCH_SCALE_X_PEAK := 1.24
const FX_STRETCH_SCALE_Y_PEAK := 0.80
const FX_STRETCH_KEYFRAMES := [        # envelope 0->1->0; peak lands ~65% in
	Vector2(0.0, 0.0),
	Vector2(0.65, 1.0),
	Vector2(1.0, 0.0),
]

# 6. Screen shake — cubic decay so it settles quickly even though the peak
# amplitude is bigger now; render-only offset on this Node2D's own position
# (see note above).
const FX_SHAKE_DURATION := 0.14
const FX_SHAKE_PEAK_AMPLITUDE := 4.5   # px

const SCORE_PER_COMBO := 10           # gate score = SCORE_PER_COMBO x combo, before the boost multiplier

# BOOST popup — fires only on a gate that actually earned a boost multiplier.
#
# Pinned beside the character at the moment of the pass — that is where the
# player is already looking, which a screen corner is not. The anchor is
# CAPTURED at the pass rather than tracked live, so the text stays where the
# pass happened instead of riding the character's flapping for half a second.
#
# Because the anchor moves with the character, it can land anywhere in the
# gate zone — including the top-right corner the combo readout owns. So the
# layout checks the two rectangles and pushes this one below the combo block
# when they would collide, rather than assuming they never meet.
# tools/check_popup_overlap.gd drives the real layout function over the whole
# height of the zone and fails on any intersection or off-screen text.
#
# One popup at a time, not a list: a second pass inside 0.45s restarts it.
const BOOST_POP_CHARACTER_OFFSET := Vector2(58.0, 0.0)  # from the character's centre; clears PLAYER_VISUAL_SIZE's 50px half-width
const BOOST_POP_SCREEN_MARGIN := 14.0                   # never let the text reach a screen edge
const BOOST_POP_COMBO_GAP := 10.0                       # clearance kept when pushed below the combo block
const BOOST_POP_DURATION := 0.45               # spec calls for 0.4-0.5s
const BOOST_POP_FONT_SIZE_BEST := 40
const BOOST_POP_FONT_SIZE_MID := 27
const BOOST_POP_RISE := 24.0                   # px, out and back over the popup's life
# Best tier only: the string redrawn on a ring at low alpha, which reads as
# a glow without needing a shader or a second canvas.
const BOOST_POP_GLOW_PASSES := 6
const BOOST_POP_GLOW_RADIUS := 5.0
const BOOST_POP_GLOW_ALPHA := 0.2
const BOOST_POP_BURST_COUNT_BEST := Vector2i(14, 18)
const BOOST_POP_BURST_COUNT_MID := Vector2i(5, 7)
const BOOST_POP_BURST_SIZE_RANGE := Vector2(15.0, 28.0)
const BOOST_POP_BURST_RADIUS := 36.0           # tight ring around the text, not _spawn_spark_burst's gate-sized default
const BOOST_POP_MIN_FONT_SIZE := 13            # floor for the shrink-to-fit; below this the text stops being readable anyway
# _pop_scale's overshoot, hoisted so tools/check_popup_overlap.gd can size
# both popups at their widest without duplicating the number.
const POP_PEAK_SCALE := 1.22

# 9. Audio hooks — each its own AudioStreamPlayer so they can overlap.
# Whoosh is still an unfilled placeholder (drop a file at that path and it
# starts playing automatically, ResourceLoader.exists guarded). Chime plays
# on every correct gate pass (see _play_gate_success_fx); flap plays once
# per tap (see _unhandled_input).
const FX_SOUND_WHOOSH_PATH := "res://assets/audio/gate_whoosh.ogg"
const FX_SOUND_CHIME_PATH := "res://assets/audio/gate_chime.wav"
# 탭 소리는 모드마다 다르다. 확장자 없이 적고 _resolve_audio가 .ogg -> .wav
# 순으로 찾는다. 정글은 예전부터 쓰던 파일을 그대로 쓴다. 파일이 없는 모드는
# FX_SOUND_FLAP_FALLBACK으로 되돌아가므로 하나씩 채워 넣어도 된다.
const MODE_FLAP_SOUND_NAME := [
	"sky_flap",     # SKY
	"bird_flap",    # JUNGLE — 기존 소리 유지
	"ocean_flap",   # OCEAN
	"unicorn_flap", # DREAM — 캐릭터 이름을 딴 파일명
]
const FX_SOUND_FLAP_FALLBACK := "res://assets/audio/bird_flap.wav"
# Background music — starts once in _ready() and loops for the whole
# session (menu, playing, game over all keep it going, same as the
# parallax background), independent of the FX players above. Respects the
# existing mute button since AudioStreamPlayer defaults to the Master bus,
# same as every other sound here.
const BGM_DIR := "res://assets/audio/"
# Music is named without an extension here and resolved at load time, .ogg
# first. OGG is the intended shipping format — these tracks run 10-14 MB
# each as WAV and roughly a tenth of that as OGG, which is the difference
# between a sane and an absurd mobile build once all five exist — but the
# fallback means an un-converted .wav still plays, and dropping the .ogg
# beside it switches over with no code change.
const BGM_EXTENSIONS := [".ogg", ".wav"]
# The splash and mode-picker screens share one track; a run switches to the
# chosen mode's. Per-mode entries are indexed by Mode, same convention as
# MODE_CHARACTER_DIR/MODE_GATE_DIR — all four point at the one existing
# game track for now, so adding a per-mode file later is one line each.
const BGM_MENU_NAME := "splash_main_bgm"
# 모드마다 자기 곡. 확장자 없이 적고 불러올 때 .ogg -> .wav 순으로 찾는다
# (BGM_EXTENSIONS). 파일이 아직 없으면 _bgm_path_for_state가 메뉴 곡으로
# 되돌아가므로, 이름을 미리 적어 둬도 안전하다 — 파일만 넣으면 바뀐다.
const MODE_BGM_NAME := [
	"sky_bgm",     # SKY
	"jungle_bgm",  # JUNGLE
	"ocean_bgm",   # OCEAN
	"dream_bgm",   # DREAM
]
# Swapping tracks hard-cuts audibly, so the outgoing player fades down while
# the incoming one fades up over this long. Two players exist purely to make
# that overlap possible.
const BGM_CROSSFADE_TIME := 0.4
const BGM_SILENT_DB := -40.0
# Countdown beat sounds — one played the instant the READY image appears,
# the other the instant it swaps to START (see _start_countdown and
# _update_countdown).
const COUNTDOWN_READY_SOUND_PATH := "res://assets/audio/countdown_ready.mp3"
const COUNTDOWN_START_SOUND_PATH := "res://assets/audio/countdown_start.mp3"
# Failure sound — wrong gate, wall collision, or falling off the bottom of
# the screen all funnel through the single _game_over() below, so this is
# the one place it needs to be wired. BGM is stopped (not just paused) at
# the same time — see _game_over — pending a separate failure-BGM track
# later; _start_countdown resumes the music for the next run.
const FX_SOUND_GAMEOVER_PATH := "res://assets/audio/gameover.wav"

# Tapping the title screen to enter the mode picker. Every other sound here
# belongs to a run; this one is the first thing the game ever plays, so it
# doubles as the "audio is working" confirmation. Optional like the rest —
# a missing file just means the transition stays silent.
const FX_SOUND_SPLASH_START_PATH := "res://assets/audio/splash_start.wav"

# 부스트 버튼을 누르고 있는 동안 계속 나는 소리. 다른 효과음과 달리 한 번
# 울리고 끝나는 게 아니라 홀드와 길이를 같이 한다 — 누를 때 play, 뗄 때 stop.
#
# 그래서 이 하나만 루프를 켠다(_enable_stream_loop). 파일은 2.25초라 그보다
# 오래 누르면 그냥 끊기기 때문이다. 홀드가 풀리는 길은 손을 떼는 것 말고도
# 죽거나 일시정지해서 버튼이 숨는 경우가 있는데, 숨겨진 Button 은 button_up 을
# 쏘지 않으므로 그쪽은 _process 에서 boost_button_held 와 함께 꺼 준다.
const FX_SOUND_BOOST_PATH := "res://assets/audio/boost.wav"


# ---- Phase curve, shared by all three modes ----
# Difficulty is keyed on how many gates the run has PASSED, and the phase
# each mode is in drives its own quiz generation (see _get_phase_index and
# its callers: flag tiers, math operation mix, Stroop hue band + decoy mix).
# One curve for all three on purpose — the modes are meant to be compared
# against each other, which only works if they ramp on the same schedule.
#
# This array is the LENGTH of each phase in gates, not the boundaries: the
# last phase runs forever, so it has no length and no entry here. Three
# entries = four phases. _phase_gate_thresholds() accumulates them.
#   [10, 20, 30] -> phase 1 = gates 1-10, phase 2 = 11-30,
#                   phase 3 = 31-60, phase 4 = 61 onward, to the death.
# How many times a mode re-rolls a question that repeats the previous gate's
# (see last_quiz_key). Capped rather than looped until distinct: the late
# phases draw from deliberately small pools, so "always different" is not
# always available, and a repeat is far better than a hang.
const QUIZ_REPEAT_RETRIES := 8

## Length in gates of each phase except the last, which runs unbounded.
## Shared by all three modes — this is the single place the ramp is set.
## Editable live while playing; every new gate re-reads it.
@export var phase_gate_counts: PackedInt32Array = PackedInt32Array([10, 20, 30])


# ============================================================
# JUNGLE mode's math quiz. Six problem shapes, mixed per phase rather than
# assigned outright, so a phase reads as a shifting blend instead of a hard
# switch — an easy shape stays possible late, and a hard one shows up early
# just often enough to warn you it is coming.
#
# Division and two-digit x two-digit are deliberately absent: not modelled at
# all, so no weight can bring them back.
# ============================================================
enum MathKind {
	SINGLE_ADD_SUB,       # 한자리 덧셈/뺄셈 — sum/difference stays within math_single_max_result
	DOUBLE_ADD_SUB_PLAIN, # 두자리 덧셈/뺄셈, 자리올림/빌림 없음
	TIMES_TABLE,          # 구구단 (한자리 x 한자리)
	DOUBLE_ADD_SUB_CARRY, # 두자리 덧셈/뺄셈, 자리올림/빌림 있음
	DOUBLE_X_SINGLE,      # 두자리 x 한자리
	MISSING_OPERAND,      # 빈칸추론 — 7 + ? = 15
}

# Per-phase weights, one array per problem shape, indexed by phase. Laid out
# by shape rather than by phase so the Inspector shows each shape's whole
# curve on one line: read a row to see when a shape appears, read a column to
# see a phase's mix. Relative weights, not percentages.
# ============================================================
# SKY mode's flag quiz. Two independent axes, on purpose:
#   recognition_tier     — how well known the flag is. Picks the ANSWER, and
#                          is the only thing the phase curve touches.
#   confusion_cluster_id — what the flag LOOKS like. Picks the DECOY, and
#                          ignores the phase and the tier entirely.
# Keeping them apart is what makes the decoy honest: pick it by fame and the
# odd one out is obvious without looking at either flag.
# ============================================================
@export_group("Flag quiz weights (by phase)")
## Tier 1 — 누구나 아는 국기 (48개국)
@export var flag_weight_tier1: PackedFloat32Array = PackedFloat32Array([90, 30, 0, 0])
## Tier 2 — 대체로 아는 국기 (54개국)
@export var flag_weight_tier2: PackedFloat32Array = PackedFloat32Array([10, 60, 30, 0])
## Tier 3 — 들어는 본 국기 (54개국)
@export var flag_weight_tier3: PackedFloat32Array = PackedFloat32Array([0, 10, 60, 30])
## Tier 4 — 낯선 국기 (37개국)
@export var flag_weight_tier4: PackedFloat32Array = PackedFloat32Array([0, 0, 10, 70])

@export_group("Math quiz weights (by phase)")
## 한자리 덧셈/뺄셈
@export var math_weight_single_add_sub: PackedFloat32Array = PackedFloat32Array([90, 10, 0, 0])
## 두자리 덧셈/뺄셈 (자리올림 없음)
@export var math_weight_double_plain: PackedFloat32Array = PackedFloat32Array([10, 70, 0, 0])
## 구구단
@export var math_weight_times_table: PackedFloat32Array = PackedFloat32Array([0, 20, 40, 20])
## 두자리 덧셈/뺄셈 (자리올림 있음)
@export var math_weight_double_carry: PackedFloat32Array = PackedFloat32Array([0, 0, 40, 0])
## 두자리 x 한자리 곱셈
@export var math_weight_double_x_single: PackedFloat32Array = PackedFloat32Array([0, 0, 20, 40])
## 빈칸추론 (7 + ? = 15)
@export var math_weight_missing_operand: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 40])

@export_group("Math quiz number ranges")
## 한자리 덧셈/뺄셈의 합·차 상한
@export var math_single_max_result: int = 10
## 두자리 피연산자 범위
@export var math_double_range: Vector2i = Vector2i(10, 99)
## 구구단 단 범위
@export var math_times_table_range: Vector2i = Vector2i(2, 9)
## 두자리 x 한자리에서 한자리 쪽 범위
@export var math_single_factor_range: Vector2i = Vector2i(2, 9)
@export_group("")


# ============================================================
# OCEAN mode's Stroop colour quiz. Self-contained: nothing below is read by
# SKY's flag quiz or JUNGLE's math quiz, and it reads nothing of theirs.
# See the OceanDecoy enum at the top of the file for the wrong-gate traps.
#
# The whole point of the quiz is the conflict between what a word SAYS and
# what it LOOKS like, so two rules hold for every item this generates:
#   1. The word and the answer colour are never the same colour — there is
#      always a trap (no congruent items at all).
#   2. The two gate options are the answer's name and the WORD's own name,
#      the word being the strongest possible decoy: reading the question
#      instead of looking at it lands you on the wrong gate every time.
# ============================================================
const OCEAN_COLOR_NAMES := [
	"RED", "BLUE", "GREEN", "YELLOW", "ORANGE",
	"PURPLE", "PINK", "BROWN", "BLACK", "WHITE", "GRAY",
]
# HSL hue in degrees for each name above, used only for the phase difficulty
# curve (see OCEAN_PHASE_HUE_BAND / _ocean_color_distance). BLACK/WHITE/GRAY
# are achromatic — hue is undefined for them, so they carry OCEAN_HUE_NONE
# and the distance function falls back to their lightness instead.
const OCEAN_HUE_NONE := -1.0
const OCEAN_COLOR_HUES := [
	0.0, 220.0, 130.0, 52.0, 28.0,
	280.0, 335.0, 22.0, OCEAN_HUE_NONE, OCEAN_HUE_NONE, OCEAN_HUE_NONE,
]
# HSL lightness, same order. Only consulted for the three neutrals, where it
# is the only axis they differ on; kept for all 11 so the table stays whole.
const OCEAN_COLOR_LIGHTNESS := [
	0.50, 0.50, 0.40, 0.52, 0.52,
	0.50, 0.68, 0.35, 0.08, 0.97, 0.55,
]
# What actually gets painted, same order — the HSL triples above converted to
# RGB once, by hand, so the on-screen colour is art-directable independently
# of the numbers driving the difficulty maths.
const OCEAN_COLOR_RGB := [
	Color(0.90, 0.13, 0.13),  # RED
	Color(0.10, 0.43, 0.90),  # BLUE
	Color(0.10, 0.62, 0.25),  # GREEN
	Color(0.97, 0.85, 0.05),  # YELLOW
	Color(0.97, 0.51, 0.05),  # ORANGE
	Color(0.60, 0.20, 0.80),  # PURPLE
	Color(0.95, 0.45, 0.68),  # PINK
	Color(0.54, 0.32, 0.16),  # BROWN
	Color(0.08, 0.08, 0.09),  # BLACK
	Color(0.98, 0.98, 0.98),  # WHITE
	Color(0.55, 0.55, 0.56),  # GRAY
]
const OCEAN_HUE_DISTANCE_MAX := 180.0  # hue is a circle, so this is as far apart as two hues get

# Difficulty curve, indexed by phase (see _get_phase_index). Each entry is
# the [min, max] hue distance allowed between the WORD's own colour and the
# ANSWER colour, so the two get harder to keep apart as the run goes on:
# phase 1 is "RED" in blue (impossible to confuse), phase 4 is "RED" in
# orange (you have to actually look). If a phase's band happens to have no
# legal pair, _make_color_problem falls back to the closest pairs instead of
# failing — so these can be retuned freely without breaking generation.
const OCEAN_PHASE_HUE_BAND := [
	Vector2(150.0, 180.0),  # phase 1 — far apart, easy
	Vector2(95.0, 150.0),   # phase 2
	Vector2(55.0, 95.0),    # phase 3
	Vector2(0.0, 40.0),     # phase 4 — near-neighbour hues, hard
]

# Question box wording. A question about the COLOUR, never about the word,
# which is the one thing the player has to keep straight.
const OCEAN_PROMPT_INK := "Q. What COLOR is this word?"

# Question box layout. The prompt is static and read once; the stimulus is
# what gets re-read every single gate, so the prompt is deliberately the
# smaller of the two and the pair is centred in the writing area as a group.
const OCEAN_PROMPT_SIZE_RATIO := 0.46      # prompt font size, as a fraction of the stimulus's
const OCEAN_PROMPT_GAP_FRAC := 0.022       # of box width — prompt -> stimulus gap
const OCEAN_STIMULUS_MIN_FONT_FRAC := 0.034  # of box width — floor when the pair has to shrink to fit
const OCEAN_PROMPT_MIN_FONT := 9
# The word is painted straight onto the cream quiz-box art, where a yellow or
# white word would otherwise vanish. Every word gets the same dark outline —
# uniformly, so the outline is never itself a hint.
const OCEAN_INK_OUTLINE_PX := 2.0
const OCEAN_INK_OUTLINE_COLOR := Color(0.09, 0.12, 0.18, 0.95)

# Gate options. The names are up to six letters on a card built for a flag,
# so they take more of its width than JUNGLE's digits do — raise
# GATE_FLAG_ICON_WIDTH if they ever want to be bigger, since that (not this)
# is what caps them. See _ocean_gate_font_size.
const OCEAN_GATE_FIT_WIDTH_FRAC := 0.92
const OCEAN_GATE_MIN_FONT := 10

# Next zone's center is clamped to what's physically reachable from the
# previous zone's center within the spawn-to-judgement travel window, using
# each direction's real max speed (climbing is slower than falling). This
# factor shaves a margin off the theoretical max so it's not a frame-perfect
# reaction-time requirement.
const REACH_SAFETY_FACTOR := 0.85

# Flag Explorer answer database — all 193 UN member states, each record
# {code, name, image} built by tools/validate_flags_data.ps1's companion
# pipeline (see assets/flags/flags_data.json). Loaded once in _ready() into
# flag_records (Array of Dictionaries) + flag_textures (code -> Texture2D),
# and picked from directly in _spawn_gate — replaces the old QUIZ_PAIRS
# dummy country-name list entirely.
const FLAGS_DATA_PATH := "res://assets/flags/flags_data.json"

# SPLASH is the boot screen (title art + "Tap to START"); it hands off to
# MODE_SELECT on the first tap. Appended rather than placed first so the
# existing states keep their values.
# LOGO 는 그보다도 앞, 부팅 직후의 제작사 화면이다. 값이 밀리지 않게 뒤에 붙인다.
enum State { MODE_SELECT, READY, COUNTDOWN, PLAYING, GAMEOVER, SPLASH, LOGO }

# ============================================================
# 로고 화면 — 부팅 직후, 스플래시보다 먼저. 검은 바탕에 로고와 크레딧만
# 띄우고 페이드 인/유지/페이드 아웃 뒤 스스로 스플래시로 넘어간다.
# 아무 데나 누르면 바로 페이드 아웃으로 건너뛴다. 음악은 아직 틀지 않는다 —
# 스플래시로 넘어갈 때 시작해야 로고가 조용히 뜬다.
# ============================================================
const LOGO_TEXTURE_PATH := "res://assets/ui_assets/title/logo.png"
const LOGO_BACKGROUND := Color(0.0, 0.0, 0.0, 1.0)
const LOGO_FADE_IN := 0.45
const LOGO_HOLD := 1.5
const LOGO_FADE_OUT := 0.45
const LOGO_WIDTH_FRAC := 0.78        # of view width
# 로고와 글자를 한 덩어리로 묶어 화면 가운데에 놓는다.
const LOGO_BLOCK_CENTER_FRAC := 0.46  # of view height
const LOGO_TO_BETA_GAP_FRAC := 0.055  # of view height
const LOGO_BETA_TO_CREDIT_GAP_FRAC := 0.040
const LOGO_CREDIT_LINE_GAP_FRAC := 0.028
const LOGO_BETA_TEXT := "BETA VERSION"
const LOGO_BETA_FONT_FRAC := 0.026    # of view height
const LOGO_BETA_COLOR := Color(1.0, 0.84, 0.32, 1.0)
const LOGO_CREDIT_FONT_FRAC := 0.019
const LOGO_CREDIT_ROLE_COLOR := Color(0.62, 0.66, 0.74, 1.0)
const LOGO_CREDIT_NAME_COLOR := Color(0.92, 0.94, 0.98, 1.0)
const LOGO_CREDIT_DOT := "·"
# 역할 칸을 가장 긴 역할에 맞춰 잡고 그 뒤에 점과 이름을 놓으므로, 글꼴이
# 바뀌어도 두 줄의 점이 세로로 맞는다.
const LOGO_CREDIT_GAP_FRAC := 0.030   # of view width — 역할|점|이름 사이 간격
const LOGO_CREDITS := [
	["Game Design & Development", "Kim Min Cheol"],
	["Art & Design", "Kang Sol Ji"],
]

# ============================================================
# Splash / title screen — the first thing shown on boot, before the mode
# picker. Just the painted title art plus a prompt; a tap anywhere moves on.
# ============================================================
const SPLASH_TEXTURE_PATH := "res://assets/ui_assets/title/splash_v3.png"
# The title is its own piece of art now. The v3 painting is a plain sky, so
# the wordmark can be moved, resized or replaced without repainting the
# background — and it is the same file the mode picker uses, so the two
# screens can never drift apart.
const SPLASH_TITLE_PATH := "res://assets/ui_assets/main/title_main_v2.png"
# Matched to how wide the row of three characters below it reads, so the
# title and the characters share one column rather than sitting at two
# unrelated widths.
const SPLASH_TITLE_WIDTH_FRAC := 0.84   # of view width
const SPLASH_TITLE_MID_Y_FRAC := 0.30   # of view height — centre of the art
# The art is a taller aspect than the viewport, so it is scaled to COVER and
# centred — the overflow is cropped rather than letterboxed. The title and
# the three characters sit in the upper-middle of the painting, so an even
# centre crop keeps them all and only trims sky and sea-floor.
const SPLASH_PROMPT_TEXT := "Tap to START"
const SPLASH_PROMPT_BOTTOM_FRAC := 0.135   # of view height — distance from the bottom edge to the prompt's centre
const SPLASH_PROMPT_FONT_SCALE := 0.055    # of view height
const SPLASH_PROMPT_PULSE_PERIOD := 1.2    # seconds per breath cycle
# Alpha, scale and glow all ride the SAME pulse, in phase: three separate
# rhythms would read as clutter, one shared rhythm reads as breathing. The
# alpha floor is kept high enough that the swell is what draws the eye
# rather than the text vanishing and returning.
const SPLASH_PROMPT_ALPHA_RANGE := Vector2(0.72, 1.0)
const SPLASH_PROMPT_SCALE_RANGE := Vector2(1.0, 1.05)
# Faked bloom: the same string redrawn in rings around itself, each ring
# fainter than the last. draw_string has no blur, and a real shader would be
# a lot of machinery for one line of text on one screen.
const SPLASH_PROMPT_GLOW_COLOR := Color(1.0, 0.84, 0.32)  # gold
const SPLASH_PROMPT_GLOW_RADII := [3.0, 7.0, 12.0]        # px, at scale 1.0
const SPLASH_PROMPT_GLOW_STEPS := 8                       # samples per ring
const SPLASH_PROMPT_GLOW_ALPHA := 0.14                    # per sample at full pulse — kept low on purpose
const SPLASH_PROMPT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SPLASH_PROMPT_OUTLINE := Color(0.09, 0.16, 0.33, 1.0)  # deep navy, matching the title art's own outline
# Tap feedback: the prompt swells and fades out, and the handover to the
# mode picker waits for it. Without the wait the title would simply cut
# away and the effect would never be seen. Scaling is done with a draw
# transform rather than by growing the font size, which would re-rasterise
# the glyphs every frame and shimmer.
const SPLASH_EXIT_DURATION := 0.32
const SPLASH_EXIT_SCALE := 1.55
# The three playable characters fly under the title, using the same sheets
# and frame rate the game itself runs them at rather than a painted copy.
# Order is left to right on screen, so JUNGLE's dragon lands in the middle.
const SPLASH_CHARACTER_MODES := [Mode.SKY, Mode.JUNGLE, Mode.OCEAN]
const SPLASH_CHARACTER_MID_Y_FRAC := 0.600   # of view height — below the title, clear of the prompt
const SPLASH_CHARACTER_SIZE_FRAC := 0.260    # of view width, per character
const SPLASH_CHARACTER_SPACING_FRAC := 0.300 # of view width, centre to centre
# Each drifts on its own phase, so the three never rise and fall as a block.
# Amplitude is a fraction of the drawn size, so it tracks the size above.
const SPLASH_BOB_AMPLITUDE_FRAC := 0.06
const SPLASH_BOB_PERIOD := 2.1
const SPLASH_BOB_PHASE := [0.0, 0.7, 1.35]   # seconds of lead per character

var state: int = State.READY

# Tap-to-pause (PLAYING only — see pause_button visibility in _process).
# Only gates the gameplay-affecting update calls in _process; background
# parallax keeps drifting while paused, same as it does on every other
# non-PLAYING screen.
var paused: bool = false
# 한 판에 부활 제안은 한 번만. 이어간 뒤 또 죽으면 그때는 바로 게임오버다.
var revive_offered: bool = false

# "READY" -> "START" pop-in shown before every *retry* (post-onboarding).
# The very first play (from the READY/onboarding panel) skips straight to
# PLAYING and never touches this — see _on_play_pressed vs _on_restart_pressed.
enum CountdownPhase { READY_TEXT, START_TEXT }
var countdown_phase: int = CountdownPhase.READY_TEXT
var countdown_timer: float = 0.0
const COUNTDOWN_READY_DURATION := 0.9
const COUNTDOWN_START_DURATION := 0.4

# "READY" / "START" countdown pop art, cut from one hand-authored sheet
# (assets/ui_assets/ready_start_sheet_v3.png) by tools/slice_ready_sheet_v3.gd,
# and the "TRY AGAIN" game-over word, still from the v2 sheet. Ready/Start are
# drawn in place of the old plain-text draw_string call (see the State.COUNTDOWN
# block in _draw()) and fall back to that text if a file is missing; TRY AGAIN
# is a TextureRect in the game-over panel, replacing what used to be a red
# "GAME OVER" label.
#
# 여덟 장(4모드 x READY/START)이 한 캔버스를 같이 쓰고, 그 위에서 글자의 중심이
# 한 점에 모이도록 배치되어 있다 — 모드마다 장식(날개, 잎, 산호)이 튀어나온
# 정도가 달라서 그림 전체를 가운데 맞추면 정작 글자가 제각각 다른 자리에 뜨기
# 때문이다. 캔버스가 하나이므로 여기에는 모드별 보정값이 필요 없다.
const MODE_READY_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/Ready_v3.png",
	"res://assets/ui_assets/jungle/Ready_v3.png",
	"res://assets/ui_assets/ocean/Ready_v3.png",
	"res://assets/ui_assets/dream/Ready_v3.png",
]
const MODE_START_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/Start_v3.png",
	"res://assets/ui_assets/jungle/Start_v3.png",
	"res://assets/ui_assets/ocean/Start_v3.png",
	"res://assets/ui_assets/dream/Start_v3.png",
]
const MODE_TRY_AGAIN_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/TryAgain.png",
	"res://assets/ui_assets/jungle/TryAgain.png",
	"res://assets/ui_assets/ocean/TryAgain.png",
	"res://assets/ui_assets/sky/TryAgain.png",  # DREAM — placeholder, reusing SKY art
]
# 화면에 그릴 가로 폭(px). 높이는 원본 비율을 따른다. START 를 READY 보다
# 크게 잡아 "준비 -> 출발"이 커지면서 이어지게 한다. 캔버스 664px 중 배너가
# 636px 이므로, 화면 폭 480 을 넘지 않으려면 START 는 pop 최고점까지 쳐서
# 480 * 664 / 636 = 501 이하여야 한다.
const COUNTDOWN_READY_WIDTH := 360.0
const COUNTDOWN_START_WIDTH := 400.0
# 배너 아트는 픽셀아트 풍이라 테두리가 원본에서부터 계단으로 꺾이기 쉽다.
# 시트 캔버스를 그대로 GPU 밉맵에 맡겨 줄이면 그 계단이 그대로 남으므로,
# 미리 Lanczos 로 구워 풀어 준다. 굽는 폭은 그릴 폭의 이 배수 —
# 1.0 이면 가장 부드럽지만 고해상도 기기에서 다시 확대돼 뭉개지고, 1.2 면
# 계단은 충분히 사라지면서 여유도 남는다.
const COUNTDOWN_ART_OVERSAMPLE := 1.2

# Top HUD art: score box (top-center, drawn — no interaction needed), quiz
# box (directly under it, also drawn), pause (top-left) and mute (top-right)
# as real Buttons. All four come out of one hand-authored sheet,
# assets/ui_assets/hud_sheet_v5.png, cut by tools/slice_hud_sheet_v5.gd.
#
# The slicer is what makes the three modes interchangeable here: rather than
# cropping each mode to its own tight bounding box (which lands the writing
# area somewhere different in every mode, because the frames differ in
# thickness and the decorations — wings, leaves, coral — stick out by
# different amounts), it gives every column ONE canvas size shared across the
# modes and positions each mode's art on it so the cream writing boxes land
# on the same pixel. Pause and mute additionally share a canvas with each
# other, so both buttons are the same size on screen.
#
# The practical payoff: the *_FRAC constants below are single values, not the
# per-mode arrays this used to need, and the score number and quiz text now
# land in exactly the same place at exactly the same size in all three modes.
# Re-run the slicer if the sheet is ever redrawn; it prints the fractions.
const MODE_PAUSE_ICON_PATH := [
	"res://assets/ui_assets/sky/pause_v3.png",
	"res://assets/ui_assets/jungle/pause_v3.png",
	"res://assets/ui_assets/ocean/pause_v3.png",
	"res://assets/ui_assets/dream/pause_v3.png",
]
const MODE_MUTE_ICON_PATH := [
	"res://assets/ui_assets/sky/mute_v3.png",
	"res://assets/ui_assets/jungle/mute_v3.png",
	"res://assets/ui_assets/ocean/mute_v3.png",
	"res://assets/ui_assets/dream/mute_v3.png",
]
# 스코어 박스는 게이트 위 보기답 패널과 같은 아트를 9-slice로 늘려 쓴다.
# 예전 아트에는 "SCORE"·"BEST"·왕관·구분선이 그려져 있었지만 이 패널은
# 빈 상자라, 그 넷을 아래 _draw_hud_bar가 직접 그린다.
const MODE_SCORE_BOX_PATH := [
	"res://assets/gates/flag_panel/panel_sky.png",
	"res://assets/gates/flag_panel/panel_jungle.png",
	"res://assets/gates/flag_panel/panel_ocean.png",
	"res://assets/gates/flag_panel/panel_dream.png",
]
# 퀴즈 박스는 모드마다 자기 아트를 쓴다(hud_quizbox.png에서 잘라 냄). 양 끝에
# 보석 장식이 박혀 있어 9-slice로 늘리면 그 장식이 늘어나므로, 통째로 그려
# 아트 비율을 그대로 지킨다.
const MODE_QUIZ_BOX_PATH := [
	"res://assets/ui_assets/sky/quiz_box_v3.png",
	"res://assets/ui_assets/jungle/quiz_box_v3.png",
	"res://assets/ui_assets/ocean/quiz_box_v3.png",
	"res://assets/ui_assets/dream/quiz_box_v3.png",
]
const HUD_CANVAS_SCRIPT_PATH := "res://scripts/HudCanvas.gd"
# 점수 숫자의 속만 칠하는 캔버스에 씌우는 셰이더. draw_string 은 한 가지
# 색밖에 못 받으므로, 글리프의 알파는 그대로 두고 RGB 만 세로 위치에 따라
# 섞는다. y_top/y_bottom 은 숫자 잉크의 위/아래 끝(캔버스 좌표)이다.
const SCORE_FILL_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(1.0);
uniform vec4 bottom_color : source_color = vec4(1.0);
uniform float y_top = 0.0;
uniform float y_bottom = 1.0;
varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp((local_pos.y - y_top) / max(y_bottom - y_top, 0.001), 0.0, 1.0);
	vec4 g = mix(top_color, bottom_color, t);
	COLOR.rgb = g.rgb;
	COLOR.a *= g.a;
}
"""
# Best score persistence. user:// is the per-user writable location Godot
# maps outside the project (%APPDATA%/Godot/app_userdata/<project> on
# Windows), so this survives reinstalls of the game files themselves.
# One best across all three modes, matching the single BEST slot the art has.
const SAVE_PATH := "user://savegame.cfg"
const SAVE_SECTION := "progress"
# 모드마다 기록을 따로 둔다. 키는 "best_score_<모드번호>".
const SAVE_KEY_BEST_PREFIX := "best_score_"
# 모드 구분 없이 하나만 쓰던 시절의 키. 불러올 때 한 번 옮겨 오고 그 뒤로는
# 쓰지 않는다.
const SAVE_KEY_BEST_LEGACY := "best_score"
# 순위표에 올릴 기록. 개인 최고 기록과 따로 둔다 — 아래 leaderboard_score 참고.
const SAVE_KEY_LEADERBOARD_PREFIX := "leaderboard_best_"
const SAVE_SECTION_AUDIO := "audio"
const SAVE_KEY_SFX := "sfx_volume"
const SAVE_KEY_MUSIC := "music_volume"

# ---- 오디오 버스 ----
# 효과음과 음악을 따로 줄이려면 각자의 버스가 있어야 한다. 프로젝트에는
# Master 하나뿐이라 실행할 때 만들어 붙인다 — .tres 레이아웃 파일을 두는
# 것보다 이쪽이 눈에 보이고, 버스가 이미 있으면 건너뛰므로 안전하다.
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"
# 슬라이더 0~1을 데시벨로 옮길 때 쓰는 하한. 0에 닿으면 -inf가 되어 버려서,
# 완전히 끈 상태는 볼륨이 아니라 mute로 따로 처리한다.
const VOLUME_MIN_DB := -32.0
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.8
@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.7
# The score box art is split by a painted divider into a SCORE half and a
# BEST half, each carrying a painted label with blank writing space beside it.
# All fractions are of the box's *display* size, so they hold at whatever the
# row scale works out to.
#
# The two numbers are deliberately NOT the same size or on the same line: each
# is matched to the label it belongs to, so the pair reads as "SCORE <big>"
# and "BEST <small>" the way the art draws them. The values below come from
# measuring the painted lettering in the sliced PNGs — all three modes agreed
# to within a pixel, which is why one set covers them all:
#
#   label   ink height   vertical centre   right edge
#   SCORE   0.286        0.548             0.2625
#   BEST    0.242        0.696             0.6734
#
# Font size converts from ink height: Fredoka's digits occupy 0.72 em (0.700
# above the baseline, 0.020 below — see DIGIT_BASELINE_FROM_CENTER_FRAC), so
# font = ink_height / 0.72.
# 빈 패널 위에 직접 그리는 것들.
#
# 왼쪽 칸은 "SCORE" 글자 + 점수, 오른쪽 칸은 왕관 + 최고 점수다. 오른쪽에는
# "BEST"라고 쓰지 않는다 — 왕관이 그 뜻을 대신한다.
const SCORE_LABEL_TEXT := "SCORE"
const SCORE_LABEL_FONT_FRAC := 0.485     # 박스 높이 대비
const SCORE_LABEL_LEFT_FRAC := 0.0428     # 박스 너비 대비 — 왼쪽 여백
# 박스를 걷어 내고 배경 위에 바로 얹으므로, 글자는 스스로 읽히게 꾸민다.
# 바깥부터 음영 -> 검은 테두리 -> 속 순서로 겹쳐 그린다.
const SCORE_LABEL_FILL := Color(1.0, 1.0, 1.0, 1.0)
const SCORE_TEXT_OUTLINE := Color(0.06, 0.06, 0.09, 1.0)
# 음영은 여덟 방향으로 겹쳐 그려 만든다. 겹치는 만큼 진해지므로 한 겹은
# 아주 옅게 둔다 — 글자 아래로 삐져나온 부분만 보이면 된다.
const SCORE_TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.11)
# 테두리 두께와 음영 거리는 글꼴 크기에 비례한다. 고정 px 로 두면 작은
# 글자("BEST")에서 테두리가 글자 사이를 메워 검은 덩어리로 보인다.
const TEXT_OUTLINE_FONT_FRAC := 0.068
const TEXT_SHADOW_FONT_FRAC := 0.092
# 점수 숫자 속색 — 위는 밝게, 아래는 어둡게. 세로 그라데이션은 평범한
# draw_string 으로는 안 되므로 전용 캔버스 + 셰이더로 칠한다
# (score_fill_canvas / SCORE_FILL_SHADER).
const SCORE_NUMBER_TOP := Color(1.00, 0.95, 0.55, 1.0)
const SCORE_NUMBER_BOTTOM := Color(0.92, 0.55, 0.04, 1.0)
# 최고 점수는 하늘색. 위아래 차이는 점수보다 얕게 둔다.
const BEST_NUMBER_TOP := Color(0.88, 0.98, 1.00, 1.0)
const BEST_NUMBER_BOTTOM := Color(0.44, 0.75, 0.96, 1.0)
# 테두리/음영을 한 번에 두르려고 여덟 방향으로 겹쳐 그린다.
const TEXT_OUTLINE_RING: Array[Vector2] = [
	Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
	Vector2(-1, 0), Vector2(1, 0),
	Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1),
]
const SCORE_DIVIDER_COLOR := Color(0.55, 0.47, 0.36, 0.55)
const SCORE_DIVIDER_WIDTH := 2.0
const SCORE_DIVIDER_INSET_FRAC := 0.20   # 박스 높이 대비 위아래 여백
const BEST_CROWN_PATH := "res://assets/ui_assets/popup/icon_crown.png"
const BEST_CROWN_LEFT_FRAC := 0.016      # 구분선에서 왕관까지(박스 너비 대비)
const BEST_CROWN_HEIGHT_FRAC := 0.40     # 박스 높이 대비
# 오른쪽 칸은 왕관 + "BEST" + 최고 점수 셋이 한 줄에 들어간다. 칸 폭이
# 정해져 있으니 셋 다 그 안에 맞도록 줄여 잡은 값들이다.
const BEST_LABEL_TEXT := "BEST"
const BEST_LABEL_FONT_FRAC := 0.30       # 박스 높이 대비
const BEST_LABEL_FILL := Color(0.99, 0.80, 0.22, 1.0)   # 노란색
const BEST_LABEL_GAP_FRAC := 0.011       # 박스 너비 대비 — 왕관과 "BEST" 사이
# 왕관은 숫자 가운데선보다 살짝 위로. 왕관 그림은 아래쪽 받침이 무거워서
# 가운데를 맞추면 내려앉아 보인다.
const BEST_CROWN_Y_OFFSET_FRAC := -0.055 # 박스 높이 대비
# 최고 점수는 오른쪽 끝자리를 박스 오른쪽 테두리 가까이에 붙여 오른쪽 정렬한다.
const BEST_NUMBER_RIGHT_INSET_FRAC := 0.0377   # 박스 너비 대비
# 스코어 박스 테두리는 일시정지/음소거 버튼과 비슷한 두께로. 패널 아트를
# 9-slice로 그릴 때의 배수이고, 게이트 위 보기답 패널과는 따로 둔다.
const SCORE_PANEL_SCALE := 0.877
# 버튼 사이를 꽉 채우지 않고 살짝 줄여 그린다 — 버튼과의 간격이 그만큼 넓어진다.
const SCORE_BOX_WIDTH_TRIM := 0.96
# 패널 그림을 깔지 않고 글자만 배경 위에 얹는다. 자리와 크기는 그대로
# _score_box_rect 에서 나오므로, 다시 켜면 예전 모습으로 돌아온다.
const SCORE_BOX_PANEL_VISIBLE := false
# panel_*.png 는 가장자리에 투명 여백이 2px 있다(잉크 y 2..50 of 53). 9-slice
# 모서리 조각째로 그려지니 화면에서도 SCORE_PANEL_SCALE 배만큼 안쪽으로
# 밀려 들어가, 같은 rect 를 줘도 버튼보다 4px 작아 보였다. 그만큼 넓혀서
# 그린다 — rect 는 "칠해진 테두리가 놓일 자리"라는 뜻을 유지한다.
const SCORE_PANEL_ART_PAD := 2.0
# 구분선 위치 = 왼쪽 칸(SCORE)과 오른쪽 칸(최고 점수)의 비율 3:2.
const SCORE_NUM_RIGHT_FRAC := 0.55        # of width
const SCORE_NUMBER_FONT_FRAC := 0.52      # of height
# 두 칸의 내용이 한 줄에 놓인다. 예전 값(0.548 / 0.696)은 아트에 그려져
# 있던 SCORE/BEST 두 줄에 맞춘 것이라, 빈 패널에서는 어긋나 보인다.
const SCORE_NUMBER_MID_Y_FRAC := 0.50     # of height
# 최고 점수도 점수와 같은 크기, 같은 줄. 예전 값(0.336 / 0.696)은 아트에
# 그려져 있던 BEST 줄에 맞춘 것이었다.
const BEST_NUMBER_FONT_FRAC := 0.34       # of height
const BEST_NUMBER_MID_Y_FRAC := 0.50      # of height
const SCORE_NUMBER_RIGHT_INSET_FRAC := 0.024  # of box width — keeps the ones digit off the divider
const SCORE_NUMBER_DIGIT_SPACING := 1.7     # extra px between digit cells, on top of the tabular cell width
# Baseline offset from a digit row's visual center, as a fraction of the
# font size — see _draw_spaced_digits. Measured by rendering
# "0123456789" at a known baseline and reading the ink box back: Fredoka's
# figures run 0.700 em above the baseline to 0.020 em below at this weight,
# putting their visual middle 0.34 em up. (Mulmaru's sat at 0.38, which is
# why this changed with the font.)
const DIGIT_BASELINE_FROM_CENTER_FRAC := 0.34
# 그라데이션을 숫자 잉크 높이에 딱 맞추려고 쓰는, 같은 측정에서 나온 값.
const DIGIT_INK_ABOVE_FRAC := 0.700
const DIGIT_INK_BELOW_FRAC := 0.020

# Pause/Mute button size comes from the shared row scale (see
# _layout_hud_buttons) rather than a fixed height, so the buttons keep the
# proportion to the score box that they were drawn with. Both icons are
# cropped onto the same canvas by the slicer, so one size fits both and they
# read as a matched pair.

# Pause/Mute button press feedback — quick squash-in on press, springy
# release back to full size. Needs pivot_offset centered on the button (set
# in _ready) so the scale anchors from the icon's center, not its top-left.
const BUTTON_PRESS_SCALE := 0.85
const BUTTON_PRESS_ANIM_DURATION := 0.08

var player_y: float = 0.0
var player_vel: float = 0.0

# Gate-pass speed boost state (see GATE_SPEED_BOOST_PEAK/DURATION above).
# -1 = inactive. Read by _update_playing's gate-scroll step only.
var gate_speed_boost_elapsed: float = -1.0
var boost_button_held: bool = false  # see the BOOST_BUTTON_* consts; read fresh each frame, so releasing is instant
# 0..1 ease behind boost_button_held. The world speed itself is NOT eased —
# it reads the bool directly, so release is instant — but the look is, so it
# does not snap. See the speed-feel block above.
var boost_visual_blend: float = 0.0
# Drives the boost glow's breathe only. Kept ever-increasing rather than
# reset on each press: restarting it would snap the halo to the top of its
# pulse every time the button goes down, which is a flicker exactly when the
# player is looking at the character.
var boost_glow_elapsed: float = 0.0
var character_glow_texture: Texture2D
# Boost burst (see the BOOST_BURST_* consts). -1 = not playing; the press
# sets it to 0 and _update_fx runs it back to -1 at the end. Same
# -1-means-idle convention the other one-shot FX timers here use.
var boost_burst_frames: Array[Texture2D] = []
var boost_burst_elapsed: float = -1.0
# Boost bonus bar (see the BOOST_BAR_* consts). elapsed counts real seconds
# since the current gate spawned and is deliberately NOT scaled by boost —
# that is the entire mechanic.
var boost_bar_elapsed: float = -1.0    # -1 = no gate in flight
var boost_bar_duration: float = 0.0    # T_base for the gate in flight
var boost_bar_flash_elapsed: float = -1.0
var boost_bar_flash_color := Color.WHITE
var boost_bar_track_texture: Texture2D            # see BOOST_BAR_TRACK_PATH
var boost_bar_fill_textures: Array[Texture2D] = []  # index-aligned to BOOST_BAR_FILL_PATHS: none / mid / best
# BOOST popup (see the BOOST_POP_* consts). Single instance — it is pinned
# to a corner, so a list would only ever stack on itself.
var boost_pop_elapsed: float = -1.0    # -1 = inactive
var boost_pop_text := ""
var boost_pop_color := Color.WHITE
var boost_pop_font_size: int = 0
var boost_pop_is_best: bool = false    # gates the glow pass
var boost_pop_anchor := Vector2.ZERO   # captured beside the character at the instant of the pass

var score: int = 0
var combo: int = 0
var max_combo: int = 0   # highest combo reached this run — see the gate-pass handler
# 광고를 보고 이어서 뛴 판인가. 부활 팝업이 "이어가면 이 판은 순위표에
# 올라가지 않는다"고 약속하므로, 그 약속을 지키려면 끝까지 들고 가야 한다.
# (개인 최고 기록은 "always saved"라고 했으니 부활 여부와 무관하게 쓴다.)
var run_revived: bool = false
# 이 판에서 "첫 실수 전까지" 도달한 점수. 순위표에 올라가는 건 이 값이다.
#
# 광고를 보고 이어 뛰면 개인 최고 기록은 끝까지 간 점수로 갱신되지만,
# 순위표는 여기서 멈춘다. 광고로 순위를 살 수는 없게 하면서, 광고를 보기
# 전에 이미 정직하게 벌어 둔 점수까지 빼앗지는 않는 선이다.
#
# 부활을 거절하면 이 값이 곧 최종 점수라 아무 차이가 없다.
var leaderboard_score: int = 0
var gates_passed: int = 0

var gates: Array = []
var last_zone_center: float = 0.0  # anchor for the next reachable-zone roll

var flash_color := Color(0, 0, 0, 0)
var flash_time := 0.0
const FLASH_DURATION := 0.25

# Back-to-back repeat guard, shared by all three modes. Holds whatever
# identifies the PREVIOUS gate's question — country code for SKY, the
# expression text for JUNGLE, the colour word for OCEAN — and a new question
# that matches it is re-rolled (see QUIZ_REPEAT_RETRIES and _spawn_gate).
# Only the immediately previous one: repeats further back are fine, and
# forbidding them would starve the late phases, whose pools are small by
# design. Cleared per run in _reset_game.
var last_quiz_key: String = ""

# Shared size for every OCEAN gate option, resolved on first draw — see
# _ocean_gate_font_size. -1 = not computed yet.
var ocean_gate_font_size: int = -1

var current_mode: int = Mode.SKY  # picked at State.MODE_SELECT — see _apply_mode
var active_draw_offset_fly := Vector2.ZERO
var active_draw_offset_happy := Vector2.ZERO
var active_draw_offset_sad := Vector2.ZERO
var active_visual_size_scale: float = 1.0

var flap_frames: Array[Texture2D] = []
var flap_frame_index: int = 0
var flap_timer: float = 0.0
var happy_face_texture: Texture2D
var happy_flap_elapsed: float = -1.0  # -1 = inactive; set to 0 on every gate pass, see _play_gate_success_fx
var sad_face_texture: Texture2D
var ready_texture: Texture2D
var start_texture: Texture2D
# No sign-in exists yet. The game-over popup branches on this, so it lives
# here as an export rather than a bare false — it can be flipped in the
# inspector to see the logged-in variants once they are built.
# 인증이 붙기 전까지의 자리표시 — 설정 팝업의 계정 줄이 이걸 읽는다.
var player_avatar: Texture2D = null
var player_display_name: String = ""
@export var player_logged_in: bool = false
# 모드별 최고 점수. 인덱스가 곧 Mode 값이다. _ready에서 불러오고, 기록을
# 갈아치울 때만 저장한다.
var best_scores := PackedInt32Array()
# 모드별 순위표 기록. 개인 최고 기록과 나뉘어 있다 — leaderboard_score 참고.
var leaderboard_bests := PackedInt32Array()
var score_box_texture: Texture2D
var score_crown_texture: Texture2D
var score_font: Font
var quiz_box_texture: Texture2D
var logo_texture: Texture2D
var logo_elapsed: float = 0.0
# 무거운 부팅이 아직 남아 있는가. 로고가 다 밝아진 뒤 한 번 돈다.
var boot_pending := false
var splash_texture: Texture2D
var splash_title_texture: Texture2D
var splash_elapsed: float = 0.0   # free-running clock for the prompt pulse
var splash_exit_elapsed: float = -1.0  # -1 = not leaving yet; see SPLASH_EXIT_DURATION
# One Array[Texture2D] of flight frames per entry in SPLASH_CHARACTER_MODES,
# loaded once in _ready and independent of the game's own flap_frames, which
# only ever holds the mode currently being played.
var splash_character_frames: Array = []
# Own CanvasItem so the title characters can use a smooth minification filter
# without the rest of the game inheriting it — see _draw_splash_characters.
var splash_char_layer: Node2D
# Child canvas the top HUD is drawn on, so it can use a texture filter of
# its own (see scripts/HudCanvas.gd). Created in _ready.
var hud_canvas: Node2D
# 점수 숫자의 속만 그리는 캔버스. HUD 캔버스보다 뒤에 붙어 테두리 위에 얹힌다.
var score_fill_canvas: Node2D
var score_fill_material: ShaderMaterial
# 최고 점수도 같은 방식으로. 셰이더 uniform 은 캔버스마다 하나씩이라,
# 그라데이션이 둘이면 캔버스도 둘이어야 한다.
var best_fill_canvas: Node2D
var best_fill_material: ShaderMaterial
var flag_records: Array = []          # [{code, name, image, tier}, ...] — see FLAGS_DATA_PATH
var flag_textures: Dictionary = {}    # code (String) -> Texture2D, preloaded from flag_records
var flag_records_by_tier: Dictionary = {}  # recognition_tier (int 1-4) -> Array of records, picks the ANSWER
var flag_records_by_cluster: Dictionary = {}  # confusion_cluster_id -> Array of records, picks the DECOY
var muted: bool = false

var gate_left_pillar_texture: Texture2D
var gate_right_pillar_texture: Texture2D
var gate_base_texture: Texture2D
var gate_flag_panel_texture: Texture2D

# Background parallax state (see the const block above for tunables).
var mountain_textures: Array[Texture2D] = []
var mountain_list: Array = []  # fixed pool, each: {texture, x, y, width_px, height_px}

var bg_sparkle_textures: Array[Texture2D] = []
var bg_sparkles: Array = []  # fixed pool, each: {texture, x, y, base_scale, base_alpha, duration, elapsed, pulses}

var castle_texture: Texture2D
var castle_active: bool = false
var castle_x: float = 0.0
var castle_y: float = 0.0
var castle_height_px: float = 0.0
var castle_alpha: float = 0.0
var castle_cooldown_timer: float = 3.0  # short initial wait so the first castle isn't instant

var cloud_mid_textures: Array[Texture2D] = []
var cloud_mid_list: Array = []  # fixed pool, each: {texture, x, y, scale, alpha, speed, flip, near}

# Per-mode background state — loaded in _apply_mode, see the const/export block above.
var bg_texture: Texture2D
var bg_scroll_x: float = 0.0  # ever-increasing distance scrolled; wrapped with fposmod at draw time
# Optional near parallax layer. null for a mode with no MODE_BG_NEAR_TEXTURE_PATH
# row; it keeps its own scroll distance because it travels at a different rate.
var bg_near_texture: Texture2D
var bg_near_scroll_x: float = 0.0

# Ambient background particle state (see the const/export block above).
var particle_textures: Array[Texture2D] = []
var ambient_particle_list: Array = []  # fixed pool, each: {texture, base_x, y, size, wobble_amp, wobble_freq, phase, elapsed, rotation, spin}

# Gate-pass FX state (see the const block above for tunables).
var sparkle_texture_sets: Array = []  # ALL four colours, index-aligned to SPARKLE_COLOR_NAMES; each an Array[Texture2D] of that colour's shapes. Shared by the trail and the gate burst — see the shared-sparkle const block.
var fx_burst_textures: Array[Texture2D] = []  # flat, pre-weighted pool for the two spark layers: each colour repeated per FX_BURST_COLOR_WEIGHTS_PER_MODE, so a uniform pick yields the mode's mix
var fx_sparks: Array = []            # each: {pos, vel, scale, rotation, lifetime, elapsed, texture}
var fx_speed_lines: Array = []       # each: {y_offset, length, elapsed, color}
var trail_texture_sets: Array = []   # one Array[Texture2D] of sparkle shapes per colour in TRAIL_COLORS_PER_MODE — grouped, not flattened, so DREAM can step colour by colour
var trail_particles: Array = []      # each: {pos, drift_y, size, rotation, spin, lifetime, elapsed, texture} — see the TRAIL_* consts
var trail_spawn_timer: float = 0.0
var trail_color_cursor: int = 0      # walks trail_texture_sets, carrying across spawns — what makes DREAM's trail and bursts rainbow
var combo_display_punch_elapsed: float = 0.0  # time since the last pass — drives the punch/bounce, then just sits at rest (never expires while combo > 0)
var combo_display_time: float = 0.0           # free-running clock while combo > 0, drives the Tier 3/4 color animation
var fx_impact_flashes: Array = []    # each: {pos, radius, elapsed}
var fx_pending_bursts: Array = []    # each: {delay, gate_center} — burst B + speed streaks fire together once delay elapses
var fx_shake_elapsed: float = -1.0   # -1 = inactive
var fx_stretch_elapsed: float = -1.0 # -1 = inactive
var combo_shake_elapsed: float = -1.0  # -1 = inactive; separate tiny shake for combo Tier 3+, independent of fx_shake_elapsed
var combo_glow_elapsed: float = -1.0   # -1 = inactive; screen-edge glow for combo Tier 4
var combo_font: Font
var fx_sound_whoosh: AudioStreamPlayer
var fx_sound_chime: AudioStreamPlayer
var fx_sound_flap: AudioStreamPlayer
# Two players so a track change can crossfade; bgm_active indexes whichever
# is currently the audible one. See _play_bgm.
var bgm_players: Array[AudioStreamPlayer] = []
var bgm_active: int = 0
var bgm_current_path: String = ""
var bgm_fade_tween: Tween
var fx_sound_countdown_ready: AudioStreamPlayer
var fx_sound_countdown_start: AudioStreamPlayer
var fx_sound_gameover: AudioStreamPlayer
var fx_sound_splash_start: AudioStreamPlayer
var fx_sound_boost: AudioStreamPlayer
var boost_alpha_tween: Tween  # see _tween_boost_alpha — kept so it can be killed

@onready var mode_select_panel: Control = $UI/ModeSelectPanel
@onready var ready_panel: Control = $UI/ReadyPanel
@onready var gameover_popup: Control = $UI/GameOverPopupPanel
@onready var settings_popup: Control = $UI/SettingsPopupPanel
@onready var about_popup: Control = $UI/AboutPopupPanel
@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var final_score_label: Label = $UI/GameOverPanel/FinalScoreLabel
@onready var try_again_image: TextureRect = $UI/GameOverPanel/TryAgainImage
@onready var play_button: Button = $UI/ReadyPanel/PlayButton
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton
@onready var pause_button: Button = $UI/PauseButton
@onready var mute_button: Button = $UI/MuteButton
@onready var boost_button: Button = $UI/BoostButton
@onready var pause_panel: Control = $UI/PausePanel
@onready var revive_panel: Control = $UI/RevivePanel


# 부팅을 둘로 나눈다.
#
# 나머지 전부(_boot_load)는 약 2초가 걸리는데, 그걸 여기서 다 하면 첫 프레임이
# 그만큼 늦어져서 앱을 켜고 2초 동안 검은 화면만 보인다. 그래서 여기서는 로고
# 화면을 그리는 데 꼭 필요한 것 — 글꼴과 로고 그림 — 만 챙기고 바로 넘어간다.
#
# 무거운 쪽은 로고가 다 밝아진 뒤(_process 의 LOGO 갈래)에 한 번에 돈다.
# 그 사이 화면은 로고가 가만히 떠 있는 상태 — 어차피 유지 구간이라 멈춰 있어도
# 티가 나지 않는다. 끝나면 유지 시간을 처음부터 다시 세어 로고가 제 길이만큼
# 머문다.
func _ready() -> void:
	# Filter for everything Main draws: background, gates, character, flags,
	# particles. draw_texture_rect has no per-call filter option, so it has to
	# be set on the CanvasItem itself — which is also why the HUD needs its
	# own node to differ. See SMOOTH_WORLD_FILTER to revert this.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if SMOOTH_WORLD_FILTER else CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_fonts()
	if ResourceLoader.exists(LOGO_TEXTURE_PATH):
		logo_texture = load(LOGO_TEXTURE_PATH)
	if logo_texture != null:
		boot_pending = true
		_set_state(State.LOGO)
		return
	_boot_load()


# 글꼴만 먼저. 로고 화면의 크레딧이 이걸 쓴다.
func _setup_fonts() -> void:
	var base_font: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(COMBO_FONT_PATH):
		base_font = load(COMBO_FONT_PATH)
	# Real weight axis rather than the faux-bold this used to need: Mulmaru
	# shipped a single weight, Fredoka carries 300-700.
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	combo_font = _weighted_font(base_font, wght, TEXT_FONT_WEIGHT)
	score_font = _weighted_font(base_font, wght, SCORE_FONT_WEIGHT)


# 부팅의 무거운 쪽. _ready 에서 곧바로, 또는 로고가 뜬 뒤에 불린다.
func _boot_load() -> void:
	# 팝업 셋과 모드 선택 화면은 씬의 자식이라 원래 Main 보다 먼저 _ready 가
	# 돌았다 — 넷이 합쳐 1.6초라, 로고가 뜨기도 전에 그만큼을 잡아먹었다.
	# 이제 조립을 여기서 시킨다.
	for panel in [pause_panel, revive_panel, gameover_popup, settings_popup, about_popup,
			mode_select_panel]:
		if panel != null and panel.has_method("ensure_built"):
			panel.ensure_built()
	# ...except the top HUD, whose painted frames are minified hard enough
	# that nearest breaks their outlines. It gets its own canvas with linear
	# + mipmap filtering — see scripts/HudCanvas.gd for the why.
	hud_canvas = Node2D.new()
	hud_canvas.name = "HudCanvas"
	hud_canvas.set_script(load(HUD_CANVAS_SCRIPT_PATH))
	hud_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud_canvas.main = self
	add_child(hud_canvas)
	# 숫자 속칠 전용 캔버스 둘. 셰이더가 캔버스 전체에 걸리므로, 여기에는
	# 해당 숫자의 속 말고 아무것도 그리지 않는다.
	score_fill_canvas = _make_gradient_canvas("ScoreFillCanvas", "draw_score_fill_into",
		SCORE_NUMBER_TOP, SCORE_NUMBER_BOTTOM)
	score_fill_material = score_fill_canvas.material
	best_fill_canvas = _make_gradient_canvas("BestFillCanvas", "draw_best_fill_into",
		BEST_NUMBER_TOP, BEST_NUMBER_BOTTOM)
	best_fill_material = best_fill_canvas.material
	_load_best_score()
	_load_audio_settings()
	_load_flags_data()
	# The four HUD pieces are all per-mode now and get loaded in _apply_mode;
	# only the parts that never change per mode are set up here.
	pause_button.text = ""
	pause_button.expand_icon = true
	mute_button.text = ""
	mute_button.expand_icon = true
	boost_button.expand_icon = true
	boost_button.modulate = Color(1.0, 1.0, 1.0, BOOST_BUTTON_ALPHA)
	# flat=true 라도 Button 은 기본 테마 스타일박스의 content margin(사방 4px)을
	# 그대로 써서 아이콘을 그 안쪽에 맞춘다. 57.5px 버튼이면 그림은 49.5px 밖에
	# 안 되고, 그래서 옆의 스코어박스보다 눈에 띄게 작아 보였다. 여백 0 인
	# 스타일박스를 씌워 아이콘이 버튼 사각형을 그대로 채우게 한다.
	#
	# 부스트 버튼도 같은 이유로 함께 씌운다 — 예전에는 자기 StyleBoxFlat 로
	# 둥근 칩을 그렸지만, 이제는 그림이 원판이라 배경 상자가 필요 없다.
	for b: Button in [pause_button, mute_button, boost_button]:
		var empty := StyleBoxEmpty.new()
		for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(slot, empty)
	# Shared across every mode, so loaded once here rather than in _apply_mode.
	if ResourceLoader.exists(BOOST_BAR_TRACK_PATH):
		boost_bar_track_texture = load(BOOST_BAR_TRACK_PATH)
	for path in BOOST_BAR_FILL_PATHS:
		boost_bar_fill_textures.append(load(path) if ResourceLoader.exists(path) else null)
	# STOP is the Button default, but it is the whole reason a press here
	# does not also flap, so it is set explicitly rather than inherited.
	boost_button.mouse_filter = Control.MOUSE_FILTER_STOP
	boost_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_layout_hud_buttons()
	for path in MOUNTAIN_TEXTURE_PATHS:
		mountain_textures.append(load(path))
	for path in BG_SPARKLE_TEXTURE_PATHS:
		bg_sparkle_textures.append(load(path))
	if ResourceLoader.exists(CASTLE_TEXTURE_PATH):
		castle_texture = load(CASTLE_TEXTURE_PATH)
	# One white radial for every mode — only the tint is per-mode, so this
	# loads here with the other shared art rather than in _apply_mode.
	if ResourceLoader.exists(BOOST_GLOW_TEXTURE_PATH):
		character_glow_texture = load(BOOST_GLOW_TEXTURE_PATH)
	for path in CLOUD_MID_TEXTURE_PATHS:
		cloud_mid_textures.append(load(path))
	var view_size := get_viewport_rect().size
	_init_mountains(view_size)
	_init_bg_sparkles(view_size)
	_init_cloud_mid(view_size)
	_apply_mode(current_mode)  # loads a valid default (SKY) so nothing is empty before mode-select runs _apply_mode again
	# 효과음과 음악을 따로 조절하려면 각자 버스를 타야 한다.
	_setup_audio_buses()
	fx_sound_whoosh = AudioStreamPlayer.new()
	add_child(fx_sound_whoosh)
	fx_sound_whoosh.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_WHOOSH_PATH):
		fx_sound_whoosh.stream = load(FX_SOUND_WHOOSH_PATH)
	fx_sound_chime = AudioStreamPlayer.new()
	add_child(fx_sound_chime)
	fx_sound_chime.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_CHIME_PATH):
		fx_sound_chime.stream = load(FX_SOUND_CHIME_PATH)
	fx_sound_flap = AudioStreamPlayer.new()
	add_child(fx_sound_flap)
	fx_sound_flap.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_FLAP_FALLBACK):
		fx_sound_flap.stream = load(FX_SOUND_FLAP_FALLBACK)
	for i in range(2):
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.bus = BUS_MUSIC
		player.volume_db = BGM_SILENT_DB
		# Manual loop — simpler and more reliable than relying on each source
		# format's own loop points.
		player.finished.connect(_on_bgm_finished.bind(player))
		bgm_players.append(player)
	fx_sound_countdown_ready = AudioStreamPlayer.new()
	add_child(fx_sound_countdown_ready)
	fx_sound_countdown_ready.bus = BUS_SFX
	if ResourceLoader.exists(COUNTDOWN_READY_SOUND_PATH):
		fx_sound_countdown_ready.stream = load(COUNTDOWN_READY_SOUND_PATH)
	fx_sound_countdown_start = AudioStreamPlayer.new()
	add_child(fx_sound_countdown_start)
	fx_sound_countdown_start.bus = BUS_SFX
	if ResourceLoader.exists(COUNTDOWN_START_SOUND_PATH):
		fx_sound_countdown_start.stream = load(COUNTDOWN_START_SOUND_PATH)
	fx_sound_gameover = AudioStreamPlayer.new()
	add_child(fx_sound_gameover)
	fx_sound_gameover.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_GAMEOVER_PATH):
		fx_sound_gameover.stream = load(FX_SOUND_GAMEOVER_PATH)
	fx_sound_splash_start = AudioStreamPlayer.new()
	add_child(fx_sound_splash_start)
	fx_sound_splash_start.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_SPLASH_START_PATH):
		fx_sound_splash_start.stream = load(FX_SOUND_SPLASH_START_PATH)
	fx_sound_boost = AudioStreamPlayer.new()
	add_child(fx_sound_boost)
	fx_sound_boost.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_BOOST_PATH):
		fx_sound_boost.stream = load(FX_SOUND_BOOST_PATH)
		# 홀드는 클립(2.25초)보다 길어질 수 있으므로 이 소리만 이어 붙인다.
		# BGM 과 같은 헬퍼를 쓴다 — .import 의 loop_mode 에 기대지 않는다.
		_enable_stream_loop(fx_sound_boost.stream)
	# The mode picker builds its own UI (see ModeSelectScreen.gd) and reports
	# back which mode START chose.
	mode_select_panel.start_pressed.connect(_on_mode_selected)
	mode_select_panel.settings_pressed.connect(_open_settings)
	settings_popup.close_pressed.connect(func(): settings_popup.visible = false)
	settings_popup.sfx_volume_changed.connect(set_sfx_volume)
	settings_popup.music_volume_changed.connect(set_music_volume)
	settings_popup.login_pressed.connect(_on_login_pressed)
	settings_popup.logout_pressed.connect(_on_logout_pressed)
	settings_popup.privacy_pressed.connect(_on_privacy_pressed)
	settings_popup.terms_pressed.connect(_on_terms_pressed)
	settings_popup.contact_pressed.connect(_on_contact_pressed)
	settings_popup.about_pressed.connect(_on_about_pressed)
	about_popup.close_pressed.connect(_on_about_closed)
	settings_popup.remove_ads_pressed.connect(_on_remove_ads_pressed)
	play_button.pressed.connect(_on_play_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	gameover_popup.play_again_pressed.connect(_on_gameover_play_again_pressed)
	gameover_popup.login_pressed.connect(_on_gameover_login_pressed)
	gameover_popup.leaderboard_pressed.connect(_on_gameover_leaderboard_pressed)
	gameover_popup.share_pressed.connect(_on_gameover_share_pressed)
	gameover_popup.home_pressed.connect(_on_pause_home_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	# 팝업이 자기 버튼을 들고 있고, 눌린 결과만 신호로 알려 준다.
	pause_panel.resume_pressed.connect(_on_resume_pressed)
	pause_panel.restart_pressed.connect(_on_pause_restart_pressed)
	pause_panel.home_pressed.connect(_on_pause_home_pressed)
	pause_panel.sfx_volume_changed.connect(set_sfx_volume)
	pause_panel.music_volume_changed.connect(set_music_volume)
	revive_panel.watch_ad_pressed.connect(_on_revive_continue)
	revive_panel.decline_pressed.connect(_on_revive_decline)
	mute_button.pressed.connect(_on_mute_pressed)
	# pivot_offset is set in _layout_hud_buttons instead — it resizes the
	# buttons deferred, so reading .size here would still give the scene's
	# pre-layout value and the press animation would scale off-center.
	pause_button.button_down.connect(_animate_button_press.bind(pause_button))
	pause_button.button_up.connect(_animate_button_release.bind(pause_button))
	mute_button.button_down.connect(_animate_button_press.bind(mute_button))
	mute_button.button_up.connect(_animate_button_release.bind(mute_button))
	boost_button.button_down.connect(_on_boost_pressed)
	boost_button.button_up.connect(_on_boost_released)
	boost_button.button_down.connect(_animate_button_press.bind(boost_button))
	boost_button.button_up.connect(_animate_button_release.bind(boost_button))
	splash_char_layer = Node2D.new()
	splash_char_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	splash_char_layer.draw.connect(_draw_splash_characters)
	add_child(splash_char_layer)
	if ResourceLoader.exists(SPLASH_TEXTURE_PATH):
		splash_texture = load(SPLASH_TEXTURE_PATH)
	splash_title_texture = _load_trimmed(SPLASH_TITLE_PATH)
	splash_character_frames.clear()
	for mode in SPLASH_CHARACTER_MODES:
		var grid: Vector2i = MODE_CHARACTER_SHEET_GRID[mode]
		splash_character_frames.append(
			_slice_spritesheet(MODE_CHARACTER_DIR[mode] + MODE_CHARACTER_FLY_FILE[mode], grid.x, grid.y))
	_reset_game()
	# 로고를 이미 띄우고 있으면 그대로 두고, 로고가 끝날 때 스플래시로 간다.
	# 다만 방금 만든 노드들의 보이기 상태는 지금 화면 기준으로 다시 잡아 준다.
	if state == State.LOGO:
		_apply_screen_visibility()
	else:
		_set_state(State.SPLASH if splash_texture != null else State.MODE_SELECT)


# Slices a cols x rows spritesheet (equal-size cells) into individual
# textures, row-major (left-to-right, top-to-bottom — cell 0 is top-left,
# matching the requested TL/TR/BL/BR frame order for bird_fly.png). Built
# from Image regions at load time rather than a set of pre-cut PNGs or
# AtlasTexture .tres resources, so the sheet is the only file to manage.
func _weighted_font(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


# One happy/sad face, or SKY's if this mode's has not been drawn yet. See the
# fallback note in _apply_mode.

# Loads art with its transparent margin cropped off.
#
# The wordmark art is drawn on a canvas with slack around it (45px on the
# left, 47 on the right, and unequal top/bottom). Sizing by the canvas would
# make the visible letters narrower than asked for and push them off centre,
# and the slack differs per file, so the numbers here would stop meaning
# anything the moment the art is redrawn. Cropping first makes the width
# fraction describe the letters themselves.
# icon_crown.png 처럼 캔버스 대부분이 거의 안 보이는 픽셀인 아트는
# get_used_rect() 가 캔버스를 통째로 돌려준다. 그러면 높이를 지정해도
# 실제 그림은 그 40% 밖에 안 되어 "작게" 보인다. 알파 문턱값으로 다시 잰다.
const TRIM_INK_ALPHA := 0.06
const TRIM_INK_MIN_RUN := 2
# 잘라 낸 뒤 사방에 두르는 투명 여백(잉크 크기 대비)과, 미리 줄여 둘 높이.
# 507px 짜리 왕관을 26px 로 그리면 축소가 전부 GPU 밉맵 체인에서 일어나는데,
# 홀수 크기에서 마지막 열이 버려져 오른쪽이 깎여 보인다. 미리 짝수 크기로
# 줄여 굽고 여백을 둘러 실루엣이 가장자리에서 흐려질 자리를 만든다.
const TRIM_INK_PAD_FRAC := 0.06
const TRIM_INK_BAKE_H := 192

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
			if img.get_pixel(x, y).a < TRIM_INK_ALPHA:
				continue
			n += 1
			if row_left < 0:
				row_left = x
			row_right = x
		if n < TRIM_INK_MIN_RUN:
			continue
		if top < 0:
			top = y
		bottom = y
		left = mini(left, row_left)
		right = maxi(right, row_right)
	if top < 0 or right < 0:
		return img.get_used_rect()
	# 반투명 가장자리 한 겹은 남긴다 — 잘라 내면 계단이 진다.
	return Rect2i(maxi(0, left - 1), maxi(0, top - 1),
		mini(w - 1, right + 1) - maxi(0, left - 1) + 1,
		mini(h - 1, bottom + 1) - maxi(0, top - 1) + 1)


# READY/START 배너를 그릴 크기 가까이로 미리 구워 테두리 계단을 푼다.
# 알파를 곱한 채 줄여야 투명한 쪽 RGB 가 끌려 들어오지 않는다.
# 모드 전환 때 한 번만 돌므로 캐시해 둔다.
var _word_art_cache := {}

func _softened_word_art(tex: Texture2D, draw_width: float) -> Texture2D:
	if tex == null:
		return null
	var key: String = "%s@%d" % [tex.resource_path, int(draw_width)]
	if _word_art_cache.has(key):
		return _word_art_cache[key]
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	var target: int = int(round(draw_width * COUNTDOWN_ART_OVERSAMPLE))
	if target < img.get_width():
		var h: int = int(round(img.get_height() * float(target) / img.get_width()))
		img.premultiply_alpha()
		img.resize(target, h, Image.INTERPOLATE_LANCZOS)
		img = _unpremultiplied(img)
	img.generate_mipmaps()
	var out: Texture2D = ImageTexture.create_from_image(img)
	_word_art_cache[key] = out
	return out


# 알파를 곱해 둔 이미지를 되돌린다.
func _unpremultiplied(img: Image) -> Image:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
	return img


func _load_trimmed(path: String, by_ink := false) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("missing art: %s" % path)
		return null
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	var used := _ink_rect(img) if by_ink else img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0 and used.size != img.get_size():
		img = img.get_region(used)
	var ink_frac := Vector2.ONE
	if by_ink:
		img = _bake_small(img)
		var ink := img.get_size()
		var pad: int = maxi(4, roundi(maxi(ink.x, ink.y) * TRIM_INK_PAD_FRAC))
		# 짝수 크기로 맞춰 밉맵 체인이 잉크를 갉아먹지 않게 한다.
		var pw: int = ink.x + pad * 2
		var ph: int = ink.y + pad * 2
		pw += pw % 2
		ph += ph % 2
		var padded := Image.create_empty(pw, ph, false, Image.FORMAT_RGBA8)
		# 투명 여백의 RGB 는 검정이 아니라 실루엣 테두리 색으로 채운다.
		# 검정으로 두면 축소할 때 그 색이 끌려 들어와 가장자리가 어두워진다.
		padded.fill(Color(_edge_color(img), 0.0))
		padded.blit_rect(img, Rect2i(Vector2i.ZERO, ink), Vector2i(pad, pad))
		ink_frac = Vector2(float(ink.x) / pw, float(ink.y) / ph)
		img = padded
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	# 그릴 때 여백을 빼고 실제 그림 크기를 맞출 수 있도록 남겨 둔다.
	tex.set_meta("ink_frac", ink_frac)
	return tex


# 그릴 크기에 가깝게 미리 줄인다. 알파를 곱한 채로 줄여야 투명한 쪽 RGB 가
# 끌려 들어오지 않는다.
func _bake_small(img: Image) -> Image:
	if img.get_height() <= TRIM_INK_BAKE_H:
		return img
	var w: int = maxi(2, roundi(img.get_width() * float(TRIM_INK_BAKE_H) / float(img.get_height())))
	var out := img.duplicate() as Image
	out.premultiply_alpha()
	out.resize(w + w % 2, TRIM_INK_BAKE_H, Image.INTERPOLATE_LANCZOS)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
	return out


# 실루엣 가장자리(알파가 반쯤 있는 픽셀)의 평균 색.
func _edge_color(img: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.35 and c.a < 0.95:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	if n == 0:
		return Color(0, 0, 0)
	return Color(r / n, g / n, b / n)

func _load_face(path: String, fallback_path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if fallback_path != path and ResourceLoader.exists(fallback_path):
		push_warning("No face at %s — falling back to %s." % [path, fallback_path])
		return load(fallback_path)
	return null


func _slice_spritesheet(path: String, cols: int, rows: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	if not ResourceLoader.exists(path):
		return frames
	var sheet_texture: Texture2D = load(path)
	var full_image: Image = sheet_texture.get_image()
	var cell_w: int = full_image.get_width() / cols
	var cell_h: int = full_image.get_height() / rows
	for row in range(rows):
		for col in range(cols):
			var region := Rect2i(col * cell_w, row * cell_h, cell_w, cell_h)
			var cell_image: Image = full_image.get_region(region)
			# A grid rarely divides evenly into the frame count — DREAM's run
			# is 5 frames in a 3x2 grid, leaving the last cell blank. Drawing
			# that blank would blink the character out for one frame of every
			# cycle, so skip cells with nothing in them.
			if cell_image.is_invisible():
				continue
			# get_region() carries the source's has_mipmaps flag over and
			# allocates the whole chain, but only ever fills level 0 — every
			# smaller level comes back fully transparent. The character is
			# drawn at ~39% (256px frame into PLAYER_VISUAL_SIZE), so with a
			# mipmapping filter the GPU samples level 1 and the sprite
			# vanishes outright. Rebuild the chain from the cell we actually
			# extracted. Cheap: this runs once per mode change, not per frame.
			if cell_image.has_mipmaps():
				cell_image.clear_mipmaps()
			cell_image.generate_mipmaps()
			frames.append(ImageTexture.create_from_image(cell_image))
	return frames


# Loads assets/flags/flags_data.json (193 UN member records) and preloads
# every flag texture up front — 193 small 256x171 PNGs is negligible memory,
# and preloading means _spawn_gate can never hit a mid-run load hitch or a
# missing-texture gap. See tools/validate_flags_data.ps1 for the offline
# check that every record's code/name/image is present and 1:1 matched;
# this just trusts that and loads it.
func _load_flags_data() -> void:
	if not ResourceLoader.exists(FLAGS_DATA_PATH):
		return
	var file := FileAccess.open(FLAGS_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not (parsed is Array):
		return
	flag_records = parsed
	for record in flag_records:
		var tex_path: String = record.image
		if ResourceLoader.exists(tex_path):
			flag_textures[record.code] = load(tex_path)
		# recognition_tier drives which countries can be the ANSWER (see
		# flag_tier_weights_by_phase); confusion_cluster_id drives which one
		# becomes the DECOY (see _pick_flag_decoy). Deliberately independent
		# axes: how well known a flag is has nothing to do with what it
		# looks like, and a decoy picked by fame would be a giveaway.
		var tier: int = int(record.get("recognition_tier", 1))
		if not flag_records_by_tier.has(tier):
			flag_records_by_tier[tier] = []
		flag_records_by_tier[tier].append(record)
		var cluster: String = str(record.get("confusion_cluster_id", ""))
		if cluster == "":
			continue  # no visual twin worth trapping with — see the fallback in _pick_flag_decoy
		if not flag_records_by_cluster.has(cluster):
			flag_records_by_cluster[cluster] = []
		flag_records_by_cluster[cluster].append(record)


func _draw_sky_gradient(view_size: Vector2) -> void:
	var mid_y: float = view_size.y * 0.5
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(view_size.x, 0), Vector2(view_size.x, mid_y), Vector2(0, mid_y)]),
		PackedColorArray([COLOR_SKY_TOP, COLOR_SKY_TOP, COLOR_SKY_MID, COLOR_SKY_MID])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, mid_y), Vector2(view_size.x, mid_y), Vector2(view_size.x, view_size.y), Vector2(0, view_size.y)]),
		PackedColorArray([COLOR_SKY_MID, COLOR_SKY_MID, COLOR_SKY_BOTTOM, COLOR_SKY_BOTTOM])
	)


# ---- Layer 1: distant mountain range ----

func _make_mountain_segment(view_size: Vector2, start_x: float) -> Dictionary:
	var tex: Texture2D = mountain_textures[randi() % mountain_textures.size()]
	var height_px: float = view_size.y * MOUNTAIN_HEIGHT_FRACTION
	var width_px: float = tex.get_width() * (height_px / tex.get_height())
	return {
		"texture": tex,
		"x": start_x,
		"y": view_size.y - height_px + height_px * MOUNTAIN_BOTTOM_OVERSHOOT_FRAC,
		"width_px": width_px,
		"height_px": height_px,
		"flip": randf() < 0.5,
	}


func _init_mountains(view_size: Vector2) -> void:
	mountain_list.clear()
	var overlap_px: float = view_size.y * MOUNTAIN_HEIGHT_FRACTION * MOUNTAIN_SEGMENT_OVERLAP_FRAC
	var cursor_x := 0.0
	for i in range(MOUNTAIN_POOL_SIZE):
		var seg: Dictionary = _make_mountain_segment(view_size, cursor_x)
		mountain_list.append(seg)
		cursor_x += seg.width_px - overlap_px


func _update_mountains(delta: float, view_size: Vector2) -> void:
	var overlap_px: float = view_size.y * MOUNTAIN_HEIGHT_FRACTION * MOUNTAIN_SEGMENT_OVERLAP_FRAC
	for seg in mountain_list:
		seg.x -= MOUNTAIN_SPEED_RATIO * GATE_SPEED * _boost_bg_multiplier() * delta
	for seg in mountain_list:
		if seg.x + seg.width_px < 0.0:
			var max_right := 0.0
			for s2 in mountain_list:
				max_right = max(max_right, s2.x + s2.width_px)
			var fresh: Dictionary = _make_mountain_segment(view_size, max_right - overlap_px)
			for key in fresh:
				seg[key] = fresh[key]


func _draw_mountains() -> void:
	for seg in mountain_list:
		var size := Vector2(seg.width_px, seg.height_px)
		var flip_x: float = -1.0 if seg.flip else 1.0
		draw_set_transform(Vector2(seg.x + size.x * 0.5, seg.y + size.y * 0.5), 0.0, Vector2(flip_x, 1.0))
		draw_texture_rect(seg.texture, Rect2(-size * 0.5, size), false, Color(1.0, 1.0, 1.0, MOUNTAIN_ALPHA))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- Layer 2: background sparkle ----

func _make_bg_sparkle(view_size: Vector2, stagger_start: bool) -> Dictionary:
	var duration: float = randf_range(BG_SPARKLE_DURATION_RANGE.x, BG_SPARKLE_DURATION_RANGE.y)
	return {
		"texture": bg_sparkle_textures[randi() % bg_sparkle_textures.size()],
		"x": randf_range(0.0, view_size.x),
		"y": randf_range(view_size.y * BG_SPARKLE_Y_BAND.x, view_size.y * BG_SPARKLE_Y_BAND.y),
		"base_scale": randf_range(BG_SPARKLE_SCALE_RANGE.x, BG_SPARKLE_SCALE_RANGE.y),
		"base_alpha": randf_range(BG_SPARKLE_ALPHA_RANGE.x, BG_SPARKLE_ALPHA_RANGE.y),
		"duration": duration,
		"elapsed": randf_range(0.0, duration) if stagger_start else 0.0,
		"pulses": randf() < BG_SPARKLE_PULSE_CHANCE,
	}


func _init_bg_sparkles(view_size: Vector2) -> void:
	bg_sparkles.clear()
	for i in range(BG_SPARKLE_POOL_SIZE):
		bg_sparkles.append(_make_bg_sparkle(view_size, true))


func _update_bg_sparkles(delta: float, view_size: Vector2) -> void:
	for s in bg_sparkles:
		s.elapsed += delta
		s.x -= BG_SPARKLE_SPEED_RATIO * GATE_SPEED * _boost_bg_multiplier() * delta
		if s.elapsed >= s.duration or s.x < -32.0:
			# Recycled in place — same Dictionary object, fields overwritten,
			# never freed/reallocated (see the pooling note above).
			var fresh: Dictionary = _make_bg_sparkle(view_size, false)
			for key in fresh:
				s[key] = fresh[key]


func _draw_bg_sparkles() -> void:
	for s in bg_sparkles:
		var t: float = clampf(s.elapsed / s.duration, 0.0, 1.0)
		var envelope: float = sin(PI * t)  # fade in -> brighten -> fade out
		var alpha: float = s.base_alpha * envelope
		if alpha <= 0.001:
			continue
		var scale_mult: float = s.base_scale
		if s.pulses:
			scale_mult *= 1.0 + sin(s.elapsed * TAU / (s.duration * 0.5)) * BG_SPARKLE_PULSE_AMOUNT
		var tex: Texture2D = s.texture
		var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * scale_mult
		draw_texture_rect(tex, Rect2(Vector2(s.x - size.x * 0.5, s.y - size.y * 0.5), size), false, Color(1.0, 1.0, 1.0, alpha))


# ---- Layer 3: far castle (rare landmark) ----

func _spawn_castle(view_size: Vector2) -> void:
	castle_active = true
	castle_height_px = view_size.y * randf_range(CASTLE_HEIGHT_FRACTION_RANGE.x, CASTLE_HEIGHT_FRACTION_RANGE.y)
	castle_x = view_size.x + castle_height_px
	castle_y = view_size.y * randf_range(CASTLE_Y_BAND.x, CASTLE_Y_BAND.y)
	castle_alpha = randf_range(CASTLE_ALPHA_RANGE.x, CASTLE_ALPHA_RANGE.y)


func _update_castle(delta: float, view_size: Vector2) -> void:
	if castle_active:
		castle_x -= CASTLE_SPEED_RATIO * GATE_SPEED * _boost_bg_multiplier() * delta
		if castle_x + castle_height_px < 0.0:
			castle_active = false
			castle_cooldown_timer = randf_range(CASTLE_COOLDOWN_RANGE.x, CASTLE_COOLDOWN_RANGE.y)
	else:
		castle_cooldown_timer -= delta
		if castle_cooldown_timer <= 0.0 and castle_texture != null:
			_spawn_castle(view_size)


func _draw_castle() -> void:
	if not castle_active or castle_texture == null:
		return
	var size := Vector2(castle_height_px, castle_height_px)  # source art is square
	var top_left := Vector2(castle_x - size.x * 0.5, castle_y - size.y * 0.5)
	draw_texture_rect(castle_texture, Rect2(top_left, size), false, Color(1.0, 1.0, 1.0, castle_alpha))


# ---- Layer 4: mid-distance clouds (near/far sub-groups for depth) ----

func _make_cloud_mid(view_size: Vector2, start_x: float, is_near: bool) -> Dictionary:
	var scale_range: Vector2 = CLOUD_MID_NEAR_SCALE_RANGE if is_near else CLOUD_MID_FAR_SCALE_RANGE
	var alpha_range: Vector2 = CLOUD_MID_NEAR_ALPHA_RANGE if is_near else CLOUD_MID_FAR_ALPHA_RANGE
	var speed_ratio: float = CLOUD_MID_NEAR_SPEED_RATIO if is_near else CLOUD_MID_FAR_SPEED_RATIO
	return {
		"texture": cloud_mid_textures[randi() % cloud_mid_textures.size()],
		"x": start_x,
		"y": randf_range(view_size.y * CLOUD_MID_Y_BAND.x, view_size.y * CLOUD_MID_Y_BAND.y),
		"scale": randf_range(scale_range.x, scale_range.y),
		"alpha": randf_range(alpha_range.x, alpha_range.y),
		"speed": speed_ratio * GATE_SPEED,
		"flip": randf() < 0.5,
		"near": is_near,
	}


func _init_cloud_mid(view_size: Vector2) -> void:
	cloud_mid_list.clear()
	for i in range(CLOUD_MID_FAR_COUNT):
		cloud_mid_list.append(_make_cloud_mid(view_size, randf_range(0.0, view_size.x), false))
	for i in range(CLOUD_MID_NEAR_COUNT):
		cloud_mid_list.append(_make_cloud_mid(view_size, randf_range(0.0, view_size.x), true))


func _update_cloud_mid(delta: float, view_size: Vector2) -> void:
	for c in cloud_mid_list:
		c.x -= c.speed * _boost_bg_multiplier() * delta
		var tex_w: float = c.texture.get_width() * c.scale
		if c.x + tex_w < 0.0:
			# Recycled in place, respawned past the right edge — never
			# visibly clipped popping in. Keeps its own near/far identity.
			var fresh: Dictionary = _make_cloud_mid(view_size, view_size.x + randf_range(20.0, 140.0), c.near)
			for key in fresh:
				c[key] = fresh[key]


func _draw_cloud_mid(near: bool) -> void:
	for c in cloud_mid_list:
		if c.near != near:
			continue
		var tex: Texture2D = c.texture
		var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * c.scale
		var flip_x: float = -1.0 if c.flip else 1.0
		draw_set_transform(Vector2(c.x + size.x * 0.5, c.y + size.y * 0.5), 0.0, Vector2(flip_x, 1.0))
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1.0, 1.0, 1.0, c.alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- Per-mode background (see _apply_mode/_draw()) ----
# A painted scene, scaled to exactly fill the view height and tiled
# horizontally — the same infinite-scroll technique the old three-layer sky
# used. Modes that declare a near cut-out get a second pass of it at a
# faster rate, which is the whole of the parallax: one tiler, two
# independent scroll distances.

func _update_sky_background(delta: float) -> void:
	var world_speed: float = GATE_SPEED * _boost_bg_multiplier() * delta
	bg_scroll_x += bg_speed_ratio * world_speed
	# Advanced even with no near texture loaded. It costs one multiply-add,
	# and it keeps the two distances from having to be reasoned about
	# separately — _apply_mode zeroes both on every mode switch anyway.
	bg_near_scroll_x += bg_near_speed_ratio * world_speed


func _draw_sky_background(view_size: Vector2) -> void:
	_draw_bg_layer(bg_texture, bg_scroll_x, view_size)
	# Second, so its foliage and pillars frame what the far layer paints
	# through its transparent middle. Both still draw behind the gate zone —
	# see the call site in _draw().
	_draw_bg_layer(bg_near_texture, bg_near_scroll_x, view_size)


func _draw_bg_layer(tex: Texture2D, scroll_x: float, view_size: Vector2) -> void:
	if tex == null:
		return
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	if tex_size.y <= 0.0 or view_size.y <= 0.0:
		return
	var draw_scale: float = view_size.y / tex_size.y
	var tile_w: float = tex_size.x * draw_scale
	# Guards against an infinite loop if tile_w is ever degenerate (e.g. the
	# viewport briefly reporting zero size on startup) — see the freeze this
	# caused before it was guarded.
	if tile_w <= 1.0:
		return
	var tint := Color(bg_brightness, bg_brightness, bg_brightness, 1.0)
	var x: float = -fposmod(scroll_x, tile_w)
	while x < view_size.x:
		draw_texture_rect(tex, Rect2(Vector2(x, 0.0), Vector2(tile_w, view_size.y)), false, tint)
		x += tile_w


# ---- Ambient background particles (see _apply_mode/_draw()) ----
# base_x never changes after spawn — JUNGLE/OCEAN sway around it, SKY just
# holds still there. y is the only field that actually travels over time
# (for JUNGLE/OCEAN); SKY's y is fixed and only alpha pulses.

func _make_ambient_particle(view_size: Vector2, stagger_start: bool) -> Dictionary:
	var size: float = randf_range(particle_draw_size_range.x, particle_draw_size_range.y)
	var texture: Texture2D = particle_textures[randi() % particle_textures.size()] if not particle_textures.is_empty() else null
	var d := {
		"texture": texture,
		"base_x": randf_range(0.0, view_size.x),
		"y": 0.0,
		"size": size,
		"wobble_amp": 0.0,
		"wobble_freq": 0.0,
		"phase": randf_range(0.0, TAU),
		"elapsed": 0.0,
		"rotation": randf_range(0.0, TAU),
		"spin": randf_range(PARTICLE_SPIN_RANGE.x, PARTICLE_SPIN_RANGE.y),
	}
	var motion: int = MODE_PARTICLE_MOTION[current_mode]
	var rising: bool = motion == AmbientMotion.RISE
	if rising:
		d.wobble_amp = randf_range(particle_sway_amplitude_range.x, particle_sway_amplitude_range.y)
		d.wobble_freq = randf_range(particle_sway_freq_range.x, particle_sway_freq_range.y)
	elif motion == AmbientMotion.DRIFT_DIAGONAL:
		# Deliberately much lazier than FALL's — see the const block for why
		# a lively flutter here hides the diagonal completely.
		d.wobble_amp = randf_range(PARTICLE_DIAGONAL_FLUTTER_AMP_RANGE.x, PARTICLE_DIAGONAL_FLUTTER_AMP_RANGE.y)
		d.wobble_freq = randf_range(PARTICLE_DIAGONAL_FLUTTER_FREQ_RANGE.x, PARTICLE_DIAGONAL_FLUTTER_FREQ_RANGE.y)
	else:
		d.wobble_amp = randf_range(particle_flutter_amplitude_range.x, particle_flutter_amplitude_range.y)
		d.wobble_freq = randf_range(particle_flutter_freq_range.x, particle_flutter_freq_range.y)

	if stagger_start:
		# Initial fill only: scatter over the whole screen so the field is
		# already populated instead of raining in from one edge.
		d.base_x = randf_range(0.0, view_size.x)
		d.y = randf_range(0.0, view_size.y * 1.3) if rising else randf_range(-view_size.y * 0.3, view_size.y)
		return d

	# Which edge a recycled particle re-enters through.
	#
	# With purely vertical motion that is always the ceiling (or the floor).
	# Add the boost's leftward wind and part of the flow now crosses the
	# RIGHT edge instead — so some of them have to appear there.
	#
	# Without this the field visibly empties under a sustained boost: the
	# pool is a fixed size (particle_count), every particle re-enters at the
	# ceiling, and the wind sweeps each one off the left before it has
	# crossed. All 8 end up spending their lives in the top-left corner.
	# Splitting the spawn between the two inflow edges in proportion to how
	# much flow actually crosses each keeps the screen populated at any
	# boost level, and collapses back to "always the ceiling" at rest, where
	# the sideways flow is zero.
	var speed_y: float = (particle_rise_speed if rising else particle_fall_speed) * _boost_bg_multiplier()
	var speed_x: float = PARTICLE_BOOST_WIND_X * boost_visual_blend
	if motion == AmbientMotion.DRIFT_DIAGONAL:
		speed_x += particle_fall_speed * PARTICLE_DRIFT_X_RATIO * _boost_bg_multiplier()
	var flux_top: float = speed_y * view_size.x
	var flux_side: float = speed_x * view_size.y
	if flux_side > 0.0 and randf() < flux_side / (flux_side + flux_top):
		d.base_x = view_size.x + size * 0.5
		d.y = randf_range(0.0, view_size.y)
	else:
		d.base_x = randf_range(0.0, view_size.x)
		d.y = view_size.y + size if rising else -size
	return d


func _init_ambient_particles(view_size: Vector2) -> void:
	ambient_particle_list.clear()
	for i in range(particle_count):
		ambient_particle_list.append(_make_ambient_particle(view_size, true))


func _update_ambient_particles(delta: float, view_size: Vector2) -> void:
	if particle_textures.is_empty():
		return
	# Travel rides the hold-to-accelerate boost like the rest of the backdrop
	# — see _boost_bg_multiplier. The wobble phase and the spin deliberately
	# do NOT: covering more ground at the same sway rate is what reads as
	# speed, where scaling everything would just look fast-forwarded.
	var boost: float = _boost_bg_multiplier()
	var wind: float = PARTICLE_BOOST_WIND_X * boost_visual_blend
	for p in ambient_particle_list:
		p.elapsed += delta
		p.rotation += p.spin * delta
		# Applies to every motion, and is zero unless the button is down.
		p.base_x -= wind * delta
		var recycle := false
		match MODE_PARTICLE_MOTION[current_mode]:
			AmbientMotion.DRIFT_DIAGONAL:
				p.y += particle_fall_speed * boost * delta
				p.base_x -= particle_fall_speed * PARTICLE_DRIFT_X_RATIO * boost * delta
				recycle = p.y - p.size > view_size.y
			AmbientMotion.FALL:
				p.y += particle_fall_speed * boost * delta
				recycle = p.y - p.size > view_size.y
			AmbientMotion.RISE:
				p.y -= particle_rise_speed * boost * delta
				recycle = p.y + p.size < 0.0
		# Checked for every motion, not just the diagonal: the boost wind can
		# carry anything off the left edge, whichever way it was heading.
		if p.base_x + p.size < 0.0:
			recycle = true
		if recycle:
			var fresh: Dictionary = _make_ambient_particle(view_size, false)
			for key in fresh:
				p[key] = fresh[key]


func _draw_ambient_particles() -> void:
	for p in ambient_particle_list:
		var texture: Texture2D = p.texture
		if texture == null:
			continue
		var tex_size := Vector2(texture.get_width(), texture.get_height())
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			continue
		var draw_scale: float = p.size / max(tex_size.x, tex_size.y)
		var size: Vector2 = tex_size * draw_scale
		# Sway is a draw-time offset, not part of base_x — so a diagonal
		# drift stays a straight line the sway rides on rather than
		# compounding into a random walk.
		var x: float = p.base_x + sin(p.elapsed * p.wobble_freq * TAU + p.phase) * p.wobble_amp
		draw_set_transform(Vector2(x, p.y), p.rotation, Vector2.ONE)
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false, Color(1.0, 1.0, 1.0, particle_alpha_max))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gate_zone_top(view_size: Vector2) -> float:
	# Starts at the quiz box's bottom edge. The art is cropped tight to its
	# frame now (tools/slice_hud_sheet.gd trims to the alpha bounding box), so
	# the rect's bottom IS the painted bottom — no transparent margin to
	# compensate for the way the old assets needed. The top gate's frame is
	# separately inset in _spawn_gate (see _gate_frame_top_overhang) so its
	# own top edge still never crosses this line — it's allowed to touch it,
	# just not go past it.
	return _quiz_box_rect(view_size).end.y + GATE_ZONE_TOP_BUFFER


func _gate_zone_bottom(view_size: Vector2) -> float:
	# No reserved control zone — the gate zone always runs to the screen edge.
	return view_size.y


func _gate_wall_center_y(view_size: Vector2) -> float:
	# The center wall (and the top/bottom lane split) is centered within the
	# gate zone, not the raw screen — otherwise shrinking the top of the
	# zone for the HUD/quiz box would silently steal space from the top
	# lane only, making the two lanes uneven.
	return (_gate_zone_top(view_size) + _gate_zone_bottom(view_size)) * 0.5


func _gate_ring_inner_zone_height() -> float:
	# Converts the ring art's measured inner-hole height (in source-canvas
	# pixels, see GATE_RING_INNER_TOP/BOTTOM_LOCAL_Y) into world pixels using
	# the exact same scale factor _draw_gate_frame_layer uses to size the
	# frame art, so the judgment zone always matches whatever size the ring
	# is actually drawn at (including if gate_visual_zone_ratio is retuned
	# later). This replaces the old hand-picked PLAYER_SIZE.y + margin value
	# now that the passable opening is dictated by real art, not a rectangle.
	var scale: float = (GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / GATE_PILLAR_CANVAS_SIZE
	var inner_height_px: float = (GATE_RING_INNER_BOTTOM_LOCAL_Y - GATE_RING_INNER_TOP_LOCAL_Y) + GATE_ZONE_HEIGHT_MARGIN_LOCAL
	return inner_height_px * scale


func _gate_frame_top_overhang() -> float:
	# How far above a zone's center the pillars' tops extend, in world
	# pixels. _spawn_gate insets the top-lane spawn band by this so a zone
	# never rolls close enough to the screen's top edge to push the frame
	# off it; the frame is always drawn centered exactly on the zone (see
	# _draw()), so keeping the frame on-screen this way — instead of
	# clamping the draw position — means the drawn "hole" never drifts
	# away from the actual judged zone.
	var base_scale: float = ((GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / GATE_PILLAR_CANVAS_SIZE) * GATE_VISUAL_CLAMP_MARGIN
	var pillar_center: float = GATE_PILLAR_CANVAS_SIZE * 0.5
	return (pillar_center - GATE_PILLAR_TOP_LOCAL_Y) * base_scale


func _gate_frame_bottom_overhang() -> float:
	# Same as _gate_frame_top_overhang, for how far below a zone's center
	# the pillars' feet extend — used to inset the bottom-lane spawn band
	# from the screen's bottom edge. Pillar-canvas-space (512 units).
	var base_scale: float = ((GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / GATE_PILLAR_CANVAS_SIZE) * GATE_VISUAL_CLAMP_MARGIN
	var pillar_center: float = GATE_PILLAR_CANVAS_SIZE * 0.5
	return (GATE_PILLAR_BOTTOM_LOCAL_Y - pillar_center) * base_scale


func _draw_gate_frame_layer(texture: Texture2D, center_x: float, center_y: float, punch_scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var target_long_edge: float = GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio
	# punch_scale (see _gate_punch_scale) is a draw-time-only size wobble —
	# it never changes the zone/collision geometry this is centered on. The
	# gate-pass color flash is a brightness tint (see _gate_glow_tint) on
	# this same single ring texture, not a separate glow-art texture swap.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var scale_factor: float = (target_long_edge / max(tex_size.x, tex_size.y)) * punch_scale
	var draw_size: Vector2 = tex_size * scale_factor
	var top_left := Vector2(center_x - draw_size.x * 0.5, center_y - draw_size.y * 0.5)
	draw_texture_rect(texture, Rect2(top_left, draw_size), false, tint)


func _gate_base_center_y_offset() -> float:
	# In local canvas units (not yet scaled): how far below the ring's own
	# center the base's own center needs to land so the base's top platform
	# surface lines up just inside the ring's bottom edge (with
	# GATE_BASE_OVERLAP_LOCAL of intentional overlap — see the const comment).
	var ring_bottom_from_center: float = GATE_PILLAR_BOTTOM_LOCAL_Y - GATE_PILLAR_CANVAS_SIZE * 0.5
	var base_top_from_center: float = GATE_BASE_CANVAS_SIZE * 0.5 - GATE_BASE_TOP_LOCAL_Y
	return ring_bottom_from_center + base_top_from_center - GATE_BASE_OVERLAP_LOCAL[current_mode]


func _draw_gate_base(center_x: float, center_y: float) -> void:
	if gate_base_texture == null:
		return
	var target_long_edge: float = GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio
	var tex_size := Vector2(gate_base_texture.get_width(), gate_base_texture.get_height())
	var scale_factor: float = target_long_edge / max(tex_size.x, tex_size.y)
	# Position offset uses the ring's own scale_factor (it's defined relative
	# to the ring's edges), but the draw SIZE gets its own independent
	# shrink — so making the base smaller doesn't also drag its anchor point.
	var base_center_y: float = center_y + _gate_base_center_y_offset() * scale_factor
	var draw_size: Vector2 = tex_size * scale_factor * GATE_BASE_SCALE_MULTIPLIER[current_mode]
	var base_center_x: float = center_x + GATE_BASE_OFFSET_X_LOCAL * scale_factor
	var top_left := Vector2(base_center_x - draw_size.x * 0.5, base_center_y - draw_size.y * 0.5)
	draw_texture_rect(gate_base_texture, Rect2(top_left, draw_size), false)


# Draws a gate's answer flag icon (with its backing panel) on top of
# everything else at that gate, always on the frame's own "top" side
# (toward smaller y) — the pillar art is never vertically flipped between
# lanes, so its top-of-canvas opening faces the same direction (up) whether
# this is the top-lane or bottom-lane gate; mirroring the icon per-lane put
# it down in the bottom lane's floral pillar base instead of at the U's
# opening. Anchored so the flag's own bottom edge sits exactly on zone_top
# (touching, never overlapping), clamped only as a safety floor so it can't
# render above _gate_zone_top (the HUD/quiz-box buffer). code indexes into
# flag_textures — see _spawn_gate for where top_code/bottom_code are set
# and code-checked against the quiz box target. Called last in _draw() (see
# the bottom of that function), after both ring halves and the bird, so the
# flag is guaranteed to never end up hidden behind the (now much bigger)
# ring art.
# 텍스처를 9칸으로 나눠 그린다 — 네 모서리는 크기를 유지하고 변과 가운데만
# 늘어난다. NinePatchRect는 노드라서 이 즉시 그리기 방식에는 못 쓰고,
# draw_texture_rect_region으로 아홉 조각을 직접 그린다.
#
# margin은 원본 픽셀 기준 모서리 크기, scale은 그 모서리를 화면에 몇 배로
# 그릴지다. scale이 없으면 394px짜리 패널이 그 크기 그대로 나온다.
func _draw_nine_patch(texture: Texture2D, rect: Rect2, margin: float, scale: float, ci: CanvasItem = null) -> void:
	var target: CanvasItem = ci if ci != null else self
	var tex_w: float = texture.get_width()
	var tex_h: float = texture.get_height()
	var m: float = margin
	var d: float = margin * scale
	# 그릴 사각형이 모서리 둘을 담지 못할 만큼 작으면 모서리를 줄인다 —
	# 안 그러면 좌우(또는 상하) 모서리가 서로 겹쳐 그려진다.
	d = minf(d, rect.size.x * 0.5)
	d = minf(d, rect.size.y * 0.5)
	var sx := [0.0, m, tex_w - m, tex_w]
	var sy := [0.0, m, tex_h - m, tex_h]
	var dx := [rect.position.x, rect.position.x + d, rect.end.x - d, rect.end.x]
	var dy := [rect.position.y, rect.position.y + d, rect.end.y - d, rect.end.y]
	for row in range(3):
		for col in range(3):
			var src := Rect2(sx[col], sy[row], sx[col + 1] - sx[col], sy[row + 1] - sy[row])
			var dst := Rect2(dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			target.draw_texture_rect_region(texture, dst, src)


# 좌우 끝은 그대로 두고 가운데만 가로로 늘려 그린다.
#
# 퀴즈 박스 아트는 양 끝에 보석 장식이 박혀 있어 통째로 늘리면 그 장식이
# 함께 찌그러진다. 9-slice처럼 나누되 세로로는 쪼개지 않는다 — 장식이
# 위아래 모서리가 아니라 좌우 변의 한가운데에 있어서, 세로로 쪼개면 오히려
# 장식을 가로지른다.
#
# 끝 조각은 세로 배율에 맞춰 가로도 같은 비율로 그리므로 장식의 생김새가
# 그대로 유지된다.
func _draw_horizontal_slice(texture: Texture2D, rect: Rect2, cap: float, ci: CanvasItem = null) -> void:
	var target: CanvasItem = ci if ci != null else self
	var tex_w: float = texture.get_width()
	var tex_h: float = texture.get_height()
	var scale: float = rect.size.y / tex_h
	var cap_dst: float = minf(cap * scale, rect.size.x * 0.5)
	# 왼쪽 끝
	target.draw_texture_rect_region(texture,
		Rect2(rect.position, Vector2(cap_dst, rect.size.y)),
		Rect2(0.0, 0.0, cap, tex_h))
	# 오른쪽 끝
	target.draw_texture_rect_region(texture,
		Rect2(Vector2(rect.end.x - cap_dst, rect.position.y), Vector2(cap_dst, rect.size.y)),
		Rect2(tex_w - cap, 0.0, cap, tex_h))
	# 가운데 — 가로로만 늘어난다
	var mid_w: float = rect.size.x - cap_dst * 2.0
	if mid_w > 0.0:
		target.draw_texture_rect_region(texture,
			Rect2(Vector2(rect.position.x + cap_dst, rect.position.y), Vector2(mid_w, rect.size.y)),
			Rect2(cap, 0.0, tex_w - cap * 2.0, tex_h))


func _draw_gate_answer_box(code: String, gate_x: float, zone_top: float, zone_bottom: float, view_size: Vector2) -> void:
	# JUNGLE draws its answer as plain number text instead of a flag texture
	# — everything else about the box (panel, position, card fill) is shared.
	# OCEAN takes the same text path for its colour NAME, and deliberately
	# draws it in the shared dark ink on the shared cream card, with no trace
	# of the colour it names: an option painted RED would let the player
	# match the question by colour and never read a word, which is exactly
	# the shortcut this quiz exists to close off. The name is the only way in.
	var is_math: bool = current_mode == Mode.JUNGLE
	var is_color_name: bool = current_mode == Mode.OCEAN
	var is_text: bool = is_math or is_color_name
	var texture: Texture2D = null
	if not is_text:
		texture = flag_textures.get(code)
		if texture == null:
			return
	var center_x: float = gate_x + GATE_WIDTH * 0.5
	# Width always fits the panel to the flag's own fixed on-screen size (see
	# the const block above) — that part is shared by both modes. Height is
	# where they diverge: a flag has its own fixed 3:2 to preserve, but
	# JUNGLE's number has no art of its own, so instead of the fixed flag
	# height it uses the panel's own actual scaled window height — otherwise
	# a panel whose window aspect isn't ~3:2 (jungle's is noticeably taller)
	# leaves the fixed-height card overflowing past the window into the
	# panel's own frame artwork.
	# 네 모드가 같은 크기로 그려진다 — 국기 모드 카드(72x48)가 기준이고,
	# 글자 모드도 같은 카드를 쓴다. 예전에는 패널마다 창 비율이 달라 글자
	# 카드만 높이가 따로 놀았다.
	var icon_size := Vector2(GATE_FLAG_ICON_WIDTH, GATE_FLAG_ICON_HEIGHT)
	var half_h: float = icon_size.y * 0.5
	var center_y: float = maxf(zone_top - half_h - GATE_FLAG_GAP_ABOVE_ZONE, _gate_zone_top(view_size) + half_h)
	var icon_top_left := Vector2(center_x, center_y) - icon_size * 0.5

	if gate_flag_panel_texture != null:
		# 패널은 답 카드를 테두리 두께만큼 사방으로 키운 사각형이다. 9-slice라
		# 이 사각형이 어떤 크기든 모서리와 테두리는 그려진 굵기 그대로다.
		var inset: float = (GATE_PANEL_BORDER + GATE_PANEL_PAD) * GATE_PANEL_SCALE
		var panel_rect := Rect2(icon_top_left - Vector2(inset, inset),
			icon_size + Vector2(inset, inset) * 2.0)
		_draw_nine_patch(gate_flag_panel_texture, panel_rect,
			GATE_PANEL_CORNER + GATE_PANEL_PAD, GATE_PANEL_SCALE)

	# 예전에는 여기서 답 뒤에 크림색 판을 깔았다. 국기는 3:2로 레터박스
	# 처리돼 있어(assets/flags/flags_data.json) 스위스처럼 정사각인 깃발은
	# 투명한 여백을 안고 있는데, 그 구멍을 메우고 숫자·색이름의 바탕도
	# 겸하던 판이다.
	#
	# 새 패널 아트는 자기 바탕색을 갖고 있어서 그 판이 필요 없어졌다.
	# 빼는 편이 낫다 — 패널마다 바탕 톤이 다른데 그 위에 한 가지 크림색을
	# 덮으면 모드 색이 죽는다.
	if is_text:
		# Capped by height too, not just width — the window's real height
		# varies per panel (see the note above), so a flat max wide enough
		# for sky's window could overflow a shorter one like jungle's.
		var max_font_size: int = int(min(30.0, icon_size.y * 0.6))
		# A colour name is up to six letters against JUNGLE's one or two
		# digits, so it gets more of the card's width to work with — and,
		# unlike the digits, ONE size shared by all eleven names rather than
		# a per-word fit. Fitting each word on its own would draw "RED" at
		# 30px next to "YELLOW" at 15px, which makes the pair of gates look
		# unbalanced and, worse, turns letter size into a second channel the
		# player can read the option by. Uniform, and the name is the signal.
		var font_size: int
		if is_color_name:
			font_size = _ocean_gate_font_size(icon_size, max_font_size)
		else:
			font_size = _fit_font_size(code, icon_size.x * 0.8, max_font_size, 16, combo_font)
		_draw_centered_text(code, Vector2(center_x, center_y), font_size, COLOR_TEXT_DARK, Color(COLOR_TEXT_DARK.r, COLOR_TEXT_DARK.g, COLOR_TEXT_DARK.b, 0.0), combo_font)
	else:
		draw_texture_rect(texture, Rect2(icon_top_left, icon_size), false)


# One font size for every OCEAN gate option: the largest at which the widest
# name in the table still fits the card. Cached because the answer only
# depends on the card size, which is fixed for the mode, and this is called
# twice per gate per frame. See the call site for why it is uniform.
func _ocean_gate_font_size(icon_size: Vector2, max_font_size: int) -> int:
	if ocean_gate_font_size > 0:
		return ocean_gate_font_size
	var widest: String = OCEAN_COLOR_NAMES[0]
	var widest_width: float = 0.0
	for name in OCEAN_COLOR_NAMES:
		var w: float = combo_font.get_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, -1, max_font_size).x
		if w > widest_width:
			widest_width = w
			widest = name
	ocean_gate_font_size = _fit_font_size(widest, icon_size.x * OCEAN_GATE_FIT_WIDTH_FRAC, max_font_size, OCEAN_GATE_MIN_FONT, combo_font)
	return ocean_gate_font_size


func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING and state != State.SPLASH:
		return
	if paused:
		return
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		tapped = true
	if state == State.LOGO:
		# 누르면 남은 시간을 건너뛰고 페이드 아웃부터 — 화면을 뚝 끊지 않는다.
		if tapped:
			logo_elapsed = maxf(logo_elapsed, LOGO_FADE_IN + LOGO_HOLD)
		return
	if state == State.SPLASH:
		# Any tap leaves the title screen; the flap below must not also fire.
		# The screen does not hand over immediately — it starts the prompt's
		# exit and _process changes state once that finishes — so a second
		# tap while it is playing has to be ignored.
		if tapped and splash_exit_elapsed < 0.0:
			# The cue starts now, on the tap, rather than at the handover:
			# it is the feedback for the press, and _set_state swaps the BGM
			# track, which would otherwise land on top of it.
			if fx_sound_splash_start.stream != null:
				fx_sound_splash_start.play()
			splash_exit_elapsed = 0.0
		return
	if tapped:
		player_vel = flap_velocity
		_spawn_trail_burst()
		if fx_sound_flap.stream != null:
			fx_sound_flap.play()


func _process(delta: float) -> void:
	# The title screen draws nothing but its own art, so it skips the whole
	# world update below — it only needs its prompt clock running.
	if state == State.LOGO:
		# 다 밝아진 뒤에 무거운 부팅을 한 번에 돌린다. 그 프레임의 delta 는
		# 통째로 로딩 시간이므로 유지 시간에 더하지 않고, 시계를 방금 밝아진
		# 지점으로 되돌려 로고가 제 길이만큼 머물게 한다.
		if boot_pending and logo_elapsed >= LOGO_FADE_IN:
			boot_pending = false
			_boot_load()
			logo_elapsed = LOGO_FADE_IN
			queue_redraw()
			return
		logo_elapsed += delta
		if not boot_pending and logo_elapsed >= LOGO_FADE_IN + LOGO_HOLD + LOGO_FADE_OUT:
			_set_state(State.SPLASH if splash_texture != null else State.MODE_SELECT)
		queue_redraw()
		return
	if state == State.SPLASH:
		splash_elapsed += delta
		splash_char_layer.queue_redraw()
		if splash_exit_elapsed >= 0.0:
			splash_exit_elapsed += delta
			if splash_exit_elapsed >= SPLASH_EXIT_DURATION:
				_set_state(State.MODE_SELECT)
		queue_redraw()
		return
	# Background parallax keeps drifting on every screen (menu, playing,
	# game over) for a lively backdrop, independent of gameplay state.
	var view_size := get_viewport_rect().size
	if bg_texture != null:
		_update_sky_background(delta)
		_update_ambient_particles(delta, view_size)
	else:
		_update_mountains(delta, view_size)
		_update_bg_sparkles(delta, view_size)
		_update_castle(delta, view_size)
		_update_cloud_mid(delta, view_size)
	pause_button.visible = state == State.PLAYING or state == State.COUNTDOWN
	# Re-derived every frame rather than only on state changes: the revive
	# popup opens without one (see _update_mute_button_visibility). LOGO and
	# SPLASH return above, and _apply_screen_visibility covers those on entry.
	_update_mute_button_visibility()
	# Only while actually flying — during the countdown the world is not
	# scrolling yet, and a paused run has a popup over this corner.
	boost_button.visible = state == State.PLAYING and not paused
	if not boost_button.visible:
		# A Button hidden mid-press never emits button_up, which would leave
		# the world accelerated forever after dying with it held down. The
		# release is re-derived here rather than trusted to the signal.
		boost_button_held = false
		# Same reason the alpha has to be put back by hand: without this the
		# button would come back for the next run stuck at its pressed alpha.
		# The press tween has to be killed first or it just repaints it.
		if boost_alpha_tween != null and boost_alpha_tween.is_valid():
			boost_alpha_tween.kill()
		boost_button.modulate.a = BOOST_BUTTON_ALPHA
		# ...and the same for the hold sound, which loops — dying or pausing
		# with the button down would otherwise leave it droning forever.
		if fx_sound_boost != null:
			fx_sound_boost.stop()
	if not paused:
		if state == State.PLAYING:
			_update_playing(delta)
		elif state == State.COUNTDOWN:
			_update_countdown(delta)
		if flash_time > 0.0:
			flash_time = max(0.0, flash_time - delta)
		_update_fx(delta)
		flap_timer += delta
		while flap_timer >= FLAP_FRAME_DURATION and not flap_frames.is_empty():
			flap_timer -= FLAP_FRAME_DURATION
			flap_frame_index = (flap_frame_index + 1) % flap_frames.size()
	queue_redraw()
	if hud_canvas != null:
		hud_canvas.queue_redraw()
	if score_fill_canvas != null:
		score_fill_canvas.queue_redraw()
	if best_fill_canvas != null:
		best_fill_canvas.queue_redraw()


func _update_countdown(delta: float) -> void:
	countdown_timer -= delta
	if countdown_timer > 0.0:
		return
	if countdown_phase == CountdownPhase.READY_TEXT:
		countdown_phase = CountdownPhase.START_TEXT
		countdown_timer = COUNTDOWN_START_DURATION
		if fx_sound_countdown_start.stream != null:
			fx_sound_countdown_start.play()
	else:
		_set_state(State.PLAYING)


func _gate_speed_boost_multiplier() -> float:
	# 1.0 when idle; otherwise holds at full GATE_SPEED_BOOST_PEAK for
	# GATE_SPEED_BOOST_HOLD (so the jolt actually registers instead of
	# being smoothed away instantly), then eases back down to 1.0 over the
	# rest of GATE_SPEED_BOOST_DURATION (cubic ease-out) — the "yanked
	# through, then back to normal" feel.
	if gate_speed_boost_elapsed < 0.0:
		return 1.0
	if gate_speed_boost_elapsed < GATE_SPEED_BOOST_HOLD:
		return GATE_SPEED_BOOST_PEAK
	var decay_span: float = GATE_SPEED_BOOST_DURATION - GATE_SPEED_BOOST_HOLD
	var t: float = (gate_speed_boost_elapsed - GATE_SPEED_BOOST_HOLD) / decay_span
	var eased: float = pow(1.0 - t, 3)
	return 1.0 + (GATE_SPEED_BOOST_PEAK - 1.0) * eased


# What the world actually scrolls at: the gate-pass jolt above, times the
# hold-to-accelerate button. Kept separate from _gate_speed_boost_multiplier
# so that function still means just "the jolt" — the two stack, so passing a
# gate while holding the button still delivers its kick on top.
func _gate_speed_multiplier() -> float:
	return _gate_speed_boost_multiplier() * _boost_hold_multiplier()


# The hold on its own, without the gate-pass jolt — what the background
# scrolls by. The jolt stays excluded from the background (a 3.2x flash on
# the sky every pass reads as a stutter, not as speed); a sustained hold does
# not, which is the whole point of BOOST_BG_SPEED_SHARE.
func _boost_hold_multiplier() -> float:
	return BOOST_BUTTON_MULTIPLIER if boost_button_held else 1.0


func _boost_bg_multiplier() -> float:
	return 1.0 + (_boost_hold_multiplier() - 1.0) * BOOST_BG_SPEED_SHARE


func _update_playing(delta: float) -> void:
	var view_size := get_viewport_rect().size

	player_vel = min(player_vel + gravity * delta, max_fall_speed)
	player_y += player_vel * delta
	var half_h := PLAYER_SIZE.y * 0.5
	var zone_top := _gate_zone_top(view_size)
	var zone_bottom := _gate_zone_bottom(view_size)
	if player_y - half_h < zone_top:
		player_y = zone_top + half_h
		player_vel = 0.0
	elif player_y + half_h > zone_bottom:
		player_y = zone_bottom - half_h
		player_vel = 0.0
		_game_over()
		return

	if gate_speed_boost_elapsed >= 0.0:
		gate_speed_boost_elapsed += delta
		if gate_speed_boost_elapsed >= GATE_SPEED_BOOST_DURATION:
			gate_speed_boost_elapsed = -1.0
	# Plain delta, never scaled by _gate_speed_multiplier — the bar has to
	# drain on the base clock for the leftover to mean anything.
	if boost_bar_elapsed >= 0.0:
		boost_bar_elapsed += delta
	var gate_speed: float = GATE_SPEED * _gate_speed_multiplier()

	for g in gates:
		g.x -= gate_speed * delta
		# Judged where the ring is actually DRAWN, not at the gate's left
		# edge. _draw_gate_frame_layer centres the ring on g.x + GATE_WIDTH/2,
		# so judging on g.x alone resolved the pass a half-gate (65px) before
		# the character reached the hole — the run was already decided while
		# the ring was still visibly ahead, and a last-moment correction came
		# too late to count. Judging on the ring's own centre line puts the
		# verdict where the player sees it happen.
		if not g.resolved and _gate_judge_x(g) <= PLAYER_X:
			_resolve_gate(g, view_size)

	gates = gates.filter(func(g): return g.x + GATE_WIDTH > -10.0)

	# Reveal the next question the instant the active one is cleared (same
	# frame the pass is judged) — no independent timer/cadence in between.
	if state == State.PLAYING and _get_upcoming_target() == "":
		_spawn_gate(view_size)


func _spawn_gate(view_size: Vector2) -> void:
	var phase_index := _get_phase_index(gates_passed)

	# Quiz content: JUNGLE gets a single-digit arithmetic problem (see
	# _make_math_problem/_make_wrong_answer), OCEAN gets a Stroop colour
	# problem (see _make_color_problem); every other mode keeps the flag
	# quiz. Either way this only produces target_code/target_name/
	# other_code — everything below (zone placement, reachability, spacing)
	# is quiz-agnostic and untouched.
	var target_code: String
	var target_name: String
	var other_code: String
	# OCEAN only — the indices the question box needs to repaint this item
	# (see _draw_ocean_quiz_box). Left at -1 for the other two modes, which
	# never read them.
	var ocean_word_index: int = -1
	var ocean_answer_index: int = -1
	if current_mode == Mode.JUNGLE:
		# Re-rolled if it repeats the previous gate's expression — see
		# last_quiz_key. The decoy comes from the problem shape itself now,
		# not from a generic offset (see the _make_*_problem block).
		var problem: Dictionary = _make_math_problem(phase_index)
		for attempt in range(QUIZ_REPEAT_RETRIES):
			if problem.text != last_quiz_key:
				break
			problem = _make_math_problem(phase_index)
		last_quiz_key = problem.text
		target_code = str(problem.answer)
		# The shape supplies the whole question, "= ?" included — the blank
		# is mid-expression for MISSING_OPERAND ("7 + ? = 15"), so it cannot
		# be tacked on here.
		target_name = problem.text
		other_code = str(problem.wrong)
		# A decoy that collides with the answer would put the same number on
		# both gates. The shape-specific decoys are built not to, but they
		# depend on Inspector-tunable ranges, so this is the backstop.
		if other_code == target_code:
			other_code = str(problem.answer + 1)
	elif current_mode == Mode.OCEAN:
		# Difficulty comes from how close the word's own colour and the
		# answer colour sit on the hue circle — see OCEAN_PHASE_HUE_BAND.
		# Re-rolled if the WORD repeats the previous gate's word: the same
		# word twice running reads as a stutter even when the ink changed,
		# and the word is what the player is fighting to ignore. The ink may
		# still repeat — the late phase bands are too narrow to forbid it.
		var color_problem: Dictionary = _make_color_problem(phase_index)
		for attempt in range(QUIZ_REPEAT_RETRIES):
			if OCEAN_COLOR_NAMES[color_problem.word] != last_quiz_key:
				break
			color_problem = _make_color_problem(phase_index)
		last_quiz_key = OCEAN_COLOR_NAMES[color_problem.word]
		ocean_word_index = color_problem.word
		ocean_answer_index = color_problem.answer
		# The answer is the NAME of the colour the word is painted in.
		target_code = OCEAN_COLOR_NAMES[ocean_answer_index]
		# Which trap the wrong gate runs is rolled per question from the
		# phase's mix — see _pick_ocean_decoy. Never equal to target_code
		# whichever branch wins, so the wrong gate is always wrong.
		other_code = OCEAN_COLOR_NAMES[_pick_ocean_decoy(ocean_word_index, ocean_answer_index, phase_index)]
		# Only a fallback for _get_upcoming_target — OCEAN paints its own
		# question box (see _draw_quiz_box's branch) rather than printing
		# this string, but it must stay non-empty for that path's guard.
		target_name = OCEAN_PROMPT_INK
	else:
		# Difficulty curve: the phase shifts WHICH recognition_tier the answer
		# is drawn from — famous flags early, obscure ones late — as a
		# weighted blend rather than a hard tier-per-phase, so a phase reads
		# as a gradual shift instead of a switch. The decoy does not follow
		# that curve at all: it comes from the answer's visual cluster (see
		# _pick_flag_decoy), because a decoy chosen by fame would let the
		# player spot the odd one out without looking at either flag.
		# Re-rolled if it repeats the previous gate's country — see
		# last_quiz_key.
		var target: Dictionary = _pick_flag_target(phase_index)
		for attempt in range(QUIZ_REPEAT_RETRIES):
			if target.is_empty() or str(target.code) != last_quiz_key:
				break
			target = _pick_flag_target(phase_index)
		if target.is_empty():
			return  # no flag data loaded — nothing to ask
		last_quiz_key = str(target.code)
		var other: Dictionary = _pick_flag_decoy(target)
		target_code = target.code
		target_name = target.name
		other_code = other.code if not other.is_empty() else target.code
	var top_correct: bool = randi() % 2 == 0

	var wall_center_y := _gate_wall_center_y(view_size)
	var wall_top := wall_center_y - WALL_THICKNESS * 0.5
	var wall_bottom := wall_center_y + WALL_THICKNESS * 0.5
	var zone_height: float = _gate_ring_inner_zone_height()

	# The decorative pillar frame drawn around a zone is taller than the
	# zone itself — see _gate_frame_top_overhang/
	# _gate_frame_bottom_overhang — so a zone centered too close to the
	# outer edge of the gate zone would push the frame past it (into the
	# HUD/quiz-box buffer, or off the physical screen edge). Rather than
	# clamping the frame's draw position at render time (which would make
	# the drawn "hole" stop matching the actual judged zone), inset the
	# allowed spawn band here so the zone itself never rolls close enough
	# to need that: frame and zone always land in exactly the same place,
	# and the frame can never render above _gate_zone_top.
	var gate_zone_top := _gate_zone_top(view_size)
	var gate_zone_bottom := _gate_zone_bottom(view_size)
	var top_lane_band_top: float = gate_zone_top + max(0.0, _gate_frame_top_overhang() - zone_height * 0.5)
	var bottom_lane_band_bottom: float = gate_zone_bottom - max(0.0, _gate_frame_bottom_overhang() - zone_height * 0.5)

	# base_gate_spacing controls how far ahead of the judgement line a new
	# gate spawns, which is exactly how long the player has to get from the
	# last target into this one.
	var available_time: float = base_gate_spacing / GATE_SPEED
	var up_reach: float = available_time * absf(flap_velocity) * REACH_SAFETY_FACTOR
	var down_reach: float = available_time * max_fall_speed * REACH_SAFETY_FACTOR

	# On top of raw physics reachability, cap consecutive-target movement to
	# a fraction of full screen height so "top then straight to bottom"
	# extremes can't roll even when the physics would technically allow it.
	var move_ratio: float = max_move_ratio_early if phase_index < 2 else max_move_ratio_late
	var max_travel: float = move_ratio * view_size.y
	up_reach = min(up_reach, max_travel)
	down_reach = min(down_reach, max_travel)

	# Both lanes get their own randomized zone (even the wrong one, which is
	# always blocked regardless) so the highlighted strip never gives away
	# which lane is correct — only the text does. Only the CORRECT lane's
	# zone is constrained to be reachable; the decoy has no gameplay effect.
	# The nearest a zone center in the *other* lane could ever be is that
	# lane's own min/max-center (already inset by half its zone height) —
	# not the raw wall coordinate — so use those as the future-reach anchor.
	var bottom_near_edge: float = wall_bottom + zone_height * 0.5
	var top_near_edge: float = wall_top - zone_height * 0.5

	var top_zone: Vector2
	var bottom_zone: Vector2
	if top_correct:
		# Escaping top -> bottom next time needs down_reach; keep this zone
		# within that of the wall so a future lane switch stays reachable.
		top_zone = _random_reachable_zone(top_lane_band_top, wall_top, zone_height, last_zone_center, up_reach, down_reach, bottom_near_edge, down_reach)
		bottom_zone = _random_zone(wall_bottom, bottom_lane_band_bottom, zone_height)
		last_zone_center = (top_zone.x + top_zone.y) * 0.5
	else:
		# Escaping bottom -> top next time needs up_reach (the tighter one).
		bottom_zone = _random_reachable_zone(wall_bottom, bottom_lane_band_bottom, zone_height, last_zone_center, up_reach, down_reach, top_near_edge, up_reach)
		top_zone = _random_zone(top_lane_band_top, wall_top, zone_height)
		last_zone_center = (bottom_zone.x + bottom_zone.y) * 0.5

	var top_code: String = target_code if top_correct else other_code
	var bottom_code: String = other_code if top_correct else target_code

	# Code-level correctness check (per spec): the quiz box always shows
	# target_name, so the gate in the correct lane must carry that exact
	# same code, not just a name/text that happens to match.
	var correct_lane_code: String = top_code if top_correct else bottom_code
	assert(correct_lane_code == target_code, "Quiz target code and correct-lane gate code must match")

	var gate := {
		"x": PLAYER_X + base_gate_spacing,
		"top_code": top_code,
		"bottom_code": bottom_code,
		"top_correct": top_correct,
		"target_code": target_code,
		"target_name": target_name,
		"resolved": false,
		"top_zone_top": top_zone.x,
		"top_zone_bottom": top_zone.y,
		"bottom_zone_top": bottom_zone.x,
		"bottom_zone_bottom": bottom_zone.y,
	}
	# OCEAN carries its Stroop item on the gate itself — the question box
	# repaints the word from these every frame the gate is the pending one.
	if current_mode == Mode.OCEAN:
		gate["ocean_word_index"] = ocean_word_index
		gate["ocean_answer_index"] = ocean_answer_index
	gates.append(gate)
	_start_boost_bar(gate)


func _random_zone(band_top: float, band_bottom: float, zone_height: float) -> Vector2:
	var min_center := band_top + zone_height * 0.5
	var max_center := band_bottom - zone_height * 0.5
	if max_center < min_center:
		var mid := (band_top + band_bottom) * 0.5
		return Vector2(mid - zone_height * 0.5, mid + zone_height * 0.5)
	var center := randf_range(min_center, max_center)
	return Vector2(center - zone_height * 0.5, center + zone_height * 0.5)


func _random_reachable_zone(band_top: float, band_bottom: float, zone_height: float, anchor_y: float, up_reach: float, down_reach: float, near_wall_edge: float, future_reach: float) -> Vector2:
	var min_center := band_top + zone_height * 0.5
	var max_center := band_bottom - zone_height * 0.5
	if max_center < min_center:
		var mid := (band_top + band_bottom) * 0.5
		return Vector2(mid - zone_height * 0.5, mid + zone_height * 0.5)

	var anchor_min: float = max(min_center, anchor_y - up_reach)
	var anchor_max: float = min(max_center, anchor_y + down_reach)
	if anchor_min > anchor_max:
		# Not even immediately reachable from the previous zone (e.g. it
		# sat at the far edge of the other lane) — best-effort clamp within
		# this band rather than leaving a genuinely unreachable gap.
		var nearest: float = clampf(anchor_y, min_center, max_center)
		return Vector2(nearest - zone_height * 0.5, nearest + zone_height * 0.5)

	# Also stay close enough to the wall that a future switch to the other
	# lane remains reachable from here — otherwise a zone placed deep in
	# this lane could make the *next* gate's opposite-lane zone impossible.
	var reach_min: float = max(anchor_min, near_wall_edge - future_reach)
	var reach_max: float = min(anchor_max, near_wall_edge + future_reach)
	if reach_min > reach_max:
		# Future reachability conflicts with immediate reachability — this
		# frame's judgement takes priority, so clamp toward the wall within
		# whatever is immediately reachable instead of abandoning the
		# future-reach preference entirely.
		var nearest2: float = clampf(near_wall_edge, anchor_min, anchor_max)
		return Vector2(nearest2 - zone_height * 0.5, nearest2 + zone_height * 0.5)

	var center := randf_range(reach_min, reach_max)
	return Vector2(center - zone_height * 0.5, center + zone_height * 0.5)


# Which phase a run is in, 0-based, from the number of gates already passed.
# passed_count is how many are BEHIND you, so the gate being generated is
# number passed_count + 1 — which is why phase 1 covering "gates 1-10" means
# passed_count 0..9 here.
#
# Guarded rather than trusting phase_gate_counts, since it is an @export the
# Inspector can put anything into: non-positive lengths would make a phase
# zero-width and silently skip it, so they are ignored. An empty array (or
# one of nothing but junk) leaves every gate in phase 1, which is a sane
# reading of "no ramp configured" and never an out-of-range index.
func _get_phase_index(passed_count: int) -> int:
	var boundary := 0
	for i in range(phase_gate_counts.size()):
		var length: int = phase_gate_counts[i]
		if length <= 0:
			continue
		boundary += length
		if passed_count < boundary:
			return i
	# Past every listed phase — the last one, which runs unbounded.
	return _phase_count() - 1


# Number of phases the curve describes: one more than the lengths given,
# because the final phase is open-ended. Always at least 1.
func _phase_count() -> int:
	var listed := 0
	for length in phase_gate_counts:
		if length > 0:
			listed += 1
	return listed + 1


# ---- SKY mode's flag quiz (see _spawn_gate) ----

# Rolls a recognition_tier for this phase, then a country from it. Tiers with
# no countries loaded are skipped rather than rolled and retried, so a weight
# pointing at an empty tier costs nothing.
func _pick_flag_target(phase_index: int) -> Dictionary:
	var curves: Array = [flag_weight_tier1, flag_weight_tier2, flag_weight_tier3, flag_weight_tier4]
	var weights: Array[float] = []
	var total: float = 0.0
	for i in range(curves.size()):
		var curve: PackedFloat32Array = curves[i]
		var pool: Array = flag_records_by_tier.get(i + 1, [])
		var w: float = 0.0
		if not curve.is_empty() and not pool.is_empty():
			# A curve shorter than the phase count holds its last value, so
			# trimming it in the Inspector cannot silently empty a phase.
			w = maxf(0.0, curve[clampi(phase_index, 0, curve.size() - 1)])
		weights.append(w)
		total += w
	if total <= 0.0:
		# Nothing configured (or nothing loaded) for this phase — any country
		# beats no question at all.
		return flag_records[randi() % flag_records.size()] if not flag_records.is_empty() else {}
	var roll: float = randf() * total
	for i in range(weights.size()):
		roll -= weights[i]
		if roll < 0.0:
			var pool: Array = flag_records_by_tier[i + 1]
			return pool[randi() % pool.size()]
	return flag_records[randi() % flag_records.size()]


# The decoy: a flag that LOOKS like the answer, drawn from its
# confusion_cluster_id and nothing else — the answer's own tier and the
# phase are both ignored, per the design. 105 of the 193 sit in a visual
# cluster; the rest have no twin worth trapping with, and fall back to a
# plain different country.
func _pick_flag_decoy(target: Dictionary) -> Dictionary:
	var cluster: String = str(target.get("confusion_cluster_id", ""))
	var siblings: Array = flag_records_by_cluster.get(cluster, [])
	if siblings.size() >= 2:
		# Pick any sibling but the answer itself — index-shifted rather than
		# retried, so a two-country cluster resolves in one step.
		var target_at: int = siblings.find(target)
		var pick: int = randi() % (siblings.size() - 1)
		if target_at >= 0 and pick >= target_at:
			pick += 1
		return siblings[pick]
	# No cluster (or a cluster of one): any other country.
	if flag_records.size() < 2:
		return {}
	var target_index: int = flag_records.find(target)
	var other: int = randi() % (flag_records.size() - 1)
	if target_index >= 0 and other >= target_index:
		other += 1
	return flag_records[other]


# ---- JUNGLE mode's math quiz (see _spawn_gate) ----
# Each _make_*_problem below returns {text, answer, wrong}: the shape decides
# its own decoy, because a good decoy is the specific mistake that shape
# invites — a dropped carry in a column sum, a neighbouring times-table row,
# an inverted operation. A generic "answer ± 2" cannot express any of that.
#
# Real × rather than ASCII "x": Fredoka covers it, verified against the font.

# Weight of each MathKind for this phase, in enum order.
func _math_kind_weights(phase_index: int) -> Array[float]:
	var curves: Array = [
		math_weight_single_add_sub,
		math_weight_double_plain,
		math_weight_times_table,
		math_weight_double_carry,
		math_weight_double_x_single,
		math_weight_missing_operand,
	]
	var out: Array[float] = []
	for curve in curves:
		# A curve shorter than the phase count holds its last value rather
		# than reading as zero, so trimming the array in the Inspector can
		# never silently empty out a late phase.
		if curve.is_empty():
			out.append(0.0)
		else:
			out.append(maxf(0.0, curve[clampi(phase_index, 0, curve.size() - 1)]))
	return out


func _pick_math_kind(phase_index: int) -> int:
	var weights: Array[float] = _math_kind_weights(phase_index)
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return MathKind.SINGLE_ADD_SUB  # nothing configured for this phase — fall back to the gentlest shape
	var roll: float = randf() * total
	for i in range(weights.size()):
		roll -= weights[i]
		if roll < 0.0:
			return i
	return MathKind.SINGLE_ADD_SUB


func _make_math_problem(phase_index: int) -> Dictionary:
	match _pick_math_kind(phase_index):
		MathKind.DOUBLE_ADD_SUB_PLAIN:
			return _make_double_add_sub(false)
		MathKind.TIMES_TABLE:
			return _make_times_table()
		MathKind.DOUBLE_ADD_SUB_CARRY:
			return _make_double_add_sub(true)
		MathKind.DOUBLE_X_SINGLE:
			return _make_double_x_single()
		MathKind.MISSING_OPERAND:
			return _make_missing_operand()
		_:
			return _make_single_add_sub()


# 한자리 덧셈/뺄셈 — both operands single-digit AND the result capped, so
# this stays the shape a young player can do at a glance.
func _make_single_add_sub() -> Dictionary:
	var cap: int = maxi(1, math_single_max_result)
	if randi() % 2 == 0:
		var a: int = randi_range(1, mini(9, cap - 1))
		var b: int = randi_range(1, mini(9, cap - a))
		# Off by one in the units column — the mistake this shape invites.
		return {"text": "%d + %d = ?" % [a, b], "answer": a + b, "wrong": a + b + (1 if randi() % 2 == 0 else -1)}
	var x: int = randi_range(2, mini(9, cap))
	var y: int = randi_range(1, x - 1)
	return {"text": "%d - %d = ?" % [x, y], "answer": x - y, "wrong": maxi(0, x - y + (1 if randi() % 2 == 0 else -1))}


# 두자리 덧셈/뺄셈. `with_carry` picks whether the units column carries (or
# borrows) — which is exactly what the decoy then gets wrong, landing 10 off.
# Without a carry there is no carry to drop, so those decoys miss by 1 in a
# column instead.
func _make_double_add_sub(with_carry: bool) -> Dictionary:
	var lo: int = mini(math_double_range.x, math_double_range.y)
	var hi: int = maxi(math_double_range.x, math_double_range.y)
	lo = maxi(10, lo)
	hi = clampi(hi, lo, 99)
	if randi() % 2 == 0:
		# Addition. Build it column-wise so the carry is decided, not hoped for.
		var a_units: int = randi_range(5, 9) if with_carry else randi_range(0, 4)
		var b_units: int = randi_range(10 - a_units, 9) if with_carry else randi_range(0, 4 - mini(a_units, 4))
		var a_tens: int = randi_range(lo / 10, mini(hi / 10, 8))
		var b_tens: int = randi_range(1, mini(9 - a_tens, hi / 10))
		var a: int = a_tens * 10 + a_units
		var b: int = maxi(10, b_tens * 10 + b_units)
		var sum: int = a + b
		# The classic column error: 10 away, from dropping the carry. Always
		# DOWN, never up — a decoy above the sum can spill into three digits
		# (61 + 31 -> 102), and a decoy with more digits than the answer is
		# dismissable at a glance without doing the sum at all.
		var wrong: int = sum - 10
		return {"text": "%d + %d = ?" % [a, b], "answer": sum, "wrong": maxi(0, wrong)}
	# Subtraction, same idea: force (or forbid) a borrow in the units column.
	var top_units: int = randi_range(0, 4) if with_carry else randi_range(5, 9)
	var bot_units: int = randi_range(top_units + 1, 9) if with_carry else randi_range(0, top_units)
	var top_tens: int = randi_range(maxi(2, lo / 10), mini(hi / 10, 9))
	var bot_tens: int = randi_range(1, top_tens - 1)
	var top: int = top_tens * 10 + top_units
	var bot: int = bot_tens * 10 + bot_units
	var diff: int = top - bot
	var wrong_diff: int = diff + 10 if with_carry else diff - 10  # forgot to borrow / borrowed anyway
	return {"text": "%d - %d = ?" % [top, bot], "answer": diff, "wrong": maxi(0, wrong_diff)}


# 구구단. The decoy is a genuine neighbouring product — one row or one column
# away — so it is a number that really does live in the times table, not an
# arbitrary near miss.
func _make_times_table() -> Dictionary:
	var lo: int = mini(math_times_table_range.x, math_times_table_range.y)
	var hi: int = maxi(math_times_table_range.x, math_times_table_range.y)
	lo = clampi(lo, 1, 9)
	hi = clampi(hi, lo, 9)
	var a: int = randi_range(lo, hi)
	var b: int = randi_range(lo, hi)
	var answer: int = a * b
	var neighbours: Array[int] = []
	for delta in [-1, 1]:
		if a + delta >= 1 and a + delta <= 9:
			neighbours.append((a + delta) * b)
		if b + delta >= 1 and b + delta <= 9:
			neighbours.append(a * (b + delta))
	neighbours = neighbours.filter(func(n: int) -> bool: return n != answer)
	var wrong: int = neighbours[randi() % neighbours.size()] if not neighbours.is_empty() else answer + 1
	return {"text": "%d × %d = ?" % [a, b], "answer": answer, "wrong": wrong}


# 두자리 x 한자리. The decoy drops the carry out of the units column, which is
# the error this shape actually produces when done in the head.
func _make_double_x_single() -> Dictionary:
	var lo: int = clampi(mini(math_double_range.x, math_double_range.y), 10, 99)
	var hi: int = clampi(maxi(math_double_range.x, math_double_range.y), lo, 99)
	var f_lo: int = clampi(mini(math_single_factor_range.x, math_single_factor_range.y), 2, 9)
	var f_hi: int = clampi(maxi(math_single_factor_range.x, math_single_factor_range.y), f_lo, 9)
	var a: int = randi_range(lo, hi)
	var b: int = randi_range(f_lo, f_hi)
	var answer: int = a * b
	# What you get by multiplying each column and forgetting to carry.
	var no_carry: int = (a / 10) * b * 10 + ((a % 10) * b) % 10
	var wrong: int = no_carry if no_carry != answer and no_carry > 0 else answer + 10
	return {"text": "%d × %d = ?" % [a, b], "answer": answer, "wrong": wrong}


# 빈칸추론 — 7 + ? = 15. The decoy is the operation run the wrong way: adding
# where you should subtract, which is the mistake the blank invites.
func _make_missing_operand() -> Dictionary:
	var cap: int = clampi(maxi(math_double_range.x, math_double_range.y), 20, 99)
	if randi() % 2 == 0:
		# a + ? = c   ->   ? = c - a, wrong = c + a (added instead)
		var a: int = randi_range(2, cap / 2)
		var missing: int = randi_range(2, cap / 2)
		var c: int = a + missing
		return {"text": "%d + ? = %d" % [a, c], "answer": missing, "wrong": a + c}
	# ? - b = c   ->   ? = c + b, wrong = c - b (subtracted instead).
	# c is kept above b so that wrong stays a positive, plausible number: a
	# decoy clamped to 0 is no trap at all, it is instantly dismissable.
	var b: int = randi_range(2, maxi(3, cap / 3))
	var c2: int = randi_range(b + 1, maxi(b + 2, cap / 2))
	var missing2: int = c2 + b
	return {"text": "? - %d = %d" % [b, c2], "answer": missing2, "wrong": c2 - b}


# ---- OCEAN mode's Stroop colour quiz (see _spawn_gate) ----
# Generation only — the drawing lives in _draw_ocean_quiz_box.

# Perceptual distance between two entries of the colour table, on a single
# 0..OCEAN_HUE_DISTANCE_MAX scale so one phase band can gate every pair.
func _ocean_color_distance(a: int, b: int) -> float:
	var hue_a: float = OCEAN_COLOR_HUES[a]
	var hue_b: float = OCEAN_COLOR_HUES[b]
	var a_neutral: bool = hue_a == OCEAN_HUE_NONE
	var b_neutral: bool = hue_b == OCEAN_HUE_NONE
	if a_neutral and b_neutral:
		# Hue says nothing about black vs white vs gray — lightness is the
		# only axis they differ on, so stretch that gap onto the same scale.
		# Black/white land far apart (easy), black/gray land mid (harder).
		return absf(OCEAN_COLOR_LIGHTNESS[a] - OCEAN_COLOR_LIGHTNESS[b]) * OCEAN_HUE_DISTANCE_MAX
	if a_neutral or b_neutral:
		# A neutral against a chromatic is as far apart as this scale goes:
		# there is no hue confusion to be had between "gray" and "orange".
		return OCEAN_HUE_DISTANCE_MAX
	var d: float = absf(hue_a - hue_b)
	return d if d <= 180.0 else 360.0 - d


# Rolls one Stroop item for the given phase. Returns indices into
# OCEAN_COLOR_NAMES: `word` is the text shown, `answer` is the colour it is
# actually painted in (INK_COLOR) or sat on (BACKGROUND_COLOR). The two are
# never equal, so every item traps.
func _make_color_problem(phase_index: int) -> Dictionary:
	var band: Vector2 = OCEAN_PHASE_HUE_BAND[clampi(phase_index, 0, OCEAN_PHASE_HUE_BAND.size() - 1)]
	var in_band: Array = []
	# Every pair that missed the band by the same smallest amount, kept as
	# the fallback so a band with no legal pair still yields the closest
	# thing to the intended difficulty rather than nothing at all.
	var nearest: Array = []
	var nearest_miss: float = INF
	for word in range(OCEAN_COLOR_NAMES.size()):
		for answer in range(OCEAN_COLOR_NAMES.size()):
			if word == answer:
				continue  # never congruent — the trap is the whole quiz
			var d: float = _ocean_color_distance(word, answer)
			if d >= band.x and d <= band.y:
				in_band.append(Vector2i(word, answer))
				continue
			var miss: float = (band.x - d) if d < band.x else (d - band.y)
			if miss < nearest_miss - 0.01:
				nearest_miss = miss
				nearest = [Vector2i(word, answer)]
			elif absf(miss - nearest_miss) <= 0.01:
				nearest.append(Vector2i(word, answer))
	var pool: Array = in_band if not in_band.is_empty() else nearest
	var pick: Vector2i = pool[randi() % pool.size()]
	return {"word": pick.x, "answer": pick.y}


# The palette colour sitting closest to `answer` on the hue circle, the
# answer itself excluded. Basis of the NEAREST_HUE trap: near enough that a
# glance at the ink won't separate them, so you have to actually look.
func _ocean_nearest_hue(answer_index: int) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i in range(OCEAN_COLOR_NAMES.size()):
		if i == answer_index:
			continue
		var d: float = _ocean_color_distance(answer_index, i)
		if d < best_distance:
			best_distance = d
			best = i
	return best


# Rolls which of the three traps this question's wrong gate runs, then
# returns the colour index to print on it. Never returns `answer_index` —
# whichever branch wins, the wrong gate must stay wrong.
func _pick_ocean_decoy(word_index: int, answer_index: int, phase_index: int) -> int:
	var weights := Vector3(1.0, 0.0, 0.0)  # all-zero/empty table degrades to the word-meaning trap
	if not ocean_decoy_weights_by_phase.is_empty():
		weights = ocean_decoy_weights_by_phase[clampi(phase_index, 0, ocean_decoy_weights_by_phase.size() - 1)]
	# Negative weights would silently eat the roll, so floor each at zero
	# rather than trusting whatever got typed into the Inspector.
	var w_word: float = maxf(0.0, weights.x)
	var w_near: float = maxf(0.0, weights.y)
	var w_random: float = maxf(0.0, weights.z)
	var total: float = w_word + w_near + w_random
	var kind: int = OceanDecoy.WORD_MEANING
	if total > 0.0:
		var roll: float = randf() * total
		if roll < w_word:
			kind = OceanDecoy.WORD_MEANING
		elif roll < w_word + w_near:
			kind = OceanDecoy.NEAREST_HUE
		else:
			kind = OceanDecoy.RANDOM

	match kind:
		OceanDecoy.WORD_MEANING:
			return word_index
		OceanDecoy.NEAREST_HUE:
			# Can coincide with the word — most often late on, where the
			# phase band already pulls the word's own colour in tight around
			# the answer. That is not a bug: the option is still a valid
			# wrong answer, it just happens to be running both traps at once.
			return _ocean_nearest_hue(answer_index)
		_:
			# Neither trap, per spec — and never the answer, which would
			# make the wrong gate right.
			var nearest_index: int = _ocean_nearest_hue(answer_index)
			var candidates: Array[int] = []
			for i in range(OCEAN_COLOR_NAMES.size()):
				if i != answer_index and i != word_index and i != nearest_index:
					candidates.append(i)
			if candidates.is_empty():
				return word_index  # unreachable with 11 colours; keeps the return total
			return candidates[randi() % candidates.size()]


# The x at which a gate is judged: the ring's own centre line, matching
# where _draw_gate_frame_layer draws it. One definition, used by both the
# judgement in _update_playing and the debug overlay, so the line drawn is
# always the line judged.
func _gate_judge_x(g: Dictionary) -> float:
	return g.x + GATE_WIDTH * 0.5


# ---- Boost bonus bar (see the BOOST_BAR_* consts) ----

func _start_boost_bar(gate: Dictionary) -> void:
	# T_base measured off the gate that was just spawned rather than off
	# base_gate_spacing, so it stays correct if the spawn point or the judge
	# offset ever moves — it is by definition the distance this gate still
	# has to cover, at the base rate.
	var distance: float = _gate_judge_x(gate) - PLAYER_X
	boost_bar_duration = distance / GATE_SPEED if GATE_SPEED > 0.0 else 0.0
	boost_bar_elapsed = 0.0


func _boost_bar_remaining() -> float:
	if boost_bar_elapsed < 0.0 or boost_bar_duration <= 0.0:
		return 1.0
	return clampf(1.0 - boost_bar_elapsed / boost_bar_duration, 0.0, 1.0)


func _boost_bonus_multiplier(remaining: float) -> float:
	if remaining >= boost_bonus_best_threshold:
		return boost_bonus_best_multiplier
	if remaining >= boost_bonus_mid_threshold:
		return boost_bonus_mid_multiplier
	return boost_bonus_none_multiplier


func _boost_bar_fill_texture(remaining: float) -> Texture2D:
	var index: int = 0
	if remaining >= boost_bonus_best_threshold:
		index = 2
	elif remaining >= boost_bonus_mid_threshold:
		index = 1
	return boost_bar_fill_textures[index] if index < boost_bar_fill_textures.size() else null


func _boost_bar_zone_color(remaining: float) -> Color:
	if remaining >= boost_bonus_best_threshold:
		return BOOST_BAR_ZONE_BEST_COLOR
	if remaining >= boost_bonus_mid_threshold:
		return BOOST_BAR_ZONE_MID_COLOR
	return BOOST_BAR_ZONE_NONE_COLOR


# The combo readout's worst-case footprint: widest of its two lines, at the
# punch's peak scale, lifted by the punch's rise. Empty when nothing shows.
func _combo_display_rect(view_size: Vector2) -> Rect2:
	if combo <= 0:
		return Rect2()
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var tier := _combo_tier(combo)
	var number_size: int = int(round(COMBO_TIER_FONT_SIZES[tier] * POP_PEAK_SCALE))
	var label_size: int = int(round(COMBO_TIER_FONT_SIZES[tier] * 0.55 * POP_PEAK_SCALE))
	var number := font.get_string_size("x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size)
	var label := font.get_string_size("COMBO!", HORIZONTAL_ALIGNMENT_LEFT, -1, label_size)
	var widest: float = maxf(number.x, label.x)
	var top: float = _gate_zone_top(view_size) + COMBO_DISPLAY_MARGIN.y - COMBO_TIER_RISE[tier]
	return Rect2(
		Vector2(view_size.x - COMBO_DISPLAY_MARGIN.x - widest, top),
		Vector2(widest, number.y * 1.75 + label.y))


# Resolves the popup's final geometry from its anchor and the string it has
# to fit. Split out of _draw_boost_pop so tools/check_popup_overlap.gd can
# drive the real thing instead of re-deriving a copy that could drift.
func _boost_pop_layout(view_size: Vector2, text: String, is_best: bool, anchor: Vector2, font_scale: float) -> Dictionary:
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var nominal: int = BOOST_POP_FONT_SIZE_BEST if is_best else BOOST_POP_FONT_SIZE_MID
	var glow: float = BOOST_POP_GLOW_RADIUS if is_best else 0.0
	var edge_pad: float = BOOST_POP_SCREEN_MARGIN + glow
	# Left-anchored beside the character, so its room is whatever lies
	# between the anchor and the right edge — shrink to fit that.
	var max_width: float = maxf(view_size.x - edge_pad - anchor.x, 0.0)
	var font_size: int = _fit_font_size(text, max_width,
		maxi(int(round(nominal * font_scale)), 1), BOOST_POP_MIN_FONT_SIZE, font)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var left: float = clampf(anchor.x, edge_pad, maxf(view_size.x - edge_pad - size.x, edge_pad))
	var top: float = anchor.y - size.y * 0.5
	# A pass taken high in the zone puts this straight over the combo
	# readout's corner — drop below it rather than stack on it.
	var combo_rect := _combo_display_rect(view_size)
	if combo_rect.size.x > 0.0 \
			and Rect2(Vector2(left - glow, top - glow), size + Vector2(glow, glow) * 2.0).intersects(combo_rect):
		top = combo_rect.end.y + BOOST_POP_COMBO_GAP + glow
	# Held inside the gate zone, not merely on-screen: a pass taken high in
	# the lane would otherwise put the text up over the quiz box and the
	# boost bar that sit in the band above it.
	var zone_top: float = _gate_zone_top(view_size) + glow
	var zone_bottom: float = _gate_zone_bottom(view_size) - BOOST_POP_SCREEN_MARGIN - size.y - glow
	top = clampf(top, zone_top, maxf(zone_bottom, zone_top))
	return {
		"font": font,
		"font_size": font_size,
		"size": size,
		"pos": Vector2(left, top),
		"rect": Rect2(Vector2(left - glow, top - glow), size + Vector2(glow, glow) * 2.0),
	}


func _spawn_boost_pop(points: int, remaining: float, view_size: Vector2) -> void:
	boost_pop_is_best = remaining >= boost_bonus_best_threshold
	# The tier decides the wording, the size, the colour and how much
	# confetti — all from the one bool, so the two tiers can never drift into
	# saying different things.
	boost_pop_text = ("BOOST!! +%d" if boost_pop_is_best else "BOOST! +%d") % points
	boost_pop_color = BOOST_BAR_ZONE_BEST_COLOR if boost_pop_is_best else BOOST_BAR_ZONE_MID_COLOR
	boost_pop_font_size = BOOST_POP_FONT_SIZE_BEST if boost_pop_is_best else BOOST_POP_FONT_SIZE_MID
	boost_pop_elapsed = 0.0
	# Captured now, held for the popup's whole life — see the BOOST_POP_*
	# header for why this does not track the character.
	boost_pop_anchor = Vector2(PLAYER_X, player_y) + BOOST_POP_CHARACTER_OFFSET
	var count: Vector2i = BOOST_POP_BURST_COUNT_BEST if boost_pop_is_best else BOOST_POP_BURST_COUNT_MID
	_spawn_spark_burst(boost_pop_anchor, count, BOOST_POP_BURST_SIZE_RANGE,
		fx_burst_textures, FX_SPARK_SPEED_RANGE, FX_SPARK_LIFETIME_RANGE, BOOST_POP_BURST_RADIUS)


func _draw_boost_pop(view_size: Vector2) -> void:
	if boost_pop_elapsed < 0.0 or boost_pop_text.is_empty():
		return
	var t: float = clampf(boost_pop_elapsed / BOOST_POP_DURATION, 0.0, 1.0)
	# Same overshoot-then-settle curve the combo punch and the countdown use,
	# so all three popups move in one language.
	var scale: float = _pop_scale(t)
	# Cubic hold-then-drop rather than a linear fade: at 0.45s a linear fade
	# is already visibly dimming while the text is still arriving.
	var alpha: float = clampf(1.0 - pow(t, 3), 0.0, 1.0)
	# Rise is applied to the anchor, not to the finished position, so the
	# combo-collision test in _boost_pop_layout sees where it will actually be.
	var anchor: Vector2 = boost_pop_anchor + Vector2(0.0, -BOOST_POP_RISE * sin(t * PI))
	var layout := _boost_pop_layout(view_size, boost_pop_text, boost_pop_is_best, anchor, scale)
	var font: Font = layout["font"]
	var font_size: int = layout["font_size"]
	# layout["pos"] is the text block's top-left; draw_string wants a baseline.
	var draw_pos: Vector2 = layout["pos"] + Vector2(0.0, font.get_ascent(font_size))

	if boost_pop_is_best:
		var glow := Color(boost_pop_color.r, boost_pop_color.g, boost_pop_color.b, BOOST_POP_GLOW_ALPHA * alpha)
		for i in range(BOOST_POP_GLOW_PASSES):
			var angle: float = TAU * float(i) / float(BOOST_POP_GLOW_PASSES)
			var offset := Vector2(cos(angle), sin(angle)) * BOOST_POP_GLOW_RADIUS
			draw_string(font, draw_pos + offset, boost_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow)

	var outline_col := Color(COLOR_TEXT_OUTLINE.r, COLOR_TEXT_OUTLINE.g, COLOR_TEXT_OUTLINE.b, COLOR_TEXT_OUTLINE.a * alpha)
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, draw_pos + offset, boost_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_col)
	draw_string(font, draw_pos, boost_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(boost_pop_color.r, boost_pop_color.g, boost_pop_color.b, alpha))


func _boost_bar_rect(view_size: Vector2) -> Rect2:
	var box := _quiz_box_rect(view_size)
	return Rect2(
		Vector2(box.position.x + BOOST_BAR_SIDE_MARGIN, box.end.y + BOOST_BAR_GAP),
		Vector2(maxf(box.size.x - BOOST_BAR_SIDE_MARGIN * 2.0, 0.0), BOOST_BAR_HEIGHT))


func _resolve_gate(g: Dictionary, view_size: Vector2) -> void:
	g.resolved = true
	var wall_center_y := _gate_wall_center_y(view_size)
	var wall_top := wall_center_y - WALL_THICKNESS * 0.5
	var wall_bottom := wall_center_y + WALL_THICKNESS * 0.5
	var half_h := PLAYER_SIZE.y * 0.5
	var p_top := player_y - half_h
	var p_bottom := player_y + half_h

	if p_bottom > wall_top and p_top < wall_bottom:
		_game_over()
		return

	var in_top := player_y < wall_center_y
	var in_correct_lane: bool = (in_top and g.top_correct) or (not in_top and not g.top_correct)

	# Being in the correct lane is necessary but not sufficient — you must
	# also be inside that lane's precision zone this gate rolled.
	var passed: bool
	if not in_correct_lane:
		passed = false
	else:
		var zone_top: float = g.top_zone_top if in_top else g.bottom_zone_top
		var zone_bottom: float = g.top_zone_bottom if in_top else g.bottom_zone_bottom
		passed = p_top >= zone_top and p_bottom <= zone_bottom

	if passed:
		gates_passed += 1
		combo += 1
		# combo is zeroed by any miss, so the run's peak has to be kept
		# separately — the game-over popup reports the peak, not what was
		# left standing at the end.
		max_combo = maxi(max_combo, combo)
		# Read before _spawn_gate refills the bar for the next gate — that
		# happens later in the same _update_playing pass, once this one is
		# resolved.
		var remaining: float = _boost_bar_remaining()
		var boost_multiplier: float = _boost_bonus_multiplier(remaining)
		# combo was incremented just above, so the first gate of a run scores
		# SCORE_PER_COMBO x 1 — the multiplier is the only thing the boost
		# bar adds on top.
		var base_points: int = SCORE_PER_COMBO * combo
		var gained: int = int(round(base_points * (1.0 + boost_multiplier)))
		score += gained
		boost_bar_flash_color = _boost_bar_zone_color(remaining)
		boost_bar_flash_elapsed = 0.0
		# What the popup reports: the difference the multiplier actually made
		# on THIS gate, derived from the same two numbers that moved the
		# score — never a fixed per-tier figure.
		var bonus_points: int = gained - base_points
		if bonus_points > 0:
			_spawn_boost_pop(bonus_points, remaining, view_size)
		flash_color = Color(0.3, 0.8, 0.4, 0.35)
		flash_time = FLASH_DURATION
		gate_speed_boost_elapsed = 0.0
		_play_gate_success_fx(g, in_top)
		_spawn_combo_popup(view_size)
	else:
		_game_over()


# ============================================================
# Gate-pass success FX. Called once from _resolve_gate() above, right where
# `passed` is already known true — never reads or writes player_y/vel,
# gravity, gate x/speed, or any zone bound. Pure cosmetics layered on top.
# ============================================================
func _play_gate_success_fx(g: Dictionary, in_top: bool) -> void:
	g["fx_flash_side"] = "top" if in_top else "bottom"
	g["fx_flash_elapsed"] = 0.0
	happy_flap_elapsed = 0.0

	var zone_top: float = g.top_zone_top if in_top else g.bottom_zone_top
	var zone_bottom: float = g.top_zone_bottom if in_top else g.bottom_zone_bottom
	var gate_center := Vector2(g.x + GATE_WIDTH * 0.5, (zone_top + zone_bottom) * 0.5)

	# 0ms: impact flash + gate punch/crystal flash (driven by fx_flash_elapsed
	# above, sampled in _draw()) + big spark burst + both sound hooks.
	_spawn_impact_flash(gate_center)
	_spawn_spark_burst(gate_center, FX_SPARK_BURST_A_COUNT_RANGE, FX_SPARK_BURST_A_SIZE_RANGE, fx_burst_textures)
	# 30-50ms: small spark burst + speed streaks, fired together once this
	# pending entry's delay elapses (see _update_fx).
	fx_pending_bursts.append({
		"delay": randf_range(FX_SPARK_BURST_B_DELAY_RANGE.x, FX_SPARK_BURST_B_DELAY_RANGE.y),
		"gate_center": gate_center,
	})
	fx_shake_elapsed = 0.0
	fx_stretch_elapsed = 0.0
	_play_gate_success_sound()


func _spawn_impact_flash(gate_center: Vector2) -> void:
	var frame_outer_radius: float = (GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) * 0.5
	fx_impact_flashes.append({
		"pos": gate_center,
		"radius": frame_outer_radius + FX_IMPACT_FLASH_MARGIN,
		"elapsed": 0.0,
	})


func _spawn_spark_burst(gate_center: Vector2, count_range: Vector2i, scale_range: Vector2, texture_pool: Array[Texture2D], speed_range: Vector2 = FX_SPARK_SPEED_RANGE, lifetime_range: Vector2 = FX_SPARK_LIFETIME_RANGE, spawn_radius_override: float = -1.0) -> void:
	if texture_pool.is_empty():
		return
	# Default ring sits outside the gate frame's own edge — right for a gate
	# pass, far too wide for a burst around a line of text, which is what the
	# override is for.
	var ring_radius: float
	if spawn_radius_override >= 0.0:
		ring_radius = spawn_radius_override
	else:
		var frame_outer_radius: float = (GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) * 0.5
		ring_radius = frame_outer_radius + FX_SPARK_RING_MARGIN
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	var count: int = int(round(randi_range(count_range.x, count_range.y) * strength))
	for i in range(count):
		# Angled outward from gate_center (the zone center the bird just
		# passed through), starting at the ring outside the frame's own
		# edge — spreads toward the gate's outer boundary, not over the
		# bird's face/body which sits back near gate_center itself.
		var angle: float = randf_range(0.0, TAU)
		var dir := Vector2(cos(angle), sin(angle))
		var dist: float = ring_radius * randf_range(0.9, 1.15)
		var speed: float = randf_range(speed_range.x, speed_range.y) * strength
		var texture: Texture2D = texture_pool[randi() % texture_pool.size()]
		# scale_range is a target size in px, not a multiplier: the sparkle
		# sheet ships each shape at its own resolution, so normalise by the
		# texture's longest edge or the shape the RNG picked would decide how
		# big the particle came out. See FX_SPARK_BURST_A_SIZE_RANGE.
		var longest: float = maxf(texture.get_width(), texture.get_height())
		var spark_scale: float = randf_range(scale_range.x, scale_range.y)
		spark_scale = spark_scale / longest if longest > 0.0 else 0.0
		fx_sparks.append({
			"pos": gate_center + dir * dist,
			"vel": dir * speed,
			"scale": spark_scale * clampf(strength, 0.3, 2.0),
			# Near-upright, like the trail: these are 4-point stars, and a
			# fully random angle just smears them.
			"rotation": randf_range(-TRAIL_ROTATION_JITTER, TRAIL_ROTATION_JITTER),
			"lifetime": randf_range(lifetime_range.x, lifetime_range.y),
			"elapsed": 0.0,
			"texture": texture,
		})


func _spawn_speed_lines() -> void:
	var strength: float = clampf(successFxIntensity, 0.3, 2.0)
	var count := randi_range(FX_SPEED_LINE_COUNT_RANGE.x, FX_SPEED_LINE_COUNT_RANGE.y)
	for i in range(count):
		var line_color: Color = FX_SPEED_LINE_WHITE if randf() < 0.5 else FX_SPEED_LINE_CYAN
		fx_speed_lines.append({
			"y_offset": randf_range(-1.0, 1.0) * PLAYER_VISUAL_SIZE.y * FX_SPEED_LINE_Y_SPREAD,
			"length": randf_range(FX_SPEED_LINE_LENGTH_RANGE.x, FX_SPEED_LINE_LENGTH_RANGE.y) * strength,
			"elapsed": 0.0,
			"color": line_color,
		})


func _combo_tier(combo_value: int) -> int:
	# 0-indexed: 1-25 -> Tier 1 (0), 26-50 -> Tier 2 (1), 51-75 -> Tier 3 (2),
	# 76+ (capped at COMBO_TIER_CAP) -> Tier 4 (3), and it just stays there.
	var capped: int = mini(combo_value, COMBO_TIER_CAP)
	var tier: int = (maxi(capped, 1) - 1) / COMBO_TIER_SIZE
	return clampi(tier, 0, 3)


func _combo_display_pos(view_size: Vector2) -> Vector2:
	return Vector2(view_size.x - COMBO_DISPLAY_MARGIN.x, _gate_zone_top(view_size) + COMBO_DISPLAY_MARGIN.y)


func _spawn_combo_popup(view_size: Vector2) -> void:
	# The "×N" display itself is persistent (drawn every frame combo > 0 in
	# _draw_combo_popups) — this only re-triggers the punch/bounce and the
	# one-shot burst effects (particles, Tier 3 shake, Tier 4 glow) on top
	# of it, it doesn't spawn or replace anything that needs to expire.
	var tier := _combo_tier(combo)
	combo_display_punch_elapsed = 0.0
	var pos := _combo_display_pos(view_size)
	var particle_count: int = COMBO_TIER_PARTICLE_COUNTS[tier]
	if particle_count > 0:
		_spawn_spark_burst(pos, Vector2i(particle_count, particle_count), FX_SPARK_BURST_A_SIZE_RANGE, fx_burst_textures)
	if tier >= 2:
		combo_shake_elapsed = 0.0
	if tier >= 3:
		combo_glow_elapsed = 0.0


func _play_gate_success_sound() -> void:
	if fx_sound_whoosh.stream != null:
		fx_sound_whoosh.play()
	if fx_sound_chime.stream != null:
		fx_sound_chime.play()


func _sample_keyframes(keyframes: Array, t: float) -> float:
	# Piecewise-linear lookup over (time_fraction, value) pairs, used for
	# both the gate punch and bird stretch envelopes below.
	for i in range(keyframes.size() - 1):
		var a: Vector2 = keyframes[i]
		var b: Vector2 = keyframes[i + 1]
		if t >= a.x and t <= b.x:
			var span: float = b.x - a.x
			var local_t: float = 0.0 if span <= 0.0 else (t - a.x) / span
			return lerp(a.y, b.y, local_t)
	return keyframes[keyframes.size() - 1].y


func _gate_fx_elapsed(g: Dictionary, side: String) -> float:
	if g.get("fx_flash_side", "") != side:
		return -1.0
	return g.get("fx_flash_elapsed", -1.0)


func _gate_punch_scale(g: Dictionary, side: String) -> float:
	# 1.0 when idle; otherwise the 1.00 -> 1.08 -> 0.97 -> 1.00 keyframe
	# curve above, with the overshoot amount scaled by successFxIntensity.
	var elapsed := _gate_fx_elapsed(g, side)
	if elapsed < 0.0 or elapsed >= FX_GATE_PUNCH_DURATION:
		return 1.0
	var t: float = elapsed / FX_GATE_PUNCH_DURATION
	var raw: float = _sample_keyframes(FX_GATE_PUNCH_KEYFRAMES, t)
	return 1.0 + (raw - 1.0) * successFxIntensity


# ---- Boost glow (see the BOOST_GLOW_* consts) ----
# Nothing is drawn unless the boost look is at least partly engaged, so the
# not-boosting case costs one float compare.

func _boost_glow_alpha_and_scale() -> Vector2:
	# Returned together so check_boost_hold can assert on the same numbers
	# the draw uses, rather than re-deriving the pulse and drifting from it.
	if boost_visual_blend <= 0.0:
		return Vector2.ZERO
	var pulse: float = sin(boost_glow_elapsed * BOOST_GLOW_PULSE_HZ * TAU)
	var alpha: float = boost_glow_alpha * (1.0 + pulse * BOOST_GLOW_PULSE_ALPHA) * boost_visual_blend
	var scale: float = boost_glow_size_scale * (1.0 + pulse * BOOST_GLOW_PULSE_SCALE)
	return Vector2(maxf(alpha, 0.0), scale)


func _draw_boost_burst(pos: Vector2) -> void:
	if boost_burst_elapsed < 0.0 or boost_burst_frames.is_empty():
		return
	# Floor of the normalised time, clamped: at exactly t = 1 the index would
	# run one past the last frame.
	var t: float = clampf(boost_burst_elapsed / maxf(boost_burst_duration, 0.001), 0.0, 0.9999)
	var frame: Texture2D = boost_burst_frames[int(t * boost_burst_frames.size())]
	if frame == null:
		return
	# Square art, and sized off PLAYER_VISUAL_SIZE rather than the frame's own
	# pixels so re-cutting the sheet at another resolution changes nothing.
	var size: Vector2 = PLAYER_VISUAL_SIZE * active_visual_size_scale * BOOST_BURST_SIZE_SCALE
	draw_texture_rect(frame, Rect2(pos - size * 0.5, size), false)


func _draw_boost_glow(pos: Vector2) -> void:
	if character_glow_texture == null:
		return
	var av: Vector2 = _boost_glow_alpha_and_scale()
	if av.x <= 0.0:
		return
	# The per-mode colour carries channels above 1.0 (see
	# MODE_BOOST_GLOW_COLOR); only alpha is scaled here, so the overexposure
	# survives the fade instead of being normalised away.
	var tint: Color = MODE_BOOST_GLOW_COLOR[current_mode]
	tint.a = av.x
	# Scaled off PLAYER_VISUAL_SIZE, not the character's own stretch: the
	# gate-pass squash and the happy pop are the body reacting, and a halo
	# that squashed with them would read as attached to the sprite rather
	# than as light around it.
	var size: Vector2 = PLAYER_VISUAL_SIZE * active_visual_size_scale * av.y
	draw_texture_rect(character_glow_texture, Rect2(pos - size * 0.5, size), false, tint)


func _gate_glow_tint(g: Dictionary, side: String) -> Color:
	# Brightness modulate for this side's ring texture right now — a smooth
	# 0 -> 1 -> 0 pulse over GATE_GLOW_TINT_ENVELOPE, driven by the same
	# elapsed-since-pass timer as the punch FX above. Returns plain white
	# (no tint) when idle or once the flash has finished. Replaces the old
	# discrete normal/glow01/02/03 texture-swap now that there's only one
	# ring texture per side.
	var elapsed := _gate_fx_elapsed(g, side)
	if elapsed < 0.0:
		return Color.WHITE
	var blend: float = _sample_keyframes(GATE_GLOW_TINT_ENVELOPE, elapsed)
	return Color.WHITE.lerp(GATE_GLOW_TINT_COLOR, blend)


func _bird_stretch_scale() -> Vector2:
	if fx_stretch_elapsed < 0.0 or fx_stretch_elapsed >= FX_STRETCH_DURATION:
		return Vector2.ONE
	var t: float = fx_stretch_elapsed / FX_STRETCH_DURATION
	var envelope: float = _sample_keyframes(FX_STRETCH_KEYFRAMES, t)
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	var sx: float = lerp(1.0, FX_STRETCH_SCALE_X_PEAK, envelope * strength)
	var sy: float = lerp(1.0, FX_STRETCH_SCALE_Y_PEAK, envelope * strength)
	return Vector2(sx, sy)


func _happy_pop_envelope() -> float:
	if happy_flap_elapsed < 0.0:
		return 0.0
	return _sample_keyframes(HAPPY_POP_ENVELOPE, happy_flap_elapsed / HAPPY_FLAP_DURATION)


func _happy_pop_scale() -> float:
	return lerp(1.0, HAPPY_POP_SCALE_PEAK, _happy_pop_envelope())


func _happy_pop_bounce_offset() -> float:
	return -HAPPY_POP_BOUNCE_HEIGHT * _happy_pop_envelope()  # negative Y = up on screen


func _update_fx(delta: float) -> void:
	if happy_flap_elapsed >= 0.0:
		happy_flap_elapsed += delta
		if happy_flap_elapsed >= HAPPY_FLAP_DURATION:
			happy_flap_elapsed = -1.0

	for g in gates:
		if g.get("fx_flash_elapsed", -1.0) >= 0.0:
			g.fx_flash_elapsed += delta
			if g.fx_flash_elapsed >= FX_GATE_TIMELINE_DURATION:
				g.fx_flash_elapsed = -1.0

	for f in fx_impact_flashes:
		f.elapsed += delta
	fx_impact_flashes = fx_impact_flashes.filter(func(f): return f.elapsed < FX_IMPACT_FLASH_DURATION)

	for s in fx_sparks:
		s.elapsed += delta
		s.pos += s.vel * delta
	fx_sparks = fx_sparks.filter(func(s): return s.elapsed < s.lifetime)

	for l in fx_speed_lines:
		l.elapsed += delta
	fx_speed_lines = fx_speed_lines.filter(func(l): return l.elapsed < FX_SPEED_LINE_DURATION)

	_update_bird_trail(delta)

	if boost_bar_flash_elapsed >= 0.0:
		boost_bar_flash_elapsed += delta
		if boost_bar_flash_elapsed >= BOOST_BAR_FLASH_DURATION:
			boost_bar_flash_elapsed = -1.0

	if boost_pop_elapsed >= 0.0:
		boost_pop_elapsed += delta
		if boost_pop_elapsed >= BOOST_POP_DURATION:
			boost_pop_elapsed = -1.0

	# Runs from _update_fx, not _update_playing, so the look keeps easing out
	# after a game over instead of freezing mid-stretch.
	var blend_target: float = 1.0 if boost_button_held else 0.0
	var blend_span: float = BOOST_VISUAL_BLEND_IN if boost_button_held else BOOST_VISUAL_BLEND_OUT
	boost_visual_blend = move_toward(boost_visual_blend, blend_target, delta / maxf(blend_span, 0.001))
	# Runs unconditionally, so the glow's breathe is already mid-cycle when
	# the button goes down instead of starting from its peak. Wrapped to keep
	# the float from growing without bound across a long session.
	boost_glow_elapsed = fmod(boost_glow_elapsed + delta, 1.0 / BOOST_GLOW_PULSE_HZ)

	if boost_burst_elapsed >= 0.0:
		boost_burst_elapsed += delta
		if boost_burst_elapsed >= boost_burst_duration:
			boost_burst_elapsed = -1.0

	if combo > 0:
		combo_display_punch_elapsed += delta
		combo_display_time += delta
	else:
		combo_display_time = 0.0

	# Burst B + speed streaks fire together once their shared delay elapses.
	for b in fx_pending_bursts:
		b.delay -= delta
	var fired: Array = fx_pending_bursts.filter(func(b): return b.delay <= 0.0)
	fx_pending_bursts = fx_pending_bursts.filter(func(b): return b.delay > 0.0)
	for b in fired:
		_spawn_spark_burst(b.gate_center, FX_SPARK_BURST_B_COUNT_RANGE, FX_SPARK_BURST_B_SIZE_RANGE, fx_burst_textures)
		_spawn_speed_lines()

	if fx_stretch_elapsed >= 0.0:
		fx_stretch_elapsed += delta
		if fx_stretch_elapsed >= FX_STRETCH_DURATION:
			fx_stretch_elapsed = -1.0

	# Two independent shake sources (gate-pass impact, combo Tier 3+) summed
	# into one offset — each decays and clears on its own schedule.
	var shake_offset := Vector2.ZERO
	if fx_shake_elapsed >= 0.0:
		fx_shake_elapsed += delta
		if fx_shake_elapsed >= FX_SHAKE_DURATION:
			fx_shake_elapsed = -1.0
		else:
			# Cubic decay: drops under 1px well before FX_SHAKE_DURATION ends.
			var t: float = fx_shake_elapsed / FX_SHAKE_DURATION
			var amp: float = FX_SHAKE_PEAK_AMPLITUDE * pow(1.0 - t, 3) * clampf(successFxIntensity, 0.0, 2.0)
			shake_offset += Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	if combo_shake_elapsed >= 0.0:
		combo_shake_elapsed += delta
		if combo_shake_elapsed >= COMBO_SHAKE_DURATION:
			combo_shake_elapsed = -1.0
		else:
			var t2: float = combo_shake_elapsed / COMBO_SHAKE_DURATION
			var amp2: float = COMBO_SHAKE_PEAK_AMPLITUDE * pow(1.0 - t2, 3)
			shake_offset += Vector2(randf_range(-amp2, amp2), randf_range(-amp2, amp2))
	position = shake_offset

	if combo_glow_elapsed >= 0.0:
		combo_glow_elapsed += delta
		if combo_glow_elapsed >= COMBO_GLOW_DURATION:
			combo_glow_elapsed = -1.0


func _update_bird_trail(delta: float) -> void:
	# Runs from _update_fx, not _update_playing, so an existing trail keeps
	# drifting and fading after a game over instead of freezing mid-air.
	var world_dx: float = GATE_SPEED * _gate_speed_multiplier() * delta
	for p in trail_particles:
		p.elapsed += delta
		p.pos.x -= world_dx          # rides the world, not the bird — see the TRAIL_* header
		p.pos.y += p.drift_y * delta
		p.rotation += p.spin * delta
	trail_particles = trail_particles.filter(func(p): return p.elapsed < p.lifetime and p.pos.x > -TRAIL_OFFSCREEN_MARGIN)

	if not _trail_active():
		return
	# Flat rate, deliberately: the tap's punctuation is the tap flare's job,
	# and emission chasing the character's speed would just fight it. See
	# the header.
	trail_spawn_timer += delta
	# Shortened while boosting so the streak behind the character thickens
	# rather than just stretching out — the particles already ride the faster
	# world, which spaces them further apart on its own.
	var spawn_interval: float = TRAIL_SPAWN_INTERVAL * lerpf(1.0, BOOST_TRAIL_INTERVAL_SCALE, boost_visual_blend)
	# Streak modes pack it tighter still — see boost_streak_density. Applied
	# here rather than baked per particle because it governs emission, not the
	# particle itself.
	if TRAIL_BOOST_STREAK_PER_MODE[current_mode]:
		spawn_interval /= lerpf(1.0, boost_streak_density, boost_visual_blend)
	while trail_spawn_timer >= spawn_interval:
		trail_spawn_timer -= spawn_interval
		_spawn_trail_particle()


func _trail_active() -> bool:
	return state == State.PLAYING and TRAIL_ENABLED_PER_MODE[current_mode] and not trail_texture_sets.is_empty()


func _spawn_trail_burst() -> void:
	# Fired on tap: a short puff on top of the baseline, so the input gets a
	# visible kick without the trail ever becoming a steady stream. Same
	# particle as the baseline — see the TRAIL_* header for why the tap is
	# not its own separate effect.
	if not _trail_active():
		return
	for i in range(randi_range(TRAIL_TAP_BURST_RANGE.x, TRAIL_TAP_BURST_RANGE.y)):
		_spawn_trail_particle(TRAIL_TAP_BURST_SIZE_SCALE, TRAIL_TAP_BURST_JITTER)


func _spawn_trail_particle(size_scale: float = 1.0, jitter: float = TRAIL_ORIGIN_JITTER) -> void:
	var size_range: Vector2 = TRAIL_SIZE_RANGE_PER_MODE[current_mode] * size_scale
	# 0 = the usual tumbling wake, 1 = a speed line. Frozen here rather than
	# read at draw time — see the TRAIL_BOOST_STREAK_* block.
	var streak: float = boost_visual_blend if TRAIL_BOOST_STREAK_PER_MODE[current_mode] else 0.0
	var jitter_x: float = lerpf(jitter, maxf(jitter, TRAIL_BOOST_STREAK_X_JITTER), streak)
	var jitter_y: float = jitter * lerpf(1.0, TRAIL_BOOST_STREAK_Y_JITTER_SCALE, streak)
	var origin := Vector2(
		PLAYER_X + PLAYER_VISUAL_SIZE.x * TRAIL_ORIGIN_FRAC.x + randf_range(-jitter_x, jitter_x),
		player_y + PLAYER_VISUAL_SIZE.y * TRAIL_ORIGIN_FRAC.y + randf_range(-jitter_y, jitter_y))
	# One colour step per particle, and the cursor is never reset between
	# spawns: that is what turns DREAM's four colours into a rainbow that
	# keeps advancing, rather than a random pick that repeats itself. The
	# three single-colour modes only ever hold one set, so the step is a
	# no-op for them.
	var color_set: Array = trail_texture_sets[trail_color_cursor % trail_texture_sets.size()]
	trail_color_cursor += 1
	# Per-mode drift (bubbles rise, leaves settle) plus a little of the
	# character's own vertical motion, so a hard dive throws the trail
	# downward instead of leaving it hanging level. A streak eases all of
	# that to zero — vertical wander is exactly what stops a stream of
	# particles reading as one line.
	var drift_y: float = TRAIL_DRIFT_Y_PER_MODE[current_mode] + player_vel * TRAIL_INHERIT_VEL_Y \
			+ randf_range(TRAIL_DRIFT_Y_RANGE.x, TRAIL_DRIFT_Y_RANGE.y)
	trail_particles.append({
		"pos": origin,
		"drift_y": lerpf(drift_y, 0.0, streak),
		"streak": streak,
		"size": randf_range(size_range.x, size_range.y),
		# Near-upright rather than any angle: these are 4-point stars now,
		# and a fully random spin reads as a smear at this size. A streak
		# goes fully upright and stops turning, so the stretch below lands
		# on the screen's own X axis.
		"rotation": lerpf(randf_range(-TRAIL_ROTATION_JITTER, TRAIL_ROTATION_JITTER), 0.0, streak),
		"spin": lerpf(randf_range(TRAIL_SPIN_RANGE.x, TRAIL_SPIN_RANGE.y), 0.0, streak),
		"lifetime": randf_range(TRAIL_LIFETIME_RANGE.x, TRAIL_LIFETIME_RANGE.y) \
				* lerpf(1.0, TRAIL_BOOST_STREAK_LIFETIME_SCALE, streak),
		"elapsed": 0.0,
		"texture": color_set[randi() % color_set.size()],
	})


func _draw_bird_trail() -> void:
	if trail_particles.is_empty():
		return
	for p in trail_particles:
		var texture: Texture2D = p.texture
		if texture == null:
			continue
		var tex_size := Vector2(texture.get_width(), texture.get_height())
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			continue
		var t: float = p.elapsed / p.lifetime
		# Quadratic fade holds the head of the trail near full and dissolves
		# the tail, rather than the whole streak dimming evenly.
		var alpha: float = TRAIL_ALPHA * clampf(1.0 - t * t, 0.0, 1.0)
		if alpha <= 0.001:
			continue
		var draw_scale: float = p.size * (1.0 - t * TRAIL_SHRINK) / max(tex_size.x, tex_size.y)
		var size: Vector2 = tex_size * draw_scale
		# The one thing that actually gives a symmetric star a direction:
		# stretched along travel and squashed across it. Applied through the
		# transform, so it works with p.rotation — which a streak has already
		# driven to 0, putting the stretch on the screen's X axis.
		var stretch := Vector2.ONE
		if p.streak > 0.0:
			stretch = Vector2(
				lerpf(1.0, boost_streak_stretch, p.streak),
				lerpf(1.0, TRAIL_BOOST_STREAK_SQUASH, p.streak))
		draw_set_transform(p.pos, p.rotation, stretch)
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_speed_lines() -> void:
	if fx_speed_lines.is_empty():
		return
	var right_x: float = PLAYER_X - PLAYER_VISUAL_SIZE.x * 0.3
	for l in fx_speed_lines:
		var t: float = l.elapsed / FX_SPEED_LINE_DURATION
		var alpha: float = 1.0 - t
		var y: float = player_y + l.y_offset
		var rect := Rect2(Vector2(right_x - l.length, y - FX_SPEED_LINE_THICKNESS * 0.5), Vector2(l.length, FX_SPEED_LINE_THICKNESS))
		var c: Color = l.color
		draw_rect(rect, Color(c.r, c.g, c.b, c.a * alpha))


func _draw_impact_flashes() -> void:
	if fx_impact_flashes.is_empty():
		return
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	for f in fx_impact_flashes:
		var t: float = f.elapsed / FX_IMPACT_FLASH_DURATION
		var alpha: float = clampf((1.0 - t) * FX_IMPACT_FLASH_COLOR.a * strength, 0.0, 1.0)
		var col := Color(FX_IMPACT_FLASH_COLOR.r, FX_IMPACT_FLASH_COLOR.g, FX_IMPACT_FLASH_COLOR.b, alpha)
		draw_arc(f.pos, f.radius, 0.0, TAU, 48, col, FX_IMPACT_FLASH_WIDTH, true)


func _draw_sparks() -> void:
	if fx_sparks.is_empty():
		return
	for s in fx_sparks:
		_draw_one_spark(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_one_spark(s: Dictionary) -> void:
	var texture: Texture2D = s.texture
	if texture == null:
		return
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var t: float = s.elapsed / s.lifetime
	var modulate := Color(1.0, 1.0, 1.0, 1.0 - t)  # fast fade-out
	draw_set_transform(s.pos, s.rotation, Vector2.ONE * s.scale)
	draw_texture_rect(texture, Rect2(-tex_size * 0.5, tex_size), false, modulate)


# Tuning overlay for the pass zones. Drawn over the gate art so each band can
# be read against the ring it belongs to. Reads the same values _resolve_gate
# judges on, so what is drawn is exactly what is judged.
func _draw_debug_zones(view_size: Vector2) -> void:
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var half_h: float = PLAYER_SIZE.y * 0.5
	for g in gates:
		if g.resolved:
			continue
		for lane in ["top", "bottom"]:
			var zone_top: float = g.top_zone_top if lane == "top" else g.bottom_zone_top
			var zone_bottom: float = g.top_zone_bottom if lane == "top" else g.bottom_zone_bottom
			# 1. The opening — the whole hitbox has to fit in here.
			draw_rect(Rect2(Vector2(g.x, zone_top), Vector2(GATE_WIDTH, zone_bottom - zone_top)), DEBUG_ZONE_FILL)
			draw_rect(Rect2(Vector2(g.x, zone_top), Vector2(GATE_WIDTH, zone_bottom - zone_top)), DEBUG_ZONE_EDGE, false, 2.0)
			# 2. Where the centre may sit and still fit — the same opening
			#    inset by half the hitbox, top and bottom. This is the band
			#    the player is really aiming at.
			var slack_top: float = zone_top + half_h
			var slack_bottom: float = zone_bottom - half_h
			if slack_bottom > slack_top:
				draw_rect(Rect2(Vector2(g.x + 10.0, slack_top), Vector2(GATE_WIDTH - 20.0, slack_bottom - slack_top)), DEBUG_SLACK_FILL)
				draw_rect(Rect2(Vector2(g.x + 10.0, slack_top), Vector2(GATE_WIDTH - 20.0, slack_bottom - slack_top)), DEBUG_SLACK_EDGE, false, 2.0)
			var zone_center: float = (zone_top + zone_bottom) * 0.5
			draw_line(Vector2(g.x, zone_center), Vector2(g.x + GATE_WIDTH, zone_center), DEBUG_CENTER_LINE, 1.0)
			var label: String = "zone %.0f   center+-%.1f" % [
				zone_bottom - zone_top, (zone_bottom - zone_top - PLAYER_SIZE.y) * 0.5]
			draw_string(font, Vector2(g.x + 2.0, zone_top - 5.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, DEBUG_LABEL_SIZE, Color(1, 1, 1, 0.95))
		# Where the verdict is taken — the ring's centre line reaching the
		# character (see _update_playing). Everything is decided the instant
		# this line crosses, so it is a moment, not an area.
		var jx: float = _gate_judge_x(g)
		draw_line(Vector2(jx, _gate_zone_top(view_size)), Vector2(jx, view_size.y), DEBUG_JUDGE_LINE, 2.0)

	# The character's real collision rect, on top of whichever band it is in.
	var hitbox := Rect2(Vector2(PLAYER_X, player_y) - PLAYER_SIZE * 0.5, PLAYER_SIZE)
	draw_rect(hitbox, Color(DEBUG_HITBOX_COLOR.r, DEBUG_HITBOX_COLOR.g, DEBUG_HITBOX_COLOR.b, 0.18))
	draw_rect(hitbox, DEBUG_HITBOX_COLOR, false, 2.0)
	draw_line(Vector2(hitbox.position.x, player_y), Vector2(hitbox.end.x, player_y), DEBUG_HITBOX_COLOR, 2.0)

	# Legend, parked under the quiz box where nothing else draws.
	var legend_y: float = _gate_zone_top(view_size) + 14.0
	var entries := [
		[DEBUG_HITBOX_COLOR, "HITBOX  %.0fx%.0f" % [PLAYER_SIZE.x, PLAYER_SIZE.y]],
		[DEBUG_JUDGE_LINE, "JUDGE LINE  verdict happens HERE"],
		[DEBUG_ZONE_EDGE, "ZONE   whole hitbox must fit inside"],
		[DEBUG_SLACK_EDGE, "SLACK  where the CENTER may sit"],
	]
	for i in range(entries.size()):
		var y: float = legend_y + i * 17.0
		draw_rect(Rect2(Vector2(8.0, y - 9.0), Vector2(14.0, 12.0)), entries[i][0])
		draw_string(font, Vector2(28.0, y), entries[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, DEBUG_LABEL_SIZE, Color(1, 1, 1, 0.95))


func _combo_tier_color(tier: int, elapsed: float) -> Color:
	match tier:
		1:
			return Color(1.0, 0.85, 0.2)  # yellow
		2:
			# Orange <-> purple pulse ("주황/보라 계열").
			var mix: float = (sin(elapsed * TAU * 3.0) + 1.0) * 0.5
			return Color(1.0, 0.55, 0.15).lerp(Color(0.65, 0.3, 0.85), mix)
		3:
			# Rainbow shimmer.
			var hue: float = fmod(elapsed * 1.6, 1.0)
			return Color.from_hsv(hue, 0.8, 1.0)
	return COLOR_TEXT  # Tier 1: plain white


func _draw_combo_popups(view_size: Vector2) -> void:
	if combo <= 0:
		return
	var tier := _combo_tier(combo)
	# Punch: a quick overshoot-then-settle right after each pass (via
	# _pop_scale), clamped so it holds steady at rest instead of
	# extrapolating once combo_display_punch_elapsed outlives the punch
	# window — the "×N" text itself never expires or fades, only this
	# bounce is momentary. The tiny rise-then-return keeps the resting
	# position fixed (no permanent drift upward pass after pass).
	var punch_duration: float = COMBO_TIER_DURATIONS[tier]
	var t_punch: float = clampf(combo_display_punch_elapsed / punch_duration, 0.0, 1.0)
	var scale: float = _pop_scale(t_punch)
	var font_size: int = int(round(COMBO_TIER_FONT_SIZES[tier] * scale))
	var rise: float = COMBO_TIER_RISE[tier] * sin(t_punch * PI)
	var pos: Vector2 = _combo_display_pos(view_size) + Vector2(0.0, -rise)
	var text := "x%d" % combo
	var col: Color = _combo_tier_color(tier, combo_display_time)
	var main_col := Color(col.r, col.g, col.b, 1.0)
	var outline_col := COLOR_TEXT_OUTLINE
	# Right-anchored to pos.x so it grows toward screen-left as the digit
	# count changes, always staying inside the gate zone's top-right corner
	# rather than spilling off the screen edge.
	var text_size := combo_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var draw_pos := Vector2(pos.x - text_size.x, pos.y + text_size.y * 0.75)
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(combo_font, draw_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_col)
	draw_string(combo_font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, main_col)

	# "COMBO!" line below the "×N" at every tier — persistent just like the
	# number itself (no fade), riding the same punch bounce and tier color.
	var label := "COMBO!"
	var label_font_size: int = int(round(COMBO_TIER_FONT_SIZES[tier] * 0.55 * scale))
	var label_size := combo_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
	var label_pos := Vector2(pos.x - label_size.x, draw_pos.y + text_size.y * 0.7)
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(combo_font, label_pos + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, outline_col)
	draw_string(combo_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, main_col)


func _draw_combo_glow(view_size: Vector2, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	if combo_glow_elapsed < 0.0:
		return
	var t: float = combo_glow_elapsed / COMBO_GLOW_DURATION
	var pulse: float = 0.6 + 0.4 * sin(combo_glow_elapsed * TAU * 2.0)
	var alpha: float = COMBO_GLOW_PEAK_ALPHA * (1.0 - t) * pulse
	if alpha <= 0.0:
		return
	var c := Color(COMBO_GLOW_COLOR.r, COMBO_GLOW_COLOR.g, COMBO_GLOW_COLOR.b, alpha)
	var b := COMBO_GLOW_BAND_PX
	ci.draw_rect(Rect2(Vector2(0, 0), Vector2(view_size.x, b)), c)
	ci.draw_rect(Rect2(Vector2(0, view_size.y - b), Vector2(view_size.x, b)), c)
	ci.draw_rect(Rect2(Vector2(0, 0), Vector2(b, view_size.y)), c)
	ci.draw_rect(Rect2(Vector2(view_size.x - b, 0), Vector2(b, view_size.y)), c)


# ---- Best score (the BEST half of the score box) ----

# 한 모드의 최고 점수. 저장본이 아직 없거나 모드가 늘어난 직후에도
# 안전하게 0을 돌려준다.
func _best_for(mode: int) -> int:
	if mode < 0 or mode >= best_scores.size():
		return 0
	return best_scores[mode]


func _load_best_score() -> void:
	best_scores.resize(Mode.size())
	best_scores.fill(0)
	leaderboard_bests.resize(Mode.size())
	leaderboard_bests.fill(0)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return   # no save yet — a fresh install starts at 0, not an error
	for mode in range(Mode.size()):
		best_scores[mode] = int(cfg.get_value(
			SAVE_SECTION, SAVE_KEY_BEST_PREFIX + str(mode), 0))
		leaderboard_bests[mode] = int(cfg.get_value(
			SAVE_SECTION, SAVE_KEY_LEADERBOARD_PREFIX + str(mode), 0))
	# 예전 저장본에는 모드 구분 없는 기록 하나뿐이다. 어느 모드에서 낸
	# 점수인지 알 길이 없으므로, 처음 모드(SKY)의 기록으로 옮긴다. 버리는
	# 것보다는 낫고, 여러 모드에 복사하면 없던 기록이 생긴다.
	var legacy: int = int(cfg.get_value(SAVE_SECTION, SAVE_KEY_BEST_LEGACY, 0))
	if legacy > 0 and best_scores[Mode.SKY] == 0:
		best_scores[Mode.SKY] = legacy
		_save_best_score(Mode.SKY)


func _save_best_score(mode: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION, SAVE_KEY_BEST_PREFIX + str(mode), best_scores[mode])
	cfg.set_value(SAVE_SECTION, SAVE_KEY_LEADERBOARD_PREFIX + str(mode), leaderboard_bests[mode])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("could not write %s (error %d) — best score will not persist" % [SAVE_PATH, err])


# 실패한 순간. 곧바로 게임오버 화면으로 가지 않고 부활 제안을 먼저 띄운다 —
# 판을 접을지 이어갈지는 아직 플레이어가 정하지 않았다. 광고를 보면 이 판이
# 그대로 이어지고(_on_revive_continue), 거절하면 그때 진짜 게임오버로 간다.
func _game_over() -> void:
	# 첫 죽음에서 한 번만 — 이어 뛴 뒤의 죽음은 이 값을 건드리지 않는다.
	if not run_revived:
		leaderboard_score = score
	if revive_panel != null and not revive_offered:
		revive_offered = true
		_offer_revive()
		return
	_finish_run()


# 부활 제안. 죽은 자리를 그대로 두고 판만 멈춘다.
func _offer_revive() -> void:
	state = State.GAMEOVER   # 게이트와 물리를 멈추기 위해 — 화면은 아직 안 띄운다
	combo = 0
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	_stop_bgm()
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()
	revive_panel.set_character(sad_face_texture, PLAYER_VISUAL_SIZE.y * active_visual_size_scale)
	# 이어 뛰어도 순위표는 여기서 멈춘다는 걸 숫자로 보여 준다.
	revive_panel.set_leaderboard_score(leaderboard_score, player_logged_in)
	revive_panel.visible = true


# 광고를 본 뒤 이어가기. 죽은 게이트를 치우고 안전한 높이에서 다시 시작한다 —
# 점수와 통과 수는 그대로 두어 "이어서 뛰는" 것이 되게 한다.
func _on_revive_continue() -> void:
	run_revived = true
	revive_panel.visible = false
	var view_size := get_viewport_rect().size
	gates.clear()
	player_y = (_gate_zone_top(view_size) + _gate_zone_bottom(view_size)) * 0.5
	player_vel = 0.0
	last_zone_center = player_y
	flash_time = 0.0
	_spawn_gate(view_size)
	_start_countdown()


# 제안을 거절했을 때 — 여기서부터가 원래의 게임오버다.
func _on_revive_decline() -> void:
	revive_panel.visible = false
	_finish_run()


func _finish_run() -> void:
	state = State.GAMEOVER
	combo = 0  # combo is purely a run-length streak; a miss always zeroes it immediately, not just on restart
	# Whether this run set a record has to be read BEFORE the record is
	# updated — the popup shows a different face for a new best, and once
	# best_score has been overwritten the two are indistinguishable.
	var is_new_record: bool = score > _best_for(current_mode)
	var previous_best: int = _best_for(current_mode)
	# Only write on an actual improvement, so a run that doesn't beat the
	# record costs no disk access at all.
	if is_new_record:
		best_scores[current_mode] = score
	# 순위표 기록은 첫 실수 전까지의 점수로만 겨룬다.
	if leaderboard_score > leaderboard_bests[current_mode]:
		leaderboard_bests[current_mode] = leaderboard_score
	if is_new_record or leaderboard_score > 0:
		_save_best_score(current_mode)
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	# 네 가지 조합(신기록 여부 x 로그인 여부)을 팝업이 스스로 갈래 친다.
	if gameover_popup != null:
		# 신기록이면 웃는 얼굴, 아니면 우는 얼굴. 어느 모드인지 아는 쪽이
		# 여기라, 표정도 여기서 고른다.
		var face: Texture2D = happy_face_texture if is_new_record else sad_face_texture
		gameover_popup.set_result(face,
			PLAYER_VISUAL_SIZE.y * active_visual_size_scale,
			score, max_combo, previous_best, is_new_record, player_logged_in,
			leaderboard_score)
		gameover_popup.visible = true
	else:
		final_score_label.text = "SCORE: %d" % score
		gameover_panel.visible = true
	_stop_bgm()
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()


# Placeholder — there is no sign-in yet, so the popup always takes the
# not-logged-in branch. Wiring real auth means setting this and building the
# other three popup variants.
# 같은 모드로 곧장 다시 시작한다 — 일시정지의 RESTART와 같은 동작이다.
# (모드 선택으로 돌아가는 건 HOME 쪽이다.)
func _on_gameover_play_again_pressed() -> void:
	gameover_popup.visible = false
	_reset_game()
	_start_countdown()


func _on_gameover_login_pressed() -> void:
	push_warning("game over: login not wired up yet")


func _on_gameover_leaderboard_pressed() -> void:
	push_warning("game over: leaderboard not wired up yet")


func _on_gameover_share_pressed() -> void:
	push_warning("game over: share not wired up yet")


func _on_play_pressed() -> void:
	# Same READY -> START beat as a retry (see _on_restart_pressed) — first
	# play used to skip straight to PLAYING, changed per request so every
	# run start gets the countdown.
	_reset_game()
	_start_countdown()


func _on_restart_pressed() -> void:
	# Back to mode-select rather than an instant same-mode retry — all 3
	# concepts currently share this same flag quiz and are meant to be
	# compared/tested back and forth, so restart is the natural point to
	# switch between them rather than a separate menu button. _reset_game
	# clears the just-ended run's score/gates so mode-select's background
	# isn't showing stale gates.
	_reset_game()
	_set_state(State.MODE_SELECT)


# 메인 화면 오른쪽 위 톱니바퀴. 지금 볼륨을 넣어 열어 준다.
func _open_settings() -> void:
	settings_popup.set_volumes(sfx_volume, music_volume)
	# 프로필 사진과 닉네임은 인증이 붙으면 여기로 들어온다.
	settings_popup.set_account(player_avatar, player_display_name, player_logged_in)
	settings_popup.visible = true


func _on_login_pressed() -> void:
	push_warning("설정: 로그인 아직 연결 안 됨")


func _on_logout_pressed() -> void:
	push_warning("설정: 로그아웃 아직 연결 안 됨")


func _on_privacy_pressed() -> void:
	push_warning("설정: 개인정보 처리방침 링크 아직 연결 안 됨")


func _on_terms_pressed() -> void:
	push_warning("설정: 이용약관 링크 아직 연결 안 됨")


func _on_about_closed() -> void:
	about_popup.visible = false
	settings_popup.visible = true


func _on_contact_pressed() -> void:
	push_warning("설정: 문의/피드백 아직 연결 안 됨")


# About 을 여는 동안 설정은 감춘다. 겹쳐 두면 두 판의 테두리와 닫기 버튼이
# 서로 비어져 나와 지저분하다. 닫으면 설정으로 돌아온다.
func _on_about_pressed() -> void:
	settings_popup.visible = false
	about_popup.visible = true


func _on_remove_ads_pressed() -> void:
	push_warning("설정: 광고 제거 결제 아직 연결 안 됨")


func _on_mode_selected(mode: int) -> void:
	# 메인 화면의 START 가 곧 시작이다. 예전에는 여기서 State.READY 로 가서
	# PLAY 를 한 번 더 눌러야 했는데, 버튼을 두 번 누르게 할 이유가 없다.
	# ReadyPanel/PlayButton 은 그대로 두었다 — 되돌리려면 이 두 줄만 바꾸면 된다.
	_apply_mode(mode)
	_reset_game()
	_start_countdown()


# Loads the character/gate/FX asset set for the given Mode into the existing
# runtime textures/vars — called once at _ready() (default SKY) and again
# every time the mode-select screen picks a mode. See MODE_CHARACTER_DIR/
# MODE_GATE_DIR above for what's shared vs. per-mode.
func _apply_mode(mode: int) -> void:
	current_mode = mode

	# Character art, with SKY as the safety net. A mode whose art has not been
	# drawn yet (DREAM, while the unicorn is in progress) would otherwise run
	# with an invisible character; falling back per-file means each unicorn
	# PNG starts being used the moment it is dropped in, with no code change
	# and no need for all three to land at once.
	var char_dir: String = MODE_CHARACTER_DIR[mode]
	var sky_dir: String = MODE_CHARACTER_DIR[Mode.SKY]
	var grid: Vector2i = MODE_CHARACTER_SHEET_GRID[mode]
	flap_frames = _slice_spritesheet(char_dir + MODE_CHARACTER_FLY_FILE[mode], grid.x, grid.y)
	if flap_frames.is_empty() and mode != Mode.SKY:
		push_warning("Mode %d: no motion sheet at %s — falling back to SKY art." % [mode, char_dir + MODE_CHARACTER_FLY_FILE[mode]])
		var sky_grid: Vector2i = MODE_CHARACTER_SHEET_GRID[Mode.SKY]
		flap_frames = _slice_spritesheet(sky_dir + MODE_CHARACTER_FLY_FILE[Mode.SKY], sky_grid.x, sky_grid.y)
	flap_frame_index = 0
	happy_face_texture = _load_face(char_dir + MODE_CHARACTER_HAPPY_FILE[mode], sky_dir + MODE_CHARACTER_HAPPY_FILE[Mode.SKY])
	sad_face_texture = _load_face(char_dir + MODE_CHARACTER_SAD_FILE[mode], sky_dir + MODE_CHARACTER_SAD_FILE[Mode.SKY])
	# 부활 팝업이 쓸 얼굴을 미리 넘겨 둔다. 팝업이 알파 경계를 다듬느라
	# 30ms쯤 쓰는데, 게이트를 놓친 그 순간에 그러면 멈칫하는 게 느껴진다.
	if revive_panel != null:
		# 크기도 함께 — 팝업이 게임 화면과 똑같은 크기로 캐릭터를 띄운다.
		revive_panel.set_character(sad_face_texture, PLAYER_VISUAL_SIZE.y * MODE_VISUAL_SIZE_SCALE[mode])
	active_draw_offset_fly = MODE_DRAW_OFFSET_FLY[mode]
	active_draw_offset_happy = MODE_DRAW_OFFSET_HAPPY[mode]
	active_draw_offset_sad = MODE_DRAW_OFFSET_SAD[mode]
	active_visual_size_scale = MODE_VISUAL_SIZE_SCALE[mode]

	# 탭 소리도 모드를 따라간다. 없으면 기본 소리로 남겨 둔다.
	var flap_path: String = _resolve_audio(MODE_FLAP_SOUND_NAME[mode])
	if flap_path == "":
		flap_path = FX_SOUND_FLAP_FALLBACK
	if fx_sound_flap != null and ResourceLoader.exists(flap_path):
		fx_sound_flap.stream = load(flap_path)

	var gate_dir: String = MODE_GATE_DIR[mode]
	gate_left_pillar_texture = null
	if ResourceLoader.exists(gate_dir + "gate_ring_left.png"):
		gate_left_pillar_texture = load(gate_dir + "gate_ring_left.png")
	gate_right_pillar_texture = null
	if ResourceLoader.exists(gate_dir + "gate_ring_right.png"):
		gate_right_pillar_texture = load(gate_dir + "gate_ring_right.png")
	gate_base_texture = null
	if MODE_GATE_BASE_ENABLED[mode] and ResourceLoader.exists(gate_dir + "gate_ring_base.png"):
		gate_base_texture = load(gate_dir + "gate_ring_base.png")

	bg_texture = null
	var bg_path: String = MODE_BG_TEXTURE_PATH[mode]
	if bg_path != "" and ResourceLoader.exists(bg_path):
		bg_texture = load(bg_path)
	bg_scroll_x = 0.0
	bg_near_texture = null
	var bg_near_path: String = MODE_BG_NEAR_TEXTURE_PATH[mode]
	if bg_near_path != "" and ResourceLoader.exists(bg_near_path):
		bg_near_texture = load(bg_near_path)
	bg_near_scroll_x = 0.0

	# Per-mode animation strip, sliced the same way the character sheets are.
	boost_burst_frames = _slice_spritesheet(BOOST_BURST_DIR + BOOST_BURST_FILE_PER_MODE[mode], BOOST_BURST_SHEET_GRID.x, BOOST_BURST_SHEET_GRID.y)
	boost_burst_elapsed = -1.0

	# SKY used to be skipped here — its old twinkling lights did not suit the
	# scene and were dropped. It has drifting feathers now, so every mode
	# loads.
	particle_textures.clear()
	var particle_dir: String = MODE_PARTICLE_DIR[mode]
	var particle_prefix: String = MODE_PARTICLE_PREFIX[mode]
	for i in range(1, MODE_PARTICLE_COUNT[mode] + 1):
		var particle_path: String = particle_dir + "%s_%02d.png" % [particle_prefix, i]
		if ResourceLoader.exists(particle_path):
			particle_textures.append(load(particle_path))
	_init_ambient_particles(get_viewport_rect().size)

	gate_flag_panel_texture = null
	var panel_path: String = MODE_GATE_FLAG_PANEL_PATH[mode]
	if ResourceLoader.exists(panel_path):
		gate_flag_panel_texture = load(panel_path)

	ready_texture = null
	if ResourceLoader.exists(MODE_READY_TEXTURE_PATH[mode]):
		ready_texture = _softened_word_art(load(MODE_READY_TEXTURE_PATH[mode]), COUNTDOWN_READY_WIDTH)
	start_texture = null
	if ResourceLoader.exists(MODE_START_TEXTURE_PATH[mode]):
		start_texture = _softened_word_art(load(MODE_START_TEXTURE_PATH[mode]), COUNTDOWN_START_WIDTH)
	# TRY AGAIN is a node in the game-over panel rather than something
	# _draw() paints, so it is assigned rather than cached.
	if ResourceLoader.exists(MODE_TRY_AGAIN_TEXTURE_PATH[mode]):
		try_again_image.texture = load(MODE_TRY_AGAIN_TEXTURE_PATH[mode])

	# All four top-HUD pieces are per-mode. They share one canvas size per
	# piece across the modes, so nothing about the layout has to change here
	# — only which texture is drawn.
	if score_crown_texture == null:
		# 아이콘 캔버스에 투명 여백이 넉넉히 붙어 있어, 잘라 내지 않으면 같은
		# 높이로 그려도 왕관만 작아 보인다.
		score_crown_texture = _load_trimmed(BEST_CROWN_PATH, true)
	score_box_texture = null
	if ResourceLoader.exists(MODE_SCORE_BOX_PATH[mode]):
		score_box_texture = load(MODE_SCORE_BOX_PATH[mode])
	quiz_box_texture = null
	if ResourceLoader.exists(MODE_QUIZ_BOX_PATH[mode]):
		quiz_box_texture = load(MODE_QUIZ_BOX_PATH[mode])
	if ResourceLoader.exists(MODE_PAUSE_ICON_PATH[mode]):
		pause_button.icon = load(MODE_PAUSE_ICON_PATH[mode])
	if ResourceLoader.exists(MODE_MUTE_ICON_PATH[mode]):
		mute_button.icon = load(MODE_MUTE_ICON_PATH[mode])
	if ResourceLoader.exists(MODE_BOOST_ICON_PATH[mode]):
		boost_button.icon = load(MODE_BOOST_ICON_PATH[mode])
	# Re-run now that the icons are loaded: _ready lays the row out before
	# any mode is applied, so it sizes off the HUD_BUTTON_SRC fallback.
	_layout_hud_buttons()

	# Sparkles come from one shared folder rather than a per-mode one: the art
	# is a single sheet cut four ways by colour, and both the trail (DREAM
	# needs all four rows at once) and the gate burst (every mode sprinkles
	# in the other three colours) reach across modes, which a per-mode
	# folder could not express. Every colour is loaded for every mode; the
	# two tables below only pick among them. load() is cached, so re-running
	# this on each mode switch costs nothing after the first.
	sparkle_texture_sets.clear()
	for color_name in SPARKLE_COLOR_NAMES:
		var color_set: Array[Texture2D] = []
		for i in range(1, SPARKLE_SPRITES_PER_COLOR + 1):
			var sparkle_path: String = SPARKLE_DIR + "tap_%s_%d.png" % [color_name, i]
			if ResourceLoader.exists(sparkle_path):
				color_set.append(load(sparkle_path))
		sparkle_texture_sets.append(color_set)

	trail_texture_sets.clear()
	for color_name in TRAIL_COLORS_PER_MODE[mode]:
		var ci: int = SPARKLE_COLOR_NAMES.find(color_name)
		if ci >= 0 and not sparkle_texture_sets[ci].is_empty():
			trail_texture_sets.append(sparkle_texture_sets[ci])
	trail_color_cursor = 0

	# Weights realised as repetition: a colour weighted 7 lands in the pool
	# seven times over, so _spawn_spark_burst's plain uniform pick already
	# produces the mix without carrying weight logic of its own.
	fx_burst_textures.clear()
	var burst_weights: Array = FX_BURST_COLOR_WEIGHTS_PER_MODE[mode]
	for ci in range(SPARKLE_COLOR_NAMES.size()):
		var color_set: Array = sparkle_texture_sets[ci]
		if color_set.is_empty():
			continue
		for _repeat in range(int(burst_weights[ci])):
			fx_burst_textures.append_array(color_set)


func _start_countdown() -> void:
	countdown_phase = CountdownPhase.READY_TEXT
	countdown_timer = COUNTDOWN_READY_DURATION
	_set_state(State.COUNTDOWN)
	if fx_sound_countdown_ready.stream != null:
		fx_sound_countdown_ready.play()
	# A run may be starting again after a game over silenced the music.
	_play_bgm(_bgm_path_for_state())


func _reset_game() -> void:
	var view_size := get_viewport_rect().size
	player_y = (_gate_zone_top(view_size) + _gate_zone_bottom(view_size)) * 0.5
	player_vel = 0.0
	score = 0
	combo = 0
	max_combo = 0
	gates_passed = 0
	gates.clear()
	last_quiz_key = ""  # repeat guard is per-run — see last_quiz_key
	revive_offered = false
	run_revived = false
	leaderboard_score = 0
	if revive_panel != null:
		revive_panel.visible = false
	flash_time = 0.0
	gate_speed_boost_elapsed = -1.0
	boost_button_held = false
	if fx_sound_boost != null:
		fx_sound_boost.stop()
	boost_visual_blend = 0.0
	boost_burst_elapsed = -1.0
	boost_bar_elapsed = -1.0
	boost_bar_flash_elapsed = -1.0
	boost_pop_elapsed = -1.0
	boost_pop_anchor = Vector2.ZERO
	last_zone_center = player_y
	fx_sparks.clear()
	fx_speed_lines.clear()
	trail_particles.clear()
	trail_spawn_timer = 0.0
	combo_display_punch_elapsed = 0.0
	combo_display_time = 0.0
	fx_impact_flashes.clear()
	fx_pending_bursts.clear()
	fx_shake_elapsed = -1.0
	fx_stretch_elapsed = -1.0
	happy_flap_elapsed = -1.0
	combo_shake_elapsed = -1.0
	combo_glow_elapsed = -1.0
	position = Vector2.ZERO  # in case a restart lands mid-shake
	paused = false
	pause_panel.visible = false
	# First question is revealed immediately so it's visible for the full
	# spawn-to-player travel time, well over the 1.5-2s minimum preview.
	_spawn_gate(view_size)


func _on_pause_pressed() -> void:
	if state != State.PLAYING:
		return
	paused = true
	# 슬라이더가 현재 볼륨을 비추도록 — 팝업은 값을 들고 있지 않고, 열릴 때마다
	# 받아 간다.
	pause_panel.set_volumes(sfx_volume, music_volume)
	pause_panel.visible = true
	pause_button.modulate = Color(1.0, 1.0, 1.0, 0.5)


func _on_resume_pressed() -> void:
	paused = false
	pause_panel.visible = false
	pause_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


# 일시정지 팝업의 RESTART — 지금 모드 그대로 처음부터. _reset_game이 pause
# 상태와 팝업 표시를 함께 정리하므로 여기서 따로 끌 필요는 없다.
func _on_pause_restart_pressed() -> void:
	pause_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_reset_game()
	_start_countdown()


# 일시정지 팝업의 HOME — 모드 선택 화면으로. 진행 중이던 판은 버린다.
func _on_pause_home_pressed() -> void:
	pause_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_reset_game()
	_set_state(State.MODE_SELECT)


# Master 아래에 SFX / Music 버스를 만든다. 이미 있으면 그대로 둔다.
func _setup_audio_buses() -> void:
	for bus_name in [BUS_SFX, BUS_MUSIC]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


# 0~1 슬라이더 값을 버스에 적용한다. 0은 데시벨로 표현할 수 없으므로
# (linear_to_db(0)이 -inf) 그 지점만 mute로 갈아탄다.
func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, maxf(VOLUME_MIN_DB, linear_to_db(v)) if v > 0.001 else VOLUME_MIN_DB)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_save_audio_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_save_audio_settings()


func _load_audio_settings() -> void:
	# 버스가 아직 없으면 볼륨을 적을 곳이 없어 조용히 사라진다. 호출 순서에
	# 기대지 않도록 여기서 먼저 확보한다 — 이미 있으면 아무 일도 하지 않는다.
	_setup_audio_buses()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		sfx_volume = clampf(float(cfg.get_value(SAVE_SECTION_AUDIO, SAVE_KEY_SFX, sfx_volume)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value(SAVE_SECTION_AUDIO, SAVE_KEY_MUSIC, music_volume)), 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)


# 최고 점수와 같은 파일을 쓰므로, 먼저 읽어 들여 다른 값을 지우지 않는다.
func _save_audio_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SAVE_SECTION_AUDIO, SAVE_KEY_SFX, sfx_volume)
	cfg.set_value(SAVE_SECTION_AUDIO, SAVE_KEY_MUSIC, music_volume)
	cfg.save(SAVE_PATH)


func _on_mute_pressed() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	mute_button.modulate = Color(1.0, 1.0, 1.0, 0.5) if muted else Color(1.0, 1.0, 1.0, 1.0)


# Hold to accelerate. Both handlers only move the flag — the multiplier is
# read off it fresh every frame in _gate_speed_multiplier, so release takes
# effect on the very next frame with no decay to unwind.
func _on_boost_pressed() -> void:
	boost_button_held = true
	_tween_boost_alpha(BOOST_BUTTON_PRESSED_ALPHA)
	if fx_sound_boost.stream != null:
		fx_sound_boost.play()
	# Restarted from 0 rather than only started when idle: hammering the
	# button should re-pop each time, not be swallowed by the tail of the
	# previous one.
	boost_burst_elapsed = 0.0


func _on_boost_released() -> void:
	boost_button_held = false
	_tween_boost_alpha(BOOST_BUTTON_ALPHA)
	fx_sound_boost.stop()


# modulate:a 만 민다 — 크기는 _animate_button_press/_release 가 따로 맡는다.
#
# 진행 중인 것은 먼저 죽인다. 빠르게 눌렀다 떼면 반대 방향 트윈이 겹쳐 서로
# 덮어쓰고, 무엇보다 버튼이 숨을 때 알파를 되돌려도 살아남은 트윈이 다음
# 프레임에 눌린 값으로 다시 칠해 버린다(_process 의 리셋 참고).
func _tween_boost_alpha(alpha: float) -> void:
	if boost_alpha_tween != null and boost_alpha_tween.is_valid():
		boost_alpha_tween.kill()
	boost_alpha_tween = create_tween()
	boost_alpha_tween.tween_property(boost_button, "modulate:a", alpha, BUTTON_PRESS_ANIM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animate_button_press(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * BUTTON_PRESS_SCALE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animate_button_release(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Drawn into splash_char_layer rather than here. The frames are 256px drawn
# at about half that, and this project renders with nearest filtering — right
# for the pixel-art sprites in play, but it stair-steps a sprite this heavily
# minified. The layer is a child CanvasItem carrying its own filter, so the
# title screen gets smooth minification without changing how the game itself
# draws a single pixel.
# 로고 화면. 검은 바탕 + 로고 + "BETA VERSION" + 크레딧 두 줄을 한 덩어리로
# 묶어 가운데에 놓고, 전체에 같은 페이드를 건다.
func _draw_logo(view_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), LOGO_BACKGROUND)
	if logo_texture == null:
		return
	var alpha := 1.0
	if logo_elapsed < LOGO_FADE_IN:
		alpha = clampf(logo_elapsed / LOGO_FADE_IN, 0.0, 1.0)
	elif logo_elapsed > LOGO_FADE_IN + LOGO_HOLD:
		var out_t: float = (logo_elapsed - LOGO_FADE_IN - LOGO_HOLD) / LOGO_FADE_OUT
		alpha = clampf(1.0 - out_t, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font

	var logo_w: float = view_size.x * LOGO_WIDTH_FRAC
	var logo_h: float = logo_w * float(logo_texture.get_height()) / float(logo_texture.get_width())
	var beta_size: int = maxi(8, int(round(view_size.y * LOGO_BETA_FONT_FRAC)))
	var credit_size: int = maxi(7, int(round(view_size.y * LOGO_CREDIT_FONT_FRAC)))
	var beta_h: float = font.get_string_size(LOGO_BETA_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, beta_size).y
	var credit_h: float = font.get_string_size("Ag", HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size).y
	var gap1: float = view_size.y * LOGO_TO_BETA_GAP_FRAC
	var gap2: float = view_size.y * LOGO_BETA_TO_CREDIT_GAP_FRAC
	var line_gap: float = view_size.y * LOGO_CREDIT_LINE_GAP_FRAC

	var block_h: float = logo_h + gap1 + beta_h + gap2 + credit_h * LOGO_CREDITS.size() \
		+ line_gap * (LOGO_CREDITS.size() - 1)
	var top: float = view_size.y * LOGO_BLOCK_CENTER_FRAC - block_h * 0.5

	draw_texture_rect(logo_texture,
		Rect2(view_size.x * 0.5 - logo_w * 0.5, top, logo_w, logo_h),
		false, Color(1.0, 1.0, 1.0, alpha))

	var beta_w: float = font.get_string_size(LOGO_BETA_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, beta_size).x
	var beta_baseline: float = top + logo_h + gap1 + beta_h * 0.78
	draw_string(font, Vector2(view_size.x * 0.5 - beta_w * 0.5, beta_baseline),
		LOGO_BETA_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, beta_size,
		Color(LOGO_BETA_COLOR, LOGO_BETA_COLOR.a * alpha))

	# 역할 칸을 가장 긴 역할에 맞춰 두면 두 줄의 점이 세로로 맞는다.
	var gap: float = view_size.x * LOGO_CREDIT_GAP_FRAC
	var role_w := 0.0
	var name_w := 0.0
	for row in LOGO_CREDITS:
		role_w = maxf(role_w, font.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size).x)
		name_w = maxf(name_w, font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size).x)
	var dot_w: float = font.get_string_size(LOGO_CREDIT_DOT, HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size).x
	var block_w: float = role_w + gap + dot_w + gap + name_w
	var left: float = view_size.x * 0.5 - block_w * 0.5
	var y: float = top + logo_h + gap1 + beta_h + gap2 + credit_h * 0.78
	for row in LOGO_CREDITS:
		draw_string(font, Vector2(left, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size,
			Color(LOGO_CREDIT_ROLE_COLOR, LOGO_CREDIT_ROLE_COLOR.a * alpha))
		draw_string(font, Vector2(left + role_w + gap, y), LOGO_CREDIT_DOT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size,
			Color(LOGO_CREDIT_ROLE_COLOR, LOGO_CREDIT_ROLE_COLOR.a * alpha))
		draw_string(font, Vector2(left + role_w + gap + dot_w + gap, y), row[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size,
			Color(LOGO_CREDIT_NAME_COLOR, LOGO_CREDIT_NAME_COLOR.a * alpha))
		y += credit_h + line_gap


func _draw_splash_characters() -> void:

	var view_size := get_viewport_rect().size
	if splash_character_frames.is_empty():
		return
	var draw_size: float = view_size.x * SPLASH_CHARACTER_SIZE_FRAC
	var spacing: float = view_size.x * SPLASH_CHARACTER_SPACING_FRAC
	var mid_x: float = view_size.x * 0.5
	var mid_y: float = view_size.y * SPLASH_CHARACTER_MID_Y_FRAC
	# The per-mode draw offsets are measured against PLAYER_VISUAL_SIZE, so
	# they have to be rescaled to whatever size the title screen draws at or
	# the three end up misaligned against each other.
	var offset_scale: float = draw_size / PLAYER_VISUAL_SIZE.x
	var span: float = spacing * (splash_character_frames.size() - 1)
	for i in range(splash_character_frames.size()):
		var frames: Array = splash_character_frames[i]
		if frames.is_empty():
			continue
		var mode: int = SPLASH_CHARACTER_MODES[i]
		# Frame index straight off the clock — the splash runs its own
		# animation rather than borrowing the gameplay flap timer, which does
		# not tick on this screen.
		var frame: int = int(splash_elapsed / FLAP_FRAME_DURATION) % frames.size()
		var texture: Texture2D = frames[frame]
		if texture == null:
			continue
		var phase: float = SPLASH_BOB_PHASE[i] if i < SPLASH_BOB_PHASE.size() else 0.0
		var bob: float = sin((splash_elapsed + phase) / SPLASH_BOB_PERIOD * TAU) * draw_size * SPLASH_BOB_AMPLITUDE_FRAC
		var centre := Vector2(mid_x - span * 0.5 + spacing * i, mid_y + bob)
		var size_scale: float = MODE_VISUAL_SIZE_SCALE[mode]
		var size := Vector2(draw_size, draw_size) * size_scale
		var offset: Vector2 = MODE_DRAW_OFFSET_FLY[mode] * offset_scale
		splash_char_layer.draw_texture_rect(texture, Rect2(centre - size * 0.5 + offset, size), false)


func _draw_splash(view_size: Vector2) -> void:
	if splash_texture == null:
		return
	# Scale to cover, then centre: whichever axis is proportionally shorter
	# decides the scale, and the surplus on the other axis is cropped evenly.
	var tex_size := Vector2(splash_texture.get_width(), splash_texture.get_height())
	var scale: float = maxf(view_size.x / tex_size.x, view_size.y / tex_size.y)
	var draw_size: Vector2 = tex_size * scale
	var top_left: Vector2 = (view_size - draw_size) * 0.5
	draw_texture_rect(splash_texture, Rect2(top_left, draw_size), false)

	if splash_title_texture != null:
		var tw: float = view_size.x * SPLASH_TITLE_WIDTH_FRAC
		var th: float = tw * (float(splash_title_texture.get_height())
			/ float(splash_title_texture.get_width()))
		draw_texture_rect(splash_title_texture, Rect2(
			(view_size.x - tw) * 0.5,
			view_size.y * SPLASH_TITLE_MID_Y_FRAC - th * 0.5,
			tw, th), false)


	var alpha: float
	var prompt_scale := 1.0
	var glow_pulse := 0.0   # 0 at the trough, 1 at the peak of the breath
	if splash_exit_elapsed >= 0.0:
		var e: float = clampf(splash_exit_elapsed / SPLASH_EXIT_DURATION, 0.0, 1.0)
		# Cubic ease-out: the prompt jumps at the moment of the tap and eases
		# to a stop, which reads as a response to the press. Easing in would
		# creep first and feel like lag.
		var eased: float = 1.0 - pow(1.0 - e, 3)
		prompt_scale = lerpf(1.0, SPLASH_EXIT_SCALE, eased)
		alpha = 1.0 - eased
	else:
		var t: float = fposmod(splash_elapsed, SPLASH_PROMPT_PULSE_PERIOD) / SPLASH_PROMPT_PULSE_PERIOD
		# sin over the full cycle gives a smooth in-and-out with no hard turn
		# — the ease-in-out shape, without needing a Tween to drive it. The
		# clock is free-running (splash_elapsed), so the breath is already
		# going the moment the screen appears and keeps going until the tap.
		var pulse: float = (sin(t * TAU - PI * 0.5) + 1.0) * 0.5
		alpha = lerpf(SPLASH_PROMPT_ALPHA_RANGE.x, SPLASH_PROMPT_ALPHA_RANGE.y, pulse)
		prompt_scale = lerpf(SPLASH_PROMPT_SCALE_RANGE.x, SPLASH_PROMPT_SCALE_RANGE.y, pulse)
		glow_pulse = pulse
	if alpha <= 0.001:
		return
	var font_size := int(round(view_size.y * SPLASH_PROMPT_FONT_SCALE))
	var centre := Vector2(view_size.x * 0.5, view_size.y * (1.0 - SPLASH_PROMPT_BOTTOM_FRAC))
	var fill := Color(SPLASH_PROMPT_COLOR.r, SPLASH_PROMPT_COLOR.g, SPLASH_PROMPT_COLOR.b, alpha)
	var outline := Color(SPLASH_PROMPT_OUTLINE.r, SPLASH_PROMPT_OUTLINE.g, SPLASH_PROMPT_OUTLINE.b, alpha)
	# Drawn about the origin with the transform placing and scaling it, so
	# the swell grows from the prompt's centre instead of its top-left.
	draw_set_transform(centre, 0.0, Vector2(prompt_scale, prompt_scale))
	# Glow first, so the text sits on top of its own bloom rather than under it.
	_draw_splash_prompt_glow(font_size, glow_pulse * alpha)
	_draw_centered_text(SPLASH_PROMPT_TEXT, Vector2.ZERO, font_size, fill, outline, combo_font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Gold bloom behind the prompt. Called inside the prompt's own transform, so
# it is placed about the origin and scales with the swell. `strength` is
# 0..1 and rides the same pulse as the text.
func _draw_splash_prompt_glow(font_size: int, strength: float) -> void:
	if strength <= 0.001:
		return
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var text_size := font.get_string_size(SPLASH_PROMPT_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	# Same baseline _draw_centered_text uses with no baseline_frac, so the
	# bloom lands exactly under the glyphs instead of offset from them.
	var base := Vector2(-text_size.x * 0.5, text_size.y * 0.25)
	for ring_index in range(SPLASH_PROMPT_GLOW_RADII.size()):
		var radius: float = SPLASH_PROMPT_GLOW_RADII[ring_index]
		# Outer rings fade out, which is what makes the edge soft rather than
		# a series of visible outlines.
		var falloff: float = 1.0 - float(ring_index) / float(SPLASH_PROMPT_GLOW_RADII.size())
		var a: float = SPLASH_PROMPT_GLOW_ALPHA * falloff * strength
		if a <= 0.002:
			continue
		var col := Color(SPLASH_PROMPT_GLOW_COLOR.r, SPLASH_PROMPT_GLOW_COLOR.g, SPLASH_PROMPT_GLOW_COLOR.b, a)
		for i in range(SPLASH_PROMPT_GLOW_STEPS):
			var angle: float = TAU * float(i) / float(SPLASH_PROMPT_GLOW_STEPS)
			var offset := Vector2(cos(angle), sin(angle)) * radius
			draw_string(font, base + offset, SPLASH_PROMPT_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)


# Finds an audio file by name, preferring OGG over WAV — see BGM_EXTENSIONS.
# Used for music and for the per-mode tap sound. Returns "" when neither
# exists, which _play_bgm treats as "leave the
# current music alone" rather than dropping to silence.
func _resolve_audio(track_name: String) -> String:
	if track_name == "":
		return ""
	for ext in BGM_EXTENSIONS:
		var path: String = BGM_DIR + track_name + ext
		if ResourceLoader.exists(path):
			return path
	return ""


# Which track belongs to the screen we are on: the menu screens share one,
# everything from the countdown onward uses the chosen mode's.
func _bgm_path_for_state() -> String:
	if state == State.SPLASH or state == State.MODE_SELECT:
		return _resolve_audio(BGM_MENU_NAME)
	# 모드 곡이 아직 없으면 메뉴 곡으로 되돌아간다.
	#
	# 예전에는 빈 문자열을 돌려주고 "틀어 두던 걸 그대로 두라"는 뜻으로 썼는데,
	# 판이 끝날 때 _stop_bgm()이 이미 다 꺼 버린 뒤라 이어질 음악이 없었다.
	# 그래서 다시 시작하면 아무 소리도 나지 않았다.
	var mode_track: String = _resolve_audio(MODE_BGM_NAME[current_mode])
	if mode_track != "":
		return mode_track
	return _resolve_audio(BGM_MENU_NAME)


func _play_bgm(path: String) -> void:
	if path == "" or path == bgm_current_path:
		return  # nothing to switch to, or already on this track
	var incoming: int = 1 - bgm_active
	var outgoing: AudioStreamPlayer = bgm_players[bgm_active]
	var target: AudioStreamPlayer = bgm_players[incoming]
	var stream: AudioStream = load(path)
	_enable_stream_loop(stream)
	target.stream = stream
	target.volume_db = BGM_SILENT_DB
	target.play()
	bgm_active = incoming
	bgm_current_path = path
	if bgm_fade_tween != null and bgm_fade_tween.is_valid():
		bgm_fade_tween.kill()
	bgm_fade_tween = create_tween()
	bgm_fade_tween.set_parallel(true)
	bgm_fade_tween.tween_property(target, "volume_db", 0.0, BGM_CROSSFADE_TIME)
	bgm_fade_tween.tween_property(outgoing, "volume_db", BGM_SILENT_DB, BGM_CROSSFADE_TIME)
	bgm_fade_tween.chain().tween_callback(outgoing.stop)


func _stop_bgm() -> void:
	if bgm_fade_tween != null and bgm_fade_tween.is_valid():
		bgm_fade_tween.kill()
	for player in bgm_players:
		player.stop()
	bgm_current_path = ""


# Loop inside the stream rather than by restarting the player. Waiting for
# the finished signal and calling play() again costs at least a frame of
# silence, which is plainly audible on a music loop; the audio server's own
# loop is sample-accurate and seamless. (A track whose end does not lead
# musically back into its start will still sound like a seam — that is the
# music, not the playback. AudioStream's loop_offset is the knob for
# looping past an intro, if a track ever needs one.)
func _enable_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		# WAV는 루프 켜는 이름이 다르고, 임포트 기본값이 "루프 없음"이다.
		# 여기서 켜 두면 .import 파일 설정에 기대지 않아도 되고, 아트를
		# 다시 임포트해도 그대로다.
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# loop_end 는 "끝까지"가 아니라 마지막 프레임 번호다. 0으로 두면 길이
		# 0짜리 구간을 돌게 되어 재생이 첫 프레임에 그냥 끝난다. BGM 은 전부
		# .ogg 라 위 갈래로 빠져서 이게 드러나지 않았고, 부스트 홀드 소리가
		# 이 갈래를 처음 쓰면서 나왔다.
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))


func _on_bgm_finished(player: AudioStreamPlayer) -> void:
	# Only reached by a stream that could not be set to loop itself; the
	# faded-out player is on its way to stop and must not restart.
	if player == bgm_players[bgm_active]:
		player.play()


func _set_state(new_state: int) -> void:
	state = new_state
	# GAMEOVER keeps the existing behaviour of cutting the music (see
	# _game_over); every other screen gets the track that belongs to it.
	# LOGO 는 조용히 지나간다 — 음악은 스플래시부터.
	if state != State.GAMEOVER and state != State.LOGO:
		_play_bgm(_bgm_path_for_state())
	if new_state == State.LOGO:
		logo_elapsed = 0.0
	if new_state == State.SPLASH:
		splash_elapsed = 0.0
		splash_exit_elapsed = -1.0
	_apply_screen_visibility()
	# 카드의 BEST 판은 화면에 들어올 때마다 새로 채운다 — 방금 끝난 판에서
	# 기록을 갈아치웠을 수 있다.
	if state == State.MODE_SELECT:
		mode_select_panel.set_best_scores(best_scores)


# 지금 화면에 무엇이 보여야 하는가. _set_state 말고 _boot_load 끝에서도 부른다 —
# 로고가 떠 있는 동안 만들어진 노드(스플래시 캐릭터 층 등)는 기본값이 "보임"이라,
# 다시 적용하지 않으면 로고 위로 튀어나온다.
func _apply_screen_visibility() -> void:
	if splash_char_layer != null:
		splash_char_layer.visible = state == State.SPLASH
	_update_mute_button_visibility()
	mode_select_panel.visible = state == State.MODE_SELECT
	ready_panel.visible = state == State.READY
	gameover_panel.visible = state == State.GAMEOVER
	# 띄우는 쪽은 _finish_run(어느 갈래인지 아는 쪽)이라, 여기서는 끄기만 한다.
	if gameover_popup != null and state != State.GAMEOVER:
		gameover_popup.visible = false
	# 설정과 About 은 메인 화면에서만 열 수 있고, 화면이 바뀌면 닫는다.
	if settings_popup != null:
		settings_popup.visible = false
	if about_popup != null:
		about_popup.visible = false


# 음소거 버튼이 사라져야 하는 경우는 두 가지다.
#
# 하나는 화면 — 메뉴 화면들은 자체 음량 조절이 있고, 음소거 버튼은 모드 선택
# 화면이 설정 아이콘을 놓는 자리와 정확히 겹친다. 그래서 게임 화면 전용이다.
#
# 다른 하나는 팝업 — 부활 제안과 게임오버가 떠 있는 동안에는 뒤에 남아 있으면
# 안 된다. 이건 화면 상태만으로는 판별할 수 없다. 두 팝업 모두 GAMEOVER 상태에서
# 뜨지만, _offer_revive 는 게임오버 화면이 먼저 나타나지 않도록 _set_state 를
# 일부러 우회하고 state 를 직접 넣기 때문에 _apply_screen_visibility 가 아예
# 호출되지 않는다. 그래서 상태 대신 팝업 노드의 실제 표시 여부를 본다.
#
# 일시정지 버튼이 이미 두 팝업에서 알아서 사라지는 건 별개 이유다 — _process 가
# 매 프레임 PLAYING/COUNTDOWN 일 때만 켜는데 두 팝업은 GAMEOVER 라서 걸러진다.
func _update_mute_button_visibility() -> void:
	if mute_button == null:
		return
	var popup_open: bool = (revive_panel != null and revive_panel.visible) \
		or (gameover_popup != null and gameover_popup.visible)
	mute_button.visible = state != State.SPLASH and state != State.MODE_SELECT \
		and state != State.LOGO and not popup_open


# ---- Layer 3: HUD bar + quiz box (always drawn above the background/gate
# zone, per the layer-order spec) ----

# Source size of a HUD piece: the loaded texture's own size, or the sheet
# canvas size the slicer produced when it isn't loaded yet.
func _hud_src(texture: Texture2D, fallback: Vector2) -> Vector2:
	if texture == null:
		return fallback
	return Vector2(texture.get_width(), texture.get_height())


# Extra scale on the buttons so they end up exactly as tall as the score box.
func _hud_button_mult() -> float:
	var score_src := SCORE_BOX_SRC
	var button_src := _hud_src(pause_button.icon if pause_button != null else null, HUD_BUTTON_SRC)
	return (score_src.y / button_src.y) * HUD_BUTTON_EXTRA


# One scale for the whole top row, chosen so pause + score box + mute exactly
# fill the screen width inside the margins. Everything in the row is sized
# from this, so enlarging the buttons automatically takes width back off the
# score box instead of overflowing the screen.
func _hud_row_scale(view_size: Vector2) -> float:
	var score_src := SCORE_BOX_SRC
	var button_src := _hud_src(pause_button.icon if pause_button != null else null, HUD_BUTTON_SRC)
	var available: float = view_size.x - HUD_ROW_SIDE_MARGIN * 2.0 - HUD_ROW_GAP * 2.0
	return available / (score_src.x + button_src.x * 2.0 * _hud_button_mult())


# Screen rect of the score box art. The art is cropped tight to its frame, so
# this rect IS what you see.
func _score_box_rect(view_size: Vector2) -> Rect2:
	# 크기는 아트가 아니라 SCORE_BOX_SRC 비율로 정한다. 패널 아트는 2.9:1이라
	# 아트 비율을 따르면 박스가 세 배 높아진다 — 9-slice로 늘려 그리므로
	# 아트 비율에 맞출 이유가 없다.
	var src := SCORE_BOX_SRC
	# 높이는 버튼과 같은 식으로 뽑는다(HUD_BUTTON_EXTRA 한 번 더). 그래야
	# 세 조각의 위/아래 테두리가 한 줄에 딱 맞는다.
	var draw_size := Vector2(src.x * SCORE_BOX_WIDTH_TRIM, src.y * HUD_BUTTON_EXTRA) * _hud_row_scale(view_size)
	return Rect2(Vector2(view_size.x * 0.5 - draw_size.x * 0.5, SCORE_BOX_TOP), draw_size)


# Screen rect of the quiz box art, parked directly under the score box. It
# spans the full width inside the margins rather than following the row
# scale — it has no neighbours to share the line with.
func _quiz_box_rect(view_size: Vector2) -> Rect2:
	# 크기는 아트가 아니라 QUIZ_BOX_SRC 비율로 정한다.
	#
	# 새 아트는 테두리가 두꺼워 3.2:1인데(예전 아트는 10:1), 그 비율대로
	# 화면 폭을 채우면 박스 높이가 146px이 되어 레인이 10% 짧아진다.
	# 좌우 끝만 남기고 가운데를 늘리는 방식(_draw_horizontal_slice)으로
	# 그리므로 아트 비율에 맞출 이유가 없다.
	var src := QUIZ_BOX_SRC
	var width: float = view_size.x - HUD_ROW_SIDE_MARGIN * 2.0
	var draw_size := Vector2(width, width * src.y / src.x * QUIZ_BOX_HEIGHT_STRETCH)
	var top: float = _score_box_rect(view_size).end.y + QUIZ_BOX_GAP
	return Rect2(Vector2(view_size.x * 0.5 - draw_size.x * 0.5, top), draw_size)


# Sizes and parks the pause/mute buttons off the score box, so the three of
# them stay on one line if SCORE_BOX_TOP/WIDTH get retuned. Both buttons get
# the same rect size — their art shares a canvas (see the slicer note).
func _layout_hud_buttons() -> void:
	var view_size := get_viewport_rect().size
	var box := _score_box_rect(view_size)
	var size: Vector2 = _hud_src(pause_button.icon, HUD_BUTTON_SRC) * _hud_row_scale(view_size) * _hud_button_mult()
	# Bottom edge of the score box's painted art, then hang the buttons so
	# their own painted bottoms land on the same line.
	var score_art_bottom: float = box.position.y + box.size.y * MODE_SCORE_BOX_ART_BOTTOM_FRAC[current_mode]
	var top: float = score_art_bottom - size.y * MODE_HUD_BUTTON_ART_BOTTOM_FRAC[current_mode] + HUD_BUTTON_Y_OFFSET
	pause_button.set_deferred("size", size)
	pause_button.set_deferred("position", Vector2(HUD_ROW_SIDE_MARGIN, top))
	pause_button.set_deferred("pivot_offset", size * 0.5)
	mute_button.set_deferred("size", size)
	mute_button.set_deferred("position", Vector2(view_size.x - HUD_ROW_SIDE_MARGIN - size.x, top))
	mute_button.set_deferred("pivot_offset", size * 0.5)
	# Bottom-right corner, sized off its own constant rather than the HUD
	# row's scale — it belongs to the play area, not to the top bar.
	var boost_size := Vector2(BOOST_BUTTON_SIZE, BOOST_BUTTON_SIZE)
	boost_button.set_deferred("size", boost_size)
	boost_button.set_deferred("position", Vector2(
		view_size.x - BOOST_BUTTON_MARGIN - boost_size.x,
		view_size.y - BOOST_BUTTON_MARGIN - boost_size.y))
	boost_button.set_deferred("pivot_offset", boost_size * 0.5)


# Called from HudCanvas._draw. Everything here draws onto `ci` (the HUD's
# own canvas) rather than onto Main, which is the whole point — see
# scripts/HudCanvas.gd.
func draw_hud_into(ci: CanvasItem, view_size: Vector2) -> void:
	if state == State.PLAYING or state == State.COUNTDOWN:
		_draw_hud_bar(view_size, ci)
		_draw_quiz_box(view_size, ci)
		_draw_boost_bar(ci, view_size)
	_draw_combo_glow(view_size, ci)


# The three zones are painted across the WHOLE track at low alpha, not just
# under the fill: the point of the bar is to show where the boundaries are
# before you get there, so the bands have to stay visible in the part that
# has already drained. The fill then repaints 0..remaining at full strength
# in whichever zone the remaining amount currently falls in.
func _draw_boost_bar(ci: CanvasItem, view_size: Vector2) -> void:
	var rect := _boost_bar_rect(view_size)
	if rect.size.x <= 0.0:
		return
	if boost_bar_track_texture == null:
		return
	# Both pieces go through the same horizontal 3-slice the quiz box uses:
	# left cap, stretched middle, right cap. On a capsule the cap IS the
	# rounded end, so its width is half the art's height — that keeps the
	# ends round no matter how far the fill has drained.
	var track_cap: float = boost_bar_track_texture.get_height() * 0.5
	_draw_horizontal_slice(boost_bar_track_texture, rect, track_cap, ci)

	# The fill sits in the track's well, so it is inset by the rim on every
	# side rather than covering the whole rect.
	var inset: float = rect.size.y * BOOST_BAR_FILL_INSET_FRAC
	var well := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	var remaining: float = _boost_bar_remaining()
	var fill_texture: Texture2D = _boost_bar_fill_texture(remaining)
	if fill_texture != null and remaining > 0.0 and well.size.y > 0.0:
		var fill_rect := Rect2(well.position, Vector2(well.size.x * remaining, well.size.y))
		_draw_horizontal_slice(fill_texture, fill_rect, fill_texture.get_height() * 0.5, ci)

	# Threshold ticks last, so they read on top of both track and fill.
	for threshold: float in [boost_bonus_mid_threshold, boost_bonus_best_threshold]:
		var x: float = well.position.x + well.size.x * threshold
		ci.draw_line(Vector2(x, well.position.y), Vector2(x, well.end.y),
			BOOST_BAR_DIVIDER_COLOR, BOOST_BAR_DIVIDER_WIDTH)

	# Post-judgement highlight: the whole bar in the colour of the zone the
	# pass actually landed in, fading out.
	if boost_bar_flash_elapsed >= 0.0:
		var t: float = boost_bar_flash_elapsed / BOOST_BAR_FLASH_DURATION
		var alpha: float = BOOST_BAR_FLASH_ALPHA * clampf(1.0 - t, 0.0, 1.0)
		ci.draw_rect(rect, Color(boost_bar_flash_color.r, boost_bar_flash_color.g, boost_bar_flash_color.b, alpha))


# 빈 패널 위에 "SCORE" / 구분선 / 왕관+"BEST"를 얹는다. 예전 스코어 박스
# 아트에 그려져 있던 것들이라, 패널로 갈아끼우면서 코드로 옮겼다.
func _draw_score_box_labels(rect: Rect2, ci: CanvasItem) -> void:
	var font: Font = score_font if score_font != null else ThemeDB.fallback_font
	# SCORE — 왼쪽. 숫자와 같은 높이에 맞춘다.
	var score_size := int(round(rect.size.y * SCORE_LABEL_FONT_FRAC))
	var score_y: float = rect.position.y + rect.size.y * SCORE_NUMBER_MID_Y_FRAC + score_size * 0.35
	_draw_outlined_string(ci, font,
		Vector2(rect.position.x + rect.size.x * SCORE_LABEL_LEFT_FRAC, score_y),
		SCORE_LABEL_TEXT, score_size, SCORE_LABEL_FILL)

	# 두 칸을 가르는 세로 점선 대신 얇은 실선. 숫자가 오른쪽 정렬로 붙는 기준선이다.
	var dx: float = rect.position.x + rect.size.x * SCORE_NUM_RIGHT_FRAC
	var inset: float = rect.size.y * SCORE_DIVIDER_INSET_FRAC
	ci.draw_line(Vector2(dx, rect.position.y + inset), Vector2(dx, rect.end.y - inset),
		SCORE_DIVIDER_COLOR, SCORE_DIVIDER_WIDTH)

	# 왕관 + 최고 점수 — 오른쪽 칸. 글자 없이 왕관이 곧 "BEST"다.
	var best_mid_y: float = rect.position.y + rect.size.y * BEST_NUMBER_MID_Y_FRAC
	# 왕관 -> "BEST" -> 숫자 순서로 왼쪽부터 놓는다. 숫자만 오른쪽 테두리에
	# 붙여 오른쪽 정렬해, 자릿수가 늘어도 끝자리가 움직이지 않는다.
	var gap: float = rect.size.x * BEST_LABEL_GAP_FRAC
	var x: float = dx + rect.size.x * BEST_CROWN_LEFT_FRAC
	if score_crown_texture != null:
		# BEST_CROWN_HEIGHT_FRAC / LEFT_FRAC 은 "눈에 보이는 왕관" 기준이다.
		# 텍스처에 두른 투명 여백만큼 키우고 왼쪽으로 되돌려 그린다.
		var ink_frac: Vector2 = score_crown_texture.get_meta("ink_frac", Vector2.ONE)
		var ch: float = rect.size.y * BEST_CROWN_HEIGHT_FRAC / ink_frac.y
		var cw: float = ch * (float(score_crown_texture.get_width()) / float(score_crown_texture.get_height()))
		var cy: float = best_mid_y + rect.size.y * BEST_CROWN_Y_OFFSET_FRAC
		ci.draw_texture_rect(score_crown_texture,
			Rect2(x - cw * (1.0 - ink_frac.x) * 0.5, cy - ch * 0.5, cw, ch), false)
		x += cw * ink_frac.x + gap
	var best_size := int(round(rect.size.y * BEST_LABEL_FONT_FRAC))
	_draw_outlined_string(ci, font, Vector2(x, best_mid_y + best_size * 0.35),
		BEST_LABEL_TEXT, best_size, BEST_LABEL_FILL)
	# 점수와 마찬가지로 음영/테두리만 여기서. 속은 draw_best_fill_into 가
	# 전용 캔버스에 칠한다.
	var best_layout := _best_digit_layout(rect)
	var best_digits: String = best_layout["text"]
	var best_pos: PackedVector2Array = best_layout["pos"]
	for i in range(best_digits.length()):
		_draw_outlined_string(ci, font, best_pos[i], best_digits[i],
			best_layout["size"], Color(0, 0, 0, 0))


func _draw_hud_bar(view_size: Vector2, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	# PauseButton/MuteButton (real Control/Button nodes, see scene) occupy the
	# top-left/top-right corners; nothing drawn here for them. Combo lives
	# entirely in the gate zone's top-right corner as a per-pass effect (see
	# _draw_combo_popups), not here — this only ever draws the score box.
	if score_box_texture != null:
		var rect := _score_box_rect(view_size)
		if SCORE_BOX_PANEL_VISIBLE:
			_draw_nine_patch(score_box_texture, rect.grow(SCORE_PANEL_ART_PAD * SCORE_PANEL_SCALE),
				GATE_PANEL_CORNER + GATE_PANEL_PAD, SCORE_PANEL_SCALE, ci)
		_draw_score_box_labels(rect, ci)
		# Two halves of the same box, each number matched to its own painted
		# label rather than sharing one size and line: the live score is the
		# big one, right-aligned to just inside the divider so its ones digit
		# never moves; the stored best is the small one, left-aligned so it
		# sits directly beside the word BEST.
		# 음영과 테두리만 여기서. 속(그라데이션)은 draw_score_fill_into 가
		# 전용 캔버스에 칠한다.
		var layout := _score_digit_layout(view_size)
		var digits: String = layout["text"]
		var digit_pos: PackedVector2Array = layout["pos"]
		for i in range(digits.length()):
			_draw_outlined_string(ci, layout["font"], digit_pos[i], digits[i],
				layout["size"], Color(0, 0, 0, 0))
	else:
		ci.draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, HUD_BAR_HEIGHT)), HUD_BAR_COLOR)
		_draw_centered_text("SCORE %d  BEST %d" % [score, _best_for(current_mode)], Vector2(view_size.x * 0.5, HUD_BAR_HEIGHT * 0.5), 18, COLOR_TEXT, COLOR_TEXT_OUTLINE, null, ci)


func _draw_quiz_box(view_size: Vector2, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	# OCEAN's question is a painted colour, not a string, so it takes over
	# the whole box rather than feeding text into the path below.
	if current_mode == Mode.OCEAN:
		_draw_ocean_quiz_box(view_size, ci)
		return
	var upcoming_target := _get_upcoming_target()
	if upcoming_target == "":
		return
	var box_top: float = _quiz_box_rect(view_size).position.y
	var text: String = upcoming_target
	if quiz_box_texture != null:
		var rect := _quiz_box_rect(view_size)
		var draw_size: Vector2 = rect.size
		var top_left: Vector2 = rect.position
		_draw_horizontal_slice(quiz_box_texture, rect, QUIZ_BOX_CAP, ci)
		var pad: float = draw_size.x * QUIZ_TEXT_SIDE_PAD_FRAC
		var area_left: float = top_left.x + draw_size.x * QUIZ_TEXT_LEFT_FRAC + pad
		var area_right: float = top_left.x + draw_size.x * QUIZ_TEXT_RIGHT_FRAC - pad
		var max_width: float = area_right - area_left
		# Sized off the box WIDTH on purpose — see QUIZ_TEXT_MAX_FONT_FRAC.
		var max_font_size: int = int(round(draw_size.x * QUIZ_TEXT_MAX_FONT_FRAC))
		var min_font_size: int = int(round(draw_size.x * QUIZ_TEXT_MIN_FONT_FRAC))
		var font_size := _fit_font_size(text, max_width, max_font_size, min_font_size, combo_font)
		# Centred within the writing area — the part of the box left over once
		# the painted "QUIZ" pill is excluded — not within the box as a whole.
		var text_center := Vector2((area_left + area_right) * 0.5, top_left.y + draw_size.y * QUIZ_TEXT_CENTER_Y_FRAC)
		_draw_centered_text(text, text_center, font_size, Color(0.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 0.0, 0.0), combo_font, ci, QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC)
	else:
		var box_rect := Rect2(Vector2(QUIZ_BOX_MARGIN, box_top), Vector2(view_size.x - QUIZ_BOX_MARGIN * 2.0, _quiz_box_rect(view_size).size.y))
		var style := StyleBoxFlat.new()
		style.bg_color = QUIZ_BOX_COLOR
		style.set_corner_radius_all(int(QUIZ_BOX_CORNER_RADIUS))
		ci.draw_style_box(style, box_rect)
		var max_width: float = box_rect.size.x - QUIZ_BOX_MARGIN
		var font_size := _fit_font_size(text, max_width, 22, 14)
		_draw_centered_text(text, box_rect.get_center(), font_size, COLOR_TEXT_DARK, Color(COLOR_TEXT_DARK.r, COLOR_TEXT_DARK.g, COLOR_TEXT_DARK.b, 0.0), null, ci)


# ============================================================
# OCEAN mode's question box. Lays out one row inside the same writing area
# the other modes' text uses — prompt on the left, the painted word on the
# right, centred as a pair.
# ============================================================

# First gate whose question hasn't been answered yet — the one the box is
# currently asking about. Sibling of _get_upcoming_target, which returns a
# bare string and so can't carry a colour.
func _get_upcoming_ocean_gate() -> Dictionary:
	for g in gates:
		if not g.resolved and g.has("ocean_answer_index"):
			return g
	return {}


# Left-aligned sibling of _draw_centered_text. The prompt and the stimulus
# are laid out as one row, so both have to be placed by their left edge and
# share the one measured baseline.
func _draw_ocean_text(ci: CanvasItem, text: String, left_x: float, center_y: float, font_size: int, fill: Color, outline: Color, outline_px: float) -> void:
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var pos := Vector2(left_x, center_y + font_size * QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC)
	if outline_px > 0.0 and outline.a > 0.0:
		for dx in [-outline_px, 0.0, outline_px]:
			for dy in [-outline_px, 0.0, outline_px]:
				if dx == 0.0 and dy == 0.0:
					continue
				ci.draw_string(font, pos + Vector2(dx, dy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill)


func _draw_ocean_quiz_box(view_size: Vector2, ci: CanvasItem) -> void:
	var g: Dictionary = _get_upcoming_ocean_gate()
	if g.is_empty():
		return
	var rect := _quiz_box_rect(view_size)
	if quiz_box_texture != null:
		_draw_horizontal_slice(quiz_box_texture, rect, QUIZ_BOX_CAP, ci)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = QUIZ_BOX_COLOR
		style.set_corner_radius_all(int(QUIZ_BOX_CORNER_RADIUS))
		ci.draw_style_box(style, rect)

	# Blank writing area inside the box art, right of the painted "QUIZ"
	# label — the same one the flag/math text is centred in.
	var pad: float = rect.size.x * QUIZ_TEXT_SIDE_PAD_FRAC
	var area_left: float = rect.position.x + rect.size.x * QUIZ_TEXT_LEFT_FRAC + pad
	var area_right: float = rect.position.x + rect.size.x * QUIZ_TEXT_RIGHT_FRAC - pad
	var area_width: float = area_right - area_left
	var center_y: float = rect.position.y + rect.size.y * QUIZ_TEXT_CENTER_Y_FRAC

	var word: String = OCEAN_COLOR_NAMES[g.ocean_word_index]
	var ink_color: Color = OCEAN_COLOR_RGB[g.ocean_answer_index]
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font

	# Shrink the pair together until the row fits the writing area. The
	# prompt is static and read once, the word is re-read every gate, so the
	# prompt stays the smaller of the two at every size (see
	# OCEAN_PROMPT_SIZE_RATIO). Bounded by the floor, so this always ends.
	var word_size: int = int(round(rect.size.x * QUIZ_TEXT_MAX_FONT_FRAC))
	var min_word_size: int = int(round(rect.size.x * OCEAN_STIMULUS_MIN_FONT_FRAC))
	var gap: float = rect.size.x * OCEAN_PROMPT_GAP_FRAC
	var prompt_size: int = 0
	var prompt_width: float = 0.0
	var word_width: float = 0.0
	while true:
		prompt_size = maxi(OCEAN_PROMPT_MIN_FONT, int(round(word_size * OCEAN_PROMPT_SIZE_RATIO)))
		prompt_width = font.get_string_size(OCEAN_PROMPT_INK, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_size).x
		word_width = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, word_size).x
		if prompt_width + gap + word_width <= area_width or word_size <= min_word_size:
			break
		word_size -= 1

	var cursor_x: float = (area_left + area_right) * 0.5 - (prompt_width + gap + word_width) * 0.5
	_draw_ocean_text(ci, OCEAN_PROMPT_INK, cursor_x, center_y, prompt_size, COLOR_TEXT_DARK, Color(0.0, 0.0, 0.0, 0.0), 0.0)
	cursor_x += prompt_width + gap

	# The answer is the INK. Outlined because a YELLOW or WHITE word would
	# otherwise wash out against the cream box art; the same outline goes on
	# every colour so it never becomes a hint.
	_draw_ocean_text(ci, word, cursor_x, center_y, word_size, ink_color, OCEAN_INK_OUTLINE_COLOR, OCEAN_INK_OUTLINE_PX)


func _draw() -> void:
	var view_size := get_viewport_rect().size
	if state == State.LOGO:
		_draw_logo(view_size)
		return
	if state == State.SPLASH:
		_draw_splash(view_size)
		return
	if bg_texture != null:
		_draw_sky_background(view_size)     # single scrolling background image — see _draw_sky_background
		_draw_ambient_particles()           # small twinkle/leaf/bubble particles, still behind the gate zone
	else:
		_draw_sky_gradient(view_size)          # Layer 0
		_draw_mountains()                      # Layer 1
		_draw_bg_sparkles()                    # Layer 2
		_draw_cloud_mid(false)                 # Layer 4, far sub-group — drawn BEHIND the castle (see below)
		_draw_castle()                         # Layer 3 — drawn between the far/near cloud sub-groups on purpose:
												# a far cloud is very translucent (alpha ~0.3-0.5), so layering it
												# OVER the also-translucent castle just double-fades into a muddy
												# blend the castle shows straight through — not a convincing
												# occlusion. Near clouds are opaque enough (~0.85-1.0) to still
												# read as genuinely passing in front when they cross the castle.
		_draw_cloud_mid(true)                  # Layer 4, near sub-group

	# ---- Layer 2: gate zone (gates, center wall, bird) ----
	var wall_center_y := _gate_wall_center_y(view_size)
	var wall_top := wall_center_y - WALL_THICKNESS * 0.5
	var wall_bottom := wall_center_y + WALL_THICKNESS * 0.5

	# Base pedestal drawn first (furthest back) so the ring always renders in
	# front of it — see _draw_gate_base.
	for g in gates:
		_draw_gate_base(g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5)
		_draw_gate_base(g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5)

	# Right pillar drawn behind the bird (bird occludes it while passing that
	# side), left pillar drawn in front (it occludes the bird while passing
	# that side) — that's what sells the bird actually passing *through* the
	# gate instead of just sliding across a flat picture.
	for g in gates:
		_draw_gate_frame_layer(gate_right_pillar_texture, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"), _gate_glow_tint(g, "top"))
		_draw_gate_frame_layer(gate_right_pillar_texture, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"), _gate_glow_tint(g, "bottom"))

	for g in gates:
		var wall_rect := Rect2(Vector2(g.x, wall_top), Vector2(GATE_WIDTH, WALL_THICKNESS))
		draw_rect(Rect2(Vector2(g.x, g.top_zone_top), Vector2(GATE_WIDTH, g.top_zone_bottom - g.top_zone_top)), COLOR_ZONE)
		draw_rect(Rect2(Vector2(g.x, g.bottom_zone_top), Vector2(GATE_WIDTH, g.bottom_zone_bottom - g.bottom_zone_top)), COLOR_ZONE)
		draw_rect(wall_rect, COLOR_WALL)

	_draw_bird_trail()   # behind the bird, and behind the speed lines
	_draw_speed_lines()  # behind the bird

	if state != State.READY and state != State.MODE_SELECT:
		# Stretch (see _bird_stretch_scale) and the happy pop/bounce (see
		# _happy_pop_scale/_happy_pop_bounce_offset) are both draw-time-only —
		# player_y/PLAYER_X/PLAYER_SIZE and collision never change. They
		# multiply/add together rather than one replacing the other, so a
		# gate pass reads as one continuous "impact squash, then happy
		# bounce" motion instead of two competing effects.
		var bird_texture: Texture2D
		var draw_offset: Vector2
		if state == State.GAMEOVER and sad_face_texture != null:
			# Static — no flap cycling once the run has ended.
			bird_texture = sad_face_texture
			draw_offset = active_draw_offset_sad
		elif happy_flap_elapsed >= 0.0 and happy_face_texture != null:
			# Single static frame — no cycling, reverts to fly on its own
			# once happy_flap_elapsed passes HAPPY_FLAP_DURATION (_update_fx).
			bird_texture = happy_face_texture
			draw_offset = active_draw_offset_happy
		else:
			# Guarded rather than a bare index — an unfinished asset sync (or a
			# bad mode path) leaving flap_frames empty would otherwise throw
			# an out-of-bounds error every single frame here, which reads as
			# the whole game freezing rather than "the bird just doesn't draw".
			bird_texture = flap_frames[flap_frame_index] if flap_frame_index < flap_frames.size() else null
			draw_offset = active_draw_offset_fly
		var bird_scale: Vector2 = _bird_stretch_scale() * _happy_pop_scale() * active_visual_size_scale
		var pos := Vector2(PLAYER_X, player_y + _happy_pop_bounce_offset())
		# Behind the character, and deliberately not inside the bird_texture
		# null-check below: the halo is the boost's own feedback and should
		# still show if a mode's sprite failed to load.
		_draw_boost_glow(pos)
		if bird_texture != null:
			draw_set_transform(pos, 0.0, bird_scale)
			draw_texture_rect(bird_texture, Rect2(-PLAYER_VISUAL_SIZE * 0.5 + draw_offset, PLAYER_VISUAL_SIZE), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Over the character, not behind it like the glow: this is something
		# thrown OFF the body, and the art is a ring with an empty middle, so
		# the character still reads through it.
		_draw_boost_burst(pos)
		if DEBUG_SHOW_HITBOX:
			# The REAL collision rect — PLAYER_SIZE at (PLAYER_X, player_y),
			# untouched by bird_scale/draw_offset/happy-bounce above, since
			# those are visual-only and never affect actual collision math
			# (see _resolve_gate/_update_playing). Temporary tuning aid.
			var hitbox_rect := Rect2(Vector2(PLAYER_X, player_y) - PLAYER_SIZE * 0.5, PLAYER_SIZE)
			draw_rect(hitbox_rect, DEBUG_HITBOX_COLOR, false, 2.0)

	for g in gates:
		_draw_gate_frame_layer(gate_left_pillar_texture, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"), _gate_glow_tint(g, "top"))
		_draw_gate_frame_layer(gate_left_pillar_texture, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"), _gate_glow_tint(g, "bottom"))

	# Answer boxes (flag icon, or a number for JUNGLE's math quiz) drawn last
	# (topmost) of everything gate-related, after both ring halves and the
	# bird, so they can never end up hidden behind the ring art — see
	# _draw_gate_answer_box.
	for g in gates:
		_draw_gate_answer_box(g.top_code, g.x, g.top_zone_top, g.top_zone_bottom, view_size)
		_draw_gate_answer_box(g.bottom_code, g.x, g.bottom_zone_top, g.bottom_zone_bottom, view_size)

	# ---- Layer 3: HUD bar + quiz box ----
	# Drawn by the HudCanvas child instead of here, so it can use its own
	# texture filter. The child renders after this whole _draw, which keeps
	# the HUD above the gate zone as before — see draw_hud_into.

	# ---- Layer 4: effects layer (top of everything drawn above) ----
	_draw_impact_flashes()
	_draw_sparks()
	if debug_show_zones and (state == State.PLAYING or state == State.COUNTDOWN):
		_draw_debug_zones(view_size)
	_draw_boost_pop(view_size)
	_draw_combo_popups(view_size)
	# _draw_combo_glow also moved to HudCanvas: its top band overlaps the
	# score box, and it has to stay on top of it the way it was here.

	if state == State.COUNTDOWN:
		var countdown_center := Vector2(view_size.x * 0.5, view_size.y * 0.5)
		if countdown_phase == CountdownPhase.READY_TEXT:
			if ready_texture != null:
				_draw_countdown_image(ready_texture, countdown_center, 1.0, COUNTDOWN_READY_WIDTH)
			else:
				_draw_centered_text("READY", countdown_center, 36)
		else:
			var t: float = 1.0 - (countdown_timer / COUNTDOWN_START_DURATION)
			var pop_scale: float = _pop_scale(t)
			if start_texture != null:
				_draw_countdown_image(start_texture, countdown_center, pop_scale, COUNTDOWN_START_WIDTH)
			else:
				_draw_centered_text("START", countdown_center, int(round(36.0 * pop_scale)))

	if flash_time > 0.0:
		var a: float = flash_color.a * (flash_time / FLASH_DURATION)
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(flash_color.r, flash_color.g, flash_color.b, a))
	# Layer 5 (pause menu / game-over panel) is real Control nodes in the UI
	# CanvasLayer, which already renders above all of this Node2D's _draw()
	# content — nothing to do here for it.


func _draw_countdown_image(texture: Texture2D, center: Vector2, scale_mult: float, width: float) -> void:
	# 슬라이서가 글자 중심을 캔버스 정가운데에 맞춰 두었으므로, 캔버스를
	# `center` 에 가운데 맞춰 그리기만 하면 모드가 바뀌어도 글자가 안 움직인다.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var draw_size: Vector2 = tex_size * (width / tex_size.x) * scale_mult
	draw_texture_rect(texture, Rect2(center - draw_size * 0.5, draw_size), false)


func _pop_scale(t: float) -> float:
	# t: 0..1 progress through the "START" display. Quick overshoot, then
	# eases back down to 1.0x for a short "pop" feel.
	#
	# 최고점은 START 가 화면 밖으로 나가지 않는 선에서 최대로 잡는다. 캔버스
	# 664px 중 START 그림이 616px(0.928)이므로, 화면 폭 480 을 넘지 않으려면
	# COUNTDOWN_START_WIDTH * PEAK_SCALE * 0.928 <= 480, 즉 400 기준 1.29 까지.
	# 여유를 두고 1.22 — 튀는 맛이 있어야 "출발" 느낌이 산다.
	const PEAK_T := 0.35
	if t < PEAK_T:
		return lerpf(1.0, POP_PEAK_SCALE, t / PEAK_T)
	return lerpf(POP_PEAK_SCALE, 1.0, (t - PEAK_T) / (1.0 - PEAK_T))


func _get_upcoming_target() -> String:
	for g in gates:
		if not g.resolved:
			return g.target_name
	return ""


# `ci` lets the HUD render this onto its own canvas (see HudCanvas.gd);
# every other caller leaves it null and draws onto Main as before.
func _draw_centered_text(text: String, center: Vector2, font_size: int, fill_color: Color = COLOR_TEXT, outline_color: Color = COLOR_TEXT_OUTLINE, font: Font = null, ci: CanvasItem = null, baseline_frac: float = 0.0) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	if ci == null:
		ci = self
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	# baseline_frac > 0 puts the baseline a measured fraction of the font size
	# below `center`, which centres the glyphs on their actual ink rather than
	# on the font's line box. The line-box fallback below sits the text
	# slightly high, since the descent it counts is space most strings never
	# use; callers that care (the quiz box) pass the measured value instead.
	var baseline_offset: float = font_size * baseline_frac if baseline_frac > 0.0 else text_size.y * 0.25
	var pos := Vector2(center.x - text_size.x * 0.5, center.y + baseline_offset)
	# Dark outline so the light default HUD text still reads over the pastel
	# sky — callers drawing over a light background (the quiz box) pass a
	# dark fill_color instead, at which point the outline just adds a touch
	# of contrast rather than doing the main legibility work.
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ci.draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, fill_color)


func _draw_right_aligned_text(text: String, right_center: Vector2, font_size: int, fill_color: Color = COLOR_TEXT, outline_color: Color = COLOR_TEXT_OUTLINE, font: Font = null) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(right_center.x - text_size.x, right_center.y + text_size.y * 0.25)
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


# Same as _draw_right_aligned_text but inserts extra_spacing px between each
# character — draw_string has no per-glyph tracking control, so each glyph
# is measured and placed individually, right-to-left, to add breathing room
# between the score panel's tightly-kerned digits.
# Draws a run of digits on a fixed grid. `anchor` is the vertical centre plus
# either the right edge (align_right) or the left edge of the run.
func _draw_spaced_digits(text: String, anchor: Vector2, font_size: int, extra_spacing: float, align_right: bool, fill_color: Color = COLOR_TEXT, outline_color: Color = COLOR_TEXT_OUTLINE, font: Font = null, ci: CanvasItem = null) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	if ci == null:
		ci = self
	# Every glyph gets the same cell width — the widest digit — and is centred
	# in it. Fredoka's figures are not tabular ("1" is 40 units wide against
	# "2" at 61), so advancing by each glyph's own width would make the score
	# visibly reflow every time a digit changed. Forcing a uniform cell makes
	# the number sit rock-steady no matter what it counts up to, without
	# depending on the font having tabular figures at all.
	var positions := _digit_positions(text, anchor, font_size, extra_spacing, align_right, font)
	for i in range(text.length()):
		var ch: String = text[i]
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			ci.draw_string(font, positions[i] + offset, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)
		ci.draw_string(font, positions[i], ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


# 각 자리를 그릴 위치. 음영/테두리/속을 서로 다른 캔버스에 나눠 그려도
# 자리가 어긋나지 않도록, 계산은 여기 한 곳에만 둔다.
#
# 자리마다 폭이 같은 칸(가장 넓은 숫자 폭)을 주고 그 안에 가운데 정렬한다.
# Fredoka 의 숫자는 폭이 제각각이라("1" 40, "2" 61), 글자 폭대로 밀면 숫자가
# 바뀔 때마다 점수 전체가 들썩인다. 칸을 고정하면 무엇을 세든 자리가 고정된다.
#
# 세로는 draw_string 이 베이스라인을 받는데 anchor.y 는 "눈에 가운데로 보이는"
# 높이다. 줄 높이로 가운데를 잡으면 숫자가 쓰지 않는 디센더 공간 때문에 위로
# 뜬다 — DIGIT_BASELINE_FROM_CENTER_FRAC 이 그래서 있다.
func _digit_positions(text: String, anchor: Vector2, font_size: int, extra_spacing: float,
		align_right: bool, font: Font) -> PackedVector2Array:
	var cell := 0.0
	for d in range(10):
		cell = maxf(cell, font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var total_width: float = cell * text.length() + extra_spacing * maxi(0, text.length() - 1)
	var cursor_x: float = anchor.x - total_width if align_right else anchor.x
	var y: float = anchor.y + font_size * DIGIT_BASELINE_FROM_CENTER_FRAC
	var out := PackedVector2Array()
	for i in range(text.length()):
		var w: float = font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		out.append(Vector2(cursor_x + (cell - w) * 0.5, y))
		cursor_x += cell + extra_spacing
	return out


# 바깥부터 음영 -> 검은 테두리 -> 속. fill_color 의 알파가 0 이면 속은
# 건너뛴다 — 점수 숫자처럼 속을 다른 캔버스에 칠할 때 쓴다.
func _draw_outlined_string(ci: CanvasItem, font: Font, pos: Vector2, text: String,
		font_size: int, fill_color: Color) -> void:
	var ring: float = maxf(1.0, font_size * TEXT_OUTLINE_FONT_FRAC)
	var shadow := Vector2(0.0, font_size * TEXT_SHADOW_FONT_FRAC)
	for o in TEXT_OUTLINE_RING:
		ci.draw_string(font, pos + shadow + o * ring, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SCORE_TEXT_SHADOW)
	for o in TEXT_OUTLINE_RING:
		ci.draw_string(font, pos + o * ring, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SCORE_TEXT_OUTLINE)
	if fill_color.a > 0.0:
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


# 점수 숫자의 글꼴 크기와 자리, 그리고 잉크의 위/아래 끝. 테두리(HUD 캔버스)와
# 속(그라데이션 캔버스)을 따로 그리므로 두 곳에서 같은 답이 나와야 한다.
func _score_digit_layout(view_size: Vector2) -> Dictionary:
	var rect := _score_box_rect(view_size)
	var font: Font = score_font if score_font != null else ThemeDB.fallback_font
	var font_size := int(round(rect.size.y * SCORE_NUMBER_FONT_FRAC))
	var text := "%05d" % score
	var anchor := Vector2(
		rect.position.x + rect.size.x * (SCORE_NUM_RIGHT_FRAC - SCORE_NUMBER_RIGHT_INSET_FRAC),
		rect.position.y + rect.size.y * SCORE_NUMBER_MID_Y_FRAC)
	var baseline: float = anchor.y + font_size * DIGIT_BASELINE_FROM_CENTER_FRAC
	return {
		"font": font,
		"size": font_size,
		"text": text,
		"pos": _digit_positions(text, anchor, font_size, SCORE_NUMBER_DIGIT_SPACING, true, font),
		"ink_top": baseline - font_size * DIGIT_INK_ABOVE_FRAC,
		"ink_bottom": baseline + font_size * DIGIT_INK_BELOW_FRAC,
	}


# 세로 그라데이션 셰이더를 건 캔버스 하나. HUD 캔버스보다 뒤에 붙으므로
# 여기 그리는 속칠이 테두리 위에 얹힌다.
func _make_gradient_canvas(node_name: String, method: String, top: Color, bottom: Color) -> Node2D:
	var shader := Shader.new()
	shader.code = SCORE_FILL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("bottom_color", bottom)
	var canvas := Node2D.new()
	canvas.name = node_name
	canvas.set_script(load(HUD_CANVAS_SCRIPT_PATH))
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.material = mat
	canvas.main = self
	canvas.draw_method = method
	add_child(canvas)
	return canvas


# 최고 점수 숫자의 글꼴 크기와 자리. 점수와 달리 왕관/"BEST" 흐름과 무관하게
# 박스 오른쪽 테두리에 오른쪽 정렬이라, 박스 사각형만 있으면 나온다.
func _best_digit_layout(rect: Rect2) -> Dictionary:
	var font: Font = score_font if score_font != null else ThemeDB.fallback_font
	var font_size := int(round(rect.size.y * BEST_NUMBER_FONT_FRAC))
	var text := "%05d" % _best_for(current_mode)
	var anchor := Vector2(rect.end.x - rect.size.x * BEST_NUMBER_RIGHT_INSET_FRAC,
		rect.position.y + rect.size.y * BEST_NUMBER_MID_Y_FRAC)
	var baseline: float = anchor.y + font_size * DIGIT_BASELINE_FROM_CENTER_FRAC
	return {
		"font": font,
		"size": font_size,
		"text": text,
		"pos": _digit_positions(text, anchor, font_size, SCORE_NUMBER_DIGIT_SPACING, true, font),
		"ink_top": baseline - font_size * DIGIT_INK_ABOVE_FRAC,
		"ink_bottom": baseline + font_size * DIGIT_INK_BELOW_FRAC,
	}


# BestFillCanvas._draw 에서 불린다. 최고 점수 숫자의 속만.
func draw_best_fill_into(ci: CanvasItem, view_size: Vector2) -> void:
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	if score_box_texture == null or best_fill_material == null:
		return
	var layout := _best_digit_layout(_score_box_rect(view_size))
	best_fill_material.set_shader_parameter("y_top", layout["ink_top"])
	best_fill_material.set_shader_parameter("y_bottom", layout["ink_bottom"])
	var positions: PackedVector2Array = layout["pos"]
	var text: String = layout["text"]
	for i in range(text.length()):
		ci.draw_string(layout["font"], positions[i], text[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, layout["size"], Color(1.0, 1.0, 1.0, 1.0))


# ScoreFillCanvas._draw 에서 불린다. 이 캔버스에는 세로 그라데이션 셰이더가
# 걸려 있으므로 점수 숫자의 속 말고는 아무것도 그리지 않는다.
func draw_score_fill_into(ci: CanvasItem, view_size: Vector2) -> void:
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	if score_box_texture == null or score_fill_material == null:
		return
	var layout := _score_digit_layout(view_size)
	score_fill_material.set_shader_parameter("y_top", layout["ink_top"])
	score_fill_material.set_shader_parameter("y_bottom", layout["ink_bottom"])
	var positions: PackedVector2Array = layout["pos"]
	var text: String = layout["text"]
	for i in range(text.length()):
		ci.draw_string(layout["font"], positions[i], text[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, layout["size"], Color(1.0, 1.0, 1.0, 1.0))


func _fit_font_size(text: String, max_width: float, max_size: int, min_size: int, font: Font = null) -> int:
	if font == null:
		font = ThemeDB.fallback_font
	var size := max_size
	while size > min_size:
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		if w <= max_width:
			break
		size -= 1
	return size
