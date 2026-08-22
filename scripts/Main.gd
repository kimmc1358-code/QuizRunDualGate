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

const PLAYER_SIZE := Vector2(36, 36)  # hitbox — independent of the sprite, unchanged by any art swap
const PLAYER_VISUAL_SIZE := Vector2(64, 64)  # 1x integer scale of the 64x64 source art
const PLAYER_X := 130.0

# Wing-flap loop: user-supplied 3-frame set (up/mid/down), cycled as
# up -> mid -> down -> mid -> repeat by just listing mid twice — the index
# cycling below doesn't need to know the sequence isn't 4 unique frames.
# All three share one 64x64 canvas so swapping frames never shifts the
# apparent center. ~9 FPS (mid of the requested 8-10 FPS range).
const FLAP_FRAME_DURATION := 0.11
const FLAP_FRAME_PATHS := [
	"res://assets/characters/custom_bird/bird_fly_up.png",
	"res://assets/characters/custom_bird/bird_fly_mid.png",
	"res://assets/characters/custom_bird/bird_fly_down.png",
	"res://assets/characters/custom_bird/bird_fly_mid.png",
]

# Gate-pass "happy" expression swap — a separate 3-frame set (same up/mid/
# down/mid cycle shape as FLAP_FRAME_PATHS above, same PixelLab character/
# palette, just a new "Happy" state) drawn in place of the normal flap
# frames for HAPPY_FLAP_DURATION after every successful pass, then reverts
# on its own. Never touches FLAP_FRAME_PATHS or the normal flap_frame_index/
# flap_timer cadence — see happy_flap_elapsed in _update_fx/_draw.
const HAPPY_FLAP_FRAME_PATHS := [
	"res://assets/characters/custom_bird/bird_happy_up.png",
	"res://assets/characters/custom_bird/bird_happy_mid.png",
	"res://assets/characters/custom_bird/bird_happy_down.png",
	"res://assets/characters/custom_bird/bird_happy_mid.png",
]
const HAPPY_FLAP_DURATION := 0.6

# Game-over "sad" face — a single static frame (no animation needed, the
# screen is frozen on GAME OVER anyway), same technique as the happy set:
# same pose/wings/colors as bird_fly_mid.png, only the expression edited.
const SAD_FACE_PATH := "res://assets/characters/custom_bird/bird_sad_mid.png"

const GATE_WIDTH := 130.0
const GATE_SPEED := 130.0  # halved for testing — was 260.0
# The center wall doubles as the fixed 30-40px buffer between the top and
# bottom gates (see _gate_wall_center_y) — its own thickness IS that buffer,
# so widening it here is the whole fix; nothing else needs to change.
const WALL_THICKNESS := 36.0

# ============================================================
# Screen layout zones (top -> bottom): HUD bar -> quiz box -> the gate zone
# (everything gameplay-visual: gates/wall/bird), starting right at the quiz
# box's real (non-transparent) bottom edge -> optionally a fixed control
# zone at the very bottom (Easy mode only; Hard mode's gate zone just runs
# to the screen edge).
# These are absolute pixel values, not scaled with screen height, per spec —
# see _gate_zone_top/_gate_zone_bottom, the only two places that combine
# them into the actual bounds gate spawning/clamping/drawing use.
# ============================================================
const HUD_BAR_HEIGHT := 100.0
const HUD_SIDE_MARGIN := 12.0
const HUD_BAR_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const QUIZ_BOX_MARGIN := 24.0        # left/right inset from screen edges (fallback draw only)
# Both score_panel.png and quiz_box.png carry a lot of transparent padding
# around their actual painted frame (wings/clouds stick out unevenly), so a
# gap of 0 here still looks like a big visual gap on screen — this is
# negative to pull the quiz box's real artwork up close to the score
# panel's real bottom edge. See the two PNGs' measured content bounds if
# retuning: score panel's frame spans y 0.278-0.737 of its canvas, quiz
# box's spans y 0.231-0.641 of its own (different canvas height).
const QUIZ_BOX_TOP_GAP := -28.0
const QUIZ_BOX_HEIGHT := 116.0       # display height; width follows the quiz_box.png source aspect (~3:1 wide banner)
const QUIZ_BOX_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const QUIZ_BOX_CORNER_RADIUS := 12.0
# Blank text area inside quiz_box.png sits to the right of the "Q." badge —
# measured directly off the source PNG (cream box spans roughly x
# 0.159-0.976, y 0.311-0.559 of the full image).
const QUIZ_TEXT_CENTER_X_FRAC := 0.567
const QUIZ_TEXT_CENTER_Y_FRAC := 0.47
const QUIZ_TEXT_MAX_WIDTH_FRAC := 0.75
# Same measured content bounds as above, used to find the quiz box's real
# (non-transparent) bottom edge on screen — see _gate_zone_top, which anchors
# the gate zone to this instead of the padded bounding box.
const QUIZ_CONTENT_BOTTOM_FRAC := 0.641
const GATE_ZONE_TOP_BUFFER := 0.0    # extra gap beyond the quiz box's real bottom edge, if ever wanted again
const CONTROL_ZONE_HEIGHT := 70.0    # Easy mode only — layout reserved, no buttons wired yet (see README)

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
# Pillar art (gate_glow_256 set): each side is a 256x256 PNG, pre-split from
# a single master (gate_normal_256.png) so left+right always land exactly on
# top of each other with no manual per-layer positioning — verified
# pixel-identical to the master when composited. Each side also ships 3 glow
# variants (successively brighter crystals) for the gate-pass flash (see
# GATE_GLOW_SEQUENCE below); left and right always show the same glow stage
# together since both are driven by the same elapsed-time lookup
# (_gate_glow_frame_index). NOTE: the file names say "left_back"/
# "right_front", but which side renders in front of the bird is a deliberate
# choice made earlier (bird ducks behind the right pillar, emerges in front
# of the left) — the FRONT/BACK draw-order comment above reflects the actual
# behavior, not the file names.
const GATE_GLOW_DIR := "res://assets/gates/gate_glow_256/"
const GATE_LEFT_PILLAR_PATHS := [
	GATE_GLOW_DIR + "gate_left_back_normal_256.png",
	GATE_GLOW_DIR + "gate_left_back_glow_01_256.png",
	GATE_GLOW_DIR + "gate_left_back_glow_02_256.png",
	GATE_GLOW_DIR + "gate_left_back_glow_03_256.png",
]
const GATE_RIGHT_PILLAR_PATHS := [
	GATE_GLOW_DIR + "gate_right_front_normal_256.png",
	GATE_GLOW_DIR + "gate_right_front_glow_01_256.png",
	GATE_GLOW_DIR + "gate_right_front_glow_02_256.png",
	GATE_GLOW_DIR + "gate_right_front_glow_03_256.png",
]
# Gate-pass glow flash: steps through NORMAL -> 01 -> 02 -> 03 -> 02 -> 01 ->
# NORMAL, each held for the matching GATE_GLOW_STEP_DURATIONS entry before
# advancing (index 0 = normal, 1-3 = glow stages) — see
# _gate_glow_frame_index. Adjust these two arrays to retime the flash; they
# must stay the same length (6 steps between the 7 sequence entries).
const GATE_GLOW_SEQUENCE := [0, 1, 2, 3, 2, 1, 0]
const GATE_GLOW_STEP_DURATIONS := [0.06, 0.06, 0.08, 0.08, 0.08, 0.08]
# Pillar art's own canvas size (gate_glow_256 set is 256x256) and its
# topmost/lowest opaque pixels (measured bbox on gate_normal_256.png) — the
# frame's actual edges, above/below the zone center. Used to keep the spawn
# band inset from the screen edges (see _gate_frame_top_overhang/
# _gate_frame_bottom_overhang) so the frame never clips off-screen.
const GATE_PILLAR_CANVAS_SIZE := 256.0
const GATE_PILLAR_TOP_LOCAL_Y := 6.0
const GATE_PILLAR_BOTTOM_LOCAL_Y := 249.0
# Safety margin so the FX_GATE_PUNCH_KEYFRAMES peak (+8%) can't push the
# frame's edges past the screen bounds this clamp is meant to guarantee.
const GATE_VISUAL_CLAMP_MARGIN := 1.1
#
# The frame's own display size is FIXED, not phase-scaled — it's the
# container the flag answer art and pass-through FX are built against, so
# it can't keep shrinking every phase or that art and those effects would
# never fit consistently. gate_visual_zone_ratio controls how much bigger
# the frame renders than the zone highlight inside it — left at the
# original 2.2 (gate size unchanged) per request; the zone itself is grown
# instead via PHASE_ZONE_MARGIN[0] below. Don't shrink this ratio without
# also shrinking GATE_FLAG_ICON_WIDTH/HEIGHT — the answer flag sits in the
# same gap above the zone, and at some point the two start to overlap.
# Phase 1's zone height (PLAYER_SIZE.y 36 + PHASE_ZONE_MARGIN[0] 60) — the
# largest/most permissive zone, used as a constant sizing reference so the
# frame never rescales itself between phases.
const GATE_VISUAL_REFERENCE_ZONE_HEIGHT := 96.0
@export_range(1.0, 4.0, 0.05) var gate_visual_zone_ratio: float = 1.9

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

# Answer flag icon sits inside the gate's decorative frame, directly above
# its zone — positioned so the border's own bottom edge exactly touches the
# zone's top edge (see _draw_gate_answer_flag), never overlapping it and
# never leaving a gap either. Flag PNGs are all a unified 256x171 (3:2)
# frame now (see assets/flags/flags_data.json), so the display size is a
# rect, not a square — width/height match that same 3:2 ratio so the art
# is never stretched.
const GATE_FLAG_ICON_WIDTH := 72.0
const GATE_FLAG_ICON_HEIGHT := 48.0
# Border framing the flag, styled to match the gate pillar's own crystal
# window (gold trim band + thin dark inner outline) — colors sampled
# directly from assets/gates/gate_glow_256/gate_left_back_normal_256.png
# so the two read as the same decorative language, not two unrelated pieces.
const GATE_FLAG_BORDER_THICKNESS := 2.5
const GATE_FLAG_OUTLINE_THICKNESS := 1.3
const GATE_FLAG_BORDER_COLOR := Color(0.969, 0.580, 0.016)
const GATE_FLAG_OUTLINE_COLOR := Color(0.059, 0.008, 0.31)
# Beveled trim (lighter gold along top/left, darker along bottom/right,
# same 3D-bevel trick the crystal window itself uses) plus small corner
# gem accents — the same corner-diamond motif already used on score_panel
# and quiz_box, reused here so all three UI pieces read as one kit.
const GATE_FLAG_BORDER_HIGHLIGHT := Color(1.0, 0.82, 0.35)
const GATE_FLAG_BORDER_SHADOW := Color(0.75, 0.33, 0.0)
const GATE_FLAG_CORNER_ACCENT_SIZE := 3.4
const GATE_FLAG_CORNER_ACCENT_COLOR := Color(0.969, 0.580, 0.016)
const GATE_FLAG_CORNER_ACCENT_HIGHLIGHT := Color(1.0, 0.95, 0.6)

# ============================================================
# Combo tier popup — an "×N" burst in the gate zone's top-right corner,
# fired on every successful pass (spawned from _resolve_gate right next to
# where `combo` itself is incremented), never a persistent HUD element.
# Entirely independent of the Phase system (gates_passed-based difficulty
# curve) — this only ever reads `combo`. Four escalating tiers, 25 combo
# wide each, capped at Tier 4 for anything >= COMBO_TIER_CAP.
# ============================================================
const COMBO_FONT_PATH := "res://assets/fonts/Mulmaru.ttf"
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
# NOTE: a near-cloud-sea foreground layer (cloud_near_seamless_512x256.png)
# used to live here and has been removed entirely per request. The file
# itself is left on disk untouched; nothing below loads or references it.
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
# and GATE_GLOW_STEP_DURATIONS' total (currently 0.440s) — this is what
# _gate_glow_frame_index reads elapsed time against.
const FX_GATE_TIMELINE_DURATION := 0.45

# 3. Two-stage particle burst: big/immediate, then small/delayed. Counts,
# sizes, speeds, and lifetimes all bumped up for a bigger, longer-lived burst.
const FX_SPARK_TEXTURE_PATH := "res://assets/fx/success_spark.png"
const FX_SPARK_BURST_A_COUNT_RANGE := Vector2i(6, 9)        # big, at 0ms
const FX_SPARK_BURST_A_SCALE_RANGE := Vector2(1.5, 2.2)
const FX_SPARK_BURST_B_COUNT_RANGE := Vector2i(18, 26)      # small, delayed
const FX_SPARK_BURST_B_SCALE_RANGE := Vector2(0.6, 1.1)
const FX_SPARK_BURST_B_DELAY_RANGE := Vector2(0.04, 0.06)
const FX_SPARK_LIFETIME_RANGE := Vector2(0.20, 0.42)
const FX_SPARK_SPEED_RANGE := Vector2(70.0, 150.0)          # px/s, outward from gate center
const FX_SPARK_GOLD_CHANCE := 0.25                          # rest split white/cyan
const FX_SPARK_GOLD_TINT := Color(1.0, 0.82, 0.45)
const FX_SPARK_CYAN_TINT := Color(0.75, 0.96, 1.0)
const FX_SPARK_WHITE_TINT := Color(1.0, 1.0, 1.0)
const FX_SPARK_RING_MARGIN := 18.0  # spawn ring sits this far outside the frame's own outer edge

# 5. Speed accent — short thick streaks, fired together with spark burst B.
const FX_SPEED_LINE_COUNT_RANGE := Vector2i(4, 6)
const FX_SPEED_LINE_DURATION := 0.13
const FX_SPEED_LINE_LENGTH_RANGE := Vector2(30.0, 60.0)
const FX_SPEED_LINE_THICKNESS := 4.5
const FX_SPEED_LINE_Y_SPREAD := 0.4                 # fraction of PLAYER_VISUAL_SIZE.y either side
const FX_SPEED_LINE_CYAN := Color(0.75, 0.96, 1.0)
const FX_SPEED_LINE_WHITE := Color(1.0, 1.0, 1.0)

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

enum Difficulty { EASY, HARD }

# Precision-zone clearance beyond the player hitbox (Hard mode only). Was
# phase-scaled (shrinking each phase) but that's reverted per feedback —
# _spawn_gate now always uses index 0 regardless of phase. Left as an array
# (not a single float) so the per-phase curve is a one-line change to bring
# back if wanted later.
# Easy mode never uses this — the whole lane stays a safe zone (see _resolve_gate).
const PHASE_ZONE_MARGIN := [90.0, 45.0, 32.0, 20.0]

# Placeholder phase thresholds keyed on gates-passed count — the design doc
# leaves the real curve open (section 11), tune these once that's decided.
const PHASE_GATE_THRESHOLDS := [0, 5, 12, 20]

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

enum State { READY, COUNTDOWN, PLAYING, GAMEOVER }

var state: int = State.READY
var difficulty: int = Difficulty.HARD  # Only Hard is wired to the UI so far.

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

# "READY!" / "START!" countdown pop art — PixelLab-sourced, drawn in place of
# the old plain-text draw_string call (see the State.COUNTDOWN block in
# _draw()). Falls back to the old text if either file is missing.
const READY_TEXTURE_PATH := "res://assets/ui_assets/Ready.png"
const START_TEXTURE_PATH := "res://assets/ui_assets/Start.png"
const COUNTDOWN_IMAGE_WIDTH := 220.0  # display width in px; height follows the source aspect ratio

# Top HUD art: pause (top-left, real Button) / mute (top-right, real Button) /
# score panel (top-center, drawn — no interaction needed). All PixelLab-
# sourced, sized to fit inside the existing HUD_BAR_HEIGHT band unchanged.
const PAUSE_ICON_PATH := "res://assets/ui_assets/pause.png"
const MUTE_ICON_PATH := "res://assets/ui_assets/mute.png"
const SCORE_PANEL_PATH := "res://assets/ui_assets/score_panel.png"
const QUIZ_BOX_TEXTURE_PATH := "res://assets/ui_assets/quiz_box.png"
const SCORE_PANEL_WIDTH := 240.0            # display width; height follows source aspect
# Blank number box inside the score panel art sits to the right of the
# "SCORE" label — measured directly off the source PNG (cream box spans
# roughly x 0.397-0.869, y 0.356-0.658 of the full image). The number is
# drawn right-aligned so it hugs the box's right edge instead of centering
# under the whole panel (which would drift left, under the label).
const SCORE_NUMBER_RIGHT_FRAC := 0.83       # fraction of panel display width — right edge the digits align to
const SCORE_NUMBER_Y_FRAC := 0.51           # fraction of panel display height — vertical center of the digits
const SCORE_NUMBER_FONT_SCALE := 0.22       # fraction of panel display height, used as the digit font size
const SCORE_NUMBER_DIGIT_SPACING := 3.0     # extra px inserted between digits (score panel's default kerning is tight)
const SCORE_NUMBER_EMBOLDEN := 0.5          # faux-bold strength (FontVariation) — Mulmaru only ships one weight

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

var flap_frames: Array[Texture2D] = []
var flap_frame_index: int = 0
var flap_timer: float = 0.0
var happy_flap_frames: Array[Texture2D] = []
var happy_flap_elapsed: float = -1.0  # -1 = inactive; set to 0 on every gate pass, see _play_gate_success_fx
var sad_face_texture: Texture2D
var ready_texture: Texture2D
var start_texture: Texture2D
var score_panel_texture: Texture2D
var score_font: Font
var quiz_box_texture: Texture2D
var flag_records: Array = []          # [{code, name, image, tier}, ...] — see FLAGS_DATA_PATH
var flag_textures: Dictionary = {}    # code (String) -> Texture2D, preloaded from flag_records
var flag_records_by_tier: Dictionary = {}  # tier (int 1-4) -> Array of records, for difficulty-gated spawning
var muted: bool = false

var gate_left_pillar_textures: Array[Texture2D] = []   # [normal, glow01, glow02, glow03]
var gate_right_pillar_textures: Array[Texture2D] = []  # [normal, glow01, glow02, glow03]

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

# Gate-pass FX state (see the const block above for tunables).
var fx_spark_texture: Texture2D
var fx_sparks: Array = []            # each: {pos, vel, scale, rotation, lifetime, elapsed, tint}
var fx_speed_lines: Array = []       # each: {y_offset, length, elapsed, color}
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

@onready var ready_panel: Control = $UI/ReadyPanel
@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var final_score_label: Label = $UI/GameOverPanel/FinalScoreLabel
@onready var play_button: Button = $UI/ReadyPanel/PlayButton
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton
@onready var pause_button: Button = $UI/PauseButton
@onready var mute_button: Button = $UI/MuteButton
@onready var pause_panel: Control = $UI/PausePanel
@onready var resume_button: Button = $UI/PausePanel/ResumeButton


func _ready() -> void:
	# Keeps all pixel art crisp at any render scale — draw_texture_rect has no
	# per-call filter option, so this has to be set on the CanvasItem itself.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for path in FLAP_FRAME_PATHS:
		flap_frames.append(load(path))
	for path in HAPPY_FLAP_FRAME_PATHS:
		happy_flap_frames.append(load(path))
	if ResourceLoader.exists(SAD_FACE_PATH):
		sad_face_texture = load(SAD_FACE_PATH)
	if ResourceLoader.exists(READY_TEXTURE_PATH):
		ready_texture = load(READY_TEXTURE_PATH)
	if ResourceLoader.exists(START_TEXTURE_PATH):
		start_texture = load(START_TEXTURE_PATH)
	if ResourceLoader.exists(SCORE_PANEL_PATH):
		score_panel_texture = load(SCORE_PANEL_PATH)
	if ResourceLoader.exists(QUIZ_BOX_TEXTURE_PATH):
		quiz_box_texture = load(QUIZ_BOX_TEXTURE_PATH)
	_load_flags_data()
	if ResourceLoader.exists(PAUSE_ICON_PATH):
		pause_button.icon = load(PAUSE_ICON_PATH)
		pause_button.text = ""
		pause_button.expand_icon = true
	if ResourceLoader.exists(MUTE_ICON_PATH):
		mute_button.icon = load(MUTE_ICON_PATH)
		mute_button.text = ""
		mute_button.expand_icon = true
	if ResourceLoader.exists(COMBO_FONT_PATH):
		combo_font = load(COMBO_FONT_PATH)
	else:
		combo_font = ThemeDB.fallback_font
	var score_font_variation := FontVariation.new()
	score_font_variation.base_font = combo_font
	score_font_variation.variation_embolden = SCORE_NUMBER_EMBOLDEN
	score_font = score_font_variation
	for path in GATE_LEFT_PILLAR_PATHS:
		gate_left_pillar_textures.append(load(path))
	for path in GATE_RIGHT_PILLAR_PATHS:
		gate_right_pillar_textures.append(load(path))
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
	if ResourceLoader.exists(FX_SPARK_TEXTURE_PATH):
		fx_spark_texture = load(FX_SPARK_TEXTURE_PATH)
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
	play_button.pressed.connect(_on_play_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	mute_button.pressed.connect(_on_mute_pressed)
	pause_button.pivot_offset = pause_button.size * 0.5
	mute_button.pivot_offset = mute_button.size * 0.5
	pause_button.button_down.connect(_animate_button_press.bind(pause_button))
	pause_button.button_up.connect(_animate_button_release.bind(pause_button))
	mute_button.button_down.connect(_animate_button_press.bind(mute_button))
	mute_button.button_up.connect(_animate_button_release.bind(mute_button))
	_reset_game()
	_set_state(State.READY)


# Loads assets/flags/flags_data.json (193 UN member records) and preloads
# every flag texture up front — 193 tiny 64x64 PNGs is negligible memory,
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
		var tier: int = record.tier
		if not flag_records_by_tier.has(tier):
			flag_records_by_tier[tier] = []
		flag_records_by_tier[tier].append(record)


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


func _gate_zone_top(view_size: Vector2) -> float:
	# Anchored to the quiz box's real (non-transparent) bottom edge, not its
	# padded bounding box — quiz_box.png has a lot of transparent margin, so
	# using the raw box_top + QUIZ_BOX_HEIGHT would leave a dead gap here and
	# shrink the gate's actual travel range for no visual reason. The top
	# gate's frame is separately inset in _spawn_gate (see
	# _gate_frame_top_overhang) so its own top edge still never crosses this
	# line — it's allowed to touch it, just not go past it.
	var quiz_box_top: float = HUD_BAR_HEIGHT + QUIZ_BOX_TOP_GAP
	return quiz_box_top + QUIZ_BOX_HEIGHT * QUIZ_CONTENT_BOTTOM_FRAC + GATE_ZONE_TOP_BUFFER


func _gate_zone_bottom(view_size: Vector2) -> float:
	# Easy mode reserves a fixed control zone at the very bottom; Hard mode
	# has no button UI, so the gate zone just runs to the screen edge.
	if difficulty == Difficulty.EASY:
		return view_size.y - CONTROL_ZONE_HEIGHT
	return view_size.y


func _gate_wall_center_y(view_size: Vector2) -> float:
	# The center wall (and the top/bottom lane split) is centered within the
	# gate zone, not the raw screen — otherwise shrinking the top of the
	# zone for the HUD/quiz box would silently steal space from the top
	# lane only, making the two lanes uneven.
	return (_gate_zone_top(view_size) + _gate_zone_bottom(view_size)) * 0.5


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
	# from the screen's bottom edge. Pillar-canvas-space (256 units).
	var base_scale: float = ((GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / GATE_PILLAR_CANVAS_SIZE) * GATE_VISUAL_CLAMP_MARGIN
	var pillar_center: float = GATE_PILLAR_CANVAS_SIZE * 0.5
	return (GATE_PILLAR_BOTTOM_LOCAL_Y - pillar_center) * base_scale


func _draw_gate_frame_layer(texture: Texture2D, center_x: float, center_y: float, punch_scale: float = 1.0) -> void:
	if texture == null:
		return
	var target_long_edge: float = GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio
	# punch_scale (see _gate_punch_scale) is a draw-time-only size wobble —
	# it never changes the zone/collision geometry this is centered on. The
	# gate-pass color flash is real glow-frame art now (see
	# _gate_glow_frame_index), not a synthetic tint here.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var scale_factor: float = (target_long_edge / max(tex_size.x, tex_size.y)) * punch_scale
	var draw_size: Vector2 = tex_size * scale_factor
	var top_left := Vector2(center_x - draw_size.x * 0.5, center_y - draw_size.y * 0.5)
	draw_texture_rect(texture, Rect2(top_left, draw_size), false)


# Draws a gate's answer flag icon inside its own decorative frame, always on
# the frame's own "top" side (toward smaller y) — the pillar art is never
# vertically flipped between lanes, so its top-of-canvas opening faces the
# same direction (up) whether this is the top-lane or bottom-lane gate;
# mirroring the icon per-lane put it down in the bottom lane's floral pillar
# base instead of at the U's opening. Anchored so the border's own bottom
# edge sits exactly on zone_top (touching, never overlapping), clamped only
# as a safety floor so it can't render above _gate_zone_top (the HUD/quiz-
# box buffer). code indexes into flag_textures — see _spawn_gate for where
# top_code/bottom_code are set and code-checked against the quiz box target.
func _draw_gate_answer_flag(code: String, gate_x: float, zone_top: float, zone_bottom: float, view_size: Vector2) -> void:
	var texture: Texture2D = flag_textures.get(code)
	if texture == null:
		return
	var center_x: float = gate_x + GATE_WIDTH * 0.5
	var outline_half_h: float = GATE_FLAG_ICON_HEIGHT * 0.5 + GATE_FLAG_BORDER_THICKNESS + GATE_FLAG_OUTLINE_THICKNESS
	var center_y: float = maxf(zone_top - outline_half_h, _gate_zone_top(view_size) + outline_half_h)

	var icon_size := Vector2(GATE_FLAG_ICON_WIDTH, GATE_FLAG_ICON_HEIGHT)
	var icon_top_left := Vector2(center_x, center_y) - icon_size * 0.5
	var border_size := icon_size + Vector2.ONE * (GATE_FLAG_BORDER_THICKNESS * 2.0)
	var border_top_left := icon_top_left - Vector2.ONE * GATE_FLAG_BORDER_THICKNESS
	var outline_size := border_size + Vector2.ONE * (GATE_FLAG_OUTLINE_THICKNESS * 2.0)
	var outline_top_left := border_top_left - Vector2.ONE * GATE_FLAG_OUTLINE_THICKNESS

	# Dark outline -> gold trim band -> flag art, same layering as the gate
	# frame's own crystal window (dark outline around a gold-trimmed inset).
	draw_rect(Rect2(outline_top_left, outline_size), GATE_FLAG_OUTLINE_COLOR)
	draw_rect(Rect2(border_top_left, border_size), GATE_FLAG_BORDER_COLOR)

	# Bevel the gold band — brighter along top/left, darker along
	# bottom/right — the same 3D trick the gate's own crystal trim uses,
	# instead of one flat gold tone.
	var band_inset: float = GATE_FLAG_BORDER_THICKNESS * 0.5
	var b_tl: Vector2 = border_top_left + Vector2.ONE * band_inset
	var b_tr: Vector2 = border_top_left + Vector2(border_size.x - band_inset, band_inset)
	var b_bl: Vector2 = border_top_left + Vector2(band_inset, border_size.y - band_inset)
	var b_br: Vector2 = border_top_left + border_size - Vector2.ONE * band_inset
	draw_line(b_tl, b_tr, GATE_FLAG_BORDER_HIGHLIGHT, GATE_FLAG_BORDER_THICKNESS)
	draw_line(b_tl, b_bl, GATE_FLAG_BORDER_HIGHLIGHT, GATE_FLAG_BORDER_THICKNESS)
	draw_line(b_bl, b_br, GATE_FLAG_BORDER_SHADOW, GATE_FLAG_BORDER_THICKNESS)
	draw_line(b_tr, b_br, GATE_FLAG_BORDER_SHADOW, GATE_FLAG_BORDER_THICKNESS)

	draw_texture_rect(texture, Rect2(icon_top_left, icon_size), false)

	# Small gem accents at the four outline corners — same corner-diamond
	# motif as score_panel.png / quiz_box.png, tying this into the rest of
	# the UI kit.
	_draw_flag_corner_accent(outline_top_left)
	_draw_flag_corner_accent(outline_top_left + Vector2(outline_size.x, 0.0))
	_draw_flag_corner_accent(outline_top_left + Vector2(0.0, outline_size.y))
	_draw_flag_corner_accent(outline_top_left + outline_size)


func _draw_flag_corner_accent(center: Vector2) -> void:
	var s := GATE_FLAG_CORNER_ACCENT_SIZE
	var outer := PackedVector2Array([
		center + Vector2(0, -s), center + Vector2(s, 0), center + Vector2(0, s), center + Vector2(-s, 0),
	])
	draw_colored_polygon(outer, GATE_FLAG_CORNER_ACCENT_COLOR)
	var inner_s := s * 0.45
	var inner := PackedVector2Array([
		center + Vector2(0, -inner_s), center + Vector2(inner_s, 0), center + Vector2(0, inner_s), center + Vector2(-inner_s, 0),
	])
	draw_colored_polygon(inner, GATE_FLAG_CORNER_ACCENT_HIGHLIGHT)


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
		if fx_sound_flap.stream != null:
			fx_sound_flap.play()


func _process(delta: float) -> void:
	# Background parallax keeps drifting on every screen (menu, playing,
	# game over) for a lively backdrop, independent of gameplay state.
	var view_size := get_viewport_rect().size
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
		while flap_timer >= FLAP_FRAME_DURATION:
			flap_timer -= FLAP_FRAME_DURATION
			flap_frame_index = (flap_frame_index + 1) % flap_frames.size()
	queue_redraw()


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

	# Difficulty curve: phase 0 (tier 1) draws only from the most
	# internationally famous flags, phase 3 (tier 4) from the least — both
	# the correct answer and the decoy come from the same tier, so a wrong
	# choice is never a giveaway just because it "looks less famous."
	var tier: int = phase_index + 1
	var pool: Array = flag_records_by_tier.get(tier, flag_records)
	if pool.size() < 2:
		pool = flag_records
	var target_index := randi() % pool.size()
	var other_index := randi() % (pool.size() - 1)
	if other_index >= target_index:
		other_index += 1  # skip target_index so other is always a different country
	var target: Dictionary = pool[target_index]
	var other: Dictionary = pool[other_index]
	var top_correct: bool = randi() % 2 == 0

	var wall_center_y := _gate_wall_center_y(view_size)
	var wall_top := wall_center_y - WALL_THICKNESS * 0.5
	var wall_bottom := wall_center_y + WALL_THICKNESS * 0.5
	var margin: float = PHASE_ZONE_MARGIN[0]  # fixed, not phase_index — see comment on PHASE_ZONE_MARGIN
	var zone_height: float = PLAYER_SIZE.y + margin

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

	var top_code: String = target.code if top_correct else other.code
	var bottom_code: String = other.code if top_correct else target.code

	# Code-level correctness check (per spec): the quiz box always shows
	# target.name, so the gate in the correct lane must carry that exact
	# same country code, not just a name that happens to match.
	var correct_lane_code: String = top_code if top_correct else bottom_code
	assert(correct_lane_code == target.code, "Quiz target code and correct-lane gate code must match")

	gates.append({
		"x": PLAYER_X + base_gate_spacing,
		"top_code": top_code,
		"bottom_code": bottom_code,
		"top_correct": top_correct,
		"target_code": target.code,
		"target_name": target.name,
		"resolved": false,
		"top_zone_top": top_zone.x,
		"top_zone_bottom": top_zone.y,
		"bottom_zone_top": bottom_zone.x,
		"bottom_zone_bottom": bottom_zone.y,
	})


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


func _get_phase_index(passed_count: int) -> int:
	var idx := 0
	for i in range(PHASE_GATE_THRESHOLDS.size()):
		if passed_count >= PHASE_GATE_THRESHOLDS[i]:
			idx = i
	return idx


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

	var passed: bool
	if difficulty == Difficulty.HARD:
		# Being in the correct lane is necessary but not sufficient — you
		# must also be inside that lane's precision zone this gate rolled.
		if not in_correct_lane:
			passed = false
		else:
			var zone_top: float = g.top_zone_top if in_top else g.bottom_zone_top
			var zone_bottom: float = g.top_zone_bottom if in_top else g.bottom_zone_bottom
			passed = p_top >= zone_top and p_bottom <= zone_bottom
	else:
		# Easy mode: whole correct lane stays a safe zone, no precision check.
		passed = in_correct_lane

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
	# above, sampled in _draw()) + big spark burst + both sound hooks.
	_spawn_impact_flash(gate_center)
	_spawn_spark_burst(gate_center, FX_SPARK_BURST_A_COUNT_RANGE, FX_SPARK_BURST_A_SCALE_RANGE)
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


func _spawn_spark_burst(gate_center: Vector2, count_range: Vector2i, scale_range: Vector2) -> void:
	if fx_spark_texture == null:
		return
	var frame_outer_radius: float = (GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) * 0.5
	var ring_radius: float = frame_outer_radius + FX_SPARK_RING_MARGIN
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	var count: int = int(round(randi_range(count_range.x, count_range.y) * strength))
	for i in range(count):
		# Angled outward from gate_center (the zone center the bird just
		# passed through), starting at the ring outside the frame's own
		# edge — spreads toward the gate's outer boundary, not over the
		# bird's face/body which sits back near gate_center itself.
		var angle := randf_range(0.0, TAU)
		var dir := Vector2(cos(angle), sin(angle))
		var dist: float = ring_radius * randf_range(0.9, 1.15)
		var speed: float = randf_range(FX_SPARK_SPEED_RANGE.x, FX_SPARK_SPEED_RANGE.y) * strength
		var roll := randf()
		var tint: Color = FX_SPARK_GOLD_TINT if roll < FX_SPARK_GOLD_CHANCE \
			else (FX_SPARK_WHITE_TINT if roll < FX_SPARK_GOLD_CHANCE + 0.35 else FX_SPARK_CYAN_TINT)
		fx_sparks.append({
			"pos": gate_center + dir * dist,
			"vel": dir * speed,
			"scale": randf_range(scale_range.x, scale_range.y) * clampf(strength, 0.3, 2.0),
			"rotation": randf_range(0.0, TAU),
			"lifetime": randf_range(FX_SPARK_LIFETIME_RANGE.x, FX_SPARK_LIFETIME_RANGE.y),
			"elapsed": 0.0,
			"tint": tint,
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
		_spawn_spark_burst(pos, Vector2i(particle_count, particle_count), FX_SPARK_BURST_A_SCALE_RANGE)
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


func _gate_glow_frame_index(g: Dictionary, side: String) -> int:
	# Which pillar texture (0=normal, 1-3=glow stages) this side should show
	# right now — a step function over GATE_GLOW_SEQUENCE/
	# GATE_GLOW_STEP_DURATIONS, driven by the same elapsed-since-pass timer
	# as the punch/crystal-flash FX above. Returns 0 (normal) when idle or
	# once the flash has finished.
	var elapsed := _gate_fx_elapsed(g, side)
	if elapsed < 0.0:
		return 0
	var t := 0.0
	for i in range(GATE_GLOW_STEP_DURATIONS.size()):
		if elapsed < t + GATE_GLOW_STEP_DURATIONS[i]:
			return GATE_GLOW_SEQUENCE[i]
		t += GATE_GLOW_STEP_DURATIONS[i]
	return 0


func _bird_stretch_scale() -> Vector2:
	if fx_stretch_elapsed < 0.0 or fx_stretch_elapsed >= FX_STRETCH_DURATION:
		return Vector2.ONE
	var t: float = fx_stretch_elapsed / FX_STRETCH_DURATION
	var envelope: float = _sample_keyframes(FX_STRETCH_KEYFRAMES, t)
	var strength: float = clampf(successFxIntensity, 0.0, 2.0)
	var sx: float = lerp(1.0, FX_STRETCH_SCALE_X_PEAK, envelope * strength)
	var sy: float = lerp(1.0, FX_STRETCH_SCALE_Y_PEAK, envelope * strength)
	return Vector2(sx, sy)


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
		_spawn_spark_burst(b.gate_center, FX_SPARK_BURST_B_COUNT_RANGE, FX_SPARK_BURST_B_SCALE_RANGE)
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
	if fx_spark_texture == null or fx_sparks.is_empty():
		return
	var tex_size := Vector2(fx_spark_texture.get_width(), fx_spark_texture.get_height())
	for s in fx_sparks:
		var t: float = s.elapsed / s.lifetime
		var alpha: float = 1.0 - t  # fast fade-out
		var draw_scale: float = s.scale
		draw_set_transform(s.pos, s.rotation, Vector2.ONE * draw_scale)
		var tint: Color = s.tint
		draw_texture_rect(fx_spark_texture, Rect2(-tex_size * 0.5, tex_size), false, Color(tint.r, tint.g, tint.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


func _draw_combo_glow(view_size: Vector2) -> void:
	if combo_glow_elapsed < 0.0:
		return
	var t: float = combo_glow_elapsed / COMBO_GLOW_DURATION
	var pulse: float = 0.6 + 0.4 * sin(combo_glow_elapsed * TAU * 2.0)
	var alpha: float = COMBO_GLOW_PEAK_ALPHA * (1.0 - t) * pulse
	if alpha <= 0.0:
		return
	var c := Color(COMBO_GLOW_COLOR.r, COMBO_GLOW_COLOR.g, COMBO_GLOW_COLOR.b, alpha)
	var b := COMBO_GLOW_BAND_PX
	draw_rect(Rect2(Vector2(0, 0), Vector2(view_size.x, b)), c)
	draw_rect(Rect2(Vector2(0, view_size.y - b), Vector2(view_size.x, b)), c)
	draw_rect(Rect2(Vector2(0, 0), Vector2(b, view_size.y)), c)
	draw_rect(Rect2(Vector2(view_size.x - b, 0), Vector2(b, view_size.y)), c)


func _game_over() -> void:
	state = State.GAMEOVER
	combo = 0  # combo is purely a run-length streak; a miss always zeroes it immediately, not just on restart
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
	# Retry after onboarding is already done: short READY -> START beat
	# before gameplay actually starts.
	_reset_game()
	_start_countdown()


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
	flash_time = 0.0
	gate_speed_boost_elapsed = -1.0
	last_zone_center = player_y
	fx_sparks.clear()
	fx_speed_lines.clear()
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
	ready_panel.visible = state == State.READY
	gameover_panel.visible = state == State.GAMEOVER


# ---- Layer 3: HUD bar + quiz box (always drawn above the background/gate
# zone, per the layer-order spec) ----

func _draw_hud_bar(view_size: Vector2) -> void:
	var mid_y: float = HUD_BAR_HEIGHT * 0.5
	# PauseButton/MuteButton (real Control/Button nodes, see scene) occupy the
	# top-left/top-right corners; nothing drawn here for them. Combo lives
	# entirely in the gate zone's top-right corner as a per-pass effect (see
	# _draw_combo_popups), not here — this only ever draws the score panel.
	if score_panel_texture != null:
		var tex_size := Vector2(score_panel_texture.get_width(), score_panel_texture.get_height())
		var scale: float = SCORE_PANEL_WIDTH / tex_size.x
		var draw_size: Vector2 = tex_size * scale
		var top_left := Vector2(view_size.x * 0.5 - draw_size.x * 0.5, mid_y - draw_size.y * 0.5)
		draw_texture_rect(score_panel_texture, Rect2(top_left, draw_size), false)
		var number_right := Vector2(top_left.x + draw_size.x * SCORE_NUMBER_RIGHT_FRAC, top_left.y + draw_size.y * SCORE_NUMBER_Y_FRAC)
		var font_size := int(round(draw_size.y * SCORE_NUMBER_FONT_SCALE))
		_draw_spaced_right_aligned_text("%05d" % score, number_right, font_size, SCORE_NUMBER_DIGIT_SPACING, Color(1.0, 1.0, 1.0, 1.0), COLOR_TEXT_OUTLINE, score_font)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, HUD_BAR_HEIGHT)), HUD_BAR_COLOR)
		_draw_centered_text("SCORE %d" % score, Vector2(view_size.x * 0.5, mid_y), 18)


func _draw_quiz_box(view_size: Vector2) -> void:
	var upcoming_target := _get_upcoming_target()
	if upcoming_target == "":
		return
	var box_top: float = HUD_BAR_HEIGHT + QUIZ_BOX_TOP_GAP
	var text: String = upcoming_target
	if quiz_box_texture != null:
		var tex_size := Vector2(quiz_box_texture.get_width(), quiz_box_texture.get_height())
		var scale: float = QUIZ_BOX_HEIGHT / tex_size.y
		var draw_size: Vector2 = tex_size * scale
		var top_left := Vector2(view_size.x * 0.5 - draw_size.x * 0.5, box_top)
		draw_texture_rect(quiz_box_texture, Rect2(top_left, draw_size), false)
		var text_center := Vector2(top_left.x + draw_size.x * QUIZ_TEXT_CENTER_X_FRAC, top_left.y + draw_size.y * QUIZ_TEXT_CENTER_Y_FRAC)
		var max_width: float = draw_size.x * QUIZ_TEXT_MAX_WIDTH_FRAC
		var max_font_size: int = int(round(draw_size.y * 0.20))
		var min_font_size: int = int(round(draw_size.y * 0.10))
		var font_size := _fit_font_size(text, max_width, max_font_size, min_font_size, combo_font)
		_draw_centered_text(text, text_center, font_size, Color(0.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 0.0, 0.0), combo_font)
	else:
		var box_rect := Rect2(Vector2(QUIZ_BOX_MARGIN, box_top), Vector2(view_size.x - QUIZ_BOX_MARGIN * 2.0, QUIZ_BOX_HEIGHT))
		var style := StyleBoxFlat.new()
		style.bg_color = QUIZ_BOX_COLOR
		style.set_corner_radius_all(int(QUIZ_BOX_CORNER_RADIUS))
		draw_style_box(style, box_rect)
		var max_width: float = box_rect.size.x - QUIZ_BOX_MARGIN
		var font_size := _fit_font_size(text, max_width, 22, 14)
		_draw_centered_text(text, box_rect.get_center(), font_size, COLOR_TEXT_DARK, Color(COLOR_TEXT_DARK.r, COLOR_TEXT_DARK.g, COLOR_TEXT_DARK.b, 0.0))


func _draw() -> void:
	var view_size := get_viewport_rect().size
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

	# Right pillar drawn behind the bird (bird occludes it while passing that
	# side), left pillar drawn in front (it occludes the bird while passing
	# that side) — that's what sells the bird actually passing *through* the
	# gate instead of just sliding across a flat picture.
	for g in gates:
		var right_top_tex: Texture2D = gate_right_pillar_textures[_gate_glow_frame_index(g, "top")]
		var right_bottom_tex: Texture2D = gate_right_pillar_textures[_gate_glow_frame_index(g, "bottom")]
		_draw_gate_frame_layer(right_top_tex, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"))
		_draw_gate_frame_layer(right_bottom_tex, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"))

	for g in gates:
		var wall_rect := Rect2(Vector2(g.x, wall_top), Vector2(GATE_WIDTH, WALL_THICKNESS))
		if difficulty == Difficulty.HARD:
			draw_rect(Rect2(Vector2(g.x, g.top_zone_top), Vector2(GATE_WIDTH, g.top_zone_bottom - g.top_zone_top)), COLOR_ZONE)
			draw_rect(Rect2(Vector2(g.x, g.bottom_zone_top), Vector2(GATE_WIDTH, g.bottom_zone_bottom - g.bottom_zone_top)), COLOR_ZONE)
		draw_rect(wall_rect, COLOR_WALL)
		_draw_gate_answer_flag(g.top_code, g.x, g.top_zone_top, g.top_zone_bottom, view_size)
		_draw_gate_answer_flag(g.bottom_code, g.x, g.bottom_zone_top, g.bottom_zone_bottom, view_size)

	_draw_speed_lines()  # behind the bird

	if state != State.READY:
		# Stretch (see _bird_stretch_scale) is a draw-time-only scale around
		# the bird's own center — player_y/PLAYER_X/PLAYER_SIZE never change.
		var stretch: Vector2 = _bird_stretch_scale()
		draw_set_transform(Vector2(PLAYER_X, player_y), 0.0, stretch)
		var bird_texture: Texture2D
		if state == State.GAMEOVER and sad_face_texture != null:
			# Static — no flap cycling once the run has ended.
			bird_texture = sad_face_texture
		else:
			# Same flap_frame_index/cadence either way — happy_flap_elapsed
			# only swaps which 4-frame set it indexes into, right after a
			# gate pass.
			var current_flap_frames: Array[Texture2D] = happy_flap_frames if happy_flap_elapsed >= 0.0 else flap_frames
			bird_texture = current_flap_frames[flap_frame_index]
		draw_texture_rect(bird_texture, Rect2(-PLAYER_VISUAL_SIZE * 0.5, PLAYER_VISUAL_SIZE), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for g in gates:
		var left_top_tex: Texture2D = gate_left_pillar_textures[_gate_glow_frame_index(g, "top")]
		var left_bottom_tex: Texture2D = gate_left_pillar_textures[_gate_glow_frame_index(g, "bottom")]
		_draw_gate_frame_layer(left_top_tex, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"))
		_draw_gate_frame_layer(left_bottom_tex, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"))

	# ---- Layer 3: HUD bar + quiz box (always above background/gate zone) ----
	if state == State.PLAYING or state == State.COUNTDOWN:
		_draw_hud_bar(view_size)
		_draw_quiz_box(view_size)

	# ---- Layer 4: effects layer (top of everything drawn above) ----
	_draw_impact_flashes()
	_draw_sparks()
	_draw_score_pops()
	_draw_combo_popups(view_size)
	_draw_combo_glow(view_size)

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
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var base_scale: float = COUNTDOWN_IMAGE_WIDTH / tex_size.x
	var draw_size: Vector2 = tex_size * base_scale * scale_mult
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


func _draw_centered_text(text: String, center: Vector2, font_size: int, fill_color: Color = COLOR_TEXT, outline_color: Color = COLOR_TEXT_OUTLINE, font: Font = null) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(center.x - text_size.x * 0.5, center.y + text_size.y * 0.25)
	# Dark outline so the light default HUD text still reads over the pastel
	# sky — callers drawing over a light background (the quiz box) pass a
	# dark fill_color instead, at which point the outline just adds a touch
	# of contrast rather than doing the main legibility work.
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, fill_color)


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
func _draw_spaced_right_aligned_text(text: String, right_center: Vector2, font_size: int, extra_spacing: float, fill_color: Color = COLOR_TEXT, outline_color: Color = COLOR_TEXT_OUTLINE, font: Font = null) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	var char_widths: Array[float] = []
	var total_width := 0.0
	for i in range(text.length()):
		var w: float = font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		char_widths.append(w)
		total_width += w
	total_width += extra_spacing * max(0, text.length() - 1)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var cursor_x := right_center.x - total_width
	var y := right_center.y + text_size.y * 0.25
	for i in range(text.length()):
		var ch: String = text[i]
		var pos := Vector2(cursor_x, y)
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(font, pos + offset, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)
		cursor_x += char_widths[i] + extra_spacing


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
