@tool
extends SceneTree

# Maps how much boost a player actually held to the bar's remaining-percent
# at the judge line, using the real tuning constants. This is what the bonus
# thresholds have to be picked against: the bar drains on a fixed T_base
# clock, so "remaining" IS "how much of the flight you skipped".
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_boost_bar_range.gd

const PLAYER_X := 130.0
const GATE_WIDTH := 130.0
const GATE_SPEED := 130.0
const BASE_GATE_SPACING := 600.0        # the @export default
const GATE_SPEED_BOOST_PEAK := 3.2
const GATE_SPEED_BOOST_HOLD := 0.06
const GATE_SPEED_BOOST_DURATION := 0.5
const BOOST_BUTTON_MULTIPLIER := 2.0
# Mirrors of Main.gd's boost_bonus_* export defaults and SCORE_PER_COMBO —
# keep these in step when any of them is retuned.
const MID_THRESHOLD := 0.12
const BEST_THRESHOLD := 0.48
const NONE_MULTIPLIER := 0.0
const MID_MULTIPLIER := 0.5
const BEST_MULTIPLIER := 1.0
const SCORE_PER_COMBO := 10
const DT := 1.0 / 480.0


func _jolt(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= GATE_SPEED_BOOST_DURATION:
		return 1.0
	if elapsed < GATE_SPEED_BOOST_HOLD:
		return GATE_SPEED_BOOST_PEAK
	var decay_span: float = GATE_SPEED_BOOST_DURATION - GATE_SPEED_BOOST_HOLD
	var t: float = (elapsed - GATE_SPEED_BOOST_HOLD) / decay_span
	return 1.0 + (GATE_SPEED_BOOST_PEAK - 1.0) * pow(1.0 - t, 3)


# Holds the button for `hold` seconds starting at `start`. Returns
# {remaining, flight, held_fraction} — held_fraction measured against the
# flight that actually happened, which is the number a player would feel.
func _run(hold: float, start: float) -> Dictionary:
	var distance: float = BASE_GATE_SPACING + GATE_WIDTH * 0.5
	var t_base: float = distance / GATE_SPEED
	var travelled := 0.0
	var t := 0.0
	var held := 0.0
	while travelled < distance and t < t_base * 4.0:
		var mult: float = _jolt(t)
		if t >= start and t < start + hold:
			mult *= BOOST_BUTTON_MULTIPLIER
			held += DT
		travelled += GATE_SPEED * mult * DT
		t += DT
	return {
		"remaining": clampf(1.0 - t / t_base, 0.0, 1.0),
		"flight": t,
		"held_fraction": held / t if t > 0.0 else 0.0,
	}


func _init() -> void:
	var distance: float = BASE_GATE_SPACING + GATE_WIDTH * 0.5
	var t_base: float = distance / GATE_SPEED
	print("distance %.0f px, GATE_SPEED %.0f, boost %.1fx  ->  T_base = %.3f s" % [distance, GATE_SPEED, BOOST_BUTTON_MULTIPLIER, t_base])
	print("The gate-pass jolt always fires as a gate spawns, so it is included everywhere.\n")

	var floor_r: float = _run(0.0, 0.0)["remaining"]
	var ceil_r: float = _run(t_base * 4.0, 0.0)["remaining"]
	print("FLOOR   no boost at all        remaining %.1f%%" % (floor_r * 100.0))
	print("CEILING held the whole flight  remaining %.1f%%" % (ceil_r * 100.0))
	print("=> the whole scoring axis is %.1f%% .. %.1f%%\n" % [floor_r * 100.0, ceil_r * 100.0])

	print("%-14s %-14s %-12s %s" % ["hold (s)", "held/flight", "flight (s)", "remaining"])
	for hold in [0.0, 0.15, 0.3, 0.5, 0.75, 1.0, 1.4, 1.8, 2.2, 3.0]:
		var r := _run(hold, 0.0)
		print("%-14s %-14s %-12s %.1f%%" % [
			"%.2f" % hold, "%.0f%%" % (r["held_fraction"] * 100.0),
			"%.2f" % r["flight"], r["remaining"] * 100.0])

	# Same total hold, spent at different points in the flight. The jolt
	# window at the start is worth far more per second, so WHEN matters.
	print("\nsame 0.60s hold, spent at different moments:")
	for start in [0.0, 0.25, 0.5, 1.5, 3.0]:
		var r := _run(0.6, start)
		print("   start at %.2fs -> remaining %.1f%%" % [start, r["remaining"] * 100.0])

	# The thresholds Main.gd actually ships, checked against that curve: all
	# three tiers must be reachable, and no-boost must land on zero.
	print("\nverdict with Main.gd's boost_bonus_* defaults (mid %.2f, best %.2f):" % [MID_THRESHOLD, BEST_THRESHOLD])
	var seen := {}
	for hold in [0.0, 0.15, 0.3, 0.5, 0.75, 1.0, 1.4, 1.8, 2.2, 3.0]:
		var r := _run(hold, 0.0)
		var tier: String = _tier(r["remaining"])
		seen[tier] = true
		print("   hold %.2fs -> %.1f%% -> %s" % [hold, r["remaining"] * 100.0, tier])
	var problems := 0
	if _tier(floor_r) != "x0.0":
		print("   FAIL: no boost scores '%s', expected x0.0" % _tier(floor_r))
		problems += 1
	if _tier(ceil_r) != "x1.0":
		print("   FAIL: perfect boost scores '%s', expected x1.0" % _tier(ceil_r))
		problems += 1
	for tier in ["x0.0", "x0.5", "x1.0"]:
		if not seen.has(tier):
			print("   FAIL: tier %s is unreachable" % tier)
			problems += 1

	# What the multiplier is actually worth, at a few combo counts.
	print("\ngate score = %d x combo x (1 + multiplier):" % SCORE_PER_COMBO)
	print("   %-8s %-10s %-10s %s" % ["combo", "x0.0", "x0.5", "x1.0"])
	for combo in [1, 5, 10, 25]:
		var base: int = SCORE_PER_COMBO * combo
		print("   %-8d %-10d %-10d %d" % [combo, base,
			int(round(base * 1.5)), int(round(base * 2.0))])

	print("\n", "PASS — all three tiers reachable" if problems == 0 else "FAIL (%d problems)" % problems)
	quit(0 if problems == 0 else 1)


func _tier(remaining: float) -> String:
	if remaining >= BEST_THRESHOLD:
		return "x%.1f" % BEST_MULTIPLIER
	if remaining >= MID_THRESHOLD:
		return "x%.1f" % MID_MULTIPLIER
	return "x%.1f" % NONE_MULTIPLIER
