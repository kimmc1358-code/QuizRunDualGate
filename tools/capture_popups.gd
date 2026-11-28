extends SceneTree

# Shoots every popup over the running play screen, in English and Korean:
# pause, the game over (with the stardust row and its x2), settings
# and about. Not headless — the dummy renderer draws nothing.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_popups.gd -- --out <dir> [--ratio 16x9]
#
# Use it for anything about how a popup looks. check_popup_fit measures
# whether rows fit; this is for whether they read.

const SAVE_PATH := "user://savegame.cfg"

var out_dir := "user://popup_shots"
var _had_save := false
var _save_backup := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
		elif args[i] == "--ratio" and args[i + 1] == "16x9":
			DisplayServer.window_set_size(Vector2i(480, 854))
	DirAccess.make_dir_recursive_absolute(out_dir)
	# The real game writes the real save; take it whole and put it back.
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE_PATH)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _restore_save() -> void:
	if not _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_save_backup)
		f.close()


func _shot(name: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  ", path)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	main.set("tutorial_seen", true)
	main.call("_start_countdown")
	for i in range(30):
		await process_frame

	for lang in [["en", false], ["ko", true]]:
		main.call("set_language_korean", bool(lang[1]))
		for i in range(4):
			await process_frame
		var pause: Control = main.get("pause_panel")
		pause.call("ensure_built")
		pause.visible = true
		await _shot("pause_%s" % lang[0])
		pause.visible = false

		var over: Control = main.get("gameover_popup")
		over.call("ensure_built")
		over.call("set_result", 12600, 24, 14000, false)
		over.call("set_stardust", 186, true, false)
		over.visible = true
		await _shot("gameover_%s" % lang[0])
		over.call("set_stardust_doubled")
		over.call("set_result", 15200, 31, 14000, true)
		await _shot("gameover_best_%s" % lang[0])
		over.visible = false

		main.call("_open_settings")
		await _shot("settings_%s" % lang[0])
		main.get("settings_popup").visible = false

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
