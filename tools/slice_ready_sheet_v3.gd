extends SceneTree

# assets/ui_assets/ready_start_sheet_v3.png 를 8장(4모드 x READY/START)으로 자른다.
#
#   godot --headless --path . --script tools/slice_ready_sheet_v3.gd
#
# 시트 구성: 위에서부터 sky / jungle / ocean / dream, 각 줄에 READY | START.
#
# v2 슬라이서와 다른 점은 "무엇을 기준으로 가운데를 잡느냐"다. v2 는 그림
# 전체의 경계상자를 캔버스 가운데에 놓았는데, v3 는 모드마다 장식(날개, 잎,
# 산호)이 좌우로 튀어나온 정도가 달라서 그렇게 하면 정작 READY/START 글자가
# 모드마다 다른 자리에 뜬다. 그래서 글자만 따로 찾아 그 중심을 기준으로
# 배치한다 — 캔버스가 하나이므로 게임에서는 같은 크기, 같은 자리에 그려진다.
#
# 글자 찾는 법(_word_bbox): READY 는 주황, START 는 초록이라는 점을 이용해
# 색으로 마스크를 만든 뒤,
#   1. 줄별 개수의 합이 가장 두툼한 구간을 글자 띠로 잡고,
#   2. 그 띠 안에 들어가고 크기가 글자다운 연결 요소만 남기고,
#   3. 가로로 붙은 것끼리 묶어 넓이 합이 가장 큰 묶음을 고르고,
#   4. 윗선/밑선이 어긋나는 것을 뺀다.
# 보석(띠 밖), 배너 테두리(너무 넓음), 잎사귀(색·크기), 반짝이(작음),
# 불가사리(밑선 어긋남)가 각각 다른 단계에서 걸러진다.

const SHEET := "res://assets/ui_assets/ready_start_sheet_v3.png"
const OUT_DIR := "res://assets/ui_assets"
const A_THR := 0.10
const ROW_SPARSE_FRAC := 0.005
const COL_SPARSE_FRAC := 0.005
const MODES := ["sky", "jungle", "ocean", "dream"]
const NAMES := ["Ready", "Start"]
const MIN_BLOB := 40


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

	# art[mode][col] = 그림 전체 경계상자, word[mode][col] = 글자 경계상자
	var art := []
	var word := []
	for mi in range(MODES.size()):
		var y0: int = bands[mi][0]
		var y1: int = bands[mi][1]
		var cols := _cols(img, y0, y1, NAMES.size())
		if cols.size() != NAMES.size():
			printerr("%s: expected %d columns, got %d" % [MODES[mi], NAMES.size(), cols.size()])
			quit(1)
			return
		var art_row := []
		var word_row := []
		for ci in range(NAMES.size()):
			var box := _bbox(img, cols[ci][0], y0, cols[ci][1], y1)
			art_row.append(box)
			word_row.append(_word_bbox(img, box, ci == 0))
		art.append(art_row)
		word.append(word_row)
		print("--- %-6s band y %d..%d" % [MODES[mi], y0, y1])
		for ci in range(NAMES.size()):
			print("      %-5s 그림 %s   글자 %s" % [NAMES[ci], str(art_row[ci]), str(word_row[ci])])

	for m in MODES:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, m]))

	# 글자 중심에서 그림이 네 방향으로 얼마나 뻗는지. 그 최대치를 모아 캔버스를
	# 잡으면 어느 그림도 잘리지 않으면서 글자 중심이 한 점에 모인다.
	#
	# 여덟 장이 한 캔버스를 같이 쓴다 — 모드끼리만 맞추고 READY/START 를 따로
	# 잡으면, 게임에서 폭을 기준으로 크기를 정하는 탓에 READY 에서 START 로
	# 넘어갈 때 글자가 옆으로 튄다.
	var left := 0
	var right := 0
	var top := 0
	var bottom := 0
	for mi in range(MODES.size()):
		for ci in range(NAMES.size()):
			var a: Rect2i = art[mi][ci]
			var c: Vector2i = _center(word[mi][ci])
			left = maxi(left, c.x - a.position.x)
			right = maxi(right, a.position.x + a.size.x - c.x)
			top = maxi(top, c.y - a.position.y)
			bottom = maxi(bottom, a.position.y + a.size.y - c.y)
	# 글자 중심을 캔버스 한가운데에 둔다. 게임 쪽은 캔버스를 화면 가운데에
	# 그리기만 하면 되고(_draw_countdown_image), 그러면 글자가 화면 정가운데에 온다.
	left = maxi(left, right)
	right = left
	top = maxi(top, bottom)
	bottom = top
	var cw := left + right
	var chh := top + bottom
	print("")
	print("=== 캔버스 %dx%d, 글자 중심 (%d,%d)" % [cw, chh, left, top])
	for ci in range(NAMES.size()):
		for mi in range(MODES.size()):
			var a: Rect2i = art[mi][ci]
			var c: Vector2i = _center(word[mi][ci])
			var canvas := Image.create_empty(cw, chh, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			var px: int = left - (c.x - a.position.x)
			var py: int = top - (c.y - a.position.y)
			canvas.blit_rect(img, a, Vector2i(px, py))
			canvas.save_png(ProjectSettings.globalize_path(
				"%s/%s/%s_v3.png" % [OUT_DIR, MODES[mi], NAMES[ci]]))
			print("   %-6s 그림 %dx%d -> (%d,%d)" % [MODES[mi], a.size.x, a.size.y, px, py])
	quit(0)


func _center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


# READY 는 밝은 주황, START 는 밝은 초록. 장식과 겹치지 않게 좁게 잡는다 —
# 오션의 붉은 불가사리(초록기 없음)와 정글의 어두운 잎(밝기 낮음)이 빠지도록.
func _is_word_color(c: Color, orange: bool) -> bool:
	if c.a < 0.6:
		return false
	if orange:
		return c.r > 0.72 and c.g > 0.32 and c.g < 0.92 and c.b < 0.45 and (c.r - c.b) > 0.38
	return c.g > 0.60 and (c.g - c.r) > 0.15 and (c.g - c.b) > 0.25


# 색 마스크 -> 글자가 놓인 가로 띠 -> 그 띠에 속한 연결 요소 -> 가장 큰 묶음.
#
# 씨앗을 "가장 큰 덩어리"로 잡으면 sky READY 처럼 위쪽 보석 장식이 글자보다
# 커서 그쪽으로 끌려간다. 대신 마스크의 줄별 개수가 가장 많은 곳을 글자 띠로
# 본다 — 글자는 다섯 자가 한 줄에 늘어서므로 어떤 장식보다도 폭이 넓다.
func _word_bbox(img: Image, area: Rect2i, orange: bool) -> Rect2i:
	var w := area.size.x
	var h := area.size.y
	var mask := PackedByteArray()
	mask.resize(w * h)
	var rows := PackedInt32Array()
	rows.resize(h)
	for y in range(h):
		var n := 0
		for x in range(w):
			var hit: bool = _is_word_color(img.get_pixel(area.position.x + x, area.position.y + y), orange)
			mask[y * w + x] = 1 if hit else 0
			n += 1 if hit else 0
		rows[y] = n
	# 글자 띠 = 줄별 개수를 다 더했을 때 가장 두툼한 구간.
	#
	# "가장 빽빽한 한 줄"로 잡으면 안 된다: sky/dream 은 배너 테두리가 글자와
	# 같은 금색이라, 가로로 쭉 뻗은 테두리 레일 한 줄이 글자 어느 줄보다도
	# 많다. 다만 레일은 예닐곱 줄로 얇고 글자는 예순 줄쯤 되므로, 구간별 합을
	# 보면 글자가 확실히 이긴다.
	var peak_row := 0
	for y in range(h):
		if rows[y] > rows[peak_row]:
			peak_row = y
	var floor_n: int = int(rows[peak_row] * 0.25)
	var band_top := 0
	var band_bottom := h - 1
	var best_sum := -1
	var run_start := -1
	var run_sum := 0
	for y in range(h + 1):
		var above: bool = y < h and rows[y] > floor_n
		if above:
			if run_start < 0:
				run_start = y
				run_sum = 0
			run_sum += rows[y]
		elif run_start >= 0:
			if run_sum > best_sum:
				best_sum = run_sum
				band_top = run_start
				band_bottom = y - 1
			run_start = -1
	var band_h: int = band_bottom - band_top + 1

	var blobs := _blobs(mask, w, h)
	var kept: Array[Rect2i] = []
	for b in blobs:
		var bb: Rect2i = b["box"]
		# 띠 안에 중심이 있고, 띠 높이만큼 큰 것만 — 작은 반짝이와 잎은 빠진다.
		var mid: int = bb.position.y + bb.size.y / 2
		if mid < band_top or mid > band_bottom:
			continue
		var ratio: float = float(bb.size.y) / float(band_h)
		if ratio < 0.55 or ratio > 1.5:
			continue
		# 글자 한 자가 그림 폭의 3분의 1을 넘을 수는 없다 — 배너 테두리를 뺀다.
		if float(bb.size.x) / float(w) > 0.35:
			continue
		kept.append(bb)
	if kept.is_empty():
		return Rect2i(area.position.x, area.position.y + band_top, w, band_h)
	# 가로로 붙어 있는 것끼리 묶고, 넓이 합이 가장 큰 묶음을 글자로 본다 —
	# 글자는 다섯 덩어리, 장식은 한둘이라 합에서 크게 차이가 난다.
	kept.sort_custom(_left_first)
	var max_gap: float = band_h * 0.5
	var group: Array[Rect2i] = []
	var groups := []
	for bb in kept:
		if group.is_empty():
			group = [bb]
			continue
		var prev: Rect2i = group[group.size() - 1]
		if bb.position.x - (prev.position.x + prev.size.x) > max_gap:
			groups.append(group)
			group = [bb]
		else:
			group.append(bb)
	groups.append(group)
	var best: Array = groups[0]
	var best_area := 0
	for g in groups:
		var total := 0
		for bb in g:
			total += bb.size.x * bb.size.y
		if total > best_area:
			best_area = total
			best = g
	# 마지막으로 윗선/밑선이 어긋나는 것을 뺀다. 글자는 다섯 자가 같은 높이,
	# 같은 baseline 에 놓이지만, 옆에 붙은 장식(오션의 불가사리)은 그렇지 않다.
	var tops := PackedInt32Array()
	var bottoms := PackedInt32Array()
	for bb in best:
		tops.append(bb.position.y)
		bottoms.append(bb.position.y + bb.size.y)
	tops.sort()
	bottoms.sort()
	var mid_top: int = tops[tops.size() / 2]
	var mid_bottom: int = bottoms[bottoms.size() / 2]
	var tol: float = band_h * 0.15
	var aligned: Array[Rect2i] = []
	for bb in best:
		if absf(bb.position.y - mid_top) > tol:
			continue
		if absf(bb.position.y + bb.size.y - mid_bottom) > tol:
			continue
		aligned.append(bb)
	if aligned.size() >= 3:
		best = aligned
	var out: Rect2i = best[0]
	for bb in best:
		out = out.merge(bb)
	return Rect2i(out.position + area.position, out.size)


func _left_first(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.position.x


# 4방향 연결 요소. 재귀는 깊이가 위험하므로 스택으로 훑는다.
func _blobs(mask: PackedByteArray, w: int, h: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out := []
	for sy in range(h):
		for sx in range(w):
			var s := sy * w + sx
			if mask[s] == 0 or seen[s] == 1:
				continue
			var stack: Array[int] = [s]
			seen[s] = 1
			var minx := sx
			var maxx := sx
			var miny := sy
			var maxy := sy
			var n := 0
			while not stack.is_empty():
				var i: int = stack.pop_back()
				n += 1
				var x: int = i % w
				var y: int = i / w
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var j: int = ny * w + nx
					if mask[j] == 1 and seen[j] == 0:
						seen[j] = 1
						stack.append(j)
			if n >= MIN_BLOB:
				out.append({"area": n, "box": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)})
	return out


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
	# 줄 사이가 완전히 비지 않으면(장식이 위아래로 겹치면) 구간이 붙어 나온다.
	# 그럴 때는 가장 높은 구간을 가장 성긴 줄에서 잘라 개수를 맞춘다.
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
	var counts := PackedInt32Array()
	counts.resize(w)
	var first := -1
	var last := -1
	for x in range(w):
		var n := 0
		for y in range(y0, y1 + 1):
			if img.get_pixel(x, y).a > A_THR:
				n += 1
		counts[x] = n
		dense[x] = n > min_px
		if n > 0:
			if first < 0:
				first = x
			last = x
	var groups := _reduce_to(_runs(dense), want)
	# 두 칸 사이가 완전히 비지 않으면(부드럽게 다듬은 시트는 옅은 글로우가
	# 틈을 메운다) 하나로 붙어 나온다. 그럴 때는 가장 넓은 구간을 가장 성긴
	# 열에서 잘라 개수를 맞춘다 — 행을 나눌 때와 같은 방법이다.
	while groups.size() < want and groups.size() > 0:
		var widest := 0
		for i in range(groups.size()):
			if groups[i][1] - groups[i][0] > groups[widest][1] - groups[widest][0]:
				widest = i
		var lo: int = groups[widest][0]
		var hi: int = groups[widest][1]
		var margin: int = int((hi - lo) * 0.25)
		var cut: int = lo + margin
		for x in range(lo + margin, hi - margin + 1):
			if counts[x] < counts[cut]:
				cut = x
		groups.remove_at(widest)
		groups.insert(widest, [cut + 1, hi])
		groups.insert(widest, [lo, cut - 1])
	if groups.size() <= 1:
		return [[first, last]] if first >= 0 else []
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
