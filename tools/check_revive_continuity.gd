extends SceneTree

# 광고를 보고 이어 뛴 판이 정말 "이어진" 판인지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_revive_continuity.gd
#
# 이어가기는 값 여러 개가 각자 살아남거나 죽는 자리다. 점수는 이어지는데
# 난이도만 처음으로 돌아가거나, 반대로 순위표 기록까지 딸려 올라가거나 —
# 어느 쪽이든 화면에는 "게임이 계속된다"로 똑같이 보인다. 한 판을 40 게이트쯤
# 끌고 가서 죽어 봐야 재현되는 것이라 플레이로 확인하기도 어렵다.
#
# 보는 것:
#   1. 이어 뛰면 점수·통과 게이트 수·phase·최고 콤보가 그대로다. phase 는
#      gates_passed 로만 정해지므로, 그 값이 살아남는 것이 곧 난이도가
#      이어진다는 뜻이다.
#   2. 그리고 이어서 더 가면 phase 가 계속 그 자리에서 오른다 — 0 부터 다시
#      세기 시작하지 않는다.
#   3. 콤보는 끊긴다. 이건 버그가 아니라 규칙이다(틀렸으니까). 값이 바뀌면
#      알아야 하는 쪽이라 명시해 둔다.
#   4. 순위표 기록은 첫 죽음 시점에 얼어붙는다. 광고로 순위를 살 수 없다는
#      규칙이고, 개인 최고 기록은 반대로 끝까지 간 점수를 받는다.

const RUN_GATES := 35   # phase_gate_counts 기본값 [10,20,30] 에서 phase 2 에 드는 수

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# 게이트 하나를 실제 판정 함수로 통과시킨다. correct=false 면 틀린 차선에
# 놓아 진짜 죽음을 만든다.
func _gate(m: Node2D, correct: bool) -> void:
	var view: Vector2 = m.call("get_viewport_rect").size
	m.call("_spawn_gate", view)
	var gs: Array = m.get("gates")
	if gs.is_empty():
		_fail("_spawn_gate 가 게이트를 안 만들었다")
		return
	var g: Dictionary = gs[gs.size() - 1]
	var use_top: bool = g.top_correct if correct else not g.top_correct
	var zt: float = g.top_zone_top if use_top else g.bottom_zone_top
	var zb: float = g.top_zone_bottom if use_top else g.bottom_zone_bottom
	m.set("player_y", (zt + zb) * 0.5)
	m.call("_resolve_gate", g, view)


func _snap(m: Node2D) -> Dictionary:
	return {
		"score": m.get("score"),
		"gates": m.get("gates_passed"),
		"phase": m.call("_get_phase_index", m.get("gates_passed")),
		"combo": m.get("combo"),
		"max_combo": m.get("max_combo"),
		"leaderboard": m.get("leaderboard_score"),
	}


func _show(tag: String, s: Dictionary) -> void:
	print("  %-22s score %-7d gates %-4d phase %d  combo %-4d max %-4d 순위표 %d" % [
		tag, s["score"], s["gates"], s["phase"], s["combo"], s["max_combo"], s["leaderboard"]])


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame

	print("check_revive_continuity: phase_gate_counts = %s" % str(m.get("phase_gate_counts")))
	print("")

	m.call("_apply_mode", 0)
	m.call("_reset_game")
	m.call("_start_countdown")
	for i in range(RUN_GATES):
		_gate(m, true)
	var before: Dictionary = _snap(m)
	_show("죽기 직전", before)
	if before["phase"] <= 0:
		_fail("%d 게이트를 지났는데 아직 phase %d 다 — 이 검사가 phase 유지 여부를 못 본다" % [
			RUN_GATES, before["phase"]])

	_gate(m, false)   # 틀린 차선 -> 진짜 죽음 -> 부활 제안
	var dead: Dictionary = _snap(m)
	_show("죽은 직후", dead)
	if m.get("state") != 4:
		_fail("죽었는데 상태가 GAMEOVER(4) 가 아니라 %d 다 — 부활 제안이 안 떴다" % m.get("state"))

	m.call("_on_revive_continue")
	# 카운트다운을 실제로 끝까지 돌린다. 여기서 초기화가 일어나면 버튼 직후만
	# 재서는 못 본다.
	for i in range(400):
		m.call("_process", 1.0 / 60.0)
		if m.get("state") == 3:
			break
	var after: Dictionary = _snap(m)
	_show("이어 뛰기 시작", after)
	if m.get("state") != 3:
		_fail("이어가기 뒤 카운트다운이 안 끝났다 (상태 %d)" % m.get("state"))
	if not m.get("run_revived"):
		_fail("run_revived 가 안 섰다 — 전면광고 카운터가 이 판을 세어 버린다")

	# ---- 1. 이어지는 값들 ----
	for key in ["score", "gates", "phase", "max_combo"]:
		if after[key] != before[key]:
			_fail("이어 뛰는데 %s 가 %s -> %s 로 바뀌었다" % [key, before[key], after[key]])
	if after["phase"] == before["phase"] and after["gates"] == before["gates"]:
		print("  -> phase %d, 통과 %d 게이트 그대로 (난이도가 이어진다)" % [
			after["phase"], after["gates"]])

	# ---- 2. 그 자리에서 계속 오르는가 ----
	var need: int = 0
	for n in m.get("phase_gate_counts"):
		need += int(n)
	var to_next: int = maxi(1, need - after["gates"] + 1)
	for i in range(to_next):
		_gate(m, true)
	var later: Dictionary = _snap(m)
	_show("이어서 %d 게이트 더" % to_next, later)
	if later["gates"] != after["gates"] + to_next:
		_fail("이어 뛴 뒤 게이트가 %d -> %d 로 세어졌다 (기대 %d)" % [
			after["gates"], later["gates"], after["gates"] + to_next])
	if later["phase"] < after["phase"]:
		_fail("이어 뛰면서 phase 가 %d -> %d 로 내려갔다 — 곡선이 처음으로 돌아갔다" % [
			after["phase"], later["phase"]])

	# ---- 3. 콤보는 끊긴다 (규칙) ----
	if after["combo"] != 0:
		_fail("이어 뛰기 시작에 콤보가 %d 다 — 틀린 판인데 연속 기록이 남았다" % after["combo"])
	else:
		print("  -> 콤보는 0 으로 끊김 (틀렸으니 규칙대로), 최고 콤보 %d 는 보존" % after["max_combo"])

	# ---- 4. 순위표는 첫 죽음에서 얼어붙는가 ----
	var frozen: int = later["leaderboard"]
	if frozen != dead["score"]:
		_fail("순위표 점수가 %d 인데 첫 죽음 시점 점수는 %d 였다 — 광고 뒤에 번 점수가 순위표에 들어갔다" % [
			frozen, dead["score"]])
	if later["score"] <= frozen:
		_fail("이어 뛰고도 점수가 %d 로 순위표 값 %d 를 안 넘었다 — 이 검사가 둘을 구분하지 못한다" % [
			later["score"], frozen])
	else:
		print("  -> 순위표 %d (첫 죽음 시점), 개인 기록용 점수 %d (끝까지)" % [frozen, later["score"]])

	# 그리고 판이 끝났을 때 두 기록이 각자 제 값을 받는가.
	#
	# 두 번째 죽음을 실제로 겪게 한다. _finish_run 을 직접 부르면 _game_over 를
	# 건너뛰는데, 순위표 점수를 얼리는 조건이 바로 거기 있어서 규칙을 지웠는데도
	# 이 검사가 통과했다. 이어 뛴 판은 반드시 한 번 더 죽는다.
	var was_best: int = m.get("best_scores")[m.get("current_mode")]
	var was_lb: int = m.get("leaderboard_bests")[m.get("current_mode")]
	m.get("best_scores")[m.get("current_mode")] = 0
	m.get("leaderboard_bests")[m.get("current_mode")] = 0
	var final_score: int = later["score"]
	_gate(m, false)
	if m.get("state") != 4:
		_fail("두 번째 죽음 뒤 상태가 %d 다 — 게임오버로 안 갔다" % m.get("state"))
	if m.get("leaderboard_score") != frozen:
		_fail("두 번째로 죽자 순위표 점수가 %d -> %d 로 갱신됐다 — 광고 뒤에 번 점수가 순위에 올라간다" % [
			frozen, m.get("leaderboard_score")])
	var got_best: int = m.get("best_scores")[m.get("current_mode")]
	var got_lb: int = m.get("leaderboard_bests")[m.get("current_mode")]
	print("  판 종료 -> 개인 최고 %d, 순위표 최고 %d" % [got_best, got_lb])
	if got_best != final_score:
		_fail("개인 최고 기록이 %d 다 — 끝까지 간 점수 %d 여야 한다" % [got_best, final_score])
	if got_lb != frozen:
		_fail("순위표 기록이 %d 다 — 첫 죽음 시점 %d 여야 한다" % [got_lb, frozen])
	# 남의 저장을 건드리지 않는다.
	m.get("best_scores")[m.get("current_mode")] = was_best
	m.get("leaderboard_bests")[m.get("current_mode")] = was_lb
	m.call("_save_best_score", m.get("current_mode"))

	print("")
	if fails == 0:
		print("check_revive_continuity: OK")
	else:
		print("check_revive_continuity: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
