extends SceneTree

# 전면광고가 정해진 빈도로 나오는지, 그리고 나오면 안 되는 자리에서 안 나오는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ad_policy.gd
#
# 눈으로는 확인이 거의 불가능한 종류다. 규칙 하나를 보려면 대여섯 판을 실제로
# 죽어 가며 해야 하고, "앱을 껐다 켜도 카운터가 남는가" 같은 것은 그 위에 재실행
# 까지 얹어야 한다. 그리고 틀렸을 때 화면에 나타나는 증상이 "광고가 좀 자주 나오는
# 것 같다" 정도라, 플레이로는 규칙 위반과 운을 구분할 수 없다.
#
# 여기서 보는 것:
#   1. 설치 후 면제 구간에는 절대 안 나온다.
#   2. 면제가 끝난 뒤에는 정확히 N판마다 나온다.
#   3. 리워드 광고를 본 판은 카운터에 안 들어간다 — 부활 광고 바로 뒤에
#      전면광고가 붙는 것을 막는 규칙이다.
#   4. 카운터가 저장된다. 앱을 껐다 켜는 것으로 광고를 피할 수 없어야 한다.
#   5. 판을 떠나는 네 경로가 전부 세어진다. 한 경로만 빠져도 그 경로로만
#      재시작하면 광고가 영영 안 나온다.

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# 판 하나를 처음부터 끝까지. revived=true 면 그 판에 리워드 광고를 봤다는 뜻.
# 게임의 실제 함수만 부른다 — 카운터를 여기서 직접 만지면 규칙이 아니라 이
# 스크립트를 검사하게 된다.
func _play_one(m: Node2D, revived: bool) -> bool:
	m.call("_start_countdown")
	if revived:
		m.set("run_revived", true)
	m.call("_reset_game")
	return m.call("_ad_try_interstitial")


func _fresh_install(m: Node2D) -> void:
	m.set("games_played_total", 0)
	m.set("restarts_since_interstitial", 0)
	m.set("run_revived", false)
	m.set("run_active", false)
	m.call("_save_ad_state")


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	m.call("_apply_mode", 0)

	var every: int = m.get("interstitial_every_restarts")
	var free_games: int = m.get("interstitial_free_games")
	print("check_ad_policy: %d판마다 1회, 설치 후 %d판 면제" % [every, free_games])

	# ---- 1+2. 면제 구간과 그 뒤의 주기 ----
	_fresh_install(m)
	var shown_at: Array[int] = []
	var total := free_games + every * 3 + 2
	for i in range(total):
		if _play_one(m, false):
			shown_at.append(i + 1)   # 몇 번째 판을 떠날 때 나왔는가
	print("")
	print("  %d판 연속 플레이 -> 광고 나온 판: %s" % [total, str(shown_at)])

	for at in shown_at:
		if at <= free_games:
			_fail("면제 구간(%d판까지)인 %d판째에 광고가 나왔다" % [free_games, at])
	# 면제 직후부터 every 마다. 첫 광고는 free_games + every 판째.
	var want: Array[int] = []
	var n: int = free_games + every
	while n <= total:
		want.append(n)
		n += every
	if shown_at != want:
		_fail("노출 시점이 %s 여야 하는데 %s 였다" % [str(want), str(shown_at)])
	else:
		print("  -> 면제 %d판 뒤 정확히 %d판 주기 (기대 %s)" % [free_games, every, str(want)])

	# ---- 3. 리워드 광고를 본 판은 안 센다 ----
	_fresh_install(m)
	for i in range(free_games):
		_play_one(m, false)          # 면제 소진
	var shown_rewarded := 0
	for i in range(every * 2):
		if _play_one(m, true):       # 매 판 부활 광고 시청
			shown_rewarded += 1
	print("")
	if shown_rewarded > 0:
		_fail("리워드 광고를 본 판만 %d번 했는데 전면광고가 %d번 나왔다 — 카운터에서 빠지지 않았다" % [
			every * 2, shown_rewarded])
	else:
		print("  리워드 광고 판 %d회 -> 전면광고 0회 (카운터에서 제외됨)" % (every * 2))
	# 그리고 그 뒤 정상 판을 채우면 나와야 한다 — 위가 "영영 안 나온다"로
	# 통과하는 구현도 있기 때문이다.
	var came_back := false
	for i in range(every):
		if _play_one(m, false):
			came_back = true
	if not came_back:
		_fail("리워드 판 뒤에 정상 판을 %d회 했는데도 광고가 안 나왔다 — 카운터가 멈춰 있다" % every)
	else:
		print("  이어서 정상 판 %d회 -> 광고 나옴 (카운터가 멈춘 것은 아님)" % every)

	# ---- 4. 저장되는가 ----
	_fresh_install(m)
	for i in range(free_games + every - 1):
		_play_one(m, false)          # 광고 직전까지
	var before: int = m.get("restarts_since_interstitial")
	var fresh: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh)
	await process_frame
	while fresh.get("boot_pending"):
		await process_frame
	var after: int = fresh.get("restarts_since_interstitial")
	var after_total: int = fresh.get("games_played_total")
	print("")
	print("  재실행 전후: 마지막 광고 이후 %d -> %d판, 누적 %d판" % [
		before, after, after_total])
	if after != before:
		_fail("앱을 다시 띄우니 카운터가 %d -> %d 로 바뀌었다 — 껐다 켜서 광고를 피할 수 있다" % [
			before, after])
	elif not fresh.call("_ad_try_interstitial"):
		# 새 인스턴스에서 한 판 더 하면 바로 나와야 한다.
		fresh.call("_start_countdown")
		fresh.call("_reset_game")
		if not fresh.call("_ad_try_interstitial"):
			_fail("재실행 뒤 한 판 더 했는데도 광고가 안 나왔다")
		else:
			print("  -> 재실행 뒤 한 판 더 하니 광고 나옴")
	fresh.queue_free()

	# ---- 5. 네 경로가 모두 세어지는가 ----
	# 각 핸들러를 직접 부른다. 하나라도 _reset_game 을 안 거치면 그 경로로만
	# 재시작하는 사용자는 광고를 영영 안 본다.
	print("")
	var paths := [
		["게임오버 PLAY AGAIN", "_on_gameover_play_again_pressed"],
		["게임오버/일시정지 HOME", "_on_pause_home_pressed"],
		["일시정지 RESTART", "_on_pause_restart_pressed"],
		["모드선택 복귀(restart_button)", "_on_restart_pressed"],
	]
	for entry in paths:
		_fresh_install(m)
		# 면제를 실제 판으로 소진한다. 새 설치 상태 그대로 한 판만 하면 그 판이
		# 면제에 걸려 카운터가 0 그대로이고, 경로가 멀쩡해도 실패로 읽힌다 —
		# 처음에 그렇게 짜서 네 경로가 전부 거짓 실패했다.
		for i in range(free_games):
			_play_one(m, false)
		m.call("_start_countdown")
		var was: int = m.get("restarts_since_interstitial")
		m.call(entry[1])
		var now: int = m.get("restarts_since_interstitial")
		if now != was + 1:
			_fail("%s 경로가 카운터를 올리지 않았다 (%d -> %d)" % [entry[0], was, now])
		else:
			print("  %-30s 카운터 +1" % entry[0])

	_fresh_install(m)
	print("")
	if fails == 0:
		print("check_ad_policy: OK")
	else:
		print("check_ad_policy: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
