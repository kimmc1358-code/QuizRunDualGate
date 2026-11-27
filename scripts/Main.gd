extends Node2D

## The run: score, combo, hearts, the revive offer, the popups, the
## play-screen HUD, the logo and title screens, audio, ads and the save. The
## 3D world and the rules of contact are SpaceRun's (scripts/SpaceRun.gd),
## which reports each outcome through the _space_* handlers below.

# The 1.x modes. Kept because the per-mode best scores, their save keys and
# the leaderboards (MODE_LEADERBOARD_ID) are indexed by them; the mode select
# hands over its card's index (ModeSelectScreen.CARD_MODES), and only QUIZ
# RUN (0) can start a run yet.
enum Mode { SKY, JUNGLE, OCEAN, DREAM }

# The faces the revive and game over popups and the share card show: happy
# for a new record, sad otherwise. Slots for now (ArtSlot) at the 1.x bird's
# paths, which ArtSlot still sizes; 2.0 art dropped there is used as is.
const FACE_HAPPY_PATH := "res://assets/characters/bird_v2/bird_happy.png"
const FACE_SAD_PATH := "res://assets/characters/bird_v2/bird_sad.png"
# The size the popups draw a face at (logical px) — the bird's in-game size
# in 1.x (100px x its 0.92 scale), which the popup layouts were built around.
const FACE_DRAW_SIZE := 92.0


# ============================================================
# Art filtering.
#
# Linear + mipmaps for everything Main draws: none of it is authored at 1:1,
# and nearest-neighbour minification just point-samples, dropping most of the
# source pixels, which is what chews up thin outlines and leaves ragged edges.
#
# Flip this to false to get hard edges back — that single edit is the whole
# revert. (Nearest ignores mipmaps, so the mipmap flags in the *.import files
# are harmless either way.) The top HUD is filtered separately and stays
# smooth regardless — see scripts/HudCanvas.gd.
const SMOOTH_WORLD_FILTER := true

# Top HUD: one row of pause | score box (the mute button left on 2026-11-26;
# sound lives in settings), with the quiz row directly under it. The row is
# laid out at a single shared scale, so the button keeps its size
# relationship to the score box.
#
# The scale falls out of filling the screen width (see _hud_row_scale), so
# the knobs here are the margins and gaps, not the widths. _score_box_rect,
# _quiz_row_rect and the three slots split from it are the only places that
# turn any of this into screen rects.
const SCORE_BOX_TOP := 16.0          # screen y of the top HUD row — the single knob that moves the whole HUD (button, score box and quiz row all derive from it)
const HUD_ROW_SIDE_MARGIN := 6.0     # screen edge -> pause button
const HUD_ROW_GAP := 4.0             # button -> score box
const QUIZ_BOX_GAP := 7.0            # score box bottom edge -> quiz box top edge
# 둘째 줄 양옆 칸(체력 | 스타더스트)의 폭 — 둘이 같은 크기라 문제 박스가
# 가운데에 온다(_quiz_box_rect). 룰렛이 있던 칸을 2026-11-27 스타더스트가
# 물려받았다. 문제 박스는 그 나머지 — 480 폭에서 약 316px.
const SIDE_SLOT_WIDTH := 70.0
const HUD_SLOT_GAP := 6.0
# Pause is scaled so its height matches the score box's exactly, which is
# what makes the top row read as one flush band. Derived from the art rather
# than hard-coded, so it still holds if the art is redrawn — see
# _hud_button_mult. This is a further nudge on top of that: >1 makes the
# button overhang the row.
# 버튼 높이 = 스코어박스 높이 x 이 값인데, 버튼을 키우면 행 배율이 줄어
# 스코어박스가 같이 작아진다. 그 되먹임까지 풀어서 얻은 값이다 — 이 값이면
# 버튼이 퀴즈 박스와 같은 57.5px가 된다.
const HUD_BUTTON_EXTRA := 0.9517
const HUD_BUTTON_Y_OFFSET := 0.0     # nudge the button down (+) or up (-) from the score box's bottom edge
# Stretches the quiz box taller than its art's aspect. The box already spans
# the full screen width, so it cannot grow taller proportionally.
#
# 그래도 양 끝 장식은 안 깨진다: _draw_horizontal_slice 가 좌우 끝
# HUD_QUIZ_BOX_CAP 만큼은 세로 배율과 같은 배율로(찌그러짐 없이) 그리고,
# 늘어나는 것은 가운데 밋밋한 테두리 구간뿐이기 때문이다.
# The quiz TEXT does not grow with it; see QUIZ_TEXT_*_FONT_FRAC.
const QUIZ_BOX_HEIGHT_STRETCH := 1.429
# 세 조각의 '그려질 비율'. 아트를 재서 나온 값이 아니라 정해 둔 값이다 —
# 점수 박스와 퀴즈 박스는 늘려 그리므로 원본 비율을 따르면 각각 세 배, 1.6 배로
# 두꺼워진다(_score_box_rect / _quiz_row_rect 의 주석 참고). 즉 이 셋은
# 측정값이 아니라 튜닝값이다.
#
# 아트가 없을 때의 대체 비율로도 쓰인다 — 실제 텍스처가 있으면 그쪽이 이긴다.
const SCORE_BOX_SRC := Vector2(937.0, 135.0)
const QUIZ_BOX_SRC := Vector2(1190.0, 117.0)
const HUD_BUTTON_SRC := Vector2(117.0, 109.0)
# 글자는 박스 전체를 쓰고 양 끝 장식만 피한다. 그 장식은 늘어나지 않고 고정
# 폭으로 그려지므로 비율도 박스 폭에 대한 그 폭으로 잡는다.
const QUIZ_TEXT_LEFT_FRAC := 0.14         # of width — clear of the frame's orange end caps
const QUIZ_TEXT_RIGHT_FRAC := 0.86
const QUIZ_TEXT_SIDE_PAD_FRAC := 0.020    # of width — keeps text off both edges
const QUIZ_TEXT_CENTER_Y_FRAC := 0.5109   # of height — the frame's inner face
# The text is centred within LEFT_FRAC..RIGHT_FRAC, not within the box as a
# whole. Font size is pinned to the box's WIDTH, not its height. Height would
# be the natural choice, but it would tie the text to QUIZ_BOX_HEIGHT_STRETCH
# — making the panel taller would grow the letters with it, which is exactly
# what we don't want. Width is untouched by the stretch, so the text holds
# its size no matter how tall the box gets.
#
# The ceiling comes from descenders: measured on Fredoka, cap-height strings
# ink 0.72 em above the baseline to 0.01 below, but a "Paraguay" reaches
# 0.21 em below. Centred on the ink midpoint, that puts the descender
# 0.565 em under the centre, which is what has to clear the frame.
const QUIZ_TEXT_MAX_FONT_FRAC := 0.062    # of box width
const QUIZ_TEXT_MIN_FONT_FRAC := 0.030    # of box width — floor for very long questions
# Baseline offset from the text's visual centre, as a fraction of font size.
# Measured the same way as the digits: ink midpoint of cap-height strings
# sits 0.355 em above the baseline. Centring on the cap band rather than on
# the full ink box keeps strings with descenders from jumping upward.
const QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC := 0.355

const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_TEXT_OUTLINE := Color(0.05, 0.08, 0.12, 0.85)  # keeps light text legible over the space behind


# ============================================================
# Combo tier popup — an "×N" under the quiz row's right end, re-punched on
# every right answer (_space_correct, right where `combo` is incremented).
# This only ever reads `combo`. Four escalating tiers, 25 combo wide each,
# capped at Tier 4 for anything >= COMBO_TIER_CAP.
# ============================================================
# Fredoka (SIL OFL, see assets/fonts/Fredoka_LICENSE.txt) — a rounded
# geometric sans. Replaces Mulmaru, which is a Korean face whose Latin glyphs
# were only a secondary concern.
#
# That reasoning has since flipped once: the UI is translated now, so the
# game does render Hangul, which Fredoka has none of. It comes from a
# fallback face instead — the whole arrangement lives in scripts/AppFont.gd,
# and every screen takes its font from there.
#
# It is a variable font with a wght axis (300-700, default 300 — too light
# for a HUD, so both weights below are set explicitly). The axis has to be
# keyed by its integer OpenType tag, not the string "wght": a string key is
# silently ignored and you get the 300 default back.
const TEXT_FONT_WEIGHT := 600      # quiz text, combo popups, banners
const SCORE_FONT_WEIGHT := 700     # the score/best digits, which want more punch
const COMBO_TIER_SIZE := 25
const COMBO_TIER_CAP := 100
# Inset from the right edge, and down from the quiz row's bottom edge. The 42
# is where the combo has sat since 1.x: 16 below the 26px band the boost bar
# took under the row.
const COMBO_DISPLAY_MARGIN := Vector2(20.0, 42.0)

# Indexed by tier (0..3 = Tier 1..Tier 4).
const COMBO_TIER_DURATIONS := [0.3, 0.35, 0.45, 0.55]
const COMBO_TIER_FONT_SIZES := [28, 34, 40, 50]
const COMBO_TIER_RISE := [10.0, 14.0, 18.0, 22.0]
const COMBO_SHAKE_DURATION := 0.12    # Tier 3+ only — much smaller/shorter than the hit shake (FX_SHAKE_*)
const COMBO_SHAKE_PEAK_AMPLITUDE := 2.5  # px, per spec's "2~3px"
const COMBO_GLOW_DURATION := 0.6      # Tier 4 only — screen-edge glow, roughly matches that tier's popup lifetime
const COMBO_GLOW_COLOR := Color(1.0, 0.75, 0.25)  # warm gold
const COMBO_GLOW_BAND_PX := 36.0
const COMBO_GLOW_PEAK_ALPHA := 0.22

# Screen shake on a hit, a wrong gate and the boss going down — cubic decay
# so it settles quickly; a render-only offset on this Node2D's own position.
const FX_SHAKE_DURATION := 0.14
const FX_SHAKE_PEAK_AMPLITUDE := 4.5   # px

const SCORE_PER_COMBO := 10           # a right answer scores SCORE_PER_COMBO x combo

# _pop_scale's overshoot (the START pop).
const POP_PEAK_SCALE := 1.22

# A weapon step won by the streak, and each planet smashed in fever.
const FX_SOUND_CHIME_PATH := "res://assets/audio/gate_chime.wav"
# Background music: the menu track, each mode's track and the game over one,
# crossfaded by _play_bgm on the Music bus (_setup_audio_buses). There is no
# music at the moment — every name below is a slot, and a file dropped in
# under it plays with no code change.
const BGM_DIR := "res://assets/audio/"
# Music is named without an extension here and resolved at load time, .ogg
# first. OGG is the intended shipping format — a track runs 10-14 MB as WAV
# and roughly a tenth of that as OGG — but the fallback means an un-converted
# .wav still plays, and dropping the .ogg beside it switches over with no
# code change.
const BGM_EXTENSIONS := [".ogg", ".wav"]
# The splash and mode-picker screens share one track; a run switches to the
# chosen mode's.
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
# 부활 제안과 게임오버 화면의 곡. 판이 끝나면 음악을 통째로 끊었었는데, 두
# 팝업 모두 한참 들여다보는 화면이라 그 사이가 무음이었다.
#
# 둘이 같은 곡이고, 그래야 한다. 제안을 거절하면 부활 팝업이 곧바로 게임오버
# 팝업으로 바뀌는데 곡이 다르면 거기서 한 번 끊긴다 — _play_bgm 은 같은
# 경로면 아무 일도 안 하므로, 이름만 같으면 저절로 이어진다.
const BGM_GAMEOVER_NAME := "gameover_bgm"
# Countdown beat sounds — one played the instant the READY image appears,
# the other the instant it swaps to START (see _start_countdown and
# _update_countdown).
const COUNTDOWN_READY_SOUND_PATH := "res://assets/audio/countdown_ready.mp3"
const COUNTDOWN_START_SOUND_PATH := "res://assets/audio/countdown_start.mp3"
# Failure sound — every heart lost (_take_hit), and the revive offer and the
# game over. A softer per-hit cue is still to be chosen.
const FX_SOUND_GAMEOVER_PATH := "res://assets/audio/gameover.wav"

# Tapping the title screen to enter the mode picker. Every other sound here
# belongs to a run; this one is the first thing the game ever plays, so it
# doubles as the "audio is working" confirmation. Optional like the rest —
# a missing file just means the transition stays silent.
const FX_SOUND_SPLASH_START_PATH := "res://assets/audio/splash_start.wav"

# Fever's opening cue (_space_fever_started) — the 1.x boost's ignition, a
# 0.68 s one-shot, so it is never looped.
const FX_SOUND_BOOST_START_PATH := "res://assets/audio/boost_start.wav"
# 판이 도는 동안의 곡보다 낮게 깐다. 읽을 것이 있는 화면이고 게임오버 효과음이
# 그 위에 울리므로, 같은 크기면 둘이 서로를 밟는다. 0 이 기본 크기이고 음수가
# 작아지는 쪽이다(데시벨).
@export_group("Music")
@export_range(-30.0, 0.0, 0.5) var gameover_bgm_db: float = -9.0
@export_group("")  # closes "Music"
# 점화음의 크기. 짧은 트랜지언트라 RMS 가 낮아(피크는 -5.1 dBFS) 다른 소리
# 옆에서 묻히므로 올린다. +4 면 피크에 1 dB 를 남긴다 — +5 면 이 클립 혼자
# 0 dBFS 를 친다.
@export_group("Boost Audio")
@export_range(-12.0, 12.0, 0.5) var boost_start_volume_db: float = 4.0
@export_group("")  # closes "Boost Audio"


# SPLASH is the boot screen (title art + "Tap to START"); it hands off to
# MODE_SELECT on the first tap. LOGO 는 그보다도 앞, 부팅 직후의 제작사 화면이다.
# 체커들이 몇몇 상태를 숫자로 부르므로(0 = MODE_SELECT, 2 = PLAYING 등),
# 순서를 바꾸면 tools/ 의 그 숫자도 같이 고친다.
enum State { MODE_SELECT, COUNTDOWN, PLAYING, GAMEOVER, SPLASH, LOGO }

# ============================================================
# 로고 화면 — 부팅 직후, 스플래시보다 먼저. 검은 바탕에 로고만 띄우고
# 페이드 인/유지/페이드 아웃 뒤 스스로 스플래시로 넘어간다.
# 아무 데나 누르면 바로 페이드 아웃으로 건너뛴다. 음악은 아직 틀지 않는다 —
# 스플래시로 넘어갈 때 시작해야 로고가 조용히 뜬다.
# ============================================================
const LOGO_TEXTURE_PATH := "res://assets/ui_assets/title/logo.png"
const LOGO_BACKGROUND := Color(0.0, 0.0, 0.0, 1.0)
const LOGO_FADE_IN := 0.45
const LOGO_HOLD := 1.5
const LOGO_FADE_OUT := 0.45
const LOGO_WIDTH_FRAC := 0.78        # of view width
# 로고 한 장만 놓는다. 정중앙보다 살짝 위 — 화면 가운데에 정확히 두면 아래가
# 비어 보인다.
#
# 예전에는 로고 아래에 "BETA VERSION"과 제작자 두 줄이 함께 붙어 한 덩어리로
# 가운데 정렬됐다. 크레딧은 About 팝업에 이미 있고, 시작할 때마다 이름을
# 지나쳐야 할 이유가 없다.
const LOGO_BLOCK_CENTER_FRAC := 0.46  # of view height

# ============================================================
# Splash / title screen — the first thing shown on boot, before the mode
# picker; a tap anywhere moves on.
#
# Built 2026-11-27 after the Synty INTERFACE Sci-Fi Menus pack's own banner,
# turned for a portrait screen. It is made from the pack's pieces, baked by
# tools/build_ui_kit.gd into assets/synty_ui/ (gitignored), and the pack's
# banner itself is not used.
#   - The live space world, dimmed to a deep blue.
#   - A horizontal band of blue light across the title.
#   - "WARP" and "GATE" either side of a gold star on a wreath, in Zen Dots:
#     pale letters, a bright cyan rim and a soft cyan glow.
#   - The metal bar under them, then QUIZ RUN in gold to match the star.
# Without the kit the pieces are ArtSlot placeholders and the letters fall
# back to the game's own font.
# ============================================================
const TITLE_BAR_PATH := "res://assets/synty_ui/title_bar.png"
const TITLE_SUBTITLE := "QUIZ RUN"
const TITLE_MID_Y_FRAC := 0.31          # of view height — the band, star and words
const TITLE_STAR_HEIGHT := 150.0         # px at 480 wide (190 until 2026-11-27: the words needed the room)
const TITLE_WREATH_HEIGHT := 100.0
const TITLE_WORD_SIZE := 56              # px; shrinks to fit the side
const TITLE_SUBTITLE_SIZE := 30
const TITLE_BAR_Y := 54.0                # below the middle line
const TITLE_SUBTITLE_Y := 112.0          # below the middle line — clear of the star's lower tip
const TITLE_BAND_HEIGHT := 128.0
const TITLE_BAND_COLOR := Color(0.10, 0.42, 0.95, 0.62)
const TITLE_DIM := Color(0.01, 0.05, 0.16, 0.62)
# The subtitle: gold metal to match the star. The fill is graded from pale gold
# to deep orange (title_subtitle.gdshader), with an orange rim over a dark
# one, a warm glow, and gold rules with diamonds either side.
const TITLE_SUBTITLE_SHADER_PATH := "res://assets/shaders/title_subtitle.gdshader"
const TITLE_SUBTITLE_TOP := Color(1.0, 0.96, 0.66)
const TITLE_SUBTITLE_BOTTOM := Color(1.0, 0.56, 0.08)
const TITLE_SUBTITLE_RIM := Color(0.86, 0.38, 0.04)
const TITLE_SUBTITLE_OUTLINE := Color(0.16, 0.07, 0.01)
const TITLE_SUBTITLE_GLOW := Color(1.0, 0.62, 0.15, 0.10)
const TITLE_SUBTITLE_GLOW_RADII := [5.0, 10.0]
const TITLE_SUBTITLE_RULE_GAP := 14.0
const TITLE_SUBTITLE_RULE_LENGTH := 46.0
const SPLASH_PROMPT_TEXT := "Tap to START"
const SPLASH_PROMPT_BOTTOM_FRAC := 0.135   # of view height — distance from the bottom edge to the prompt's centre
const SPLASH_PROMPT_FONT_SCALE := 0.036    # of view height — Zen Dots runs wide
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
const SPLASH_PROMPT_GLOW_COLOR := Color(0.35, 0.86, 1.0)  # the title's cyan (2026-11-27; was gold)
const SPLASH_PROMPT_GLOW_RADII := [3.0, 7.0, 12.0]        # px, at scale 1.0
const SPLASH_PROMPT_GLOW_STEPS := 8                       # samples per ring
const SPLASH_PROMPT_GLOW_ALPHA := 0.14                    # per sample at full pulse — kept low on purpose
const SPLASH_PROMPT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SPLASH_PROMPT_OUTLINE := Color(0.03, 0.10, 0.25, 1.0)  # deep navy
# Tap feedback: the prompt swells and fades out, and the handover to the
# mode picker waits for it. Without the wait the title would simply cut
# away and the effect would never be seen. Scaling is done with a draw
# transform rather than by growing the font size, which would re-rasterise
# the glyphs every frame and shimmer.
const SPLASH_EXIT_DURATION := 0.32
const SPLASH_EXIT_SCALE := 1.55

var state: int = State.SPLASH   # _ready moves it to LOGO before the first frame

# Tap-to-pause (PLAYING only — see pause_button visibility in _process).
# Only gates the run's own updates in _process; the space world keeps
# drifting while paused, as it does on every other screen.
var paused: bool = false
# 한 판에 부활 제안은 한 번만. 이어간 뒤 또 죽으면 그때는 바로 게임오버다.
var revive_offered: bool = false

# "READY" -> "START" pop-in shown before every run, and again after a revive.
enum CountdownPhase { READY_TEXT, START_TEXT }
var countdown_phase: int = CountdownPhase.READY_TEXT
var countdown_timer: float = 0.0
const COUNTDOWN_READY_DURATION := 0.9
const COUNTDOWN_START_DURATION := 0.4

# "READY" / "START" countdown pop art (see the State.COUNTDOWN block in
# _draw_overlay_layers). Slots (ArtSlot) at SKY's 1.x paths until 2.0 art
# lands; the word's centre sits at the canvas centre, so drawing the canvas
# centred is what keeps it still.
const READY_TEXTURE_PATH := "res://assets/ui_assets/sky/Ready_v3.png"
const START_TEXTURE_PATH := "res://assets/ui_assets/sky/Start_v3.png"
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

# Play-screen HUD art (2026-11-27): Synty's INTERFACE Sci-Fi Menus pieces,
# baked by tools/build_ui_kit.gd into assets/synty_ui/ — gitignored, like the
# space kit, because the pack may not be redistributed. One set for every
# mode; without the kit each is an ArtSlot placeholder. The bars are drawn
# with their ends kept whole and the middle stretched (_draw_horizontal_slice;
# the caps are in baked pixels), the square frames as nine-patches.
const HUD_SCORE_BAR_PATH := "res://assets/synty_ui/score_bar.png"
const HUD_QUIZ_BOX_PATH := "res://assets/synty_ui/quiz_box.png"
const HUD_PAUSE_PATH := "res://assets/synty_ui/pause.png"
const HUD_SIDE_SLOT_PATH := "res://assets/synty_ui/side_slot.png"
const HUD_SCORE_BAR_CAP := 60.0
const HUD_QUIZ_BOX_CAP := 95.0
const HUD_SIDE_SLOT_MARGIN := 34.0
## Text on the HUD frames: their insides are dark.
const HUD_TEXT_COLOR := Color(0.93, 0.96, 1.0)
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
const SAVE_PATH := "user://savegame.cfg"
const SAVE_SECTION := "progress"
# 모드마다 기록을 따로 둔다. 키는 "best_score_<모드번호>".
const SAVE_KEY_BEST_PREFIX := "best_score_"
# 모드 구분 없이 하나만 쓰던 시절의 키. 불러올 때 한 번 옮겨 오고 그 뒤로는
# 쓰지 않는다.
const SAVE_KEY_BEST_LEGACY := "best_score"
# 순위표에 올릴 기록. 개인 최고 기록과 따로 둔다 — 아래 leaderboard_score 참고.
const SAVE_KEY_LEADERBOARD_PREFIX := "leaderboard_best_"
# 튜토리얼을 이미 봤는가. 설치 단위다 — 실행 단위로 두면 앱을 껐다 켤 때마다
# 다시 돈다.
const SAVE_KEY_TUTORIAL := "tutorial_seen"

# ============================================================
# 전면광고 노출 판단.
#
# 여기에는 광고를 띄우는 코드가 없다 — 프로젝트에 광고 SDK 자체가 없다(git log
# 의 감사 참고). 판단만 하고, 플러그인이 붙으면 _ad_try_interstitial 안쪽만
# 실제 호출로 바꾸면 된다. 그때 넘길 단위 ID 는 AdIds 가 정한다 — 실제 단위가
# 테스트 빌드로 새어 나가지 못하게 막는 잠금장치가 거기 있다.
#
# 규칙:
#   - 판을 떠날 때마다 하나씩 센다. "떠난다"는 게임오버 후 PLAY AGAIN /
#     HOME 이든 일시정지의 RESTART / HOME 이든 같다 — 사용자에게는 전부 "한 판
#     끝"이고, 한 경로만 빼두면 그게 다음 구멍이 된다.
#   - 리워드 광고를 본 판은 세지 않는다. 안 그러면 부활 광고 직후 전면광고가
#     붙어 30초 안에 광고 둘을 보게 된다.
#   - 설치 후 처음 몇 판은 면제한다. 신규 사용자가 게임을 파악하기 전에 광고를
#     보지 않게 하려는 것으로, 앱 오프닝 광고를 안 쓰는 것과 같은 이유다.
#
# 카운터는 저장된다. 세션에만 두면 4판 하고 앱을 껐다 켜는 것으로 광고를 계속
# 피할 수 있고, 그보다 흔하게는 안드로이드가 메모리 압박으로 앱을 죽일 때마다
# 사용자가 아무 짓도 안 했는데 카운터가 날아간다.
#
# 면제도 "실행마다"가 아니라 "설치 후 한 번"이다. 실행마다 주면 1판씩 하고 끄는
# 것으로 영원히 광고를 안 보게 되어, 카운터를 저장한 의미가 없어진다.
#
# Whole feature = these consts + games_played_total/restarts_since_interstitial/
# run_active + the _ad_* functions + the [ads] save section.
@export_range(1, 20, 1) var interstitial_every_restarts: int = 5
# 3 = 잠금 해제된 모드 수(FLAG/MATH/STROOP). 모드당 한 판씩 겪어 보라는 몫이다.
@export_range(0, 20, 1) var interstitial_free_games: int = 3

const SAVE_SECTION_ADS := "ads"
const SAVE_KEY_GAMES_PLAYED := "games_played"
const SAVE_KEY_RESTARTS_SINCE_AD := "restarts_since_ad"
# 광고 제거를 샀는가. 판정은 Google Play 가 하지만(Store), 켤 때마다 답을
# 기다리면 산 사람도 첫 몇 초는 배너를 보고, 오프라인이면 계속 본다. 마지막
# 답을 여기 적어 두고 켜자마자 따른다.
const SAVE_KEY_ADS_REMOVED := "removed"

# 스타더스트(2.0 의 재화). 게이트를 맞게 지날 때, 피버에서 행성을 부술 때,
# 보스를 잡을 때 번다(SpaceRun.STARDUST_*). 판 안에서는 run_stardust 에 모아
# 두었다가 판을 떠날 때(_bank_stardust) 합계에 더해 저장한다 — 게이트마다
# 쓰면 디스크를 판당 수십 번 건드린다.
const SAVE_SECTION_META := "meta"
const SAVE_KEY_STARDUST := "stardust"

const SAVE_SECTION_AUDIO := "audio"
# 언어. 저장이 없으면 기기 언어를 따른다 — 처음 켠 사람이 설정을 찾을 필요가
# 없어야 한다. 한 번 고르고 나면 그 선택이 기기 언어보다 앞선다.
const SAVE_SECTION_LOCALE := "locale"
const SAVE_KEY_LANGUAGE := "language"
const LOCALE_EN := "en"
const LOCALE_KO := "ko"
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
# The score box: the SCORE label and the live score in the left half, the
# BEST mark and the stored best in the right. All fractions are of the box's
# *display* size, so they hold at whatever the row scale works out to.
#
# 빈 패널 위에 직접 그린다. 왼쪽 칸은 "SCORE" 글자 + 점수, 오른쪽 칸은 왕관 +
# "BEST" + 최고 점수다.
const SCORE_LABEL_TEXT := "SCORE"
const SCORE_LABEL_FONT_FRAC := 0.485     # 박스 높이 대비
const SCORE_LABEL_LEFT_FRAC := 0.065      # 박스 너비 대비 — UI 킷 점수판의 왼쪽 끝 장식을 비켜서
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
# The BEST mark: the UI kit's trophy, tinted gold (tools/build_ui_kit.gd).
const BEST_CROWN_PATH := "res://assets/synty_ui/best_icon.png"
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
const BEST_NUMBER_RIGHT_INSET_FRAC := 0.075    # 박스 너비 대비 — UI 킷 점수판(2026-11-27)의 오른쪽 끝 장식을 비켜서
# 버튼 사이를 꽉 채우지 않고 살짝 줄여 그린다 — 버튼과의 간격이 그만큼 넓어진다.
const SCORE_BOX_WIDTH_TRIM := 0.96
# 패널 그림을 깔지 않고 글자만 배경 위에 얹는다. 자리와 크기는 그대로
# _score_box_rect 에서 나오므로, 다시 켜면 예전 모습으로 돌아온다.
# 2026-11-26: 다시 켰다 — 2.0 아트가 올 때까지 HUD 를 임시 박스로 채우는
# 동안, 점수판이 어디까지인지 보여야 배치를 정할 수 있다.
const SCORE_BOX_PANEL_VISIBLE := true
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
# font size — see _digit_positions. Measured by rendering
# "0123456789" at a known baseline and reading the ink box back: Fredoka's
# figures run 0.700 em above the baseline to 0.020 em below at this weight,
# putting their visual middle 0.34 em up. (Mulmaru's sat at 0.38, which is
# why this changed with the font.)
const DIGIT_BASELINE_FROM_CENTER_FRAC := 0.34
# 그라데이션을 숫자 잉크 높이에 딱 맞추려고 쓰는, 같은 측정에서 나온 값.
const DIGIT_INK_ABOVE_FRAC := 0.700
const DIGIT_INK_BELOW_FRAC := 0.020

# Pause button press feedback — quick squash-in on press, springy release
# back to full size. Needs pivot_offset centered on the button (set in
# _layout_hud_buttons) so the scale anchors from the icon's center, not its
# top-left.
const BUTTON_PRESS_SCALE := 0.85
const BUTTON_PRESS_ANIM_DURATION := 0.08


var score: int = 0
var combo: int = 0
var max_combo: int = 0   # highest combo reached this run — see _space_correct
# 광고를 보고 이어서 뛴 판인가. 부활 팝업이 "이어가면 이 판은 순위표에
# 올라가지 않는다"고 약속하므로, 그 약속을 지키려면 끝까지 들고 가야 한다.
# (개인 최고 기록은 "always saved"라고 했으니 부활 여부와 무관하게 쓴다.)
var run_revived: bool = false
# 판이 실제로 시작됐는가. _reset_game 은 첫 플레이에서도 불리므로, 이것 없이는
# "떠난 판"과 "아직 없던 판"을 구분할 수 없다.
var run_active: bool = false
# 설치 후 누적 판 수(면제 판정용)와 마지막 전면광고 이후 떠난 판 수.
var games_played_total: int = 0
var restarts_since_interstitial: int = 0
# 이 판에서 "첫 실수 전까지" 도달한 점수. 순위표에 올라가는 건 이 값이다.
#
# 광고를 보고 이어 뛰면 개인 최고 기록은 끝까지 간 점수로 갱신되지만,
# 순위표는 여기서 멈춘다. 광고로 순위를 살 수는 없게 하면서, 광고를 보기
# 전에 이미 정직하게 벌어 둔 점수까지 빼앗지는 않는 선이다.
#
# 부활을 거절하면 이 값이 곧 최종 점수라 아무 차이가 없다.
var leaderboard_score: int = 0
# 이 판에서 맞게 지난 게이트 수. 분석의 post_score 가 싣고, 부활해도 이어진다.
var gates_passed: int = 0

var flash_color := Color(0, 0, 0, 0)
var flash_time := 0.0
const FLASH_DURATION := 0.25


var current_mode: int = Mode.SKY  # picked on the mode select — see _apply_mode

var happy_face_texture: Texture2D
var sad_face_texture: Texture2D
var ready_texture: Texture2D
var start_texture: Texture2D
# 모드마다 순위표 하나. Play Console 이 준 ID 이고, 어차피 앱 안에 그대로 실려
# 나가는 공개 값이다(비밀이 아니다). 인덱스가 곧 Mode 값이다.
const MODE_LEADERBOARD_ID := [
	"CgkIxNW7848QEAIQAQ",  # SKY
	"CgkIxNW7848QEAIQAg",  # JUNGLE
	"CgkIxNW7848QEAIQAw",  # OCEAN
	"CgkIxNW7848QEAIQBA",  # DREAM (MIX)
]
# 로그인 상태. PlayGames(scripts/PlayGames.gd)가 정하고 _on_play_games_changed
# 가 여기로 옮겨 적는다 — 게임오버·부활·설정 팝업이 이 셋을 읽는다.
var player_avatar: Texture2D = null
var player_display_name: String = ""
var player_logged_in: bool = false
var play_games: PlayGames
# 공유. 카드는 user:// 에 덮어쓴다 — 한 번에 한 장만 나가므로 쌓아 둘 까닭이
# 없고, 안드로이드에서는 앱 내부 저장소라 FileProvider 가 넘길 수 있는 곳이다
# (ShareSheet 참고).
const SHARE_IMAGE_PATH := "user://share/quizrun_score.png"
var share_card: ShareCard
var share_busy: bool = false
# 게임오버 때 정해지는 "이번 판이 신기록인가". 판이 끝난 뒤에는 best_scores 가
# 이미 이번 점수로 바뀌어 있어 다시 계산할 수 없다(_finish_run).
var last_run_new_record: bool = false
# 광고. Ads 가 AdMob 을 감싼다 — PC 에서는 available 이 false 다.
var ads: Ads
# 분석. Firebase Analytics 를 감싼다 — PC 에서는 available 이 false 고 아무것도 안 보낸다.
var analytics: Analytics
# 전면광고가 떠 있는 동안 카운트다운을 붙잡는다. 광고 뒤에서 READY -> START 가
# 흘러가 버리면, 광고를 닫았을 때 판이 이미 시작돼 있다.
var ad_hold_countdown: bool = false
# 광고 제거. Store 가 Google Play 결제를 감싼다 — PC 에서는 available 이 false 다.
var store: Store
var ads_removed: bool = false
var stardust_total: int = 0   # 저장된 합계
var run_stardust: int = 0     # 이번 판에서 번 것, 아직 합계에 안 더한 것
# 에디터에서 로그인한 화면을 보는 길. PC 에서는 진짜 로그인이 안 되므로 이것
# 말고는 볼 방법이 없다. 켜면 "Test Player" 로 로그인된 채로 시작한다.
#
# 플러그인이 있는 기기에서는 아무 일도 안 한다 — 진짜 결과가 있는 곳에서 가짜를
# 덮어쓸 이유가 없다. 그래도 debug_replay_tutorial 과 같은 @export 함정은
# 그대로라(인스펙터에서 켜면 Main.tscn 에 저장된다), check_play_games.gd 가
# 켜진 채로 두면 실패한다.
@export var debug_fake_sign_in: bool = false
# 모드별 최고 점수. 인덱스가 곧 Mode 값이다. _ready에서 불러오고, 기록을
# 갈아치울 때만 저장한다.
var best_scores := PackedInt32Array()
# 모드별 순위표 기록. 개인 최고 기록과 나뉘어 있다 — leaderboard_score 참고.
var leaderboard_bests := PackedInt32Array()
# 튜토리얼을 봤는지. SAVE_KEY_TUTORIAL 참고.
var tutorial_seen: bool = false
# 튜토리얼이 도는 동안. 카운트다운 시계를 세우고 READY/START 글자를 접어 둔다.
var tutorial_active: bool = false
## 튜토리얼을 다시 보기 위한 스위치. 켜면 이미 본 뒤에도 게임에 들어갈 때마다
## 다시 돈다.
##
## 켜져 있는 동안은 "봤다"를 저장하지 않는다 — 확인하려고 켠 것이 이 기기의
## 진짜 상태를 바꿔서는 안 되고, 껐을 때 원래대로 돌아와야 한다.
##
## @export 의 함정이 있다: 인스펙터에서 켜면
## Main.tscn 에 저장되고, 그대로 커밋되면 모두가 매 판 튜토리얼을 본다 —
## 게임은 멀쩡히 돌아가므로 눈치채기 어렵다. tools/check_tutorial.gd 가 켜진
## 채로 커밋된 것을 잡는다.
@export var debug_replay_tutorial: bool = false
var score_box_texture: Texture2D
var score_crown_texture: Texture2D
var score_font: Font
var quiz_box_texture: Texture2D
var logo_texture: Texture2D
var logo_elapsed: float = 0.0
# 무거운 부팅이 아직 남아 있는가. 로고가 다 밝아진 뒤 한 번 돈다.
var boot_pending := false
var splash_elapsed: float = 0.0   # free-running clock for the prompt pulse
var splash_exit_elapsed: float = -1.0  # -1 = not leaving yet; see SPLASH_EXIT_DURATION
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
var combo_display_punch_elapsed: float = 0.0  # time since the last right answer — drives the punch/bounce, then just sits at rest (never expires while combo > 0)
var combo_display_time: float = 0.0           # free-running clock while combo > 0, drives the Tier 3/4 color animation
var fx_shake_elapsed: float = -1.0   # -1 = inactive
var combo_shake_elapsed: float = -1.0  # -1 = inactive; separate tiny shake for combo Tier 3+, independent of fx_shake_elapsed
var combo_glow_elapsed: float = -1.0   # -1 = inactive; screen-edge glow for combo Tier 4
var combo_font: Font
var fx_sound_chime: AudioStreamPlayer
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
var fx_sound_boost_start: AudioStreamPlayer

@onready var mode_select_panel: Control = $UI/ModeSelectPanel
@onready var gameover_popup: Control = $UI/GameOverPopupPanel
@onready var settings_popup: Control = $UI/SettingsPopupPanel
@onready var about_popup: Control = $UI/AboutPopupPanel
@onready var tutorial_overlay: Control = $UI/TutorialOverlay
@onready var pause_button: Button = $UI/PauseButton
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
	# Filter for everything Main draws: the space world's frame, the title, the
	# countdown art and the effects. draw_texture_rect has no per-call filter
	# option, so it has to be set on the CanvasItem itself — which is also why
	# the HUD needs its own node to differ. See SMOOTH_WORLD_FILTER to revert this.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if SMOOTH_WORLD_FILTER else CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_fonts()
	logo_texture = ArtSlot.texture(LOGO_TEXTURE_PATH)
	if logo_texture != null:
		boot_pending = true
		_set_state(State.LOGO)
		return
	_boot_load()


# 글꼴만 먼저. 로고 화면의 크레딧이 이걸 쓴다.
func _setup_fonts() -> void:
	# 한글 fallback 까지 붙은 한 벌을 받는다 — scripts/AppFont.gd 참고.
	var base_font: Font = AppFont.base()
	# Real weight axis rather than the faux-bold this used to need: Mulmaru
	# shipped a single weight, Fredoka carries 300-700.
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	combo_font = _weighted_font(base_font, wght, TEXT_FONT_WEIGHT)
	score_font = _weighted_font(base_font, wght, SCORE_FONT_WEIGHT)


# 부팅의 무거운 쪽. _ready 에서 곧바로, 또는 로고가 뜬 뒤에 불린다.
func _boot_load() -> void:
	# 무엇보다 먼저. 판들은 지어질 때 tr() 을 한 번 지나고 그 결과를 라벨과
	# 맞춰 둔 글자 크기에 굳혀 버린다 — 다 지은 뒤에 로케일을 바꾸면 화면은
	# 기기 언어 그대로 남는다.
	_load_language()
	# 팝업 셋과 모드 선택 화면은 씬의 자식이라 원래 Main 보다 먼저 _ready 가
	# 돌았다 — 넷이 합쳐 1.6초라, 로고가 뜨기도 전에 그만큼을 잡아먹었다.
	# 이제 조립을 여기서 시킨다.
	for panel in [pause_panel, revive_panel, gameover_popup, settings_popup, about_popup,
			tutorial_overlay, mode_select_panel]:
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
	_load_ad_state()
	# The four HUD pieces are all per-mode now and get loaded in _apply_mode;
	# only the parts that never change per mode are set up here.
	pause_button.text = ""
	pause_button.expand_icon = true
	# flat=true 라도 Button 은 기본 테마 스타일박스의 content margin(사방 4px)을
	# 그대로 써서 아이콘을 그 안쪽에 맞춘다. 57.5px 버튼이면 그림은 49.5px 밖에
	# 안 되고, 그래서 옆의 스코어박스보다 눈에 띄게 작아 보였다. 여백 0 인
	# 스타일박스를 씌워 아이콘이 버튼 사각형을 그대로 채우게 한다.
	for b: Button in [pause_button]:
		var empty := StyleBoxEmpty.new()
		for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(slot, empty)
	_layout_hud_buttons()
	var view_size := get_viewport_rect().size
	_apply_mode(current_mode)  # loads a valid default (SKY) so nothing is empty before mode-select runs _apply_mode again
	# 2.0 우주 판. 판(점수·하트·콤보·팝업)은 Main 이, 3D 세계와 닿음 판정은
	# SpaceRun 이 맡는다 — scripts/SpaceRun.gd 머리말.
	space = SpaceRun.new()
	space.name = "SpaceRun"
	add_child(space)
	space.setup(self, view_size)
	# 효과음과 음악을 따로 조절하려면 각자 버스를 타야 한다.
	_setup_audio_buses()
	fx_sound_chime = AudioStreamPlayer.new()
	add_child(fx_sound_chime)
	fx_sound_chime.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_CHIME_PATH):
		fx_sound_chime.stream = load(FX_SOUND_CHIME_PATH)
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
	fx_sound_boost_start = AudioStreamPlayer.new()
	add_child(fx_sound_boost_start)
	fx_sound_boost_start.bus = BUS_SFX
	if ResourceLoader.exists(FX_SOUND_BOOST_START_PATH):
		fx_sound_boost_start.stream = load(FX_SOUND_BOOST_START_PATH)
		fx_sound_boost_start.volume_db = boost_start_volume_db
	# The mode picker builds its own UI (see ModeSelectScreen.gd) and reports
	# back which mode START chose.
	mode_select_panel.start_pressed.connect(_on_mode_selected)
	mode_select_panel.settings_pressed.connect(_open_settings)
	mode_select_panel.login_pressed.connect(_on_mode_select_login_pressed)
	mode_select_panel.leaderboard_pressed.connect(_on_mode_select_leaderboard_pressed)
	mode_select_panel.remove_ads_pressed.connect(_on_remove_ads_pressed)
	settings_popup.close_pressed.connect(func(): settings_popup.visible = false)
	settings_popup.sfx_volume_changed.connect(set_sfx_volume)
	settings_popup.music_volume_changed.connect(set_music_volume)
	settings_popup.language_changed.connect(set_language_korean)
	settings_popup.login_pressed.connect(_on_login_pressed)
	settings_popup.privacy_pressed.connect(_on_privacy_pressed)
	settings_popup.ad_privacy_pressed.connect(_on_ad_privacy_pressed)
	settings_popup.terms_pressed.connect(_on_terms_pressed)
	settings_popup.contact_pressed.connect(_on_contact_pressed)
	settings_popup.about_pressed.connect(_on_about_pressed)
	about_popup.close_pressed.connect(_on_about_closed)
	tutorial_overlay.finished.connect(_on_tutorial_finished)
	settings_popup.remove_ads_pressed.connect(_on_remove_ads_pressed)
	gameover_popup.play_again_pressed.connect(_on_gameover_play_again_pressed)
	gameover_popup.login_pressed.connect(_on_gameover_login_pressed)
	gameover_popup.leaderboard_pressed.connect(_on_gameover_leaderboard_pressed)
	gameover_popup.share_pressed.connect(_on_gameover_share_pressed)
	gameover_popup.home_pressed.connect(_on_pause_home_pressed)
	# 로그인. 팝업이 다 지어지고 신호가 이어진 뒤라야 결과를 받아 줄 곳이 있다.
	play_games = PlayGames.new()
	play_games.name = "PlayGames"
	add_child(play_games)
	play_games.state_changed.connect(_on_play_games_changed)
	play_games.start()
	if debug_fake_sign_in and OS.is_debug_build() and not play_games.available:
		play_games.fake_sign_in("Test Player")
	# 게임오버의 SHARE 가 보낼 점수 카드를 그리는 곳. 트리에 있어야 SubViewport
	# 가 그려진다.
	share_card = ShareCard.new()
	share_card.name = "ShareCard"
	add_child(share_card)
	# 광고. PC 에서는 아무것도 띄우지 않고 available 만 false 로 남는다.
	# 분석은 광고보다 먼저 세운다 — 광고 쪽 동의 결과가 오면 바로 받아야 한다.
	analytics = Analytics.new()
	analytics.name = "Analytics"
	add_child(analytics)
	analytics.start()
	ads = Ads.new()
	ads.name = "Ads"
	add_child(ads)
	ads.fullscreen_changed.connect(_on_ads_fullscreen)
	ads.consent_changed.connect(_on_ads_consent_changed)
	ads.start()
	# 광고 제거 결제. 저장해 둔 답을 먼저 화면에 걸고, Google Play 의 답이 오면
	# 그걸 따른다(_on_store_ownership).
	store = Store.new()
	store.name = "Store"
	add_child(store)
	store.ownership_changed.connect(_on_store_ownership)
	_apply_ads_removed()
	store.start()
	pause_button.pressed.connect(_on_pause_pressed)
	# 팝업이 자기 버튼을 들고 있고, 눌린 결과만 신호로 알려 준다.
	pause_panel.resume_pressed.connect(_on_resume_pressed)
	pause_panel.restart_pressed.connect(_on_pause_restart_pressed)
	pause_panel.home_pressed.connect(_on_pause_home_pressed)
	pause_panel.sfx_volume_changed.connect(set_sfx_volume)
	pause_panel.music_volume_changed.connect(set_music_volume)
	revive_panel.watch_ad_pressed.connect(_on_revive_watch_ad)
	revive_panel.decline_pressed.connect(_on_revive_decline)
	# pivot_offset is set in _layout_hud_buttons instead — it resizes the
	# buttons deferred, so reading .size here would still give the scene's
	# pre-layout value and the press animation would scale off-center.
	pause_button.button_down.connect(_animate_button_press.bind(pause_button))
	pause_button.button_up.connect(_animate_button_release.bind(pause_button))
	_load_title_art()
	_reset_game()
	# 로고를 이미 띄우고 있으면 그대로 두고, 로고가 끝날 때 스플래시로 간다.
	# 다만 방금 만든 노드들의 보이기 상태는 지금 화면 기준으로 다시 잡아 준다.
	if state == State.LOGO:
		_apply_screen_visibility()
	else:
		_set_state(State.SPLASH)


func _weighted_font(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


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
	var img: Image = ArtSlot.image(path)
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


func _unhandled_input(event: InputEvent) -> void:
	# 우주 게임에서는 탭이 아니라 끌기로 조종한다. 카운트다운 동안에도 받아
	# 시작 전에 자리를 잡을 수 있게 한다.
	if not paused and (state == State.PLAYING or state == State.COUNTDOWN):
		space.handle_input(event)
		return
	if state != State.SPLASH:
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
		# Any tap leaves the title screen.
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
			_set_state(State.SPLASH)
		queue_redraw()
		return
	if state == State.SPLASH:
		splash_elapsed += delta
		# The title sits over the space world, so keep it flowing (no run).
		if space != null:
			space.tick(delta, false, false)
		if title_sub_layer != null:
			title_sub_layer.queue_redraw()
		if splash_exit_elapsed >= 0.0:
			splash_exit_elapsed += delta
			if splash_exit_elapsed >= SPLASH_EXIT_DURATION:
				_set_state(State.MODE_SELECT)
		queue_redraw()
		return
	pause_button.visible = state == State.PLAYING or state == State.COUNTDOWN
	# 우주 판(SpaceRun) — 세계는 모든 화면에서 흐르고, 판의 규칙은 PLAYING 에서만.
	space.tick(delta, state == State.PLAYING and not paused,
		(state == State.PLAYING or state == State.COUNTDOWN) and not paused)
	if space_banner_elapsed >= 0.0 and not paused:
		space_banner_elapsed += delta
		if space_banner_elapsed >= SPACE_BANNER_TIME:
			space_banner_elapsed = -1.0
	if not paused:
		if state == State.PLAYING:
			_update_hearts(delta)
		elif state == State.COUNTDOWN and not tutorial_active:
			# 튜토리얼이 도는 동안은 시계를 세워 둔다 — 안 그러면 설명을 읽는
			# 중에 카운트다운이 끝나고 판이 시작된다.
			_update_countdown(delta)
		if flash_time > 0.0:
			flash_time = max(0.0, flash_time - delta)
		_update_fx(delta)
	queue_redraw()
	if hud_canvas != null:
		hud_canvas.queue_redraw()
	if score_fill_canvas != null:
		score_fill_canvas.queue_redraw()
	if best_fill_canvas != null:
		best_fill_canvas.queue_redraw()


func _update_countdown(delta: float) -> void:
	# 전면광고가 떠 있는 동안에는 시계를 세우지 않는다(ad_hold_countdown).
	if ad_hold_countdown:
		return
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


func _combo_tier(combo_value: int) -> int:
	# 0-indexed: 1-25 -> Tier 1 (0), 26-50 -> Tier 2 (1), 51-75 -> Tier 3 (2),
	# 76+ (capped at COMBO_TIER_CAP) -> Tier 4 (3), and it just stays there.
	var capped: int = mini(combo_value, COMBO_TIER_CAP)
	var tier: int = (maxi(capped, 1) - 1) / COMBO_TIER_SIZE
	return clampi(tier, 0, 3)


func _combo_display_pos(view_size: Vector2) -> Vector2:
	return Vector2(view_size.x - COMBO_DISPLAY_MARGIN.x, _quiz_box_rect(view_size).end.y + COMBO_DISPLAY_MARGIN.y)


func _spawn_combo_popup() -> void:
	# The "×N" display itself is persistent (drawn every frame combo > 0 in
	# _draw_combo_popups) — this only re-triggers the punch/bounce and the
	# one-shot effects (Tier 3 shake, Tier 4 glow) on top
	# of it, it doesn't spawn or replace anything that needs to expire.
	var tier := _combo_tier(combo)
	combo_display_punch_elapsed = 0.0
	if tier >= 2:
		combo_shake_elapsed = 0.0
	if tier >= 3:
		combo_glow_elapsed = 0.0


func _update_fx(delta: float) -> void:
	if combo > 0:
		combo_display_punch_elapsed += delta
		combo_display_time += delta
	else:
		combo_display_time = 0.0

	# Two independent shake sources (a hit, a wrong gate or the boss going
	# down; combo Tier 3+) summed into one offset — each decays and clears on
	# its own schedule.
	var shake_offset := Vector2.ZERO
	if fx_shake_elapsed >= 0.0:
		fx_shake_elapsed += delta
		if fx_shake_elapsed >= FX_SHAKE_DURATION:
			fx_shake_elapsed = -1.0
		else:
			# Cubic decay: drops under 1px well before FX_SHAKE_DURATION ends.
			var t: float = fx_shake_elapsed / FX_SHAKE_DURATION
			var amp: float = FX_SHAKE_PEAK_AMPLITUDE * pow(1.0 - t, 3)
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
	# count changes, always staying under the quiz row's right end
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
	tutorial_seen = bool(cfg.get_value(SAVE_SECTION, SAVE_KEY_TUTORIAL, false))
	stardust_total = int(cfg.get_value(SAVE_SECTION_META, SAVE_KEY_STARDUST, 0))
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


func _save_tutorial_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION, SAVE_KEY_TUTORIAL, tutorial_seen)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("could not write %s (error %d) — the tutorial will run again" % [SAVE_PATH, err])


func _save_best_score(mode: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION, SAVE_KEY_BEST_PREFIX + str(mode), best_scores[mode])
	cfg.set_value(SAVE_SECTION, SAVE_KEY_LEADERBOARD_PREFIX + str(mode), leaderboard_bests[mode])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("could not write %s (error %d) — best score will not persist" % [SAVE_PATH, err])


# ============================================================
# 하트 (2.0).
#
# 1.x 는 한 번 틀리면 끝이었다. 첫 28일 데이터에서 1인당 판이 8개 남짓, 하루 뒤
# 다시 오는 사람이 12% 정도였고, 주변 테스터는 한결같이 "어렵다"고 했다. 그래서
# 판에 하트를 MAX_HEARTS 개 준다. 우주 판에서 하트는 조작의 실수 — 소행성과 보스
# 탄, 게이트 사이의 소행성 — 에만 쓰고, 오답 게이트는 연속 기록과 콤보만
# 끊는다(_space_wrong). 마지막
# 하트를 잃는 순간이 예전의 죽음이고, 그 뒤 흐름(부활 제안 → 게임오버)은 그대로다.
#
# 맞은 순간 콤보는 끊긴다 — 점수가 콤보에 비례하므로 하트가 남아도 실수의 값은
# 치른다.
#
# 맞은 뒤 HURT_INVULN_DURATION 동안은 우주선이 깜빡이고 소행성과 보스 탄이 하트를
# 가져가지 않는다(_space_invulnerable) — 한 번에 둘을 잃지 않게.
const MAX_HEARTS := 3
const HURT_INVULN_DURATION := 1.2
# 무적 동안 우주선이 깜빡이는 주기(초)와 꺼졌을 때의 알파. 완전히 지우면 어디
# 있는지 잃어버린다.
const HURT_BLINK_PERIOD := 0.12
const HURT_BLINK_ALPHA := 0.25
const HURT_FLASH_COLOR := Color(0.85, 0.12, 0.12, 0.35)
# HUD 체력 — 문제 박스 왼쪽 칸(_health_rect)의 세로 3칸 게이지(2026-11-26).
# 하트 아이콘이 게이지 아래 왼쪽에 있던 것을 문제 박스 옆으로 올리면서 칸으로
# 바꿨다. 칸으로 나눈 것은 "몇 번 남았나"가 하트처럼 한눈에 세어지게 하려는 것 —
# 이어진 막대면 그게 흐려진다. 칸 테두리 안쪽 여백과 칸 사이 간격(px).

const HEALTH_INSET := Vector2(14.0, 12.0)   # inside the side_slot frame's bevel
const HEALTH_CELL_GAP := 4.0
const HEART_FILL := Color(0.93, 0.16, 0.24, 1.0)
const HEART_EMPTY := Color(0.10, 0.12, 0.20, 0.45)
const HEART_EDGE := Color(1.0, 1.0, 1.0, 0.95)
# 잃은 칸이 하얗게 번쩍이며 사라지는 시간과 최대 배율.
const HEART_LOSS_POP_DURATION := 0.45
const HEART_LOSS_POP_SCALE := 1.9

var hearts: int = MAX_HEARTS
# 2.0 우주 게임(SpaceRun.gd). _boot_load 가 만든다 — 그 전에는 null.
var space: SpaceRun = null
# 피버 중 행성 하나를 부술 때의 점수 배수 — 콤보 점수(SCORE_PER_COMBO x combo)의
# 절반. 8초에 스무 개 남짓 부수므로, 문제를 맞힌 열 개보다 조금 더 벌린다.
const FEVER_SMASH_SHARE := 0.5
const FEVER_FLASH_COLOR := Color(1.0, 0.65, 0.2, 0.35)


## SpaceRun 이 판이 살아 있는지 묻는다(판정 도중 게임오버로 넘어갔는지).
func space_run_live() -> bool:
	return state == State.PLAYING


## 정답 게이트를 지났을 때. 1.x 의 게이트 통과와 같은 득점이다 — 부스트 배수만
## 없다.
func _space_correct() -> void:
	gates_passed += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	score += SCORE_PER_COMBO * combo
	flash_color = Color(0.3, 0.8, 0.4, 0.25)
	flash_time = FLASH_DURATION
	_spawn_combo_popup()


## 틀린 게이트를 지났거나 게이트 없는 구역에 있었을 때. 하트도 무기도 그대로다
## — 값은 끊긴 연속 기록(속도와 스타더스트 보너스가 처음으로)과 콤보로 치른다.
## 하트는 조작의 실수(소행성·보스 탄)에만 쓴다.
func _space_wrong() -> void:
	combo = 0
	flash_color = HURT_FLASH_COLOR
	flash_time = FLASH_DURATION
	fx_shake_elapsed = 0.0


## 소행성이나 보스 탄에 맞았을 때.
func _space_hurt() -> void:
	_take_hit()


## 맞은 뒤 깜빡이는 동안은 소행성과 보스 탄이 하트를 가져가지 않는다.
func _space_invulnerable() -> bool:
	return hurt_elapsed >= 0.0


func _space_points(points: int) -> void:
	score += points


## 연속 통과로 무기가 올랐을 때(SpaceRun._power_up). 룰렛이 있을 때는 그 칸이
## 결과를 보여 줘서 문구를 안 띄웠지만, 룰렛이 없어진 지금은 이것이 유일한
## 알림이다.
func _space_powered_up(label: String) -> void:
	_spawn_space_banner(label, Color(0.55, 0.92, 1.0))
	if fx_sound_chime != null and fx_sound_chime.stream != null:
		fx_sound_chime.play()


func _space_boss_down(points: int) -> void:
	score += points
	flash_color = Color(1.0, 0.9, 0.6, 0.5)
	flash_time = FLASH_DURATION
	fx_shake_elapsed = 0.0
	_spawn_space_banner("+%d" % points, Color(1.0, 0.85, 0.3))


# 보스 처치 점수와 무기 강화를 화면 가운데에 잠깐 띄운다.
const SPACE_BANNER_TIME := 1.1
var space_banner_text := ""
var space_banner_color := Color.WHITE
var space_banner_elapsed := -1.0


func _spawn_space_banner(text: String, color: Color) -> void:
	space_banner_text = text
	space_banner_color = color
	space_banner_elapsed = 0.0


func _draw_space_banner(view_size: Vector2) -> void:
	if space_banner_elapsed < 0.0:
		return
	var t: float = space_banner_elapsed / SPACE_BANNER_TIME
	var font: Font = combo_font if combo_font != null else ThemeDB.fallback_font
	var size := int(round(lerpf(30.0, 40.0, minf(t * 4.0, 1.0))))
	var col := space_banner_color
	col.a = clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
	var outline := Color(0.05, 0.04, 0.12, col.a)
	_draw_centered_text(space_banner_text, Vector2(view_size.x * 0.5, _quiz_box_rect(view_size).end.y + 70.0 - t * 16.0), size, col, outline, font)


func _space_fever_started() -> void:
	flash_color = FEVER_FLASH_COLOR
	flash_time = FLASH_DURATION
	if fx_sound_boost_start != null and fx_sound_boost_start.stream != null:
		fx_sound_boost_start.play()


func _space_fever_ended() -> void:
	pass


func _space_fever_smash() -> void:
	run_stardust += SpaceRun.STARDUST_FEVER_SMASH
	score += maxi(1, int(round(SCORE_PER_COMBO * maxi(combo, 1) * FEVER_SMASH_SHARE)))
	if fx_sound_chime != null and fx_sound_chime.stream != null:
		fx_sound_chime.play()


## 게이트를 맞게 지났거나 보스를 잡았을 때 SpaceRun 이 번 만큼을 알린다.
func _space_stardust(amount: int) -> void:
	run_stardust += amount


## 이번 판에 번 스타더스트를 합계에 더해 저장한다. 판을 떠나는 길은 둘 —
## 게임오버(_finish_run)와 일시정지에서 나가기(_reset_game) — 이고 둘 다 부른다.
## 먼저 부른 쪽이 run_stardust 를 비우므로 두 번 더해지지 않는다.
func _bank_stardust() -> void:
	if run_stardust <= 0:
		return
	stardust_total += run_stardust
	run_stardust = 0
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION_META, SAVE_KEY_STARDUST, stardust_total)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("could not write %s (error %d) — stardust will not persist" % [SAVE_PATH, err])
	if mode_select_panel != null:
		mode_select_panel.set_stardust(stardust_total)


var hurt_elapsed: float = -1.0       # -1 = 무적 아님
var heart_lost_elapsed: float = -1.0 # -1 = 사라지는 하트 없음


## 소행성이나 보스 탄에 맞았을 때(_space_hurt). 하트가 남으면 판은 계속되고,
## 마지막 하트였으면 예전의 죽음(_game_over)으로 간다. 하트가 남았는지를 돌려준다.
func _take_hit() -> bool:
	combo = 0
	hearts = maxi(0, hearts - 1)
	heart_lost_elapsed = 0.0
	if hearts <= 0:
		_game_over()
		return false
	hurt_elapsed = 0.0
	flash_color = HURT_FLASH_COLOR
	flash_time = FLASH_DURATION
	fx_shake_elapsed = 0.0
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()
	return true


func _update_hearts(delta: float) -> void:
	if hurt_elapsed >= 0.0:
		hurt_elapsed += delta
		if hurt_elapsed >= HURT_INVULN_DURATION:
			hurt_elapsed = -1.0
	if heart_lost_elapsed >= 0.0:
		heart_lost_elapsed += delta
		if heart_lost_elapsed >= HEART_LOSS_POP_DURATION:
			heart_lost_elapsed = -1.0


## 무적 동안 깜빡이는 캐릭터의 알파.
func _hurt_blink_alpha() -> float:
	if hurt_elapsed < 0.0:
		return 1.0
	return 1.0 if int(hurt_elapsed / HURT_BLINK_PERIOD) % 2 == 0 else HURT_BLINK_ALPHA


## i 번째 체력 칸의 화면 사각형 — 아래부터 쌓는다(0 이 맨 아래). 칸을 잃는
## 순서가 위에서부터라, 남은 체력이 바닥부터 차 있는 게이지로 읽힌다.
func heart_hud_rect(i: int, view_size: Vector2) -> Rect2:
	var inner := _health_rect(view_size).grow_individual(-HEALTH_INSET.x, -HEALTH_INSET.y, -HEALTH_INSET.x, -HEALTH_INSET.y)
	var h: float = (inner.size.y - HEALTH_CELL_GAP * (MAX_HEARTS - 1)) / MAX_HEARTS
	var y: float = inner.end.y - h - i * (h + HEALTH_CELL_GAP)
	return Rect2(inner.position.x, y, inner.size.x, h)


func _draw_hearts(ci: CanvasItem, view_size: Vector2) -> void:
	var slot_tex := ArtSlot.texture(HUD_SIDE_SLOT_PATH)
	_draw_nine_patch(slot_tex, _health_rect(view_size), HUD_SIDE_SLOT_MARGIN,
		_health_rect(view_size).size.y / slot_tex.get_height(), ci)
	for i in range(MAX_HEARTS):
		var rect: Rect2 = heart_hud_rect(i, view_size)
		ci.draw_rect(rect, HEART_FILL if i < hearts else HEART_EMPTY)
		ci.draw_rect(rect, HEART_EDGE, false, 1.5)
	# 방금 잃은 칸은 빈 칸 위에서 부풀며 사라진다.
	if heart_lost_elapsed >= 0.0 and hearts < MAX_HEARTS:
		var t: float = heart_lost_elapsed / HEART_LOSS_POP_DURATION
		var rect2: Rect2 = heart_hud_rect(hearts, view_size)
		var grow: float = lerpf(1.0, HEART_LOSS_POP_SCALE, t)
		var col := HEART_FILL
		col.a = 1.0 - t
		ci.draw_rect(rect2.grow_individual(rect2.size.x * (grow - 1.0) * 0.25, rect2.size.y * (grow - 1.0) * 0.5,
			rect2.size.x * (grow - 1.0) * 0.25, rect2.size.y * (grow - 1.0) * 0.5), col)


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
	state = State.GAMEOVER   # 판의 규칙을 멈추기 위해 — 화면은 아직 안 띄운다
	combo = 0
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	_play_gameover_bgm()
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()
	revive_panel.set_character(sad_face_texture, FACE_DRAW_SIZE)
	revive_panel.set_score(score)
	# 이어 뛰어도 순위표는 여기서 멈춘다는 걸 숫자로 보여 준다.
	revive_panel.set_leaderboard_score(leaderboard_score, player_logged_in)
	revive_panel.visible = true


# 광고를 본 뒤 이어가기. 하트를 채우고 우주 판을 되살려(space.revive) 카운트다운
# 부터 다시 — 점수와 맞힌 수는 그대로 두어 "이어서 뛰는" 것이 되게 한다.
func _on_revive_continue() -> void:
	run_revived = true
	revive_panel.visible = false
	# 하트를 다 잃어서 온 자리다 — 이어 하려면 다시 채워야 한다.
	hearts = MAX_HEARTS
	hurt_elapsed = -1.0
	heart_lost_elapsed = -1.0
	flash_time = 0.0
	space.revive()
	_start_countdown()


# 제안을 거절했을 때 — 여기서부터가 원래의 게임오버다.
func _on_revive_decline() -> void:
	_log_event("revive", {"result": "declined"})
	revive_panel.visible = false
	_finish_run()


# 부활 팝업의 광고 보기. 띄울 광고가 없으면(아직 못 불러옴, 인터넷 없음, PC)
# 그냥 이어 준다 — 플레이어 탓이 아닌데 기회를 빼앗을 까닭이 없고, 부활은 판에
# 한 번뿐인 데다 순위표 점수는 이미 부활 전으로 묶였다(_game_over).
func _on_revive_watch_ad() -> void:
	# 광고 제거를 산 사람은 광고 없이 곧장 이어 간다(주인이 정한 규칙).
	if ads_removed:
		_log_event("revive", {"result": "ad_free"})
		_on_revive_continue()
		return
	if ads == null or not ads.show_rewarded(_on_revive_ad_finished):
		_log_event("revive", {"result": "no_ad"})
		_on_revive_continue()


# 광고가 닫힌 뒤. 끝까지 보지 않고 닫았으면 팝업에 남는다 — 다시 누르거나
# 거절할 수 있다. 띄우려다 실패한 것은 광고가 없던 것과 같게 친다.
func _on_revive_ad_finished(result: int) -> void:
	_log_event("revive", {"result": "skipped" if result == Ads.Reward.SKIPPED \
		else ("watched" if result == Ads.Reward.EARNED else "no_ad")})
	if result == Ads.Reward.SKIPPED:
		return
	_on_revive_continue()


# 전면광고가 닫혔을 때. 실제로 보였을 때만 카운터를 비운다 — 띄우려다 실패했는데
# 비우면 다음 광고까지 또 다섯 판을 기다리게 된다.
func _on_interstitial_finished(shown: bool) -> void:
	ad_hold_countdown = false
	if shown:
		note_interstitial_shown()


# 전체 화면 광고가 떠 있는 동안 게임 소리를 끈다. 광고에도 소리가 있어 BGM 과
# 겹친다. Master 음소거는 게임이 달리 쓰는 곳이 없어 설정의 음량과 부딪치지 않는다.
func _on_ads_fullscreen(showing: bool) -> void:
	AudioServer.set_bus_mute(0, showing)


func _finish_run() -> void:
	state = State.GAMEOVER
	_bank_stardust()
	_log_event("post_score", {
		"level_name": Analytics.mode_name(current_mode),
		"score": score,
		"gates": gates_passed,
		"max_combo": max_combo,
		"revived": 1 if run_revived else 0,
	})
	combo = 0  # combo is purely a run-length streak; a miss always zeroes it immediately, not just on restart
	# Whether this run set a record has to be read BEFORE the record is
	# updated — the popup shows a different face for a new best, and once
	# best_score has been overwritten the two are indistinguishable.
	var is_new_record: bool = score > _best_for(current_mode)
	last_run_new_record = is_new_record
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
	# 로그인해 있으면 이 모드의 순위표 기록을 올린다. 이번 판 점수가 아니라
	# 쌓아 둔 최고 기록을 보낸다 — Play 게임즈는 높은 쪽만 남기므로 손해가 없고,
	# 전에 오프라인이라 못 올린 기록이 있으면 여기서 따라 올라간다.
	_submit_leaderboard(current_mode)
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	# 네 가지 조합(신기록 여부 x 로그인 여부)을 팝업이 스스로 갈래 친다.
	# 신기록이면 웃는 얼굴, 아니면 우는 얼굴.
	var face: Texture2D = happy_face_texture if is_new_record else sad_face_texture
	gameover_popup.set_result(face, FACE_DRAW_SIZE,
		score, max_combo, previous_best, is_new_record, player_logged_in,
		leaderboard_score)
	gameover_popup.visible = true
	_play_gameover_bgm()
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()


# 같은 모드로 곧장 다시 시작한다 — 일시정지의 RESTART와 같은 동작이다.
# (모드 선택으로 돌아가는 건 HOME 쪽이다.)
func _on_gameover_play_again_pressed() -> void:
	gameover_popup.visible = false
	_reset_game()
	_ad_try_interstitial()
	_start_countdown()


func _on_gameover_login_pressed() -> void:
	_sign_in()


func _on_gameover_leaderboard_pressed() -> void:
	_show_leaderboard(current_mode)


## 방금 끝난 판의 점수 카드를 그려 저장하고, 문구와 함께 공유 창을 연다.
##
## 카드를 그리는 데 한 프레임이 걸리므로 그 사이 두 번 눌러도 한 번만 간다.
## PC 에는 공유 창이 없어서 카드만 저장하고 경로를 남긴다 — 카드가 어떻게
## 나오는지 볼 수는 있다.
func _on_gameover_share_pressed() -> void:
	if share_busy or share_card == null:
		return
	_log_event("share", {"method": "share_sheet", "content_type": "score_card",
		"item_id": Analytics.mode_name(current_mode)})
	share_busy = true
	var img: Image = await share_card.render(current_mode, score, last_run_new_record,
		happy_face_texture)
	share_busy = false
	if img == null or img.is_empty():
		push_warning("share: the card rendered empty — no renderer?")
		return
	DirAccess.make_dir_recursive_absolute(SHARE_IMAGE_PATH.get_base_dir())
	var err := img.save_png(SHARE_IMAGE_PATH)
	if err != OK:
		push_warning("share: could not save %s (error %d)" % [SHARE_IMAGE_PATH, err])
		return
	var absolute: String = ProjectSettings.globalize_path(SHARE_IMAGE_PATH)
	if not ShareSheet.share_image(absolute,
			share_card.share_text(current_mode, score), share_card.chooser_title()):
		print("share: no share sheet here — the card is at %s" % absolute)


# 메인 화면 오른쪽 위 톱니바퀴. 지금 볼륨을 넣어 열어 준다.
func _open_settings() -> void:
	settings_popup.set_volumes(sfx_volume, music_volume)
	settings_popup.set_language(TranslationServer.get_locale().begins_with(LOCALE_KO))
	# 프로필 사진과 닉네임은 PlayGames 가 채운다 — _on_play_games_changed 참고.
	settings_popup.set_account(player_avatar, player_display_name, player_logged_in)
	settings_popup.visible = true


func _on_login_pressed() -> void:
	_sign_in()


# 메인 화면 왼쪽 위 사람 모양. 로그인 전에는 로그인하고, 로그인한 뒤에는 설정을
# 연다 — 거기 계정 줄에 누구로 들어가 있는지가 나온다. 로그인된 채로 눌렀는데
# 아무 일도 안 일어나면 고장처럼 보인다.
func _on_mode_select_login_pressed() -> void:
	if player_logged_in:
		_open_settings()
	else:
		_sign_in()


# 로그인 버튼 셋(설정 / 게임오버 / 메인 화면)이 모두 여기로 온다.
func _sign_in() -> void:
	if play_games != null:
		play_games.sign_in()


# PlayGames 가 바뀌었다고 알려 오면 상태를 옮겨 적고, 지금 떠 있는 화면에 바로
# 반영한다. 로그인 창은 게임오버 팝업의 버튼에서도 뜨므로, 결과가 돌아올 때
# 그 팝업이 떠 있을 수 있다 — 그때 LOGIN WITH GOOGLE 이 그대로 남아 있으면
# 로그인이 안 된 것처럼 보인다.
func _on_play_games_changed() -> void:
	var was_logged_in := player_logged_in
	player_logged_in = play_games.signed_in
	player_display_name = play_games.display_name
	player_avatar = play_games.avatar
	if settings_popup != null:
		settings_popup.set_account(player_avatar, player_display_name, player_logged_in)
	if gameover_popup != null and gameover_popup.visible:
		gameover_popup.set_logged_in(player_logged_in)
	if revive_panel != null and revive_panel.visible:
		revive_panel.set_leaderboard_score(leaderboard_score, player_logged_in)
	# 막 로그인했다면 로그인하기 전에 낸 기록까지 올린다. 게임오버 팝업이
	# "최고 기록이 순위표에 있습니다" 라고 말하는 것이 이것 덕에 참이 된다.
	# 로그인 한 번에 이 함수는 여러 번 불리므로(인증, 이름, 사진) 넘어가는
	# 순간에만 한다.
	if player_logged_in and not was_logged_in:
		for mode in range(Mode.size()):
			_submit_leaderboard(mode)


# 쌓아 둔 그 모드의 순위표 기록을 올린다. 로그인 전이거나 기록이 없으면 PlayGames
# 가 알아서 넘어간다.
func _submit_leaderboard(mode: int) -> void:
	if play_games == null or mode < 0 or mode >= MODE_LEADERBOARD_ID.size():
		return
	play_games.submit_score(MODE_LEADERBOARD_ID[mode], leaderboard_bests[mode])


func _show_leaderboard(mode: int) -> void:
	if play_games == null or mode < 0 or mode >= MODE_LEADERBOARD_ID.size():
		return
	play_games.show_leaderboard(MODE_LEADERBOARD_ID[mode])


# 메인 화면의 LEADERBOARD. 고른 카드의 모드 순위표를 연다. 로그인 전이면 로그인
# 부터 하고, 성공하면 이어서 연다 — 로그인만 되고 아무것도 안 열리면 버튼이
# 한 번 헛돈 것처럼 보인다. 창이 이미 떠 있으면 기다리는 쪽을 또 걸지 않는다 —
# 연타한 만큼 순위표가 겹쳐 뜬다.
func _on_mode_select_leaderboard_pressed(mode: int) -> void:
	if player_logged_in:
		_show_leaderboard(mode)
		return
	if play_games == null or play_games.busy:
		return
	play_games.sign_in_finished.connect(_on_signed_in_for_leaderboard.bind(mode), CONNECT_ONE_SHOT)
	play_games.sign_in()


func _on_signed_in_for_leaderboard(ok: bool, mode: int) -> void:
	if ok:
		_show_leaderboard(mode)


# 세 링크는 앱 밖으로 나간다. 주소는 scripts/ExternalLinks.gd 한 곳에 있고,
# 아직 비어 있으면 열리지 않는다 — 설정 화면도 그 줄을 흐리게 그린다.
func _on_privacy_pressed() -> void:
	ExternalLinks.open(ExternalLinks.PRIVACY_POLICY_URL)


# 유럽 사용자가 광고 동의를 다시 고른다. Ads 가 Google 의 동의 화면을 다시 띄운다.
func _on_ad_privacy_pressed() -> void:
	if ads != null:
		ads.show_privacy_options()


# 동의 상태가 새로 읽히면 설정의 광고 동의 줄을 살릴지 다시 정한다.
func _on_ads_consent_changed() -> void:
	settings_popup.set_ad_privacy_available(ads.privacy_options_available())
	# 분석은 Google 이 "동의 필요 없음"이라고 한 곳에서만 켠다(Analytics.gd 참고).
	if analytics != null:
		analytics.set_consent_status(ads.consent_status)


# 분석 이벤트 한 줄. 분석 노드가 없거나(체커 일부) 수집이 꺼져 있으면 버려진다.
func _log_event(event_name: String, params: Dictionary = {}) -> void:
	if analytics != null:
		analytics.log_event(event_name, params)


func _on_terms_pressed() -> void:
	ExternalLinks.open(ExternalLinks.TERMS_OF_SERVICE_URL)


func _on_about_closed() -> void:
	about_popup.visible = false
	settings_popup.visible = true


# 메일 앱을 연다. 주소가 없으면 contact_url 이 빈 문자열을 주고 open 이 거른다.
func _on_contact_pressed() -> void:
	ExternalLinks.open(ExternalLinks.contact_url())


# About 을 여는 동안 설정은 감춘다. 겹쳐 두면 두 판의 테두리와 닫기 버튼이
# 서로 비어져 나와 지저분하다. 닫으면 설정으로 돌아온다.
func _on_about_pressed() -> void:
	settings_popup.visible = false
	about_popup.visible = true


# 설정의 REMOVE ADS 와 모드 선택 화면 아래의 "광고 제거" 줄. 결과는 결제 창이
# 닫힌 뒤 Store 가 ownership_changed 로 알려 온다.
func _on_remove_ads_pressed() -> void:
	if ads_removed:
		return
	if store == null or not store.buy():
		print("[결제] 지금은 결제 창을 열 수 없다 — PC 이거나, 스토어 연결·상품 조회 전이다")


# Google Play 의 답. 저장해 둔 것과 다를 때만 바꾼다 — 사서 생기거나, 환불로
# 없어지거나.
func _on_store_ownership(owned: bool) -> void:
	if owned == ads_removed:
		return
	ads_removed = owned
	_save_ad_state()
	print("[결제] 광고 제거 %s" % ("적용" if owned else "해제 (환불되었거나 내역에 없다)"))
	_apply_ads_removed()


# 광고 제거 여부를 화면 곳곳에 건다.
func _apply_ads_removed() -> void:
	settings_popup.set_ads_removed(ads_removed)
	mode_select_panel.set_ads_removed(ads_removed)
	revive_panel.set_ad_free(ads_removed)


func _on_mode_selected(mode: int) -> void:
	# 메인 화면의 PLAY 가 곧 시작이다.
	_apply_mode(mode)
	_reset_game()
	# 게임 화면에 처음 들어온 것이면 튜토리얼을 먼저 돌린다. 다 보고 나면
	# _on_tutorial_finished 가 이어서 카운트다운을 건다.
	if (not tutorial_seen or _tutorial_forced()) and tutorial_overlay != null:
		_begin_tutorial()
		return
	_start_countdown()


# ---- 튜토리얼 (설치 후 1회, 모드 무관) ----
#
# 메뉴가 아니라 게임 화면 위에서 돈다. 설명하는 것들이 전부 "화면의 이 물건"에
# 관한 것이라, 그 물건을 옆에 두고 봐야 옮겨진다.
#
# State.COUNTDOWN 에 세워 둔다. 이 상태는 세계를 그리면서 물리는 안 돌리는
# 유일한 상태라 그대로 쓸 수 있고, 시계만 tutorial_active 로 멈춘다
# (_process). READY/START 글자도 같은 값으로 잠시 접어 둔다.
# 다시 보기 스위치가 지금 듣고 있는가. 릴리스 빌드에서는 언제나 false 다.
func _tutorial_forced() -> bool:
	return debug_replay_tutorial and OS.is_debug_build()


func _begin_tutorial() -> void:
	_log_event("tutorial_begin")
	tutorial_active = true
	_set_state(State.COUNTDOWN)
	var view_size := get_viewport_rect().size
	# 문제가 하나 떠 있어야 상자를 가리킬 수 있다.
	if space.upcoming_wave().is_empty():
		space.spawn_wave()
	_apply_screen_visibility()
	tutorial_overlay.begin(_tutorial_steps(view_size))
	queue_redraw()


# 밝힐 자리와 문구. 자리는 전부 게임이 실제로 그리는 데서 가져온다 — 여기에
# 좌표를 적어 두면 HUD 를 옮길 때 하이라이트만 옛 자리에 남는다.
func _tutorial_steps(view_size: Vector2) -> Array:
	var ship: Rect2 = space.ship_screen_rect()
	var quiz: Rect2 = _quiz_box_rect(view_size)
	var gauge: Rect2 = space.gauge_rect(quiz)
	var weapon: Rect2 = space.weapon_label_rect()
	return [
		{
			"holes": [{"rect": ship, "round": maxf(ship.size.x, ship.size.y)}],
			"text": tr("DRAG anywhere to steer the ship.\nIt fires on its own."),
			# 우주선 바로 아래 빈 자리. 우주선 위에 겹치면 정작 밝힌 것을 가린다.
			"tap": Vector2(view_size.x * 0.5, ship.end.y + ship.size.y * 0.8),
		},
		{
			"holes": [{"rect": quiz, "round": quiz.size.y * 0.42}],
			"text": tr("Fly through the gate this box\nasks for: its colour, its arrow,\nor its symbols, in order."),
		},
		{
			# 게이지(패턴 10칸의 진행)와 무기 표시를 같이 밝힌다 — 연달아 맞힐수록
			# 아래쪽 무기가 오르고, 위쪽 게이지가 금색인 채로 차면 피버가 온다.
			"holes": [
				{"rect": gauge.grow(4.0), "round": gauge.size.y},
				{"rect": weapon, "round": weapon.size.y * 0.5},
			],
			"text": tr("Right gates in a row speed you up,\npower your gun and pay more stardust.\nAll 10 right: FEVER!"),
		},
	]


func _on_tutorial_finished() -> void:
	_log_event("tutorial_complete")
	tutorial_active = false
	# 다 본 순간 저장한다. 판이 끝날 때 쓰면 첫 판 도중에 앱이 죽었을 때
	# 다음 실행에서 또 돈다. 다시 보기로 켜서 돈 것은 저장하지 않는다.
	if not _tutorial_forced():
		tutorial_seen = true
		_save_tutorial_seen()
	# 튜토리얼용으로 띄워 둔 게이트는 그대로 두고 시작한다 — 지우면 첫 게이트가
	# 한 칸 늦게 오고, 그 한 칸이 다른 판과 다른 시작이 된다.
	_start_countdown()


# Sets the mode and loads the art the play screen and its popups draw —
# called once from _boot_load and again every time the mode select starts a
# run. None of it differs per mode any more (the per-mode 1.x art went with
# 1.x); the mode itself still keys the best scores and the leaderboards.
func _apply_mode(mode: int) -> void:
	current_mode = mode
	happy_face_texture = ArtSlot.texture(FACE_HAPPY_PATH)
	sad_face_texture = ArtSlot.texture(FACE_SAD_PATH)
	# 부활 팝업이 쓸 얼굴을 미리 넘겨 둔다. 팝업이 알파 경계를 다듬느라
	# 30ms쯤 쓰는데, 판이 끝난 그 순간에 그러면 멈칫하는 게 느껴진다.
	if revive_panel != null:
		revive_panel.set_character(sad_face_texture, FACE_DRAW_SIZE)
	ready_texture = _softened_word_art(ArtSlot.texture(READY_TEXTURE_PATH), COUNTDOWN_READY_WIDTH)
	start_texture = _softened_word_art(ArtSlot.texture(START_TEXTURE_PATH), COUNTDOWN_START_WIDTH)
	if score_crown_texture == null:
		# 아이콘 캔버스에 투명 여백이 넉넉히 붙어 있어, 잘라 내지 않으면 같은
		# 높이로 그려도 왕관만 작아 보인다.
		score_crown_texture = _load_trimmed(BEST_CROWN_PATH, true)
	score_box_texture = ArtSlot.texture(HUD_SCORE_BAR_PATH)
	quiz_box_texture = ArtSlot.texture(HUD_QUIZ_BOX_PATH)
	pause_button.icon = ArtSlot.texture(HUD_PAUSE_PATH)
	# Re-run now that the icon is loaded: _boot_load lays the row out before
	# any mode is applied, so it sizes off the HUD_BUTTON_SRC fallback.
	_layout_hud_buttons()


func _start_countdown() -> void:
	run_active = true   # 여기부터 "떠날 수 있는 판"이 된다 — _reset_game 참고
	# 부활해 이어 뛸 때도 여기를 지나지만 같은 판이다 — 판의 시작은 한 번만 센다.
	if not run_revived:
		_log_event("level_start", {"level_name": Analytics.mode_name(current_mode)})
	countdown_phase = CountdownPhase.READY_TEXT
	countdown_timer = COUNTDOWN_READY_DURATION
	_set_state(State.COUNTDOWN)
	if fx_sound_countdown_ready.stream != null:
		fx_sound_countdown_ready.play()
	# A run may be starting again after a game over silenced the music.
	_play_bgm(_bgm_path_for_state())


func _reset_game() -> void:
	# 판을 떠나는 네 경로(게임오버 PLAY AGAIN/HOME, 일시정지 RESTART/HOME)가
	# 전부 여기를 지난다. 세는 자리를 여기 하나로 두면 경로를 빠뜨릴 수 없다 —
	# 핸들러마다 넣으면 나중에 다섯 번째 경로가 생겼을 때 조용히 안 세어진다.
	if run_active:
		_ad_note_run_left()
		run_active = false
	_bank_stardust()
	score = 0
	combo = 0
	max_combo = 0
	gates_passed = 0
	revive_offered = false
	run_revived = false
	leaderboard_score = 0
	hearts = MAX_HEARTS
	hurt_elapsed = -1.0
	heart_lost_elapsed = -1.0
	if revive_panel != null:
		revive_panel.visible = false
	flash_time = 0.0
	combo_display_punch_elapsed = 0.0
	combo_display_time = 0.0
	fx_shake_elapsed = -1.0
	combo_shake_elapsed = -1.0
	combo_glow_elapsed = -1.0
	position = Vector2.ZERO  # in case a restart lands mid-shake
	paused = false
	pause_panel.visible = false
	space_banner_elapsed = -1.0
	# 첫 문제는 바로 띄운다 — 카운트다운 동안 이미 읽을 수 있게.
	space.reset_run()


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
	_ad_try_interstitial()
	_start_countdown()


# 일시정지 팝업의 HOME — 모드 선택 화면으로. 진행 중이던 판은 버린다.
func _on_pause_home_pressed() -> void:
	pause_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_reset_game()
	_ad_try_interstitial()
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


# ---- 전면광고 판단. 위 @export 블록의 주석에 규칙이 있다. ----

# 판 하나를 떠났다. _reset_game 에서만 부른다.
func _ad_note_run_left() -> void:
	games_played_total += 1
	# 면제 구간의 판은 세지도 않는다. 처음에는 세되 노출만 막았는데, 그러면
	# 면제가 끝나는 순간 카운터가 이미 3이라 두 판 만에 첫 광고가 나온다 —
	# "5판마다"면 첫 광고가 5판째라, 면제 3판이 아무 일도 안 하는 값이 된다.
	# 세지 않아야 두 값이 각자 뜻대로 움직인다: 처음 3판 무료, 그 뒤 5판마다.
	if games_played_total <= interstitial_free_games:
		_save_ad_state()
		return
	# 리워드 광고를 본 판은 카운터에 넣지 않는다. run_revived 가 곧 "부활
	# 광고를 보고 이어 뛰었다"이므로 따로 플래그를 두지 않는다 — 두 개를 두면
	# 언젠가 한쪽만 갱신된다.
	if not run_revived:
		restarts_since_interstitial += 1
	_save_ad_state()


## 지금 전면광고를 띄워야 하는가. 실제로 띄우는 것은 부르는 쪽의 몫이다.
func should_show_interstitial() -> bool:
	if games_played_total <= interstitial_free_games:
		return false
	return restarts_since_interstitial >= interstitial_every_restarts


## 광고가 실제로 나갔을 때 부른다. 판단과 분리해 둔 이유는, 플러그인이 붙으면
## 광고 로드 실패나 사용자 이탈로 안 나갈 수 있기 때문이다 — 그때 카운터를
## 비우면 다음 기회까지 또 다섯 판을 기다리게 된다.
func note_interstitial_shown() -> void:
	restarts_since_interstitial = 0
	_save_ad_state()


# 전면광고를 띄울 차례인지 보고, 차례면 띄운다. 띄웠으면(또는 띄운 것으로
# 쳤으면) true.
#
# 광고 모듈이 없는 곳(PC, 헤드리스)에서는 예전처럼 "띄웠다" 치고 카운터만
# 비운다 — 이 판단 층을 check_ad_policy.gd 가 PC 에서 잰다. 기기에서는 준비된
# 광고가 있을 때만 띄우고, 카운터는 광고가 닫힌 뒤(_on_interstitial_finished)
# 비운다. 준비된 것이 없으면 그대로 두어 다음 기회에 다시 시도한다.
func _ad_try_interstitial() -> bool:
	# 광고 제거를 샀으면 전면광고는 없다. 카운터도 건드리지 않는다.
	if ads_removed:
		return false
	if not should_show_interstitial():
		return false
	# 단위 ID 를 같이 찍어 잠금장치가 걸려 있는지 로그로 보이게 한다.
	print("[광고] 전면광고 노출 지점 (누적 %d판, 마지막 광고 이후 %d판) unit=%s" % [
		games_played_total, restarts_since_interstitial, AdIds.interstitial_id()])
	if ads == null or not ads.available:
		note_interstitial_shown()
		return true
	if not ads.show_interstitial(_on_interstitial_finished):
		print("[광고] 준비된 전면광고가 없어 다음 기회로 미룬다")
		return false
	ad_hold_countdown = true
	return true


func _load_ad_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		games_played_total = int(cfg.get_value(
			SAVE_SECTION_ADS, SAVE_KEY_GAMES_PLAYED, games_played_total))
		restarts_since_interstitial = int(cfg.get_value(
			SAVE_SECTION_ADS, SAVE_KEY_RESTARTS_SINCE_AD, restarts_since_interstitial))
		ads_removed = bool(cfg.get_value(SAVE_SECTION_ADS, SAVE_KEY_ADS_REMOVED, ads_removed))


func _save_ad_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION_ADS, SAVE_KEY_GAMES_PLAYED, games_played_total)
	cfg.set_value(SAVE_SECTION_ADS, SAVE_KEY_RESTARTS_SINCE_AD, restarts_since_interstitial)
	cfg.set_value(SAVE_SECTION_ADS, SAVE_KEY_ADS_REMOVED, ads_removed)
	cfg.save(SAVE_PATH)


# 저장해 둔 언어. 없으면 기기 언어를 그대로 쓴다.
#
# 다른 설정들과 달리 _boot_load 의 맨 앞에서 불린다 — 판을 짓는 것보다 먼저
# 정해져 있어야 한다. 여기 뒤로 밀려 있었을 때는, 한국어를 고른 기기에서
# 영어를 골라 두고 다시 켜면 화면 전체가 한국어로 뜬 뒤 로케일만 영어가
# 되어 있었다.
func _load_language() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved: String = str(cfg.get_value(SAVE_SECTION_LOCALE, SAVE_KEY_LANGUAGE, ""))
	if saved != "":
		TranslationServer.set_locale(saved)


# ---- 언어 ----
#
# 설정에서 ENG/KOR 을 고를 때. 저장한 뒤 화면들을 다시 짓는다.
#
# 다시 짓는 것 말고는 방법이 마땅치 않다. 이 프로젝트는 글자를 그릴 때 tr() 을
# 거치는데, 그 결과가 라벨의 text 나 미리 맞춰 둔 글자 크기·판 너비로 굳어
# 있다 — 로케일만 바꾸면 이미 굳은 것들은 옛 언어 그대로 남는다. 판을 새로
# 짓게 하면 모든 tr() 과 모든 맞춤 계산이 새 언어로 다시 돈다.
func set_language_korean(korean: bool) -> void:
	var want: String = LOCALE_KO if korean else LOCALE_EN
	if TranslationServer.get_locale().begins_with(want):
		return
	TranslationServer.set_locale(want)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION_LOCALE, SAVE_KEY_LANGUAGE, want)
	cfg.save(SAVE_PATH)
	# 지금 이 호출은 설정 팝업의 버튼 신호 안이다. 그 팝업을 여기서 헐면
	# 신호를 쏜 노드가 자기 아래에서 사라진다.
	_rebuild_for_language.call_deferred()


func _rebuild_for_language() -> void:
	for panel in [pause_panel, revive_panel, gameover_popup, settings_popup, about_popup,
			mode_select_panel]:
		if panel != null and panel.has_method("rebuild"):
			panel.rebuild()
	# 설정 팝업은 다시 지어지면서 토글도 초기값으로 돌아간다 — 지금 값을 도로
	# 넣어 준다.
	if settings_popup != null:
		settings_popup.set_language(TranslationServer.get_locale().begins_with(LOCALE_KO))
		settings_popup.set_volumes(sfx_volume, music_volume)
		settings_popup.set_account(player_avatar, player_display_name, player_logged_in)
	if pause_panel != null:
		pause_panel.set_volumes(sfx_volume, music_volume)
	if mode_select_panel != null:
		mode_select_panel.set_best_scores(best_scores)
		mode_select_panel.set_stardust(stardust_total)
	queue_redraw()


# 최고 점수와 같은 파일을 쓰므로, 먼저 읽어 들여 다른 값을 지우지 않는다.
func _save_audio_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SAVE_SECTION_AUDIO, SAVE_KEY_SFX, sfx_volume)
	cfg.set_value(SAVE_SECTION_AUDIO, SAVE_KEY_MUSIC, music_volume)
	cfg.save(SAVE_PATH)


func _animate_button_press(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * BUTTON_PRESS_SCALE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animate_button_release(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 로고 화면. 검은 바탕에 로고 한 장, 페이드 인/아웃.
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

	var logo_w: float = view_size.x * LOGO_WIDTH_FRAC
	var logo_h: float = logo_w * float(logo_texture.get_height()) / float(logo_texture.get_width())
	var top: float = view_size.y * LOGO_BLOCK_CENTER_FRAC - logo_h * 0.5
	draw_texture_rect(logo_texture,
		Rect2(view_size.x * 0.5 - logo_w * 0.5, top, logo_w, logo_h),
		false, Color(1.0, 1.0, 1.0, alpha))


var title_font: Font
## WARP GATE's fill: its own CanvasItem so it can carry the gradient shader
## (draw_string has no gradient), drawn over the rims Main lays down. Where
## and how big come from _draw_splash, which is what places everything else.
var title_sub_layer: Node2D
var title_sub_pos := Vector2.ZERO
var title_sub_size := 0


## The title screen's art and face. Kept on Main, not read inside the draw —
## see ArtSlot.texture for why a texture loaded there would draw white.
func _load_title_art() -> void:
	for p in [TitleArt.STAR_PATH, TitleArt.WREATH_PATH, TITLE_BAR_PATH]:
		ArtSlot.texture(p)
	title_font = TitleArt.font(combo_font)
	if title_sub_layer == null:
		title_sub_layer = Node2D.new()
		title_sub_layer.name = "TitleSubtitle"
		var mat := ShaderMaterial.new()
		mat.shader = load(TITLE_SUBTITLE_SHADER_PATH)
		mat.set_shader_parameter("top_color", TITLE_SUBTITLE_TOP)
		mat.set_shader_parameter("bottom_color", TITLE_SUBTITLE_BOTTOM)
		title_sub_layer.material = mat
		title_sub_layer.draw.connect(_draw_title_subtitle_fill)
		add_child(title_sub_layer)


func _draw_splash(view_size: Vector2) -> void:
	# The world keeps flowing behind the title, dimmed to the banner's blue.
	var world: Texture2D = space.texture() if space != null else null
	if world != null:
		draw_texture_rect(world, Rect2(Vector2.ZERO, view_size), false)
	draw_rect(Rect2(Vector2.ZERO, view_size), TITLE_DIM)
	var k: float = view_size.x / 480.0
	var mid := Vector2(view_size.x * 0.5, view_size.y * TITLE_MID_Y_FRAC)

	# The band of light: clear at its edges, strongest through the middle.
	var bh: float = TITLE_BAND_HEIGHT * k
	var clear := Color(TITLE_BAND_COLOR, 0.0)
	for half in [-1.0, 1.0]:
		var edge_y: float = mid.y + half * bh * 0.5
		draw_polygon(PackedVector2Array([Vector2(0, mid.y), Vector2(view_size.x, mid.y),
			Vector2(view_size.x, edge_y), Vector2(0, edge_y)]),
			PackedColorArray([TITLE_BAND_COLOR, TITLE_BAND_COLOR, clear, clear]))

	# The bar, across the screen at its own proportions (its linework would
	# warp if stretched) — drawn before the crest, which stands in front of it
	# as the banner's does.
	var bar_tex := ArtSlot.texture(TITLE_BAR_PATH)
	var bar_w: float = view_size.x - 12.0 * k
	var bar_h: float = bar_w * bar_tex.get_height() / bar_tex.get_width()
	draw_texture_rect(bar_tex, Rect2(6.0 * k, mid.y + TITLE_BAR_Y * k, bar_w, bar_h), false)

	# The crest and WARP / GATE either side of it — TitleArt, shared with the
	# mode select.
	var font: Font = title_font if title_font != null else combo_font
	TitleArt.draw_emblem(self, mid, TITLE_STAR_HEIGHT * k, TITLE_WREATH_HEIGHT * k,
		view_size.x, 6.0 * k, int(TITLE_WORD_SIZE * k), font, k)

	_draw_title_subtitle(font, Vector2(mid.x, mid.y + TITLE_SUBTITLE_Y * k), k)
	_draw_splash_prompt(view_size)


## WARP GATE, dressed: a warm glow, a dark rim under an orange one, gold
## rules with diamonds either side. The gradient fill itself goes on
## title_sub_layer, over all of this.
func _draw_title_subtitle(font: Font, centre: Vector2, k: float) -> void:
	var size := int(TITLE_SUBTITLE_SIZE * k)
	var w: float = font.get_string_size(TITLE_SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(centre.x - w * 0.5, centre.y + size * 0.36)
	title_sub_pos = pos
	title_sub_size = size
	for r: float in TITLE_SUBTITLE_GLOW_RADII:
		for i in 8:
			var o := Vector2.from_angle(i * TAU / 8.0) * r * k
			draw_string_outline(font, pos + o, TITLE_SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, TITLE_SUBTITLE_GLOW)
	draw_string_outline(font, pos, TITLE_SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(6, size / 4), TITLE_SUBTITLE_OUTLINE)
	draw_string_outline(font, pos, TITLE_SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 9), TITLE_SUBTITLE_RIM)
	# The rules: a line from just off the word outward, a diamond at each end.
	for side in [-1.0, 1.0]:
		var inner_x: float = centre.x + side * (w * 0.5 + TITLE_SUBTITLE_RULE_GAP * k)
		var outer_x: float = inner_x + side * TITLE_SUBTITLE_RULE_LENGTH * k
		var y: float = centre.y
		draw_line(Vector2(inner_x, y), Vector2(outer_x, y), TITLE_SUBTITLE_OUTLINE, 5.0 * k, true)
		draw_line(Vector2(inner_x, y), Vector2(outer_x, y), TITLE_SUBTITLE_BOTTOM, 2.0 * k, true)
		_draw_title_diamond(Vector2(outer_x, y), 7.0 * k)
		_draw_title_diamond(Vector2(inner_x, y), 4.0 * k)


func _draw_title_diamond(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var rim := PackedVector2Array([c + Vector2(0, -r - 2), c + Vector2(r + 2, 0), c + Vector2(0, r + 2), c + Vector2(-r - 2, 0)])
	draw_colored_polygon(rim, TITLE_SUBTITLE_OUTLINE)
	draw_polygon(pts, PackedColorArray([TITLE_SUBTITLE_TOP, TITLE_SUBTITLE_BOTTOM, TITLE_SUBTITLE_BOTTOM, TITLE_SUBTITLE_TOP]))


## The fill, on title_sub_layer: white glyphs that the shader paints from
## TITLE_SUBTITLE_TOP at the cap line to TITLE_SUBTITLE_BOTTOM at the baseline.
func _draw_title_subtitle_fill() -> void:
	if state != State.SPLASH or title_sub_size <= 0:
		return
	var font: Font = title_font if title_font != null else combo_font
	var mat := title_sub_layer.material as ShaderMaterial
	mat.set_shader_parameter("top_y", title_sub_pos.y - title_sub_size * 0.74)
	mat.set_shader_parameter("bottom_y", title_sub_pos.y)
	title_sub_layer.draw_string(font, title_sub_pos, TITLE_SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, title_sub_size, Color.WHITE)


func _draw_splash_prompt(view_size: Vector2) -> void:
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
	_draw_centered_text(SPLASH_PROMPT_TEXT, Vector2.ZERO, font_size, fill, outline, title_font if title_font != null else combo_font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Gold bloom behind the prompt. Called inside the prompt's own transform, so
# it is placed about the origin and scales with the swell. `strength` is
# 0..1 and rides the same pulse as the text.
func _draw_splash_prompt_glow(font_size: int, strength: float) -> void:
	if strength <= 0.001:
		return
	var font: Font = title_font if title_font != null else (combo_font if combo_font != null else ThemeDB.fallback_font)
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


# target_db 는 다 페이드인했을 때의 크기다. 기본은 0(원래 크기) 이고 게임오버
# 곡만 낮춰 깐다 — 버스 볼륨을 건드리면 설정의 음악 슬라이더와 싸우게 되므로
# 플레이어 쪽에서 낮춘다.
func _play_bgm(path: String, target_db: float = 0.0) -> void:
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
	bgm_fade_tween.tween_property(target, "volume_db", target_db, BGM_CROSSFADE_TIME)
	bgm_fade_tween.tween_property(outgoing, "volume_db", BGM_SILENT_DB, BGM_CROSSFADE_TIME)
	bgm_fade_tween.chain().tween_callback(outgoing.stop)


# 부활 제안과 게임오버가 같은 곡을 같은 크기로 깐다. 두 곳에서 같은 두 값을
# 적으면 한쪽만 고치는 날이 온다.
#
# 파일이 없으면 _resolve_audio 가 빈 문자열을 주고 _play_bgm 은 아무 일도 안
# 한다 — 그러면 판이 끝나도 게임 곡이 계속 흐르게 되므로, 그때는 예전처럼
# 끊는다.
func _play_gameover_bgm() -> void:
	var path: String = _resolve_audio(BGM_GAMEOVER_NAME)
	if path == "":
		_stop_bgm()
		return
	_play_bgm(path, gameover_bgm_db)


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
		mode_select_panel.set_stardust(stardust_total)


# 지금 화면에 무엇이 보여야 하는가. _set_state 말고 _boot_load 끝에서도 부른다 —
# 로고가 떠 있는 동안 만들어진 노드(제목 글자 층 등)는 기본값이 "보임"이라,
# 다시 적용하지 않으면 로고 위로 튀어나온다.
func _apply_screen_visibility() -> void:
	if title_sub_layer != null:
		title_sub_layer.visible = state == State.SPLASH
	mode_select_panel.visible = state == State.MODE_SELECT
	# 띄우는 쪽은 _finish_run(어느 갈래인지 아는 쪽)이라, 여기서는 끄기만 한다.
	if gameover_popup != null and state != State.GAMEOVER:
		gameover_popup.visible = false
	# 설정과 About 은 메인 화면에서만 열 수 있고, 화면이 바뀌면 닫는다.
	if settings_popup != null:
		settings_popup.visible = false
	if about_popup != null:
		about_popup.visible = false


# ---- The play-screen HUD: score bar + quiz row (drawn on HudCanvas, above
# the world) ----

# Source size of a HUD piece: the loaded texture's own size, or the
# fallback when it isn't loaded yet.
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
# fill the screen width inside the margins. (Mute has gone; the formula still
# counts it so the row keeps its scale, and the score box takes its width —
# see _score_box_rect.) Everything in the row is sized from this, so enlarging
# the button automatically takes width back off the score box instead of
# overflowing the screen.
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
	# 소리 끄기 버튼이 빠진 뒤로는(2026-11-26, 설정으로 옮겨 감) 일시정지 버튼
	# 오른쪽부터 화면 오른쪽 여백까지가 점수판이다. 높이는 그대로 두고 폭만
	# 그 자리를 채운다 — SCORE 는 왼쪽 칸, 최고 점수는 오른쪽 칸.
	var button_w: float = _hud_src(pause_button.icon if pause_button != null else null, HUD_BUTTON_SRC).x \
		* _hud_row_scale(view_size) * _hud_button_mult()
	var left: float = HUD_ROW_SIDE_MARGIN + button_w + HUD_ROW_GAP
	draw_size.x = view_size.x - HUD_ROW_SIDE_MARGIN - left
	return Rect2(Vector2(left, SCORE_BOX_TOP), draw_size)


# Screen rect of the quiz box art, parked directly under the score box. It
# spans the full width inside the margins rather than following the row
# scale — it has no neighbours to share the line with.
func _quiz_row_rect(view_size: Vector2) -> Rect2:
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


# 두 번째 줄은 세 칸이다(2026-11-26): 체력 | 문제 박스 | 스타더스트(처음엔 룰렛). 줄 전체의 자리와
# 높이는 예전 문제 박스 그대로(_quiz_row_rect) 두고 폭만 나눈다 — 그래야 그
# 아래 게이트가 놓이는 판이 한 픽셀도 안 움직인다. 하트가 게이지 아래,
# 룰렛이 그 가운데에 따로 있던 것을 문제 박스 양옆으로 올려, 게이트가 날아오는
# 판 위에는 아무것도 걸리지 않게 했다.
func _quiz_box_rect(view_size: Vector2) -> Rect2:
	var row := _quiz_row_rect(view_size)
	var left: float = row.position.x + SIDE_SLOT_WIDTH + HUD_SLOT_GAP
	var right: float = row.end.x - SIDE_SLOT_WIDTH - HUD_SLOT_GAP
	return Rect2(Vector2(left, row.position.y), Vector2(right - left, row.size.y))


func _health_rect(view_size: Vector2) -> Rect2:
	var row := _quiz_row_rect(view_size)
	return Rect2(row.position, Vector2(SIDE_SLOT_WIDTH, row.size.y))


func _stardust_rect(view_size: Vector2) -> Rect2:
	var row := _quiz_row_rect(view_size)
	return Rect2(Vector2(row.end.x - SIDE_SLOT_WIDTH, row.position.y), Vector2(SIDE_SLOT_WIDTH, row.size.y))


# Sizes and parks the pause button off the score box, so the two stay on one
# line if SCORE_BOX_TOP gets retuned.
func _layout_hud_buttons() -> void:
	var view_size := get_viewport_rect().size
	var box := _score_box_rect(view_size)
	var size: Vector2 = _hud_src(pause_button.icon, HUD_BUTTON_SRC) * _hud_row_scale(view_size) * _hud_button_mult()
	# Hung off the score box's bottom edge, so the two bottoms land on one line.
	var top: float = box.end.y - size.y + HUD_BUTTON_Y_OFFSET
	pause_button.set_deferred("size", size)
	pause_button.set_deferred("position", Vector2(HUD_ROW_SIDE_MARGIN, top))
	pause_button.set_deferred("pivot_offset", size * 0.5)


# Called from HudCanvas._draw. Everything here draws onto `ci` (the HUD's
# own canvas) rather than onto Main, which is the whole point — see
# scripts/HudCanvas.gd.
func draw_hud_into(ci: CanvasItem, view_size: Vector2) -> void:
	if state == State.PLAYING or state == State.COUNTDOWN:
		_draw_hud_bar(view_size, ci)
		_draw_quiz_box(view_size, ci)
		space.draw_hud(ci, _quiz_box_rect(view_size), _stardust_rect(view_size))
		_draw_hearts(ci, view_size)
	_draw_combo_glow(view_size, ci)


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
	# PauseButton (a real Button node, see scene) occupies the top-left
	# corner; nothing drawn here for it. Combo lives under the quiz row's
	# right end (see _draw_combo_popups), not here — this only ever draws the
	# score box.
	if score_box_texture == null:
		return
	var rect := _score_box_rect(view_size)
	if SCORE_BOX_PANEL_VISIBLE:
		_draw_horizontal_slice(score_box_texture, rect, HUD_SCORE_BAR_CAP, ci)
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


func _draw_quiz_box(view_size: Vector2, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var question: String = space.question()
	if question == "" or quiz_box_texture == null:
		return
	var text: String = tr(question)
	var rect := _quiz_box_rect(view_size)
	var draw_size: Vector2 = rect.size
	var top_left: Vector2 = rect.position
	_draw_horizontal_slice(quiz_box_texture, rect, HUD_QUIZ_BOX_CAP, ci)
	var pad: float = draw_size.x * QUIZ_TEXT_SIDE_PAD_FRAC
	var area_left: float = top_left.x + draw_size.x * QUIZ_TEXT_LEFT_FRAC + pad
	var area_right: float = top_left.x + draw_size.x * QUIZ_TEXT_RIGHT_FRAC - pad
	var max_width: float = area_right - area_left
	# Sized off the WIDTH on purpose — see QUIZ_TEXT_MAX_FONT_FRAC — and off the
	# whole row's, not the box's: since the health and stardust slots took
	# the box's sides (2026-11-26) the box is narrower, and the question
	# should not shrink with it. _fit_font_size still shrinks a long one.
	var row_w: float = _quiz_row_rect(view_size).size.x
	var max_font_size: int = int(round(row_w * QUIZ_TEXT_MAX_FONT_FRAC))
	var min_font_size: int = int(round(row_w * QUIZ_TEXT_MIN_FONT_FRAC))
	var font_size := _fit_font_size(text, max_width, max_font_size, min_font_size, combo_font)
	# Centred within the writing area, clear of the frame's end caps.
	var text_center := Vector2((area_left + area_right) * 0.5, top_left.y + draw_size.y * QUIZ_TEXT_CENTER_Y_FRAC)
	_draw_centered_text(text, text_center, font_size, HUD_TEXT_COLOR, Color(0.0, 0.0, 0.0, 0.0), combo_font, ci, QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC)


func _draw() -> void:
	var view_size := get_viewport_rect().size
	if state == State.LOGO:
		_draw_logo(view_size)
		return
	if state == State.SPLASH:
		_draw_splash(view_size)
		return
	# 우주 판: 3D 세계(배경·우주선·행성·파편)를 통째로 깔고, 행성 위의 답
	# 팻말만 2D 로 얹는다.
	var tex: Texture2D = space.texture()
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, view_size), false)
	space.draw_labels(self, combo_font if combo_font != null else ThemeDB.fallback_font)
	_draw_space_banner(view_size)
	_draw_overlay_layers(view_size)


## 게임 화면 맨 위의 효과·카운트다운·번쩍임.
func _draw_overlay_layers(view_size: Vector2) -> void:
	# ---- Layer 3: HUD bar + quiz box ----
	# Drawn by the HudCanvas child instead of here, so it can use its own
	# texture filter. The child renders after this whole _draw, which keeps
	# the HUD above the world — see draw_hud_into.

	# ---- Layer 4: effects layer (top of everything drawn above) ----
	_draw_combo_popups(view_size)
	# _draw_combo_glow also moved to HudCanvas: its top band overlaps the
	# score box, and it has to stay on top of it the way it was here.

	if state == State.COUNTDOWN and not tutorial_active:
		var countdown_center := Vector2(view_size.x * 0.5, view_size.y * 0.5)
		if countdown_phase == CountdownPhase.READY_TEXT:
			_draw_countdown_image(ready_texture, countdown_center, 1.0, COUNTDOWN_READY_WIDTH)
		else:
			var t: float = 1.0 - (countdown_timer / COUNTDOWN_START_DURATION)
			_draw_countdown_image(start_texture, countdown_center, _pop_scale(t), COUNTDOWN_START_WIDTH)

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
	# 숫자는 가장 넓은 자릿수에 맞춘 고정 칸에 하나씩 넣는다. 점수가 오르며
	# 1 이 7 로 바뀔 때 그 앞뒤가 흔들리지 않게 하는 것이 이 함수의 존재
	# 이유이고, 비례폭 글꼴에 draw_string 한 번으로는 얻을 수 없다.
	#
	# 다만 숫자 아닌 글자는 제 폭을 쓴다. ScoreFormat.compact 가 "1.2M" 같은
	# 것을 돌려주기 시작하면서 필요해졌다 — 마침표를 숫자 칸에 넣으면 양옆이
	# 반 칸씩 비어 "1 . 2 M" 처럼 벌어지고, K/M 은 숫자보다 넓어 반대로
	# 이웃을 파고든다. 자릿수 정렬은 자릿수에만 필요하다.
	var cell := 0.0
	for d in range(10):
		cell = maxf(cell, font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var glyph := PackedFloat32Array()
	var cells := PackedFloat32Array()
	var total_width: float = extra_spacing * maxi(0, text.length() - 1)
	for i in range(text.length()):
		var w: float = font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		glyph.append(w)
		cells.append(cell if text[i].is_valid_int() else w)
		total_width += cells[i]
	var cursor_x: float = anchor.x - total_width if align_right else anchor.x
	var y: float = anchor.y + font_size * DIGIT_BASELINE_FROM_CENTER_FRAC
	var out := PackedVector2Array()
	for i in range(text.length()):
		out.append(Vector2(cursor_x + (cells[i] - glyph[i]) * 0.5, y))
		cursor_x += cells[i] + extra_spacing
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
	var text: String = ScoreFormat.compact(score)
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
	var text: String = ScoreFormat.compact(_best_for(current_mode))
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
