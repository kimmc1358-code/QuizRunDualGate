extends SceneTree

# Play 스토어 휴대전화 스크린샷(9:16, 1080x1920)을 게임에서 직접 찍는다. 헤드리스가
# 아니라 창을 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_store_screenshots.gd -- --out <dir>
#
# 폰으로 찍으면 안 되는 이유: 요즘 폰은 19.5:9 같은 긴 화면이라 스토어가 받는
# 16:9 / 9:16 에 맞지 않는다. 게임의 기본 화면 480x854 는 9:16 이므로, 그 화면을
# 2.25배 해상도로 그리면 된다.
#
# 창을 1080x1920 으로 키우는 대신 화면 밖 SubViewport 에서 돌린다. 개발 PC 의
# 모니터가 세로 1440 이라 그 창은 만들 수 없다. SubViewport 는 1080x1920 으로
# 그리되 게임에는 480x854 라고 알려(size_2d_override) 배치가 평소와 같게 한다.
#
# 믹스(유니콘) 모드는 잠긴 카드로만 보인다. 조건을 채워야 열리는 숨은 모드다.
#
# 언어를 바꾸면 그 선택이, 판을 끝내면 최고 기록과 광고 카운터가 세이브 파일에
# 적힌다. 파일 전체를 받아 두었다가 끝에 되돌린다.

const OUT_SIZE := Vector2i(1080, 1920)
const SAVE_PATH := "user://savegame.cfg"
# 스크린샷에 보일 점수들. 너무 작으면 초라하고 너무 크면 거짓말 같다.
const CARD_BESTS := [2350, 1680, 3120, 0]
const PLAY_SCORES := [1250, 980, 1430]
const GAMEOVER_SCORE := 2480

var out_dir := "user://store_shots"
var _vp: SubViewport
var _main: Node2D
var _save_backup: PackedByteArray
var _had_save := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	_vp = SubViewport.new()
	_vp.size = OUT_SIZE
	_vp.size_2d_override = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	_vp.size_2d_override_stretch = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.call_deferred("add_child", _vp)
	_main = load("res://scenes/Main.tscn").instantiate()
	_vp.call_deferred("add_child", _main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)   # 스토어는 투명을 받지 않는다
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	await process_frame
	await process_frame
	while _main.get("boot_pending"):
		await process_frame
	var main := _main
	# 튜토리얼은 첫 판에 한 번 뜬다 — 스크린샷에는 필요 없다.
	main.set("tutorial_seen", true)
	var view := Vector2(_vp.size_2d_override)
	var was_korean: bool = TranslationServer.get_locale().begins_with("ko")

	for korean in [true, false]:
		var tag := "ko" if korean else "en"
		main.call("set_language_korean", korean)
		await process_frame

		# 1. 모드 선택 — 기록이 조금 쌓인 모습, 믹스 카드는 잠긴 채.
		var bests: PackedInt32Array = main.get("best_scores")
		for i in range(bests.size()):
			bests[i] = CARD_BESTS[i % CARD_BESTS.size()]
		main.set("best_scores", bests)
		main.call("_set_state", main.State.MODE_SELECT)
		var screen = main.get("mode_select_panel")
		screen.call("set_best_scores", bests)
		var required: int = screen.get("hidden_modes_required")
		var gates_needed: int = screen.get("hidden_gates_needed")
		screen.call("set_hidden_progress", 1, required, gates_needed)
		screen.call("_select", 0, false)
		await _shot("%s_1_mode_select" % tag)

		# 2~4. 모드별 플레이 — 게이트 하나가 퀴즈를 들고 다가오는 순간.
		for mode in range(3):
			main.call("_apply_mode", mode)
			main.set("current_mode", mode)
			main.call("_reset_game")
			main.call("_set_state", main.State.PLAYING)
			main.set("current_mode", mode)
			main.set("score", PLAY_SCORES[mode])
			main.get("gates").clear()
			main.call("_spawn_gate", view)
			var g: Dictionary = main.get("gates")[0]
			g.x = main.PLAYER_X + 210.0
			main.queue_redraw()
			await _shot("%s_%d_play_%s" % [tag, mode + 2, ["sky", "jungle", "ocean"][mode]])

		# 5. 신기록 게임오버.
		main.call("_apply_mode", 0)
		main.set("current_mode", 0)
		main.call("_reset_game")
		main.call("_set_state", main.State.PLAYING)
		main.set("current_mode", 0)
		main.set("score", GAMEOVER_SCORE)
		main.set("leaderboard_score", GAMEOVER_SCORE)
		main.set("max_combo", 18)
		main.call("_finish_run")
		await _shot("%s_5_gameover" % tag)
		main.get("gameover_popup").visible = false

	main.call("set_language_korean", was_korean)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
