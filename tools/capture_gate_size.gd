extends SceneTree

# 초반 게이트 확대(_gate_hole_scale)를 눈으로 보려고 찍는다. 헤드리스가 아니라
# 창을 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_gate_size.gd -- --out <dir>
#   ... --script res://tools/capture_gate_size.gd -- --mode 2
#
# check_gate_reach 는 구멍이 몇 px 인지, 판정과 그림이 같은 배수를 쓰는지까지
# 본다. 그러나 "1.2배가 정말 넉넉해 보이는가, 30게이트에 걸쳐 줄어드는 것이
# 눈에 띄는가"는 숫자가 답하지 못한다 — 테스터가 어렵다고 한 것도 px 가 아니라
# 화면이었다.
#
# 같은 자리(플레이어 바로 앞)에 게이트를 하나만 놓고 gates_passed 만 바꿔 찍으므로
# 장끼리 겹쳐 보면 링이 줄어드는 것만 달라진다.
#
# _reset_game 은 전면 광고 카운터를 올리고 저장한다. 세이브 파일 전체를 받아
# 두었다가 끝에 되돌린다 — 체커들이 하는 것과 같다.

const SAVE_PATH := "user://savegame.cfg"
const GATE_X_AHEAD := 210.0     # 플레이어 앞 몇 px 에 세워 찍을지
const SHOTS := [0, 5, 10, 15, 20, 25, 30, 40]

var out_dir := "user://gate_size_shots"
var mode := 0
var _save_backup: PackedByteArray
var _had_save := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
		if args[i] == "--mode":
			mode = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _shot(name: String) -> void:
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

	# 튜토리얼은 첫 판에 한 번 뜨고 화면을 덮는다.
	main.set("tutorial_seen", true)
	main.call("_apply_mode", mode)
	main.set("current_mode", mode)
	main.call("_reset_game")
	main.call("_set_state", main.State.PLAYING)
	main.set("current_mode", mode)

	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var base: float = main.call("_gate_ring_inner_zone_height", 1.0)
	print("capture_gate_size: mode %d, full-size hole %.1f px" % [mode, base])

	for passed in SHOTS:
		main.set("gates_passed", passed)
		main.set("score", passed * 20)
		# 매번 화면 한가운데에서 다시 뽑는다. 그러지 않으면 구멍 높이가 아니라
		# 직전 게이트에서 얼마나 움직였는지가 장마다 달라져 비교가 안 된다.
		main.set("last_zone_center", main.get("player_y"))
		main.get("gates").clear()
		main.call("_spawn_gate", view)
		var g: Dictionary = main.get("gates")[0]
		g.x = main.PLAYER_X + GATE_X_AHEAD
		var scale: float = float(g.get("hole_scale", 1.0))
		var hole: float = float(g.top_zone_bottom) - float(g.top_zone_top)
		print("  gate %2d  %.2fx  hole %.1f px" % [passed, scale, hole])
		main.queue_redraw()
		await _shot("gate_%02d_%.2fx" % [passed, scale])

	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
