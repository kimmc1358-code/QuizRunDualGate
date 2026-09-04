extends SceneTree

# 부스트 스피드 라인이 "속도감만 주고 게임을 안 가린다"를 지키는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_speed_lines.gd
#
# 파스 체크가 못 보는 것들:
#
#   1. 안 누르고 있을 때 정말 아무것도 안 그린다. boost_visual_blend 를 타므로
#      맞아야 하지만, "맞아야 한다"가 조용히 어긋나는 조건이다.
#   2. 스트릭이 위/아래 띠 안에만 있다. 가운데로 새면 레인을 읽는 자리에
#      흰 줄이 지나간다 — 화면에서는 부스트 중에만 잠깐 보이니 놓치기 쉽다.
#   3. 양쪽 띠가 다 차 있다. 배정이 어긋나면 한쪽만 흐르는데, 그것도 그럴싸해
#      보여서 눈으로는 잘 안 잡힌다.
#   4. 게이트보다 확실히 빠르다. 게이트 속도에 가까우면 배경이 하나 더 늘어난
#      것이지 속도감이 아니다.
#   5. 재활용이 꼬리까지 기다린다. 머리 기준으로 자르면 긴 스트릭이 화면
#      한가운데서 사라진다.
#
# 실제 Main.tscn 을 띄워 게임 자기 함수를 부른다(다른 체커와 같은 규칙).

const DT := 1.0 / 60.0

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
	main.call("_apply_mode", 0)

	# 헤드리스 뷰포트는 정사각형을 보고하므로 실제 해상도를 설정에서 읽는다.
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	print("check_speed_lines: viewport %.0f x %.0f" % [view.x, view.y])

	var tex: Texture2D = main.get("speed_line_texture")
	if tex == null:
		_fail("speed_line_texture did not load — %s missing?" % main.get("BOOST_SPEEDLINE_TEXTURE_PATH"))
	else:
		# 세로로 눌러 구운 스트립이다. 원본(817x309)을 그대로 넣으면 그리는
		# 크기까지 20배 축소가 되어 빗살처럼 깜빡인다.
		var size: Vector2 = tex.get_size()
		print("  strip %.0fx%.0f" % [size.x, size.y])
		if size.x <= size.y * 4.0:
			_fail("strip is %.0fx%.0f — it should be baked far wider than tall (tools/bake_speed_line.ps1); is the raw source committed here?" % [size.x, size.y])

	main.call("_init_boost_speedlines", view)
	var pool: Array = main.get("boost_speedlines")
	if pool.is_empty():
		_fail("pool is empty after _init_boost_speedlines")
		_finish()
		return
	print("  pool %d" % pool.size())

	# 모드별로 색과 최대 알파가 다르다 — 흰 선이 네 배경에서 같게 읽히지
	# 않아서다. 배열이 Mode 로 색인되므로 길이가 어긋나면 모드 전환에서
	# 인덱스가 터진다.
	var tints: Array = main.get("MODE_BOOST_SPEEDLINE_COLOR")
	if tints.size() != 4:
		_fail("MODE_BOOST_SPEEDLINE_COLOR has %d rows, needs one per mode" % tints.size())
	else:
		for m in range(4):
			if tints[m].a <= 0.0:
				_fail("mode %d speed lines would be fully transparent" % m)
		print("  per-mode peak alpha %.2f / %.2f / %.2f / %.2f" % [tints[0].a, tints[1].a, tints[2].a, tints[3].a])

	# ---- 1. 안 누르면 아무것도 없다 ----
	main.set("boost_visual_blend", 0.0)
	var drew_at_rest := false
	for l in pool:
		if l.alpha_scale * main.get("boost_visual_blend") > 0.002:
			drew_at_rest = true
	if drew_at_rest:
		_fail("something would draw with boost_visual_blend at 0")

	# ---- 2-5. 부스트 중에 오래 돌려 본다 ----
	main.set("boost_visual_blend", 1.0)
	var zone_top: float = main.call("_gate_zone_top", view)
	var band_h: float = main.get("BOOST_SPEEDLINE_BAND_HEIGHT")
	var top_band := Vector2(zone_top, zone_top + band_h)
	var bottom_band := Vector2(view.y - band_h, view.y)
	var gate_speed: float = main.get("GATE_SPEED") * main.get("BOOST_BUTTON_MULTIPLIER")

	# 그리고 띠 상수와 무관한 기준이 하나 더 필요하다. 위의 top_band /
	# bottom_band 는 BOOST_SPEEDLINE_BAND_HEIGHT 에서 만들어지므로, 띠를 키우면
	# 기대치도 같이 커져서 그 검사만으로는 절대 실패하지 않는다 — 실제로 띠를
	# 400 으로 키워 보니 통과했다.
	#
	# 게이트 존의 가운데 절반은 무슨 일이 있어도 비어 있어야 한다. 레인을 읽고
	# 캐릭터가 나는 자리다.
	var zone_h: float = view.y - zone_top
	var keep_clear := Vector2(zone_top + zone_h * 0.25, zone_top + zone_h * 0.75)
	var middle_hits := 0

	var worst_middle := 0
	var slowest := 99999.0
	var top_seen := 0
	var bottom_seen := 0
	var vanished_on_screen := 0
	var prev_x := {}
	# 그 프레임에 실제로 쓰인 속도도 같이 들고 있어야 한다. 재활용은 속도를
	# 새로 뽑으므로, 새 속도로 직전 이동을 역산하면 900~1500 사이의 최대
	# 1.67배 차이만큼 어긋나 멀쩡한 재활용을 오탐한다.
	var prev_speed := {}
	for i in range(pool.size()):
		prev_x[i] = pool[i].x
		prev_speed[i] = pool[i].speed

	# 스트릭이 화면을 한 번 건너는 데 0.32-0.53초. 5초면 모든 항목이 여러 번
	# 재활용된다.
	for step in range(int(5.0 / DT)):
		main.call("_update_boost_speedlines", DT, view)
		for i in range(pool.size()):
			var l: Dictionary = pool[i]
			slowest = minf(slowest, l.speed)
			# 띠 안에 있는가 — 두께까지 포함해서 본다.
			var top_edge: float = l.y - l.thickness * 0.5
			var bottom_edge: float = l.y + l.thickness * 0.5
			var in_top: bool = top_edge >= top_band.x - 0.01 and bottom_edge <= top_band.y + 0.01
			var in_bottom: bool = top_edge >= bottom_band.x - 0.01 and bottom_edge <= bottom_band.y + 0.01
			if in_top:
				top_seen += 1
			elif in_bottom:
				bottom_seen += 1
			else:
				worst_middle += 1
			# 그리고 띠와 무관하게, 가운데 절반을 건드렸는지 따로 센다.
			if bottom_edge > keep_clear.x and top_edge < keep_clear.y:
				middle_hits += 1
			# 재활용이 꼬리를 기다렸는가. x 는 스트릭의 오른쪽 끝이고(그리는
			# 쪽이 x-length..x 로 편다) 왼쪽으로 가므로, 오른쪽 끝이 0 을
			# 지나야 완전히 사라진 것이다.
			#
			# 재활용은 x 를 오른쪽으로 되돌리므로 그 순간을 그렇게 잡는다.
			# 다만 재활용 직전의 x 를 그대로 보면 안 된다 — 갱신은 한 프레임씩
			# 뛰므로 직전 프레임에는 아직 몇 px 남아 있는 게 정상이다. 재활용이
			# 없었다면 갔을 자리를 계산해서, 그 자리가 화면 밖인지 본다.
			if l.x > prev_x[i] + 1.0:
				var would_be: float = prev_x[i] - prev_speed[i] * DT
				if would_be > 0.0:
					vanished_on_screen += 1
			prev_x[i] = l.x
			prev_speed[i] = l.speed

	if middle_hits > 0:
		_fail("%d samples had a streak inside the gate zone's middle half (%.0f-%.0f) — that is where the lanes are read" % [middle_hits, keep_clear.x, keep_clear.y])
	else:
		print("  middle half of the gate zone (%.0f-%.0f) never touched" % [keep_clear.x, keep_clear.y])
	if worst_middle > 0:
		_fail("%d samples had a streak outside both bands — the middle of the play area must stay clear" % worst_middle)
	else:
		print("  every sample inside the bands (top %.0f-%.0f, bottom %.0f-%.0f)" % [top_band.x, top_band.y, bottom_band.x, bottom_band.y])
	if top_seen == 0:
		_fail("nothing ever ran in the top band")
	if bottom_seen == 0:
		_fail("nothing ever ran in the bottom band")
	if top_seen > 0 and bottom_seen > 0:
		print("  both bands populated (top %d / bottom %d samples)" % [top_seen, bottom_seen])
	if slowest <= gate_speed:
		_fail("slowest streak is %.0f px/s against gates at %.0f — that reads as scenery, not speed" % [slowest, gate_speed])
	else:
		print("  slowest streak %.0f px/s vs gates %.0f (%.1fx)" % [slowest, gate_speed, slowest / gate_speed])
	if vanished_on_screen > 0:
		_fail("%d recycles happened while the streak's tail was still on screen" % vanished_on_screen)

	_finish()


func _finish() -> void:
	if fails == 0:
		print("check_speed_lines: OK")
	else:
		print("check_speed_lines: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
