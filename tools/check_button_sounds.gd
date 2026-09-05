extends SceneTree

# 버튼마다 제 소리가 걸려 있는지, 그리고 그 파일이 정말 있는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_button_sounds.gd
#
# 소리는 없어도 아무 일이 안 일어난다. PopupBase 는 파일을 못 찾으면 그 버튼을
# 조용히 무음 처리하고 넘어가므로(그래야 소리 없이도 게임이 돈다), 이름을
# 바꿔 놓고 파일을 안 넣었을 때 화면에서 달라지는 것이 하나도 없다. 눌러 보고
# "어, 소리가 안 나네" 하기 전까지는 모른다.
#
# 그래서 둘을 본다: 어떤 버튼이 어떤 소리를 달라고 하는가, 그리고 그 이름으로
# 실제 파일이 찾아지는가.

const SOUND_DIR := "res://assets/audio/"
const EXTENSIONS := [".ogg", ".wav"]

var _fail := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail_msg(msg: String) -> void:
	_fail += 1
	print("  FAIL  %s" % msg)


func _resolve(name: String) -> String:
	for ext in EXTENSIONS:
		var path: String = SOUND_DIR + name + ext
		if ResourceLoader.exists(path):
			return path
	return ""


# 팝업 아래 모든 버튼을 훑는다. 노드 이름이 아니라 sound 메타를 본다 —
# PopupBase 가 실제로 재생할 때 보는 것이 그것이다.
func _collect(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is Control and child.has_meta("sound"):
			var art: String = str(child.get_meta("sound"))
			if not out.has(art):
				out[art] = 0
			out[art] += 1
		_collect(child, out)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var popups := {
		"pause": main.get("pause_panel"),
		"revive": main.get("revive_panel"),
		"gameover": main.get("gameover_popup"),
		"settings": main.get("settings_popup"),
		"about": main.get("about_popup"),
	}
	var wanted := {}
	for label in popups:
		var popup: Control = popups[label]
		popup.call("ensure_built")
		await process_frame
		var found := {}
		_collect(popup, found)
		if found.is_empty():
			_fail_msg("%s 팝업에 소리가 걸린 버튼이 하나도 없다" % label)
		for art in found:
			if not wanted.has(art):
				wanted[art] = 0
			wanted[art] += found[art]
		print("  %-9s %s" % [label, str(found)])

	# 금색 버튼은 넷이다. 하나라도 다른 소리를 달라고 하면 팝업마다 소리가
	# 갈린다 — 나란히 눌러 보기 전에는 모르는 종류다.
	var gold: String = load("res://scripts/PopupBase.gd").get_script_constant_map()["GOLD_SOUND_NAME"]
	var cream: String = load("res://scripts/PopupBase.gd").get_script_constant_map()["CREAM_SOUND_NAME"]
	print("")
	print("  금색 버튼 소리 \"%s\" x%d, 크림 버튼 소리 \"%s\" x%d" % [
		gold, int(wanted.get(gold, 0)), cream, int(wanted.get(cream, 0))])
	if int(wanted.get(gold, 0)) != 4:
		_fail_msg("금색 버튼이 넷이어야 하는데 %d 개가 \"%s\" 를 쓴다 (RESUME / PLAY AGAIN / WATCH AD / REMOVE ADS)" % [
			int(wanted.get(gold, 0)), gold])

	# 이름이 걸려 있어도 파일이 없으면 무음이다. 여기가 이 검사의 요점이다.
	for art in wanted:
		var path: String = _resolve(art)
		if path == "":
			_fail_msg("\"%s\" 를 %d 개 버튼이 쓰는데 %s%s 로 찾을 수 있는 파일이 없다 — 그 버튼들은 무음이다" % [
				art, int(wanted[art]), SOUND_DIR, str(EXTENSIONS)])
		else:
			print("  ok    \"%s\" -> %s" % [art, path])

	# 메인 화면의 START 는 이 길을 안 지난다. 팝업 소리를 바꿀 때 같이
	# 딸려가면 안 되는 쪽이라, 제 파일을 따로 들고 있는지 본다.
	var screen: Control = main.get("mode_select_panel")
	var start_file: String = screen.get_script().get_script_constant_map()["SFX_START_FILE"]
	print("")
	if start_file == gold + ".wav" or start_file == gold + ".ogg":
		_fail_msg("메인 화면 START 가 팝업의 금색 버튼과 같은 소리(%s)를 쓴다" % start_file)
	elif not ResourceLoader.exists(SOUND_DIR + start_file):
		_fail_msg("메인 화면 START 의 %s%s 가 없다" % [SOUND_DIR, start_file])
	else:
		print("  ok    메인 화면 START 는 제 소리 %s 를 따로 낸다" % start_file)

	if _fail == 0:
		print("check_button_sounds: ok")
		quit(0)
	else:
		print("check_button_sounds: %d failure(s)" % _fail)
		quit(1)
