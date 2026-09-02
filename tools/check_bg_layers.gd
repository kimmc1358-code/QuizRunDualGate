extends SceneTree

# Headless check on the per-mode background layers.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_bg_layers.gd
#
# Drives the real Main through _apply_mode for every mode and inspects the
# textures it actually ended up holding, rather than re-reading the path
# tables here — a copy of the tables would pass while the game loaded
# nothing.
#
# Guards what a parse check cannot see:
#
#   1. Every declared path really loads. A typo is otherwise silent:
#      _apply_mode's ResourceLoader.exists() guard leaves the texture null
#      and the mode quietly falls back to the old mountains/cloud layers,
#      which reads as a rendering bug rather than a missing file.
#   2. A near layer is only declared where there is a far layer under it.
#      Alone it is a cut-out with nothing behind it.
#   3. A near layer is genuinely a cut-out. Re-export it flattened and it
#      covers the far layer completely — the parallax still runs, it is
#      just invisible, and nothing else in the project would complain.
#   4. The near layer scrolls strictly faster than the far one, or there is
#      no parallax at all, only two images sliding together.
#   5. A pair tiles at one width, so the two wrap in step instead of
#      drifting into an ever-changing composite.
#   6. No background layer reaches the saturation or brightness of its own
#      mode's character and gate ring. The backdrop is not allowed to be the
#      loudest thing on screen, and re-exporting one background at full
#      saturation is exactly the kind of change that looks fine in isolation
#      and only reads wrong next to the art it sits behind.
#
# Re-run when MODE_BG_TEXTURE_PATH, MODE_BG_NEAR_TEXTURE_PATH,
# bg_speed_ratio or bg_near_speed_ratio change, or when a background is
# re-cut or re-graded.

const MODE_NAMES := ["SKY", "JUNGLE", "OCEAN", "DREAM"]

# A near layer with less transparency than this is not framing anything, it
# is a second opaque background. JUNGLE's blurred cut-out sits near 48%, so
# this leaves room for art that frames far more heavily while still
# catching a flattened re-export (which lands at 0%).
const MIN_CLEAR_FRACTION := 0.15

# The far layer is the bottom of the stack, with nothing behind it but the
# window's clear colour, so it has to be opaque.
const MAX_FAR_CLEAR_FRACTION := 0.001

# Percentile the comparison is made on. The very top of either distribution
# is a handful of pixels — a single specular dot on the gate, one bright
# coral tip — and neither decides what the screen reads like.
const LEVEL_PERCENTILE := 0.99

# The ceilings tools/bake_background.ps1 grades every background under.
# Deliberately duplicated here rather than derived: this exists to catch a
# background that was re-exported without being run through the tool at all,
# and a check that read its numbers from the same place would have nothing
# left to compare against. Keep the two in step — the tool's $SatCap/$ValCap
# are the source of truth and carry the reasoning.
#
# The tolerance is for PNG rounding; the soft cap itself lands exactly on
# the ceiling.
const SAT_CEILING := 0.72
const VAL_CEILING := 0.85
const CEILING_TOLERANCE := 0.01

# And the reason those ceilings are where they are: they have to clear the
# character and gate ring by a real margin, not a rounding error. This half
# of the check is the weaker one — every mode's gate art has fully saturated
# pixels, so the foreground p99 sits at ~1.00 and almost anything passes it.
# It is here to catch art direction drifting the other way, a foreground
# repainted so muted that the graded backdrop catches up with it.
const MIN_LEVEL_HEADROOM := 0.05

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# Saturation and value at LEVEL_PERCENTILE over the mostly-opaque pixels of
# every texture given, pooled. Returns [saturation, value].
func _levels(textures: Array) -> Array:
	var sats: Array[float] = []
	var vals: Array[float] = []
	for tex in textures:
		if tex == null:
			continue
		var image: Image = tex.get_image()
		var w: int = image.get_width()
		var h: int = image.get_height()
		# Strided: these run from 512x512 sprites to 2208x1056 paintings, and
		# a percentile does not need every pixel to be stable.
		for y in range(0, h, 3):
			for x in range(0, w, 3):
				var c: Color = image.get_pixel(x, y)
				if c.a < 0.78:
					continue
				var v: float = maxf(c.r, maxf(c.g, c.b))
				var m: float = minf(c.r, minf(c.g, c.b))
				sats.append(0.0 if v <= 0.0 else (v - m) / v)
				vals.append(v)
	if sats.is_empty():
		return [0.0, 0.0]
	sats.sort()
	vals.sort()
	var i: int = clampi(int(round(LEVEL_PERCENTILE * (sats.size() - 1))), 0, sats.size() - 1)
	return [sats[i], vals[i]]


func _load_first(dir_path: String, names: Array) -> Texture2D:
	for n in names:
		var p: String = dir_path + n
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _clear_fraction(tex: Texture2D) -> float:
	# Sampled on a grid, not per-pixel: these are 2208x1056 sources and the
	# answer only has to separate "cut-out" from "flattened".
	var image: Image = tex.get_image()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var clear: int = 0
	var total: int = 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			if image.get_pixel(x, y).a <= 0.004:  # 1/255
				clear += 1
			total += 1
	return 0.0 if total == 0 else float(clear) / float(total)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	# 부팅이 끝나기를 기다린다 — _boot_load 가 로고 화면에서 돌기 때문에,
	# 여기서 모드를 갈아끼우면 그 뒤에 한 번 더 덮어쓴다.
	while main.get("boot_pending"):
		await process_frame

	print("check_bg_layers: per-mode background layers")

	var far_paths: Array = main.get("MODE_BG_TEXTURE_PATH")
	var near_paths: Array = main.get("MODE_BG_NEAR_TEXTURE_PATH")
	if near_paths.size() != far_paths.size():
		_fail("MODE_BG_NEAR_TEXTURE_PATH has %d rows, MODE_BG_TEXTURE_PATH has %d — both are indexed by Mode and must stay aligned" % [near_paths.size(), far_paths.size()])

	var any_near := false
	for mode in range(mini(far_paths.size(), near_paths.size())):
		main.call("_apply_mode", mode)
		var far_declared: bool = far_paths[mode] != ""
		var near_declared: bool = near_paths[mode] != ""
		var far_tex: Texture2D = main.get("bg_texture")
		var near_tex: Texture2D = main.get("bg_near_texture")

		if far_declared and far_tex == null:
			_fail("%s declares a far layer but _apply_mode loaded nothing: %s" % [MODE_NAMES[mode], far_paths[mode]])
		if near_declared and near_tex == null:
			_fail("%s declares a near layer but _apply_mode loaded nothing: %s" % [MODE_NAMES[mode], near_paths[mode]])
		if near_declared and not far_declared:
			_fail("%s declares a near layer with no far layer to draw it over" % MODE_NAMES[mode])

		if far_tex != null:
			var far_clear: float = _clear_fraction(far_tex)
			if far_clear > MAX_FAR_CLEAR_FRACTION:
				_fail("%s far layer is %.1f%% transparent — the bottom layer has nothing behind it" % [MODE_NAMES[mode], far_clear * 100.0])

		if near_tex == null:
			print("  %-7s far only" % MODE_NAMES[mode])
			continue
		any_near = true

		var clear: float = _clear_fraction(near_tex)
		if clear < MIN_CLEAR_FRACTION:
			_fail("%s near layer is only %.1f%% transparent (need >= %.0f%%) — it would cover the far layer instead of framing it. Re-exported flattened?" % [MODE_NAMES[mode], clear * 100.0, MIN_CLEAR_FRACTION * 100.0])
		else:
			print("  %-7s near layer %.1f%% transparent" % [MODE_NAMES[mode], clear * 100.0])

		if far_tex != null:
			# _draw_bg_layer scales each layer to fill the view height, so a
			# pair with different aspect ratios tiles at different widths and
			# the two never line up the same way twice.
			var far_aspect: float = float(far_tex.get_width()) / float(far_tex.get_height())
			var near_aspect: float = float(near_tex.get_width()) / float(near_tex.get_height())
			if absf(far_aspect - near_aspect) > 0.001:
				_fail("%s pair has mismatched aspect ratios (far %.4f, near %.4f) — they tile at different widths and drift apart" % [MODE_NAMES[mode], far_aspect, near_aspect])

	# Re-walk the modes for the level ceilings. Separate pass because it
	# needs the character and gate art too, which _apply_mode also loads —
	# read off the node rather than re-opening files, so this compares what
	# the game actually draws.
	for mode in range(far_paths.size()):
		main.call("_apply_mode", mode)
		var fg: Array = []
		for f in main.get("flap_frames"):
			fg.append(f)
		fg.append(main.get("gate_left_pillar_texture"))
		fg.append(main.get("gate_right_pillar_texture"))
		var fg_levels: Array = _levels(fg)
		if fg_levels[0] <= 0.0 and fg_levels[1] <= 0.0:
			_fail("%s: no character or gate art loaded to measure the background against" % MODE_NAMES[mode])
			continue
		for pair in [["far", main.get("bg_texture")], ["near", main.get("bg_near_texture")]]:
			var tex: Texture2D = pair[1]
			if tex == null:
				continue
			var bg_levels: Array = _levels([tex])
			if bg_levels[0] > SAT_CEILING + CEILING_TOLERANCE:
				_fail("%s %s layer saturation %.2f is over the %.2f ceiling — re-exported without tools/bake_background.ps1?" % [MODE_NAMES[mode], pair[0], bg_levels[0], SAT_CEILING])
			if bg_levels[1] > VAL_CEILING + CEILING_TOLERANCE:
				_fail("%s %s layer brightness %.2f is over the %.2f ceiling — re-exported without tools/bake_background.ps1?" % [MODE_NAMES[mode], pair[0], bg_levels[1], VAL_CEILING])
			if bg_levels[0] > fg_levels[0] - MIN_LEVEL_HEADROOM:
				_fail("%s %s layer saturation %.2f is not clear of the character/gate's %.2f — the backdrop would out-colour what is played against it" % [MODE_NAMES[mode], pair[0], bg_levels[0], fg_levels[0]])
			if bg_levels[1] > fg_levels[1] - MIN_LEVEL_HEADROOM:
				_fail("%s %s layer brightness %.2f is not clear of the character/gate's %.2f — the backdrop would out-shine what is played against it" % [MODE_NAMES[mode], pair[0], bg_levels[1], fg_levels[1]])
			print("  %-7s %-4s sat %.2f (cap %.2f, fg %.2f)   val %.2f (cap %.2f, fg %.2f)" % [MODE_NAMES[mode], pair[0], bg_levels[0], SAT_CEILING, fg_levels[0], bg_levels[1], VAL_CEILING, fg_levels[1]])

	var far_ratio: float = main.get("bg_speed_ratio")
	var near_ratio: float = main.get("bg_near_speed_ratio")
	if any_near and near_ratio <= far_ratio:
		_fail("bg_near_speed_ratio (%.3f) must exceed bg_speed_ratio (%.3f), or the near layer travels with the far one and there is no parallax" % [near_ratio, far_ratio])
	elif any_near:
		print("  near/far speed %.2fx (%.2f vs %.2f of GATE_SPEED)" % [near_ratio / far_ratio, near_ratio, far_ratio])

	if fails == 0:
		print("check_bg_layers: OK")
	else:
		print("check_bg_layers: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
