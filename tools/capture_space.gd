extends SceneTree
# Shoots the space game at each step of its cycle: an arrow question, a
# rock-paper-scissors question, the roulette with the asteroid field, the boss
# fight and fever.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 480x854 \
#       --script res://tools/capture_space.gd -- <out dir>
#
# It drives SpaceRun.tick by hand rather than waiting in real time, so the
# frames are the same on any PC. It plays real waves, so the save file is
# backed up and written back like the checkers do.
var m
var sp
var out := ""


func _init():
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_go.call_deferred()


func _shot(name: String) -> void:
	m.queue_redraw()
	if m.hud_canvas != null:
		m.hud_canvas.queue_redraw()
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name)


func _tick(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		sp.tick(dt, m.state == m.State.PLAYING, true)
		m._update_fx(dt)
		m._update_hearts(dt)
		if m.flash_time > 0.0:
			m.flash_time = maxf(0.0, m.flash_time - dt)
		if m.space_banner_elapsed >= 0.0:
			m.space_banner_elapsed += dt
			if m.space_banner_elapsed >= m.SPACE_BANNER_TIME:
				m.space_banner_elapsed = -1.0


func _fresh_wave(kind: int) -> Dictionary:
	for w in sp.waves:
		for p in w.planets:
			p.node.queue_free()
	sp.waves.clear()
	sp.spawn_wave(kind)
	return sp.upcoming_wave()


func _correct(w: Dictionary) -> Vector2:
	for p in w.planets:
		if p.correct:
			return p.pos
	return Vector2.ZERO


func _go():
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	var bak := FileAccess.get_file_as_bytes("user://savegame.cfg")
	await process_frame
	await process_frame
	m = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	sp = m.space
	m.call("_reset_game")
	m.call("_set_state", m.State.PLAYING)
	m.tutorial_active = false
	m.set_process(false)

	sp.cycle = 1                 # three planets, and red arrows possible
	var w := _fresh_wave(sp.Kind.ARROW)
	sp.ship_target = Vector2(0.3, -0.6)
	_tick(1.6)
	await _shot("space_1_arrow.png")

	w = _fresh_wave(sp.Kind.RPS)
	_tick(1.6)
	await _shot("space_2_rps.png")
	sp.ship_target = _correct(w)
	while not w.resolved:
		_tick(1.0 / 60.0)
	_tick(0.5)
	await _shot("space_3_roulette.png")
	_tick(1.2)
	await _shot("space_4_asteroids.png")

	sp.weapon = sp.Weapon.SPREAD
	sp.level = 6
	sp.drones = 1
	sp._sync_drones()
	sp._enter(sp.Phase.BOSS)
	sp.ship_target = Vector2(-0.6, -1.2)
	_tick(3.2)
	await _shot("space_5_boss.png")

	sp._enter(sp.Phase.FEVER)
	sp.ship_target = Vector2(0.4, 0.6)
	_tick(2.0)
	await _shot("space_6_fever.png")

	var f := FileAccess.open("user://savegame.cfg", FileAccess.WRITE)
	f.store_buffer(bak)
	f.close()
	quit()
