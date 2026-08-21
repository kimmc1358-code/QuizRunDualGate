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

const GATE_WIDTH := 130.0
const GATE_SPEED := 130.0  # halved for testing — was 260.0
const WALL_THICKNESS := 14.0

# Parallax sky: solid pastel color base (always seamless — no tiled image to
# seam-match) with individual cloud sprites drifting right-to-left and
# respawning off the right edge once fully clear of the left edge, so a cloud
# is never visibly clipped. Near clouds are bigger/faster/more opaque, far
# clouds smaller/slower/fainter, for a simple depth cue.
const CLOUD_TEXTURE_PATHS := [
	"res://assets/backgrounds/clouds/cloud_a.png",
	"res://assets/backgrounds/clouds/cloud_b.png",
	"res://assets/backgrounds/clouds/cloud_c.png",
]
const CLOUD_NEAR_COUNT := 3
const CLOUD_FAR_COUNT := 3
const CLOUD_NEAR_SPEED := 55.0
const CLOUD_FAR_SPEED := 18.0
const CLOUD_NEAR_SCALE_RANGE := Vector2(1.0, 1.3)
const CLOUD_FAR_SCALE_RANGE := Vector2(0.5, 0.7)
const CLOUD_NEAR_ALPHA := 0.95
const CLOUD_FAR_ALPHA := 0.5
const CLOUD_Y_BAND := Vector2(0.05, 0.85)  # fraction of screen height — spread across most of the sky
const CLOUD_RESPAWN_MARGIN := Vector2(20.0, 120.0)

# Gate visual: the image's hollow center is the real passage and its
# stonework is the obstacle, drawn centered on the precision zone (the
# actual pass/fail window the collision check uses) — same values the
# answer text already keys off, so frame and text stay in sync without
# needing an actual parent node yet. Passage geometry (zone/wall), judging,
# movement, and quiz logic are untouched; this only changes what gets drawn.
#
# Split into three layers, all sharing the same 128x128 canvas so they land
# exactly on top of each other: right pillar (BACK, drawn behind the player
# sprite so the bird occludes it while passing that side), left pillar
# (FRONT, drawn after the bird so it occludes the bird while passing that
# side), and the nameplate box (FRONT, drawn after the left pillar) — the
# box where flag/number answer art will go, split out on its own so
# gate_nameplate_scale below can grow it without resizing the pillar art
# around it. Left+right pillars alone pixel-match the original combined
# gate_frame.png design; adding the nameplate on top reconstructs the full
# thing.
const GATE_PILLAR_LEFT_PATH := "res://assets/gates/custom_gate/gate_pillar_left.png"
const GATE_PILLAR_RIGHT_PATH := "res://assets/gates/custom_gate/gate_pillar_right.png"
const GATE_NAMEPLATE_PATH := "res://assets/gates/custom_gate/gate_nameplate.png"
# This layer's own visual center within its shared 128x128 canvas (measured
# from its opaque-pixel bounding box) — the pivot _draw_gate_nameplate scales
# around, so gate_nameplate_scale grows/shrinks it in place instead of
# drifting relative to the rest of the frame.
const GATE_NAMEPLATE_ANCHOR := Vector2(64.0, 61.5)
# Where in the shared frame canvas (same 0-128 coordinate space the pillars
# use, centered on the zone) GATE_NAMEPLATE_ANCHOR should land — near the
# pillar tops instead of at local y=64 (the zone's own center), so the box
# reads as mounted at the top of the gate rather than floating in the
# middle of the pass-through hole.
const GATE_NAMEPLATE_FRAME_TARGET := Vector2(64.0, 10.0)
# Half the nameplate art's own bbox height (measured 37-85 out of its 128
# canvas, so half of the 48px span) — with GATE_NAMEPLATE_FRAME_TARGET this
# gives the nameplate's rendered top edge in shared frame-canvas units.
const GATE_NAMEPLATE_BBOX_HALF_HEIGHT := 24.0
# Pillar art's lowest opaque pixel (measured bbox bottom) in the shared
# 128x128 canvas — the frame's actual bottom edge, below the zone center.
const GATE_PILLAR_BOTTOM_LOCAL_Y := 118.0
# Safety margin so the FX_GATE_PUNCH_KEYFRAMES peak (+8%) can't push the
# frame's edges past the screen bounds this clamp is meant to guarantee.
const GATE_VISUAL_CLAMP_MARGIN := 1.1
#
# The frame's own display size is FIXED, not phase-scaled — it's the
# container the future flag/number answer art and pass-through FX will be
# built against, so it can't keep shrinking every phase or that art and
# those effects would never fit consistently. Only the actual judged
# target (the translucent zone highlight below) still narrows by phase, as
# it always has; the frame just shows more empty margin around a tighter
# highlighted target in later phases instead of resizing itself.
# Phase 1's zone height (PLAYER_SIZE.y 36 + PHASE_ZONE_MARGIN[0] 60) — the
# largest/most permissive zone, used as a constant sizing reference so the
# frame never rescales itself between phases.
const GATE_VISUAL_REFERENCE_ZONE_HEIGHT := 96.0
@export_range(1.0, 4.0, 0.05) var gate_visual_zone_ratio: float = 2.2
# Independent size multiplier for just the nameplate box (see
# GATE_NAMEPLATE_ANCHOR above) — tune this up to make room for flag/number
# art without also enlarging the pillar art around it.
@export_range(0.5, 2.5, 0.05) var gate_nameplate_scale: float = 1.0

# Sky gradient — colors sampled from the reference (assets/references/sky_gradient),
# top -> mid -> bottom, drawn as two vertex-colored quads for a smooth blend.
const COLOR_SKY_TOP := Color(0.0039, 0.4235, 0.9882)
const COLOR_SKY_MID := Color(0.2392, 0.7137, 0.9922)
const COLOR_SKY_BOTTOM := Color(0.7843, 0.9569, 0.9804)
const COLOR_WALL := Color(0.62, 0.16, 0.16)
const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_TEXT_OUTLINE := Color(0.05, 0.08, 0.12, 0.85)  # keeps HUD text legible over the light sky
const COLOR_ZONE := Color(0.55, 0.75, 0.95, 0.55)

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

# 1. Impact flash — a thin white/cyan ring right at the frame's own outer
# edge, 1-2 frames only, so it never paints over the bird or the center
# passage (no full-screen flash).
const FX_IMPACT_FLASH_DURATION := 0.05
const FX_IMPACT_FLASH_WIDTH := 5.0
const FX_IMPACT_FLASH_MARGIN := 6.0   # ring sits this far outside the frame's own outer edge
const FX_IMPACT_FLASH_COLOR := Color(0.85, 0.98, 1.0, 0.95)

# 2. Gate visual punch — draw-time scale keyframes (time_fraction, scale)
# on the gate sprite only; the collision zone this is centered on never
# moves. 1.00 -> 1.08 -> 0.97 -> 1.00 across FX_GATE_PUNCH_DURATION.
const FX_GATE_PUNCH_DURATION := 0.12   # 100-140ms
const FX_GATE_PUNCH_KEYFRAMES := [
	Vector2(0.0, 1.0),
	Vector2(0.15, 1.08),
	Vector2(0.5, 0.97),
	Vector2(1.0, 1.0),
]

# 7. Gate crystal flash — separate, shorter tint-only envelope layered on
# top of the punch scale above (same sprite, no per-pixel mask without a
# shader, so this brightens the whole frame sprite toward white and back).
const FX_CRYSTAL_FLASH_DURATION := 0.15   # 120-180ms
const FX_CRYSTAL_FLASH_PEAK := 0.85       # peak lerp-to-white amount (0-1)
# Shared per-gate-side timeline length; must stay >= both durations above.
const FX_GATE_TIMELINE_DURATION := 0.15

# 3. Two-stage particle burst: big/immediate, then small/delayed.
const FX_SPARK_TEXTURE_PATH := "res://assets/fx/success_spark.png"
const FX_SPARK_BURST_A_COUNT_RANGE := Vector2i(3, 4)       # big, at 0ms
const FX_SPARK_BURST_A_SCALE_RANGE := Vector2(1.1, 1.6)
const FX_SPARK_BURST_B_COUNT_RANGE := Vector2i(10, 16)     # small, delayed
const FX_SPARK_BURST_B_SCALE_RANGE := Vector2(0.4, 0.8)
const FX_SPARK_BURST_B_DELAY_RANGE := Vector2(0.03, 0.05)  # 30-50ms
const FX_SPARK_LIFETIME_RANGE := Vector2(0.12, 0.28)
const FX_SPARK_SPEED_RANGE := Vector2(50.0, 110.0)         # px/s, outward from gate center
const FX_SPARK_GOLD_CHANCE := 0.25                          # rest split white/cyan
const FX_SPARK_GOLD_TINT := Color(1.0, 0.82, 0.45)
const FX_SPARK_CYAN_TINT := Color(0.75, 0.96, 1.0)
const FX_SPARK_WHITE_TINT := Color(1.0, 1.0, 1.0)
const FX_SPARK_RING_MARGIN := 14.0  # spawn ring sits this far outside the frame's own outer edge

# 5. Speed accent — short thick streaks, fired together with spark burst B.
const FX_SPEED_LINE_COUNT_RANGE := Vector2i(2, 3)
const FX_SPEED_LINE_DURATION := 0.08                # 60-90ms
const FX_SPEED_LINE_LENGTH_RANGE := Vector2(20.0, 40.0)
const FX_SPEED_LINE_THICKNESS := 3.0
const FX_SPEED_LINE_Y_SPREAD := 0.4                 # fraction of PLAYER_VISUAL_SIZE.y either side
const FX_SPEED_LINE_CYAN := Color(0.75, 0.96, 1.0)
const FX_SPEED_LINE_WHITE := Color(1.0, 1.0, 1.0)

# 4. Bird visual stretch — sprite-draw scale only (draw_set_transform in
# _draw()); player_y/player_vel/PLAYER_SIZE are never touched.
const FX_STRETCH_DURATION := 0.09      # 60-100ms, back to 1:1 well inside it
const FX_STRETCH_SCALE_X_PEAK := 1.12  # 1.10-1.14
const FX_STRETCH_SCALE_Y_PEAK := 0.92  # 0.90-0.94
const FX_STRETCH_KEYFRAMES := [        # envelope 0->1->0; peak lands ~60ms in
	Vector2(0.0, 0.0),
	Vector2(0.65, 1.0),
	Vector2(1.0, 0.0),
]

# 6. Screen shake — cubic decay so it's under 1px well before it ends;
# render-only offset on this Node2D's own position (see note above).
const FX_SHAKE_DURATION := 0.09        # 70-100ms total
const FX_SHAKE_PEAK_AMPLITUDE := 2.5   # px, 2-3

# Score pop — kept from the previous pass, unaffected by this redesign.
const FX_SCORE_POP_DURATION := 0.5
const FX_SCORE_POP_RISE := 22.0
const FX_SCORE_POP_COLOR := Color(1.0, 0.93, 0.6)
const FX_SCORE_POP_FONT_SIZE := 20
const FX_SCORE_POP_OFFSET := Vector2(0.0, -18.0)

# 9. Audio hooks — two independent, layerable placeholders (an airy whoosh
# and a crystalline chime), each its own AudioStreamPlayer so they can
# overlap. No sound ships yet; drop files at these paths later and they
# start playing automatically (ResourceLoader.exists guarded) — nothing
# else here needs to change.
const FX_SOUND_WHOOSH_PATH := "res://assets/audio/gate_whoosh.ogg"
const FX_SOUND_CHIME_PATH := "res://assets/audio/gate_chime.ogg"

enum Difficulty { EASY, HARD }

# Precision-zone clearance beyond the player hitbox (Hard mode only). Was
# phase-scaled (shrinking each phase) but that's reverted per feedback —
# _spawn_gate now always uses index 0 regardless of phase. Left as an array
# (not a single float) so the per-phase curve is a one-line change to bring
# back if wanted later.
# Easy mode never uses this — the whole lane stays a safe zone (see _resolve_gate).
const PHASE_ZONE_MARGIN := [60.0, 45.0, 32.0, 20.0]

# Placeholder phase thresholds keyed on gates-passed count — the design doc
# leaves the real curve open (section 11), tune these once that's decided.
const PHASE_GATE_THRESHOLDS := [0, 5, 12, 20]

# Next zone's center is clamped to what's physically reachable from the
# previous zone's center within the spawn-to-judgement travel window, using
# each direction's real max speed (climbing is slower than falling). This
# factor shaves a margin off the theoretical max so it's not a frame-perfect
# reaction-time requirement.
const REACH_SAFETY_FACTOR := 0.85

# Dummy data: 5~10 confusable country-name pairs (real flag art comes later).
const QUIZ_PAIRS := [
	["Korea", "Japan"],
	["Indonesia", "Monaco"],
	["Romania", "Chad"],
	["Ireland", "Ivory Coast"],
	["New Zealand", "Australia"],
	["Norway", "Iceland"],
	["Senegal", "Mali"],
	["Chile", "Thailand"],
]

enum State { READY, COUNTDOWN, PLAYING, GAMEOVER }

var state: int = State.READY
var difficulty: int = Difficulty.HARD  # Only Hard is wired to the UI so far.

# "READY" -> "START" pop-in shown before every *retry* (post-onboarding).
# The very first play (from the READY/onboarding panel) skips straight to
# PLAYING and never touches this — see _on_play_pressed vs _on_restart_pressed.
enum CountdownPhase { READY_TEXT, START_TEXT }
var countdown_phase: int = CountdownPhase.READY_TEXT
var countdown_timer: float = 0.0
const COUNTDOWN_READY_DURATION := 0.6
const COUNTDOWN_START_DURATION := 0.4

var player_y: float = 0.0
var player_vel: float = 0.0

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

var cloud_textures: Array[Texture2D] = []
var clouds: Array = []  # each: {texture, x, y, scale, alpha, speed, near}

var gate_pillar_left_texture: Texture2D
var gate_pillar_right_texture: Texture2D
var gate_nameplate_texture: Texture2D

# Gate-pass FX state (see the const block above for tunables).
var fx_spark_texture: Texture2D
var fx_sparks: Array = []            # each: {pos, vel, scale, rotation, lifetime, elapsed, tint}
var fx_speed_lines: Array = []       # each: {y_offset, length, elapsed, color}
var fx_score_pops: Array = []        # each: {pos, elapsed}
var fx_impact_flashes: Array = []    # each: {pos, radius, elapsed}
var fx_pending_bursts: Array = []    # each: {delay, gate_center} — burst B + speed streaks fire together once delay elapses
var fx_shake_elapsed: float = -1.0   # -1 = inactive
var fx_stretch_elapsed: float = -1.0 # -1 = inactive
var fx_sound_whoosh: AudioStreamPlayer
var fx_sound_chime: AudioStreamPlayer

@onready var ready_panel: Control = $UI/ReadyPanel
@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var final_score_label: Label = $UI/GameOverPanel/FinalScoreLabel
@onready var play_button: Button = $UI/ReadyPanel/PlayButton
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton


func _ready() -> void:
	# Keeps all pixel art crisp at any render scale — draw_texture_rect has no
	# per-call filter option, so this has to be set on the CanvasItem itself.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for path in FLAP_FRAME_PATHS:
		flap_frames.append(load(path))
	for path in CLOUD_TEXTURE_PATHS:
		cloud_textures.append(load(path))
	_init_clouds(get_viewport_rect().size)
	gate_pillar_left_texture = load(GATE_PILLAR_LEFT_PATH)
	gate_pillar_right_texture = load(GATE_PILLAR_RIGHT_PATH)
	gate_nameplate_texture = load(GATE_NAMEPLATE_PATH)
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
	play_button.pressed.connect(_on_play_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	_reset_game()
	_set_state(State.READY)


func _init_clouds(view_size: Vector2) -> void:
	clouds.clear()
	for i in range(CLOUD_FAR_COUNT):
		clouds.append(_make_cloud(view_size, false, randf_range(0.0, view_size.x)))
	for i in range(CLOUD_NEAR_COUNT):
		clouds.append(_make_cloud(view_size, true, randf_range(0.0, view_size.x)))


func _make_cloud(view_size: Vector2, is_near: bool, start_x: float) -> Dictionary:
	var scale_range: Vector2 = CLOUD_NEAR_SCALE_RANGE if is_near else CLOUD_FAR_SCALE_RANGE
	var speed: float = CLOUD_NEAR_SPEED if is_near else CLOUD_FAR_SPEED
	return {
		"texture": cloud_textures[randi() % cloud_textures.size()],
		"x": start_x,
		"y": randf_range(view_size.y * CLOUD_Y_BAND.x, view_size.y * CLOUD_Y_BAND.y),
		"scale": randf_range(scale_range.x, scale_range.y),
		"alpha": CLOUD_NEAR_ALPHA if is_near else CLOUD_FAR_ALPHA,
		"speed": speed * randf_range(0.85, 1.15),
		"near": is_near,
	}


func _update_clouds(delta: float, view_size: Vector2) -> void:
	for c in clouds:
		c.x -= c.speed * delta
		var tex_w: float = c.texture.get_width() * c.scale
		if c.x + tex_w < 0.0:
			# Fully clear of the left edge — respawn past the right edge so
			# it's never visibly clipped popping in or out.
			c.x = view_size.x + randf_range(CLOUD_RESPAWN_MARGIN.x, CLOUD_RESPAWN_MARGIN.y)
			c.y = randf_range(view_size.y * CLOUD_Y_BAND.x, view_size.y * CLOUD_Y_BAND.y)
			c.texture = cloud_textures[randi() % cloud_textures.size()]


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


func _draw_clouds(near: bool) -> void:
	for c in clouds:
		if c.near != near:
			continue
		var tex: Texture2D = c.texture
		var cloud_scale: float = c.scale
		var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * cloud_scale
		draw_texture_rect(tex, Rect2(Vector2(c.x, c.y), size), false, Color(1.0, 1.0, 1.0, c.alpha))


func _gate_frame_top_overhang() -> float:
	# How far above a zone's center the decorative frame's tallest point —
	# the nameplate, mounted near the pillar tops — extends, in world
	# pixels. _spawn_gate insets the top-lane spawn band by this so a zone
	# never rolls close enough to the screen's top edge to push the frame
	# off it; the frame is always drawn centered exactly on the zone (see
	# _draw()), so keeping the frame on-screen this way — instead of
	# clamping the draw position — means the drawn "hole" never drifts
	# away from the actual judged zone.
	var base_scale: float = ((GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / 128.0) * GATE_VISUAL_CLAMP_MARGIN
	return (64.0 - (GATE_NAMEPLATE_FRAME_TARGET.y - GATE_NAMEPLATE_BBOX_HALF_HEIGHT)) * base_scale


func _gate_frame_bottom_overhang() -> float:
	# Same as _gate_frame_top_overhang, for how far below a zone's center
	# the pillars' feet extend — used to inset the bottom-lane spawn band
	# from the screen's bottom edge.
	var base_scale: float = ((GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio) / 128.0) * GATE_VISUAL_CLAMP_MARGIN
	return (GATE_PILLAR_BOTTOM_LOCAL_Y - 64.0) * base_scale


func _draw_gate_frame_layer(texture: Texture2D, center_x: float, center_y: float, punch_scale: float = 1.0, crystal_flash: float = 0.0) -> void:
	if texture == null:
		return
	var target_long_edge: float = GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio
	# punch_scale (see _gate_punch_scale) is a draw-time-only size wobble;
	# crystal_flash (see _gate_crystal_flash) is a draw-time-only tint —
	# neither ever changes the zone/collision geometry this is centered on.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var scale_factor: float = (target_long_edge / max(tex_size.x, tex_size.y)) * punch_scale
	var draw_size: Vector2 = tex_size * scale_factor
	var top_left := Vector2(center_x - draw_size.x * 0.5, center_y - draw_size.y * 0.5)
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.4, 1.4, 1.35), crystal_flash)
	draw_texture_rect(texture, Rect2(top_left, draw_size), false, tint)


func _gate_nameplate_rect(center_x: float, center_y: float, punch_scale: float = 1.0) -> Rect2:
	var tex_size := Vector2(128.0, 128.0)
	if gate_nameplate_texture != null:
		tex_size = Vector2(gate_nameplate_texture.get_width(), gate_nameplate_texture.get_height())
	var target_long_edge: float = GATE_VISUAL_REFERENCE_ZONE_HEIGHT * gate_visual_zone_ratio
	var base_scale: float = (target_long_edge / max(tex_size.x, tex_size.y)) * punch_scale
	var base_top_left := Vector2(center_x - tex_size.x * base_scale * 0.5, center_y - tex_size.y * base_scale * 0.5)
	# GATE_NAMEPLATE_FRAME_TARGET picks where in the shared frame canvas the
	# box should sit (near the pillar tops); GATE_NAMEPLATE_ANCHOR is then
	# used to pivot the box's own art around that point, so
	# gate_nameplate_scale grows/shrinks it in place instead of drifting.
	var anchor_world: Vector2 = base_top_left + GATE_NAMEPLATE_FRAME_TARGET * base_scale
	var draw_scale: float = base_scale * gate_nameplate_scale
	var draw_size: Vector2 = tex_size * draw_scale
	var top_left: Vector2 = anchor_world - GATE_NAMEPLATE_ANCHOR * draw_scale
	return Rect2(top_left, draw_size)


func _draw_gate_nameplate(center_x: float, center_y: float, punch_scale: float = 1.0, crystal_flash: float = 0.0) -> void:
	if gate_nameplate_texture == null:
		return
	var rect := _gate_nameplate_rect(center_x, center_y, punch_scale)
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.4, 1.4, 1.35), crystal_flash)
	draw_texture_rect(gate_nameplate_texture, rect, false, tint)


func _gate_answer_text_pos(center_x: float, center_y: float) -> Vector2:
	# Inside the nameplate box, toward its upper portion — a placeholder
	# spot for the quiz answer text until it's replaced with flag/number
	# art, which will target this same box.
	var rect := _gate_nameplate_rect(center_x, center_y, 1.0)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.38)


func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
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


func _process(delta: float) -> void:
	# Clouds keep drifting on every screen (menu, playing, game over) for a
	# lively backdrop, independent of gameplay state.
	_update_clouds(delta, get_viewport_rect().size)
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
	else:
		_set_state(State.PLAYING)


func _update_playing(delta: float) -> void:
	var view_size := get_viewport_rect().size

	player_vel = min(player_vel + gravity * delta, max_fall_speed)
	player_y += player_vel * delta
	var half_h := PLAYER_SIZE.y * 0.5
	if player_y - half_h < 0.0:
		player_y = half_h
		player_vel = 0.0
	elif player_y + half_h > view_size.y:
		player_y = view_size.y - half_h
		player_vel = 0.0

	for g in gates:
		g.x -= GATE_SPEED * delta
		if not g.resolved and g.x <= PLAYER_X and g.x + GATE_WIDTH >= PLAYER_X:
			_resolve_gate(g, view_size)

	gates = gates.filter(func(g): return g.x + GATE_WIDTH > -10.0)

	# Reveal the next question the instant the active one is cleared (same
	# frame the pass is judged) — no independent timer/cadence in between.
	if state == State.PLAYING and _get_upcoming_target() == "":
		_spawn_gate(view_size)


func _spawn_gate(view_size: Vector2) -> void:
	var pair: Array = QUIZ_PAIRS[randi() % QUIZ_PAIRS.size()]
	var target: String = pair[randi() % 2]
	var other: String = pair[0] if target == pair[1] else pair[1]
	var top_correct: bool = randi() % 2 == 0

	var phase_index := _get_phase_index(gates_passed)
	var wall_top := view_size.y * 0.5 - WALL_THICKNESS * 0.5
	var wall_bottom := view_size.y * 0.5 + WALL_THICKNESS * 0.5
	var margin: float = PHASE_ZONE_MARGIN[0]  # fixed, not phase_index — see comment on PHASE_ZONE_MARGIN
	var zone_height: float = PLAYER_SIZE.y + margin

	# The decorative frame (pillars + nameplate) drawn around a zone is
	# taller than the zone itself — see _gate_frame_top_overhang/
	# _gate_frame_bottom_overhang — so a zone centered too close to the
	# outer screen edge would push the frame off-screen. Rather than
	# clamping the frame's draw position at render time (which would make
	# the drawn "hole" stop matching the actual judged zone), inset the
	# allowed spawn band here so the zone itself never rolls close enough
	# to need that: frame and zone always land in exactly the same place.
	var top_lane_band_top: float = max(0.0, _gate_frame_top_overhang() - zone_height * 0.5)
	var bottom_lane_band_bottom: float = view_size.y - max(0.0, _gate_frame_bottom_overhang() - zone_height * 0.5)

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

	gates.append({
		"x": PLAYER_X + base_gate_spacing,
		"top_text": target if top_correct else other,
		"bottom_text": other if top_correct else target,
		"top_correct": top_correct,
		"target": target,
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
	var wall_top := view_size.y * 0.5 - WALL_THICKNESS * 0.5
	var wall_bottom := view_size.y * 0.5 + WALL_THICKNESS * 0.5
	var half_h := PLAYER_SIZE.y * 0.5
	var p_top := player_y - half_h
	var p_bottom := player_y + half_h

	if p_bottom > wall_top and p_top < wall_bottom:
		_game_over()
		return

	var in_top := player_y < view_size.y * 0.5
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
		score += 10 * combo
		flash_color = Color(0.3, 0.8, 0.4, 0.35)
		flash_time = FLASH_DURATION
		_play_gate_success_fx(g, in_top)
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


func _gate_crystal_flash(g: Dictionary, side: String) -> float:
	# 0 when idle; otherwise a 0 -> 1 -> 0 pulse across
	# FX_CRYSTAL_FLASH_DURATION, independent of the punch-scale timing above.
	var elapsed := _gate_fx_elapsed(g, side)
	if elapsed < 0.0 or elapsed >= FX_CRYSTAL_FLASH_DURATION:
		return 0.0
	var envelope: float = sin(PI * (elapsed / FX_CRYSTAL_FLASH_DURATION))
	return envelope * FX_CRYSTAL_FLASH_PEAK * successFxIntensity


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

	if fx_shake_elapsed >= 0.0:
		fx_shake_elapsed += delta
		if fx_shake_elapsed >= FX_SHAKE_DURATION:
			fx_shake_elapsed = -1.0
			position = Vector2.ZERO
		else:
			# Cubic decay: drops under 1px well before FX_SHAKE_DURATION ends.
			var t: float = fx_shake_elapsed / FX_SHAKE_DURATION
			var amp: float = FX_SHAKE_PEAK_AMPLITUDE * pow(1.0 - t, 3) * clampf(successFxIntensity, 0.0, 2.0)
			position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))


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


func _game_over() -> void:
	state = State.GAMEOVER
	flash_color = Color(0.8, 0.15, 0.15, 0.45)
	flash_time = FLASH_DURATION
	final_score_label.text = "SCORE: %d" % score
	gameover_panel.visible = true


func _on_play_pressed() -> void:
	# First-ever play for this mode+difficulty: onboarding flow stays as-is,
	# straight into PLAYING with no READY/START pop-in.
	_reset_game()
	_set_state(State.PLAYING)


func _on_restart_pressed() -> void:
	# Retry after onboarding is already done: short READY -> START beat
	# before gameplay actually starts.
	_reset_game()
	countdown_phase = CountdownPhase.READY_TEXT
	countdown_timer = COUNTDOWN_READY_DURATION
	_set_state(State.COUNTDOWN)


func _reset_game() -> void:
	var view_size := get_viewport_rect().size
	player_y = view_size.y * 0.5
	player_vel = 0.0
	score = 0
	combo = 0
	gates_passed = 0
	gates.clear()
	flash_time = 0.0
	last_zone_center = player_y
	fx_sparks.clear()
	fx_speed_lines.clear()
	fx_score_pops.clear()
	fx_impact_flashes.clear()
	fx_pending_bursts.clear()
	fx_shake_elapsed = -1.0
	fx_stretch_elapsed = -1.0
	position = Vector2.ZERO  # in case a restart lands mid-shake
	# First question is revealed immediately so it's visible for the full
	# spawn-to-player travel time, well over the 1.5-2s minimum preview.
	_spawn_gate(view_size)


func _set_state(new_state: int) -> void:
	state = new_state
	ready_panel.visible = state == State.READY
	gameover_panel.visible = state == State.GAMEOVER


func _draw() -> void:
	var view_size := get_viewport_rect().size
	_draw_sky_gradient(view_size)
	_draw_clouds(false)  # far clouds first, near clouds drawn on top below
	_draw_clouds(true)

	var wall_top := view_size.y * 0.5 - WALL_THICKNESS * 0.5
	var wall_bottom := view_size.y * 0.5 + WALL_THICKNESS * 0.5

	# Right pillar drawn behind the bird (bird occludes it while passing that
	# side), left pillar drawn in front (it occludes the bird while passing
	# that side) — that's what sells the bird actually passing *through* the
	# gate instead of just sliding across a flat picture.
	for g in gates:
		_draw_gate_frame_layer(gate_pillar_right_texture, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"), _gate_crystal_flash(g, "top"))
		_draw_gate_frame_layer(gate_pillar_right_texture, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"), _gate_crystal_flash(g, "bottom"))

	for g in gates:
		var wall_rect := Rect2(Vector2(g.x, wall_top), Vector2(GATE_WIDTH, WALL_THICKNESS))
		if difficulty == Difficulty.HARD:
			draw_rect(Rect2(Vector2(g.x, g.top_zone_top), Vector2(GATE_WIDTH, g.top_zone_bottom - g.top_zone_top)), COLOR_ZONE)
			draw_rect(Rect2(Vector2(g.x, g.bottom_zone_top), Vector2(GATE_WIDTH, g.bottom_zone_bottom - g.bottom_zone_top)), COLOR_ZONE)
		draw_rect(wall_rect, COLOR_WALL)

	_draw_speed_lines()  # behind the bird

	if state != State.READY:
		# Stretch (see _bird_stretch_scale) is a draw-time-only scale around
		# the bird's own center — player_y/PLAYER_X/PLAYER_SIZE never change.
		var stretch: Vector2 = _bird_stretch_scale()
		draw_set_transform(Vector2(PLAYER_X, player_y), 0.0, stretch)
		draw_texture_rect(flap_frames[flap_frame_index], Rect2(-PLAYER_VISUAL_SIZE * 0.5, PLAYER_VISUAL_SIZE), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for g in gates:
		_draw_gate_frame_layer(gate_pillar_left_texture, g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"), _gate_crystal_flash(g, "top"))
		_draw_gate_frame_layer(gate_pillar_left_texture, g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"), _gate_crystal_flash(g, "bottom"))
		_draw_gate_nameplate(g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5, _gate_punch_scale(g, "top"), _gate_crystal_flash(g, "top"))
		_draw_gate_nameplate(g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5, _gate_punch_scale(g, "bottom"), _gate_crystal_flash(g, "bottom"))
		# Testing placeholder inside the nameplate box — swap for flag/number
		# art later, targeting the same _gate_answer_text_pos/_gate_nameplate_rect spot.
		_draw_centered_text(g.top_text, _gate_answer_text_pos(g.x + GATE_WIDTH * 0.5, (g.top_zone_top + g.top_zone_bottom) * 0.5), 20)
		_draw_centered_text(g.bottom_text, _gate_answer_text_pos(g.x + GATE_WIDTH * 0.5, (g.bottom_zone_top + g.bottom_zone_bottom) * 0.5), 20)

	# UI/FX layer — impact ring, sparks, and the score pop, on top of everything else.
	_draw_impact_flashes()
	_draw_sparks()
	_draw_score_pops()

	if state == State.PLAYING or state == State.COUNTDOWN:
		var upcoming_target := _get_upcoming_target()
		if upcoming_target != "":
			_draw_centered_text("TARGET: %s" % upcoming_target, Vector2(view_size.x * 0.5, 30.0), 22)

	if state == State.PLAYING or state == State.COUNTDOWN:
		var phase := _get_phase_index(gates_passed) + 1
		_draw_centered_text("SCORE %d   COMBO x%d   PHASE %d" % [score, combo, phase], Vector2(view_size.x * 0.5, view_size.y - 24.0), 18)

	if state == State.COUNTDOWN:
		if countdown_phase == CountdownPhase.READY_TEXT:
			_draw_centered_text("READY", Vector2(view_size.x * 0.5, view_size.y * 0.5), 36)
		else:
			var t: float = 1.0 - (countdown_timer / COUNTDOWN_START_DURATION)
			var pop_font_size: int = int(round(36.0 * _pop_scale(t)))
			_draw_centered_text("START", Vector2(view_size.x * 0.5, view_size.y * 0.5), pop_font_size)

	if flash_time > 0.0:
		var a: float = flash_color.a * (flash_time / FLASH_DURATION)
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(flash_color.r, flash_color.g, flash_color.b, a))


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
			return g.target
	return ""


func _draw_centered_text(text: String, center: Vector2, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(center.x - text_size.x * 0.5, center.y + text_size.y * 0.25)
	# Dark outline so the light HUD text still reads over the pastel sky,
	# not just over the darker gate rects.
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT_OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT)
