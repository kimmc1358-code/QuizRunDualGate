extends SceneTree

# MIX(DREAM) 가 세 퀴즈를 정말 섞어 내는지, 그리고 섞으면서도 페이즈 난이도
# 곡선을 단일 모드와 똑같이 타는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_mix_mode.gd
#   ... --script res://tools/check_mix_mode.gd -- --seed 12345
#
# 두 번째가 이 체커의 요점이다. 첫 번째(섞이는가)는 한 판만 해 봐도 보이지만,
# 난이도가 안 오르는 것은 보이지 않는다 — MIX 가 늘 phase 1 문제만 낸다 해도
# 화면에는 세 종류가 잘 섞여 나오고, 국기가 계속 쉬운 것이 곡선 탓인지 운
# 탓인지 플레이로는 구분할 수 없다. 그래서 통계로 잰다: 각 퀴즈 종류마다
# 난이도를 대표하는 값 하나를 정하고, MIX 의 phase 1 과 phase 4 를 비교하고,
# 다시 그것을 같은 phase 의 단일 모드와 비교한다.
#
#   국기   답의 recognition_tier 평균. 페이즈가 오르면 무명 국기 쪽으로 간다.
#   연산   답 절댓값의 평균. 페이즈가 오르면 수가 커진다.
#   스트룹 단어색과 잉크색의 색상환 거리 평균. 페이즈가 오르면 가까워진다.
#
# 어느 쪽도 게임의 곡선표를 베끼지 않는다. 실제로 생성된 문제를 세는 것이라,
# 곡선이 바뀌면 숫자는 같이 움직이고 "MIX 와 단일 모드가 같은가" 만 남는다.

const SPAWNS := 900
const RNG_SEED := 20260905

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# 한 모드/한 페이즈에서 게이트를 SPAWNS 개 뽑고, 종류별 개수와 난이도 통계를
# 돌려준다. 게임의 _spawn_gate 를 그대로 부른다.
func _sample(main: Node2D, mode: int, passed: int, view: Vector2) -> Dictionary:
	main.call("_apply_mode", mode)
	main.set("current_mode", mode)
	main.set("gates_passed", passed)
	main.set("last_quiz_key", "")
	main.get("mix_quiz_bag").clear()
	main.set("last_zone_center", main.get("player_y"))

	var counts := [0, 0, 0]            # QuizKind 순서: FLAG, MATH, STROOP
	var tier_sum := 0.0
	var answer_sum := 0.0
	var hue_sum := 0.0
	var order: Array[int] = []
	var worst_run := 1
	var run := 1
	var missing_kind := 0
	var stroop_data_wrong := 0

	var names: Dictionary = {}
	for rec in main.get("flag_records"):
		names[str(rec.code)] = int(rec.get("recognition_tier", 1))

	for i in range(SPAWNS):
		main.get("gates").clear()
		main.call("_spawn_gate", view)
		var g: Dictionary = main.get("gates")[0]
		if not g.has("quiz_kind"):
			missing_kind += 1
			continue
		var k: int = g.quiz_kind
		counts[k] += 1
		order.append(k)
		if order.size() > 1:
			run = run + 1 if order[order.size() - 2] == k else 1
			worst_run = maxi(worst_run, run)
		# 스트룹 게이트만 색 인덱스를 들고 다녀야 한다. 다른 종류가 들고 있으면
		# 질문 상자가 엉뚱한 프레임에 색을 칠하고, 스트룹이 안 들고 있으면
		# 상자가 통째로 안 그려진다.
		var has_ink: bool = g.has("ocean_answer_index")
		if has_ink != (k == 2):
			stroop_data_wrong += 1
		match k:
			0:
				tier_sum += float(names.get(str(g.target_code), 1))
			1:
				answer_sum += absf(float(str(g.target_code).to_int()))
			2:
				hue_sum += float(main.call("_ocean_color_distance",
					g.ocean_word_index, g.ocean_answer_index))

	if missing_kind > 0:
		_fail("%d gates carried no quiz_kind — the draw code has nothing to branch on" % missing_kind)
	if stroop_data_wrong > 0:
		_fail("%d gates had ocean colour indices that do not match their kind" % stroop_data_wrong)

	return {
		"counts": counts,
		"worst_run": worst_run,
		"tier": tier_sum / maxf(1.0, float(counts[0])),
		"answer": answer_sum / maxf(1.0, float(counts[1])),
		"hue": hue_sum / maxf(1.0, float(counts[2])),
	}


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

	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	print("check_mix_mode: seed %d, %d spawns per sample" % [seed_value, SPAWNS])

	# phase_gate_counts 에서 첫 페이즈와 마지막 페이즈의 통과 수를 뽑는다.
	var last_passed := 0
	for length in main.phase_gate_counts:
		if length > 0:
			last_passed += length
	var phase_count: int = main.call("_phase_count")

	# ---- 1. 단일 모드는 한 종류만 낸다 ----
	print("")
	var single := {0: "FLAG", 1: "MATH", 2: "STROOP"}
	for mode in range(3):
		var s: Dictionary = _sample(main, mode, 0, view)
		var counts: Array = s["counts"]
		if counts[mode] != SPAWNS:
			_fail("mode %d produced %s, want all %d as %s" % [mode, str(counts), SPAWNS, single[mode]])
		print("  mode %d  %-22s %s" % [mode, str(counts), "ok" if counts[mode] == SPAWNS else "FAIL"])

	# ---- 2. MIX 는 셋을 고르게, 세 번 연속 없이 ----
	print("")
	var mix: Dictionary = _sample(main, 3, 0, view)
	var mc: Array = mix["counts"]
	var lo: float = float(SPAWNS) / 3.0 * 0.85
	var hi: float = float(SPAWNS) / 3.0 * 1.15
	for k in range(3):
		if float(mc[k]) < lo or float(mc[k]) > hi:
			_fail("MIX drew %s %d times, want %.0f-%.0f" % [single[k], mc[k], lo, hi])
	print("  MIX counts %s (want %.0f-%.0f each)" % [str(mc), lo, hi])
	# 주머니는 종류당 정확히 하나씩 담기므로 경계에서만 두 번 이어질 수 있다.
	if mix["worst_run"] > 2:
		_fail("MIX ran the same quiz %d times in a row — the bag is not being used" % mix["worst_run"])
	elif mix["worst_run"] < 2:
		_fail("MIX never repeats at all — that is alternation, not a shuffle bag, and the player can predict the next quiz")
	print("  longest same-kind run %d (want exactly 2)" % mix["worst_run"])

	# ---- 3. 난이도가 페이즈를 탄다. 그리고 단일 모드와 같은 곡선을 탄다 ----
	# 이게 요청의 핵심이다: "MIX 도 다른 단일 모드처럼 phase 진행시마다 난이도
	# 올라가게".
	print("")
	var mix_lo: Dictionary = _sample(main, 3, 0, view)
	var mix_hi: Dictionary = _sample(main, 3, last_passed, view)
	var sky_lo: Dictionary = _sample(main, 0, 0, view)
	var sky_hi: Dictionary = _sample(main, 0, last_passed, view)
	var jg_lo: Dictionary = _sample(main, 1, 0, view)
	var jg_hi: Dictionary = _sample(main, 1, last_passed, view)
	var oc_lo: Dictionary = _sample(main, 2, 0, view)
	var oc_hi: Dictionary = _sample(main, 2, last_passed, view)

	print("  %-8s %-10s %10s %10s   %10s %10s" % ["kind", "metric", "MIX p1", "MIX p%d" % phase_count, "solo p1", "solo p%d" % phase_count])
	var rows := [
		["FLAG", "tier", "tier", mix_lo, mix_hi, sky_lo, sky_hi, 1],    # 오를수록 어렵다
		["MATH", "answer", "answer", mix_lo, mix_hi, jg_lo, jg_hi, 1],
		["STROOP", "hue dist", "hue", mix_lo, mix_hi, oc_lo, oc_hi, -1], # 내릴수록 어렵다
	]
	for r in rows:
		var key: String = r[2]
		var m_lo: float = r[3][key]
		var m_hi: float = r[4][key]
		var s_lo: float = r[5][key]
		var s_hi: float = r[6][key]
		var dir: int = r[7]
		print("  %-8s %-10s %10.2f %10.2f   %10.2f %10.2f" % [r[0], r[1], m_lo, m_hi, s_lo, s_hi])
		# (a) MIX 안에서 난이도가 실제로 움직였는가.
		if (m_hi - m_lo) * float(dir) <= 0.0:
			_fail("%s does not get harder across phases in MIX (%.2f -> %.2f) — is phase_index reaching the generator?" % [
				r[0], m_lo, m_hi])
		# (b) 그 움직임이 단일 모드와 같은가. 같은 생성기를 같은 phase 로
		#     부르므로 표본 오차 말고는 벌어질 이유가 없다.
		var span: float = absf(s_hi - s_lo)
		for pair in [[m_lo, s_lo, "p1"], [m_hi, s_hi, "p%d" % phase_count]]:
			var drift: float = absf(float(pair[0]) - float(pair[1]))
			if drift > maxf(span * 0.25, absf(float(pair[1])) * 0.12):
				_fail("%s at %s: MIX %.2f vs solo %.2f — MIX is not on the same curve" % [
					r[0], pair[2], pair[0], pair[1]])

	print("")
	if fails == 0:
		print("check_mix_mode: OK")
	else:
		print("check_mix_mode: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
