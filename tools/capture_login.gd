extends SceneTree

# 로그인 전후의 화면을 찍는다. 헤드리스가 아니라 창을 띄워 돌려야 한다 — 더미
# 렌더러는 그림을 만들지 않는다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_login.gd -- --out <dir>
#
# PC 에서는 진짜 로그인이 안 되므로 PlayGames 에 결과를 직접 넣는다(fake_sign_in
# 과 같은 입구). check_play_games 가 "바뀌었는가" 를 숫자로 보지만, 동그라미 안에
# 사진이 제대로 오려져 들어갔는지, 긴 이름이 줄어 들어가는지는 그려 봐야 안다.

const AVATAR_SRC := "res://assets/characters/bird_v2/bird_happy.png"
const AVATAR_PATH := "user://_capture_login_avatar.png"

var out_dir := "user://login_shots"


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
	var path: String = out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	main.call("_set_state", 0)   # State.MODE_SELECT
	var pg: Node = main.get("play_games")
	var settings: Control = main.get("settings_popup")
	var over: Control = main.get("gameover_popup")
	settings.call("ensure_built")
	over.call("ensure_built")

	main.call("_open_settings")
	await _shot("settings_signed_out")
	settings.visible = false
	over.call("set_result", null, 0.0, 12600, 24, 14000, false, false, 12600)
	over.visible = true
	await _shot("gameover_signed_out")

	# 사진은 게임 안의 새 그림을 빌려 쓴다 — 동그라미에 오려져 들어가는지 보는 데는
	# 사람 얼굴이 아니어도 된다.
	var tex: Texture2D = load(AVATAR_SRC)
	tex.get_image().save_png(AVATAR_PATH)
	pg.call("_on_authenticated", true)
	pg.call("_apply_player", "김철수", AVATAR_PATH)
	await _shot("gameover_signed_in")
	over.visible = false
	main.call("_open_settings")
	await _shot("settings_signed_in")
	settings.visible = false

	# 긴 이름. 계정 줄은 남는 폭에 맞춰 글자를 줄이는데, 버튼이 빠진 뒤의 폭으로
	# 재는지를 본다.
	pg.call("_apply_player", "Christopher Montgomery-Wellington", AVATAR_PATH)
	main.call("_open_settings")
	await _shot("settings_signed_in_long_name")
	settings.visible = false

	pg.call("_on_authenticated", false)
	if FileAccess.file_exists(AVATAR_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AVATAR_PATH))
	quit(0)
