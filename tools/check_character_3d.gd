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
