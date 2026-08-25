extends SceneTree

# Slices assets/ui_assets/ready_start_sheet_v2.png into the 9 countdown /
# game-over word images.
#
#   godot --headless --path . --script tools/slice_ready_sheet.gd
#
# Sheet layout: three row bands (sky / jungle / ocean), each holding
# READY | START | TRY AGAIN left to right.
#
# Each column gets ONE canvas size shared across the three modes, with every
# mode's art centred on it. That is the point of the exercise: the previous
# hand-cut set had a different size per mode and needed MODE_READY_OFFSET_LOCAL
# / MODE_START_OFFSET_LOCAL in Main.gd to shove each one back into place. With
# a shared canvas the art is centred by construction, so those corrections are
# not needed at all.
#
# Rows and columns are split by merging the smallest gaps until the known
# layout count is reached, rather than by a fixed gap threshold — the same
# approach the HUD slicer uses, and for the same reason: the spacing changes
# every time a sheet is redrawn.

const SHEET := "res://assets/ui_assets/ready_start_sheet_v2.png"
const OUT_DIR := "res://assets/ui_assets"
const A_THR := 0.10
const ROW_SPARSE_FRAC := 0.005   # row counts as content at this fraction of the width
const COL_SPARSE_FRAC := 0.005   # column counts as content at this fraction of the band height
const MODES := ["sky", "jungle", "ocean"]
const NAMES := ["Ready", "Start", "TryAgain"]


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img == null:
		printerr("could not load %s" % SHEET)
		quit(1)
		return
	print("SHEET %dx%d  alpha=%d" % [img.get_width(), img.get_height(), img.detect_alpha()])

	var bands := _bands(img)
	if bands.size() != 3:
		printerr("expected 3 row bands, got %d: %s" % [bands.size(), str(bands)])
		quit(1)
		return

	# cells[mode][col] = tight alpha bounding box
	var cells := []
	for mi in range(3):
		var y0: int = bands[mi][0]
		var y1: int = bands[mi][1]
		var cols := _cols(img, y0, y1, 3)
		if cols.size() != 3:
			printerr("%s: expected 3 columns, got %d" % [MODES[mi], cols.size()])
			quit(1)
			return
		var row := []
		for ci in range(3):
			row.append(_bbox(img, cols[ci][0], y0, cols[ci][1], y1))
		cells.append(row)
		print("--- %-6s band y %d..%d   %s=%s  %s=%s  %s=%s" % [
			MODES[mi], y0, y1,
			NAMES[0], str(row[0]), NAMES[1], str(row[1]), NAMES[2], str(row[2])])

	for m in MODES:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, m]))

	for ci in range(3):
		var cw := 0
		var chh := 0
		for mi in range(3):
			var o: Rect2i = cells[mi][ci]
			cw = max(cw, o.size.x)
			chh = max(chh, o.size.y)
		print("")
		print("=== %s : canvas %dx%d" % [NAMES[ci], cw, chh])
		for mi in range(3):
			var o: Rect2i = cells[mi][ci]
			var canvas := Image.create(cw, chh, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			var px := int(round((cw - o.size.x) * 0.5))
			var py := int(round((chh - o.size.y) * 0.5))
			canvas.blit_rect(img, o, Vector2i(px, py))
			canvas.save_png(ProjectSettings.globalize_path("%s/%s/%s.png" % [OUT_DIR, MODES[mi], NAMES[ci]]))
			print("   %-6s art %dx%d centred at (%d,%d)" % [MODES[mi], o.size.x, o.size.y, px, py])
	quit(0)


func _bands(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var min_px := int(w * ROW_SPARSE_FRAC)
	var content := []
	content.resize(h)
	for y in range(h):
		var n := 0
		for x in range(w):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		content[y] = n > min_px
	return _reduce_to(_runs(content), 3)


func _cols(img: Image, y0: int, y1: int, want: int) -> Array:
	var w := img.get_width()
	var rows := y1 - y0 + 1
	var min_px := int(rows * COL_SPARSE_FRAC)
	var dense := []
	dense.resize(w)
	var first := -1
	var last := -1
	for x in range(w):
		var n := 0
		for y in range(y0, y1 + 1):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		dense[x] = n > min_px
		if n > 0:
			if first < 0:
				first = x
			last = x
	var groups := _reduce_to(_runs(dense), want)
	if groups.size() <= 1:
		return [[first, last]] if first >= 0 else []
	# boundaries at gap midpoints, so nothing is clipped off an edge
	var out := []
	for i in range(groups.size()):
		var lo: int = first if i == 0 else int((groups[i - 1][1] + groups[i][0]) / 2) + 1
		var hi: int = last if i == groups.size() - 1 else int((groups[i][1] + groups[i + 1][0]) / 2)
		out.append([lo, hi])
	return out


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
