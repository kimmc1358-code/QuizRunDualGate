extends SceneTree

# 히든 모드(MIX)가 조건대로 열리는지, 그리고 열리기 전에는 안 열리는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_hidden_unlock.gd
#
# 눈으로 확인하려면 세 모드에서 각각 열 게이트씩, 앱을 껐다 켜 가며 서른 번을
# 지나야 한다. 그러고도 "안 열렸다"가 조건 미달인지 저장 실패인지 구분할 수
# 없다 — 화면에 나오는 것은 잠긴 카드 하나뿐이라 원인이 안 적혀 있다.
#
# 게이트 통과는 실제 판정 함수(_resolve_gate)를 부른다. 카운터를 여기서 직접
# 올리면 "규칙"이 아니라 이 스크립트를 검사하게 된다.
#
# 보는 것:
#   1. 새 설치는 잠겨 있고, 문턱 직전까지 가도 안 열린다.
#   2. 못 지나간 게이트는 안 세어진다.
#   3. 히든 모드에서 지난 게이트는 자기 해금 조건에 안 들어간다.
#   4. 세 모드를 다 채우면 열리고, 모드 선택 화면도 같이 열린 것으로 바뀐다.
#   5. 앱을 껐다 켜도 남는다. 그리고 게임오버가 아니라 일시정지 HOME 으로
#      빠져나간 판의 게이트도 남는다 — 경로에 따라 사라지면 조건을 채우고도
#      안 열린다.

# 진짜 판을 굴리므로 진짜 저장 파일에 쓴다 — 해금 진행도만이 아니라 최고
# 기록과 광고 카운터까지. 값 몇 개만 되돌리면 나머지가 남는다(같은 실수로 이
# PC 의 SKY 기록이 검사값으로 덮였다), 그래서 파일째로 백업했다 되돌린다.
# tools/check_revive_continuity.gd 도 같은 방식이다.
const SAVE_PATH := "user://savegame.cfg"

var fails := 0
var saved_gates := PackedInt32Array()
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
		push_warning("could not restore %s — this machine's save is left as the check left it" % SAVE_PATH)
		return
	f.store_string(_save_backup)
	f.close()


# 게이트 하나를 실제로 통과시킨다. 정답 차선의 판정 구역 한가운데에 캐릭터를
# 놓고 진짜 판정 함수를 부른다. correct=false 면 반대 차선에 놓는다.
func _pass_gate(m: Node2D, correct: bool = true) -> void:
	var view: Vector2 = m.call("get_viewport_rect").size
	m.call("_spawn_gate", view)
	var gates: Array = m.get("gates")
	if gates.is_empty():
		_fail("_spawn_gate 가 게이트를 안 만들었다")
		return
	var g: Dictionary = gates[gates.size() - 1]
	var top_correct: bool = g.top_correct
	var use_top: bool = top_correct if correct else not top_correct
	var zt: float = g.top_zone_top if use_top else g.bottom_zone_top
	var zb: float = g.top_zone_bottom if use_top else g.bottom_zone_bottom
	m.set("player_y", (zt + zb) * 0.5)
	m.call("_resolve_gate", g, view)


func _play_gates(m: Node2D, mode: int, count: int, correct: bool = true) -> void:
	m.call("_apply_mode", mode)
	m.call("_start_countdown")
	for i in range(count):
		_pass_gate(m, correct)


func _fresh(m: Node2D) -> void:
	var zeros := PackedInt32Array()
	zeros.resize(saved_gates.size())
	zeros.fill(0)
	m.set("mode_gates_cleared", zeros)
	for mode in range(zeros.size()):
		m.call("_save_best_score", mode)


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame

	var need: int = m.get("HIDDEN_UNLOCK_GATES")
	var hidden: int = m.get("HIDDEN_MODE")
	var required: int = m.call("hidden_modes_required")
	var single: Array[int] = []
	for mode in range(m.get("mode_gates_cleared").size()):
		if mode != hidden:
			single.append(mode)
	_backup_save()
	print("check_hidden_unlock: 모드 %d개에서 각 %d게이트, 히든은 모드 %d" % [
		required, need, hidden])
	print("")

	# 사용자의 실제 진행도를 되돌려 놓기 위해 먼저 챙긴다 — 검사가 남의 저장을
	# 지우면 안 된다.
	saved_gates = m.get("mode_gates_cleared").duplicate()

	# ---- 1. 새 설치, 그리고 문턱 직전 ----
	_fresh(m)
	if m.call("hidden_mode_unlocked"):
		_fail("새 설치인데 이미 열려 있다")
	for mode in single:
		_play_gates(m, mode, need - 1)
	var cleared: int = m.call("hidden_modes_cleared")
	print("  세 모드에서 %d게이트씩 -> %d/%d, 열림=%s" % [
		need - 1, cleared, required, m.call("hidden_mode_unlocked")])
	if cleared != 0:
		_fail("문턱(%d) 직전인데 %d개 모드가 채워진 것으로 세어졌다" % [need, cleared])
	if m.call("hidden_mode_unlocked"):
		_fail("문턱 직전인데 열렸다")

	# ---- 2. 못 지나간 게이트는 안 센다 ----
	var before: int = m.get("mode_gates_cleared")[single[0]]
	_play_gates(m, single[0], 1, false)
	var after: int = m.get("mode_gates_cleared")[single[0]]
	print("  틀린 차선으로 1게이트 -> %d -> %d" % [before, after])
	if after != before:
		_fail("실패한 게이트가 해금 진행도에 들어갔다 (%d -> %d)" % [before, after])
	m.call("_reset_game")   # 위에서 _game_over 로 넘어갔다

	# ---- 3. 히든 모드 자신은 조건에 안 들어간다 ----
	_play_gates(m, hidden, need * 2)
	if m.call("hidden_mode_unlocked"):
		_fail("히든 모드에서만 %d게이트를 지났는데 열렸다 — 자기 자신이 조건에 들어가 있다" % (need * 2))
	else:
		print("  히든 모드에서 %d게이트 -> 여전히 %d/%d (자기 조건 아님)" % [
			need * 2, m.call("hidden_modes_cleared"), required])

	# ---- 4. 마지막 한 게이트씩 ----
	for i in range(single.size()):
		_play_gates(m, single[i], 1)
		var n: int = m.call("hidden_modes_cleared")
		var want: int = i + 1
		if n != want:
			_fail("%d번째 모드를 채웠는데 %d/%d 로 세어졌다 (기대 %d)" % [i + 1, n, required, want])
		var should_open: bool = want >= required
		if m.call("hidden_mode_unlocked") != should_open:
			_fail("%d/%d 에서 열림=%s (기대 %s)" % [
				n, required, m.call("hidden_mode_unlocked"), should_open])
		print("  모드 %d 완료 -> %d/%d, 열림=%s" % [
			single[i], n, required, m.call("hidden_mode_unlocked")])

	# 화면도 같이 열려야 한다. Main 이 알고 화면이 모르면 카드는 계속 잠겨 있다.
	m.call("_push_hidden_progress")
	await process_frame
	var screen = m.get("mode_select_panel")
	if screen != null and not screen.get("hidden_mode_open"):
		_fail("Main 은 열렸다고 하는데 모드 선택 화면은 잠긴 채다 — _push_hidden_progress 가 안 닿았다")
	elif screen != null:
		print("  모드 선택 화면도 열림 상태")

	# ---- 5-a. 앱을 껐다 켜도 남는가 ----
	_fresh(m)
	_play_gates(m, single[0], need)
	m.call("_reset_game")
	var fresh_inst: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh_inst)
	await process_frame
	while fresh_inst.get("boot_pending"):
		await process_frame
	var reloaded: int = fresh_inst.get("mode_gates_cleared")[single[0]]
	print("")
	print("  재실행 전후: 모드 %d 게이트 %d -> %d" % [single[0], need, reloaded])
	if reloaded != need:
		_fail("앱을 다시 띄우니 %d 였던 게이트가 %d 가 됐다" % [need, reloaded])
	fresh_inst.queue_free()

	# ---- 5-b. 일시정지 HOME 으로 나간 판도 남는가 ----
	_fresh(m)
	m.call("_apply_mode", single[1])
	m.call("_start_countdown")
	for i in range(need):
		_pass_gate(m)
	m.call("_on_pause_home_pressed")   # 게임오버를 거치지 않는 경로
	var fresh2: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh2)
	await process_frame
	while fresh2.get("boot_pending"):
		await process_frame
	var kept: int = fresh2.get("mode_gates_cleared")[single[1]]
	print("  일시정지 HOME 으로 나간 뒤 재실행: 모드 %d 게이트 %d" % [single[1], kept])
	if kept != need:
		_fail("일시정지 HOME 으로 나가니 그 판의 게이트 %d개가 사라졌다 (남은 값 %d)" % [need, kept])
	fresh2.queue_free()

	# 사용자의 저장을 통째로 되돌린다 — 이 검사가 굴린 판들이 해금 진행도 외에
	# 최고 기록과 광고 카운터까지 건드렸다.
	m.set("mode_gates_cleared", saved_gates)
	_restore_save()

	print("")
	if fails == 0:
		print("check_hidden_unlock: OK")
	else:
		print("check_hidden_unlock: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
