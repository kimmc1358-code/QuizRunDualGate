extends SceneTree

# Play 스토어의 그래픽 이미지(1024x500) 시안을 게임 그림으로 그린다. 헤드리스가
# 아니라 창을 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_feature_graphic.gd -- --out <dir>
#
# 유니콘(MIX)은 넣지 않는다. 조건을 채워야 열리는 숨은 모드라 스토어 그림에
# 나오면 스포일러다. 핵심(로고, 캐릭터)은 가운데 쪽에 둔다 — 기기마다 가장자리가
# 잘리거나 버튼이 겹친다.

const SIZE := Vector2i(1024, 500)
const MSS := preload("res://scripts/ModeSelectScreen.gd")
const BG_MAIN := "res://assets/ui_assets/main/background_main.png"
const TITLE := "res://assets/ui_assets/main/title_main_v2.png"
const SKY_FAR := "res://assets/backgrounds/sky_world/background_far.png"
const SKY_NEAR := "res://assets/backgrounds/sky_world/background_near.png"
const GATE_LEFT := "res://assets/gates/gate_ring/gate_ring_left.png"
const GATE_RIGHT := "res://assets/gates/gate_ring/gate_ring_right.png"
# [파일, 시트 칸 수(가로, 세로), 쓸 칸]. 새는 날개를 든 칸(앱 아이콘과 같은
# 프레임), 드래곤도 날개를 든 칸, 상어는 몸이 곧게 편 칸.
const CHARACTERS := [
	["res://assets/characters/bird_v2/bird_fly.png", Vector2i(2, 2), 2],
	["res://assets/characters/dragon_green/dragon_fly.png", Vector2i(2, 2), 0],
	["res://assets/characters/shark_blue/shark_swim.png", Vector2i(2, 2), 2],
]

var out_dir := "user://feature_graphic"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _render("feature_A_night", _variant_a)
	await _render("feature_B_gate", _variant_b)
	await _render("feature_C_cards", _variant_c)
	await _render("feature_D_worlds", _variant_d)
	await _render("feature_E_worlds_soft", _variant_e)
	quit(0)


func _render(name: String, build: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var canvas := Control.new()
	canvas.size = Vector2(SIZE)
	vp.add_child(canvas)
	build.call(canvas)
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)   # 스토어는 투명을 받지 않는다
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])
	vp.queue_free()


# ---- 시안 A: 메인 화면의 밤하늘, 로고, 캐릭터 셋 ----
func _variant_a(c: Control) -> void:
	# 세로로 긴 배경을 폭에 맞춰 키우고 가운데 조금 위 띠를 쓴다 — 별이 가장
	# 많고 위아래 색이 고르게 섞인 곳.
	var bg: Texture2D = load(BG_MAIN)
	var scale := float(SIZE.x) / bg.get_width()
	var h := bg.get_height() * scale
	_image(c, bg, Rect2(0, -h * 0.30, SIZE.x, h))
	_image(c, load(TITLE), _fit_rect(load(TITLE), Rect2(262, 18, 500, 250)))
	var xs := [260.0, 512.0, 764.0]
	for i in range(CHARACTERS.size()):
		_image(c, _frame(i), Rect2(xs[i] - 105, 265, 210, 210))


# ---- 시안 B: 하늘 모드, 게이트를 지나는 새 ----
func _variant_b(c: Control) -> void:
	_cover(c, load(SKY_FAR))
	_cover(c, load(SKY_NEAR))
	# 로고는 왼쪽 반, 게이트는 오른쪽 반. 링의 오른쪽 절반을 새 뒤에, 왼쪽 절반을
	# 앞에 그려 새가 링 안을 지나는 것처럼 보이게 한다(게임과 앱 아이콘과 같은 방식).
	_image(c, load(TITLE), _fit_rect(load(TITLE), Rect2(40, 90, 470, 320)))
	var ring := Rect2(560, 20, 460, 460)
	_image(c, load(GATE_RIGHT), ring)
	_image(c, _frame(0), Rect2(ring.position.x + ring.size.x * 0.5 - 115, ring.position.y + ring.size.y * 0.51 - 115, 230, 230))
	_image(c, load(GATE_LEFT), ring)


# ---- 시안 D: B 와 C 를 합친 것 — 세 칸, 칸마다 그 모드의 게임 배경과 게이트 ----
#
# 칸마다 원경과 근경을 겹치고, 그 모드의 게이트 링을 캐릭터 앞뒤로 나눠 그려
# 캐릭터가 게이트를 지나는 장면을 만든다. 배경은 가로로 긴 그림이라 칸 높이에
# 맞춰 키운 뒤 가운데를 잘라 쓴다(칸 밖으로 넘치는 부분은 clip 으로 자른다).
const WORLDS := [
	["res://assets/backgrounds/sky_world/", "res://assets/gates/gate_ring/"],
	["res://assets/backgrounds/jungle_world/", "res://assets/gates/gate_ring_jungle/"],
	["res://assets/backgrounds/ocean_world/", "res://assets/gates/gate_ring_ocean/"],
]
func _variant_d(c: Control) -> void:
	_worlds(c, false, 270.0, 222.0, 0.5, Rect2(262, 8, 500, 220))


# ---- 시안 E: D 에서 배경을 흐리게, 게이트와 캐릭터를 크게 ----
#
# D 는 정글 칸의 초록 게이트와 드래곤이 초록 배경에 묻혔다. 게임이 쓰는 흐린
# 배경(_blur, tools/blur_background.ps1 이 구운 것)을 깔면 링과 캐릭터가 떠
# 보이고, 실제 플레이 화면과도 같아진다. 링은 칸 폭(341px)에 거의 차게 키우고,
# 캐릭터는 앱 아이콘과 같은 비율(링의 0.56)로 둔다. 로고는 조금 줄여 가운데
# 칸의 링 윗부분과 덜 겹치게 한다.
func _variant_e(c: Control) -> void:
	_worlds(c, true, 320.0, 176.0, 0.56, Rect2(282, 6, 460, 200))


# 세 칸. blur 는 게임의 흐린 배경을 쓸지, ring 은 링 크기, ring_top 은 링 위끝,
# body_frac 은 링 대비 캐릭터 크기, logo 는 로고가 들어갈 상자.
func _worlds(c: Control, blur: bool, ring_size: float, ring_top: float, body_frac: float, logo: Rect2) -> void:
	var suffix := "_blur.png" if blur else ".png"
	var w := float(SIZE.x) / 3.0
	for i in range(3):
		var panel := Control.new()
		panel.clip_contents = true
		panel.position = Vector2(w * i, 0)
		panel.size = Vector2(w + 1, SIZE.y)
		c.add_child(panel)
		var world: String = WORLDS[i][0]
		var gate: String = WORLDS[i][1]
		_cover_in(panel, load(world + "background_far" + suffix))
		_cover_in(panel, load(world + "background_near" + suffix))
		var ring := Rect2((w - ring_size) * 0.5, ring_top, ring_size, ring_size)
		var body := ring_size * body_frac
		_image(panel, load(gate + "gate_ring_right.png"), ring)
		_image(panel, _frame(i), Rect2(ring.position.x + ring.size.x * 0.5 - body * 0.5,
			ring.position.y + ring.size.y * 0.51 - body * 0.5, body, body))
		_image(panel, load(gate + "gate_ring_left.png"), ring)
		if i > 0:
			var line := ColorRect.new()
			line.color = Color.WHITE
			line.position = Vector2(w * i - 3, 0)
			line.size = Vector2(6, SIZE.y)
			c.add_child(line)
	_image(c, load(TITLE), _fit_rect(load(TITLE), logo))


# 칸(부모 Control)을 빈틈없이 덮는 크기로, 칸 가운데에 놓는다.
func _cover_in(panel: Control, tex: Texture2D) -> void:
	var s := maxf(panel.size.x / tex.get_width(), panel.size.y / tex.get_height())
	var size := Vector2(tex.get_width(), tex.get_height()) * s
	_image(panel, tex, Rect2((panel.size - size) * 0.5, size))


# ---- 시안 C: 세 모드 카드 색, 로고, 칸마다 캐릭터 ----
func _variant_c(c: Control) -> void:
	var w := float(SIZE.x) / 3.0
	for i in range(3):
		var gradient := Gradient.new()
		gradient.set_color(0, MSS.CARD_FILL_TOP[i])
		gradient.set_color(1, MSS.CARD_FILL_BOTTOM[i])
		var fill := GradientTexture2D.new()
		fill.gradient = gradient
		fill.fill_from = Vector2(0, 0)
		fill.fill_to = Vector2(0, 1)
		fill.width = 4
		fill.height = 256
		_image(c, fill, Rect2(w * i, 0, w + 1, SIZE.y), TextureRect.STRETCH_SCALE)
		if i > 0:
			var line := ColorRect.new()
			line.color = Color.WHITE
			line.position = Vector2(w * i - 3, 0)
			line.size = Vector2(6, SIZE.y)
			c.add_child(line)
		_image(c, _frame(i), Rect2(w * i + w * 0.5 - 115, 250, 230, 230))
	_image(c, load(TITLE), _fit_rect(load(TITLE), Rect2(252, 12, 520, 250)))


# 시트의 한 칸.
func _frame(index: int) -> Texture2D:
	var entry: Array = CHARACTERS[index]
	var sheet: Texture2D = load(entry[0])
	var grid: Vector2i = entry[1]
	var cell := Vector2(sheet.get_width() / grid.x, sheet.get_height() / grid.y)
	var n: int = entry[2]
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(n % grid.x, n / grid.x) * cell, cell)
	return atlas


# 화면을 빈틈없이 덮는 크기로 가운데에 놓는다(넘치는 쪽은 잘린다).
func _cover(c: Control, tex: Texture2D) -> void:
	var s := maxf(float(SIZE.x) / tex.get_width(), float(SIZE.y) / tex.get_height())
	var size := Vector2(tex.get_width(), tex.get_height()) * s
	_image(c, tex, Rect2((Vector2(SIZE) - size) * 0.5, size))


# 비율을 지켜 상자 안에 들어가는 가장 큰 사각형, 상자 가운데.
func _fit_rect(tex: Texture2D, box: Rect2) -> Rect2:
	var s := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
	var size := Vector2(tex.get_width(), tex.get_height()) * s
	return Rect2(box.position + (box.size - size) * 0.5, size)


func _image(c: Control, tex: Texture2D, rect: Rect2, stretch := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> void:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = stretch
	t.position = rect.position
	t.size = rect.size
	c.add_child(t)
