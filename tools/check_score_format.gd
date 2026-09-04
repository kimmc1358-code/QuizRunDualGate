extends SceneTree

# 좁은 자리의 점수 표기가 다섯 글자를 절대 안 넘는지, 그리고 그 자리들이 정말
# 그 표기를 쓰는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_score_format.gd
#
# 왜 스크립트가 필요한가: 넘치는 순간이 화면에 나오려면 10만 점을 넣어야 하고,
# 그건 플레이테스트로 도달할 수 있는 값이 아니다. 그때까지 HUD 는 멀쩡해
# 보이다가, 어느 날 잘 하는 플레이어 한 명에게서만 숫자가 점수판 밖으로
# 삐져나간다.
#
# 두 가지를 따로 본다:
#
#   1. ScoreFormat.compact 자체가 int32 전 구간에서 다섯 글자 이하인가.
#      경계값(99,999 / 100,000 / 999,999 / ...)을 전부 짚는다 — 넘치는 곳이
#      있다면 거기다.
#   2. 게임이 그걸 쓰는가. 1 만 보면 포맷터는 완벽한데 HUD 가 여전히
#      "%05d" 를 쓰고 있어도 통과한다. 그래서 실제 _score_digit_layout /
#      _best_digit_layout 을 불러 나온 문자열을 잰다.

const MAX_CHARS := 5

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	# ---- 1. 요청받은 규칙 그대로 ----
	# 사양에 적힌 예시를 그대로 옮겨 둔다. 규칙이 바뀌면 여기가 먼저 깨져야
	# 하고, 깨진 자리가 곧 무엇이 바뀌었는지의 기록이 된다.
	var cases := [
		[0, "0"], [85, "85"], [1250, "1250"], [99999, "99999"],
		[100000, "100K"], [123456, "123K"], [999999, "999K"],
		[1000000, "1.0M"], [1250000, "1.2M"], [9999999, "9.9M"],
	]
	for c in cases:
		var got: String = ScoreFormat.compact(c[0])
		if got != c[1]:
			_fail("compact(%d) = %s, want %s" % [c[0], got, c[1]])
	print("  %d spec examples checked" % cases.size())

	# 앞자리 0 채우기가 정말 사라졌는지. 이게 이번 변경의 요지다.
	for v in [0, 5, 85, 1250]:
		var got: String = ScoreFormat.compact(v)
		if got.length() > 1 and got.begins_with("0"):
			_fail("compact(%d) = %s — still zero-padded" % [v, got])

	# ---- 2. 다섯 글자 계약, int32 끝까지 ----
	# 경계 근처는 한 칸씩, 그 사이는 성기게. 넘치는 값은 언제나 자릿수가
	# 바뀌는 경계에 있으므로 거기를 촘촘히 본다.
	var probes := {}
	for edge in [0, 100000, 1000000, 10000000, 100000000, 1000000000, 2147483647]:
		for d in range(-2, 3):
			var v: int = edge + d
			if v >= 0 and v <= 2147483647:
				probes[v] = true
	var v_sweep := 1
	while v_sweep < 2147483647:
		probes[v_sweep] = true
		v_sweep = int(v_sweep * 1.7) + 1
	var widest := ""
	var widest_at := 0
	for v in probes.keys():
		var s: String = ScoreFormat.compact(v)
		if s.length() > widest.length():
			widest = s
			widest_at = v
		if s.length() > MAX_CHARS:
			_fail("compact(%d) = %s — %d chars, the slot holds %d" % [v, s, s.length(), MAX_CHARS])
	print("  %d values swept, widest %s (%d chars) at %d" % [probes.size(), widest, widest.length(), widest_at])
	# 반대쪽도 본다. 어떤 값에서도 다섯 글자를 못 채운다면 칸이 과하게 잡혀
	# 있거나 이 상한이 실제 제약이 아니라는 뜻이고, 그러면 이 체커는 아무것도
	# 안 지킨다.
	if widest.length() < MAX_CHARS:
		_fail("nothing ever reaches %d chars — the limit this guards is not the real one" % MAX_CHARS)

	# ---- 3. 게임이 실제로 그 표기를 쓰는가 ----
	# 좁은 자리 둘의 레이아웃 함수를 그대로 불러서, 거기 들어간 문자열을 본다.
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var box: Rect2 = main.call("_score_box_rect", view)
	print("")
	print("  %-12s %-8s %-8s" % ["score", "HUD", "BEST"])
	for v in [0, 85, 1250, 99999, 123456, 1250000]:
		main.set("score", v)
		main.get("best_scores")[main.get("current_mode")] = v
		var hud: String = main.call("_score_digit_layout", view)["text"]
		var best: String = main.call("_best_digit_layout", box)["text"]
		var want: String = ScoreFormat.compact(v)
		var ok: bool = hud == want and best == want
		if not ok:
			_fail("score %d draws HUD %s / BEST %s, but compact() says %s — a call site is still formatting on its own" % [
				v, hud, best, want])
		print("  %-12d %-8s %-8s %s" % [v, hud, best, "ok" if ok else "FAIL"])

	# 그리고 그린 자리가 점수판을 넘지 않는가. 글자 수 계약이 지켜져도 글꼴이
	# 커지면 넘칠 수 있고, 그건 글자 수로는 안 잡힌다.
	print("")
	for v in [0, 99999, 123456, 1250000]:
		main.set("score", v)
		var layout: Dictionary = main.call("_score_digit_layout", view)
		var pos: PackedVector2Array = layout["pos"]
		if pos.is_empty():
			_fail("score %d produced no glyph positions" % v)
			continue
		var font: Font = layout["font"]
		var last: float = pos[pos.size() - 1].x + font.get_string_size(
			layout["text"][layout["text"].length() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, layout["size"]).x
		var inside: bool = pos[0].x >= box.position.x - 0.5 and last <= box.end.x + 0.5
		if not inside:
			_fail("score %d draws %.0f..%.0f against a box of %.0f..%.0f" % [
				v, pos[0].x, last, box.position.x, box.end.x])
		print("  score %-8d ink %.0f..%.0f  box %.0f..%.0f  %s" % [
			v, pos[0].x, last, box.position.x, box.end.x, "ok" if inside else "OVERFLOW"])

	print("")
	if fails == 0:
		print("check_score_format: OK")
	else:
		print("check_score_format: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
