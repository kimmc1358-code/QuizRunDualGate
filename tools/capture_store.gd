extends SceneTree

# 광고 제거를 산 뒤의 화면을 찍는다. 헤드리스가 아니라 창을 띄워 돌려야 한다 —
# 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_store.gd -- --out <dir>
#
# check_store 가 버튼의 글자와 눌림 여부를 재지만, 흐리게 한 "ADS REMOVED" 가
# 판 위에서 어떻게 읽히는지, 광고 아이콘을 뗀 "CONTINUE" 버튼이 비어 보이지
# 않는지는 찍어 봐야 안다. 모드 선택 화면, 설정, 부활 팝업을 두 언어로 찍는다.
#
# 언어를 바꾸면 그 선택이, 판을 새로 차리면(_reset_game) 광고 카운터가 세이브
# 파일에 적힌다. 파일 전체를 받아 두었다가 끝에 되돌린다.

const SAVE_PATH := "user://savegame.cfg"

var out_dir := "user://store_shots"
var _save_backup: PackedByteArray
var _had_save := false


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
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
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("  %s" % name)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var was_korean: bool = TranslationServer.get_locale().begins_with("ko")
	for korean in [true, false]:
		main.call("set_language_korean", korean)
		var tag := "ko" if korean else "en"
		main.set("ads_removed", true)
		main.call("_apply_ads_removed")

		main.call("_set_state", main.State.MODE_SELECT)
		await _shot("%s_mode_select" % tag)

		main.call("_open_settings")
		await _shot("%s_settings" % tag)
		main.get("settings_popup").visible = false

		main.call("_apply_mode", 0)
		main.call("_reset_game")
		main.call("_set_state", main.State.PLAYING)
		main.call("_offer_revive")
		await _shot("%s_revive" % tag)
		main.get("revive_panel").visible = false
	main.call("set_language_korean", was_korean)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
