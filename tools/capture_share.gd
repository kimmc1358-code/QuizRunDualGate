extends SceneTree

# SHARE 가 보내는 점수 카드를 실제로 그려 저장한다. 헤드리스가 아니라 창을
# 띄워 돌려야 한다 — 더미 렌더러는 빈 png 를 준다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_share.gd -- --out <dir>
#
# check_share 가 자리와 글자 폭을 재지만, 카드 색 위에 흰 글자가 읽히는지,
# 캐릭터가 어색하지 않은지는 그림을 봐야 안다. 두 언어, 네 모드, 짧은 점수와
# int 끝까지 가는 점수, 신기록과 아닌 것을 섞어 찍는다.

const SHOTS := [
	["ko", 0, 12340, true],
	["en", 1, 0, false],
	["ko", 2, 123456, false],
	["en", 3, 2147483647, true],
]

var out_dir := "user://share_shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var card = main.get("share_card")
	var dirs: Array = main.get("MODE_CHARACTER_DIR")
	var happy: Array = main.get("MODE_CHARACTER_HAPPY_FILE")
	var was_locale: String = TranslationServer.get_locale()
	for shot in SHOTS:
		TranslationServer.set_locale(shot[0])
		var mode: int = shot[1]
		var face: Texture2D = load(str(dirs[mode]) + str(happy[mode]))
		var img: Image = await card.render(mode, shot[2], shot[3], face)
		var name := "share_%s_mode%d_%d%s.png" % [shot[0], mode, shot[2], "_new" if shot[3] else ""]
		if img == null or img.is_empty():
			print("  %s: EMPTY" % name)
			continue
		img.save_png(out_dir.path_join(name))
		print("  %s  %dx%d" % [name, img.get_width(), img.get_height()])
		print("    text: %s" % card.share_text(mode, shot[2]).replace("\n", "  |  "))
	TranslationServer.set_locale(was_locale)
	quit(0)
