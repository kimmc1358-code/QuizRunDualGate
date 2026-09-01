@tool
extends SceneTree

# Simulates the ambient particle pool over a stretch of play and reports how
# many of its fixed-size population are actually ON SCREEN, with the boost
# held and released.
#
# The bug this exists to catch: the pool is a fixed count, so if every
# recycled particle re-enters through the ceiling while a leftward wind
# sweeps them off the side, the field drains and the screen goes bare. That
# is invisible to a parse check and easy to miss in a short playtest, but it
# falls straight out of a simulation.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ambient_density.gd

const DT := 1.0 / 60.0
# A leaf takes ~24s to cross at rest, so a short window samples the initial
# scatter rather than steady state. These are long enough that every particle
# has been recycled at least once before sampling starts.
const WARMUP := 40.0    # seconds to reach steady state before sampling
const SAMPLE := 40.0    # seconds sampled

var main: Node
var frames := 0


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	_check()
	return true


func _check() -> void:
	var view_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	print("viewport %.0f x %.0f   pool size %d\n" % [view_size.x, view_size.y, main.particle_count])
	print("%-8s %-10s %-14s %-14s %s" % ["mode", "boost", "avg on-screen", "min on-screen", "verdict"])

	var problems := 0
	var mode_names := ["SKY", "JUNGLE", "OCEAN", "DREAM"]
	for mode in range(4):
		if int(main.MODE_PARTICLE_COUNT[mode]) <= 0:
			print("%-8s %-10s %-14s %-14s %s" % [mode_names[mode], "-", "-", "-", "no ambient layer"])
			continue
		for held in [false, true]:
			var result := _simulate(mode, held, view_size)
			# Under a fixed pool a healthy field keeps most of its particles
			# on screen. Half the pool is a generous floor; the bug this
			# guards against drained it to nearly nothing.
			var floor_ok: float = float(main.particle_count) * 0.5
			var ok: bool = result["min"] >= floor_ok
			if not ok:
				problems += 1
			print("%-8s %-10s %-14s %-14s %s" % [
				mode_names[mode], "held" if held else "idle",
				"%.1f" % result["avg"], "%d" % result["min"],
				"ok" if ok else "DRAINED (floor %.0f)" % floor_ok])

	print("\n", "PASS — the field stays populated with the boost held" if problems == 0 else "FAIL (%d drained)" % problems)
	quit(0 if problems == 0 else 1)


func _simulate(mode: int, held: bool, view_size: Vector2) -> Dictionary:
	main.current_mode = mode
	main.boost_button_held = held
	main.boost_visual_blend = 1.0 if held else 0.0
	main._init_ambient_particles(view_size)

	var total := 0.0
	var samples := 0
	var lowest := 9999
	var t := 0.0
	while t < WARMUP + SAMPLE:
		main._update_ambient_particles(DT, view_size)
		t += DT
		if t < WARMUP:
			continue
		var on_screen := 0
		for p in main.ambient_particle_list:
			# base_x is the travel line; the sway is a draw-time offset, so
			# counting on base_x is what the eye sees within a few px.
			if p.base_x + p.size * 0.5 >= 0.0 and p.base_x - p.size * 0.5 <= view_size.x \
					and p.y + p.size * 0.5 >= 0.0 and p.y - p.size * 0.5 <= view_size.y:
				on_screen += 1
		total += on_screen
		samples += 1
		lowest = mini(lowest, on_screen)
	return { "avg": total / maxf(samples, 1), "min": lowest }
