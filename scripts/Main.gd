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

# Three planned game concepts sharing this same tap/gate mechanic, picked at
# the mode-select screen (see State.MODE_SELECT/_apply_mode below): SKY (red
# bird + sky gate, flag quiz), JUNGLE (green dragon + jungle gate, math quiz
# — not built yet, flag quiz stands in), OCEAN (blue shark + ocean gate, quiz
# type undecided — flag quiz stands in). ThemeMotion is the gate-pass
# themed-object particle's motion (see the FX const block further down) —
# it varies per concept the same way the character/gate art does.
enum Mode { SKY, JUNGLE, OCEAN, DREAM }
enum ThemeMotion { SCATTER, FLUTTER, RISE_SWAY }

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
const QUIZ_BOX_GAP := 10.0           # score box bottom edge -> quiz box top edge
# Pause/mute are scaled so their height matches the score box's exactly,
# which is what makes the top row read as one flush band rather than three
# loosely stacked pieces. Derived from the art rather than hard-coded, so it
# still holds if the sheet is redrawn — see _hud_button_mult. This is a
# further nudge on top of that: >1 makes the buttons overhang the row.
const HUD_BUTTON_EXTRA := 1.0
# The buttons are hung off the score box's bottom edge rather than centred on
# it. Aligning the *rects* would not do it: the slicer pads every canvas to
# make the panel interiors line up across modes, so the painted art stops
# short of the canvas bottom by a different amount in each mode and each
# piece. These are where the art actually ends, as a fraction of canvas
# height, measured off the sliced PNGs — indexed by Mode.
const MODE_SCORE_BOX_ART_BOTTOM_FRAC := [0.9778, 1.0000, 0.9926, 0.9778]
const MODE_HUD_BUTTON_ART_BOTTOM_FRAC := [0.9908, 1.0000, 0.9908, 0.9908]
const HUD_BUTTON_Y_OFFSET := 0.0     # nudge both buttons down (+) or up (-) from that alignment
# Stretches the quiz box taller than its art's aspect. The box already spans
# the full screen width, so it cannot grow taller proportionally — anything
# above 1.0 scales the art vertically only, which ovalises the rounded caps
# and stretches the painted "QUIZ" letters. 1.0 = untouched art.
# The quiz TEXT does not grow with it; see QUIZ_TEXT_*_FONT_FRAC.
const QUIZ_BOX_HEIGHT_STRETCH := 1.25
# Canvas sizes the slicer produced — see tools/slice_hud_sheet_v5.gd, which
# prints them. Used for layout maths and as the aspect fallback when a
# texture is missing; the real texture's size wins when it is loaded.
const SCORE_BOX_SRC := Vector2(937.0, 135.0)
const QUIZ_BOX_SRC := Vector2(1190.0, 117.0)
const HUD_BUTTON_SRC := Vector2(117.0, 109.0)
const QUIZ_BOX_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const QUIZ_BOX_CORNER_RADIUS := 12.0
# Blank writing area inside the quiz box art, right of the painted "QUIZ"
# label. Measured off the shared crop canvas (see MODE_QUIZ_BOX_PATH), so
# one set of fractions covers all three modes.
const QUIZ_TEXT_LEFT_FRAC := 0.1588       # of width — inner edge of the "QUIZ" label pill
const QUIZ_TEXT_RIGHT_FRAC := 0.9832      # of width — inner right edge of the frame
const QUIZ_TEXT_SIDE_PAD_FRAC := 0.020    # of width — keeps text off both edges
const QUIZ_TEXT_CENTER_Y_FRAC := 0.5085
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
const GATE_ZONE_TOP_BUFFER := 0.0    # extra gap beyond the quiz box's bottom edge, if ever wanted again

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
	"res://assets/gates/gate_ring/",  # DREAM — placeholder, reusing SKY art
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
const GATE_BASE_CANVAS_SIZE := 512.0
const GATE_BASE_TOP_LOCAL_Y := 112.0
const GATE_BASE_OVERLAP_LOCAL := 78.0
const GATE_BASE_SCALE_MULTIPLIER := 0.62  # shrinks the drawn base independently of the ring's own size
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
const GATE_FLAG_CARD_COLOR := Color(0.96, 0.90, 0.78)  # cream, matching the panel/score/quiz-box family's tone — fills a non-3:2 flag's letterbox padding

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
	"res://assets/gates/flag_panel/gate_panel.png",
	"res://assets/gates/flag_panel/gate_panel_jungle.png",
	"res://assets/gates/flag_panel/gate_panel_ocean.png",
	"res://assets/gates/flag_panel/gate_panel.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_GATE_FLAG_PANEL_WINDOW_CENTER_LOCAL := [Vector2(253.0, 473.0), Vector2(254.0, 508.5), Vector2(250.0, 497.5), Vector2(253.0, 473.0)]
const MODE_GATE_FLAG_PANEL_WINDOW_WIDTH_LOCAL := [265.0, 313.0, 277.0, 265.0]
# Flags are fit by width only (see _draw_gate_answer_box) — every panel's
# window is close enough to the flags' own fixed 3:2 that the sub-pixel
# height mismatch is invisible. JUNGLE's math-quiz number instead has no
# fixed aspect of its own, so it fits both width AND height exactly to
# each panel's real window — this array is what that needs.
const MODE_GATE_FLAG_PANEL_WINDOW_HEIGHT_LOCAL := [173.0, 186.0, 180.0, 173.0]

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
# Per-mode single-image scrolling background (see current_mode/_apply_mode/
# _draw()). One painted scene per mode, scaled to fill the view height and
# tiled horizontally. Falls back to the old mountains/sparkle/castle/
# cloud_mid layers below for any mode without a dedicated image yet (empty
# path here, or the file just doesn't exist on disk) — see bg_texture's
# null-check in _draw()/_process().
# ============================================================
const MODE_BG_TEXTURE_PATH := [
	# _blur variants — a pre-blurred copy of the same art (no runtime blur
	# shader in this custom-draw setup), so the background reads as soft/
	# out-of-focus instead of competing for detail with the gate/character.
	"res://assets/backgrounds/sky_world/background_single_blur.png",
	"res://assets/backgrounds/jungle_world/background_single_blur.png",
	"res://assets/backgrounds/ocean_world/background_single_blur.png",
	"res://assets/backgrounds/sky_world/background_single_blur.png",  # DREAM — placeholder, reusing SKY art
]

@export_group("Sky Background")
@export_range(0.0, 2.0, 0.01) var bg_speed_ratio: float = 0.15  # fraction of GATE_SPEED
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
const MODE_PARTICLE_DIR := [
	"res://assets/backgrounds/sky_world/particles/",
	"res://assets/backgrounds/jungle_world/particles/",
	"res://assets/backgrounds/ocean_world/particles/",
	"res://assets/backgrounds/sky_world/particles/",  # DREAM — placeholder, reusing SKY art
]
const MODE_PARTICLE_PREFIX := ["light", "leaf", "bubble", "light"]
const MODE_PARTICLE_COUNT := [16, 24, 16, 16]  # light_01-16.png / leaf_01-24.png / bubble_01-16.png

@export_group("Ambient Particles")
@export_range(0, 40, 1) var particle_count: int = 8
@export var particle_draw_size_range: Vector2 = Vector2(34.0, 58.0)  # final on-screen px, independent of the source image's own resolution
@export_range(0.0, 1.0, 0.01) var particle_alpha_max: float = 0.8
@export var particle_twinkle_duration_range: Vector2 = Vector2(1.5, 3.5)  # SKY only — one full fade in -> out cycle
@export_range(5.0, 120.0, 1.0) var particle_fall_speed: float = 35.0      # JUNGLE only
@export var particle_flutter_amplitude_range: Vector2 = Vector2(10.0, 25.0)  # JUNGLE only — side-to-side sway width
@export var particle_flutter_freq_range: Vector2 = Vector2(0.4, 0.9)         # JUNGLE only — sway speed, Hz
@export_range(5.0, 120.0, 1.0) var particle_rise_speed: float = 30.0      # OCEAN only
@export var particle_sway_amplitude_range: Vector2 = Vector2(8.0, 18.0)   # OCEAN only
@export var particle_sway_freq_range: Vector2 = Vector2(0.3, 0.7)         # OCEAN only

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

# 3. Three-layer particle burst, all sourced from a per-concept FX sprite
# sheet (pre-colored art, no runtime hue tinting): big/immediate, a themed
# object (wings for sky, leaves for jungle, bubbles for ocean)/immediate,
# then small/delayed. Each concept's folder holds the same fx_big_N /
# fx_theme_N / fx_small_N filenames (small-particle COUNT varies per sheet —
# sky 7, ocean 8, jungle 9 — _apply_mode's loader just loads however many
# exist). Indexed by Mode, same convention as MODE_CHARACTER_DIR/MODE_GATE_DIR.
#
# Unlike character/gate art, the themed-object layer's MOTION also differs
# per concept (wings scatter, leaves flutter, bubbles rise) — not just its
# art — so MODE_FX_THEME_MOTION is swapped alongside MODE_FX_DIR.
const MODE_FX_DIR := [
	"res://assets/fx/sky/",
	"res://assets/fx/jungle/",
	"res://assets/fx/ocean/",
	"res://assets/fx/sky/",  # DREAM — placeholder, reusing SKY art
]
const MODE_FX_THEME_MOTION := [ThemeMotion.SCATTER, ThemeMotion.FLUTTER, ThemeMotion.RISE_SWAY, ThemeMotion.SCATTER]
const FX_SMALL_PARTICLE_MAX_COUNT := 9  # highest count across all 3 concepts' sheets — _apply_mode's loader tries fx_small_1..N and keeps whichever exist
const FX_SPARK_BURST_A_COUNT_RANGE := Vector2i(6, 9)        # big, at 0ms
const FX_SPARK_BURST_A_SCALE_RANGE := Vector2(0.45, 0.75)
const FX_SPARK_BURST_B_COUNT_RANGE := Vector2i(18, 26)      # small, delayed
const FX_SPARK_BURST_B_SCALE_RANGE := Vector2(0.9, 1.4)
const FX_SPARK_BURST_B_DELAY_RANGE := Vector2(0.04, 0.06)
const FX_SPARK_THEME_COUNT_RANGE := Vector2i(5, 7)          # themed object, at 0ms alongside burst A
const FX_SPARK_THEME_SCALE_RANGE := Vector2(0.7, 1.0)       # visible but not oversized — clarity comes from the hold-fraction/modulate below, not sheer size
const FX_SPARK_THEME_SPEED_RANGE := Vector2(70.0, 140.0)    # SCATTER/FLUTTER only — RISE_SWAY uses FX_RISE_SPEED_RANGE instead
const FX_SPARK_THEME_LIFETIME_RANGE := Vector2(0.55, 0.85)  # SCATTER/FLUTTER only — RISE_SWAY uses FX_RISE_LIFETIME_RANGE instead
const FX_SPARK_THEME_SPAWN_RADIUS := 65.0  # starts just outside the character's silhouette (PLAYER_VISUAL_SIZE half ~50px + happy-pop bounce margin), so the themed object never spawns on top of the face
const FX_SPARK_THEME_HOLD_FRACTION := 0.55  # stays at full opacity for this fraction of its lifetime, then fades — vs. sparks' immediate linear fade
const FX_SPARK_THEME_MODULATE := Color(1.35, 1.3, 1.15, 1.0)  # warm overexpose so the themed object reads clearly through the sparkle clutter
# FLUTTER (jungle leaves): burst outward like SCATTER, but tumbling + swaying.
const FX_FLUTTER_ANGULAR_VELOCITY_RANGE := Vector2(-7.0, 7.0)  # rad/s, random sign
const FX_FLUTTER_WOBBLE_AMPLITUDE_RANGE := Vector2(8.0, 18.0)  # px, side-to-side sway perpendicular to travel direction
const FX_FLUTTER_WOBBLE_FREQ_RANGE := Vector2(2.5, 4.5)        # Hz
# RISE_SWAY (ocean bubbles): drift upward in a narrow cone instead of bursting
# outward in every direction, gently swaying, much slower/longer-lived.
const FX_RISE_CONE_HALF_ANGLE := 0.61  # ~35 degrees either side of straight up
const FX_RISE_SPEED_RANGE := Vector2(35.0, 65.0)
const FX_RISE_LIFETIME_RANGE := Vector2(0.9, 1.3)
const FX_RISE_WOBBLE_AMPLITUDE_RANGE := Vector2(6.0, 14.0)
const FX_RISE_WOBBLE_FREQ_RANGE := Vector2(1.5, 2.5)  # slower bob than the jungle flutter
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
# Character trail — a few tiny particles shed behind the character,
# marking the path it just flew.
#
# The thing that makes this work: PLAYER_X never moves, so a particle
# parked at the character's tail would just pile into a vertical column.
# Each one instead travels left with the world at the current scroll
# speed, which is what sells it as being *left behind*. It also means a
# gate pass's speed boost stretches the trail out for free — see
# _gate_speed_boost_multiplier.
#
# Deliberately sparse: the character is small and the quiz gate is what
# the player actually has to read, so a steady plume would just dirty the
# screen. The baseline holds 1-3 tiny particles alive at a time, and the
# only time it thickens is the instant of a tap (see _spawn_trail_burst,
# called from the flap handler) — which doubles as tactile feedback for
# the input.
#
# Whole feature = these consts + trail_textures/trail_particles/
# trail_spawn_timer + _update_bird_trail/_spawn_trail_particle/
# _spawn_trail_burst/_draw_bird_trail + their four call sites. Delete
# those to remove it.
# ============================================================
const TRAIL_ENABLED_PER_MODE := [true, true, true, true]  # SKY, JUNGLE, OCEAN, DREAM
const TRAIL_SPAWN_INTERVAL := 0.19           # seconds between baseline particles — with TRAIL_LIFETIME_RANGE this keeps ~3-4 alive
const TRAIL_TAP_BURST_RANGE := Vector2i(4, 7)  # extra particles thrown off at the moment of a tap
const TRAIL_TAP_BURST_SIZE_SCALE := 1.55       # burst particles are drawn larger than the baseline ones, so the tap reads as a puff and not just "more specks"
const TRAIL_ORIGIN_FRAC := Vector2(-0.30, 0.10)  # spawn point as a fraction of PLAYER_VISUAL_SIZE from the character's center
const TRAIL_ORIGIN_JITTER := 6.0             # px of random scatter around that point
const TRAIL_LIFETIME_RANGE := Vector2(0.50, 0.80)
# Longest edge in px, per mode. Small on purpose (see the header), but not
# uniform: SKY’s gold sparkles pop off blue sky at almost any size, while
# JUNGLE and OCEAN are drawing their own colour on top of a background of
# that same colour and need a little more mass to read at all.
const TRAIL_SIZE_RANGE_PER_MODE := [Vector2(5.0, 10.0), Vector2(7.0, 13.0), Vector2(7.0, 13.0), Vector2(5.0, 10.0)]
const TRAIL_DRIFT_Y_RANGE := Vector2(-10.0, 10.0)  # px/s of random vertical wander, on top of the per-mode drift below
const TRAIL_INHERIT_VEL_Y := 0.08            # how much of player_vel each particle carries off
const TRAIL_SHRINK := 0.45                   # fraction of its size a particle loses over its life
const TRAIL_ALPHA := 1.0
const TRAIL_OFFSCREEN_MARGIN := 20.0          # px past the left edge before a particle is dropped
const TRAIL_SPIN_RANGE := Vector2(-1.6, 1.6) # radians/s
# Per-mode vertical drift, px/s, negative = upward. OCEAN is the reason
# this exists: bubbles that rise out of the spawn point while the world
# pushes them left read as a shark actually swimming forward. SKY drifts
# up a hair so sparkles hang; JUNGLE settles, like shaken-loose leaves.
const TRAIL_DRIFT_Y_PER_MODE := [-4.0, 7.0, -26.0, -4.0]
# Which fx_small_N.png each mode's trail draws from (see the contact sheets
# in assets/fx/<mode>/). Every set's last few entries are solid squares —
# fine as confetti inside a gate burst, but alone in a slow trail they just
# read as blocks — so only the sparkle/blob shapes are listed. SKY pairs
# its white-blue blob (4) with the gold sparkles (1, 3) as the "light
# specks"; OCEAN takes its bubble blob (4) plus the water-blue sparkles.
const TRAIL_TEXTURE_NUMBERS_PER_MODE := [
	[4, 1, 3],
	[4, 3, 5],
	[4, 5, 1],
	[4, 1, 3],  # DREAM — placeholder, reusing SKY art
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

# Score pop — bigger and longer-lived so the +score reads clearly.
const FX_SCORE_POP_DURATION := 0.7
const FX_SCORE_POP_RISE := 34.0
const FX_SCORE_POP_COLOR := Color(1.0, 0.93, 0.6)
const FX_SCORE_POP_FONT_SIZE := 26
const FX_SCORE_POP_OFFSET := Vector2(0.0, -18.0)

# 9. Audio hooks — each its own AudioStreamPlayer so they can overlap.
# Whoosh is still an unfilled placeholder (drop a file at that path and it
# starts playing automatically, ResourceLoader.exists guarded). Chime plays
# on every correct gate pass (see _play_gate_success_fx); flap plays once
# per tap (see _unhandled_input).
const FX_SOUND_WHOOSH_PATH := "res://assets/audio/gate_whoosh.ogg"
const FX_SOUND_CHIME_PATH := "res://assets/audio/gate_chime.wav"
const FX_SOUND_FLAP_PATH := "res://assets/audio/bird_flap.wav"
# Background music — starts once in _ready() and loops for the whole
# session (menu, playing, game over all keep it going, same as the
# parallax background), independent of the FX players above. Respects the
# existing mute button since AudioStreamPlayer defaults to the Master bus,
# same as every other sound here.
const BGM_MAIN_PATH := "res://assets/audio/bgm_main.wav"
# Countdown beat sounds — one played the instant the READY image appears,
# the other the instant it swaps to START (see _start_countdown and
# _update_countdown).
const COUNTDOWN_READY_SOUND_PATH := "res://assets/audio/countdown_ready.mp3"
const COUNTDOWN_START_SOUND_PATH := "res://assets/audio/countdown_start.mp3"
# Failure sound — wrong gate, wall collision, or falling off the bottom of
# the screen all funnel through the single _game_over() below, so this is
# the one place it needs to be wired. BGM is stopped (not just paused) at
# the same time — see _game_over — pending a separate failure-BGM track
# later; _start_countdown resumes bgm_player for the next run.
const FX_SOUND_GAMEOVER_PATH := "res://assets/audio/gameover.wav"


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

enum State { MODE_SELECT, READY, COUNTDOWN, PLAYING, GAMEOVER }

var state: int = State.READY

# Tap-to-pause (PLAYING only — see pause_button visibility in _process).
# Only gates the gameplay-affecting update calls in _process; background
# parallax keeps drifting while paused, same as it does on every other
# non-PLAYING screen.
var paused: bool = false

# "READY" -> "START" pop-in shown before every *retry* (post-onboarding).
# The very first play (from the READY/onboarding panel) skips straight to
# PLAYING and never touches this — see _on_play_pressed vs _on_restart_pressed.
enum CountdownPhase { READY_TEXT, START_TEXT }
var countdown_phase: int = CountdownPhase.READY_TEXT
var countdown_timer: float = 0.0
const COUNTDOWN_READY_DURATION := 0.9
const COUNTDOWN_START_DURATION := 0.4

# "READY" / "START" countdown pop art and the "TRY AGAIN" game-over word, all
# cut from one hand-authored sheet (assets/ui_assets/ready_start_sheet_v2.png)
# by tools/slice_ready_sheet.gd. Ready/Start are drawn in place of the old
# plain-text draw_string call (see the State.COUNTDOWN block in _draw()) and
# fall back to that text if a file is missing; TRY AGAIN is a TextureRect in
# the game-over panel, replacing what used to be a red "GAME OVER" label.
#
# The slicer centres every mode's art on one canvas shared across the three,
# which is why there are no per-mode nudge offsets here any more: this used to
# carry MODE_READY_OFFSET_LOCAL / MODE_START_OFFSET_LOCAL to shove each mode's
# differently-sized crop back into place, and centring by construction makes
# that unnecessary.
const MODE_READY_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/Ready.png",
	"res://assets/ui_assets/jungle/Ready.png",
	"res://assets/ui_assets/ocean/Ready.png",
	"res://assets/ui_assets/sky/Ready.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_START_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/Start.png",
	"res://assets/ui_assets/jungle/Start.png",
	"res://assets/ui_assets/ocean/Start.png",
	"res://assets/ui_assets/sky/Start.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_TRY_AGAIN_TEXTURE_PATH := [
	"res://assets/ui_assets/sky/TryAgain.png",
	"res://assets/ui_assets/jungle/TryAgain.png",
	"res://assets/ui_assets/ocean/TryAgain.png",
	"res://assets/ui_assets/sky/TryAgain.png",  # DREAM — placeholder, reusing SKY art
]
const COUNTDOWN_IMAGE_WIDTH := 330.0  # display width in px; height follows the source aspect ratio

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
	"res://assets/ui_assets/sky/pause.png",
	"res://assets/ui_assets/jungle/pause.png",
	"res://assets/ui_assets/ocean/pause.png",
	"res://assets/ui_assets/sky/pause.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_MUTE_ICON_PATH := [
	"res://assets/ui_assets/sky/mute.png",
	"res://assets/ui_assets/jungle/mute.png",
	"res://assets/ui_assets/ocean/mute.png",
	"res://assets/ui_assets/sky/mute.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_SCORE_BOX_PATH := [
	"res://assets/ui_assets/sky/score_box.png",
	"res://assets/ui_assets/jungle/score_box.png",
	"res://assets/ui_assets/ocean/score_box.png",
	"res://assets/ui_assets/sky/score_box.png",  # DREAM — placeholder, reusing SKY art
]
const MODE_QUIZ_BOX_PATH := [
	"res://assets/ui_assets/sky/quiz_box.png",
	"res://assets/ui_assets/jungle/quiz_box.png",
	"res://assets/ui_assets/ocean/quiz_box.png",
	"res://assets/ui_assets/sky/quiz_box.png",  # DREAM — placeholder, reusing SKY art
]
const HUD_CANVAS_SCRIPT_PATH := "res://scripts/HudCanvas.gd"
# Best score persistence. user:// is the per-user writable location Godot
# maps outside the project (%APPDATA%/Godot/app_userdata/<project> on
# Windows), so this survives reinstalls of the game files themselves.
# One best across all three modes, matching the single BEST slot the art has.
const SAVE_PATH := "user://savegame.cfg"
const SAVE_SECTION := "progress"
const SAVE_KEY_BEST := "best_score"
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
const SCORE_NUM_RIGHT_FRAC := 0.5379      # of width — the divider; the score is right-aligned to just inside it
const SCORE_NUMBER_FONT_FRAC := 0.397     # of height — 0.286 ink / 0.72
const SCORE_NUMBER_MID_Y_FRAC := 0.548    # of height — matches the painted "SCORE"
# BEST is left-aligned instead, starting just past its label, so the number
# sits beside the word rather than stranded at the far edge of the half.
const BEST_NUM_LEFT_FRAC := 0.702         # of width — label ends at 0.6734, plus a gap so the number does not crowd it
const BEST_NUMBER_FONT_FRAC := 0.336      # of height — 0.242 ink / 0.72
const BEST_NUMBER_MID_Y_FRAC := 0.696     # of height — matches the painted "BEST"
const SCORE_NUMBER_RIGHT_INSET_FRAC := 0.015  # of box width — keeps the ones digit off the divider
const SCORE_NUMBER_DIGIT_SPACING := 1.0     # extra px between digit cells, on top of the tabular cell width
# Baseline offset from a digit row's visual center, as a fraction of the
# font size — see _draw_spaced_digits. Measured by rendering
# "0123456789" at a known baseline and reading the ink box back: Fredoka's
# figures run 0.700 em above the baseline to 0.020 em below at this weight,
# putting their visual middle 0.34 em up. (Mulmaru's sat at 0.38, which is
# why this changed with the font.)
const DIGIT_BASELINE_FROM_CENTER_FRAC := 0.34

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

var score: int = 0
var combo: int = 0
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
var active_flag_panel_window_center := Vector2.ZERO
var active_flag_panel_window_width: float = 0.0
var active_flag_panel_window_height: float = 0.0
var active_theme_motion: int = ThemeMotion.SCATTER

var flap_frames: Array[Texture2D] = []
var flap_frame_index: int = 0
var flap_timer: float = 0.0
var happy_face_texture: Texture2D
var happy_flap_elapsed: float = -1.0  # -1 = inactive; set to 0 on every gate pass, see _play_gate_success_fx
var sad_face_texture: Texture2D
var ready_texture: Texture2D
var start_texture: Texture2D
var best_score: int = 0   # loaded from SAVE_PATH in _ready, written on game over
var score_box_texture: Texture2D
var score_font: Font
var quiz_box_texture: Texture2D
# Child canvas the top HUD is drawn on, so it can use a texture filter of
# its own (see scripts/HudCanvas.gd). Created in _ready.
var hud_canvas: Node2D
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

# Per-mode single-image background state — loaded in _apply_mode, see the const/export block above.
var bg_texture: Texture2D
var bg_scroll_x: float = 0.0  # ever-increasing distance scrolled; wrapped with fposmod at draw time

# Ambient background particle state (see the const/export block above).
var particle_textures: Array[Texture2D] = []
var ambient_particle_list: Array = []  # fixed pool, each: {texture, base_x, y, size, wobble_amp, wobble_freq, phase, elapsed, duration}

# Gate-pass FX state (see the const block above for tunables).
var fx_big_particle_textures: Array[Texture2D] = []
var fx_theme_object_textures: Array[Texture2D] = []
var fx_small_particle_textures: Array[Texture2D] = []
var fx_sparks: Array = []            # each: {pos, vel, scale, rotation, lifetime, elapsed, texture}
var fx_speed_lines: Array = []       # each: {y_offset, length, elapsed, color}
var trail_textures: Array[Texture2D] = []   # sparkle subset of the mode's fx_small set, see TRAIL_TEXTURE_NUMBERS
var trail_particles: Array = []      # each: {pos, drift_y, size, rotation, spin, lifetime, elapsed, texture} — see the TRAIL_* consts
var trail_spawn_timer: float = 0.0
var fx_score_pops: Array = []        # each: {pos, elapsed}
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
var bgm_player: AudioStreamPlayer
var fx_sound_countdown_ready: AudioStreamPlayer
var fx_sound_countdown_start: AudioStreamPlayer
var fx_sound_gameover: AudioStreamPlayer

@onready var mode_select_panel: Control = $UI/ModeSelectPanel
@onready var sky_mode_button: Button = $UI/ModeSelectPanel/SkyModeButton
@onready var jungle_mode_button: Button = $UI/ModeSelectPanel/JungleModeButton
@onready var ocean_mode_button: Button = $UI/ModeSelectPanel/OceanModeButton
@onready var dream_mode_button: Button = $UI/ModeSelectPanel/DreamModeButton
@onready var ready_panel: Control = $UI/ReadyPanel
@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var final_score_label: Label = $UI/GameOverPanel/FinalScoreLabel
@onready var try_again_image: TextureRect = $UI/GameOverPanel/TryAgainImage
@onready var play_button: Button = $UI/ReadyPanel/PlayButton
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton
@onready var pause_button: Button = $UI/PauseButton
@onready var mute_button: Button = $UI/MuteButton
@onready var pause_panel: Control = $UI/PausePanel
@onready var resume_button: Button = $UI/PausePanel/ResumeButton


func _ready() -> void:
	# Filter for everything Main draws: background, gates, character, flags,
	# particles. draw_texture_rect has no per-call filter option, so it has to
	# be set on the CanvasItem itself — which is also why the HUD needs its
	# own node to differ. See SMOOTH_WORLD_FILTER to revert this.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if SMOOTH_WORLD_FILTER else CanvasItem.TEXTURE_FILTER_NEAREST
	# ...except the top HUD, whose painted frames are minified hard enough
	# that nearest breaks their outlines. It gets its own canvas with linear
	# + mipmap filtering — see scripts/HudCanvas.gd for the why.
	hud_canvas = Node2D.new()
	hud_canvas.name = "HudCanvas"
	hud_canvas.set_script(load(HUD_CANVAS_SCRIPT_PATH))
	hud_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud_canvas.main = self
	add_child(hud_canvas)
	_load_best_score()
	_load_flags_data()
	# The four HUD pieces are all per-mode now and get loaded in _apply_mode;
	# only the parts that never change per mode are set up here.
	pause_button.text = ""
	pause_button.expand_icon = true
	mute_button.text = ""
	mute_button.expand_icon = true
	_layout_hud_buttons()
	var base_font: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(COMBO_FONT_PATH):
		base_font = load(COMBO_FONT_PATH)
	# Real weight axis rather than the faux-bold this used to need: Mulmaru
	# shipped a single weight, Fredoka carries 300-700.
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	combo_font = _weighted_font(base_font, wght, TEXT_FONT_WEIGHT)
	score_font = _weighted_font(base_font, wght, SCORE_FONT_WEIGHT)
	for path in MOUNTAIN_TEXTURE_PATHS:
		mountain_textures.append(load(path))
	for path in BG_SPARKLE_TEXTURE_PATHS:
		bg_sparkle_textures.append(load(path))
	if ResourceLoader.exists(CASTLE_TEXTURE_PATH):
		castle_texture = load(CASTLE_TEXTURE_PATH)
	for path in CLOUD_MID_TEXTURE_PATHS:
		cloud_mid_textures.append(load(path))
	var view_size := get_viewport_rect().size
	_init_mountains(view_size)
	_init_bg_sparkles(view_size)
	_init_cloud_mid(view_size)
	_apply_mode(current_mode)  # loads a valid default (SKY) so nothing is empty before mode-select runs _apply_mode again
	fx_sound_whoosh = AudioStreamPlayer.new()
	add_child(fx_sound_whoosh)
	if ResourceLoader.exists(FX_SOUND_WHOOSH_PATH):
		fx_sound_whoosh.stream = load(FX_SOUND_WHOOSH_PATH)
	fx_sound_chime = AudioStreamPlayer.new()
	add_child(fx_sound_chime)
	if ResourceLoader.exists(FX_SOUND_CHIME_PATH):
		fx_sound_chime.stream = load(FX_SOUND_CHIME_PATH)
	fx_sound_flap = AudioStreamPlayer.new()
	add_child(fx_sound_flap)
	if ResourceLoader.exists(FX_SOUND_FLAP_PATH):
		fx_sound_flap.stream = load(FX_SOUND_FLAP_PATH)
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	if ResourceLoader.exists(BGM_MAIN_PATH):
		bgm_player.stream = load(BGM_MAIN_PATH)
		bgm_player.finished.connect(bgm_player.play)  # manual loop — simpler/more reliable than fiddling with AudioStreamWAV's own loop points
		bgm_player.play()
	fx_sound_countdown_ready = AudioStreamPlayer.new()
	add_child(fx_sound_countdown_ready)
	if ResourceLoader.exists(COUNTDOWN_READY_SOUND_PATH):
		fx_sound_countdown_ready.stream = load(COUNTDOWN_READY_SOUND_PATH)
	fx_sound_countdown_start = AudioStreamPlayer.new()
	add_child(fx_sound_countdown_start)
	if ResourceLoader.exists(COUNTDOWN_START_SOUND_PATH):
		fx_sound_countdown_start.stream = load(COUNTDOWN_START_SOUND_PATH)
	fx_sound_gameover = AudioStreamPlayer.new()
	add_child(fx_sound_gameover)
	if ResourceLoader.exists(FX_SOUND_GAMEOVER_PATH):
		fx_sound_gameover.stream = load(FX_SOUND_GAMEOVER_PATH)
	sky_mode_button.pressed.connect(_on_mode_selected.bind(Mode.SKY))
	jungle_mode_button.pressed.connect(_on_mode_selected.bind(Mode.JUNGLE))
	ocean_mode_button.pressed.connect(_on_mode_selected.bind(Mode.OCEAN))
	dream_mode_button.pressed.connect(_on_mode_selected.bind(Mode.DREAM))
	play_button.pressed.connect(_on_play_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	mute_button.pressed.connect(_on_mute_pressed)
	# pivot_offset is set in _layout_hud_buttons instead — it resizes the
	# buttons deferred, so reading .size here would still give the scene's
	# pre-layout value and the press animation would scale off-center.
	pause_button.button_down.connect(_animate_button_press.bind(pause_button))
	pause_button.button_up.connect(_animate_button_release.bind(pause_button))
	mute_button.button_down.connect(_animate_button_press.bind(mute_button))
	mute_button.button_up.connect(_animate_button_release.bind(mute_button))
	_reset_game()
	_set_state(State.MODE_SELECT)


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
		seg.x -= MOUNTAIN_SPEED_RATIO * GATE_SPEED * delta
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
		s.x -= BG_SPARKLE_SPEED_RATIO * GATE_SPEED * delta
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
		castle_x -= CASTLE_SPEED_RATIO * GATE_SPEED * delta
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
		c.x -= c.speed * delta
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


# ---- Per-mode single-image background (see _apply_mode/_draw()) ----
# One painted scene, scaled to exactly fill the view height and tiled
# horizontally — same infinite-scroll technique as before, just a single
# layer now instead of three.

func _update_sky_background(delta: float) -> void:
	bg_scroll_x += bg_speed_ratio * GATE_SPEED * delta


func _draw_sky_background(view_size: Vector2) -> void:
	if bg_texture == null:
		return
	var tex_size := Vector2(bg_texture.get_width(), bg_texture.get_height())
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
	var x: float = -fposmod(bg_scroll_x, tile_w)
	while x < view_size.x:
		draw_texture_rect(bg_texture, Rect2(Vector2(x, 0.0), Vector2(tile_w, view_size.y)), false, tint)
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
		"duration": 1.0,
	}
	match current_mode:
		Mode.SKY:
			d.y = view_size.y * randf_range(0.04, 0.32)  # upper sky, above the gate zone
			d.duration = randf_range(particle_twinkle_duration_range.x, particle_twinkle_duration_range.y)
			d.elapsed = randf_range(0.0, d.duration) if stagger_start else 0.0
		Mode.JUNGLE:
			# Staggered across the whole fall range on init so they don't all
			# start clustered at the top; recycled particles start exactly at
			# the top edge instead, same as every other pool in this file.
			d.y = randf_range(-view_size.y * 0.3, view_size.y) if stagger_start else -size
			d.wobble_amp = randf_range(particle_flutter_amplitude_range.x, particle_flutter_amplitude_range.y)
			d.wobble_freq = randf_range(particle_flutter_freq_range.x, particle_flutter_freq_range.y)
		Mode.OCEAN:
			d.y = randf_range(0.0, view_size.y * 1.3) if stagger_start else view_size.y + size
			d.wobble_amp = randf_range(particle_sway_amplitude_range.x, particle_sway_amplitude_range.y)
			d.wobble_freq = randf_range(particle_sway_freq_range.x, particle_sway_freq_range.y)
	return d


func _init_ambient_particles(view_size: Vector2) -> void:
	ambient_particle_list.clear()
	for i in range(particle_count):
		ambient_particle_list.append(_make_ambient_particle(view_size, true))


func _update_ambient_particles(delta: float, view_size: Vector2) -> void:
	if particle_textures.is_empty():
		return
	for p in ambient_particle_list:
		p.elapsed += delta
		match current_mode:
			Mode.SKY:
				if p.elapsed >= p.duration:
					var fresh: Dictionary = _make_ambient_particle(view_size, false)
					for key in fresh:
						p[key] = fresh[key]
			Mode.JUNGLE:
				p.y += particle_fall_speed * delta
				if p.y - p.size > view_size.y:
					var fresh: Dictionary = _make_ambient_particle(view_size, false)
					for key in fresh:
						p[key] = fresh[key]
			Mode.OCEAN:
				p.y -= particle_rise_speed * delta
				if p.y + p.size < 0.0:
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
		var x: float = p.base_x
		var alpha: float = particle_alpha_max
		if current_mode == Mode.SKY:
			var t: float = p.elapsed / p.duration
			alpha = particle_alpha_max * sin(PI * clampf(t, 0.0, 1.0))  # fade in -> peak -> fade out
		else:
			x += sin(p.elapsed * p.wobble_freq * TAU + p.phase) * p.wobble_amp
		if alpha <= 0.001:
			continue
		draw_texture_rect(texture, Rect2(Vector2(x - size.x * 0.5, p.y - size.y * 0.5), size), false, Color(1.0, 1.0, 1.0, alpha))


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
	return ring_bottom_from_center + base_top_from_center - GATE_BASE_OVERLAP_LOCAL


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
	var draw_size: Vector2 = tex_size * scale_factor * GATE_BASE_SCALE_MULTIPLIER
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
	var panel_scale: float = GATE_FLAG_ICON_WIDTH / active_flag_panel_window_width
	var icon_size := Vector2(GATE_FLAG_ICON_WIDTH, GATE_FLAG_ICON_HEIGHT)
	if is_text:
		icon_size.y = active_flag_panel_window_height * panel_scale
	var half_h: float = icon_size.y * 0.5
	var center_y: float = maxf(zone_top - half_h - GATE_FLAG_GAP_ABOVE_ZONE, _gate_zone_top(view_size) + half_h)
	var icon_top_left := Vector2(center_x, center_y) - icon_size * 0.5

	if gate_flag_panel_texture != null:
		var panel_tex_size := Vector2(gate_flag_panel_texture.get_width(), gate_flag_panel_texture.get_height())
		var panel_draw_size: Vector2 = panel_tex_size * panel_scale
		var window_offset_from_center: Vector2 = active_flag_panel_window_center - panel_tex_size * 0.5
		var panel_center: Vector2 = Vector2(center_x, center_y) - window_offset_from_center * panel_scale
		draw_texture_rect(gate_flag_panel_texture, Rect2(panel_center - panel_draw_size * 0.5, panel_draw_size), false)

	# Fill card behind the flag/number itself — flags are letterboxed to a
	# unified 3:2 (see assets/flags/flags_data.json), so non-3:2 flags
	# (Switzerland's true square, etc.) have real transparent padding baked
	# into the PNG. This shows through as a solid color instead of
	# see-through gaps, without touching any of the 193 flag images
	# themselves — and doubles as the number's backdrop for JUNGLE.
	draw_rect(Rect2(icon_top_left, icon_size), GATE_FLAG_CARD_COLOR)
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
	if state != State.PLAYING or paused:
		return
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		tapped = true
	if tapped:
		player_vel = flap_velocity
		_spawn_trail_burst()
		if fx_sound_flap.stream != null:
			fx_sound_flap.play()


func _process(delta: float) -> void:
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
	var gate_speed: float = GATE_SPEED * _gate_speed_boost_multiplier()

	for g in gates:
		g.x -= gate_speed * delta
		if not g.resolved and g.x <= PLAYER_X and g.x + GATE_WIDTH >= PLAYER_X:
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
		score += 10
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
	# above, sampled in _draw()) + big spark burst + themed-object burst
	# (wings/leaves/bubbles, motion per active_theme_motion) + both sound hooks.
	_spawn_impact_flash(gate_center)
	_spawn_spark_burst(gate_center, FX_SPARK_BURST_A_COUNT_RANGE, FX_SPARK_BURST_A_SCALE_RANGE, fx_big_particle_textures)
	# Themed object bursts from a tight point at the gate's own center — see
	# active_theme_motion for how each concept then moves from there.
	_spawn_spark_burst(gate_center, FX_SPARK_THEME_COUNT_RANGE, FX_SPARK_THEME_SCALE_RANGE, fx_theme_object_textures, FX_SPARK_THEME_SPEED_RANGE, FX_SPARK_THEME_LIFETIME_RANGE, true, FX_SPARK_THEME_SPAWN_RADIUS)
	# 30-50ms: small spark burst + speed streaks, fired together once this
	# pending entry's delay elapses (see _update_fx).
	fx_pending_bursts.append({
		"delay": randf_range(FX_SPARK_BURST_B_DELAY_RANGE.x, FX_SPARK_BURST_B_DELAY_RANGE.y),
		"gate_center": gate_center,
	})
	_spawn_score_pop(gate_center)
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


func _spawn_spark_burst(gate_center: Vector2, count_range: Vector2i, scale_range: Vector2, texture_pool: Array[Texture2D], speed_range: Vector2 = FX_SPARK_SPEED_RANGE, lifetime_range: Vector2 = FX_SPARK_LIFETIME_RANGE, is_theme: bool = false, spawn_radius_override: float = -1.0) -> void:
	if texture_pool.is_empty():
		return
	var ring_radius: float
	if spawn_radius_override >= 0.0:
		# Small burst-point spread around a fixed origin (e.g. the
		# character's center) instead of the gate-frame-edge ring below.
		ring_radius = spawn_radius_override
	else:
		var frame_outer_radius: float = (GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) * 0.5
		ring_radius = frame_outer_radius + FX_SPARK_RING_MARGIN
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	var count: int = int(round(randi_range(count_range.x, count_range.y) * strength))
	# RISE_SWAY (ocean bubbles) floats far slower/longer than a burst, so it
	# overrides the caller's speed/lifetime range — SCATTER/FLUTTER use them
	# as passed in (both are bursts, just with different tumble/sway).
	var active_speed_range := speed_range
	var active_lifetime_range := lifetime_range
	if is_theme and active_theme_motion == ThemeMotion.RISE_SWAY:
		active_speed_range = FX_RISE_SPEED_RANGE
		active_lifetime_range = FX_RISE_LIFETIME_RANGE
	for i in range(count):
		var angle: float
		if is_theme and active_theme_motion == ThemeMotion.RISE_SWAY:
			# Mostly straight up (-Y), with a bit of spread either side —
			# bubbles floating, not bursting outward in every direction.
			angle = -PI * 0.5 + randf_range(-FX_RISE_CONE_HALF_ANGLE, FX_RISE_CONE_HALF_ANGLE)
		else:
			# Angled outward from gate_center (the zone center the bird just
			# passed through), starting at the ring outside the frame's own
			# edge — spreads toward the gate's outer boundary, not over the
			# bird's face/body which sits back near gate_center itself.
			angle = randf_range(0.0, TAU)
		var dir := Vector2(cos(angle), sin(angle))
		var dist: float = ring_radius * randf_range(0.9, 1.15)
		var speed: float = randf_range(active_speed_range.x, active_speed_range.y) * strength
		var texture: Texture2D = texture_pool[randi() % texture_pool.size()]
		# Themed objects tumble/sway per active_theme_motion — SCATTER (sky wings)
		# stays a rigid straight-line burst, FLUTTER (jungle leaves) tumbles
		# and sways as it bursts outward, RISE_SWAY (ocean bubbles) only
		# sways (no spin) as it drifts up. Plain sparks get zero here, so
		# their motion/draw is unaffected.
		var angular_velocity := 0.0
		var wobble_amplitude := 0.0
		var wobble_freq := 0.0
		if is_theme:
			match active_theme_motion:
				ThemeMotion.FLUTTER:
					angular_velocity = randf_range(FX_FLUTTER_ANGULAR_VELOCITY_RANGE.x, FX_FLUTTER_ANGULAR_VELOCITY_RANGE.y)
					wobble_amplitude = randf_range(FX_FLUTTER_WOBBLE_AMPLITUDE_RANGE.x, FX_FLUTTER_WOBBLE_AMPLITUDE_RANGE.y)
					wobble_freq = randf_range(FX_FLUTTER_WOBBLE_FREQ_RANGE.x, FX_FLUTTER_WOBBLE_FREQ_RANGE.y)
				ThemeMotion.RISE_SWAY:
					wobble_amplitude = randf_range(FX_RISE_WOBBLE_AMPLITUDE_RANGE.x, FX_RISE_WOBBLE_AMPLITUDE_RANGE.y)
					wobble_freq = randf_range(FX_RISE_WOBBLE_FREQ_RANGE.x, FX_RISE_WOBBLE_FREQ_RANGE.y)
				ThemeMotion.SCATTER:
					pass  # rigid straight-line burst — angular_velocity/wobble stay 0
		var wobble_phase: float = randf_range(0.0, TAU)
		fx_sparks.append({
			"pos": gate_center + dir * dist,
			"vel": dir * speed,
			"scale": randf_range(scale_range.x, scale_range.y) * clampf(strength, 0.3, 2.0),
			"rotation": randf_range(0.0, TAU),
			"lifetime": randf_range(active_lifetime_range.x, active_lifetime_range.y),
			"elapsed": 0.0,
			"texture": texture,
			"is_theme": is_theme,
			"angular_velocity": angular_velocity,
			"wobble_amplitude": wobble_amplitude,
			"wobble_freq": wobble_freq,
			"wobble_phase": wobble_phase,
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


func _spawn_score_pop(gate_center: Vector2) -> void:
	fx_score_pops.append({
		"pos": gate_center + FX_SCORE_POP_OFFSET,
		"elapsed": 0.0,
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
		_spawn_spark_burst(pos, Vector2i(particle_count, particle_count), FX_SPARK_BURST_A_SCALE_RANGE, fx_big_particle_textures)
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
		s.rotation += s.angular_velocity * delta
	fx_sparks = fx_sparks.filter(func(s): return s.elapsed < s.lifetime)

	for l in fx_speed_lines:
		l.elapsed += delta
	fx_speed_lines = fx_speed_lines.filter(func(l): return l.elapsed < FX_SPEED_LINE_DURATION)

	_update_bird_trail(delta)

	for p in fx_score_pops:
		p.elapsed += delta
	fx_score_pops = fx_score_pops.filter(func(p): return p.elapsed < FX_SCORE_POP_DURATION)

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
		_spawn_spark_burst(b.gate_center, FX_SPARK_BURST_B_COUNT_RANGE, FX_SPARK_BURST_B_SCALE_RANGE, fx_small_particle_textures)
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
	var world_dx: float = GATE_SPEED * _gate_speed_boost_multiplier() * delta
	for p in trail_particles:
		p.elapsed += delta
		p.pos.x -= world_dx          # rides the world, not the bird — see the TRAIL_* header
		p.pos.y += p.drift_y * delta
		p.rotation += p.spin * delta
	trail_particles = trail_particles.filter(func(p): return p.elapsed < p.lifetime and p.pos.x > -TRAIL_OFFSCREEN_MARGIN)

	if not _trail_active():
		return
	# Flat baseline rate — the dynamics come from the tap burst, not from
	# emission chasing the character's speed. See the header.
	trail_spawn_timer += delta
	while trail_spawn_timer >= TRAIL_SPAWN_INTERVAL:
		trail_spawn_timer -= TRAIL_SPAWN_INTERVAL
		_spawn_trail_particle()


func _trail_active() -> bool:
	return state == State.PLAYING and TRAIL_ENABLED_PER_MODE[current_mode] and not trail_textures.is_empty()


func _spawn_trail_burst() -> void:
	# Fired on tap: a short puff on top of the baseline, so the input gets a
	# visible kick without the trail ever becoming a steady stream.
	if not _trail_active():
		return
	for i in range(randi_range(TRAIL_TAP_BURST_RANGE.x, TRAIL_TAP_BURST_RANGE.y)):
		_spawn_trail_particle(TRAIL_TAP_BURST_SIZE_SCALE)


func _spawn_trail_particle(size_scale: float = 1.0) -> void:
	var size_range: Vector2 = TRAIL_SIZE_RANGE_PER_MODE[current_mode] * size_scale
	var origin := Vector2(
		PLAYER_X + PLAYER_VISUAL_SIZE.x * TRAIL_ORIGIN_FRAC.x + randf_range(-TRAIL_ORIGIN_JITTER, TRAIL_ORIGIN_JITTER),
		player_y + PLAYER_VISUAL_SIZE.y * TRAIL_ORIGIN_FRAC.y + randf_range(-TRAIL_ORIGIN_JITTER, TRAIL_ORIGIN_JITTER))
	trail_particles.append({
		"pos": origin,
		# Per-mode drift (bubbles rise, leaves settle) plus a little of the
		# character's own vertical motion, so a hard dive throws the trail
		# downward instead of leaving it hanging level.
		"drift_y": TRAIL_DRIFT_Y_PER_MODE[current_mode] + player_vel * TRAIL_INHERIT_VEL_Y + randf_range(TRAIL_DRIFT_Y_RANGE.x, TRAIL_DRIFT_Y_RANGE.y),
		"size": randf_range(size_range.x, size_range.y),
		"rotation": randf() * TAU,
		"spin": randf_range(TRAIL_SPIN_RANGE.x, TRAIL_SPIN_RANGE.y),
		"lifetime": randf_range(TRAIL_LIFETIME_RANGE.x, TRAIL_LIFETIME_RANGE.y),
		"elapsed": 0.0,
		"texture": trail_textures[randi() % trail_textures.size()],
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
		draw_set_transform(p.pos, p.rotation, Vector2.ONE)
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
	# Two passes: plain sparks first, then themed objects (wings/leaves/
	# bubbles) on top — otherwise the much larger small-particle burst (18-26
	# of them) buries the handful of themed pieces underneath it.
	for s in fx_sparks:
		if s.is_theme:
			continue
		_draw_one_spark(s)
	for s in fx_sparks:
		if not s.is_theme:
			continue
		_draw_one_spark(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_one_spark(s: Dictionary) -> void:
	var texture: Texture2D = s.texture
	if texture == null:
		return
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var t: float = s.elapsed / s.lifetime
	var draw_pos: Vector2 = s.pos
	var modulate := Color(1.0, 1.0, 1.0, 1.0 - t)  # fast fade-out
	if s.is_theme:
		# Sway perpendicular to the outward travel direction so the straight
		# radial drift reads as a flutter, not a rigid slide.
		var dir: Vector2 = (s.vel as Vector2).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var wobble: float = sin(s.elapsed * s.wobble_freq * TAU + s.wobble_phase) * s.wobble_amplitude
		draw_pos += perp * wobble
		# Full opacity for the first FX_SPARK_THEME_HOLD_FRACTION of its life,
		# then fades — unlike sparks' immediate linear fade — so wings are
		# still fully visible once the bigger, shorter-lived spark bursts
		# have already cleared out.
		var hold_alpha: float = 1.0 if t < FX_SPARK_THEME_HOLD_FRACTION \
			else clampf(1.0 - (t - FX_SPARK_THEME_HOLD_FRACTION) / (1.0 - FX_SPARK_THEME_HOLD_FRACTION), 0.0, 1.0)
		modulate = Color(FX_SPARK_THEME_MODULATE.r, FX_SPARK_THEME_MODULATE.g, FX_SPARK_THEME_MODULATE.b, hold_alpha)
	draw_set_transform(draw_pos, s.rotation, Vector2.ONE * s.scale)
	draw_texture_rect(texture, Rect2(-tex_size * 0.5, tex_size), false, modulate)


func _draw_score_pops() -> void:
	if fx_score_pops.is_empty():
		return
	var font := ThemeDB.fallback_font
	var text := "+1"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FX_SCORE_POP_FONT_SIZE)
	for p in fx_score_pops:
		var t: float = p.elapsed / FX_SCORE_POP_DURATION
		var alpha: float = 1.0 - t
		var pos: Vector2 = p.pos + Vector2(0.0, -FX_SCORE_POP_RISE * t)
		var draw_pos := Vector2(pos.x - text_size.x * 0.5, pos.y + text_size.y * 0.25)
		var outline_col := Color(COLOR_TEXT_OUTLINE.r, COLOR_TEXT_OUTLINE.g, COLOR_TEXT_OUTLINE.b, COLOR_TEXT_OUTLINE.a * alpha)
		var main_col := Color(FX_SCORE_POP_COLOR.r, FX_SCORE_POP_COLOR.g, FX_SCORE_POP_COLOR.b, alpha)
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(font, draw_pos + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, FX_SCORE_POP_FONT_SIZE, outline_col)
		draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, FX_SCORE_POP_FONT_SIZE, main_col)


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

func _load_best_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return   # no save yet — a fresh install starts at 0, not an error
	best_score = int(cfg.get_value(SAVE_SECTION, SAVE_KEY_BEST, 0))


func _save_best_score() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep anything else already stored there
	cfg.set_value(SAVE_SECTION, SAVE_KEY_BEST, best_score)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("could not write %s (error %d) — best score will not persist" % [SAVE_PATH, err])


func _game_over() -> void:
	state = State.GAMEOVER
	combo = 0  # combo is purely a run-length streak; a miss always zeroes it immediately, not just on restart
	# Only write on an actual improvement, so a run that doesn't beat the
	# record costs no disk access at all.
	if score > best_score:
		best_score = score
		_save_best_score()
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	final_score_label.text = "SCORE: %d" % score
	gameover_panel.visible = true
	bgm_player.stop()
	if fx_sound_gameover.stream != null:
		fx_sound_gameover.play()


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


func _on_mode_selected(mode: int) -> void:
	_apply_mode(mode)
	_set_state(State.READY)


# Loads the character/gate/FX asset set for the given Mode into the existing
# runtime textures/vars — called once at _ready() (default SKY) and again
# every time the mode-select screen picks a mode. See MODE_CHARACTER_DIR/
# MODE_GATE_DIR/MODE_FX_DIR above for what's shared vs. per-mode.
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
	active_draw_offset_fly = MODE_DRAW_OFFSET_FLY[mode]
	active_draw_offset_happy = MODE_DRAW_OFFSET_HAPPY[mode]
	active_draw_offset_sad = MODE_DRAW_OFFSET_SAD[mode]
	active_visual_size_scale = MODE_VISUAL_SIZE_SCALE[mode]

	var gate_dir: String = MODE_GATE_DIR[mode]
	gate_left_pillar_texture = null
	if ResourceLoader.exists(gate_dir + "gate_ring_left.png"):
		gate_left_pillar_texture = load(gate_dir + "gate_ring_left.png")
	gate_right_pillar_texture = null
	if ResourceLoader.exists(gate_dir + "gate_ring_right.png"):
		gate_right_pillar_texture = load(gate_dir + "gate_ring_right.png")
	gate_base_texture = null
	if ResourceLoader.exists(gate_dir + "gate_ring_base.png"):
		gate_base_texture = load(gate_dir + "gate_ring_base.png")

	bg_texture = null
	var bg_path: String = MODE_BG_TEXTURE_PATH[mode]
	if bg_path != "" and ResourceLoader.exists(bg_path):
		bg_texture = load(bg_path)
	bg_scroll_x = 0.0

	particle_textures.clear()
	if mode != Mode.SKY:  # sky's twinkling light particles didn't fit the scene, dropped per request — jungle/ocean keep theirs
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
	active_flag_panel_window_center = MODE_GATE_FLAG_PANEL_WINDOW_CENTER_LOCAL[mode]
	active_flag_panel_window_width = MODE_GATE_FLAG_PANEL_WINDOW_WIDTH_LOCAL[mode]
	active_flag_panel_window_height = MODE_GATE_FLAG_PANEL_WINDOW_HEIGHT_LOCAL[mode]

	ready_texture = null
	if ResourceLoader.exists(MODE_READY_TEXTURE_PATH[mode]):
		ready_texture = load(MODE_READY_TEXTURE_PATH[mode])
	start_texture = null
	if ResourceLoader.exists(MODE_START_TEXTURE_PATH[mode]):
		start_texture = load(MODE_START_TEXTURE_PATH[mode])
	# TRY AGAIN is a node in the game-over panel rather than something
	# _draw() paints, so it is assigned rather than cached.
	if ResourceLoader.exists(MODE_TRY_AGAIN_TEXTURE_PATH[mode]):
		try_again_image.texture = load(MODE_TRY_AGAIN_TEXTURE_PATH[mode])

	# All four top-HUD pieces are per-mode. They share one canvas size per
	# piece across the modes, so nothing about the layout has to change here
	# — only which texture is drawn.
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
	# Re-run now that the icons are loaded: _ready lays the row out before
	# any mode is applied, so it sizes off the HUD_BUTTON_SRC fallback.
	_layout_hud_buttons()

	var fx_dir: String = MODE_FX_DIR[mode]
	fx_big_particle_textures.clear()
	for i in range(1, 4):
		var big_path: String = fx_dir + "fx_big_%d.png" % i
		if ResourceLoader.exists(big_path):
			fx_big_particle_textures.append(load(big_path))
	fx_theme_object_textures.clear()
	for i in range(1, 6):
		var theme_path: String = fx_dir + "fx_theme_%d.png" % i
		if ResourceLoader.exists(theme_path):
			fx_theme_object_textures.append(load(theme_path))
	fx_small_particle_textures.clear()
	for i in range(1, FX_SMALL_PARTICLE_MAX_COUNT + 1):
		var small_path: String = fx_dir + "fx_small_%d.png" % i
		if ResourceLoader.exists(small_path):
			fx_small_particle_textures.append(load(small_path))
	trail_textures.clear()
	for i in TRAIL_TEXTURE_NUMBERS_PER_MODE[mode]:
		var trail_path: String = fx_dir + "fx_small_%d.png" % i
		if ResourceLoader.exists(trail_path):
			trail_textures.append(load(trail_path))
	active_theme_motion = MODE_FX_THEME_MOTION[mode]


func _start_countdown() -> void:
	countdown_phase = CountdownPhase.READY_TEXT
	countdown_timer = COUNTDOWN_READY_DURATION
	_set_state(State.COUNTDOWN)
	if fx_sound_countdown_ready.stream != null:
		fx_sound_countdown_ready.play()
	if bgm_player.stream != null and not bgm_player.playing:
		bgm_player.play()


func _reset_game() -> void:
	var view_size := get_viewport_rect().size
	player_y = (_gate_zone_top(view_size) + _gate_zone_bottom(view_size)) * 0.5
	player_vel = 0.0
	score = 0
	combo = 0
	gates_passed = 0
	gates.clear()
	last_quiz_key = ""  # repeat guard is per-run — see last_quiz_key
	flash_time = 0.0
	gate_speed_boost_elapsed = -1.0
	last_zone_center = player_y
	fx_sparks.clear()
	fx_speed_lines.clear()
	trail_particles.clear()
	trail_spawn_timer = 0.0
	fx_score_pops.clear()
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
	pause_panel.visible = true
	pause_button.modulate = Color(1.0, 1.0, 1.0, 0.5)


func _on_resume_pressed() -> void:
	paused = false
	pause_panel.visible = false
	pause_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_mute_pressed() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	mute_button.modulate = Color(1.0, 1.0, 1.0, 0.5) if muted else Color(1.0, 1.0, 1.0, 1.0)


func _animate_button_press(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * BUTTON_PRESS_SCALE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animate_button_release(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, BUTTON_PRESS_ANIM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_state(new_state: int) -> void:
	state = new_state
	mode_select_panel.visible = state == State.MODE_SELECT
	ready_panel.visible = state == State.READY
	gameover_panel.visible = state == State.GAMEOVER


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
	var score_src := _hud_src(score_box_texture, SCORE_BOX_SRC)
	var button_src := _hud_src(pause_button.icon if pause_button != null else null, HUD_BUTTON_SRC)
	return (score_src.y / button_src.y) * HUD_BUTTON_EXTRA


# One scale for the whole top row, chosen so pause + score box + mute exactly
# fill the screen width inside the margins. Everything in the row is sized
# from this, so enlarging the buttons automatically takes width back off the
# score box instead of overflowing the screen.
func _hud_row_scale(view_size: Vector2) -> float:
	var score_src := _hud_src(score_box_texture, SCORE_BOX_SRC)
	var button_src := _hud_src(pause_button.icon if pause_button != null else null, HUD_BUTTON_SRC)
	var available: float = view_size.x - HUD_ROW_SIDE_MARGIN * 2.0 - HUD_ROW_GAP * 2.0
	return available / (score_src.x + button_src.x * 2.0 * _hud_button_mult())


# Screen rect of the score box art. The art is cropped tight to its frame, so
# this rect IS what you see.
func _score_box_rect(view_size: Vector2) -> Rect2:
	var src := _hud_src(score_box_texture, SCORE_BOX_SRC)
	var draw_size: Vector2 = src * _hud_row_scale(view_size)
	return Rect2(Vector2(view_size.x * 0.5 - draw_size.x * 0.5, SCORE_BOX_TOP), draw_size)


# Screen rect of the quiz box art, parked directly under the score box. It
# spans the full width inside the margins rather than following the row
# scale — it has no neighbours to share the line with.
func _quiz_box_rect(view_size: Vector2) -> Rect2:
	var src := _hud_src(quiz_box_texture, QUIZ_BOX_SRC)
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


# Called from HudCanvas._draw. Everything here draws onto `ci` (the HUD's
# own canvas) rather than onto Main, which is the whole point — see
# scripts/HudCanvas.gd.
func draw_hud_into(ci: CanvasItem, view_size: Vector2) -> void:
	if state == State.PLAYING or state == State.COUNTDOWN:
		_draw_hud_bar(view_size, ci)
		_draw_quiz_box(view_size, ci)
	_draw_combo_glow(view_size, ci)


func _draw_hud_bar(view_size: Vector2, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	# PauseButton/MuteButton (real Control/Button nodes, see scene) occupy the
	# top-left/top-right corners; nothing drawn here for them. Combo lives
	# entirely in the gate zone's top-right corner as a per-pass effect (see
	# _draw_combo_popups), not here — this only ever draws the score box.
	if score_box_texture != null:
		var rect := _score_box_rect(view_size)
		ci.draw_texture_rect(score_box_texture, rect, false)
		# Two halves of the same box, each number matched to its own painted
		# label rather than sharing one size and line: the live score is the
		# big one, right-aligned to just inside the divider so its ones digit
		# never moves; the stored best is the small one, left-aligned so it
		# sits directly beside the word BEST.
		var score_font_size := int(round(rect.size.y * SCORE_NUMBER_FONT_FRAC))
		var score_right := rect.position.x + rect.size.x * (SCORE_NUM_RIGHT_FRAC - SCORE_NUMBER_RIGHT_INSET_FRAC)
		var score_mid_y: float = rect.position.y + rect.size.y * SCORE_NUMBER_MID_Y_FRAC
		_draw_spaced_digits("%05d" % score, Vector2(score_right, score_mid_y), score_font_size, SCORE_NUMBER_DIGIT_SPACING, true, Color(1.0, 1.0, 1.0, 1.0), COLOR_TEXT_OUTLINE, score_font, ci)
		var best_font_size := int(round(rect.size.y * BEST_NUMBER_FONT_FRAC))
		var best_left := rect.position.x + rect.size.x * BEST_NUM_LEFT_FRAC
		var best_mid_y: float = rect.position.y + rect.size.y * BEST_NUMBER_MID_Y_FRAC
		_draw_spaced_digits("%05d" % best_score, Vector2(best_left, best_mid_y), best_font_size, SCORE_NUMBER_DIGIT_SPACING, false, Color(1.0, 1.0, 1.0, 1.0), COLOR_TEXT_OUTLINE, score_font, ci)
	else:
		ci.draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, HUD_BAR_HEIGHT)), HUD_BAR_COLOR)
		_draw_centered_text("SCORE %d  BEST %d" % [score, best_score], Vector2(view_size.x * 0.5, HUD_BAR_HEIGHT * 0.5), 18, COLOR_TEXT, COLOR_TEXT_OUTLINE, null, ci)


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
		ci.draw_texture_rect(quiz_box_texture, rect, false)
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
		ci.draw_texture_rect(quiz_box_texture, rect, false)
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
		if bird_texture != null:
			draw_set_transform(pos, 0.0, bird_scale)
			draw_texture_rect(bird_texture, Rect2(-PLAYER_VISUAL_SIZE * 0.5 + draw_offset, PLAYER_VISUAL_SIZE), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
	_draw_score_pops()
	_draw_combo_popups(view_size)
	# _draw_combo_glow also moved to HudCanvas: its top band overlaps the
	# score box, and it has to stay on top of it the way it was here.

	if state == State.COUNTDOWN:
		var countdown_center := Vector2(view_size.x * 0.5, view_size.y * 0.5)
		if countdown_phase == CountdownPhase.READY_TEXT:
			if ready_texture != null:
				_draw_countdown_image(ready_texture, countdown_center, 1.0)
			else:
				_draw_centered_text("READY", countdown_center, 36)
		else:
			var t: float = 1.0 - (countdown_timer / COUNTDOWN_START_DURATION)
			var pop_scale: float = _pop_scale(t)
			if start_texture != null:
				_draw_countdown_image(start_texture, countdown_center, pop_scale)
			else:
				_draw_centered_text("START", countdown_center, int(round(36.0 * pop_scale)))

	if flash_time > 0.0:
		var a: float = flash_color.a * (flash_time / FLASH_DURATION)
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(flash_color.r, flash_color.g, flash_color.b, a))
	# Layer 5 (pause menu / game-over panel) is real Control nodes in the UI
	# CanvasLayer, which already renders above all of this Node2D's _draw()
	# content — nothing to do here for it.


func _draw_countdown_image(texture: Texture2D, center: Vector2, scale_mult: float) -> void:
	# The art is centred within its own canvas by the slicer, so drawing the
	# canvas centred on `center` is all it takes — no per-mode correction.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var draw_size: Vector2 = tex_size * (COUNTDOWN_IMAGE_WIDTH / tex_size.x) * scale_mult
	draw_texture_rect(texture, Rect2(center - draw_size * 0.5, draw_size), false)


func _pop_scale(t: float) -> float:
	# t: 0..1 progress through the "START" display. Quick overshoot to 1.3x,
	# then eases back down to 1.0x for a short "pop" feel.
	const PEAK_T := 0.35
	const PEAK_SCALE := 1.3
	if t < PEAK_T:
		return lerpf(1.0, PEAK_SCALE, t / PEAK_T)
	return lerpf(PEAK_SCALE, 1.0, (t - PEAK_T) / (1.0 - PEAK_T))


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
	var cell := 0.0
	for d in range(10):
		cell = max(cell, font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var total_width: float = cell * text.length() + extra_spacing * max(0, text.length() - 1)
	var cursor_x: float = anchor.x - total_width if align_right else anchor.x
	# draw_string takes a baseline, but anchor.y is where the glyphs should
	# look centered. Centering on the font's line height would sit the digits
	# high, since the descent below the baseline is empty space they never
	# use — see DIGIT_BASELINE_FROM_CENTER_FRAC for the measured offset this
	# uses instead.
	var y := anchor.y + font_size * DIGIT_BASELINE_FROM_CENTER_FRAC
	for i in range(text.length()):
		var ch: String = text[i]
		var w: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(cursor_x + (cell - w) * 0.5, y)
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			ci.draw_string(font, pos + offset, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)
		ci.draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)
		cursor_x += cell + extra_spacing


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
