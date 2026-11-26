extends SceneTree

# The space game's rules (2.0, scripts/SpaceRun.gd), driven through the real
# Main the way a run plays.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_space.gd
#
#   1. A run starts with full hearts on a question wave; 2 planets a wave in
#      the first cycle, 3 in the second, then 4; every kind of question has
#      exactly one right planet, and it is the right one: the sum, the hand
#      that beats the shown hand, the slot the arrow points at (or the one
#      opposite for a red arrow). Sums never repeat a label.
#   2. No point touches two slots, and every slot and field corner is on
#      screen below the question box at 16:9 and 20:9.
#   3. A right answer smashes the planet, scores like a gate pass, keeps the
#      hearts and starts the loot: the roulette lands on a gain within the
#      stretch, asteroids fly, and a new question follows.
#   4. A wrong planet, or none, costs a weapon step and the combo, not a heart.
#   5. An asteroid that reaches the ship costs a heart; one shot to pieces
#      scores and costs nothing.
#   6. After QUIZ_PER_CYCLE questions the boss comes; its shots cost a heart;
#      shooting it down scores, ends the cycle and starts FEVER.
#   7. FEVER costs no heart however long the ship sits in its path, and ends
#      on a question.
#   8. Losing the last heart offers the revive; continuing refills the hearts
#      and keeps the score.
#   9. A drag moves the ship by the finger's movement, the touch's emulated
#      mouse twin does not move it again, and it stops at the field's edge.
#
# Runs real waves through Main, which updates the best score and the ad
# counter, so the whole save file is backed up and written back at the end.

const SAVE_PATH := "user://savegame.cfg"
var _fail := 0
var _save_backup: PackedByteArray
var _had_save := false
var m
var sp


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _tick(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(ceil(seconds / dt)):
		if m.state != m.State.PLAYING:
			return
		sp.tick(dt, true, true)
		m._update_hearts(dt)


func _park(where: Vector2) -> void:
	sp.ship_pos = where
	sp.ship_target = where


## Flies the current wave in with the ship parked on `where`.
func _fly_wave_at(where: Vector2) -> Dictionary:
	var w: Dictionary = sp.upcoming_wave()
	_park(where)
	var guard := 0
	while not w.is_empty() and not w.resolved and guard < 2000 and m.state == m.State.PLAYING:
		_tick(1.0 / 60.0)
		guard += 1
	return w


func _correct_pos(w: Dictionary) -> Vector2:
	for p in w.planets:
		if p.correct:
			return p.pos
	return Vector2.ZERO


func _wrong_pos(w: Dictionary) -> Vector2:
	for p in w.planets:
		if not p.correct:
			return p.pos
	return Vector2.ZERO


## Somewhere no planet of the wave touches.
func _clear_pos(w: Dictionary) -> Vector2:
	var reach: float = sp.PLANET_RADIUS + sp.SHIP_HIT_RADIUS
	for c in [Vector2.ZERO, Vector2(2.2, 2.9), Vector2(-2.2, -2.9), Vector2(2.2, -2.9), Vector2(-2.2, 2.9)]:
		var ok := true
		for p in w.planets:
			if c.distance_to(p.pos) <= reach:
				ok = false
		if ok:
			return c
	return Vector2.ZERO


func _power() -> float:
	return float(sp.level) + 3.0 * sp.drones + (0.5 if sp.weapon != sp.Weapon.BLASTER else 0.0)


func _fresh_run() -> void:
	m._reset_game()
	m.state = m.State.PLAYING
	_park(Vector2.ZERO)


## Plays out the loot stretch with the ship out of the asteroids' way where
## it can, then waits for the next question.
func _finish_loot() -> void:
	var guard := 0
	while sp.phase == sp.Phase.LOOT and guard < 1000 and m.state == m.State.PLAYING:
		m.hurt_elapsed = 0.1    # asteroids are checked in 5; here they would only get in the way
		_tick(1.0 / 60.0)
		guard += 1
	m.hurt_elapsed = -1.0


func _run() -> void:
	await process_frame
	await process_frame
	m = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	print("check_space")
	sp = m.space
	_check(sp != null, "Main built the space game")
	if sp == null:
		_finish()
		return
	if not sp.kit_loaded:
		print("  note  no Synty kit (assets/synty_space/ missing) — running on the fallback shapes")
	m.tutorial_active = false
	m.set("tutorial_seen", true)

	# ---- 1 ----
	_fresh_run()
	_check(m.hearts == m.MAX_HEARTS and sp.phase == sp.Phase.QUIZ and not sp.upcoming_wave().is_empty(),
		"a run starts with %d hearts on a question wave" % m.MAX_HEARTS)
	var counts := []
	for c in range(4):
		counts.append(sp.planets_for_cycle(c))
	_check(counts == [2, 3, 4, 4], "planets per wave by cycle: %s" % str(counts))
	var bad := ""
	for c in range(3):
		sp.cycle = c
		for kind in [sp.Kind.MATH, sp.Kind.ARROW, sp.Kind.RPS]:
			for k in range(60):
				sp.waves.clear()
				sp.spawn_wave(kind)
				var w: Dictionary = sp.upcoming_wave()
				var right: Array = w.planets.filter(func(p): return p.correct)
				if w.planets.size() != sp.planets_for_cycle(c) or right.size() != 1:
					bad = "kind %d: %d planets, %d right" % [kind, w.planets.size(), right.size()]
					continue
				var r: Dictionary = right[0]
				match kind:
					sp.Kind.MATH:
						var labels := {}
						for p in w.planets:
							labels[p.label] = true
						var parts: PackedStringArray = str(w.question).split(" ")
						var want: int = int(parts[0]) + int(parts[2]) if parts[1] == "+" else int(parts[0]) - int(parts[2])
						if r.label != str(want) or labels.size() != w.planets.size():
							bad = "%s: right planet says %s, labels %s" % [w.question, r.label, str(labels.keys())]
					sp.Kind.RPS:
						var beats: String = sp.HANDS[(int(w.hand) + 2) % 3]
						if r.label != beats:
							bad = "hand %s: right planet says %s" % [sp.HANDS[w.hand], r.label]
						for p in w.planets:
							if not p.correct and p.label == beats:
								bad = "hand %s: a wrong planet also beats it" % sp.HANDS[w.hand]
					sp.Kind.ARROW:
						var want_slot: int = sp._opposite(int(w.dir)) if w.reverse else int(w.dir)
						if int(r.slot) != want_slot:
							bad = "arrow %d (reverse %s): right planet in slot %d" % [w.dir, str(w.reverse), r.slot]
	sp.cycle = 0
	_check(bad == "", "every question has one right planet and it answers the question%s" % ("" if bad == "" else " — " + bad))

	# ---- 2 ----
	var reach: float = sp.PLANET_RADIUS + sp.SHIP_HIT_RADIUS
	var min_gap := 1e9
	for i in sp.SLOTS.size():
		for j in range(i + 1, sp.SLOTS.size()):
			min_gap = minf(min_gap, (sp.SLOTS[i] as Vector2).distance_to(sp.SLOTS[j]))
	_check(min_gap > 2.0 * reach, "no point touches two slots (closest %.2f apart, reach %.2f)" % [min_gap, reach])
	var off := ""
	var w0 := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	for ratio in [16.0 / 9.0, 20.0 / 9.0]:
		var view := Vector2(w0, round(w0 * ratio))
		sp.fit(view)
		var box: Rect2 = m._quiz_box_rect(view)
		var pts: Array = []
		for s in sp.SLOTS:
			pts.append([s, sp.PLANET_RADIUS])
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			pts.append([c * sp.FIELD_HALF, 0.3])
		for e in pts:
			var s: Vector3 = sp.project(Vector3(e[0].x, e[0].y, 0.0))
			var r: float = s.z * e[1]
			if s.z <= 0.0 or s.y - r < box.end.y + 24.0 or s.y + r > view.y or s.x - r < 0.0 or s.x + r > view.x:
				off += " %s at %.0f:9 -> (%.0f, %.0f) r %.0f;" % [str(e[0]), ratio * 9.0, s.x, s.y, r]
	sp.fit(Vector2(w0, float(ProjectSettings.get_setting("display/window/size/viewport_height"))))
	_check(off == "", "every slot and field corner is on screen, below the question box%s" % off)

	# ---- 3 ----
	_fresh_run()
	var w: Dictionary = sp.upcoming_wave()
	var power0 := _power()
	_fly_wave_at(_correct_pos(w))
	var smashed: bool = w.planets.any(func(p): return p.correct and not p.alive)
	_check(smashed and m.combo == 1 and m.score >= m.SCORE_PER_COMBO and m.hearts == m.MAX_HEARTS,
		"a right answer smashes the planet and scores, hearts kept (combo %d, score %d)" % [m.combo, m.score])
	_check(sp.phase == sp.Phase.LOOT, "and starts the loot stretch")
	_tick(sp.ROULETTE_SPIN + 0.1)
	_check(sp.roulette_applied and _power() > power0, "the roulette lands on a gain (%s, power %.1f -> %.1f)" % [str(sp.roulette_result[1]), power0, _power()])
	var saw_rock := false
	var guard := 0
	while sp.phase == sp.Phase.LOOT and guard < 600:
		m.hurt_elapsed = 0.1
		_tick(1.0 / 60.0)
		saw_rock = saw_rock or not sp.rocks.is_empty()
		guard += 1
	m.hurt_elapsed = -1.0
	_check(saw_rock, "asteroids fly during the loot")
	_check(sp.phase == sp.Phase.QUIZ and not sp.upcoming_wave().is_empty(), "and a new question follows")

	# ---- 4 ----
	sp.level = 4
	var hearts_before: int = m.hearts
	w = sp.upcoming_wave()
	_fly_wave_at(_wrong_pos(w))
	_check(m.hearts == hearts_before and m.combo == 0 and sp.level == 3,
		"a wrong planet costs a weapon level and the combo, not a heart (hearts %d, level %d)" % [m.hearts, sp.level])
	w = sp.upcoming_wave()
	_fly_wave_at(_clear_pos(w))
	_check(m.hearts == hearts_before and sp.level == 2, "touching no planet costs a level too (level %d)" % sp.level)

	# ---- 5 ----
	_fresh_run()
	sp.waves.clear()
	sp._enter(sp.Phase.LOOT)
	sp.rocks.clear()
	sp.fire_timer = 999.0              # no bullets: let it reach the ship
	_park(Vector2(1.0, 1.0))
	sp._spawn_asteroid()
	var rock: Dictionary = sp.rocks[0]
	rock.pos = Vector2(1.0, 1.0)
	guard = 0
	while not rock.judged and guard < 600:
		sp.fire_timer = 999.0
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == m.MAX_HEARTS - 1, "an asteroid that reaches the ship costs a heart (hearts %d)" % m.hearts)
	_fresh_run()
	sp.waves.clear()
	sp._enter(sp.Phase.LOOT)
	sp.rocks.clear()
	sp.level = 8
	_park(Vector2(-1.0, -1.0))
	sp._spawn_asteroid()
	rock = sp.rocks[0]
	rock.pos = Vector2(-1.0, -1.0)
	var score0: int = m.score
	guard = 0
	while not rock.judged and guard < 600:
		_tick(1.0 / 60.0)
		guard += 1
	_check(not rock.alive and m.hearts == m.MAX_HEARTS and m.score > score0, "one shot to pieces scores and costs nothing")

	# ---- 6 ----
	_fresh_run()
	for i in range(sp.QUIZ_PER_CYCLE):
		w = sp.upcoming_wave()
		if w.is_empty():
			break
		if i % 2 == 0:
			_fly_wave_at(_correct_pos(w))
			_finish_loot()
		else:
			_fly_wave_at(_clear_pos(w))
	_check(sp.phase == sp.Phase.BOSS and sp.boss != null, "after %d questions the boss comes" % sp.QUIZ_PER_CYCLE)
	sp.fire_timer = 999.0
	_tick(sp.BOSS_ENTER_TIME + 0.2)
	var hearts_b: int = m.hearts
	guard = 0
	while m.hearts == hearts_b and guard < 600:
		sp.fire_timer = 999.0
		_park(sp.ship_pos)
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == hearts_b - 1, "a boss shot that reaches the ship costs a heart")
	m.hearts = m.MAX_HEARTS
	sp.level = 10
	sp.fire_timer = 0.0
	sp.drones = 2
	sp._sync_drones()
	score0 = m.score
	guard = 0
	while sp.phase == sp.Phase.BOSS and guard < 6000:
		m.hurt_elapsed = 0.1           # the dodging is checked above; here the gun is
		if sp.boss != null:
			_park(Vector2(sp.boss.position.x, sp.boss.position.y).clamp(-sp.FIELD_HALF, sp.FIELD_HALF))
		_tick(1.0 / 60.0)
		guard += 1
	m.hurt_elapsed = -1.0
	_check(sp.phase == sp.Phase.FEVER and sp.cycle == 1 and sp.quiz_index == 0 and m.score >= score0 + sp.BOSS_POINTS,
		"shooting the boss down scores, ends the cycle and starts FEVER (cycle %d)" % sp.cycle)

	# ---- 7 ----
	var hearts_f: int = m.hearts
	_park(Vector2.ZERO)
	_tick(sp.FEVER_DURATION + 0.3)
	_check(m.hearts == hearts_f, "FEVER costs no heart (hearts %d)" % m.hearts)
	_check(sp.phase == sp.Phase.QUIZ and not sp.upcoming_wave().is_empty() and sp.upcoming_wave().planets.size() == 3,
		"and ends on a question, three planets in the second cycle")

	# ---- 8 ----
	_fresh_run()
	m.hearts = 1
	var score_at_death: int = m.score
	sp.waves.clear()
	sp._enter(sp.Phase.LOOT)
	sp.rocks.clear()
	sp.fire_timer = 999.0
	_park(Vector2.ZERO)
	sp._spawn_asteroid()
	sp.rocks[0].pos = Vector2.ZERO
	guard = 0
	while m.state == m.State.PLAYING and guard < 600:
		sp.fire_timer = 999.0
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == 0 and m.state == m.State.GAMEOVER and m.revive_panel.visible, "the last heart offers the revive")
	m._on_revive_continue()
	_check(m.hearts == m.MAX_HEARTS and m.score == score_at_death and not sp.upcoming_wave().is_empty(),
		"continuing refills the hearts, keeps the score and asks a fresh question")
	m.state = m.State.PLAYING

	# ---- 9 ----
	_fresh_run()
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(40, -30)
	sp.handle_input(drag)
	var k: float = sp.DRAG_GAIN / sp.px_per_unit()
	_check(sp.ship_target.distance_to(Vector2(40, 30) * k) < 0.001, "a drag moves the ship by the finger's movement")
	var before_t: Vector2 = sp.ship_target
	var emu := InputEventMouseMotion.new()
	emu.relative = Vector2(40, -30)
	emu.button_mask = MOUSE_BUTTON_MASK_LEFT
	emu.device = InputEvent.DEVICE_ID_EMULATION
	sp.handle_input(emu)
	_check(sp.ship_target == before_t, "its emulated mouse twin does not move it again")
	drag.relative = Vector2(100000, 100000)
	sp.handle_input(drag)
	_check(sp.ship_target == Vector2(sp.FIELD_HALF.x, -sp.FIELD_HALF.y), "and it stops at the field's edge")

	_finish()


func _finish() -> void:
	if m != null:
		m.state = m.State.MODE_SELECT
		m._reset_game()
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	print("check_space: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
