extends SceneTree

# OCEAN(스트룹) 모드의 문제 상자를 두 언어로 찍는다. 헤드리스가 아니라 창을
# 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_ocean_quiz.gd -- --out <dir> [--tag <이름>]
#
# check_ocean_prompt 가 질문과 단어의 px 크기를 재지만, 그 크기가 이 상자
# 아트 위에서 "읽히는가"는 찍어서 봐야 안다. 언어마다 가장 넓은 색 단어를
# 넣는다 — 줄이 넘치거나 줄어드는 것은 그 단어에서 먼저 나타나고, 어느 단어가
# 가장 넓은지는 게임의 배치 함수(_ocean_quiz_layout)로 잰다.
#
# 화면 전체와 상자 부분만 잘라 낸 것을 함께 남긴다.

var out_dir := "user://ocean_quiz_shots"
var tag := "now"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
		elif args[i] == "--tag":
			tag = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _shot(name: String, main: Node2D, view: Vector2) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	var box: Rect2 = main.call("_quiz_box_rect", view)
	var r := Rect2i(box.grow(12.0)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	img.get_region(r).save_png(out_dir.path_join(name + "_box.png"))
	print("  %s  (+ _box)" % name)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var view: Vector2 = main.get_viewport_rect().size
	main.call("_apply_mode", 2)   # OCEAN
	main.set("current_mode", 2)
	main.call("_reset_game")
	main.call("_set_state", 3)    # State.PLAYING
	main.set("current_mode", 2)

	var names: Array = main.get("OCEAN_COLOR_NAMES")
	var was_locale: String = TranslationServer.get_locale()
	for loc in ["ko", "en"]:
		TranslationServer.set_locale(loc)
		var rect: Rect2 = main.call("_quiz_box_rect", view)
		var widest := 0
		var best := -1.0
		for i in range(names.size()):
			var lay: Dictionary = main.call("_ocean_quiz_layout", rect, TranslationServer.translate(str(names[i])))
			if float(lay.word_width) > best:
				best = float(lay.word_width)
				widest = i
		main.get("gates").clear()
		main.call("_spawn_gate", view)
		var g: Dictionary = main.get("gates")[0]
		g.x = main.PLAYER_X + 210.0
		g.ocean_word_index = widest
		main.queue_redraw()
		await _shot("%s_%s" % [tag, loc], main, view)
	TranslationServer.set_locale(was_locale)
	quit(0)
