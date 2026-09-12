extends SceneTree

# 콤보 표시가 숫자에 따라 어떻게 커지는지 찍는다. 헤드리스가 아니라 창을 띄워
# 돌려야 한다 — 더미 렌더러는 그림을 만들지 않는다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_combo.gd -- --out <dir>
#
# 티어는 25 콤보마다 올라가고 76 이상은 4티어 고정이다(COMBO_TIER_*). 그
# 말인즉 4티어를 눈으로 보려면 한 판에서 76번을 연속으로 통과해야 하고, 그건
# 만든 사람도 잘 못 한다. 숫자를 넣어 찍는 편이 빠르고, 자릿수가 늘 때 표시가
# 화면 밖으로 밀리지 않는지도 여기서 같이 보인다.
#
# 판정 뒤의 "펀치"(잠깐 커졌다 돌아오는 것)는 지나간 상태로 찍는다 — 플레이어가
# 실제로 읽는 것은 가라앉은 크기다. 마지막 한 장만 4티어의 화면 테두리 글로우가
# 살아 있는 순간으로 찍는다.

const SHOTS := [1, 25, 26, 50, 51, 75, 76, 100, 250]

var out_dir := "user://combo_shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("  %s  %dx%d" % [name, img.get_width(), img.get_height()])


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	main.call("_apply_mode", 0)
	main.call("_reset_game")
	main.call("_set_state", 2)   # State.COUNTDOWN — 세계는 그려지고 물리는 멈춘다
	var view: Vector2 = main.call("get_viewport_rect").size
	main.call("_spawn_gate", view)
	main.set("score", 4820)
	# 시계를 통째로 세운다. 3·4티어 색은 combo_display_time 을 따라 움직이는데,
	# 세우지 않으면 찍기까지 기다리는 세 프레임 사이에 색이 흘러가 라벨과
	# 실제로 찍힌 색이 어긋난다.
	main.set("paused", true)
	# READY 아트를 접는다. COUNTDOWN 상태라 그대로 두면 화면 한가운데에 READY 가
	# 걸려 콤보 표시를 읽는 데 방해가 된다 — 실제로 콤보 100 과 READY 가 같이
	# 보이는 순간은 게임에 없다.
	main.set("tutorial_active", true)

	for value in SHOTS:
		main.set("combo", value)
		# 펀치가 끝난 자리. 실제로 읽히는 크기는 이쪽이다.
		main.set("combo_display_punch_elapsed", 99.0)
		main.set("combo_glow_elapsed", -1.0)
		main.set("combo_shake_elapsed", -1.0)
		main.set("combo_display_time", 0.0)
		main.queue_redraw()
		await _shot("combo_%03d" % value)

	# 3티어는 주황과 보라 사이를 3Hz(주기 0.333초)로 오가고, 4티어는 무지개를
	# 1.6Hz(주기 0.625초)로 돈다 — 한 장으로는 색을 보여 줄 수 없어서 위상을
	# 나눠 찍는다.
	for phase in [0.0, 0.083, 0.167]:
		main.set("combo", 60)
		main.set("combo_display_punch_elapsed", 99.0)
		main.set("combo_display_time", phase)
		main.queue_redraw()
		await _shot("combo_t3_%03d" % int(round(phase * 1000.0)))
	for phase in [0.0, 0.156, 0.312, 0.469]:
		main.set("combo", 100)
		main.set("combo_display_punch_elapsed", 99.0)
		main.set("combo_display_time", phase)
		main.queue_redraw()
		await _shot("combo_t4_%03d" % int(round(phase * 1000.0)))

	# 4티어가 터지는 순간 — 화면 테두리 글로우와 펀치가 살아 있는 프레임.
	main.set("combo", 100)
	main.set("combo_display_punch_elapsed", 0.10)
	main.set("combo_display_time", 0.0)
	main.set("combo_glow_elapsed", 0.05)
	main.queue_redraw()
	await _shot("combo_100_burst")

	main.set("tutorial_active", false)
	main.set("paused", false)
	quit(0)
