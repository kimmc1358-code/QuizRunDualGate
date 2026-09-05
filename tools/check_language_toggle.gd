extends SceneTree

# 설정 팝업의 ENG/KOR 토글이 실제로 언어를 바꾸는지 지킨다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_language_toggle.gd
#
# 파싱 검사로는 잡히지 않는 것이 셋이다.
#
# 하나, 토글에서 Main 까지 신호가 이어져 있는가. 팝업은 language_changed 를
# 쏘고 끝이라, connect 한 줄이 빠져도 팝업 안의 손잡이는 멀쩡히 움직인다.
#
# 둘, 화면이 다시 지어지는가. TranslationServer 의 로케일만 바꾸면 tr() 은
# 새 언어를 내놓지만 이미 만들어진 라벨의 text 는 옛 언어 그대로다 — 설정
# 팝업만 보고 있으면(그건 열 때마다 새로 배치된다) 멀쩡해 보인다.
#
# 셋, 고른 언어가 저장되어 다음에 켤 때 살아나는가.

const SAVE_PATH := "user://savegame.cfg"
const SAVE_SECTION := "locale"
const SAVE_KEY := "language"

var _fail := 0
var _had_save := false
var _save_backup := ""


func _init() -> void:
	# 진짜 게임을 돌리므로 진짜 저장 파일에 쓴다. 통째로 떠 두고 되돌린다.
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


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


func _saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return str(cfg.get_value(SAVE_SECTION, SAVE_KEY, ""))


# 손잡이를 실제로 누른다. set_language_korean 을 직접 부르면 신호가 이어져
# 있는지를 못 본다 — 그 한 줄이 이 검사의 절반이다.
func _tap(toggle: Control, second_half: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(toggle.size.x * (0.75 if second_half else 0.25), toggle.size.y * 0.5)
	toggle.gui_input.emit(e)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	main.call("_set_state", 0)   # State.MODE_SELECT
	await process_frame

	# 기기 로케일이 무엇이든 영어에서 출발한다.
	main.call("set_language_korean", false)
	for i in range(4):
		await process_frame

	var settings: Control = main.get("settings_popup")
	settings.call("ensure_built")
	var toggle: Control = settings.get("_language_toggle")
	_ok(toggle != null, "설정 팝업에 언어 토글이 있다")
	if toggle == null:
		_finish()
		return
	# 판이 배치되어 폭을 가진 뒤라야 어느 칸을 눌렀는지 갈린다.
	main.call("_open_settings")
	await process_frame
	settings.visible = false

	var screen: Control = main.get("mode_select_panel")
	var en_label: String = screen.get("_remove_ads").text
	var en_explain: String = screen.get("_explain_label").text

	_tap(toggle, true)
	for i in range(4):
		await process_frame

	_ok(TranslationServer.get_locale().begins_with("ko"),
		"KOR 을 누르면 로케일이 ko 가 된다 (지금 %s)" % TranslationServer.get_locale())
	_ok(_saved_locale() == "ko", "고른 언어가 저장된다 (지금 %s)" % _saved_locale())
	# 여기가 요점이다. 로케일만 바뀌고 화면을 다시 짓지 않으면 이 둘은 영어로
	# 남는다 — tr() 은 이미 지날 대로 지난 뒤다.
	var ko_label: String = screen.get("_remove_ads").text
	var ko_explain: String = screen.get("_explain_label").text
	_ok(ko_label != en_label, "메인 화면 '광고 제거' 글자가 다시 지어진다 (%s -> %s)" % [en_label, ko_label])
	_ok(ko_explain != en_explain, "모드 설명 패널이 다시 지어진다")
	_ok(ko_label == TranslationServer.translate("Remove Ads"),
		"그 글자가 ko 번역과 같다")
	# 다시 지어진 팝업의 토글은 새 노드다. 옛 노드를 계속 들고 있으면 다음
	# 탭이 아무 데도 닿지 않는다.
	var toggle2: Control = settings.get("_language_toggle")
	_ok(toggle2 != null and toggle2 != toggle, "팝업이 다시 지어지며 토글도 새로 만들어진다")
	_ok(toggle2 != null and bool(toggle2.get_meta("second", false)),
		"다시 지어진 토글이 KOR 쪽에 켜져 있다")

	# 되돌아올 수 있어야 한다. 못 읽는 언어로 잘못 바꿨을 때 길이 이것뿐이다.
	main.call("_open_settings")
	await process_frame
	settings.visible = false
	_tap(toggle2, false)
	for i in range(4):
		await process_frame
	_ok(TranslationServer.get_locale().begins_with("en"),
		"ENG 로 되돌릴 수 있다 (지금 %s)" % TranslationServer.get_locale())
	_ok(_saved_locale() == "en", "되돌린 것도 저장된다 (지금 %s)" % _saved_locale())
	_ok(screen.get("_remove_ads").text == en_label, "글자도 영어로 돌아온다")

	await _check_relaunch()
	_finish()


# 다시 켰을 때. 고른 언어는 저장돼 있지만, 그것을 읽어 오는 시점이 판을 짓는
# 것보다 뒤면 화면은 기기 언어로 지어진 뒤 로케일만 조용히 바뀐다 — 로케일을
# 물어보는 검사로는 통과하고 화면만 틀린다. 그래서 라벨을 본다.
func _check_relaunch() -> void:
	# 기기는 영어인데 저장된 것은 한국어인 상황을 만든다.
	TranslationServer.set_locale("en")
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SAVE_SECTION, SAVE_KEY, "ko")
	cfg.save(SAVE_PATH)

	var fresh: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh)
	await process_frame
	while fresh.get("boot_pending"):
		await process_frame
	fresh.call("_set_state", 0)
	await process_frame
	var label: String = fresh.get("mode_select_panel").get("_remove_ads").text
	_ok(TranslationServer.get_locale().begins_with("ko"), "다시 켜면 저장된 언어로 돌아온다")
	_ok(label == TranslationServer.translate("Remove Ads"),
		"그때 화면도 그 언어로 지어져 있다 (%s)" % label)
	fresh.queue_free()
	await process_frame


func _finish() -> void:
	_restore_save()
	if _fail == 0:
		print("check_language_toggle: ok")
		quit(0)
	else:
		print("check_language_toggle: %d failure(s)" % _fail)
		quit(1)
