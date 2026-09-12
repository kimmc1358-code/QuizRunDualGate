extends SceneTree

# MIX(DREAM) 모드에서 세 퀴즈가 각각 어떻게 그려지는지 실제 화면으로 찍는다.
# 헤드리스가 아니라 창을 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_mix_mode.gd -- --out <dir>
#
# check_mix_mode 가 보는 것은 "무엇이 몇 번 나왔나"까지다. 국기 게이트에
# 숫자가 그려지거나 스트룹 질문 상자가 국기 게이트에서 뜨는 것 같은 문제는
# 종류별로 한 장씩 찍어 사람이 봐야 잡힌다.

var out_dir := "user://mix_shots"


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
	print("  %s" % name)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	main.call("_apply_mode", 3)   # DREAM
	main.set("current_mode", 3)
	main.call("_reset_game")
	main.call("_set_state", 3)    # State.PLAYING
	main.set("current_mode", 3)

	# 주머니를 원하는 종류 하나로 채워 넣고 게이트를 새로 뽑는다. 게임의
	# _spawn_gate 를 그대로 쓰므로 화면에 나오는 것은 실제 플레이와 같다.
	#
	# set() 이 아니라 제자리에서 비우고 채운다. mix_quiz_bag 은 Array[int] 라
	# set() 에 untyped 배열을 주면 조용히 안 들어가고, 주머니가 빈 채로 남아
	# _next_quiz_kind 가 셋을 섞어 버린다 — 처음에 그렇게 찍었더니 파일명은
	# stroop 인데 내용은 수학인 장이 나왔다.
	var names := ["flag", "math", "stroop"]
	for kind in range(3):
		main.get("gates").clear()
		var bag: Array = main.get("mix_quiz_bag")
		bag.clear()
		bag.append(kind)
		main.call("_spawn_gate", view)
		# 게이트를 판정선 근처까지 끌어와 답 상자가 크게 보이게 한다.
		var g: Dictionary = main.get("gates")[0]
		g.x = main.PLAYER_X + 210.0
		main.queue_redraw()
		# 이름은 요청한 종류가 아니라 실제로 생긴 게이트에서 읽는다. 요청한
		# 쪽을 믿으면 강제가 안 먹었을 때 파일명이 조용히 거짓말을 한다.
		if g.quiz_kind != kind:
			print("  WARNING: asked for %s, got %s" % [names[kind], names[g.quiz_kind]])
		await _shot("mix_%d_%s" % [g.quiz_kind, names[g.quiz_kind]])

	quit(0)
