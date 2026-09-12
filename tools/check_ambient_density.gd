@tool
extends SceneTree

# Simulates the ambient particle pool over a stretch of play and reports how
# many of its fixed-size population are actually ON SCREEN, with the boost
# held and released.
#
# What it catches: a fixed-size pool going thin enough that the screen reads
# as bare — the kind of thing that is invisible to a parse check and easy to
# miss in a short playtest, but falls straight out of a simulation.
#
# What it does NOT catch, though this header used to imply otherwise. The bug
# it was written for was every recycled particle re-entering through the
# ceiling while a leftward wind swept them off the side, leaving all of them
# crowded into the top-left corner. Counting on-screen particles cannot see
# that: a particle swept off the left is recycled straight back to a random x
# along the ceiling, so it is on screen again immediately and the count never
# moves. Disabling the right-edge spawn branch — that exact bug — leaves
# these numbers completely unchanged, which was verified rather than assumed.
# What collapses is the DISTRIBUTION, and catching it needs a spread or
# coverage measure this check does not have.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ambient_density.gd
#
# Add `-- --seed N` to run a different seed than the committed one.

const DT := 1.0 / 60.0
# A leaf takes ~24s to cross at rest, so a short window samples the initial
# scatter rather than steady state. These are long enough that every particle
# has been recycled at least once before sampling starts.
const WARMUP := 40.0    # seconds to reach steady state before sampling
const SAMPLE := 40.0    # seconds sampled
# Spawn positions, sizes and drifts are all randf, so an unseeded run gave a
# different answer every time — DREAM's minimum wandered across the pass/fail
# line once its diagonal was steepened, and the check began failing about one
# run in five for no reason anyone could reproduce. A fixed seed is what makes
# a failure mean something. The floor below was then chosen against a sweep of
# 12 seeds rather than against this one, so it is not tuned to whatever this
# particular seed happens to produce.
const RNG_SEED := 20260903

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
	# Seeded before anything spawns. `-- --seed N` overrides, for sweeping.
	var seed_value: int = RNG_SEED
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--seed":
			seed_value = int(args[i + 1])
	seed(seed_value)
	var view_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	# The seed is printed so a failure report says which one produced it.
	print("viewport %.0f x %.0f   pool size %d   seed %d\n" % [view_size.x, view_size.y, main.particle_count, seed_value])
	print("%-8s %-10s %-14s %-14s %s" % ["mode", "boost", "avg on-screen", "min on-screen", "verdict"])

	var problems := 0
	var mode_names := ["SKY", "JUNGLE", "OCEAN", "DREAM"]
	for mode in range(4):
		if int(main.MODE_PARTICLE_COUNT[mode]) <= 0:
			print("%-8s %-10s %-14s %-14s %s" % [mode_names[mode], "-", "-", "-", "no ambient layer"])
			continue
		for held in [false, true]:
			var result := _simulate(mode, held, view_size)
			# A tolerance on momentary thinness — see the header for what that
			# does and does not cover. Half the pool used to be the floor and
			# it sat inside normal variation: swept over 12 seeds and all six
			# live cases, a healthy field's momentary minimum lands anywhere
			# from 3 to 8 of 8, because one unlucky instant with five particles
			# in transit is ordinary. A quarter clears that measured spread,
			# and all 12 of those seeds pass against it.
			var floor_ok: float = float(main.particle_count) * 0.25
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
