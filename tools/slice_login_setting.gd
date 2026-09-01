extends SceneTree

# assets/ui_assets/main/login_setting_button.png 을 login.png / setting.png 로 나눈다.
#
#   godot --headless --path . --script tools/slice_login_setting.gd
#
# 시트에는 두 버튼이 좌우로 떨어져 있고 주위는 투명한 여백이다. 둘을 각자
# 경계상자로 자른 뒤 같은 크기의 캔버스에 가운데로 얹는다 — 캔버스가 같아야
# 화면에서 두 버튼이 같은 크기로 그려진다.

const SHEET := "res://assets/ui_assets/main/login_setting_button.png"
const OUT_DIR := "res://assets/ui_assets/main/"
const NAMES := ["login", "setting"]
const A_THR := 0.10


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img == null:
		printerr("could not load %s" % SHEET)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("SHEET %dx%d" % [w, h])

	# 열마다 그림이 있는지 보고, 빈 구간으로 둘을 가른다.
	var dense := []
	dense.resize(w)
	for x in range(w):
		var found := false
		for y in range(h):
			if img.get_pixel(x, y).a > A_THR:
				found = true
				break
		dense[x] = found
	var runs := []
	var start := -1
	for x in range(w):
		if dense[x]:
			if start < 0:
				start = x
		elif start >= 0:
			runs.append([start, x - 1])
			start = -1
	if start >= 0:
		runs.append([start, w - 1])
	if runs.size() != NAMES.size():
		printerr("expected %d buttons, got %d: %s" % [NAMES.size(), runs.size(), str(runs)])
		quit(1)
		return

	var boxes := []
	for r in runs:
		boxes.append(_bbox(img, r[0], 0, r[1], h - 1))
	var cw := 0
	var chh := 0
	for b in boxes:
		cw = maxi(cw, (b as Rect2i).size.x)
		chh = maxi(chh, (b as Rect2i).size.y)
	print("캔버스 %dx%d" % [cw, chh])
	for i in range(NAMES.size()):
		var o: Rect2i = boxes[i]
		var canvas := Image.create_empty(cw, chh, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		canvas.blit_rect(img, o, Vector2i(
			int(round((cw - o.size.x) * 0.5)), int(round((chh - o.size.y) * 0.5))))
		canvas.save_png(ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, NAMES[i]]))
		print("   %-8s %s -> %s.png" % [NAMES[i], str(o), NAMES[i]])
	quit(0)


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
