extends SceneTree

# assets/ui_assets/hud_sheet_v7.png 를 12장(4모드 x 일시정지/퀴즈박스/음소거)으로 자른다.
#
#   godot --headless --path . --script tools/slice_hud_sheet_v7.gd
#
# 시트 구성: 위에서부터 sky / jungle / ocean / dream, 각 줄에
# 일시정지 | 퀴즈박스 | 음소거.
#
# 조각마다 ONE 캔버스를 모드끼리 나눠 쓰고 그 위에 가운데 맞춰 얹는다. 모드별로
# 장식(날개, 잎, 산호)이 튀어나온 정도가 달라서, 각자 자기 경계상자로 자르면
# 게임에서 크기와 안쪽 여백이 모드마다 달라진다. 캔버스를 공유하면 Main.gd 의
# 비율 상수 한 벌이 네 모드에 그대로 통한다.

const SHEET := "res://assets/ui_assets/hud_sheet_v7.png"
const OUT_DIR := "res://assets/ui_assets"
const A_THR := 0.10
const ROW_SPARSE_FRAC := 0.004
const COL_SPARSE_FRAC := 0.02
const MODES := ["sky", "jungle", "ocean", "dream"]
const NAMES := ["pause_v3", "quiz_box_v3", "mute_v3"]


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img == null:
		printerr("could not load %s" % SHEET)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	print("SHEET %dx%d" % [img.get_width(), img.get_height()])

	var bands := _bands(img, MODES.size())
	if bands.size() != MODES.size():
		printerr("expected %d row bands, got %d: %s" % [MODES.size(), bands.size(), str(bands)])
		quit(1)
		return

	var cells := []
	for mi in range(MODES.size()):
		var y0: int = bands[mi][0]
		var y1: int = bands[mi][1]
		var cols := _cols(img, y0, y1, NAMES.size())
		if cols.size() != NAMES.size():
			printerr("%s: expected %d columns, got %d" % [MODES[mi], NAMES.size(), cols.size()])
			quit(1)
			return
		var row := []
		for ci in range(NAMES.size()):
			row.append(_bbox(img, cols[ci][0], y0, cols[ci][1], y1))
		cells.append(row)
		print("--- %-6s band y %d..%d  %s | %s | %s" % [MODES[mi], y0, y1,
			str(row[0]), str(row[1]), str(row[2])])

	for m in MODES:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, m]))

	for ci in range(NAMES.size()):
		var cw := 0
		var chh := 0
		for mi in range(MODES.size()):
			var o: Rect2i = cells[mi][ci]
			cw = maxi(cw, o.size.x)
			chh = maxi(chh, o.size.y)
		print("")
		print("=== %s : 캔버스 %dx%d" % [NAMES[ci], cw, chh])
		for mi in range(MODES.size()):
			var o: Rect2i = cells[mi][ci]
			var canvas := Image.create_empty(cw, chh, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			var px: int = int(round((cw - o.size.x) * 0.5))
			var py: int = int(round((chh - o.size.y) * 0.5))
			canvas.blit_rect(img, o, Vector2i(px, py))
			canvas.save_png(ProjectSettings.globalize_path(
				"%s/%s/%s.png" % [OUT_DIR, MODES[mi], NAMES[ci]]))
			print("   %-6s 그림 %dx%d -> (%d,%d)" % [MODES[mi], o.size.x, o.size.y, px, py])
	quit(0)


func _bands(img: Image, want: int) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var min_px := int(w * ROW_SPARSE_FRAC)
	var counts := PackedInt32Array()
	counts.resize(h)
	var content := []
	content.resize(h)
	for y in range(h):
		var n := 0
		for x in range(w):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		counts[y] = n
		content[y] = n > min_px
	var runs := _reduce_to(_runs(content), want)
	# 줄 사이가 완전히 비지 않으면 구간이 붙어 나온다. 그럴 때는 가장 높은
	# 구간을 가장 성긴 줄에서 잘라 개수를 맞춘다.
	while runs.size() < want and runs.size() > 0:
		var tallest := 0
		for i in range(runs.size()):
			if runs[i][1] - runs[i][0] > runs[tallest][1] - runs[tallest][0]:
				tallest = i
		var lo: int = runs[tallest][0]
		var hi: int = runs[tallest][1]
		var margin: int = int((hi - lo) * 0.25)
		var cut: int = lo + margin
		for y in range(lo + margin, hi - margin + 1):
			if counts[y] < counts[cut]:
				cut = y
		runs.remove_at(tallest)
		runs.insert(tallest, [cut + 1, hi])
		runs.insert(tallest, [lo, cut - 1])
	return runs


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
	# 경계는 빈 구간의 한가운데에 둔다 — 어느 쪽 그림도 잘리지 않게.
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
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
