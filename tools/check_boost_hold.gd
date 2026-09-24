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
# 부스트 잔상(BOOST_AFTERIMAGE_*)도 여기서 본다. 소리와 같은 수명을 살아야
# 하므로 — 누르면 쌓이고, 누르는 동안 유지되고, 놓으면 사라진다 — 홀드가
# 끈적해지는 것과 똑같은 방식으로 잔상도 화면에 눌어붙을 수 있다.
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

	# 누르는 순간의 악센트는 별도 플레이어이고, 이쪽은 반대로 절대 루프면
	# 안 된다. 위의 _enable_stream_loop 를 복사해 붙이기 딱 좋은 자리라
	# 명시적으로 본다 — 걸리면 점화음이 홀드 내내 겹쳐 울린다.
	var start_sfx: AudioStreamPlayer = main.get("fx_sound_boost_start")
	_check("one-shot is a separate player", start_sfx != sfx, true)
	_check("one-shot stream loaded", start_sfx.stream != null, true)
	if start_sfx.stream is AudioStreamWAV:
		_check("one-shot is NOT looped", start_sfx.stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	# 그리고 홀드보다 짧아야 악센트다. 같은 길이면 두 소리가 통째로 겹친다.
	_check("one-shot is shorter than the loop", start_sfx.stream.get_length() < sfx.stream.get_length(), true)
	# 볼륨이 실제로 플레이어까지 갔는가. @export 를 추가해 놓고 _boot_load 에서
	# 적용하는 줄을 빠뜨리면, 인스펙터에서는 값이 보이는데 소리는 그대로다 —
	# 눈으로는 절대 안 잡히는 종류의 어긋남이다.
	_check("one-shot volume applied", is_equal_approx(start_sfx.volume_db, main.get("boost_start_volume_db")), true)
	# 그리고 그 값이 클리핑으로 넘어가면 안 된다. 이 클립의 피크가 -5.1 dBFS
	# 라 헤드룸이 5.1 dB 뿐이고, 홀드음(-5.0)과 겹쳐 울리므로 합은 그보다 먼저
	# 찬다. 더 크게 하고 싶으면 홀드음을 낮추는 쪽이다.
	if start_sfx.volume_db > 5.0:
		_check("one-shot volume stays under the clip's 5.1 dB headroom", start_sfx.volume_db, 5.0)

	print("\n0. afterimage")
	# 잔상은 소리와 같은 수명을 살아야 한다 — 누르면 쌓이고, 누르는 동안 유지되고,
	# 놓으면 사라진다. 여기 있는 이유가 그것이다: 홀드가 끈적해지는 것과 똑같은
	# 방식으로 잔상도 화면에 눌어붙을 수 있고, 눌어붙으면 캐릭터가 여러 마리로
	# 보인다.
	var count_cap: int = main.get("BOOST_AFTERIMAGE_COUNT")
	await _arm(main)
	_check("idle before any press", main.get("boost_afterimages").size(), 0)
	main.call("_on_boost_pressed")
	# 블렌드가 올라오고 표본이 쌓일 만큼은 돌린다.
	var hold_y: float = main.get("player_y")
	var grew := Time.get_ticks_msec()
	var over_cap := false
	while (Time.get_ticks_msec() - grew) < 500:
		await process_frame
		# 탭이 없는 새는 그새 떨어져 죽고, 죽으면 홀드가 풀려 잔상과 무관한
		# 이유로 비워진다. 제자리에 붙잡아 둔다.
		main.set("player_y", hold_y)
		main.set("player_vel", 0.0)
		if main.get("boost_afterimages").size() > count_cap:
			over_cap = true
	var ghosts: Array = main.get("boost_afterimages")
	_check("held -> afterimages stacked", ghosts.size(), count_cap)
	# 한도를 넘지 않아야 한다. 기록은 while 루프가 하므로, 자르는 줄이 빠지면
	# 배열이 프레임마다 자라 결국 화면이 캐릭터로 덮인다.
	_check("never past the cap", over_cap, false)
	# 캐릭터 자기 그림이어야 한다. 잔상의 값어치가 거기에 있고(모드마다 그림을
	# 따로 그릴 필요가 없다), 엉뚱한 텍스처가 들어가면 그 전제가 깨진다.
	var flap: Array = main.get("flap_frames")
	var own_art := true
	for g in ghosts:
		if not flap.has(g["texture"]) and g["texture"] != main.get("happy_face_texture"):
			own_art = false
	_check("ghosts carry the character's own art", own_art, true)
	# 세로는 진짜 기록이다 — 캐릭터를 옮기면 다음에 찍히는 장이 그 자리를 들고
	# 와야 한다. 이게 깨지면 잔상이 몸에서 떨어져 나간다.
	main.set("player_y", hold_y + 60.0)
	var moved := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - moved) < 120:
		await process_frame
		main.set("player_y", hold_y + 60.0)
		main.set("player_vel", 0.0)
	var newest: Dictionary = main.get("boost_afterimages")[0]
	_check("newest ghost follows the character in y",
			absf(float(newest["y"]) - (hold_y + 60.0)) < 2.0, true)
	main.set("player_y", hold_y)
	main.call("_on_boost_released")
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	# 놓으면 비워져야 한다. 알파가 blend 를 곱하므로 화면에서는 이미 사라진
	# 뒤지만, 배열에 남아 있으면 다음 누름에서 옛날 자리가 한 프레임 번쩍인다.
	_check("release -> cleared", main.get("boost_afterimages").size(), 0)

	print("\n1. button_up")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	_check("press -> held", main.get("boost_button_held"), true)
	_check("press -> one-shot fired", start_sfx.playing, true)
	for i in 12:
		await process_frame
	# 그리고 누르고 있는 동안 계속 눌린 채여야 한다. 0.9초는 blend 가 끝까지
	# 올라가고도 남는 시간이고, 탭 없는 새가 죽지 않도록 제자리에 붙잡아 둔다.
	var held_y: float = main.get("player_y")
	var held_from := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - held_from) < 900:
		await process_frame
		main.set("player_y", held_y)
		main.set("player_vel", 0.0)
	_check("still held after a long press", main.get("boost_button_held"), true)
	main.call("_on_boost_released")
	await process_frame
	_check("release -> stopped", sfx.playing, false)
	_check("release -> not held", main.get("boost_button_held"), false)

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
	# 잔상도 스스로 사라진다. Main 의 _update_fx 가 _update_playing 바깥에
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

	await _check_pop_cues(main)

	if fails == 0:
		print("\nPASS — the hold releases cleanly on every path")
	else:
		print("\nFAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


# 게이트를 지날 때 뜨는 BOOST! / TURBO! 팝업의 소리.
#
# 등급을 정하는 bool 하나가 글자와 소리를 함께 고른다는 것이 이 코드의 주장인데,
# 어긋나도 화면은 멀쩡하다 — TURBO 라고 쓰인 팝업 밑에서 BOOST 소리가 날 뿐이고,
# 두 소리를 나란히 들어 본 사람만 안다. 그래서 글자와 울린 플레이어를 같은
# 호출에서 함께 본다.
#
# 홀드음(boost.wav)·점화음(boost_start.wav)과도 다른 파일이어야 한다. 넷이
# 같은 "부스트" 라는 말을 쓰고 있어서 한 파일로 합쳐지기 쉬운데, 버튼을 누른
# 사건과 게이트를 지난 사건은 서로 겹쳐 나므로 같은 소리면 구별이 안 된다.
func _check_pop_cues(main: Node2D) -> void:
	print("")
	print("BOOST! / TURBO! 팝업 소리")
	var mid: AudioStreamPlayer = main.get("fx_sound_boost_pop_mid")
	var best: AudioStreamPlayer = main.get("fx_sound_boost_pop_best")
	_check("BOOST! cue loaded", mid != null and mid.stream != null, true)
	_check("TURBO! cue loaded", best != null and best.stream != null, true)
	if mid == null or best == null:
		return
	_check("the two are different files", mid.stream != best.stream, true)
	_check("not the hold loop", mid.stream != main.get("fx_sound_boost").stream, true)
	_check("not the press one-shot", best.stream != main.get("fx_sound_boost_start").stream, true)
	_check("BOOST! on the SFX bus", mid.bus, "SFX")
	_check("TURBO! on the SFX bus", best.bus, "SFX")

	# 두 등급을 실제로 띄워 보고, 글자와 울린 쪽이 맞는지 본다. 임계값은
	# 게임에서 읽어 온다 — 여기 숫자를 적어 두면 임계값이 움직여도 통과한다.
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var mid_at: float = float(main.get("boost_bonus_mid_threshold"))
	var best_at: float = float(main.get("boost_bonus_best_threshold"))
	for case in [["BOOST!", mid_at, mid, best], ["TURBO!", best_at, best, mid]]:
		mid.stop()
		best.stop()
		await process_frame
		main.call("_spawn_boost_pop", 600, float(case[1]), view)
		await process_frame
		var text: String = str(main.get("boost_pop_text"))
		var want: AudioStreamPlayer = case[2]
		var other: AudioStreamPlayer = case[3]
		_check("%s bar leaves %s on screen" % [str(case[0]), str(case[0])],
			text.begins_with(str(case[0])), true)
		_check("%s cue plays" % str(case[0]), want.playing, true)
		_check("%s leaves the other silent" % str(case[0]), other.playing, false)
	mid.stop()
	best.stop()


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
