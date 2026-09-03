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
# 멈추지 않으므로 스스로 사그라들어야 한다.
#
# 알파도 같이 본다. 누를 때 트윈으로 진해지는데, 2번에서 알파만 되돌리고
# 트윈을 안 죽이면 살아남은 트윈이 다음 프레임에 도로 눌린 값으로 칠한다 —
# 실제로 그렇게 새 버튼이 눌린 채로 돌아온 적이 있다.
#
# 캐릭터 글로우(BOOST_GLOW_*)도 여기서 본다. boost_visual_blend 를 타므로
# 따로 정리할 것이 없어야 맞는데, "없어야 맞다"가 바로 조용히 어긋나는
# 조건이다. 세 길 모두에서 후광이 실제로 0 으로 내려가는지 확인한다.
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

	print("\n0. glow art and per-mode colours")
	_check("glow texture loaded", main.get("character_glow_texture") != null, true)
	var glow_colors: Array = main.get("MODE_BOOST_GLOW_COLOR")
	_check("one colour per mode", glow_colors.size(), 4)
	# 네 색이 서로 달라야 한다. 배열을 복사해 붙이다 한 줄이 중복되면 두 모드가
	# 같은 후광을 쓰게 되는데, 화면에서는 그 두 모드를 나란히 볼 일이 없어
	# 눈으로는 거의 잡히지 않는다.
	for i in range(glow_colors.size()):
		for j in range(i + 1, glow_colors.size()):
			if glow_colors[i] == glow_colors[j]:
				_check("mode %d and %d have different glow colours" % [i, j], false, true)
	_check("dark before any press", main.call("_boost_glow_alpha_and_scale").x, 0.0)

	print("\n0b. burst art, every mode")
	# 여섯 칸이 다 살아 있어야 한다. _slice_spritesheet 는 빈 칸을 버리므로,
	# 시트를 잘못 잘랐거나 한 칸이 비면 조용히 다섯 장짜리 애니메이션이 된다.
	for m in range(4):
		main.call("_apply_mode", m)
		_check("mode %d burst frames" % m, main.get("boost_burst_frames").size(), 6)
	main.call("_apply_mode", 0)
	_check("idle before any press", main.get("boost_burst_elapsed"), -1.0)

	print("\n1. button_up")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	_check("press -> held", main.get("boost_button_held"), true)
	_check("press -> glow lit", main.call("_boost_glow_alpha_and_scale").x > 0.0, true)
	_check("press -> burst playing", main.get("boost_burst_elapsed") >= 0.0, true)
	# 버스트는 홀드가 아니라 원샷이다. 버튼을 계속 누르고 있어도 스스로
	# 끝나야 하고, 그 뒤에도 -1 로 남아 있어야 한다.
	await _settle(main.get("boost_burst_duration"))
	_check("burst ends while still held", main.get("boost_burst_elapsed"), -1.0)
	_check("still held after the burst", main.get("boost_button_held"), true)
	main.call("_on_boost_released")
	await process_frame
	_check("release -> stopped", sfx.playing, false)
	_check("release -> not held", main.get("boost_button_held"), false)
	# 알파와 달리 후광은 트윈이 아니라 blend 를 타고 사그라든다. 그래서 놓은
	# 직후가 아니라 BOOST_VISUAL_BLEND_OUT 이 지난 뒤에 본다.
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	_check("release -> glow dark", main.call("_boost_glow_alpha_and_scale").x, 0.0)

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
	# 여기서 후광이 아직 켜져 있는 것이 맞다. _update_fx 는 `if not paused` 안에
	# 있어서 멈춘 화면에서는 blend 도 멈춘다 — 세상이 정지한 채 후광만 사그라
	# 들면 그게 더 이상하다. 확인할 것은 홀드가 풀렸다는 것(위에서 봤다)과,
	# 다시 풀렸을 때 남은 것 없이 빠진다는 것이다.
	main.set("paused", false)
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	_check("unpaused -> glow dark", main.call("_boost_glow_alpha_and_scale").x, 0.0)

	print("\n2b. died mid-press")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> glow lit", main.call("_boost_glow_alpha_and_scale").x > 0.0, true)
	# 죽는 길은 일시정지와 다르다. 멈추지 않으므로 _update_fx 가 계속 돌고,
	# 후광은 스스로 사그라들어야 한다. Main 의 _update_fx 가 _update_playing
	# 바깥에 있는 이유가 이것이다.
	main.set("state", 4)  # State.GAMEOVER
	main.call("_apply_screen_visibility")
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	_check("game over -> not held", main.get("boost_button_held"), false)
	_check("game over -> glow dark", main.call("_boost_glow_alpha_and_scale").x, 0.0)

	print("\n3. _reset_game")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	main.call("_reset_game")
	await process_frame
	_check("reset -> stopped", sfx.playing, false)
	await _settle(main.get("BOOST_VISUAL_BLEND_OUT"))
	_check("reset -> glow dark", main.call("_boost_glow_alpha_and_scale").x, 0.0)

	if fails == 0:
		print("\nPASS — the hold and its glow release cleanly on every path")
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
