extends SceneTree

# 3D 캐릭터(2.0)가 정말 3D 로 그려지는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_character_3d.gd
#
# 화면 캡처로는 가릴 수 없다 — 3D 화면과 같은 자리에서 찍은 스프라이트가 똑같이
# 생겼기 때문이다. 그래서 게임이 실제로 어느 길로 그리는지를 본다.
#
#   1. JUNGLE 에서는 캐릭터용 SubViewport 가 하나 있고, 그리는 텍스처가 그
#      화면이다(스프라이트가 아니다).
#   2. 모델에 "flap", "happy", "sad" 세 애니메이션이 있고, flap 은 반복한다.
#      Blender 5 에서 내보내기 방식을 잘못 고르면 애니메이션이 하나도 안
#      나가는데, 그래도 모델은 멀쩡히 서 있어서 눈으로는 "날갯짓을 안 한다"
#      뿐이다.
#   3. 자세가 게임 상태를 따라간다: 평소 flap, 통과 직후 happy, 게임오버 sad,
#      다시 평소로 돌아오면 flap.
#   4. 3D 모델이 없는 모드(SKY)로 가면 SubViewport 가 없어지고 스프라이트를
#      그리며, JUNGLE 로 돌아와도 SubViewport 는 하나뿐이다(쌓이지 않는다).

var _fail := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _viewports(m: Node) -> int:
	var n := 0
	for c in m.get_children():
		if c is SubViewport and c.name.begins_with("Character3D"):
			n += 1
	return n


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	print("check_character_3d")

	m.call("_apply_mode", m.Mode.JUNGLE)
	await process_frame
	# ---- 1 ----
	_check(m.char3d_viewport != null and _viewports(m) == 1, "JUNGLE has one character SubViewport")
	var frame: Dictionary = m.call("_bird_draw_frame")
	_check(frame.texture is ViewportTexture, "the character is drawn from that SubViewport, not a sprite")
	# ---- 1b. 카툰 셰이더 ----
	if m.CHAR3D_TOON:
		var meshes: Array = m.char3d_viewport.find_children("*", "MeshInstance3D", true, false)
		var toon_ok := not meshes.is_empty()
		for mi: MeshInstance3D in meshes:
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(s) as ShaderMaterial
				toon_ok = toon_ok and mat != null \
					and mat.shader.resource_path == m.CHAR3D_TOON_SHADER \
					and mat.get_shader_parameter("albedo_tex") is Texture2D \
					and mat.next_pass is ShaderMaterial \
					and mat.next_pass.shader.resource_path == m.CHAR3D_TOON_OUTLINE_SHADER
		_check(toon_ok, "every surface wears the toon material, keeps its texture, and has the outline pass")
	# ---- 2 ----
	var ap: AnimationPlayer = m.char3d_anim
	_check(ap != null, "the model has an AnimationPlayer")
	if ap != null:
		var names := ap.get_animation_list()
		_check("flap" in names and "happy" in names and "sad" in names,
			"it carries flap, happy and sad (%s)" % ", ".join(names))
		if ap.has_animation("flap"):
			_check(ap.get_animation("flap").loop_mode == Animation.LOOP_LINEAR, "flap loops")
	# ---- 3 ----
	m.state = m.State.PLAYING
	m.happy_flap_elapsed = -1.0
	m.call("_update_character_3d")
	_check(m.char3d_pose == "flap" and ap != null and ap.current_animation == "flap", "flying plays flap")
	m.happy_flap_elapsed = 0.0
	m.call("_update_character_3d")
	_check(m.char3d_pose == "happy", "right after a pass it plays happy")
	m.happy_flap_elapsed = -1.0
	m.call("_update_character_3d")
	_check(m.char3d_pose == "flap", "and goes back to flap")
	m.state = m.State.GAMEOVER
	m.call("_update_character_3d")
	_check(m.char3d_pose == "sad", "game over plays sad")
	# ---- 3b. 기울기와 배럴롤 ----
	# 축은 Main.gd 의 _update_character_3d_motion 주석대로: 위로 가면 x 회전이
	# 음수(고개를 든다), 가만히 있으면 옆모습(0)으로 돌아온다.
	var pv: Node3D = m.char3d_pivot
	_check(pv != null and m.char3d_viewport.is_ancestor_of(pv), "the model hangs from a pivot inside the viewport")
	if pv != null:
		m.state = m.State.PLAYING
		var dt := 1.0 / 60.0
		m.char3d_prev_y = m.player_y
		for k in 60:
			m.player_y -= 700.0 * dt
			m.call("_update_character_3d_motion", dt)
		var up_pitch := pv.rotation.x
		_check(up_pitch < -deg_to_rad(10.0) and up_pitch >= -deg_to_rad(m.CHAR3D_PITCH_MAX_DEG) - 0.001,
			"climbing lifts the nose, no further than CHAR3D_PITCH_MAX_DEG (%.1f deg)" % rad_to_deg(up_pitch))
		for k in 60:
			m.player_y += 700.0 * dt
			m.call("_update_character_3d_motion", dt)
		_check(pv.rotation.x > deg_to_rad(10.0), "diving lowers it (%.1f deg)" % rad_to_deg(pv.rotation.x))
		for k in 120:
			m.call("_update_character_3d_motion", dt)
		_check(pv.rotation.length() < deg_to_rad(1.0), "holding still settles back to the side profile")
		# 부스트 버튼을 실제로 누르지는 않는다 — 효과음이 재생 중인 채 quit 하면
		# 종료 때 가끔 누수 경고가 난다. 누름이 롤을 부르는지는 아래에서 소스로 본다.
		m.call("_char3d_start_roll")
		_check(m.char3d_roll_t >= 0.0, "_char3d_start_roll starts a barrel roll")
		var max_roll := 0.0
		var t := 0.0
		while m.char3d_roll_t >= 0.0 and t < 2.0:
			m.call("_update_character_3d_motion", dt)
			max_roll = maxf(max_roll, pv.rotation.z)
			t += dt
		_check(max_roll > PI and pv.rotation.length() < deg_to_rad(1.0),
			"the roll goes all the way round and lands level (%.2f s)" % t)
		_check(absf(t - m.CHAR3D_ROLL_TIME) < 0.05, "and takes CHAR3D_ROLL_TIME")
		var src: String = FileAccess.get_file_as_string("res://scripts/Main.gd")
		for fn in ["_play_gate_success_fx", "_on_boost_pressed"]:
			var at := src.find("func %s(" % fn)
			var hit := src.find("_char3d_start_roll()", at)
			_check(at >= 0 and hit >= 0 and hit < src.find("\nfunc ", at + 5),
				"%s starts the roll" % fn)
	m.state = m.State.MODE_SELECT
	# ---- 4 ----
	m.call("_apply_mode", m.Mode.SKY)
	await process_frame
	frame = m.call("_bird_draw_frame")
	_check(m.char3d_viewport == null and _viewports(m) == 0 and not (frame.texture is ViewportTexture),
		"SKY has no 3D model, so it draws its sprite and the SubViewport is gone")
	m.call("_apply_mode", m.Mode.JUNGLE)
	m.call("_apply_mode", m.Mode.JUNGLE)
	await process_frame
	_check(_viewports(m) == 1, "switching back and forth leaves exactly one SubViewport")

	print("check_character_3d: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
