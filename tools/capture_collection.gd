extends SceneTree

# 도감 화면들을 찍는다. 헤드리스가 아니라 창을 띄워 돌려야 한다 — 더미 렌더러는
# 그림을 만들지 않는다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_collection.gd -- --out <dir>
#
# check_collection 이 칸 수와 겹침을 숫자로 보지만, 흐린 국기가 "봤다"로 읽히는지,
# 색 칸의 글자가 읽히는지는 숫자에 안 나온다.
#
# 모은 것은 가짜로 채운다 — 메모리에서만. 저장 함수를 부르지 않으므로 저장
# 파일은 건드리지 않는다.

var out_dir := "user://collection_shots"
# --locale en|ko. 비우면 저장된 언어 그대로. 저장은 하지 않는다 — 로케일만
# 바꾸고 화면을 다시 짓는다.
var locale := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
		elif args[i] == "--locale":
			locale = args[i + 1]
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
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	if locale != "":
		TranslationServer.set_locale(locale)
		m._rebuild_for_language()
		await process_frame

	# 등급마다 앞쪽은 모으고, 몇 개는 봤지만 놓친 것으로.
	m.collected_flags.clear()
	m.seen_flags.clear()
	m.collection_unviewed.clear()
	for t in m.flag_records_by_tier.keys():
		var list: Array = m.flag_records_by_tier[t]
		var take: int = int(list.size() * [0.0, 0.8, 0.45, 0.2, 0.05][int(t)])
		for i in range(list.size()):
			var code: String = str(list[i].code)
			if i < take:
				m.collected_flags[code] = true
				m.seen_flags[code] = true
			elif i < take + 4:
				m.seen_flags[code] = true
	var some: Array = m.collected_flags.keys()
	for i in range(mini(3, some.size())):
		m.collection_unviewed["f:" + str(some[i])] = true
	m.math_solved = PackedInt32Array([240, 64, 31, 12, 4, 0])
	m.collection_unviewed["m:2"] = true
	m.collected_colors.clear()
	var n: int = m.OCEAN_COLOR_NAMES.size()
	for w in range(n):
		for ink in range(n):
			if w != ink and (w * 7 + ink * 3) % 5 < 2:
				m.collected_colors[m._color_key(w, ink)] = true
	m.collection_unviewed["c:" + m._color_key(0, 1)] = true
	m.collected_colors[m._color_key(0, 1)] = true

	m.call("_set_state", 0)   # State.MODE_SELECT
	m._push_collection_badge()
	var w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	for h in [854, 1067]:
		DisplayServer.window_set_size(Vector2i(w, h))
		await process_frame
		await _shot("mode_select_%d" % h)

	# 팝업은 가장 짧은 16:9 에서 — 스크롤 칸이 제일 좁은 경우다.
	DisplayServer.window_set_size(Vector2i(w, 854))
	await process_frame
	m._open_collection()
	var cp: Control = m.collection_popup
	for tab in [0, 1, 2]:
		cp._select_tab(tab)
		await _shot("collection_tab%d" % tab)
	# 아래쪽의 어려운 등급까지 내려 본다.
	cp._select_tab(0)
	await process_frame
	var scroll: ScrollContainer = cp.get("_scroll")
	scroll.scroll_vertical = 1400
	await _shot("collection_tab0_scrolled")
	cp.visible = false

	var go: Control = m.gameover_popup
	go.set_collection_news(3, 2, 1)
	go.set_result(m.sad_face_texture, 100.0, 1840, 9, 5000, false, false, 1840)
	go.visible = true
	await _shot("gameover_news")
	quit(0)
