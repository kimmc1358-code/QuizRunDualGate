extends SceneTree

# assets/ui_assets/boost_button_sheet.png 를 4장(모드별 부스트 버튼)으로 자른다.
#
#   godot --headless --path . --script tools/slice_boost_sheet.gd
#   godot --headless --path . --script tools/slice_boost_sheet.gd -- -measure
#
# -measure 는 다른 슬라이서와 같은 규칙으로, 찾아낸 원판의 중심과 반지름만
# 찍고 파일은 쓰지 않는다. 검출이 어긋나면 여기서 먼저 드러난다.
#
# 시트 구성: 좌상 sky / 우상 jungle / 좌하 ocean / 우하 dream.
#
# 원판은 검은 배경 위에 자기 색 글로우를 두르고 있어서 밝기로 자르면 글로우가
# 딸려 온다 — 글로우도 채널 하나는 꽉 차 있다. 대신 이웃 픽셀 색차(기울기)로
# 원판의 또렷한 테두리를 찾는다. 글로우는 부드러운 그라데이션이라 기울기가
# 낮고, 원판 가장자리만 튄다.
#
# slice_hud_sheet_v7.gd 와 같은 규칙으로 넷 다 같은 정사각 캔버스에 가운데를
# 맞춰 얹는다. 그래야 Main.gd 의 크기 상수 한 벌이 네 모드에 그대로 통한다.

const SHEET := "res://assets/ui_assets/boost_button_sheet.png"
const OUT_DIR := "res://assets/ui_assets"
const MODES := ["sky", "jungle", "ocean", "dream"]
const OUT_NAME := "boost_v1"
const EDGE_THR := 0.40   # 이웃 픽셀 색차 합 — 원판 테두리는 넘고 글로우는 못 넘는 값
const EDGE_STEP := 2     # 색차를 재는 픽셀 간격
const RADIUS_PAD := 1.0  # 테두리 잉크가 잘리지 않게 반지름에 더하는 여유
const FEATHER := 1.5     # 원 가장자리 알파를 부드럽게 깎는 폭(원본 px)
# 내보내는 한 변(px). 버튼은 BOOST_BUTTON_SIZE(92px)로 그려지는데, 원본 원판은
# 465px 라 그대로 두면 5배 축소가 된다. CLAUDE.md 의 "그려지는 크기로 잘라라"
# 를 따르되, stretch/mode=canvas_items 라 1080p 기기에서는 같은 버튼이 약
# 207px 로 확대된다 — 정확히 92 로 자르면 기기에서 흐려진다. 그래서 2배인
# 184 로 자르고 밉맵을 켠다. pause/mute 아트도 같은 비율이다(117px 캔버스를
# 57.5px 로 그림).
const OUT_SIZE := 184


func _init() -> void:
	var measure_only := OS.get_cmdline_user_args().has("-measure")
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if img == null:
		printerr("could not load %s" % SHEET)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var half := Vector2i(img.get_width() / 2, img.get_height() / 2)

	var discs: Array[Dictionary] = []
	for i in MODES.size():
		var origin := Vector2i((i % 2) * half.x, (i / 2) * half.y)
		var disc := _find_disc(img, origin, half)
		if disc.is_empty():
			printerr("no disc found for %s" % MODES[i])
			quit(1)
			return
		discs.append(disc)
		print("%s: centre=%s radius=%.1f" % [MODES[i], disc.centre, disc.radius])
	if measure_only:
		print("-measure: nothing written (would emit %dx%d)" % [OUT_SIZE, OUT_SIZE])
		quit()
		return

	for i in MODES.size():
		var out := _cut_disc(img, discs[i])
		var dir := "%s/%s" % [OUT_DIR, MODES[i]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var path := "%s/%s.png" % [dir, OUT_NAME]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			printerr("save failed: %s (%d)" % [path, err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [path, OUT_SIZE, OUT_SIZE])
	quit()


# 사분면 안에서 기울기가 EDGE_THR 을 넘는 픽셀의 경계상자를 구한다. 그 상자가
# 곧 원판이므로, 중심은 상자의 가운데이고 반지름은 긴 변의 절반이다.
func _find_disc(img: Image, origin: Vector2i, size: Vector2i) -> Dictionary:
	var min_pos := Vector2i(1 << 30, 1 << 30)
	var max_pos := Vector2i(-1, -1)
	for y in range(origin.y + EDGE_STEP, origin.y + size.y - EDGE_STEP):
		for x in range(origin.x + EDGE_STEP, origin.x + size.x - EDGE_STEP):
			if _edge_strength(img, x, y) < EDGE_THR:
				continue
			min_pos = Vector2i(mini(min_pos.x, x), mini(min_pos.y, y))
			max_pos = Vector2i(maxi(max_pos.x, x), maxi(max_pos.y, y))
	if max_pos.x < 0:
		return {}
	var span := max_pos - min_pos + Vector2i.ONE
	return {
		"centre": Vector2(min_pos) + Vector2(span) * 0.5,
		"radius": maxf(span.x, span.y) * 0.5 + RADIUS_PAD,
	}


func _edge_strength(img: Image, x: int, y: int) -> float:
	var right := img.get_pixel(x + EDGE_STEP, y)
	var left := img.get_pixel(x - EDGE_STEP, y)
	var down := img.get_pixel(x, y + EDGE_STEP)
	var up := img.get_pixel(x, y - EDGE_STEP)
	return absf(right.r - left.r) + absf(right.g - left.g) + absf(right.b - left.b) \
		+ absf(down.r - up.r) + absf(down.g - up.g) + absf(down.b - up.b)


# 원판을 원본 해상도로 오려 낸 뒤 OUT_SIZE 로 줄인다. 반지름 밖은 알파 0,
# 가장자리 FEATHER 폭만 알파를 깎아 계단을 지운다. 배경 글로우는 원 밖이라
# 함께 사라진다.
#
# 줄이기 전에 알파를 곱해 둔다(CLAUDE.md "잘라 낸 그림을 줄일 때는 먼저
# premultiply"). 색과 알파를 따로 줄이면 원 바깥의 투명한 검정이 테두리
# 안쪽으로 끌려 들어와 검은 띠가 생긴다.
func _cut_disc(img: Image, disc: Dictionary) -> Image:
	var radius: float = disc.radius
	var centre: Vector2 = disc.centre
	var side := int(ceil(radius * 2.0))
	var full := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var canvas_centre := Vector2(side, side) * 0.5
	for y in side:
		for x in side:
			var offset := Vector2(x, y) + Vector2(0.5, 0.5) - canvas_centre
			var src := Vector2i((centre + offset).floor())
			var c := Color(0.0, 0.0, 0.0, 0.0)
			if src.x >= 0 and src.y >= 0 and src.x < img.get_width() and src.y < img.get_height():
				c = img.get_pixel(src.x, src.y)
			c.a = clampf((radius - offset.length()) / FEATHER, 0.0, 1.0)
			full.set_pixel(x, y, c)
	full.premultiply_alpha()
	full.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	return _unpremultiplied(full)


# premultiply 를 되돌린다. Image 에는 짝이 되는 함수가 없어서 직접 나눈다.
func _unpremultiplied(img: Image) -> Image:
	var out := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				c = Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a)
			out.set_pixel(x, y, c)
	return out
