extends SceneTree

# The space game's rules (2.0, scripts/SpaceRun.gd), driven through the real
# Main the way a run plays.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_space.gd
#
#   1. A run starts with full hearts on a colour pattern with a step in
#      flight. Every pattern in the bank (SpaceRun.BANK), at every level,
#      puts out the gates the bank gives it and the right gates the pattern
#      asks for: COLOR the step's colour, changing exactly every `switch`
#      steps; MIX the pattern's colour, or on an avoid step every gate but
#      that one (avoid steps in MIX only, at every level); SPOT the one gate
#      whose colour is not the box's dot for its slot; MEMORY the round's
#      colour for that step, rounds of `len` covering the pattern with no
#      colour twice in a row; ARROW the slot the arrow points at (the one
#      opposite for a red arrow). Every gate in a step a different colour.
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
#   5. No rocks fly between the steps (taken out on 2026-11-27); an
#      asteroid spawned by hand still costs a heart when it reaches the
#      ship and scores when shot to pieces. A pattern holds the guns, and a
#      power-up fires one short volley; FEVER opens them. At the fastest the world goes in
#      a pattern, a late cycle at full streak, a step is still STEP_FLOOR
#      seconds or more.
#   6. FEVER lasts FEVER_PER_RIGHT a right gate of the pattern before it,
#      with a bonus for all of them, and does not come under FEVER_MIN_RIGHT.
#      A pattern with every step right brings the next weapon and its whole
#      FEVER, which pays stardust per smash, costs no heart and leads to the
#      next pattern; one with too few right goes on without. After PATTERNS_PER_CYCLE patterns
#      the boss comes; its shots cost a heart; shooting it down scores, pays
#      stardust, ends the cycle and starts the next pattern with three gates
#      a step.
#   7. Leaving a run banks its stardust into the saved total, once.
#   8. Losing the last heart ends the run straight on the game over popup;
#      there is no revive since 2026-11-28.
#   9. A drag moves the ship by the finger's movement, the touch's emulated
#      mouse twin does not move it again, and it stops at the field's edge.
#      In a debug build a held arrow key steers it too.
#
# Runs real steps through Main, which updates the best score, the stardust
# and the ad counter, so the whole save file is backed up and written back at
# the end.

const SAVE_PATH := "user://savegame.cfg"
## The least time a step may take, at a late cycle and a full streak: about
## 0.4 s to read, 0.3 s to find and 0.4 s to steer, and a little over.
## Below this the owner found it too hard (2026-11-27).
const STEP_FLOOR := 1.2
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
	for s in sp.LAYOUT_SLOTS[int(w.get("layout", 0))]:
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
	var bad := ""
	var gates_bad := ""
	var avoids := {}
	var colour_switches := {}
	var spot_hidden := {}
	# A gate's colour as an index into GATE_COLORS, read back off its glow.
	var color_of := func(p: Dictionary) -> int:
		var g: Color = p.base_glow
		for i in sp.GATE_COLORS.size():
			var gc: Color = sp.GATE_COLORS[i]
			if Color(g.r, g.g, g.b).is_equal_approx(Color(gc.r, gc.g, gc.b)):
				return i
		return -1
	# Every pattern in the bank at every level, read off the bank itself.
	var layout_bad := ""
	var layouts_seen := {}
	# The arrows adding up to each grid corner, worked out from where the
	# corner is rather than read from CORNER_PARTS.
	var parts_of := func(slot: int) -> Array:
		var at: Vector2 = sp.SLOTS[slot]
		return [2 if at.y > 0.0 else 3, 0 if at.x < 0.0 else 1]
	for kind in sp.BANK.keys():
		for li in (sp.BANK[kind] as Array).size():
			var level: int = li + 1
			var spec: Dictionary = sp.BANK[kind][li]
			sp.pattern_kind = kind
			sp.pattern_level = level
			var key := "%s L%d" % [sp.Kind.keys()[kind], level]
			var coloured: bool = kind in [sp.Kind.COLOR, sp.Kind.MIX, sp.Kind.SPOT, sp.Kind.MEMORY, sp.Kind.SHELL]
			layouts_seen[key] = {}
			for k in range(60):
				if k % 10 == 0:
					sp._prepare_pattern()
				sp.steps_spawned = k % 10
				var w: Dictionary = sp._make_step(kind)
				var n: int = w.planets.size()
				var right: Array = w.planets.filter(func(p): return p.correct)
				var wrong: Array = w.planets.filter(func(p): return not p.correct)
				var colours := {}
				for p in w.planets:
					colours[color_of.call(p)] = true
				layouts_seen[key][int(w.layout)] = true
				# Every gate stands in a slot of the step's own layout.
				var own: Array = sp.LAYOUT_SLOTS[int(w.layout)]
				if not w.planets.all(func(p): return own.has(int(p.slot))):
					layout_bad = "%s: a gate outside layout %d" % [key, w.layout]
				if n != int(spec.gates):
					gates_bad = "%s: %d gates, the bank says %d" % [key, n, spec.gates]
				elif w.avoid:
					avoids[key] = avoids.get(key, 0) + 1
					# Anything but what the box names: n - 1 right, and the one
					# wrong gate is the named colour or the named way.
					var named_ok: bool = false
					if kind == sp.Kind.MIX:
						named_ok = wrong.size() == 1 and color_of.call(wrong[0]) == sp.pattern_color and colours.size() == n
					elif kind == sp.Kind.ARROW_MIX:
						named_ok = wrong.size() == 1 and int(wrong[0].slot) == int(w.dir)
					if not named_ok:
						bad = "%s avoid: %d wrong among %d gates" % [key, wrong.size(), n]
				elif right.size() != 1:
					bad = "%s: %d gates, %d right" % [key, n, right.size()]
				elif kind in [sp.Kind.COLOR, sp.Kind.MIX, sp.Kind.MEMORY, sp.Kind.SHELL]:
					# Read off the pattern's own lists here, not through
					# memory_item, which is part of what is being checked.
					var want: int = sp.pattern_color
					if kind == sp.Kind.COLOR:
						want = int(sp.pattern_colors[k % 10])
					elif kind == sp.Kind.MEMORY:
						var size: int = int(spec.len)
						want = int(sp.pattern_rounds[(k % 10) / size][(k % 10) % size])
					if color_of.call(right[0]) != want or colours.size() != n:
						bad = "%s colour %d: right gate %d, %d colours among %d gates" % [key, want, color_of.call(right[0]), colours.size(), n]
				elif kind == sp.Kind.SPOT:
					# The box's dot matches its gate everywhere but at the
					# right gate, and shows nothing where there is no gate.
					var dots: Array = w.spot
					for s in sp.SLOTS.size():
						var gate: Array = w.planets.filter(func(p): return int(p.slot) == s)
						if gate.is_empty():
							if int(dots[s]) != -1:
								bad = "%s: a dot at empty slot %d" % [key, s]
						elif (int(dots[s]) == color_of.call(gate[0])) == bool(gate[0].correct) or int(dots[s]) < 0:
							bad = "%s %s: slot %d dot %d, gate %d, right %s" % [key, str(dots), s, dots[s], color_of.call(gate[0]), str(gate[0].correct)]
					if colours.size() != n:
						bad = "%s: %d colours among %d gates" % [key, colours.size(), n]
				else:
					var r: Dictionary = right[0]
					var want_slot: int = int(w.dir)
					if kind == sp.Kind.ARROW_MEMORY:
						var size: int = int(spec.len)
						want_slot = int(sp.pattern_rounds[(k % 10) / size][(k % 10) % size])
						# A diagonal can only be flown on the grid.
						if (want_slot >= 4) != (int(w.layout) == sp.Layout.GRID):
							layout_bad = "%s: direction %d on layout %d" % [key, want_slot, w.layout]
					if kind == sp.Kind.ARROW_SUM:
						var got: Array = (w.parts as Array).duplicate()
						got.sort()
						var expect: Array = parts_of.call(int(r.slot))
						expect.sort()
						if int(w.layout) != sp.Layout.GRID or got != expect:
							bad = "%s: parts %s for corner %d" % [key, str(w.parts), r.slot]
					if int(r.slot) != want_slot:
						bad = "%s: the box points at %d, the right gate is in %d" % [key, want_slot, r.slot]
				for p in w.planets:
					p.node.free()
			if kind == sp.Kind.COLOR:
				# The colour changes exactly every `switch` steps, never to itself.
				var cols: Array = sp.pattern_colors
				var every: int = int(spec.switch)
				var ok: bool = cols.size() == sp.PATTERN_LEN
				for i in range(1, cols.size()):
					var changes: bool = cols[i] != cols[i - 1]
					ok = ok and changes == (every > 0 and i % every == 0)
				colour_switches[key] = ok
			if kind == sp.Kind.SPOT:
				spot_hidden[key] = float(spec.hide)
			# The layouts the level asks for, and no other: a mixed level shows
			# both over sixty steps, ARROW_SUM only the grid.
			var asked: int = int(spec.get("layout", sp.Layout.DIAMOND))
			var seen: Dictionary = layouts_seen[key]
			var fine: bool = seen.keys() == [asked]
			if kind == sp.Kind.ARROW_SUM:
				fine = seen.keys() == [sp.Layout.GRID]
			elif asked == sp.Layout.MIXED:
				fine = seen.has(sp.Layout.DIAMOND) and seen.has(sp.Layout.GRID)
			if not fine:
				layout_bad = "%s: layouts %s, asked %d" % [key, str(seen.keys()), asked]
	sp.pattern_kind = sp.Kind.COLOR
	sp.pattern_level = 1
	sp.steps_spawned = 0
	_check(gates_bad == "", "every pattern at every level puts out the gates the bank gives it%s" % ("" if gates_bad == "" else " — " + gates_bad))
	_check(bad == "", "every step has its right gates and they are the ones the pattern asks for%s" % ("" if bad == "" else " — " + bad))
	_check(layout_bad == "", "every step stands in one layout, the one its level asks for, a diagonal only on the grid%s" % ("" if layout_bad == "" else " — " + layout_bad))
	# SHELL: once the swaps are done the colours are out, every gate stands
	# in a slot of its own, and the right gate is wherever the swaps, followed
	# here one by one, took the gate that started in the right colour. Once
	# judged, the colours are back.
	var shell_bad := ""
	for li in (sp.BANK[sp.Kind.SHELL] as Array).size():
		sp.pattern_kind = sp.Kind.SHELL
		sp.pattern_level = li + 1
		for t in 20:
			sp._prepare_pattern()
			sp.steps_spawned = 0
			var w: Dictionary = sp._make_step(sp.Kind.SHELL)
			var where: Array = (w.shell.start as Array).duplicate()
			for s in w.shell.swaps:
				var keep: int = where[s[0]]
				where[s[0]] = where[s[1]]
				where[s[1]] = keep
			var right_i: int = w.planets.find(w.planets.filter(func(p): return p.correct)[0])
			for p in w.planets:
				p.z = sp.SPAWN_Z * (1.0 - (sp.SHELL_END + 0.01))
			sp._shell_place(w)
			var slots: Array = w.planets.map(func(p): return int(p.slot))
			var unique := {}
			for s in slots:
				unique[s] = true
			var swaps_ok: bool = (w.shell.swaps as Array).size() == int(sp.BANK[sp.Kind.SHELL][li].swaps)
			var placed_ok: bool = w.planets.all(func(p): return (p.base_glow as Color) == sp.GATE_GLOW and (p.pos as Vector2).is_equal_approx(sp.SLOTS[int(p.slot)]))
			if not swaps_ok or unique.size() != slots.size() or int(w.planets[right_i].slot) != int(where[right_i]) or not placed_ok:
				shell_bad = "SHELL L%d: slots %s, right gate in %d, want %d" % [li + 1, str(slots), w.planets[right_i].slot, where[right_i]]
			sp._shell_reveal(w)
			if color_of.call(w.planets[right_i]) != sp.pattern_color:
				shell_bad = "SHELL L%d: the right gate does not show its colour again" % (li + 1)
			for p in w.planets:
				p.node.free()
	sp.pattern_kind = sp.Kind.COLOR
	sp.pattern_level = 1
	_check(shell_bad == "", "SHELL hides the colours, swaps the gates into slots of their own, the right gate where the swaps took it, and shows the colours again once judged%s" % ("" if shell_bad == "" else " — " + shell_bad))
	var avoid_levels: int = (sp.BANK[sp.Kind.MIX] as Array).size() + (sp.BANK[sp.Kind.ARROW_MIX] as Array).size()
	_check(avoids.keys().all(func(k): return k.begins_with("MIX") or k.begins_with("ARROW_MIX")) and avoids.size() == avoid_levels,
		"avoid steps come in MIX and ARROW_MIX only, at every one of their levels (%s)" % str(avoids))
	_check(colour_switches.values().all(func(v): return v),
		"COLOR's target colour changes exactly every `switch` steps (%s)" % str(colour_switches))
	var repeat := false
	var sizes_ok := true
	for spec in sp.BANK[sp.Kind.MEMORY]:
		for t in 30:
			var rounds: Array = sp._memory_rounds(int(spec.len), range(sp.GATE_COLORS.size()))
			var flat: Array = []
			for rd in rounds:
				sizes_ok = sizes_ok and rd.size() == int(spec.len)
				flat.append_array(rd)
			sizes_ok = sizes_ok and flat.size() >= sp.PATTERN_LEN
			for i in range(1, flat.size()):
				repeat = repeat or flat[i] == flat[i - 1]
	_check(sizes_ok and not repeat, "memory rounds cover the pattern, `len` colours each at every level, never one colour twice in a row")

	# MEMORY's time to learn a round: at full streak speed, where a step is
	# barely more than a second away, the top level's round still stays up
	# MEMORY_SECONDS_EACH a colour before its first gate; the world is back
	# to full speed for the steps flown from memory.
	_fresh_run()
	_hold_pattern()
	var top: int = (sp.BANK[sp.Kind.MEMORY] as Array).size()
	sp._begin_pattern(sp.Kind.MEMORY, top)
	var first: Dictionary = sp.upcoming_wave()
	var learn := 0.0
	var dt := 1.0 / 60.0
	while not first.resolved and learn < 20.0 and m.state == m.State.PLAYING:
		sp.streak = 10
		sp.pace = sp.PACE_MAX
		m.hurt_elapsed = 0.1
		_tick(dt)
		learn += dt
	var need: float = sp.memory_len() * sp.MEMORY_SECONDS_EACH
	# Past the hold a right pass brings (HITSTOP_TIME), when the world moves again.
	_tick(sp.HITSTOP_TIME + dt * 2.0)
	m.hurt_elapsed = -1.0
	_check(learn >= need - 0.05 and sp.memory_slow == 1.0,
		"a %d-colour round is up %.2f s before its first gate at full speed (at least %.1f), then full speed again" % [sp.memory_len(), learn, need])

	# ---- 2 ----
	# The quarters decide the answer, so in each layout each slot has to sit
	# in its own one, and the four quarters have to share the field out.
	var own := true
	var splits := true
	for layout in [sp.Layout.DIAMOND, sp.Layout.GRID]:
		var slots: Array = sp.LAYOUT_SLOTS[layout]
		for s in slots:
			own = own and sp.region_of(sp.SLOTS[s], layout) == s
		var regions := {}
		for x in range(-10, 11):
			for y in range(-10, 11):
				regions[sp.region_of(Vector2(x / 10.0 + 0.01, y / 10.0 + 0.01) * sp.FIELD_HALF, layout)] = true
		splits = splits and regions.keys().all(func(r): return slots.has(r)) and regions.size() == 4
	_check(own and splits, "in both layouts each slot lies in its own quarter of the field, and the field splits four ways")
	# Two gates' outer rings must not meet within a layout: the diamond's
	# diagonal neighbours and the grid's side by side are the closest.
	var ring: float = sp.GATE_RADIUS * sp.GATE_OUTER_OF_HOLE
	var min_gap := 1e9
	for slots in sp.LAYOUT_SLOTS:
		for i in slots.size():
			for j in range(i + 1, slots.size()):
				min_gap = minf(min_gap, (sp.SLOTS[slots[i]] as Vector2).distance_to(sp.SLOTS[slots[j]]))
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
	var w_wrong: Dictionary = sp.upcoming_wave()
	var right_gate: Dictionary = w_wrong.planets.filter(func(p): return p.correct)[0]
	_fly_wave_at(_wrong_pos(w_wrong))
	# The wrong gate answers: the camera jolts and the right gate is ringed.
	_check(sp.shake > 0.0 and sp.reveals.any(func(r): return is_same(r.p, right_gate))
		and not sp.reveals.any(func(r): return not r.p.correct),
		"a wrong gate jolts the camera and rings the gate that was right, and only that")
	# Again with four gates, where the gates that were neither flown through
	# nor right must stay unringed; with two there are none to tell apart.
	var keep_level: int = sp.pattern_level
	var keep_kind: int = sp.pattern_kind
	var keep_done: int = sp.steps_done
	var w4: Dictionary = {}
	sp.pattern_level = 3
	sp.pattern_kind = sp.Kind.COLOR
	sp._prepare_pattern()
	w4 = sp._make_step(sp.Kind.COLOR)
	sp.reveals.clear()
	var wrong4: Dictionary = w4.planets.filter(func(p): return not p.correct)[0]
	w4["target"] = wrong4
	sp._resolve_wave(w4)
	_check(w4.planets.size() == 4 and sp.reveals.size() == 1 and sp.reveals[0].p.correct,
		"with four gates, only the right one is ringed (%d ringed)" % sp.reveals.size())
	for p in w4.planets:
		p.node.free()
	sp.reveals.clear()
	sp.pattern_level = keep_level
	sp.pattern_kind = keep_kind
	sp.steps_done = keep_done
	_check(m.hearts == hearts_before and m.combo == 0 and sp.streak == 0 and sp.level == level_before
		and m.run_stardust == dust_before and is_equal_approx(sp._pace_target(), sp.PACE_START),
		"a wrong gate breaks the streak and the combo, slows the world back down, and costs no heart, weapon or stardust")
	_fly_wave_at(_correct_pos(sp.upcoming_wave()))
	_fly_wave_at(_clear_pos(sp.upcoming_wave()))
	_check(m.hearts == hearts_before and sp.streak == 0 and sp.level == level_before,
		"a quarter with no gate counts as a wrong gate")
	# Changing the answer during the pull: steered from a wrong gate's quarter
	# into the right one past half way in, the right gate is the one passed;
	# steered away after CAPTURE_LOCK, the gate already chosen still is.
	var late := func(first: Vector2, then_at: float, to: Vector2) -> void:
		var lw: Dictionary = sp.upcoming_wave()
		_park(first)
		var g := 0
		while not lw.resolved and g < 2000 and lw.z < sp.CAPTURE_Z * (1.0 - then_at):
			m.hurt_elapsed = 0.1
			_tick(1.0 / 60.0)
			g += 1
		_park(to)
		while not lw.resolved and g < 4000:
			m.hurt_elapsed = 0.1
			_tick(1.0 / 60.0)
			g += 1
		m.hurt_elapsed = -1.0
	var w_late: Dictionary = sp.upcoming_wave()
	var combo0: int = m.combo
	late.call(_wrong_pos(w_late), 0.6, _correct_pos(w_late))
	_check(m.combo == combo0 + 1, "an answer changed 60%% of the way into the pull still counts (combo %d)" % m.combo)
	w_late = sp.upcoming_wave()
	combo0 = m.combo
	late.call(_correct_pos(w_late), sp.CAPTURE_LOCK + 0.05, _wrong_pos(w_late))
	_check(m.combo == combo0 + 1, "one changed after CAPTURE_LOCK does not (combo %d)" % m.combo)

	# ---- 5 ----
	# No rocks between the steps since 2026-11-27: a few patterns' worth of
	# gaps, and not one. The asteroid itself is still checked below, spawned
	# by hand.
	var rocks_seen := 0
	for run in range(2):
		_fresh_run()
		for i in range(8):
			_fly_wave_at(_correct_pos(sp.upcoming_wave()))
			rocks_seen += sp.rocks.size()
	_check(rocks_seen == 0, "no rocks fly between the steps (%d seen)" % rocks_seen)
	# The slowest a step can get, read off the game's own speed(): a late
	# cycle, full streak, no lunge.
	var keep := [sp.cycle, sp.pace, sp.boost, sp.phase, sp.memory_slow]
	sp.cycle = 20
	sp.pace = sp.PACE_MAX
	sp.boost = 0.0
	sp.phase = sp.Phase.PATTERN
	sp.memory_slow = 1.0
	var fastest: float = sp.STEP_GAP / sp.speed()
	sp.cycle = keep[0]
	sp.pace = keep[1]
	sp.boost = keep[2]
	sp.phase = keep[3]
	sp.memory_slow = keep[4]
	_check(fastest >= STEP_FLOOR, "at its fastest a step is still %.2f s apart (at least %.1f)" % [fastest, STEP_FLOOR])
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
	# A pattern holds the guns (2026-11-28); the asteroid is kept for a
	# shooter mode, so they are opened by hand here.
	sp.volley_left = 999.0
	guard = 0
	while not rock.judged and guard < 600:
		_tick(1.0 / 60.0)
		guard += 1
	_check(not rock.alive and m.hearts == m.MAX_HEARTS and m.score > score0, "one shot to pieces scores and costs nothing")

	# The guns hold during a pattern, where nothing can be hit, and a power-up
	# fires one short volley so the new weapon is seen.
	_fresh_run()
	_hold_pattern()
	_tick(1.0)
	_check(sp.phase == sp.Phase.PATTERN and sp.bullets.is_empty(), "a pattern holds the guns (%d bullets)" % sp.bullets.size())
	sp._power_up(false)
	_tick(0.1)
	_check(not sp.bullets.is_empty(), "a power-up in a pattern fires a volley")
	_tick(sp.VOLLEY_TIME)
	var after_volley: int = sp.bullets.size()
	_tick(0.3)
	_check(sp.bullets.size() <= after_volley, "and the volley stops after VOLLEY_TIME (%d -> %d bullets)" % [after_volley, sp.bullets.size()])

	# ---- 6 ----
	var whole: float = sp.FEVER_FULL
	var per: float = whole / sp.PATTERN_LEN
	_check(sp.fever_for(sp.FEVER_MIN_RIGHT - 1) == 0.0 and is_equal_approx(sp.fever_for(sp.FEVER_MIN_RIGHT), per * sp.FEVER_MIN_RIGHT)
		and is_equal_approx(sp.fever_for(sp.PATTERN_LEN - 1), per * (sp.PATTERN_LEN - 1)) and is_equal_approx(sp.fever_for(sp.PATTERN_LEN), whole),
		"fever is in proportion to the right gates: none under %d, %.2f s a gate, %.1f s for all %d" % [sp.FEVER_MIN_RIGHT, per, whole, sp.PATTERN_LEN])
	# The gauge shows it: it fills with the right gates, the wrong ones eat in
	# from the other end, and the fever drains it from where the pattern left
	# it, so half right is half a gauge and half a fever.
	_fresh_run()
	_play_pattern(func(i): return i % 2 == 0)
	_check(sp.phase == sp.Phase.FEVER and is_equal_approx(sp.fever_time, whole * 0.5)
		and absf(sp.gauge_fill().x - 0.5) < 0.02,
		"half the steps right: half a fever (%.1f s) and the gauge at half as it starts (%.2f)" % [sp.fever_time, sp.gauge_fill().x])
	_tick(sp.fever_time * 0.5)
	_check(absf(sp.gauge_fill().x - 0.25) < 0.03, "and it drains as the fever runs (%.2f half way through)" % sp.gauge_fill().x)
	_fresh_run()
	var steps_seen := []
	_play_pattern(func(i):
		if i == 4:
			steps_seen.append(sp.gauge_fill())
		return i != 2)
	if not steps_seen.is_empty():
		var at4: Vector2 = steps_seen[0]
		_check(is_equal_approx(at4.x, 3.0 / sp.PATTERN_LEN) and is_equal_approx(at4.y, 1.0 / sp.PATTERN_LEN),
			"in a pattern the gauge is the right steps so far, and the wrong ones from the other end (%.3f, %.3f)" % [at4.x, at4.y])
	_fresh_run()
	_play_pattern(func(_i): return true)
	_check(sp.phase == sp.Phase.FEVER and sp.weapon == sp.Weapon.SPREAD and is_equal_approx(sp.fever_time, whole),
		"a pattern with every step right brings the next weapon and the whole FEVER (phase %d, weapon %d, %.1f s)" % [sp.phase, sp.weapon, sp.fever_time])
	var hearts_f: int = m.hearts
	var dust_f: int = m.run_stardust
	m._space_fever_smash()
	_check(m.run_stardust == dust_f + sp.STARDUST_FEVER_SMASH, "a planet smashed in fever pays stardust")
	for b in sp.bullets:
		b.node.queue_free()
	sp.bullets.clear()
	sp.volley_left = 0.0
	_tick(0.3)
	_check(not sp.bullets.is_empty(), "the guns open in FEVER")
	_park(Vector2.ZERO)
	_tick(sp.fever_time + 0.3)
	_check(m.hearts == hearts_f, "FEVER costs no heart (hearts %d)" % m.hearts)
	_check(sp.phase == sp.Phase.PATTERN and sp.steps_done == 0 and not sp.upcoming_wave().is_empty(),
		"and ends on the next pattern")
	# Too few right for any fever: straight on, and after the cycle's
	# patterns that is the boss.
	_play_pattern(func(i): return i < sp.FEVER_MIN_RIGHT - 1)
	_check(sp.phase == sp.Phase.BOSS and sp.boss != null and sp.weapon == sp.Weapon.SPREAD,
		"a pattern with %d right brings no fever and no weapon, and after %d patterns the boss comes" % [sp.FEVER_MIN_RIGHT - 1, sp.PATTERNS_PER_CYCLE])
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
	_hold_pattern()
	sp.fire_timer = 999.0
	_park(Vector2.ZERO)
	sp._spawn_asteroid(Vector2.ZERO, sp.SPAWN_Z * 0.5)
	guard = 0
	while m.state == m.State.PLAYING and guard < 600:
		sp.fire_timer = 999.0
		_tick(1.0 / 60.0)
		guard += 1
	_check(m.hearts == 0 and m.state == m.State.GAMEOVER and m.gameover_popup.visible,
		"the last heart ends the run on the game over (there is no revive)")
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
