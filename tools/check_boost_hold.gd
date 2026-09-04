extends SceneTree

# 부스트 홀드가 어느 길로 끝나든 소리와 겉모습이 같이 풀리는지 본다.
#
#   godot --headless --path . --script tools/check_boost_hold.gd
#
# 이 소리만 루프라서, 안 꺼지면 그냥 한 번 더 나는 게 아니라 영영 웅웅거린다.
# 그런데 홀드가 풀리는 길이 셋이다:
#   1. 손을 뗀다            -> button_up
#   2. 죽거나 일시정지한다   -> 버튼이 숨는다. 숨겨진 Button 은 button_up 을
#                             쏘지 않으므로 _process 가 직접 푼다
#   3. 다시 시작한다        -> _reset_game
# 2번이 신호가 아니라 손으로 푸는 길이라, 여기가 조용히 어긋나기 쉽다. 그
# 안에서도 죽는 길과 멈추는 길은 다르게 굴어야 해서 따로 본다 — 일시정지는
# _update_fx 가 멈추므로 겉모습이 그대로 얼어 있는 것이 맞고, 게임 오버는
# 멈추지 않으므로 스스로 끝나야 한다.
#
# 부스트 화염(BOOST_BURST_*)도 여기서 본다. 소리와 같은 수명을 살아야
# 하므로 — 누르면 켜지고, 누르는 동안 돌고, 놓으면 꺼진다 — 홀드가 끈적해지는
# 것과 똑같은 방식으로 화염도 끈적해질 수 있다.
#
# 알파도 같이 본다. 누를 때 트윈으로 진해지는데, 2번에서 알파만 되돌리고
# 트윈을 안 죽이면 살아남은 트윈이 다음 프레임에 도로 눌린 값으로 칠한다 —
# 실제로 그렇게 새 버튼이 눌린 채로 돌아온 적이 있다.
#
# 실제 Main.tscn 을 띄워 게임 자기 함수를 부른다(다른 체커와 같은 규칙).

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		fails += 1
	print("  %-42s %-7s (want %s)  %s" % [label, str(got), str(want), "ok" if ok else "FAIL"])


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	# 게임이 스스로 부팅할 때까지 기다린다 — 로고 화면에서 _process 가
	# boot_pending 을 보고 _boot_load 를 부른다. 여기서 직접 부르면 그 플래그가
	# 그대로 남아 잠시 뒤 한 번 더 돌고, 오디오 플레이어가 통째로 새로 만들어져
	# 아래에서 잡아 둔 참조는 버려진 쪽을 가리키게 된다.
	while main.get("boot_pending"):
		await process_frame
	main.call("_apply_mode", 0)
	var sfx: AudioStreamPlayer = main.get("fx_sound_boost")
	var button: Button = main.get("boost_button")
	var idle_alpha: float = main.get("BOOST_BUTTON_ALPHA")

	print("setup")
	_check("stream loaded", sfx.stream != null, true)
	_check("on the SFX bus", sfx.bus, "SFX")
	# 클립은 2.25초뿐이라 홀드가 그보다 길면 루프가 없으면 끊긴다.
	_check("loop enabled", sfx.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	# 그리고 루프가 실제로 도는지까지 본다. loop_mode 만 켜고 loop_end 를 0으로
	# 두면 길이 0짜리 구간을 돌아 첫 프레임에 재생이 끝나 버린다 — 실제로 그
	# 상태였고, 플래그만 확인하는 검사로는 잡히지 않았다.
	sfx.play()
	await create_timer(sfx.stream.get_length() + 0.5).timeout
	_check("still playing past the clip length", sfx.playing, true)
	sfx.stop()

	print("\n0. burst art, every mode")
	# 다섯 칸이 다 살아 있어야 한다. _slice_spritesheet 는 빈 칸을 버리므로,
	# 스트립을 잘못 이어 붙였거나 한 칸이 비면 조용히 네 장짜리 애니메이션이
	# 된다. 스트립은 tools/build_boost_burst_strips.ps1 이 만든다.
	for m in range(4):
		main.call("_apply_mode", m)
		var frames: Array = main.get("boost_burst_frames")
		_check("mode %d burst frames" % m, frames.size(), 5)
		# 그리고 칸이 정사각형이 아니다. 300x256 을 정사각형 rect 에 그리면
		# 화염이 세로로 눌린다 — _draw_boost_burst 는 높이를 텍스처에서
		# 받아 오는데, 그 전제가 여기서 깨지면 조용히 찌그러진다.
		if frames.size() == 5:
			var cell: Vector2 = frames[0].get_size()
			_check("mode %d cell is wider than tall" % m, cell.x > cell.y, true)
	main.call("_apply_mode", 0)
	_check("idle before any press", main.get("boost_burst_elapsed"), -1.0)

	print("\n0b. plume geometry, every mode")
	await _arm(main)
	# 화염의 머리는 몸통 실루엣 안에 있어야 "뒤에서 뿜어져 나온다"로 읽힌다.
	# 앞코를 뚫고 나가면 캐릭터가 불을 물고 있는 그림이 되고, 뒤로 빠져나가면
	# 몸에서 떨어진 잔해가 된다. 오프셋이 모드별이 된 뒤로는 각 모드를 자기
	# 몸 폭으로 재야 한다 — 가장 좁은 캐릭터 하나로 재면 DREAM(1.20)에서
	# 실제로는 몸 안에 있는 위치를 밖이라고 잡는다.
	var player_x: float = main.get("PLAYER_X")
	var visual: Vector2 = main.get("PLAYER_VISUAL_SIZE")
	for m in range(4):
		main.call("_apply_mode", m)
		# 크기도 모드별이다 — DREAM 만 셀 비율이 달라서 따로 잡혀 있다.
		var plume_w: float = visual.x * main.get("MODE_BOOST_BURST_SIZE_SCALE")[m]
		var head: Vector2 = main.call("_boost_burst_head")
		var half_body: float = visual.x * 0.5 * main.get("MODE_VISUAL_SIZE_SCALE")[m]
		_check("mode %d head is inside the body" % m,
				head.x > player_x - half_body and head.x < player_x + half_body, true)
		# 세로도 같다. 꼬리 쪽으로 내리는 건 맞지만, 몸통 아래로 완전히 빠지면
		# 캐릭터와 무관하게 떠 있는 불꽃이 된다.
		_check("mode %d head is inside the body vertically" % m,
				absf(head.y - main.get("player_y")) < half_body, true)
		# 꼬리가 화면 왼쪽으로 조금 넘어가는 건 허용한다 — DREAM 은 유니콘
		# 자기 무지개 꼬리를 피하려고 일부러 넘긴다. 다만 대부분이 화면 밖으로
		# 나가면 불꽃이 있으나 마나이므로, 70% 는 남아 있어야 한다.
		var on_screen: float = minf(head.x, plume_w)
		_check("mode %d keeps most of the plume on screen" % m,
				on_screen >= plume_w * 0.7, true)
	# _apply_mode 는 버스트를 -1 로 되돌린다. 그래서 위 루프는 반드시 프레스
	# 앞에 와야 하고, 여기서 판을 다시 깔고 눌러야 한다.
	main.call("_apply_mode", 0)

	print("\n1. button_up")
	await _arm(main)
	main.call("_on_boost_pressed")
	var burst_x0: float = main.call("_boost_burst_head").x
	await process_frame
	_check("press -> playing", sfx.playing, true)
	_check("press -> held", main.get("boost_button_held"), true)
	_check("press -> burst playing", main.get("boost_burst_elapsed") >= 0.0, true)
	for i in 12:
		await process_frame
	# 그리고 캐릭터에 붙어 있어야 한다. 이전 링은 터진 자리에 남아 월드를 타고
	# 흘러갔지만, 이건 추진기라 몸에서 떨어지면 잔해로 읽힌다. 월드를 타는
	# 코드가 되살아나면 x 가 왼쪽으로 밀려 여기서 잡힌다.
	_check("burst head stays put in x", is_equal_approx(main.call("_boost_burst_head").x, burst_x0), true)
	# 세로도 따라가야 한다 — 붙어 있다는 건 캐릭터가 오르내릴 때 같이
	# 오르내린다는 뜻이다. player_y 를 밀어 놓고 머리가 따라오는지 본다.
	var y0: float = main.call("_boost_burst_head").y
	main.set("player_y", main.get("player_y") + 40.0)
	_check("burst head follows the character in y",
			is_equal_approx(main.call("_boost_burst_head").y, y0 + 40.0), true)
	main.set("player_y", main.get("player_y") - 40.0)
	# 버스트는 누르고 있는 동안 계속 탄다. 한 바퀴 길이의 세 배를 돌려도
	# 살아 있어야 하고, 루프는 서스테인 안에서만 돌아야 한다 — 전체를 감으면
	# 불꽃이 아예 없는 마지막 프레임(불티)을 매 바퀴 지나가며 깜빡인다.
	var dur: float = main.get("boost_burst_duration")
	var sustain_start: float = dur * main.call("_boost_burst_sustain_start")
	var sustain_end: float = dur * main.get("BOOST_BURST_FADE_START")
	var dipped_below := false
	var ran_past := false
	var hold_y: float = main.get("player_y")
	var started := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - started) < int(dur * 3000.0):
		await process_frame
		# 세 바퀴는 기존 검사들보다 훨씬 긴 시간이라, 탭 없는 새가 그새 바닥에
		# 닿아 죽는다 — 죽으면 홀드가 풀려서 루프와 무관한 이유로 FAIL 이
		# 난다. 매 프레임 제자리에 붙잡아 둔다.
		main.set("player_y", hold_y)
		main.set("player_vel", 0.0)
		var e: float = main.get("boost_burst_elapsed")
		if e < 0.0:
			break
		# 첫 바퀴의 점화 구간은 정상이므로 한 바퀴 지난 뒤부터 본다.
		if (Time.get_ticks_msec() - started) > int(dur * 1000.0):
			if e < sustain_start - 0.001:
				dipped_below = true
			if e > sustain_end + 0.001:
				ran_past = true
	_check("burst still burning while held", main.get("boost_burst_elapsed") >= 0.0, true)
	_check("loop never rewinds past the sustain", dipped_below, false)
	_check("loop never reaches the ember frame", ran_past, false)
	_check("still held after three cycles", main.get("boost_button_held"), true)
	main.call("_on_boost_released")
	await process_frame
	_check("release -> stopped", sfx.playing, false)
	_check("release -> not held", main.get("boost_button_held"), false)
	# 놓으면 스스로 꺼져야 한다. 루프 조건이 boost_button_held 를 잘못 읽으면
	# 여기서 영원히 타는 채로 남는다.
	await _settle(dur)
	_check("burst ends after release", main.get("boost_burst_elapsed"), -1.0)

	print("\n2. hidden mid-press (death / pause)")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	main.set("paused", true)
	for i in 3:
		await process_frame
	_check("hidden -> stopped", sfx.playing, false)
	_check("hidden -> not held", main.get("boost_button_held"), false)
	_check("hidden -> alpha back to idle", is_equal_approx(button.modulate.a, idle_alpha), true)

	print("\n2b. died mid-press")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	# 죽는 길은 일시정지와 다르다. 멈추지 않으므로 _update_fx 가 계속 돌고,
	# 버스트도 스스로 끝난다. Main 의 _update_fx 가 _update_playing 바깥에
	# 있는 이유가 이것이다.
	main.set("state", 4)  # State.GAMEOVER
	main.call("_apply_screen_visibility")
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	_check("game over -> not held", main.get("boost_button_held"), false)

	print("\n3. _reset_game")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	main.call("_reset_game")
	await process_frame
	_check("reset -> stopped", sfx.playing, false)

	if fails == 0:
		print("\nPASS — the hold releases cleanly on every path")
	else:
		print("\nFAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _settle(span: float) -> void:
	# 실제 시간으로 기다린다. 프레임 수로 세면 안 된다 — blend 는 move_toward
	# 로 delta 를 쌓아 내려가고, 헤드리스는 프레임이 훨씬 빨라 같은 프레임 수가
	# 훨씬 짧은 시간이 된다. 처음에 16프레임을 돌렸다가 blend 가 0.01 남아
	# FAIL 이 났다.
	await create_timer(span * 1.5 + 0.1).timeout


func _arm(main: Node2D) -> void:
	# 누르기 직전마다 판을 새로 깐다. 이 체커는 프레임을 실제로 돌리기 때문에,
	# 탭이 없는 새가 그새 떨어져 죽어 버린다 — 그러면 버튼이 숨으면서 방금
	# 시작한 소리가 곧바로 꺼져, 확인하려는 것과 무관한 이유로 FAIL 이 난다.
	# _reset_game 이 게이트를 비우고 새를 가운데로 되돌린다.
	main.call("_reset_game")
	main.set("state", 3)  # State.PLAYING
	main.set("paused", false)
	main.call("_apply_screen_visibility")
	await process_frame
