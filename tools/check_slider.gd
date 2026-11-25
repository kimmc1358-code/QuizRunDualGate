extends SceneTree

# 2.0 의 세로 슬라이더 조작이 규칙대로 도는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_slider.gd
#
# 게임의 실제 함수(_slider_input, _update_player_follow, _spawn_gate)만 부른다.
#
#   1. 화면은 가로다 — 기준 뷰포트가 세로보다 가로가 길고, keep_height 로 늘어난다.
#      그리고 게임과 모드 선택 화면이 정글(연산) 모드로 시작한다.
#   2. 슬라이더 범위 = 게이트 판에서 캐릭터 히트박스가 들어가는 구간.
#   3. 왼쪽 끝 칸을 누르면 손잡이를 잡고, 그 손가락의 드래그만 따라간다.
#      칸 밖을 누른 손가락, 다른 손가락은 무시한다. 터치를 흉내 낸 마우스
#      이벤트도 무시한다 — 안 그러면 한 번의 터치가 두 번 처리된다.
#   4. 범위 밖을 가리키면 끝에서 멈춘다.
#   5. 캐릭터는 손잡이를 쫓되 한 프레임에 PLAYER_MOVE_SPEED*delta 를 넘지 않고,
#      시간이 지나면 도착한다.
#   6. 연속한 두 게이트의 정답 구멍은 부스트를 쥔 채로도 그 속도로 닿을 수 있는
#      거리 안에 놓인다.
#
# 게이트를 만들기만 하고 판정하지 않으므로 저장 파일은 건드리지 않는다.

var _fail := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	print("check_slider")

	# ---- 1. 가로 ----
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	_check(w > h, "the reference viewport is landscape (%dx%d)" % [w, h])
	_check(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep_height",
		"a longer phone gets more width, not more height (keep_height)")
	var view := Vector2(w, h)
	# 2.0 은 정글(연산) 모드로 시작한다 — 게임 쪽 기본값과 모드 선택 화면의
	# 처음 고른 카드가 같아야 한다.
	var ms = m.mode_select_panel
	_check(m.current_mode == m.Mode.JUNGLE
		and ms.CARD_MODES[ms.selected_index] == ms.MODE_JUNGLE,
		"the game and the mode-select screen both open on JUNGLE")

	m.call("_reset_game")
	m.call("_apply_mode", 0)
	m.state = m.State.PLAYING
	var r: Vector2 = m.call("slider_range", view)
	var half: float = m.PLAYER_SIZE.y * 0.5
	# ---- 2. 범위 ----
	_check(absf(r.x - (m.call("_gate_field_top", view) + half)) < 0.5
		and absf(r.y - (m.call("_gate_field_bottom", view) - half)) < 0.5,
		"the slider spans the gate field minus half the hitbox (%.0f..%.0f)" % [r.x, r.y])

	# ---- 3. 잡기 ----
	var col: float = m.SLIDER_TOUCH_WIDTH * 0.5
	var y1: float = lerpf(r.x, r.y, 0.25)
	m.call("_slider_input", _touch(3, Vector2(col, y1), true))
	_check(absf(m.slider_target_y - y1) < 0.5, "pressing the left column grabs the slider")
	var y2: float = lerpf(r.x, r.y, 0.75)
	m.call("_slider_input", _drag(3, Vector2(col + 200.0, y2)))
	_check(absf(m.slider_target_y - y2) < 0.5, "dragging that finger moves it, even off the column")
	m.call("_slider_input", _drag(5, Vector2(col, y1)))
	_check(absf(m.slider_target_y - y2) < 0.5, "another finger's drag is ignored")
	var emu := InputEventMouseMotion.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.position = Vector2(col, y1)
	emu.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.call("_slider_input", emu)
	_check(absf(m.slider_target_y - y2) < 0.5, "mouse events emulated from touch are ignored")
	m.call("_slider_input", _touch(3, Vector2(col, y2), false))
	m.call("_slider_input", _touch(4, Vector2(w * 0.5, y1), true))
	_check(absf(m.slider_target_y - y2) < 0.5, "a press outside the left column does not grab it")

	# ---- 4. 끝에서 멈춘다 ----
	m.call("_slider_input", _touch(6, Vector2(col, -500.0), true))
	_check(absf(m.slider_target_y - r.x) < 0.5, "pointing above the field stops at the top")
	m.call("_slider_input", _touch(6, Vector2(col, 5000.0), false))

	# ---- 5. 쫓기 ----
	m.player_y = r.x
	m.slider_target_y = r.y
	var dt := 1.0 / 60.0
	var worst := 0.0
	var t := 0.0
	while absf(m.player_y - r.y) > 0.5 and t < 5.0:
		var before: float = m.player_y
		m.call("_update_player_follow", dt)
		worst = maxf(worst, absf(m.player_y - before))
		t += dt
	_check(worst <= m.PLAYER_MOVE_SPEED * dt + 0.01,
		"the character never moves more than PLAYER_MOVE_SPEED per frame (%.1f px)" % worst)
	_check(t < 5.0, "and it arrives (%.2f s across the whole field)" % t)

	# ---- 6. 닿을 수 있는 배치 ----
	var reach: float = m.base_gate_spacing / (m.GATE_SPEED * m.BOOST_BUTTON_MULTIPLIER) * m.PLAYER_MOVE_SPEED
	var worst_jump := 0.0
	m.gates.clear()
	for i in range(400):
		var last: float = m.last_zone_center
		m.call("_spawn_gate", view)
		var g: Dictionary = m.gates[m.gates.size() - 1]
		var c: float = ((g.top_zone_top + g.top_zone_bottom) if g.top_correct
			else (g.bottom_zone_top + g.bottom_zone_bottom)) * 0.5
		worst_jump = maxf(worst_jump, absf(c - last))
		m.gates.clear()
	_check(worst_jump <= reach, "consecutive correct holes stay within boosted reach (%.0f of %.0f px)" % [worst_jump, reach])

	m.call("_reset_game")
	print("check_slider: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
