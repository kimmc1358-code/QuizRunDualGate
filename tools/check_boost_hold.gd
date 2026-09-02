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
# 2번이 신호가 아니라 손으로 푸는 길이라, 여기가 조용히 어긋나기 쉽다.
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

	print("\n1. button_up")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	_check("press -> held", main.get("boost_button_held"), true)
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

	print("\n3. _reset_game")
	await _arm(main)
	main.call("_on_boost_pressed")
	await process_frame
	_check("press -> playing", sfx.playing, true)
	main.call("_reset_game")
	await process_frame
	_check("reset -> stopped", sfx.playing, false)

	if fails == 0:
		print("\nPASS — the hold releases cleanly on all three paths")
	else:
		print("\nFAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


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
