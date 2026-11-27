extends SceneTree

# The space game's rules (2.0, scripts/SpaceRun.gd), driven through the real
# Main the way a run plays.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_space.gd
#
#   1. A run starts with full hearts on a colour pattern with a step in
#      flight; 2 gates a step in the first cycle, 3 in the second, then 4;
#      every step of each kind has exactly one right gate: the one in the
#      pattern's colour (every gate a different colour), the slot the arrow
#      points at (the one opposite for a red arrow), or the one with the
#      sequence's symbol for that step, in order and round again, among
#      distinct symbols, the sequence's others as decoys.
#   2. Each slot sits in its own quarter of the field (the quarter decides
#      the answer), no two gate rings touch, and every slot and field corner
#      is on screen below the question box at 16:9 and 20:9.
#   3. The steps come STEP_GAP apart, several in sight at once. The gate in
#      the ship's quarter lights up, and the ship, off the hole but in the
#      right quarter, is drawn into it: the gate is passed (lit, not
#      broken), it scores and pays stardust, hearts kept. A streak pays more
#      each gate, speeds the world up, and every POWER_EVERY in a row the
#      weapon steps up.
#   4. A wrong gate, or a quarter with no gate, breaks the streak and the
#      combo — the world eases back to PACE_START — and costs no heart, no
#      weapon and no stardust.
#   5. Rocks fly between the steps, never on a slot's centre; one that
#      reaches the ship costs a heart, one shot to pieces scores.
#   6. A pattern with every step right brings the next weapon and FEVER,
#      which pays stardust per smash, costs no heart and leads to the next
#      pattern; one with a miss does not. After PATTERNS_PER_CYCLE patterns
#      the boss comes; its shots cost a heart; shooting it down scores, pays
#      stardust, ends the cycle and starts the next pattern with three gates
#      a step.
#   7. Leaving a run banks its stardust into the saved total, once.
#   8. Losing the last heart offers the revive; continuing refills the hearts,
#      keeps the score and starts the pattern over.
#   9. A drag moves the ship by the finger's movement, the touch's emulated
#      mouse twin does not move it again, and it stops at the field's edge.
#      In a debug build a held arrow key steers it too.
#
# Runs real steps through Main, which updates the best score, the stardust
# and the ad counter, so the whole save file is backed up and written back at
# the end.

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


## Flies the front step in with the ship parked on `where`. The rocks between
## the steps are kept off the ship, since every step but 5 is about gates.
func _fly_wave_at(where: Vector2) -> Dictionary:
	var w: Dictionary = sp.upcoming_wave()
	_park(where)
	var guard := 0
	while not w.is_empty() and not w.resolved and guard < 2000 and m.state == m.State.PLAYING:
		m.hurt_elapsed = 0.1
		_tick(1.0 / 60.0)
		guard += 1
	m.hurt_elapsed = -1.0
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


## In the quarter of a step's right gate, but well off its hole: halfway to
## the field's centre and pushed sideways. Steering into the hole is not
## asked of the player; being in the right quarter is.
func _off_centre_pos(w: Dictionary) -> Vector2:
	var c := _correct_pos(w)
	return c * 0.4 + Vector2(-c.y, c.x).normalized() * 0.5


## Somewhere in a quarter with no gate of the step in it.
func _clear_pos(w: Dictionary) -> Vector2:
	for s in sp.SLOTS.size():
		if not w.planets.any(func(p): return int(p.slot) == s):
			return sp.SLOTS[s]
	return Vector2.ZERO


## Plays the rest of the pattern: the right gate where `right` says so for
## the step's index, a gate-less quarter otherwise. Stops when it ends.
func _play_pattern(right: Callable) -> void:
	var guard := 0
	while sp.phase == sp.Phase.PATTERN and guard < 200 and m.state == m.State.PLAYING:
		var w: Dictionary = sp.upcoming_wave()
		if w.is_empty():
			m.hurt_elapsed = 0.1
			_tick(1.0 / 60.0)
			m.hurt_elapsed = -1.0
		else:
			_fly_wave_at(_correct_pos(w) if right.call(int(sp.steps_done)) else _clear_pos(w))
		guard += 1


func _fresh_run() -> void:
	m._reset_game()
	m.state = m.State.PLAYING
	_park(Vector2.ZERO)


## No more steps: the pattern is held short of its end, so rocks can be
## looked at alone.
func _hold_pattern() -> void:
	for w in sp.waves:
		for p in w.planets:
			p.node.queue_free()
	sp.waves.clear()
	for r in sp.rocks:
		r.node.queue_free()
	sp.rocks.clear()
	sp.steps_spawned = sp.PATTERN_LEN
	sp.steps_done = 0


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
	_check(m.hearts == m.MAX_HEARTS and sp.phase == sp.Phase.PATTERN and sp.pattern_kind == sp.Kind.COLOR
		and not sp.upcoming_wave().is_empty(),
		"a run starts with %d hearts on a colour pattern, a step in flight" % m.MAX_HEARTS)
	var counts := []
	for c in range(4):
		counts.append(sp.planets_for_cycle(c))
	_check(counts == [2, 3, 4, 4], "gates per step by cycle: %s" % str(counts))
	var bad := ""
	for c in range(3):
		sp.cycle = c
		for kind in [sp.Kind.COLOR, sp.Kind.ARROW, sp.Kind.SEQUENCE]:
			for k in range(60):
				sp.pattern_color = k % sp.GATE_COLORS.size()
				if k % 10 == 0:
					sp.pattern_seq = sp._random_symbols(sp.SEQ_LEN[mini(c, sp.SEQ_LEN.size() - 1)])
				sp.steps_spawned = k % 10
				var w: Dictionary = sp._make_step(kind)
				var right: Array = w.planets.filter(func(p): return p.correct)
				if w.planets.size() != sp.planets_for_cycle(c) or right.size() != 1:
					bad = "kind %d: %d gates, %d right" % [kind, w.planets.size(), right.size()]
				else:
					var r: Dictionary = right[0]
					if kind == sp.Kind.COLOR:
						var want: Color = sp.GATE_COLORS[sp.pattern_color]
						var seen := {}
						for p in w.planets:
							seen[p.base_glow] = true
						var rc: Color = r.base_glow
						if not Color(rc.r, rc.g, rc.b).is_equal_approx(Color(want.r, want.g, want.b)) or seen.size() != w.planets.size():
							bad = "colour %d: right gate %s, %d colours among %d gates" % [sp.pattern_color, str(rc), seen.size(), w.planets.size()]
					elif kind == sp.Kind.SEQUENCE:
						var want_sym: int = sp.pattern_seq[(k % 10) % sp.pattern_seq.size()]
						var syms := {}
						for p in w.planets:
							syms[p.symbol] = true
						var dup: bool = syms.size() != w.planets.size()
						# A wrong gate shows another of the sequence's own
						# symbols whenever the sequence has one to spare.
						var decoy_from_seq: bool = w.planets.any(func(p): return not p.correct and sp.pattern_seq.has(p.symbol))
						if int(r.symbol) != want_sym or dup or not decoy_from_seq:
							bad = "sequence %s step %d: right gate %d (want %d), symbols %s" % [str(sp.pattern_seq), k % 10, r.symbol, want_sym, str(syms.keys())]
					else:
						var want_slot: int = sp._opposite(int(w.dir)) if w.reverse else int(w.dir)
						if int(r.slot) != want_slot:
							bad = "arrow %d (reverse %s): right gate in slot %d" % [w.dir, str(w.reverse), r.slot]
				for p in w.planets:
					p.node.free()
	sp.cycle = 0
	sp.steps_spawned = 0
	_check(bad == "", "every step has one right gate and it is the one the pattern asks for%s" % ("" if bad == "" else " — " + bad))

	# ---- 2 ----
	# The quarters decide the answer, so each slot has to sit in its own one,
	# and the four quarters have to share the field out between them.
	var own := true
	for i in sp.SLOTS.size():
		own = own and sp.region_of(sp.SLOTS[i]) == i
	var regions := {}
	for x in range(-10, 11):
		for y in range(-10, 11):
			regions[sp.region_of(Vector2(x / 10.0, y / 10.0) * sp.FIELD_HALF)] = true
	_check(own and regions.size() == 4, "each slot lies in its own quarter of the field, and the field splits four ways")
	# Two gates' outer rings must not meet: diagonal neighbours are the closest.
	var ring: float = sp.GATE_RADIUS * sp.GATE_OUTER_OF_HOLE
	var min_gap := 1e9
	for i in sp.SLOTS.size():
		for j in range(i + 1, sp.SLOTS.size()):
			min_gap = minf(min_gap, (sp.SLOTS[i] as Vector2).distance_to(sp.SLOTS[j]))
	_check(min_gap > 2.0 * ring, "no two gate rings touch (closest %.2f apart, rings %.2f across)" % [min_gap, 2.0 * ring])
	var off := ""
	var w0 := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	for ratio in [16.0 / 9.0, 20.0 / 9.0]:
		var view := Vector2(w0, round(w0 * ratio))
		sp.fit(view)
		var box: Rect2 = m._quiz_box_rect(view)
		var pts: Array = []
		for s in sp.SLOTS:
			pts.append([s, sp.GATE_RADIUS])
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
	var level0: int = sp.level
	var dust0: int = m.run_stardust
	# Flown in from off the hole, in the right quarter, counting what is in
	# sight on the way.
	_park(_off_centre_pos(w))
	var aimed_right := false
	var most_in_sight := 0
	var gap_ok := true
	var guard := 0
	while not w.resolved and guard < 3000 and m.state == m.State.PLAYING:
		aimed_right = aimed_right or w.planets.any(func(p): return p.correct and p.get("aim", false))
		var live: Array = sp.waves.filter(func(x): return not x.resolved)
		most_in_sight = maxi(most_in_sight, live.size())
		for i in range(1, live.size()):
			gap_ok = gap_ok and absf((live[i - 1].z - live[i].z) - sp.STEP_GAP) < 0.01
		m.hurt_elapsed = 0.1
		_tick(1.0 / 60.0)
		guard += 1
	m.hurt_elapsed = -1.0
	_check(most_in_sight >= 2 and gap_ok, "steps come exactly STEP_GAP apart, %d in sight at once" % most_in_sight)
	_check(aimed_right, "the gate in the ship's quarter lights up as the one it will be drawn into")
	var passed: bool = w.planets.any(func(p): return p.correct and not p.alive and p.node.visible)
	_check(passed and m.combo == 1 and m.score >= m.SCORE_PER_COMBO and m.hearts == m.MAX_HEARTS,
		"a ship in the right quarter, off the hole, is drawn into the right gate, passes it (it stays, lit) and scores, hearts kept (combo %d, score %d)" % [m.combo, m.score])
	_check(sp.ship_pos.distance_to(_correct_pos(w)) < 0.01, "and comes out at the gate's centre")
	_check(m.run_stardust == dust0 + sp.STARDUST_PER_GATE, "and pays stardust (%d)" % (m.run_stardust - dust0))
	var pace1: float = sp._pace_target()
	for i in range(sp.POWER_EVERY - 1):
		_fly_wave_at(_correct_pos(sp.upcoming_wave()))
	var paid: int = m.run_stardust - dust0
	var want_paid := 0
	for i in range(1, sp.POWER_EVERY + 1):
		want_paid += sp.STARDUST_PER_GATE * i
	_check(sp.streak == sp.POWER_EVERY and paid == want_paid,
		"a streak pays more each gate (%d in a row: %d, want %d)" % [sp.streak, paid, want_paid])
	_check(sp._pace_target() > pace1 and pace1 > sp.PACE_START,
		"and speeds the world up (pace %.2f -> %.2f -> %.2f)" % [sp.PACE_START, pace1, sp._pace_target()])
	_check(sp.level == level0 + 1, "and %d in a row steps the weapon up (level %d -> %d)" % [sp.POWER_EVERY, level0, sp.level])

	# ---- 4 ----
	var hearts_before: int = m.hearts
	var level_before: int = sp.level
	var dust_before: int = m.run_stardust
	_fly_wave_at(_wrong_pos(sp.upcoming_wave()))
	_check(m.hearts == hearts_before and m.combo == 0 and sp.streak == 0 and sp.level == level_before
		and m.run_stardust == dust_before and is_equal_approx(sp._pace_target(), sp.PACE_START),
		"a wrong gate breaks the streak and the combo, slows the world back down, and costs no heart, weapon or stardust")
	_fly_wave_at(_correct_pos(sp.upcoming_wave()))
	_fly_wave_at(_clear_pos(sp.upcoming_wave()))
	_check(m.hearts == hearts_before and sp.streak == 0 and sp.level == level_before,
		"a quarter with no gate counts as a wrong gate")

	# ---- 5 ----
	# Rocks are random; across a few patterns' worth of gaps some come.
	var rock_bad := ""
	var rocks_seen := 0
	var rock_between := false
	for run in range(3):
		_fresh_run()
		for i in range(5):
			_fly_wave_at(_correct_pos(sp.upcoming_wave()))
			var zs: Array = sp.waves.filter(func(x): return not x.resolved).map(func(x): return x.z)
			for r in sp.rocks:
				if r.judged:
					continue
				rocks_seen += 1
				for s in sp.SLOTS:
					if (r.pos as Vector2).distance_to(s) < sp.ROCK_CLEAR - 0.001:
						rock_bad += " %s near %s;" % [str(r.pos), str(s)]
				for j in range(1, zs.size()):
					rock_between = rock_between or (r.z < zs[j - 1] and r.z > zs[j])
	_check(rocks_seen > 0 and rock_between, "rocks fly between the steps (%d seen)" % rocks_seen)
	_check(rock_bad == "", "and keep off every slot's centre%s" % rock_bad)
	_fresh_run()
	_hold_pattern()
	sp.fire_timer = 999.0              # no bullets: let it reach the ship
	_park(Vector2(1.0, 1.0))
	var rock: Dictionary = sp._spawn_asteroid(Vector2(1.0, 1.0), sp.SPAWN_Z * 0.5)
	guard = 0
	while not rock.judged and guard < 600:
		sp.fire_timer = 999.0
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == m.MAX_HEARTS - 1, "an asteroid that reaches the ship costs a heart (hearts %d)" % m.hearts)
	_fresh_run()
	_hold_pattern()
	sp.level = 8
	_park(Vector2(-1.0, -1.0))
	rock = sp._spawn_asteroid(Vector2(-1.0, -1.0), sp.SPAWN_Z * 0.5)
	var score0: int = m.score
	guard = 0
	while not rock.judged and guard < 600:
		_tick(1.0 / 60.0)
		guard += 1
	_check(not rock.alive and m.hearts == m.MAX_HEARTS and m.score > score0, "one shot to pieces scores and costs nothing")

	# ---- 6 ----
	_fresh_run()
	_play_pattern(func(_i): return true)
	_check(sp.phase == sp.Phase.FEVER and sp.weapon == sp.Weapon.SPREAD,
		"a pattern with every step right brings the next weapon and FEVER (phase %d, weapon %d)" % [sp.phase, sp.weapon])
	var hearts_f: int = m.hearts
	var dust_f: int = m.run_stardust
	m._space_fever_smash()
	_check(m.run_stardust == dust_f + sp.STARDUST_FEVER_SMASH, "a planet smashed in fever pays stardust")
	_park(Vector2.ZERO)
	_tick(sp.FEVER_DURATION + 0.3)
	_check(m.hearts == hearts_f, "FEVER costs no heart (hearts %d)" % m.hearts)
	_check(sp.phase == sp.Phase.PATTERN and sp.steps_done == 0 and not sp.upcoming_wave().is_empty(),
		"and ends on the next pattern")
	_play_pattern(func(i): return i != 4)
	_check(sp.phase == sp.Phase.BOSS and sp.boss != null,
		"a pattern with a miss brings no fever, and after %d patterns the boss comes" % sp.PATTERNS_PER_CYCLE)
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
	sp.weapon = sp.Weapon.SPREAD
	sp.level = 10
	sp.fire_timer = 0.0
	sp.drones = 2
	sp._sync_drones()
	score0 = m.score
	var dust_b: int = m.run_stardust
	guard = 0
	while sp.phase == sp.Phase.BOSS and guard < 6000:
		m.hurt_elapsed = 0.1           # the dodging is checked above; here the gun is
		if sp.boss != null:
			_park(Vector2(sp.boss.position.x, sp.boss.position.y).clamp(-sp.FIELD_HALF, sp.FIELD_HALF))
		_tick(1.0 / 60.0)
		guard += 1
	m.hurt_elapsed = -1.0
	_check(sp.phase == sp.Phase.PATTERN and sp.cycle == 1 and sp.patterns_done == 0
		and m.score >= score0 + sp.BOSS_POINTS and m.run_stardust >= dust_b + sp.STARDUST_BOSS,
		"shooting the boss down scores, pays stardust, ends the cycle and starts the next pattern (cycle %d)" % sp.cycle)
	_check(not sp.upcoming_wave().is_empty() and sp.upcoming_wave().planets.size() == 3,
		"with three gates a step in the second cycle")

	# ---- 7 ----
	var total0: int = m.stardust_total
	m.run_stardust = 7
	m._bank_stardust()
	m._bank_stardust()
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	_check(m.stardust_total == total0 + 7 and m.run_stardust == 0
		and int(cfg.get_value(m.SAVE_SECTION_META, m.SAVE_KEY_STARDUST, -1)) == total0 + 7,
		"leaving a run banks its stardust into the saved total, once (%d -> %d)" % [total0, m.stardust_total])

	# ---- 8 ----
	_fresh_run()
	_fly_wave_at(_correct_pos(sp.upcoming_wave()))
	m.hearts = 1
	var score_at_death: int = m.score
	_hold_pattern()
	sp.fire_timer = 999.0
	_park(Vector2.ZERO)
	sp._spawn_asteroid(Vector2.ZERO, sp.SPAWN_Z * 0.5)
	guard = 0
	while m.state == m.State.PLAYING and guard < 600:
		sp.fire_timer = 999.0
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == 0 and m.state == m.State.GAMEOVER and m.revive_panel.visible, "the last heart offers the revive")
	m._on_revive_continue()
	_check(m.hearts == m.MAX_HEARTS and m.score == score_at_death and sp.steps_done == 0
		and not sp.upcoming_wave().is_empty(),
		"continuing refills the hearts, keeps the score and starts the pattern over")
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
	# The checker always runs as a debug build, which is where the keys steer.
	_park(Vector2.ZERO)
	_hold_pattern()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_LEFT
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for i in 15:
		sp._update_ship(1.0 / 60.0)
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var moved: float = sp.ship_target.x
	for i in 30:
		sp._update_ship(1.0 / 60.0)
	_check(absf(moved + sp.KEY_STEER_SPEED * 0.25) < 0.05 and sp.ship_target.x == moved,
		"in a debug build a held arrow key steers the ship, and letting go stops it (x %.2f)" % moved)

	_finish()


func _finish() -> void:
	if m != null:
		m.state = m.State.MODE_SELECT
		m._reset_game()
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("check_space: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
