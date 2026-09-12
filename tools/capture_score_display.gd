extends SceneTree

# 점수 표기를 실제 화면에서 찍는다. 헤드리스가 아니라 창을 띄워 돌려야 한다 —
# 더미 렌더러는 그림을 만들지 않으므로 --headless 로는 빈 png 만 나온다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_score_display.gd -- --out <dir>
#
# 자릿수가 바뀌는 값들을 차례로 넣고 HUD 를, 그리고 모드 선택 카드를 찍는다.
# 글자 수 계약은 check_score_format 이 보지만, "칸 안에서 보기 좋은가"는
# 스크립트가 볼 수 없는 것이라 사람이 봐야 한다.

const SHOTS := [0, 85, 1250, 99999, 123456, 1250000]

var out_dir := "user://score_shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _shot(name: String) -> void:
	# 그린 다음 프레임을 기다려야 한다. 같은 프레임에 읽으면 직전 화면이 나온다.
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	# 모드 선택 화면: 카드마다 다른 자릿수를 넣어 한 장에 나란히 담는다.
	var bests: PackedInt32Array = main.get("best_scores")
	for i in range(bests.size()):
		bests[i] = [0, 1250, 123456, 1250000][i % 4]
	if main.get("mode_select_panel") != null:
		main.mode_select_panel.set_best_scores(bests)
	main.call("_set_state", 0)   # State.MODE_SELECT
	await _shot("mode_select")

	# 그리고 게임 화면 HUD. 상단 점수와 그 오른쪽 BEST 를 같은 값으로 둔다.
	main.call("_reset_game")
	main.call("_set_state", 3)   # State.PLAYING
	for v in SHOTS:
		main.set("score", v)
		bests[main.get("current_mode")] = v
		main.queue_redraw()
		await _shot("hud_%d" % v)

	quit(0)
