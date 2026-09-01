@tool
extends SceneTree

# Replicates _apply_mode's sparkle loading exactly, for all four modes, and
# reports what each mode's pools actually came out as. Catches the two
# things a parse check cannot: that every sprite the tables name really
# exists on disk, and that the weighted burst pool lands on the intended
# colour mix.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_sparkle_pools.gd

const SPARKLE_DIR := "res://assets/fx/tap/"
const SPARKLE_COLOR_NAMES := ["gold", "green", "blue", "pink"]
const SPARKLE_SPRITES_PER_COLOR := 6
const TRAIL_COLORS_PER_MODE := [
	["gold"],
	["green"],
	["blue"],
	["gold", "green", "blue", "pink"],
]
const FX_BURST_COLOR_WEIGHTS_PER_MODE := [
	[7.0, 1.0, 1.0, 1.0],
	[1.0, 7.0, 1.0, 1.0],
	[1.0, 1.0, 7.0, 1.0],
	[1.0, 1.0, 1.0, 1.0],
]
const MODE_NAMES := ["SKY", "JUNGLE", "OCEAN", "DREAM"]


func _init() -> void:
	var failures := 0

	var sparkle_texture_sets: Array = []
	for color_name in SPARKLE_COLOR_NAMES:
		var color_set: Array[Texture2D] = []
		for i in range(1, SPARKLE_SPRITES_PER_COLOR + 1):
			var path: String = SPARKLE_DIR + "tap_%s_%d.png" % [color_name, i]
			if ResourceLoader.exists(path):
				color_set.append(load(path))
			else:
				print("  MISSING: ", path)
				failures += 1
		sparkle_texture_sets.append(color_set)
		var dims := ""
		for t in color_set:
			dims += "%dx%d " % [t.get_width(), t.get_height()]
		print("%-6s %d sprites   %s" % [color_name, color_set.size(), dims])

	for mode in range(4):
		print("\n--- ", MODE_NAMES[mode], " ---")

		var trail_texture_sets: Array = []
		for color_name in TRAIL_COLORS_PER_MODE[mode]:
			var ci: int = SPARKLE_COLOR_NAMES.find(color_name)
			if ci >= 0 and not sparkle_texture_sets[ci].is_empty():
				trail_texture_sets.append(sparkle_texture_sets[ci])
		print("  trail colour sets: %d (%s)" % [trail_texture_sets.size(), ", ".join(TRAIL_COLORS_PER_MODE[mode])])
		if trail_texture_sets.size() != TRAIL_COLORS_PER_MODE[mode].size():
			print("  FAIL: trail set count does not match the table")
			failures += 1

		# This is the line most likely to fail at runtime rather than parse
		# time: append_array onto a typed array from an untyped element.
		var fx_burst_textures: Array[Texture2D] = []
		var burst_weights: Array = FX_BURST_COLOR_WEIGHTS_PER_MODE[mode]
		for ci in range(SPARKLE_COLOR_NAMES.size()):
			var color_set: Array = sparkle_texture_sets[ci]
			if color_set.is_empty():
				continue
			for _repeat in range(int(burst_weights[ci])):
				fx_burst_textures.append_array(color_set)

		var counts := {}
		for t in fx_burst_textures:
			var name: String = t.resource_path.get_file().split("_")[1]
			counts[name] = counts.get(name, 0) + 1
		var total: int = fx_burst_textures.size()
		var line := "  burst pool: %d entries  ->  " % total
		for color_name in SPARKLE_COLOR_NAMES:
			line += "%s %.0f%%  " % [color_name, 100.0 * counts.get(color_name, 0) / total]
		print(line)

	print("\n", "PASS" if failures == 0 else "FAIL (%d problems)" % failures)
	quit(0 if failures == 0 else 1)
