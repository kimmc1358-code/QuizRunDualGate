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

# 문제 수. 보스(SpaceRun.QUIZ_PER_CYCLE = 10) 전에 죽어야 퀴즈 진행도(quiz_index)가
# 이어지는지를 볼 수 있다.
const RUN_GATES := 7

# 이 검사는 진짜 판을 굴리므로 진짜 저장 파일에 쓴다. 최고 기록도, 히든 모드
# 해금 진행도도, 광고 카운터도 전부 여기 있다.
#
# 값 몇 개를 골라 되돌리는 것으로는 부족하다 — 그렇게 했다가 이 PC 의 SKY
# 최고 기록이 검사용 12600 으로 덮여 있는 것을 나중에 발견했다. 파일을 통째로
# 백업했다 되돌린다.
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
		# 원래 없던 파일이면 지운다. 검사가 새 설치를 "이미 플레이한 기기"로
		# 바꿔 놓아서는 안 된다.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not restore %s — this machine's save is left as the check left it" % SAVE_PATH)
		return
	f.store_string(_save_backup)
	f.close()


# 판을 실제로 끝낸다. 우주 판에서 하트는 소행성과 보스 탄에만 깎이므로, 그 길
# (_space_hurt)로 하트를 다 잃는다. 마지막 하나 전까지는 판이 계속되어야 한다.
func _lose_all_hearts(m: Node2D) -> void:
	var n: int = m.get("hearts")
	for i in range(n):
		m.set("hurt_elapsed", -1.0)
		m.call("_space_hurt")
		if i < n - 1 and m.get("state") == 3:
			_fail("하트가 %d 개 남았는데 판이 끝났다" % (n - i - 1))
			return


# 문제 하나를 실제 판정으로 푼다: 정답이면 맞는 행성에, 아니면 어느 행성에도
# 안 닿는 자리에 세워 두고 행성이 비행면에 닿을 때까지 판을 돌린다. 정답 뒤의
# 룰렛 구간은 바로 끝낸다.
func _gate(m: Node2D, correct: bool) -> void:
	var sp = m.get("space")
	var w: Dictionary = sp.upcoming_wave()
	if w.is_empty():
		sp.spawn_wave()
		w = sp.upcoming_wave()
	var pos := Vector2(2.2, -2.9)
	if correct:
		for p in w.planets:
			if p.correct:
				pos = p.pos
	sp.ship_pos = pos
	sp.ship_target = pos
	var guard := 0
	while not w.resolved and guard < 2000 and m.get("state") == 2:
		sp.tick(1.0 / 60.0, true, true)
		guard += 1
	if sp.phase == sp.Phase.LOOT:
		for r in sp.rocks:
			r.node.queue_free()
		sp.rocks.clear()
		sp.phase_time = sp.LOOT_DURATION
		sp.tick(1.0 / 60.0, true, true)


func _snap(m: Node2D) -> Dictionary:
	return {
		"score": m.get("score"),
		"gates": m.get("gates_passed"),
		"phase": m.get("space").quiz_index,
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

	_backup_save()
	print("check_revive_continuity")
	print("")

	m.call("_apply_mode", 0)
	m.call("_reset_game")
	m.call("_start_countdown")
	# 카운트다운은 건너뛴다 — 판정은 PLAYING 에서만 돈다. 튜토리얼도 끈다.
	m.set("tutorial_active", false)
	m.set("state", 2)
	for i in range(RUN_GATES):
		_gate(m, true)
	var before: Dictionary = _snap(m)
	_show("죽기 직전", before)
	if before["phase"] <= 0:
		_fail("%d 문제를 풀었는데 진행도가 %d 다 — 이 검사가 이어짐을 못 본다" % [RUN_GATES, before["phase"]])

	_lose_all_hearts(m)   # 틀린 차선을 하트 수만큼 -> 진짜 죽음 -> 부활 제안
	var dead: Dictionary = _snap(m)
	_show("죽은 직후", dead)
	if m.get("state") != 3:
		_fail("죽었는데 상태가 GAMEOVER(3) 가 아니라 %d 다 — 부활 제안이 안 떴다" % m.get("state"))

	m.call("_on_revive_continue")
	# 카운트다운을 실제로 끝까지 돌린다. 여기서 초기화가 일어나면 버튼 직후만
	# 재서는 못 본다.
	for i in range(400):
		m.call("_process", 1.0 / 60.0)
		if m.get("state") == 2:
			break
	var after: Dictionary = _snap(m)
	_show("이어 뛰기 시작", after)
	if m.get("state") != 2:
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
	var to_next: int = 1
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
	_lose_all_hearts(m)
	if m.get("state") != 3:
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
	m.get("best_scores")[m.get("current_mode")] = was_best
	m.get("leaderboard_bests")[m.get("current_mode")] = was_lb
	# 이 판이 만진 것은 최고 기록만이 아니다 — 해금 진행도와 광고 카운터도
	# 같은 파일에 있고 판을 굴리는 동안 계속 쓰였다. 파일째로 되돌린다.
	_restore_save()

	print("")
	if fails == 0:
		print("check_revive_continuity: OK")
	else:
		print("check_revive_continuity: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
