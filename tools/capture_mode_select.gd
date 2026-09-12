extends SceneTree

# 모드 선택 화면을 화면 비율별로 찍는다. 헤드리스가 아니라 창을 띄워 돌려야
# 한다 — 더미 렌더러는 그림을 만들지 않으므로 --headless 로는 빈 png 만 나온다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_mode_select.gd -- --out <dir>
#
# check_mode_select_layout 이 겹침과 간격을 숫자로 보지만, 카드가 늘어난 만큼
# 아트가 눌려 보이는지, 여백이 허전한지는 숫자에 안 나온다. 이 화면은 남는
# 세로를 나눠 갖는 구조라 비율마다 다르게 보이므로, 한 비율만 찍으면 다른
# 비율에서 무너진 것을 못 본다.

const RATIOS := [
	["16x9", 854], ["18x9", 960], ["20x9", 1067], ["21x9", 1120],
]

var out_dir := "user://mode_select_shots"


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

	# 점수 판이 빈 채로 찍히면 카드 아래쪽이 실제보다 헐거워 보인다.
	var bests: PackedInt32Array = main.get("best_scores")
	for i in range(bests.size()):
		bests[i] = [1250, 8420, 123456, 0][i % 4]
	if main.get("mode_select_panel") != null:
		main.mode_select_panel.set_best_scores(bests)
	main.call("_set_state", 0)   # State.MODE_SELECT

	var w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h: int = int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	for row in RATIOS:
		DisplayServer.window_set_size(Vector2i(w, int(row[1])))
		await process_frame
		await _shot("mode_select_%s" % row[0])

	# 히든 모드 카드는 잠금/해금 두 얼굴이다. 설명 바 문구가 바뀌는 자리라
	# 둘 다 찍는다 — 잠금 쪽에는 진행도 숫자가 박혀 있어 길이도 다르다.
	var screen = main.get("mode_select_panel")
	if screen != null:
		var modes: Array = screen.get("CARD_MODES")
		var hidden_card: int = modes.find(screen.get("MODE_HIDDEN"))
		var required: int = screen.get("hidden_modes_required")
		var gates: int = screen.get("hidden_gates_needed")
		if hidden_card >= 0:
			for entry in [["locked", 1], ["open", required]]:
				screen.call("set_hidden_progress", int(entry[1]), required, gates)
				screen.call("_select", hidden_card, false)
				await _shot("mode_select_hidden_%s" % entry[0])
			# 잠금 판은 이름판과 점수판 사이에 맞춰 줄어들므로 화면이 짧을수록
			# 작아진다. 16:9 가 가장 좁은 경우라 읽히는지 따로 본다.
			DisplayServer.window_set_size(Vector2i(w, int(base_h)))
			await process_frame
			screen.call("set_hidden_progress", 1, required, gates)
			screen.call("_select", hidden_card, false)
			await _shot("mode_select_hidden_locked_16x9")
			# 실제 진행도로 되돌린다.
			main.call("_push_hidden_progress")
			screen.call("_select", 0, false)

	quit(0)
