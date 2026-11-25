extends SceneTree

# 하트(2.0)가 규칙대로 깎이고, 판이 끝나야 할 때만 끝나는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_hearts.gd
#
# 게임의 실제 함수(_resolve_gate, _update_playing, _on_revive_continue)만 부른다.
#
#   1. 판은 MAX_HEARTS 로 시작한다.
#   2. 오답 게이트와 벽은 하트 하나씩만 가져가고 판은 계속된다. 콤보는 끊기고,
#      점수와 통과 수는 그대로다.
#   3. 맞은 뒤 다음 게이트는 캐릭터가 실제로 있는 자리에서 닿을 수 있게 놓인다
#      (last_zone_center 가 캐릭터 자리로 옮겨진다). 안 그러면 오답 레인에서
#      다음 게이트에 못 닿아 하트를 연달아 잃는다.
#   4. 바닥은 없다(2.0 슬라이더). 손잡이를 끝까지 내려도 캐릭터는 판 안에
#      머물고 하트를 잃지 않는다.
#   5. 마지막 하트를 잃는 순간이 예전의 죽음 — 부활 제안(GAMEOVER)으로 간다.
#   6. 부활하면 하트가 다시 찬다. 새 판도 마찬가지.
#   7. HUD 하트는 게이트 구역 안 왼쪽 위에 있고 화면 밖으로 안 나간다.
#
# 진짜 판을 굴리므로 저장 파일을 떠 두었다 되돌린다.

const SAVE_PATH := "user://savegame.cfg"

var _fail := 0
var _save := PackedByteArray()
var _had_save := false


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _view() -> Vector2:
	return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))


# 게이트 하나를 만들고 판정한다. how: "pass" / "wrong" / "wall"
func _gate(m: Node2D, how: String) -> Dictionary:
	var view := _view()
	m.call("_spawn_gate", view)
	var g: Dictionary = m.gates[m.gates.size() - 1]
	match how:
		"pass":
			m.player_y = ((g.top_zone_top + g.top_zone_bottom) if g.top_correct
				else (g.bottom_zone_top + g.bottom_zone_bottom)) * 0.5
		"wrong":
			m.player_y = ((g.bottom_zone_top + g.bottom_zone_bottom) if g.top_correct
				else (g.top_zone_top + g.top_zone_bottom)) * 0.5
		"wall":
			m.player_y = m.call("_gate_wall_center_y", view)
	m.call("_resolve_gate", g, view)
	return g


func _start(m: Node2D) -> void:
	m.call("_reset_game")
	m.call("_apply_mode", 0)
	m.call("_start_countdown")
	m.state = m.State.PLAYING


func _run() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save = FileAccess.get_file_as_bytes(SAVE_PATH)
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	var max_h: int = m.MAX_HEARTS
	print("check_hearts: MAX_HEARTS = %d" % max_h)

	# ---- 1. 시작 ----
	_start(m)
	_check(m.hearts == max_h, "a run starts with %d hearts" % max_h)

	# ---- 2. 오답 ----
	for i in range(4):
		_gate(m, "pass")
	var score: int = m.score
	var passed: int = m.gates_passed
	_gate(m, "wrong")
	_check(m.hearts == max_h - 1 and m.state == m.State.PLAYING,
		"a wrong gate costs one heart and the run goes on (%d left)" % m.hearts)
	_check(m.combo == 0 and m.score == score and m.gates_passed == passed,
		"the combo breaks; score and gates passed stay")
	_check(m.hurt_elapsed >= 0.0, "being hit starts the invulnerable blink")
	# ---- 3. 다음 게이트는 지금 자리에서 ----
	var view := _view()
	var expect: float = clampf(m.player_y, m.call("_gate_field_top", view), m.call("_gate_field_bottom", view))
	_check(absf(m.last_zone_center - expect) < 0.5,
		"after a miss the next gate is placed from where the character really is")

	# ---- 벽 ----
	m.hurt_elapsed = -1.0
	_gate(m, "wall")
	_check(m.hearts == max_h - 2 and m.state == m.State.PLAYING, "the wall costs one heart too")

	# ---- 4. 바닥이 없다 ----
	# 2.0 의 슬라이더 조작에는 중력도 바닥도 없다. 손잡이를 맨 아래까지 내려도
	# 캐릭터는 판 안에 머물고 하트를 잃지 않는다.
	_start(m)
	m.gates.clear()
	m.slider_target_y = 99999.0
	for i in range(120):
		m.call("_update_playing", 1.0 / 60.0)
		m.gates.clear()
	var r: Vector2 = m.call("slider_range", view)
	_check(m.hearts == max_h and absf(m.player_y - r.y) < 0.5,
		"pushed to the bottom the character stops at the field's edge and keeps its hearts")

	# ---- 5. 마지막 하트 ----
	_start(m)
	for i in range(max_h - 1):
		_gate(m, "wrong")
		m.hurt_elapsed = -1.0
	_check(m.state == m.State.PLAYING, "still playing with one heart left")
	_gate(m, "wrong")
	_check(m.hearts == 0 and m.state == m.State.GAMEOVER,
		"losing the last heart ends the run into the revive offer")

	# ---- 6. 부활과 새 판 ----
	m.call("_on_revive_continue")
	_check(m.hearts == max_h, "a revive refills the hearts")
	m.call("_reset_game")
	_check(m.hearts == max_h, "a new run refills the hearts")

	# ---- 7. HUD ----
	var zone_top: float = m.call("_gate_zone_top", view)
	var combo_pos: Vector2 = m.call("_combo_display_pos", view)
	var last: Rect2 = m.call("heart_hud_rect", max_h - 1, view)
	var first: Rect2 = m.call("heart_hud_rect", 0, view)
	_check(first.position.y >= zone_top and first.position.x >= 0.0 and last.end.x <= view.x * 0.5,
		"the hearts sit in the gate zone's top-left, inside the left half")
	_check(last.end.x < combo_pos.x, "the hearts stay clear of the combo readout")

	m.call("_reset_game")
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("check_hearts: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
