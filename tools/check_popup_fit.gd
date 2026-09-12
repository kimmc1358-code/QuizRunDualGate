extends SceneTree

# 팝업 안의 내용이 판 밖으로 넘치지 않는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_popup_fit.gd
#
# 이 팝업들은 세로를 "쓸 것을 다 더하고 남은 것을 간격이 나눠 가진다"로 잡는다
# (used / gap). 줄을 하나 더 붙이면서 used 에 더하는 것을 잊거나 간격 개수를
# 안 고치면, 모자란 만큼이 아래로 밀려 나간다 — 오류는 없고 판 밖 배경 위에
# 글자가 얹힐 뿐이다. 설정 팝업에 언어 줄을 붙였을 때 맨 아래 버전 표시가
# 실제로 그렇게 나갔고, 부활 팝업에 점수 줄을 붙일 때 같은 자리에서 다시
# 물었다.
#
# 판 높이는 화면 비율 대비라 짧은 화면이 가장 빡빡하다. 그래서 16:9 와 20:9
# 를 모두 본다. 넘치는 것은 늘 맨 아래 것이므로 아래 모서리만 본다 — 제목
# 아트는 판 위로 걸터앉는 것이 설계라 위쪽은 보지 않는다.
#
# 보는 것은 판의 경계 하나뿐이다. "줄들이 서로 겹치는가"도 재 봤지만 이
# 팝업들에서는 뜻이 없었다 — 여기 자식 노드는 상자가 아니라 그리는 판이고,
# 넓은 투명 판 위에 좁은 것을 겹쳐 놓는 것이 이 코드의 정상 상태라 겹침이
# 스무 건씩 잡힌다. 그래서 여유가 넉넉한 팝업에서 줄 하나를 used 에서
# 빠뜨리는 것 같은 실수는 여기 안 걸린다. 여유를 다 먹고 판을 넘어설 때
# 걸린다.

const TOLERANCE := 1.0   # 반올림 한 픽셀까지는 봐준다

var _fail := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail_msg(msg: String) -> void:
	_fail += 1
	print("  FAIL  %s" % msg)


# 그릇에 해당하는 것들 — 판 자체와 글로우는 판보다 크거나 같다.
func _is_chrome(rect: Rect2, panel: Rect2) -> bool:
	return rect.size.x >= panel.size.x - TOLERANCE and rect.size.y >= panel.size.y - TOLERANCE


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	# 내용이 들어 있어야 크기가 진짜다. 빈 팝업은 무엇이든 들어간다.
	var pause: Control = main.get("pause_panel")
	var revive: Control = main.get("revive_panel")
	var over: Control = main.get("gameover_popup")
	var settings: Control = main.get("settings_popup")
	var about: Control = main.get("about_popup")
	for popup in [pause, revive, over, settings, about]:
		popup.call("ensure_built")
	pause.call("set_volumes", 0.5, 0.5)
	pause.call("set_boost_side", true)
	revive.call("set_score", 12600)
	revive.call("set_character", null, 100.0)
	settings.call("set_volumes", 0.5, 0.5)
	settings.call("set_account", null, "PlayerName", true)

	# 게임오버는 얼굴이 셋이다. 위쪽이 리본이냐 BEST 판이냐로 높이가 달라지고,
	# 아깝게 놓친 판에는 한 줄이 더 붙는다.
	var over_cases := [
		["새 기록", 14000, 12000, true, true, 14000],
		["기록 못 넘김", 12600, 14000, false, true, 12600],
		["아깝게 놓침 + 부활", 13500, 14000, false, true, 9800],
		["비로그인", 12600, 14000, false, false, 12600],
	]
	var revive_cases := [["로그인", true], ["비로그인", false]]

	for ratio in [[16, 9, 854.0], [20, 9, 1067.0]]:
		var view := Vector2(480.0, float(ratio[2]))
		print("")
		print("check_popup_fit: %dx%d 화면 480x%.0f" % [ratio[0], ratio[1], view.y])
		for entry in [["pause", pause], ["settings", settings], ["about", about]]:
			await _measure(str(entry[0]), entry[1], view)
		for case in revive_cases:
			revive.call("set_leaderboard_score", 9800, bool(case[1]))
			await _measure("revive (%s)" % case[0], revive, view)
		for case in over_cases:
			over.call("set_result", null, 0.0, int(case[1]), 24, int(case[2]),
				bool(case[3]), bool(case[4]), int(case[5]))
			await _measure("gameover (%s)" % case[0], over, view)

	if _fail == 0:
		print("")
		print("check_popup_fit: ok")
		quit(0)
	else:
		print("check_popup_fit: %d failure(s)" % _fail)
		quit(1)


func _measure(label: String, popup: Control, view: Vector2) -> void:
	popup.size = view
	popup.call("_layout")
	await process_frame
	var panel: Rect2 = popup.get("_panel_rect")
	var lowest := 0.0
	var lowest_name := ""
	for child in popup.get_children():
		if not (child is Control):
			continue
		var c: Control = child
		var rect := Rect2(c.position, c.size)
		if _is_chrome(rect, panel):
			continue
		if rect.size.y <= 0.0:
			continue
		if rect.end.y > lowest:
			lowest = rect.end.y
			lowest_name = c.name
	var slack: float = panel.end.y - lowest
	if slack < -TOLERANCE:
		_fail_msg("%s: %s 가 판 아래로 %.1fpx 넘친다 (판 바닥 %.1f, 내용 바닥 %.1f)" % [
			label, lowest_name, -slack, panel.end.y, lowest])
	else:
		print("  ok    %-26s 맨 아래 %-18s 판 바닥까지 %.1fpx 남음" % [label, lowest_name, slack])
