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

const PLAYER_SIZE := Vector2(36, 36)
const PLAYER_VISUAL_SIZE := Vector2(56, 56)  # sprite drawn larger than the hitbox
const PLAYER_X := 130.0

const GATE_WIDTH := 130.0
const GATE_SPEED := 130.0  # halved for testing — was 260.0
const WALL_THICKNESS := 14.0

const COLOR_BG := Color(0.10, 0.10, 0.12)
const COLOR_GATE := Color(0.32, 0.32, 0.38)
const COLOR_GATE_BORDER := Color(0.55, 0.55, 0.62)
const COLOR_WALL := Color(0.62, 0.16, 0.16)
const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_ZONE := Color(0.55, 0.75, 0.95, 0.55)

enum Difficulty { EASY, HARD }

# Precision-zone clearance beyond the player hitbox, by phase (Hard mode only).
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

@onready var player_texture: Texture2D = load("res://assets/characters/bluebird_reference_match/south.png")
@onready var ready_panel: Control = $UI/ReadyPanel
@onready var gameover_panel: Control = $UI/GameOverPanel
@onready var final_score_label: Label = $UI/GameOverPanel/FinalScoreLabel
@onready var play_button: Button = $UI/ReadyPanel/PlayButton
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	_reset_game()
	_set_state(State.READY)


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
	if state == State.PLAYING:
		_update_playing(delta)
	elif state == State.COUNTDOWN:
		_update_countdown(delta)
	if flash_time > 0.0:
		flash_time = max(0.0, flash_time - delta)
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
	var margin: float = PHASE_ZONE_MARGIN[phase_index]
	var zone_height: float = PLAYER_SIZE.y + margin

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
		top_zone = _random_reachable_zone(0.0, wall_top, zone_height, last_zone_center, up_reach, down_reach, bottom_near_edge, down_reach)
		bottom_zone = _random_zone(wall_bottom, view_size.y, zone_height)
		last_zone_center = (top_zone.x + top_zone.y) * 0.5
	else:
		# Escaping bottom -> top next time needs up_reach (the tighter one).
		bottom_zone = _random_reachable_zone(wall_bottom, view_size.y, zone_height, last_zone_center, up_reach, down_reach, top_near_edge, up_reach)
		top_zone = _random_zone(0.0, wall_top, zone_height)
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
	else:
		_game_over()


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
	# First question is revealed immediately so it's visible for the full
	# spawn-to-player travel time, well over the 1.5-2s minimum preview.
	_spawn_gate(view_size)


func _set_state(new_state: int) -> void:
	state = new_state
	ready_panel.visible = state == State.READY
	gameover_panel.visible = state == State.GAMEOVER


func _draw() -> void:
	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), COLOR_BG)

	var wall_top := view_size.y * 0.5 - WALL_THICKNESS * 0.5
	var wall_bottom := view_size.y * 0.5 + WALL_THICKNESS * 0.5

	for g in gates:
		var top_rect := Rect2(Vector2(g.x, 0.0), Vector2(GATE_WIDTH, wall_top))
		var bottom_rect := Rect2(Vector2(g.x, wall_bottom), Vector2(GATE_WIDTH, view_size.y - wall_bottom))
		var wall_rect := Rect2(Vector2(g.x, wall_top), Vector2(GATE_WIDTH, WALL_THICKNESS))
		draw_rect(top_rect, COLOR_GATE)
		draw_rect(bottom_rect, COLOR_GATE)
		if difficulty == Difficulty.HARD:
			draw_rect(Rect2(Vector2(g.x, g.top_zone_top), Vector2(GATE_WIDTH, g.top_zone_bottom - g.top_zone_top)), COLOR_ZONE)
			draw_rect(Rect2(Vector2(g.x, g.bottom_zone_top), Vector2(GATE_WIDTH, g.bottom_zone_bottom - g.bottom_zone_top)), COLOR_ZONE)
		draw_rect(top_rect, COLOR_GATE_BORDER, false, 2.0)
		draw_rect(bottom_rect, COLOR_GATE_BORDER, false, 2.0)
		draw_rect(wall_rect, COLOR_WALL)
		_draw_centered_text(g.top_text, Vector2(g.x + GATE_WIDTH * 0.5, wall_top * 0.5), 20)
		_draw_centered_text(g.bottom_text, Vector2(g.x + GATE_WIDTH * 0.5, wall_bottom + (view_size.y - wall_bottom) * 0.5), 20)

	if state != State.READY:
		draw_texture_rect(player_texture, Rect2(Vector2(PLAYER_X - PLAYER_VISUAL_SIZE.x * 0.5, player_y - PLAYER_VISUAL_SIZE.y * 0.5), PLAYER_VISUAL_SIZE), false)

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
	draw_string(font, Vector2(center.x - text_size.x * 0.5, center.y + text_size.y * 0.25), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT)
