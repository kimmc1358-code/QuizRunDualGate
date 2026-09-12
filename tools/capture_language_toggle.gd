extends SceneTree

# 설정 팝업의 ENG/KOR 토글과, 언어를 바꾼 뒤 화면들이 실제로 다시 지어지는지를
# 눈으로 본다. 헤드리스가 아니라 창을 띄워 돌려야 한다 — 더미 렌더러는 그림을
# 만들지 않는다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_language_toggle.gd -- --out <dir>
#
# 숫자로 잡을 수 없는 것이 둘이다. 하나는 한글이 카페24 써라운드로 나오는지,
# 다른 하나는 줄이 하나 늘어난 설정 판 안에서 맨 아래 버전 표시까지 다 들어가
# 있는지 — 둘 다 그려 봐야 안다.

const SAVE_PATH := "user://savegame.cfg"

var out_dir := "user://language_shots"
var _had_save := false
var _save_backup := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 이 스크립트는 진짜 게임을 돌리므로 진짜 저장 파일에 쓴다. 통째로 떠 두고
	# 끝날 때 되돌린다 — 언어를 바꾸는 것만으로 이 기기의 설정이 바뀌면 안 된다.
	_backup_save()
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE_PATH)


func _restore_save() -> void:
	if not _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not restore %s" % SAVE_PATH)
		return
	f.store_string(_save_backup)
	f.close()


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

	var bests: PackedInt32Array = main.get("best_scores")
	for i in range(bests.size()):
		bests[i] = [1250, 8420, 123456, 0][i % 4]
	if main.get("mode_select_panel") != null:
		main.mode_select_panel.set_best_scores(bests)
	main.call("_set_state", 0)   # State.MODE_SELECT

	for lang in [["en", false], ["ko", true]]:
		# 설정 팝업을 통하지 않고 Main 의 진입점을 직접 부른다 — 토글을 탭하면
		# 부르는 곳과 같은 함수다.
		main.call("set_language_korean", bool(lang[1]))
		# 다시 짓기는 call_deferred 로 미뤄져 있다.
		for i in range(4):
			await process_frame
		await _shot("mode_select_%s" % lang[0])
		main.call("_open_settings")
		await _shot("settings_%s" % lang[0])
		# 16:9 는 담을 것이 판보다 길어져 줄이 눌리는 유일한 비율이다.
		DisplayServer.window_set_size(Vector2i(480, 854))
		await process_frame
		await _shot("settings_%s_16x9" % lang[0])
		DisplayServer.window_set_size(Vector2i(480, 1067))
		await process_frame
		main.get("settings_popup").visible = false
		# 부활 팝업의 아랫줄은 로그인한 사람에게만 나온다 — 안 켜고 찍으면
		# 정작 번역이 빠져 있던 그 줄이 화면에 없다.
		# 진짜 경로로 띄운다 — 캐릭터까지 들어간 판이라야 점수 줄이 들어갈
		# 자리가 정말 있는지 보인다. 16:9 도 함께 찍는다: 판 높이는 화면 비율
		# 대비라 가장 짧은 화면이 가장 빡빡하다.
		var revive: Control = main.get("revive_panel")
		main.set("score", 12600)
		main.set("leaderboard_score", 9800)
		for who in [["in", true], ["out", false]]:
			main.set("player_logged_in", bool(who[1]))
			main.call("_offer_revive")
			await _shot("revive_%s_%s" % [who[0], lang[0]])
			if who[0] == "in":
				DisplayServer.window_set_size(Vector2i(480, 854))
				await process_frame
				await _shot("revive_%s_%s_16x9" % [who[0], lang[0]])
				DisplayServer.window_set_size(Vector2i(480, 1067))
				await process_frame
			revive.visible = false

		# 게임오버는 세 얼굴이 다 다른 글자를 쓴다. 순위표 줄이 나오는 것은
		# 로그인 + 부활한 판이고, 기록까지 남은 점수 줄은 아깝게 놓쳤을
		# 때만이라 기록의 80% 를 넘는 점수를 넣어야 나온다.
		var over: Control = main.get("gameover_popup")
		over.call("ensure_built")
		# BEST 판은 신기록이 아닐 때만 뜬다. 로그인 여부는 가운데 안내 상자만
		# 바꾸지만, 상단 글자가 둘 다에서 같은지 보려면 둘 다 찍어야 한다.
		for shot in [["in", true], ["out", false]]:
			over.call("set_result", null, 0.0, 12600, 24, 14000,
				false, bool(shot[1]), 9800)
			over.visible = true
			await _shot("gameover_%s_%s" % [shot[0], lang[0]])
			over.visible = false

		var about: Control = main.get("about_popup")
		about.call("ensure_built")
		about.visible = true
		await _shot("about_%s" % lang[0])
		about.visible = false

	main.call("set_language_korean", false)
	for i in range(4):
		await process_frame
	_restore_save()
	quit(0)
