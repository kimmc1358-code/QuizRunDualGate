extends SceneTree

# _spawn_gate 가 놓는 다음 구멍이, 플레이어가 정말로 도달할 수 있는 자리인지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_gate_reach.gd
#   ... --script res://tools/check_gate_reach.gd -- --seed 12345
#
# 파스 체크가 절대 못 보는 것이고, 실제로 오래 틀려 있었다:
#
#   1. available_time 이 GATE_SPEED 만 봤다. 게이트는 부스트 중 그 2배로
#      다가오고, 게이트는 900px 앞에서 생성되므로 플레이어는 생성된 뒤에
#      언제든 부스트를 누를 수 있다 — 놓을 때는 여유롭던 자리가 누르는 순간
#      도달 불가능해진다.
#   2. up_reach 가 |flap_velocity| 를 유지 상승률로 썼다. 탭은 속도를 더하는
#      게 아니라 덮어쓰므로 그건 순간 속도지 유지되는 값이 아니다. 480x854
#      에서 실측하면 부스트 중 실제 상승 294px 대 배치 상한 427px 였다.
#
# 두 경우 다 화면에서는 "가끔 아무리 두드려도 못 올라가는 게이트"로만 보이고,
# 그게 내 실력인지 게임 탓인지 플레이어는 구분할 수 없다. 그래서 눈이 아니라
# 스크립트가 지켜야 한다.
#
# 기대치를 게임 공식에서 베끼지 않는다 — 그러면 공식이 틀려도 그대로 통과한다.
# 대신 실제 gravity/flap_velocity/max_fall_speed 로 1/60 초씩 적분해서 "정말
# 얼마나 올라가고 내려가는가"를 재고, 그것과 실제 배치를 비교한다. 이 파일에서
# 게임과 공유하는 것은 최악의 시간(부스트 내내 유지)뿐이고, 그건 게임이 맞춰야
# 할 안전 기준이지 게임에서 읽어 오는 값이 아니다.

const DT := 1.0 / 60.0
const SPAWNS_PER_PHASE := 300
const RNG_SEED := 20260905
const EPS := 0.5   # px, 적분 잔차

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# 탭 간격 tap 으로 계속 두드릴 때 seconds 동안 실제로 올라가는 거리(px).
# 게임의 climb_rate 공식과 독립이다 — 여기는 그냥 물리를 돌린다.
func _climb(main: Node2D, seconds: float, tap: float) -> float:
	var y := 0.0
	var vel: float = main.flap_velocity   # t=0 의 탭
	var since := 0.0
	var t := 0.0
	while t < seconds:
		vel = minf(vel + main.gravity * DT, main.max_fall_speed)
		y += vel * DT
		since += DT
		if since >= tap:
			vel = main.flap_velocity
			since -= tap
		t += DT
	return -y


# 가만히 두었을 때 seconds 동안 떨어지는 거리(px). 정지 상태에서 시작하므로
# max_fall_speed 까지 붙는 데 걸리는 시간이 자연히 포함된다 — 게임 공식은 그
# 램프를 무시하고 곧장 max_fall_speed 를 쓰므로, 여기가 더 비관적이다.
func _fall(main: Node2D, seconds: float) -> float:
	var y := 0.0
	var vel := 0.0
	var t := 0.0
	while t < seconds:
		vel = minf(vel + main.gravity * DT, main.max_fall_speed)
		y += vel * DT
		t += DT
	return y


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var seed_value := RNG_SEED
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--seed":
			seed_value = int(args[i + 1])
	seed(seed_value)

	# 헤드리스 뷰포트는 정사각형을 보고하므로 실제 해상도를 설정에서 읽는다.
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))

	# 최악의 시간: 부스트를 스폰부터 판정까지 계속 붙잡고 있는 경우. 게이트는
	# 직전 게이트가 판정되는 그 프레임에 생성되므로(_update_playing), 이게
	# 플레이어가 직전 구멍에서 다음 구멍까지 쓸 수 있는 시간 전부다.
	var worst_time: float = main.base_gate_spacing / (main.GATE_SPEED * main.BOOST_BUTTON_MULTIPLIER)
	var tap: float = main.reach_tap_interval
	var can_climb: float = _climb(main, worst_time, tap)
	var can_fall: float = _fall(main, worst_time)

	print("check_gate_reach: seed %d, viewport %.0fx%.0f" % [seed_value, view.x, view.y])
	print("  worst case %.2fs (spacing %.0f / speed %.0f x boost %.1f), tapping every %.2fs" % [
		worst_time, main.base_gate_spacing, main.GATE_SPEED, main.BOOST_BUTTON_MULTIPLIER, tap])
	print("  simulated: climbs %.0f px, falls %.0f px" % [can_climb, can_fall])

	if can_climb <= 0.0:
		_fail("the character cannot climb at all at a %.2fs tap interval — reach_tap_interval is past the apex (%.2fs)" % [
			tap, absf(main.flap_velocity) / main.gravity])

	var names := ["SKY", "JUNGLE", "OCEAN", "DREAM"]
	# 각 페이즈의 첫 게이트. phase_gate_counts 는 누적 경계라(10, 30, 60) 이걸
	# 손으로 적으면 표가 바뀔 때 조용히 한 페이즈를 건너뛴다 — 실제로 처음
	# 쓴 [0, 15, 25, 40] 은 페이즈 4 를 통째로 빠뜨리고 2 를 두 번 쟀다.
	# move_ratio 는 phase_index 로만 갈리므로 각 페이즈의 첫 칸이면 충분하다.
	var phase_probe := []
	var boundary := 0
	for length in main.phase_gate_counts:
		if length > 0:
			phase_probe.append(boundary)
			boundary += length
	phase_probe.append(boundary)   # 마지막 페이즈는 열려 있다
	var phases_seen := {}
	var worst_up := 0.0
	var worst_down := 0.0

	for mode in range(4):
		main.call("_apply_mode", mode)
		main.set("current_mode", mode)
		for passed in phase_probe:
			main.set("gates_passed", passed)
			var phase: int = main.call("_get_phase_index", passed)
			# 게임 시작과 같은 자리에서 출발한다(_reset_game: last_zone_center = player_y).
			main.set("last_zone_center", main.get("player_y"))
			var up_here := 0.0
			var down_here := 0.0
			for i in range(SPAWNS_PER_PHASE):
				var before: float = main.get("last_zone_center")
				main.get("gates").clear()
				main.call("_spawn_gate", view)
				var delta: float = main.get("last_zone_center") - before
				if delta < 0.0:
					up_here = maxf(up_here, -delta)
				else:
					down_here = maxf(down_here, delta)
			phases_seen[phase] = true
			worst_up = maxf(worst_up, up_here)
			worst_down = maxf(worst_down, down_here)
			var bad := ""
			if up_here > can_climb + EPS:
				bad += " UP-UNREACHABLE"
			if down_here > can_fall + EPS:
				bad += " DOWN-UNREACHABLE"
			if bad != "":
				_fail("%s phase %d asked for %.0f px up / %.0f px down against %.0f / %.0f possible —%s" % [
					names[mode], phase + 1, up_here, down_here, can_climb, can_fall, bad])
			print("  %-7s phase %d   worst up %3.0f / down %3.0f px   %s" % [
				names[mode], phase + 1, up_here, down_here, "ok" if bad == "" else "FAIL"])

	print("")
	print("  worst over everything: up %.0f of %.0f possible (%.0f%% margin), down %.0f of %.0f (%.0f%%)" % [
		worst_up, can_climb, (1.0 - worst_up / can_climb) * 100.0,
		worst_down, can_fall, (1.0 - worst_down / can_fall) * 100.0])
	# 반대쪽 실패도 본다: 여유가 지나치게 크면 배치가 도달 가능성이 아니라
	# 다른 무언가에 눌려 있다는 뜻이고, 그러면 이 체커는 아무것도 안 지킨다.
	if phases_seen.size() != main.call("_phase_count"):
		_fail("only covered %d of %d phases — the probe points drifted from phase_gate_counts" % [phases_seen.size(), main.call("_phase_count")])
	if worst_up < can_climb * 0.25:
		_fail("placement never uses more than %.0f%% of the climb — up_reach is not what is binding, so this check is vacuous" % (worst_up / can_climb * 100.0))

	if fails == 0:
		print("check_gate_reach: OK")
	else:
		print("check_gate_reach: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
