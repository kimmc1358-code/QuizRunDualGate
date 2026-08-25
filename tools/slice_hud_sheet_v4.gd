extends SceneTree

# Slices assets/ui_assets/hud_sheet_v4.png into the 12 per-mode HUD PNGs.
#
#   godot --headless --path . --script tools/slice_hud_sheet_v4.gd
#
# Sheet layout: six row bands = three modes (sky / jungle / ocean), each with
# a top sub-row holding pause | score box | mute, and a bottom sub-row holding
# the quiz box. The score box is split by a vertical divider into a SCORE half
# and a BEST half; each half carries a painted label on its left with blank
# writing space to its right.
#
# Two details that this has to work around:
#
# 1. Band detection counts a row as content only when at least SPARSE_FRAC of
#    its width is opaque. Plain "any opaque pixel" merges bands, because the
#    leaf and coral decorations trail into the gaps between modes.
#
# 2. The three modes' decorations (sky's wings, jungle's leaves, ocean's
#    coral) stick out by different amounts, so cropping each mode to its own
#    bounding box would land the writing areas somewhere different in every
#    mode. Instead every piece gets ONE canvas size shared across the modes,
#    with each mode positioned so the panel interiors coincide. That is what
#    lets a single set of fractions place the score, best and quiz text
#    identically in all three modes.
#
# Prints the fractions the drawing code needs; copy them into Main.gd if the
# sheet is ever redrawn.

const SHEET := "res://assets/ui_assets/hud_sheet_v4.png"
const OUT_DIR := "res://assets/ui_assets"
const A_THR := 0.10
const SPARSE_FRAC := 0.03   # row is content when this fraction of its width is opaque
const BAND_COUNT := 6      # 3 modes x (button row + quiz row)
const COL_DENSE_FRAC := 0.35   # column is content when this fraction of the band height is opaque.
                               # Measured sweep: below ~0.25 ocean's coral bridges the score box into the
                               # buttons and jungle throws a stray run; 0.25-0.55 all give a clean 3.
const MODES := ["sky", "jungle", "ocean"]
const TOP_NAMES := ["pause", "score_box", "mute"]


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img == null:
		printerr("could not load %s" % SHEET)
		quit(1)
		return
	print("SHEET %dx%d" % [img.get_width(), img.get_height()])
	for m in MODES:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, m]))

	var bands := _bands(img)
	if bands.size() != 6:
		printerr("expected 6 row bands, got %d: %s" % [bands.size(), str(bands)])
		quit(1)
		return

	# cells[mode] = {pause, score_box, mute, quiz_box} of Rect2i,
	# plus the measured interiors for score/quiz
	var cells := []
	for mi in range(3):
		var top: Array = bands[mi * 2]
		var bottom: Array = bands[mi * 2 + 1]
		var top_cols := _cols(img, top[0], top[1], 3)
		var bot_cols := _cols(img, bottom[0], bottom[1], 1)
		if top_cols.size() != 3 or bot_cols.size() != 1:
			printerr("%s: expected 3 top cols and 1 bottom col, got %d / %d" % [MODES[mi], top_cols.size(), bot_cols.size()])
			quit(1)
			return
		var d := {}
		for ci in range(3):
			d[TOP_NAMES[ci]] = _bbox(img, top_cols[ci][0], top[0], top_cols[ci][1], top[1])
		d["quiz_box"] = _bbox(img, bot_cols[0][0], bottom[0], bot_cols[0][1], bottom[1])
		d["score_interior"] = _light_bbox(img, d["score_box"])
		d["quiz_interior"] = _light_bbox(img, d["quiz_box"])
		var div := _divider_x(img, d["score_interior"])
		d["divider"] = div
		var si: Rect2i = d["score_interior"]
		d["score_usable"] = _usable(img, si, si.position.x, div.x - 1)
		d["best_usable"] = _usable(img, si, div.y + 1, si.position.x + si.size.x - 1)
		d["quiz_usable"] = _usable(img, d["quiz_interior"], d["quiz_interior"].position.x, d["quiz_interior"].position.x + d["quiz_interior"].size.x - 1)
		cells.append(d)
		print("")
		print("--- %s" % MODES[mi])
		print("   pause=%s  mute=%s" % [str(d["pause"]), str(d["mute"])])
		print("   score_box=%s interior=%s divider=%s" % [str(d["score_box"]), str(si), str(div)])
		print("     SCORE usable=%s   BEST usable=%s" % [str(d["score_usable"]), str(d["best_usable"])])
		print("   quiz_box=%s interior=%s usable=%s" % [str(d["quiz_box"]), str(d["quiz_interior"]), str(d["quiz_usable"])])

	# Anchor each piece on the thing that must line up across modes.
	_emit(img, cells, ["score_box"], "score_interior", ["score_usable", "best_usable"])
	_emit(img, cells, ["quiz_box"], "quiz_interior", ["quiz_usable"])
	_emit(img, cells, ["pause", "mute"], "", [])
	quit(0)


# Writes one group of pieces onto a canvas size shared by all three modes.
# `anchor_key` names the rect whose centre is aligned across modes (empty =>
# use the piece's own bounding-box centre, for the icon buttons).
func _emit(img: Image, cells: Array, names: Array, anchor_key: String, usable_keys: Array) -> void:
	var L := 0.0
	var R := 0.0
	var T := 0.0
	var B := 0.0
	for n in names:
		for mi in range(3):
			var o: Rect2i = cells[mi][n]
			var p := _anchor(cells[mi], n, anchor_key)
			L = max(L, p.x - o.position.x)
			R = max(R, o.position.x + o.size.x - p.x)
			T = max(T, p.y - o.position.y)
			B = max(B, o.position.y + o.size.y - p.y)
	var cw := int(ceil(L + R))
	var chh := int(ceil(T + B))
	var ax := int(round(L))
	var ay := int(round(T))
	print("")
	print("=== %s : canvas %dx%d" % [str(names), cw, chh])

	var shared := {}
	for k in usable_keys:
		shared[k] = Rect2i(-99999, -99999, 0, 0)
	var acc := {}
	for k in usable_keys:
		acc[k] = [-999999, -999999, 999999, 999999]

	for n in names:
		for mi in range(3):
			var o: Rect2i = cells[mi][n]
			var p := _anchor(cells[mi], n, anchor_key)
			var px := int(round(ax - (p.x - o.position.x)))
			var py := int(round(ay - (p.y - o.position.y)))
			var canvas := Image.create(cw, chh, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			canvas.blit_rect(img, o, Vector2i(px, py))
			canvas.save_png(ProjectSettings.globalize_path("%s/%s/%s.png" % [OUT_DIR, MODES[mi], n]))
			for k in usable_keys:
				var u: Rect2i = cells[mi][k]
				var a: Array = acc[k]
				a[0] = max(a[0], u.position.x - o.position.x + px)
				a[1] = max(a[1], u.position.y - o.position.y + py)
				a[2] = min(a[2], u.position.x - o.position.x + px + u.size.x - 1)
				a[3] = min(a[3], u.position.y - o.position.y + py + u.size.y - 1)
	for k in usable_keys:
		var a: Array = acc[k]
		print("   %s shared: x%d..%d y%d..%d" % [k, a[0], a[2], a[1], a[3]])
		print("   %s FRACS  left=%.4f right=%.4f center_x=%.4f mid_y=%.4f height=%.4f" % [
			k, float(a[0]) / cw, float(a[2] + 1) / cw,
			(float(a[0]) + float(a[2] + 1)) * 0.5 / cw,
			(float(a[1]) + float(a[3] + 1)) * 0.5 / chh,
			float(a[3] + 1 - a[1]) / chh])


func _anchor(cell: Dictionary, name: String, anchor_key: String) -> Vector2:
	var r: Rect2i = cell[name] if anchor_key == "" else cell[anchor_key]
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5)


func _bands(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var min_px := int(w * SPARSE_FRAC)
	var content := []
	content.resize(h)
	for y in range(h):
		var n := 0
		for x in range(w):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		content[y] = n > min_px
	return _reduce_to(_runs(content), BAND_COUNT)


# Contiguous true-runs, split on every single false.
func _runs(flags: Array) -> Array:
	var out := []
	var start := -1
	for i in range(flags.size()):
		if flags[i]:
			if start < 0:
				start = i
		elif start >= 0:
			out.append([start, i - 1])
			start = -1
	if start >= 0:
		out.append([start, flags.size() - 1])
	return out


# Merges runs across the smallest gaps until exactly `n` remain.
#
# This replaces the fixed gap threshold the v3 sheet used. That threshold had
# to sit between "gap inside a mode block" and "gap between mode blocks", and
# those distances change every time the sheet is redrawn — v3's inner gaps
# were 7-8 rows, v4's are 4-6, so a constant tuned for one silently merges or
# splits the wrong things on the other. Since the layout is known (6 bands, 3
# columns in a top row, 1 in a bottom row), asking for that count directly is
# both simpler and self-tuning: only the relative ordering of the gaps has to
# hold, not their absolute size.
func _reduce_to(runs: Array, n: int) -> Array:
	while runs.size() > n:
		var best := -1
		var best_gap := 1 << 30
		for i in range(runs.size() - 1):
			var gap: int = runs[i + 1][0] - runs[i][1]
			if gap < best_gap:
				best_gap = gap
				best = i
		if best < 0:
			break
		runs[best][1] = runs[best + 1][1]
		runs.remove_at(best + 1)
	return runs


# Column split within a band. Uses a density threshold for the same reason
# the band split does: the leaves and coral trail a few stray pixels across
# the gaps, so "any opaque pixel" merges the score box into the buttons.
# Boundaries are then placed at the midpoint of each gap rather than at the
# dense run's edge, so every opaque pixel still lands in exactly one cell and
# no decoration gets clipped.
func _cols(img: Image, y0: int, y1: int, want: int) -> Array:
	var w := img.get_width()
	var rows := y1 - y0 + 1
	var min_px := int(rows * COL_DENSE_FRAC)
	var dense := []
	dense.resize(w)
	var first_opaque := -1
	var last_opaque := -1
	for x in range(w):
		var n := 0
		for y in range(y0, y1 + 1):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		dense[x] = n > min_px
		if n > 0:
			if first_opaque < 0:
				first_opaque = x
			last_opaque = x
	var groups := _reduce_to(_runs(dense), want)
	if groups.size() <= 1:
		return [[first_opaque, last_opaque]] if first_opaque >= 0 else []
	var out := []
	for i in range(groups.size()):
		var lo: int = first_opaque if i == 0 else int((groups[i - 1][1] + groups[i][0]) / 2) + 1
		var hi: int = last_opaque if i == groups.size() - 1 else int((groups[i][1] + groups[i + 1][0]) / 2)
		out.append([lo, hi])
	return out


func _is_light(c: Color) -> bool:
	return c.a > 0.9 and (c.r + c.g + c.b) / 3.0 > 0.70


func _light_bbox(img: Image, o: Rect2i) -> Rect2i:
	var minx := 999999
	var maxx := -1
	var miny := 999999
	var maxy := -1
	for y in range(o.position.y, o.position.y + o.size.y):
		var res := _longest_light_run(img, y, o.position.x, o.position.x + o.size.x - 1)
		if res.y > int(o.size.x * 0.20):
			minx = min(minx, res.x)
			maxx = max(maxx, res.x + res.y - 1)
			miny = min(miny, y)
			maxy = max(maxy, y)
	if maxx < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


# Vector2i(start, length) of the longest light run on row y within [sx..ex].
func _longest_light_run(img: Image, y: int, sx: int, ex: int) -> Vector2i:
	var run := 0
	var rs := -1
	var best := 0
	var bstart := -1
	for x in range(sx, ex + 2):
		var light := x <= ex and _is_light(img.get_pixel(x, y))
		if light:
			if rs < 0:
				rs = x
			run += 1
		else:
			if run > best:
				best = run
				bstart = rs
			run = 0
			rs = -1
	return Vector2i(bstart, best)


func _divider_x(img: Image, interior: Rect2i) -> Vector2i:
	var x0 := interior.position.x
	var y0 := interior.position.y
	var y1 := y0 + interior.size.y - 1
	var rows := y1 - y0 + 1
	var lo := int(interior.size.x * 0.25)
	var hi := int(interior.size.x * 0.75)
	var start := -1
	var end := -1
	for i in range(lo, hi):
		var x: int = x0 + i
		var light := 0
		for y in range(y0, y1 + 1):
			if _is_light(img.get_pixel(x, y)):
				light += 1
		if light < rows * 0.15:
			if start < 0:
				start = x
			end = x
		elif start >= 0 and x - end > 3:
			break
	if start < 0:
		printerr("no divider found in %s" % str(interior))
		return Vector2i(x0 + interior.size.x / 2, x0 + interior.size.x / 2)
	return Vector2i(start, end)


# Blank writing area within [sx..ex]: to the right of the painted label.
func _usable(img: Image, interior: Rect2i, sx: int, ex: int) -> Rect2i:
	var y0 := interior.position.y
	var y1 := y0 + interior.size.y - 1
	var width := ex - sx + 1
	var lo := -1
	var hi := -1
	var start_max := -1
	var end_max := -1
	for y in range(y0, y1 + 1):
		var res := _longest_light_run(img, y, sx, ex)
		if res.y > int(width * 0.35):
			if lo < 0:
				lo = y
			hi = y
			start_max = max(start_max, res.x)
			end_max = max(end_max, res.x + res.y - 1)
	if lo < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(start_max, lo, end_max - start_max + 1, hi - lo + 1)


func _groups(flags: Array, min_gap: int) -> Array:
	var out := []
	var start := -1
	var last := -1
	for i in range(flags.size()):
		if flags[i]:
			if start < 0:
				start = i
			last = i
		elif start >= 0 and i - last > min_gap:
			out.append([start, last])
			start = -1
	if start >= 0:
		out.append([start, last])
	return out


func _bbox(img: Image, x0: int, y0: int, x1: int, y1: int) -> Rect2i:
	var minx := x1
	var maxx := x0
	var miny := y1
	var maxy := y0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if img.get_pixel(x, y).a > A_THR:
				minx = min(minx, x)
				maxx = max(maxx, x)
				miny = min(miny, y)
				maxy = max(maxy, y)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
