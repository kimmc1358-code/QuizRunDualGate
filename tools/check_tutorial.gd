extends SceneTree

# 게임 화면 튜토리얼이 설치 후 한 번만 돌고, 그동안 판이 멈춰 있고, 설명 판이
# 정작 밝힌 것을 덮지 않는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_tutorial.gd
#
# 개발 중에는 거의 안 보이는 화면이다. 설치 직후 딱 한 번 도니 두 번째 판부터는
# 무슨 짓을 해도 안 뜨고, 그래서 "안 뜬다"가 정상인지 고장인지 구분이 안 된다.
# 게다가 튜토리얼이 카운트다운을 대신 걸어 주는 구조라, 끊기면 START 를 눌러도
# 아무 일이 일어나지 않는다.
#
# 보는 것:
#   1. 첫 진입에서 뜨고, 그동안 판은 시작되지 않으며 카운트다운도 안 흐른다.
#   2. 세 단계 모두 밝힐 자리가 있고, 그 자리가 게임이 실제로 그리는 자리다.
#   3. 설명 판이 어느 단계에서도 밝힌 자리를 덮지 않는다 — 3단계에서 판이 바
#      위에 앉았던 적이 있고, 그건 가리키는 것을 가린 것이다.
#   4. 끝까지 넘기면 판이 시작되고 다시는 안 돈다. 모드를 바꿔도, 앱을 껐다
#      켜도 마찬가지다.

const SAVE_PATH := "user://savegame.cfg"

var fails := 0
var _save_backup: String = ""
var _had_save := false


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


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


func _advance(overlay: Control) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	overlay.call("_gui_input", ev)


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	var overlay: Control = m.get("tutorial_overlay")
	if overlay == null:
		print("  FAIL: no tutorial_overlay")
		quit(1)
		return
	_backup_save()
	print("check_tutorial:")
	print("")

	# ---- 1. 첫 진입 ----
	m.set("tutorial_seen", false)
	m.call("_save_tutorial_seen")
	m.call("_set_state", 0)   # MODE_SELECT
	m.call("_reset_game")
	m.call("_on_mode_selected", 0)
	await process_frame
	print("  첫 진입 -> 튜토리얼 %s, 상태 %d, run_active %s" % [
		"보임" if overlay.visible else "안 보임", m.get("state"), m.get("run_active")])
	if not overlay.visible:
		_fail("게임 화면에 처음 들어왔는데 튜토리얼이 안 떴다")
	if m.get("run_active"):
		_fail("튜토리얼이 도는데 판이 이미 시작됐다")
	if not m.get("tutorial_active"):
		_fail("tutorial_active 가 안 섰다 — 카운트다운이 그냥 흘러간다")

	# 시계가 정말 멈춰 있는가. 카운트다운은 1초대라 5초를 흘려 보면 확실하다.
	var before_state: int = m.get("state")
	for i in range(300):
		m.call("_process", 1.0 / 60.0)
	print("  5초 흘림 -> 상태 %d (그대로여야 함), 튜토리얼 %s" % [
		m.get("state"), "보임" if overlay.visible else "사라짐"])
	if m.get("state") != before_state:
		_fail("설명을 읽는 동안 상태가 %d -> %d 로 넘어갔다 — 카운트다운이 흐르고 있다" % [
			before_state, m.get("state")])

	# ---- 2+3. 단계별 자리 ----
	#
	# 실제 해상도를 두 개 먹여서 본다. 헤드리스 뷰포트는 정사각형을 보고하므로
	# 그대로 두면 폰에서 존재하지 않는 배치를 검사하게 되고, 설명 판이
	# 하이라이트를 덮는지 같은 것은 화면이 짧을수록 잘 깨진다.
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	print("")
	for h in [base.y, base.x * 20.0 / 9.0]:
		var view := Vector2(base.x, h)
		overlay.size = view
		var steps: Array = m.call("_tutorial_steps", view)
		overlay.call("begin", steps)
		await process_frame
		print("  %.0fx%.0f — 단계 %d개" % [view.x, view.y, steps.size()])
		if steps.size() < 3:
			_fail("단계가 %d개다 — 캐릭터/퀴즈/가속 셋은 있어야 한다" % steps.size())
		for i in range(steps.size()):
			overlay.set("_index", i)
			var step: Dictionary = steps[i]
			var holes: Array = step.get("holes", [])
			var card: Rect2 = overlay.call("_card_rect", step)
			var problems: Array = []
			if holes.is_empty():
				problems.append("밝히는 자리가 없다")
			for hole in holes:
				var r: Rect2 = hole.get("rect", Rect2())
				if r.size.x <= 1.0 or r.size.y <= 1.0:
					problems.append("빈 사각형을 밝히려 한다")
					continue
				if r.position.x < -1.0 or r.position.y < -1.0 \
						or r.end.x > view.x + 1.0 or r.end.y > view.y + 1.0:
					problems.append("밝힐 자리가 화면 밖이다 (%.0f,%.0f %.0fx%.0f)" % [
						r.position.x, r.position.y, r.size.x, r.size.y])
				# 설명이 그 자리를 덮으면 안 된다.
				if card.intersects(r):
					problems.append("설명 판이 밝힌 자리를 덮는다")
			if card.size.y <= 0.0:
				problems.append("설명이 비어 있다")
			elif card.position.y < -1.0 or card.end.y > view.y + 1.0:
				problems.append("설명 판이 화면 밖으로 나간다 (%.0f..%.0f / %.0f)" % [
					card.position.y, card.end.y, view.y])
			if not problems.is_empty():
				_fail("%.0fx%.0f %d단계: %s" % [view.x, view.y, i + 1, ", ".join(problems)])
			print("    %d단계  구멍 %d개  판 %.0f..%.0f  %s" % [
				i + 1, holes.size(), card.position.y, card.end.y,
				"ok" if problems.is_empty() else "FAIL"])

		# 자리가 게임이 실제로 그리는 데서 왔는가. 여기에 좌표를 박아 두면 HUD 를
		# 옮겼을 때 하이라이트만 옛 자리에 남는다.
		if steps.size() >= 3:
			var quiz: Rect2 = m.call("_quiz_box_rect", view)
			var bar: Rect2 = m.call("_boost_bar_rect", view)
			var quiz_hole: Rect2 = steps[1]["holes"][0]["rect"]
			if not quiz_hole.is_equal_approx(quiz):
				_fail("2단계가 밝히는 자리가 퀴즈 상자와 다르다 (%s vs %s)" % [quiz_hole, quiz])
			var bar_hole: Rect2 = steps[2]["holes"][0]["rect"]
			if not bar_hole.is_equal_approx(bar):
				_fail("3단계가 밝히는 자리가 가속 바와 다르다 (%s vs %s)" % [bar_hole, bar])
			if steps[2]["holes"].size() < 2:
				_fail("3단계가 한 곳만 밝힌다 — 버튼과 바를 같이 밝혀야 관계가 읽힌다")
	var steps_final: Array = overlay.get("_steps")
	# 가속 버튼은 평소 PLAYING 에서만 보인다. 튜토리얼이 밝히는데 안 보이면
	# 어두운 구멍만 남는다.
	if not m.get("boost_button").visible:
		_fail("튜토리얼이 도는데 가속 버튼이 안 보인다 — 밝힌 자리가 비어 있다")

	# ---- 4. 끝까지 넘기면 ----
	overlay.set("_index", 0)
	for i in range(steps_final.size()):
		_advance(overlay)
	await process_frame
	print("")
	print("  끝까지 넘김 -> 튜토리얼 %s, run_active %s, 저장 %s" % [
		"보임" if overlay.visible else "닫힘", m.get("run_active"), m.get("tutorial_seen")])
	if overlay.visible:
		_fail("마지막 단계를 넘겼는데 튜토리얼이 안 닫혔다")
	if m.get("tutorial_active"):
		_fail("튜토리얼이 끝났는데 tutorial_active 가 서 있다 — 카운트다운이 영영 안 흐른다")
	if not m.get("run_active"):
		_fail("튜토리얼이 끝났는데 판이 시작되지 않았다 — START 를 눌러도 아무 일이 없는 상태다")
	if not m.get("tutorial_seen"):
		_fail("튜토리얼이 끝났는데 봤다는 표시가 안 섰다")

	# 다른 모드로 다시 들어가도 안 돈다.
	m.call("_reset_game")
	m.call("_set_state", 0)
	m.call("_on_mode_selected", 2)
	await process_frame
	print("  다른 모드로 재진입 -> 튜토리얼 %s, run_active %s" % [
		"보임" if overlay.visible else "안 보임", m.get("run_active")])
	if overlay.visible:
		_fail("모드를 바꾸니 튜토리얼이 다시 돌았다 — 설치 후 1회여야 한다")
	if not m.get("run_active"):
		_fail("두 번째 진입에서 판이 시작되지 않았다")

	# 껐다 켜도 안 돈다.
	m.call("_reset_game")
	var fresh: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh)
	await process_frame
	while fresh.get("boot_pending"):
		await process_frame
	print("  재실행 -> tutorial_seen %s" % fresh.get("tutorial_seen"))
	if not fresh.get("tutorial_seen"):
		_fail("앱을 다시 띄우니 튜토리얼을 안 본 것으로 돌아갔다")
	fresh.queue_free()

	_restore_save()
	print("")
	if fails == 0:
		print("check_tutorial: OK")
	else:
		print("check_tutorial: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
